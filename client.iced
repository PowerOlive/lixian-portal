
path = require 'path'
fs = require 'fs'
mkdirp = require 'mkdirp'
request = require 'request'
StatusBar = require 'status-bar'

Lixian = require 'node-lixian'
lixian = new Lixian()

exports.stats = stats = 
  task: null
  retrieving: null
  error: {}
  speed: 'NaN'
  tasks: []
  requireLogin: false
  requireVerificationCode: false
  password: ''
  username: ''

exports.queue = queue = []
exports.log = log = []

cwd = process.env.LIXIAN_PORTAL_HOME || process.cwd()

retrieves = []

exports.startCron = ->
  while true
    if retrieve = retrieves.shift()
      await queue.execute 'retrieve', retrieve.task, retrieve.file, defer e
      stats.retrieving = null
    await setTimeout defer(), 100

exports.init = (cb)->
  await lixian.init {}, defer e
  return cb e if e
  await fs.readFile (path.join cwd, '.lixian-portal.username'), 'utf8', defer e, username
  await fs.readFile (path.join cwd, '.lixian-portal.password'), 'utf8', defer e, password
  if username && password
    console.log '正在尝试自动登录...'  
    await queue.execute 'login', username, password, defer e
    if e
      console.error e.message
    else
      console.log '自动登录成功.'
  cb null

stats.executings = []
queue.execute = (command, args..., cb)=>
  commands = 
    retrieve: (task, file)-> "取回文件 #{task.name}/#{file.name}"
    deleteTask: (id)-> "删除任务 #{id}"
    updateTasklist: -> "刷新任务列表"
    addTask: (url)-> "添加任务 #{url}"
    addBtTask: (filename, torrent)-> "添加 BT 任务 #{filename}"
    login: (username, password)-> "以 #{username} 登录"
    logout: -> "登出"
  command_name = commands[command] args...
  log.unshift  "#{command_name} 启动"
  console.log log[0]
  stats.executings.push command_name
  await queue.tasks[command] args..., defer e, results...
  stats.executings.splice (stats.executings.indexOf command_name), 1
  if e
    if e.message.match /you must login first/i
      stats.requireLogin = true
    log.unshift e.message
    console.log log[0]
    log.unshift "#{command_name} 失败"
    console.log log[0]
  else
    log.unshift "#{command_name} 完成"
    console.log log[0]
  cb e, results...




queue.tasks = 
  retrieve: (task, file, cb)->
    await mkdirp (path.join cwd, task.name), defer e
    return cb e if e
    req = request
      url: file.url
      headers:
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
        'Cookie': stats.cookie
        'Referer': 'http://dynamic.cloud.vip.xunlei.com/user_task'
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/37.0.2062.124 Safari/537.36'
        'Accept-Language': 'zh-CN,zh;q=0.8,it-IT;q=0.6,it;q=0.4,en-US;q=0.2,en;q=0.2'
      proxy: process.env['http_proxy']
    writer = fs.createWriteStream path.join cwd, task.name, file.name
    await req.on 'response', defer res
    fileSize = Number res.headers['content-length']
    return cb new Error "Invalid Content-Length" if isNaN fileSize
    statusBar = StatusBar.create total: fileSize
    statusBar.on 'render', (progress)->
      stats.retrieving = 
        req: req
        progress: progress 
        task: task
        file: file
        format: statusBar.format
    req.pipe statusBar
    req.pipe writer
    await writer.on 'close', defer()
    statusBar.cancel()

    await queue.execute 'deleteTask', task.id, defer e
    
    cb()
  
  updateTasklist: (cb)->
    await lixian.list {}, defer e, data
    return cb e if e
    stats.cookie = data.cookie
    stats.tasks = data.tasks
    for task in stats.tasks
      for file in task.files
        file.status = 'warning'
        file.statusLabel = '未就绪'
        if file.url
          file.status = 'success'
          file.statusLabel = '就绪'
          unless retrieves.filter((r)-> r.task.id == task.id && r.file.name == file.name).length
            retrieves.push
              task: task
              file: file
    cb()
  deleteTask: (id, cb)->
    if stats.retrieving?.task.id == id
      stats.retrieving.req.abort()
    retrieves = retrieves.filter (retrieve)-> retrieve.task.id != id

    await lixian.delete_task delete: id, defer e
    return cb e if e
    await queue.execute 'updateTasklist', defer e
    return cb e if e
    cb null

  login: (username, password, cb)->
    await lixian.login username: username, password: password, defer e
    return cb e if e
    await queue.execute 'updateTasklist', defer e
    return cb e if e
    await fs.writeFile (path.join cwd, '.lixian-portal.username'), username, 'utf8', defer e
    await fs.writeFile (path.join cwd, '.lixian-portal.password'), password, 'utf8', defer e
    stats.requireLogin = false
    cb null
    
        
  logout: (cb)->
    await fs.unlink (path.join cwd, '.lixian-portal.username'), defer e
    await fs.unlink (path.join cwd, '.lixian-portal.password'), defer e
    stats.requireLogin = true
    cb null

  addBtTask: (filename, torrent, cb)->
    await lixian.add_torrent torrent: torrent, defer e
    return cb e if e
    await queue.execute 'updateTasklist', defer e
    return cb e if e
    cb null
  addTask: (url, cb)->
    await lixian.add_url url: url, defer e
    return cb e if e
    await queue.execute 'updateTasklist', defer e
    return cb e if e
    cb null


