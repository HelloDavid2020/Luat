--必须在这个位置定义PROJECT和VERSION变量
--PROJECT：ascii string类型，可以随便定义，只要不使用,就行
--VERSION：ascii string类型，如果使用Luat物联云平台固件升级的功能，必须按照"X.X.X"定义，X表示1位数字；否则可随便定义
PROJECT = "DEMO_TASK"
VERSION = "2.0.0"
require "sys"
-- 加载GSM
require "net"
--8秒后查询第一次csq
net.startQueryAll(8 * 1000, 600 * 1000)
-- 控制台
require "console"
console.setup(1, 115200)
-- 看门狗
require "wdt"
wdt.setup(pio.P0_31, pio.P0_29)
-- 系統指示灯
require "led"
led.setup(pio.P0_28)
-- 测试任务
require "testTask"

sys.init(0, 0)
sys.run()
