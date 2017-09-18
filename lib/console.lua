--
-- Created by IntelliJ IDEA.
-- User: 小强
-- Date: 2017/9/15
-- Time: 22:46
-- To change this template use File | Settings | File Templates.
--
require "sys"
module(..., package.seeall)
local uart = require "uart"

local uart_id
local console_task

local function read_line()
    while true do
        local s = uart.read(uart_id, "*l")
        if s ~= "" then
            return s
        end
        coroutine.yield()
    end
end

local function write(s)
    uart.write(uart_id, s)
end

local function main_loop()
    local cache_data = ""
    
    -- 定义执行环境，命令行下输入的脚本的print重写到命令行的write
    local execute_env = {
        print = function(...)
            for i = 1, #arg do
                arg[i] = tostring(arg[i])
            end
            write(table.concat(arg, "\t"))
            write("\r\n")
        end,
    }
    setmetatable(execute_env, {__index = _G})
    
    -- 输出提示语
    write("\r\nWelcome to Luat Console\r\n")
    write("---------------------------------------------------------------\r\n> ")
    
    while true do
        -- 读取输入
        local new_data = read_line("*l")
        -- 输出回显
        write(new_data)
        -- 拼接之前未成行的剩余数据
        cache_data = cache_data .. new_data
        -- 去掉回车换行
        local line = string.match(cache_data, "(.+)\r\n*")
        ---[[调试输入参数部分,不需要时用--即可注释本段
        write("\n")
        if line == nil then
            write("console.lua_60 line value is nothing")
        elseif line == "" then
            write("console.lua_62 line value null")
        else
            write("console.lua_64 line value :" .. line .."\n")
            write("console.lua_65 line type :" .. (type(line)))
        end
        write("\n")
        --]]
        if line then
            -- 收到一整行的数据 清除缓冲数据
            cache_data = ""
            -- 输出新行
            write("\n")
            -- 用xpcall执行用户输入的脚本，可以捕捉脚本的错误
            xpcall(function()
                    -- 执行用户输入的脚本
                    f = assert(loadstring(line))
                    setfenv(f, execute_env)
                    f()
            end,
            function()-- 错误输出
                write(debug.traceback())
            end)
            -- 输出输入提示符
            write("\r\n> ")
        end
    end
end

function setup(id, baudrate)
    -- 默认串口1
    uart_id = id or 1
    -- 默认波特率115200
    baudrate = baudrate or 115200
    -- 创建console处理的协程
    console_task = coroutine.create(main_loop)
    -- 初始化串口
    uart.setup(uart_id, baudrate, 8, uart.PAR_NONE, uart.STOP_1)
    -- 串口收到数据时唤醒console协程
    sys.regUartReceive(uart_id, function()
        coroutine.resume(console_task)
    end)
    coroutine.resume(console_task)
end
