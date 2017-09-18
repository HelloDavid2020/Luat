--- 模块功能：LED闪灯模块
-- @module led
-- @author smset,稀饭放姜
-- @license MIT
-- @copyright openLuat
-- @release 2017.09.13
module(..., package.seeall)

local pio = require "pio"
local sys = require "sys"
require "patch"
local base = _G
-- 加载常用的全局函数至本地
local print = base.print
local unpack = base.unpack
local ipairs = base.ipairs
local type = base.type
local pairs = base.pairs
local assert = base.assert
local tonumber = base.tonumber

-- 默认net灯的GPIO
local LEDPIN = pio.P0_28
-- 默认灯亮的事件
local lighting = 1

-- 电量任务切换
blinkCount = 4
-- 电量指示灯亮、灭、周期参数单位ms
local blinkLight, blinkDark, blinkDull = 200, 300, 3000

--[[
-- 电池电量显示
-- 参数：闪烁状态表
-- @return 无
--]]
local function battLevel(ledPin)
    pio.pin.setdir(pio.OUTPUT, ledPin)
    while true do
        for i = 1, blinkCount do
            pio.pin.setval(1, ledPin)
            sys.wait(blinkLight)
            pio.pin.setval(0, ledPin)
            sys.wait(blinkDark)
        end
        pio.pin.setval(0, ledPin)
        sys.wait(blinkDull)
    end
end

--- 配置net灯的GPIO
-- @param ledPin , 模块闪灯GPIO引脚
-- @return 无
-- @usage setup(pio.P0_28)
function setup(ledPin)
    LEDPIN = ledPin or LEDPIN
    --print("led.battLevel -- is loading !")
    sys.taskInit(battLevel, LEDPIN)
end

--- 自定义电量闪烁状态
-- @number light ,指示灯亮的时间ms
-- @number dark ，指示灯灭的时间ms
-- @number dull ，两次指示间隔的时间ms
-- @return 无
-- @usage setBattBlink(300,700,3000)
function setBattBlink(light, dark, dull)
    blinkLight = light or blinkLight
    blinkDark = dark or blinkDark
    blinkDull = dull or blinkDull
end
