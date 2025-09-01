{print} = require 'util'
{spawn, exec} = require 'child_process'
path = require 'path'

build = (callback) ->
    # 优先使用本地安装的coffeescript，然后是全局安装的
    coffeeCmd = null
    
    # 检查本地node_modules中的coffee
    localCoffee = path.join(__dirname, 'node_modules', '.bin', 'coffee')
    try
        require('fs').accessSync(localCoffee, require('fs').constants.F_OK)
        coffeeCmd = localCoffee
    catch
        # 使用全局coffee或npx
        coffeeCmd = 'npx coffee'
    
    console.log "Using coffee command: #{coffeeCmd}"
    
    # 使用exec而不是spawn，这样可以更好地处理路径
    exec "#{coffeeCmd} -c -o public src", (error, stdout, stderr) ->
        if stdout
            console.log stdout
        if stderr
            console.error stderr
        if error
            console.error "Build failed:", error
            process.exit(1)
        else
            console.log "Build completed successfully"
            callback?()

task 'build', 'Build ./public from src/', ->
    build()

