--- 模块功能：luat协程调度框架
-- @module sys
-- @author 稀饭放姜 小强
-- @license MIT
-- @copyright openLuat.com
-- @release 2017.9.13
require "patch"
require "log"
local base = _G
local table = require "table"
local rtos = require "rtos"
local uart = require "uart"
local io = require "io"
local os = require "os"
local string = require "string"
module(..., package.seeall)

-- 加载常用的全局函数至本地
local print = base.print
local unpack = base.unpack
local ipairs = base.ipairs
local type = base.type
local pairs = base.pairs
local assert = base.assert
local tonumber = base.tonumber

-- lib脚本版本号，只要lib中的任何一个脚本做了修改，都需要更新此版本号
SCRIPT_LIB_VER = "2.0.0"
-- 脚本发布时的最新core软件版本号
CORE_MIN_VER = "Luat_V0009_8955"

-- TaskID最大值
local TASK_ID_MAX = 20
-- msgId 最大值(请勿修改否则会发生msgId碰撞的危险)
local MSG_ID_MAX = 0x7FFFFFFF

-- 任务定时器id
local taskId = 0
-- 消息定时器id
local msgId = TASK_ID_MAX
-- 定时器id表
local timerPool = {}
--消息定时器参数表
local para = {}


--工作模式
--SIMPLE_MODE：简单模式，默认不会开启“每一分钟产生一个内部消息”、“定时查询csq”、“定时查询ceng”的功能
--FULL_MODE：完整模式，默认会开启“每一分钟产生一个内部消息”、“定时查询csq”、“定时查询ceng”的功能
SIMPLE_MODE, FULL_MODE = 0, 1
--默认为完整模式
local workMode = FULL_MODE

--- 启动GSM协议栈。例如在充电开机未启动GSM协议栈状态下，如果用户长按键正常开机，此时调用此接口启动GSM协议栈即可
-- @return 无
-- @usage sys.powerOn()
function powerOn()
    rtos.poweron(1)
end

--- 软件重启
-- @string r 重启原因，用户自定义，一般是string类型，重启后的trace中会打印出此重启原因
-- @return 无
-- @usage sys.restart('程序超时软件重启')
function restart(r)
    assert(r and r ~= "", "sys.restart cause null")
    log.appendErr("restart[" .. r .. "];")
    rtos.restart()
end

--- 设置工作模式
-- @number v 工作模式，默认完整模式\
--SIMPLE_MODE：简单模式，默认不会开启“每一分钟产生一个内部消息”、“定时查询csq”、“定时查询ceng”的功能\
--FULL_MODE：完整模式，默认会开启“每一分钟产生一个内部消息”、“定时查询csq”、“定时查询ceng”的功能
-- @return Boole ,成功返回true，否则返回nil
-- @usage sys.setworkmode(FULL_MODE)
function setWorkMode(v)
    if workMode ~= v and (v == SIMPLE_MODE or v == FULL_MODE) then
        workMode = v
        --产生一个工作模式变化的内部消息"SYS_WORKMODE_IND"
        dispatch("SYS_WORKMODE_IND")
        return true
    end
end

--- 获取工作模式
-- @return number ,当前工作模式
-- @usage mode = sys.getWorkMode()
function getWorkMode()
    return workMode
end

--- 获取底层软件版本号
-- @return string ,版本号字符串
-- @usage coreVer = sys.getCorVer()
function getCoreVer()
    return rtos.get_version()
end

--- 开启或者关闭print的打印输出功能
-- @bool v：false或nil为关闭，其余为开启
-- @param uartid：输出Luatrace的端口：nil表示host口，1表示uart1,2表示uart2
-- @number baudrate：number类型，uartid不为nil时，此参数才有意义，表示波特率，默认115200 \
--支持1200,2400,4800,9600,14400,19200,28800,38400,57600,76800,115200,230400,460800,576000,921600,1152000,4000000
-- @return  无
-- @usage sys.openTrace(1,nil,921600)
function openTrace(v, uartid, baudrate)
    if uartid then
        if v then
            uart.setup(uartid, baudrate or 115200, 8, uart.PAR_NONE, uart.STOP_1)
        else
            uart.close(uartid)
        end
    end
    rtos.set_trace(v and 1 or 0, uartid)
end

--“除定时器消息、物理串口消息外的其他外部消息（例如AT命令的虚拟串口数据接收消息、音频消息、充电管理消息、按键消息等）”的处理函数表
local handlers = {}
base.setmetatable(handlers, {__index = function() return function() end end, })

