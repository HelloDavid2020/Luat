--- 数据链路激活、SOCKET管理(创建、连接、数据收发、状态维护)
-- @module link
-- @author 稀饭放姜、小强
-- @license MIT
-- @copyright openLuat.com
-- @release 2017.9.20
module(..., package.seeall)
-- 定义模块,导入依赖库
local base = _G
local string = require "string"
local table = require "table"
local sys = require "sys"
local ril = require "ril"
local net = require "net"
local rtos = require "rtos"
local sim = require "sim"
-- 加载常用的全局函数至本地
local print = base.print
local pairs = base.pairs
local tonumber = base.tonumber
local tostring = base.tostring

-- 最大socket id，从0开始，所以同时支持的socket连接数是8个
local MAXLINKS = 7
--IP环境建立失败时间隔5秒重连
local IPSTART_INTVL = 5000

-- socket连接表
local linkList = {}
-- ipStatus：IP环境状态
-- shuting：是否正在关闭数据网络
local ipStatus, shuting = "IP INITIAL"
-- GPRS数据网络附着状态，"1"附着，其余未附着
local cgatt
-- apn，用户名，密码
local apnname = "CMNET"
local username = ''
local password = ''
-- socket发起连接请求后，响应间隔超时策略："restart" or "reconn"
local reconnStrategy = "reconn"
-- socket发起连接请求后，响应间隔ms
local reconnInterval
-- apnflg：本功能模块是否自动获取apn信息，true是，false则由用户应用脚本自己调用setapn接口设置apn、用户名和密码
-- checkciicrtm, 执行AT+CIICR后，如果设置了checkciicrtm，checkciicrtm毫秒后，没有激活成功，则重启软件（中途执行AT+CIPSHUT则不再重启）
-- ciicrerrcb,用户自定义AT+CIIR激活超时自定义回调函数
-- flyMode：是否处于飞行模式
-- updating：是否正在执行远程升级功能(update.lua)
-- dbging：是否正在执行dbg功能(dbg.lua)
-- ntping：是否正在执行NTP时间同步功能(ntp.lua)
-- shutpending：是否有等待处理的进入AT+CIPSHUT请求
local apnFlag, flyMode, updating, dbging, ntping, shutpending = true

--- 设置APN的参数
-- @string apn, APN的名字
-- @string user, APN登陆用户名
-- @string pwd,  APN登陆用户密码
function setApn(apn, user, pwd)
    apnname, username, password = apn, user or '', pwd or ''
    apnflag = false
end

--- 获取APN的名称
-- @return string, APN的名字
function getApn()
    return apnname
end

--[[
函数名：makeReconnPolicy
功能  ：socket连接超时没有应答处理函数
参数  ：
id：socket id
返回值：无
]]
local function makeReconnPolicy(id)
    print("link.makeReconnPolicy ---->\t", id, reconnStrategy)
    if reconnStrategy then
        sys.restart("link.makeReconnPolicy")
    end
end

--- 设置“socket连接超时没有应答”的控制参数
-- @string flag,"restart" or "reconn"
-- @number interval,超时时间ms
-- @return 无
function setReconnInterval(flag, interval)
    reconnStrategy = flag or reconnStrategy
    reconnInterval = interval
end

--- 设置PDP并激活IP服务
-- @return 无
function activatePdp()
    print("link.activatePdp----->\t", ipStatus, cgatt, flyMode)
    -- IP服务已激活或处于飞行模式直接返回
    if ipStatus ~= "IP INITIAL" or flyMode then
        return
    end
    -- GPRS 未附着成功
    if cgatt ~= "1" then
        print("link.activatePdp----->\t wait cgatt!")
    end
    -- 激活IP服务
    ril.request()
    ril.request("AT+CSTT=\"" .. apnname .. '\",\"' .. username .. '\",\"' .. password .. "\"")
    ril.request("AT+CIICR")
    --查询激活状态
    ril.request("AT+CIPSTATUS")
    ipStatus = "IP START"
end

local inited = false
--[[
函数名：initial
功能  ：配置本模块功能的一些初始化参数
参数  ：无
返回值：无
]]
local function initial()
    if not inited then
        inited = true
        req("AT+CIICRMODE=2")--ciicr异步
        req("AT+CIPMUX=1")--多链接
        req("AT+CIPHEAD=1")
        req("AT+CIPQSEND=" .. qsend)--发送模式
    end
end

--[[
函数名：netmsg
功能  ：GSM注册成功初始化PDP配置
参数  ：无
返回值：无
]]
local function netmsg(id, data)
    --GSM网络已注册
    if data == "REGISTERED" then
        --进行初始化配置
        initial()
    end
end

--[[
函数名：cgattrsp
功能  ：查询GPRS数据网络附着状态的应答处理
参数  ：
cmd：此应答对应的AT命令
success：AT命令执行结果，true或者false
response：AT命令的应答中的执行结果字符串
intermediate：AT命令的应答中的中间信息
返回值：无
]]
local function cgattrsp(cmd, success, response, intermediate)
    --已附着
    if intermediate == "+CGATT: 1" then
        cgatt = "1"
        sys.publish("NET_GPRS_READY", true)
        
        -- 如果存在链接,那么在gprs附着上以后自动激活IP网络
        if base.next(linkList) then
            if ipStatus == "IP INITIAL" then
                activatePdp()
            else
                ril.request("AT+CIPSTATUS")
            end
        end
    --未附着
    elseif intermediate == "+CGATT: 0" then
        if cgatt ~= "0" then
            cgatt = "0"
            sys.publish("NET_GPRS_READY", false)
        end
    end
