--- 模块功能：GPIO 功能配置，包括输入输出IO和上升下降沿中断IO
-- @module pins
-- @author 稀饭放姜
-- @license MIT
-- @copyright openLuat
-- @release 2017.09.22
module(..., package.seeall)
local base = _G
local assert = base.assert

-- 中断IO列表
local itPins = {}

--- 添加中断IO函数
function addIt(pin, rim)
    assert(pin ~= nil, "pins.addIt first param is nil !")
    assert(pin == "POS" or rim == "NEG", "pins.addit last param is fail !")
    table.insert(itPins, {pin, rim})
end

--- 设置GPIO_xx为输入模式
-- @param pin ，参数为pio.P0_1-31 和 pio_P1_1-31 (IO >= 32 and IO - 31)
-- @return function ,返回一个函数，这个函数可以获取GPIO_xx的当前状态
-- @usage key = setIn(pio.P1_1) ，表示设置编号32的IO为输入模式，别名key()。
-- @usage local ledStatus = key()
function setIn(pin)
    assert(pin ~= nil, "pins.setIn first param is nil !")
    pio.pin.close(pin)
    pio.pin.setdir(pio.INPUT, pin)
    return function()
        return pio.pin.getval(pin)
    end
end

--- 设置GPIO_xx为输出模式
-- @param pin ，参数为pio.P0_1-31 和 pio_P1_1-31 (IO >= 32 and IO - 31)
-- @number val，初始默认电平：0 为低电平，非0为高电平
-- @return function ,返回一个函数，该函数接受一个参数用来设置IO的电平
-- @usage led = setOut(pio.P1_1,0) ，表示设置编号32的IO为输出模式，别名led()，默认输出低电平。
-- @usage led(1) -- 设置led输出高电平
function setOut(pin, val)
    assert(pin ~= nil, "pins.setIn first param is nil !")
    pio.pin.close(pin)
    pio.pin.setdir(pio.OUTPUT, pin)
    pio.pin.setval(val, pin)
    return function(v)
        pio.pin.setval(v, pin)
    end
end

--- 自适应GPIO模式
-- @param pin ，参数为pio.P0_1-31 和 pio_P1_1-31 (IO >= 32 and IO - 31)
-- @number val，初始默认电平：0 为低电平，非0为高电平
-- @string it, 中断IO的上升沿"POS" 或 下降沿"NEG"
-- @return function ,返回一个函数，该函数接受一个参数用来设置IO的电平
-- @usage key = setup(pio.P1_1,0,"NEG") ，配置Key为中断IO，下降沿触发中断。用key()获取电平值
-- @usage key() -- 获取当前中断IO的电平值
function setup(pin, val, it)
    if val ~= nil then
        if it == "POS" or it == "NEG" then
            addIt(pin, it)
            return setIn(pin)
        else
            return setOut(pin, val)
        end
    else
        return setIn(pin)
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
    
    for _, v in ipairs(itPins) do
        if v[1] == msg.int_resnum and v[2] == status then
            sys.publish("INT_GPIO_PRESS", v[1], v[2])
            return
        end
    end
end
--注册引脚中断的处理函数
rtos.on(rtos.MSG_INT, intmsg)
