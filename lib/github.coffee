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
    "VikingAPI"
    "VikingBuddies"
    "vikingcli"
    "VikingDatachron"
    "VikingDocs"
    "vikinghug.com"
    "VikingRaidFrame"
    "VikingSet"
    "VikingStalkerResource"
    "VikingWarriorResource"
  ]

  whitelist: []

  repos: []
  owner: null

  constructor: (owner) ->
    cs.info '\n\n@@Github::constructor ->'
    @whitelist = @getDataFile('repos')
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
      cs.debug(err)

  setRepos: (repos) -> @repos = repos

  findRepo: (_repo) ->
    return null if @repos.length == 0

    for repo, i in @repos
      if _repo.id == repo.id or _repo.name == repo.name
        return i
    return null

  getRepos: ->
    cs.debug "getRepos: ->"
    org = client.org(@owner)
    self = this
    org.repos (err, array, headers) =>
      if err && err.statusCode == 403
        client = github.client(getKey())
        self.getRepos()
        cs.debug "github::getRepos: ERROR: 403"
        return
      else cs.debug "github::getRepos: SUCCESS"
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
      ssh_url           : repo.ssh_url
      issues_url        : "#{repo.html_url}/issues"
      branches          : null
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

    @runCommand("branches", payload)

    self = @
    watch payload, (key, command, data) ->
      switch key
        when "branches"
          try
            for branch, i in data
              branch.html_url = "#{this.html_url}/tree/#{branch.name}"
              branch.download_url = "#{this.git_url}\##{branch.name}"
          catch err
            self.emit("MESSAGE:ADD", err.message)
        when "recent_update"
          self.emit("UPDATE", this)
      self.emit("UPDATE", payload)

  checkForRecentUpdate: (payload, callback) ->
    try
      repo = client.repo("#{@owner}/#{payload.name}")
      repo.commit 'master', (err, data, headers) =>
        if err && err.statusCode == 403
          client = github.client(getKey())
          self.checkForRecentUpdate(payload, callback)
          cs.debug "github::checkForRecentUpdate: ERROR: 403"
          return
        else cs.debug "github::checkForRecentUpdate: SUCCESS"
        past  = new Date(data.commit.author.date).getTime()
        now   = new Date().getTime()
        delta = Math.abs(now - past) / 1000
        callback(payload, Math.floor(delta / 3600) < 12, data.commit.message)
    catch err
      cs.debug err

  getAddonVersion: (payload, callback) ->
    repo = client.repo("#{@owner}/#{payload.name}")
    repo.contents 'toc.xml', (err, data, headers) =>
      if err && err.statusCode == 403
        client = github.client(getKey())
        self.getAddonVersion(payload, callback)
        cs.debug "github::getAddonVersion: ERROR: 403"
        return
      else cs.debug "github::getAddonVersion: SUCCESS"
      try
        version = VM.getVersion(data.content) if data? and data.content?
        callback(payload, version)
      catch err
        cs.debug err
      # callback


  filterForWhitelist: (array) ->
    self = this
    repos = array.filter (repo) ->
      n = 0
      self.blacklist.map (name) => n += (repo.name == name)
      return repo if n > 0

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
