# OpenLuat　各模块发布消息ID和值详解

## link.lua
- ipStatus 多链接状态的值：
    > "IP INITIAL"  : 初始化PDP

    > "IP START"    ：启动PDP注册
    
    > "IP CONFIG"   ：配置场景

    > "IP GPRSACT"  ：场景已激活

    > "IP PROCESSING"   ： IP 数据阶段

    > "IP STATUS"   ：获得本地 IP 状态

    > "PDP DEACT"   : 场景被释放
- GPRS附着状态，true 为成功，false为失败
    - sys.dispatch("NET_GPRS_READY",false or true) 

## sim.lua 
- SIM 卡正常情况
    - sys.publish("SIM_IND", "RDY")
- SIM 卡未检测到
    - sys.publish("SIM_IND", "NIST")
- SIM 卡开启PIN
    - sys.publish("SIM_IND_SIM_PIN")
- SIM 卡没准备好
    - sys.publish("SIM_IND", "NORDY")
- SIM 卡已读取IMSI
    - sys.publish("IMSI_READY")

## net.lua
- GSM 状态发生变化
    - sys.publish("NET_STATE_CHANGED", state)
        - state 的值：
            > "UNREGISTER"   ：GSM 未注册

            > "REGISTERED"   ：GSM 已注册 
- GSM 小区号发生变化
    - sys.publish("NET_CELL_CHANGED")
- GSM 有效小区号发布
    - sys.publish("CELL_INFO_IND", cellinfo)
- GSM 读取到信号质量
    - sys.publish("GSM_SIGNAL_REPORT_IND", success, rssi)

## pins.lua
- GPIO 中断消息
    - sys.publish("INT_GPIO_PRESS", pio.pin, "NEG")