end

--[[
函数名：sendcnf
功能  ：socket数据发送结果确认
参数  ：
id：socket id
result：发送结果字符串
返回值：无
]]
local function sendcnf(id, result)
    local str = string.match(result, "([%u ])")
    --发送失败
    if str == "TCP ERROR" or str == "UDP ERROR" or str == "ERROR" then
        linkList[id].state = result
    end
    --调用用户注册的状态处理函数
    linkList[id].notify(id, "SEND", result)
end

--[[
函数名：closecnf
功能  ：socket关闭结果确认
参数  ：
id：socket id
result：关闭结果字符串
返回值：无
]]
function closecnf(id, result)
    --socket id无效
    if not id or not linkList[id] then
        print("link.closecnf:error", id)
        return
    end
    --不管任何的close结果,链接总是成功断开了,所以直接按照链接断开处理
    if linkList[id].state == "DISCONNECTING" then
        linkList[id].state = "CLOSED"
        linkList[id].notify(id, "DISCONNECT", "OK")
        usersckntfy(id, false)
        stopconnectingtimer(id)
    --连接注销,清除维护的连接信息,清除urc关注
    elseif linkList[id].state == "CLOSING" then
        local tlink = linkList[id]
        usersckntfy(id, false)
        linkList[id] = nil
        ril.deregurc(tostring(id), urc)
        tlink.notify(id, "CLOSE", "OK")
        stopconnectingtimer(id)
    else
        print("link.closecnf:error", linkList[id].state)
    end
end

--[[
函数名：rsp
功能  ：本功能模块内“通过虚拟串口发送到底层core软件的AT命令”的应答处理
参数  ：
cmd：此应答对应的AT命令
success：AT命令执行结果，true或者false
response：AT命令的应答中的执行结果字符串
intermediate：AT命令的应答中的中间信息
返回值：无
]]
local function rsp(cmd, success, response, intermediate)
    local prefix = string.match(cmd, "AT(%+%u+)")
    local id = tonumber(string.match(cmd, "AT%+%u+=(%d)"))
    --发送数据到服务器的应答
    if prefix == "+CIPSEND" then
        if response == "+PDP: DEACT" then
            ril.request("AT+CIPSTATUS")
            response = "ERROR"
        end
        if string.match(response, "DATA ACCEPT") then
            sendcnf(id, "SEND OK")
        else
            sendcnf(id, getresult(response))
        end
    --关闭socket的应答
    elseif prefix == "+CIPCLOSE" then
        closecnf(id, getresult(response))
    --关闭IP网络的应答
    elseif prefix == "+CIPSHUT" then
        shutcnf(response)
    --连接到服务器的应答
    elseif prefix == "+CIPSTART" then
        if response == "ERROR" then
            statusind(id, "ERROR")
        end
    --激活IP网络的应答
    elseif prefix == "+CIICR" then
        if success then
            ipStatus = "IP CONFIG"
            print("link.rsp ipStatus is ---->\t", ipStatus)
        else
            shut()
        end
    end
end

-- 订阅AT命令返回消息
ril.regrsp("+CIPSTART", rsp)
ril.regrsp("+CIPSEND", rsp)
ril.regrsp("+CIPCLOSE", rsp)
ril.regrsp("+CIPSHUT", rsp)
ril.regrsp("+CIICR", rsp)

-- 订阅app消息
sys.subscribe(proc, "IMSI_READY", "FLYMODE_IND", "UPDATE_BEGIN_IND", "UPDATE_END_IND", "DBG_BEGIN_IND", "DBG_END_IND", "NTP_BEGIN_IND", "NTP_END_IND")
sys.subscribe(netmsg, "NET_STATE_CHANGED")

--- GPRS网络IP服务连接处理任务
-- function connectionTask()
--     -- 每隔2000ms查询1次GPRS附着状态，直到附着成功。
--     while ipStatus ~= "IP START" do
--         -- 不是飞行模式的时候查询GPRS附着状态
--         if not flyMode then ril.request("AT+CGATT?", nil, cgattrsp) end
--         sys.wait(2000)
--     end
--     -- 'ril.regrsp("+CIICR", rsp)'回调rsp函数，并返回IP服务激活结果
--     -- i是超时计数，每次2秒
--     local i = 1
--     while ipStatus ~= "IP GPRSACT" do
--         if i >= 60 then
--             sys.restart("link.connectionTask is reboot for :\t activatePDP is fail!")
--         else
--             i = i + 1
--         end
--         sys.wait(2000)
--     end
--     --获取IP地址，地址获取成功后，IP网络状态会切换为"IP STATUS"
--     ril.request("AT+CIFSR")
--     --查询IP网络状态
--     ril.request("AT+CIPSTATUS")
-- end
function connectionTask()
    -- 每隔2000ms查询1次GPRS附着状态，直到附着成功。
    sys.waitUntil(IP_STATUS_IND, "IP START", 2000, function()
        if not flyMode then ril.request("AT+CGATT?", nil, cgattrsp) end
    end)
    -- 激活IP服务，等待IP获取成功消息，等待超时2分钟重启模块
    sys.waitUntil(IP_STATUS_IND, "IP GPRSACT", 120000, function()
        sys.restart("link.connectionTask is reboot for :\t activatePDP is fail!")
    end)
    
    --获取IP地址，地址获取成功后，IP网络状态会切换为"IP STATUS"
    ril.request("AT+CIFSR")
    --查询IP网络状态
    ril.request("AT+CIPSTATUS")
end
