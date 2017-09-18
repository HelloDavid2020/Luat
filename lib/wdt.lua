--- 模块功能：外部硬件看门狗
-- @module wdt
-- @author 稀饭放姜
-- @license MIT
-- @copyright openLuat
-- @release 2017.09.13
module(..., package.seeall)

local pio = require "pio"

-- 模块复位看门狗引脚配置
local RST_SCMWD_PIN = pio.P0_31
-- 模块喂狗引脚配置
local WATCHDOG_PIN = pio.P0_29

--[[模块和看门狗互喂任务
-- @return 无
-- @usage local RST_SCMWD_PIN,RST_SCMWD_PIN
-- @usage taskWdt()
--]]
local function taskWdt(rst, wd)
    -- 初始化喂狗引脚电平(初始高电平，喂狗拉低2秒)
    pio.pin.setdir(pio.OUTPUT, rst)
    pio.pin.setval(1, rst)
    
    -- 模块<--->看门狗  相互循环喂脉冲
    while true do
        -- 模块 ---> 看门狗 喂脉冲
        pio.pin.close(wd)
        pio.pin.setdir(pio.OUTPUT, wd)
        pio.pin.setval(0, wd)
        print("Air800 --> WATCHDOG >>>>>>", 'OK')
        sys.wait(2000)
        
        -- 看门狗 ---> 模块 喂脉冲
        pio.pin.close(wd)
        pio.pin.setdir(pio.INPUT, wd)
        for i = 1, 30 do
            if 0 ~= pio.pin.getval(wd) then
                sys.wait(100)
            else
                print("WatchDog --> Air800 >>>>>>", 'OK')
                break
            end
            -- 狗饿死了
            if 30 == i then
                pio.pin.setval(0, rst)
                print("The WatchDog --> Air800 didn't respond >>>>>>", "wdt reset 153b")
                sys.wait(100)
            end
        end
        -- 2分钟后再喂
        sys.wait(120000)
    end
end

--- 配置模块与看门狗通讯IO并启动任务
-- @param rst -- 模块复位单片机引脚(pio.P0_31)
-- @param wd  -- 模块和单片机相互喂狗引脚(pio.P0_29)
-- @return 无
-- @usage setup(pio.P0_31,pio.P0_29)
function setup(rst, wd)
    RST_SCMWD_PIN = rst or RST_SCMWD_PIN
    WATCHDOG_PIN = wd or WATCHDOG_PIN
    sys.taskInit(taskWdt, RST_SCMWD_PIN, WATCHDOG_PIN)
end