--- 注册“除定时器消息、物理串口消息外的其他外部消息（例如AT命令的虚拟串口数据接收消息、音频消息、充电管理消息、按键消息等）”的处理函数
-- @number id 消息类型id
-- @param handler 消息处理函数
-- @return 无
-- @usage regmsg(rtos.MSG_KEYPAD,keymsg) -- keymsg() 是键盘处理函数
function regmsg(id, handler)
    handlers[id] = handler
end

--各个物理串口的数据接收处理函数表
local uartReceives = {}

--各个物理串口的数据发送完成通知函数表
local uartTransmitDones = {}

---注册物理串口的数据接收处理函数
-- @number id：物理串口号，1表示UART1，2表示UART2
-- @param  fnc：数据接收处理函数名
-- @return 无
-- @usage regUartReceive(uart.ATC,atc)
function regUartReceive(id, fnc)
    uartReceives[id] = fnc
end

--- 注册物理串口的数据发送完成处理函数
-- @number id：物理串口号，1表示UART1，2表示UART2
-- @param fnc：调用uart.write接口发送数据，数据发送完成后的回调函数
-- @return 无
-- @usage regUartTransmitDone(1,uart)
function regUartTransmitDone(id, fnc)
    uartTransmitDones[id] = fnc
end

--- Task任务延时函数，只能用于任务函数中
-- @number ms  整数，最大等待126322567毫秒
-- @return number 正常返回1，失败返回nil
-- @usage sys.wait(30)
function wait(ms)
    -- 参数检测，参数不能为负值
    assert(ms > 0, "The wait time cannot be negative!")
    -- 选一个未使用的定时器ID给该任务线程
    while true do
        -- 防止taskId超过30
        if taskId >= TASK_ID_MAX then taskId = 0 end
        taskId = taskId + 1
        if timerPool[taskId] == nil then
            timerPool[taskId] = coroutine.running()
            break
        end
    end
    -- 调用core的rtos定时器
    if 1 ~= rtos.timer_start(taskId, ms) then print("rtos.timer_start error") return end
    -- 挂起调用的任务线程
    coroutine.yield()
    return 1
end

--- 创建一个任务线程,在模块最末行调用该函数并注册模块中的任务函数，main.lua导入该模块即可
-- @param fun  任务函数名，用于resume唤醒时调用
-- @param ...  任务函数fun的可变参数
-- @return co  返回该任务的线程号
-- @usage sys.taskInit(task1,'a','b')
function taskInit(fun, ...)
    co = coroutine.create(fun)
    coroutine.resume(co, unpack(arg))
    return co
end

--- Luat平台初始化
-- @param mode 充电开机是否启动GSM协议栈，1不启动，否则启动
-- @param lprfnc 用户应用脚本中定义的“低电关机处理函数”，如果有函数名，则低电时，本文件中的run接口不会执行任何动作，否则，会延时1分钟自动关机
-- @return 无
-- @usage sys.init(1,0)
function init(mode, lprfnc)
    -- 用户应用脚本中必须定义PROJECT和VERSION两个全局变量，否则会死机重启，如何定义请参考各个demo中的main.lua
    assert(base.PROJECT and base.PROJECT ~= "" and base.VERSION and base.VERSION ~= "", "Undefine PROJECT or VERSION")
    base.collectgarbage("setpause", 80)
    
    -- 设置AT命令的虚拟串口
    uart.setup(uart.ATC, 0, 0, uart.PAR_NONE, uart.STOP_1)
    print("poweron reason:", rtos.poweron_reason(), base.PROJECT, base.VERSION, SCRIPT_LIB_VER, getCoreVer())
    if mode == 1 then
        -- 充电开机
        if rtos.poweron_reason() == rtos.POWERON_CHARGER then
            -- 关闭GSM协议栈
            rtos.poweron(0)
        end
    end
    -- 如果存在脚本运行错误文件，打开文件，打印错误信息
    local f = io.open("/luaerrinfo.txt", "r")
    if f then
        print(f:read("*a") or "")
        f:close()
    end
    -- 打印LIB_ERR_FILE文件中的错误信息
    log.initErr()
    log.checkCoreVer()
end

------------------------------------------ rtos消息回调处理部分 ------------------------------------------
--[[
函数名：cmpTable
功能  ：比较两个table的内容是否相同，注意：table中不能再包含table
参数  ：
t1：第一个table
t2：第二个table
返回值：相同返回true，否则false
]]
local function cmpTable(t1, t2)
    if not t2 then return #t1 == 0 end
    if #t1 == #t2 then
        for i = 1, #t1 do
            if unpack(t1, i, i) ~= unpack(t2, i, i) then
                return false
            end
        end
        return true
    end
    return false
