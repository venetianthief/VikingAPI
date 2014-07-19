_            = require('underscore')
path         = require('path')
cs           = require('calmsoul')
fs           = require('fs')
github       = require('octonode')
yaml         = require('js-yaml')
WatchJS      = require("watchjs")
watch        = WatchJS.watch
unwatch      = WatchJS.unwatch
callWatchers = WatchJS.callWatchers
EventEmitter = require('events').EventEmitter
VM           = require('./version-manager.coffee')

# this is a generic token
# 894b9db89f78b7142263966c69cabf63cec31a19
# d34475bc0818fbc70158f0aca9a488523a6d4470
# Nimmock: 96234b48504bcb43a1d0a9e11cd7e596b45f4e54
# Mormur: 16cd039c3347e9689bf2e7d3eccdcfb627bec2fc
# fasma: 3fe23a32720c1d08a38dc488c3e5128ea809fdaa
keys = [
  "894b9db89f78b7142263966c69cabf63cec31a19"
  "96234b48504bcb43a1d0a9e11cd7e596b45f4e54"
  "16cd039c3347e9689bf2e7d3eccdcfb627bec2fc"
  "3fe23a32720c1d08a38dc488c3e5128ea809fdaa"]

getKey = -> return keys[Math.floor(Math.random() * keys.length + 1)]

client   = github.client(getKey())
basePath = path.join(__dirname, '..')

class Github extends EventEmitter

  blacklist: [
    "AddonDownloader"
    "vikinghug.com"
    "VikingBuddies"
    "VikingDocs"
    "VikingWarriorResource"
    "VikingStalkerResource"
    "vikingcli"
    "VikingAPI"
  ]

  whitelist: []

  repos: []
  owner: null

  constructor: (owner) ->
    cs.info '\n\n@@Github::constructor ->'
    @whitelist = @getDataFile('repos')
    console.log "@whitelist: ", @whitelist
    @owner = owner
    @getRepos()
    setInterval =>
      @getRepos()
    , 16000

  getDataFile: (file) ->
    try
      filepath = path.join(basePath, 'data', file + '.yaml')
      doc = yaml.safeLoad(fs.readFileSync(filepath, 'utf8'))
    catch err
      console.log(err)

  setRepos: (repos) -> @repos = repos

  findRepo: (_repo) ->
    return null if @repos.length == 0

    for repo, i in @repos
      if _repo.id == repo.id or _repo.name == repo.name
        return i
    return null

  getRepos: ->
    console.log "getRepos: ->"
    org = client.org(@owner)
    self = this
    org.repos (err, array, headers) =>
      if err && err.statusCode == 403
        client = github.client(getKey())
        self.getRepos()
        console.log "github::getRepos: ERROR: 403"
        return
      else console.log "github::getRepos: SUCCESS"
      array = @filterForBlacklist(array)

      for repo, i in array
        @initRepo(repo, i)

      @sort(@repos)

  setUpdated: (payload, updated, tooltip) ->
    payload.tooltip = tooltip
    payload.recent_update = updated

  setVersion: (payload, version) ->
    payload.version = version

  initRepo: (repo, i) ->
    payload =
      id                : repo.id
      owner             : repo.owner.login
      name              : repo.name
      git_url           : repo.git_url
      html_url          : repo.html_url
      issues_url        : "#{repo.html_url}/issues"
      open_issues_count : repo.open_issues_count
      pushed_at         : repo.pushed_at
      recent_update     : false
      tooltip           : null
      version           : null

    @checkForRecentUpdate(payload, @setUpdated.bind(payload))
    @getAddonVersion(payload, @setVersion.bind(payload))

    index = @findRepo(repo)
    if index?
      @repos[index] = payload
    else
      @repos.push(payload)


    self = @
    watch payload, "recent_update", (key, command, data) ->
      self.emit("UPDATE", this)
    @emit("UPDATE", payload)

  checkForRecentUpdate: (payload, callback) ->
    try
      repo = client.repo("#{@owner}/#{payload.name}")
      repo.commit 'master', (err, data, headers) =>
        past  = new Date(data.commit.author.date).getTime()
        now   = new Date().getTime()
        delta = Math.abs(now - past) / 1000
        callback(payload, Math.floor(delta / 3600) < 12, data.commit.message)
    catch err
      console.log err

  getAddonVersion: (payload, callback) ->
    repo = client.repo("#{@owner}/#{payload.name}")
    repo.contents 'toc.xml', (err, data, headers) =>
      try
        version = VM.getVersion(data.content) if data? and data.content?
        callback(payload, version)
      catch err
        console.log err
      # callback


  filterForBlacklist: (array) ->
    self = this
    return array.filter (repo) ->
      n = 0
      self.blacklist.map (name) => n += (repo.name == name)
      return repo if n == 0

  sort: (repos) ->
    repos.sort (a,b) ->
      aStr = a.name.toLowerCase()
      bStr = b.name.toLowerCase()
      if (aStr > bStr)
        return 1
      else if (bStr > aStr)
        return -1
      else
        return 0

  runCommand: (command, data) ->
    repo = client.repo("#{data.owner}/#{data.name}")
    repo[command] (err, response, headers) =>
      data[command] = response



module.exports = Github
