--- 模块功能：GPIO 功能配置，包括输入输出IO和上升下降沿中断IO
-- @module pins
-- @author 稀饭放姜
-- @license MIT
-- @copyright openLuat
-- @release 2017.09.22
module(..., package.seeall)
local base = _G
local assert = base.assert
local print = base.print

-- 中断IO列表
local InterrupPins = {}

--- 添加中断IO函数
-- @param pin ,参数为pio.P0_1-31 和 pio_P1_1-31 (IO >= 32 and IO - 31)
-- @string rim ,参数为下降沿:"NEG" or 上升沿:"POS"
-- @return 无
-- @usage addInterrup(pio.P1_1,"NEG") 配置IO为pio.32,中断模式，下降沿触发。中断会产生消息“INT_GPIO_TRIGGER”
function addInterrup(pin, rim)
    assert(pin ~= nil, "pins.addInterrup first param is nil !")
    assert(pin == "POS" or rim == "NEG", "pins.addInterrup last param is fail !")
    table.insert(InterrupPins, {pin, rim})
end

--- 自适应GPIO模式
-- @param pin ，参数为pio.P0_1-31 和 pio_P1_1-31 (IO >= 32 and IO - 31)
-- @number val，输出模式默认电平：0 是低电平1是高电平，中断模式0或“NEG”为下降沿，1或“POS”为上升沿。
-- @string it, 中断标志“IT”为设置当前IO为中断IO
-- @return function ,返回一个函数，该函数接受一个参数用来设置IO的电平
-- @usage key = pins.setup(pio.P1_1,0,"IT") ，配置Key的IO为pio.32,中断模式，下降沿触发。用key()获取当前电平
-- @usage led = pins.setup(pio.P1_1,0) ,配置LED脚的IO为pio.32，输出模式，默认输出低电平。led(1)即可输出高电平
-- @usage key = pins.setup(pio.P1_1),配置key的IO为pio.32，输入模式,用key()即可获得当前电平
function setup(pin, val, it)
    -- 关闭该IO
    pio.pin.close(pin)
    -- 中断模式配置
    if it == "IT" then
        if val == "POS" or 1 then
            addInterrup(pin, "POS")
        elseif val == "NEG" or 0 then
            addInterrup(pin, "NEG")
        end
    end
    -- 输出模式初始化默认配置
    if val ~= nil then
        pio.pin.setdir(pio.OUTPUT, pin)
        pio.pin.setval(val, pin)
    -- 输入模式初始化默认配置
    else
        pio.pin.setdir(pio.INPUT, pin)
    end
    -- 返回一个自动切换输入输出模式的函数
    return function(val)
        pio.pin.close(pin)
        if val ~= nil then
            pio.pin.setdir(pio.OUTPUT, pin)
            pio.pin.setval(val, pin)
            -- print("pins.setup is output1 model\t pio.p_", pin)
            pio.pin.setval(val, pin)
        else
            pio.pin.setdir(pio.INPUT, pin)
            -- print("pins.setup is input1 model\t pio.p_", pin)
            return pio.pin.getval(pin)
        end
    end
end

--[[
函数名：intmsg
功能  ：中断型引脚的中断处理程序，会抛出一个逻辑中断消息给其他模块使用
参数  ：
msg：table类型；msg.int_id：中断电平类型，cpu.INT_GPIO_POSEDGE表示高电平中断；msg.int_resnum：中断的引脚id
返回值：无
]]
local function intmsg(msg)
    local status = "NEG"
    
    if msg.int_id == cpu.INT_GPIO_POSEDGE then status = "POS" end
    
    for _, v in ipairs(InterrupPins) do
        if v[1] == msg.int_resnum and v[2] == status then
            sys.publish("INT_GPIO_TRIGGER", v[1], v[2])
            return
        end
    end
end
--注册引脚中断的处理函数
rtos.on(rtos.MSG_INT, intmsg)