end

--- 关闭定时器
-- @param val 值为number时，识别为定时器ID，值为回调函数时，需要传参数
-- @param ... val值为函数时，函数的可变参数
-- @return 无
-- @usage timer_stop(1)
function timer_stop(val, ...)
    -- val 为定时器ID
    if type(val) == 'number' then
        timerPool[val], para[val] = nil
        rtos.timer_stop(val)
    else
        for k, v in pairs(timerPool) do
            -- 回调函数相同
            if type(v) == 'table' and v.cb == val or v == val then
                -- 可变参数相同
                if cmpTable(arg, para[k]) then
                    rtos.timer_stop(k)
                    timerPool[k], para[k] = nil
                    break
                end
            end
        end
    end
end

--- 函数功能--开启一个定时器
-- @param fnc 定时器回调函数
-- @number ms 整数，最大定时126322567毫秒
-- @param ... 可变参数 fnc的参数
-- @return number 定时器ID，如果失败，返回nil
function timer_start(fnc, ms, ...)
    --回调函数和时长检测
    assert(fnc ~= nil, "sys.timer_start(first param) is nil !")
    assert(ms > 0, "sys.timer_start(Second parameter) is <= zero !")
    -- 关闭完全相同的定时器
    if arg.n == 0 then
        timer_stop(fnc)
    else
        timer_stop(fnc, unpack(arg))
    end
    -- 为定时器申请ID，ID值 1-20 留给任务，20-30留给消息专用定时器
    while true do
        if msgId >= MSG_ID_MAX then msgId = TASK_ID_MAX end
        msgId = msgId + 1
        if timerPool[msgId] == nil then
            timerPool[msgId] = fnc
            break
        end
    end
    --调用底层接口启动定时器
    if rtos.timer_start(msgId, ms) ~= 1 then print("rtos.timer_start error") return end
    --如果存在可变参数，在定时器参数表中保存参数
    if arg.n ~= 0 then
        para[msgId] = arg
    end
    --返回定时器id
    return msgId
end

------------------------------------------ app 注册处理部分 ------------------------------------------
--app应用表
local apps = {}
--内部消息队列
local queMsg = {}

--- 注册App，该类应用需要来自rtos或lua层的消息唤醒回调，用任务轮询处理不方便的时候使用。当你需要的时候你就知道为什么用它了。
-- @param ... 可变参数：以函数+参数...注册的方式，以table注册的方式
-- @return table ,返回app函数名，参数
-- @usage regapp(fncname,"MSG1","MSG2","MSG3") 注册形式为：{procer=arg[1],"MSG1","MSG2","MSG3"}
-- @usage regapp({MSG1=fnc1,MSG2=fnc2,MSG3=fnc3}) 注册形式为：形式为{MSG1=fnc1,MSG2=fnc2,MSG3=fnc3}
function regapp(...)
    local app = arg[1]
    --table方式
    if type(app) == "table" then
        --函数方式
        elseif type(app) == "function" then
        app = {procer = arg[1], unpack(arg, 2, arg.n)}
        else
            error("unknown app type " .. type(app), 2)
    end
    --产生一个增加app的内部消息
    dispatch("SYS_ADD_APP", app)
    return app
end

--- 解注册app
-- @param id：app的id，id共有两种方式，一种是函数名，另一种是table名
-- @return 无
-- @usage deregapp(app)
function deregapp(id)
    --产生一个移除app的内部消息
    dispatch("SYS_REMOVE_APP", id)
end


--[[
函数名：addapp
功能  ：增加app
参数  ：
app：某个app，有以下两种形式：
如果是以函数方式注册的app，例如regapp(fncname,"MSG1","MSG2","MSG3"),则形式为：{procer=arg[1],"MSG1","MSG2","MSG3"}
如果是以table方式注册的app，例如regapp({MSG1=fnc1,MSG2=fnc2,MSG3=fnc3}),则形式为{MSG1=fnc1,MSG2=fnc2,MSG3=fnc3}
返回值：无
]]
local function addapp(app)
    -- 插入尾部
    table.insert(apps, #apps + 1, app)
end

--[[
函数名：removeapp
功能  ：移除app
参数  ：
id：app的id，id共有两种方式，一种是函数名，另一种是table名
返回值：无
]]
local function removeapp(id)
    --遍历app表
    for k, v in ipairs(apps) do
        --app的id如果是函数名
        if type(id) == "function" then
            if v.procer == id then
                table.remove(apps, k)
                return
            end
        --app的id如果是table名
        elseif v == id then
            table.remove(apps, k)
            return
        end
    end
end

--- 产生内部消息，存储在内部消息队列中
-- @param ... 可变参数，用户自定义
-- @return 无
-- @usage dispatch(app)
function dispatch(...)
    table.insert(queMsg, arg)
end

--[[
函数名：getmsg
功能  ：读取内部消息
参数  ：无
返回值：内部消息队列中的第一个消息，不存在则返回nil
]]
local function getmsg()
    if #queMsg == 0 then
        return nil
    end
    return table.remove(queMsg, 1)
end

--[[
函数名：callapp
功能  ：处理内部消息
通过遍历每个app进行处理
参数  ：
msg：消息
返回值：无
]]
local function callapp(msg)
    local id = msg[1]
    --增加app消息
    if id == "SYS_ADD_APP" then
        addapp(unpack(msg, 2, #msg))
    --移除app消息
    elseif id == "SYS_REMOVE_APP" then
        removeapp(unpack(msg, 2, #msg))
    else
        local app
        --遍历app表
        for i = #apps, 1, -1 do
            app = apps[i]
            --函数注册方式的app,带消息id通知
            if app.procer then
                for _, v in ipairs(app) do
                    if v == id then
                        --如果消息的处理函数没有返回true，则此消息的生命期结束；否则一直遍历app
                        if app.procer(unpack(msg)) ~= true then
                            return
                        end
                    end
                end
            --table注册方式的app,不带消息id通知
            elseif app[id] then
                --如果消息的处理函数没有返回true，则此消息的生命期结束；否则一直遍历app
                if app[id](unpack(msg, 2, #msg)) ~= true then
                    return
                end
            end
        end
    end
end

--界面刷新内部消息
local refreshmsg = {"MMI_REFRESH_IND"}

--[[
函数名：runqmsg
功能  ：处理内部消息
参数  ：无
返回值：无
]]
local function runqmsg()
    local inmsg
    
    while true do
        --读取内部消息
        inmsg = getmsg()
        --内部消息为空
        if inmsg == nil then
            --需要刷新界面
            if refreshflag == true then
                refreshflag = false
                --产生一个界面刷新内部消息
                inmsg = refreshmsg
            else
                break
            end
        end
        --处理内部消息
        callapp(inmsg)
    end
end

------------------------------------------ Luat 主调度框架  ------------------------------------------
--- run()从底层获取core消息并及时处理相关消息，查询定时器并调度各注册成功的任务线程运行和挂起
-- @return 无
-- @usage sys.run()
function run()
    while true do
        --处理内部消息
        runqmsg()
        -- 阻塞读取外部消息
        msg, msgPara = rtos.receive(rtos.INF_TIMEOUT)
        -- 判断是否为定时器消息，并且消息是否注册
        if msg == rtos.MSG_TIMER and timerPool[msgPara] ~= nil then
            if msgPara < 21 then
                print("timerPool[msgPara] is task ----->", msgPara, timerPool[msgPara])
                -- 根据定时器表获得任务线程ID
                local co = timerPool[msgPara]
                -- 清除定时器ID值
                timerPool[msgPara] = nil
                -- 运行该线程
                coroutine.resume(co)
            else
                local cb = timerPool[msgPara]
                print("timerPool[msgPara] is msg ---->", msgPara, timerPool[msgPara])
                timerPool[msgPara] = nil
                print("sys.run msg --> cb", cb)
                if para[msgPara] ~= nil then
                    cb(unpack(para[msgPara]))
                else
                    cb()
                end
            end
        --串口数据接收消息
        elseif msg == rtos.MSG_UART_RXDATA then
            --AT命令的虚拟串口
            if msgPara == uart.ATC then
                handlers.atc()
            --物理串口
            else
                if uartReceives[msgPara] ~= nil then
                    uartReceives[msgPara]()
                else
                    handlers[msg](msg, msgPara)
                end
            end
        --串口发送数据完成消息
        elseif msg == rtos.MSG_UART_TX_DONE then
            if uartTransmitDones[msgPara] then
                uartTransmitDones[msgPara]()
            end
        --其他消息（音频消息、充电管理消息、按键消息等）
        else
            handlers[msg](msg, msgPara)
        end
    end
end
