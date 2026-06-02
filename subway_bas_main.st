(*=======================================================*)
(* 地铁BAS系统 - 主程序                                    *)
(* Subway Building Automation System - Main Program       *)
(* Version: 1.0                                           *)
(* Date: 2025-01-01                                       *)
(*=======================================================*)

PROGRAM Main
VAR
    (* 系统状态变量 *)
    system_mode : BYTE;                (* 0=自动 1=手动 2=维护 *)
    system_enabled : BOOL := TRUE;     (* 系统启用标志 *)
    fault_flag : BOOL := FALSE;        (* 故障标志 *)
    
    (* 输入输出对象 *)
    lighting : LightingControl;        (* 照明控制 *)
    hvac : HVACControl;               (* 空调通风控制 *)
    water : WaterSystemControl;       (* 给排水控制 *)
    power : PowerMonitoring;          (* 电力监测 *)
    
    (* 时间和定时器 *)
    system_timer : TON;               (* 系统运行定时器 *)
    fault_timer : TON;                (* 故障检测定时器 *)
    
    (* 通讯和日志 *)
    data_logger : DataLogger;         (* 数据记录器 *)
    alarm_manager : AlarmManager;     (* 报警管理器 *)
END_VAR

(* 主程序逻辑 *)
BEGIN
    (* 系统初始化 *)
    IF NOT system_enabled THEN
        DisableAllSystems();
        RETURN;
    END_IF;
    
    (* 根据系统模式执行不同逻辑 *)
    CASE system_mode OF
        0: (* 自动模式 *)
            AutomaticMode();
        1: (* 手动模式 *)
            ManualMode();
        2: (* 维护模式 *)
            MaintenanceMode();
    END_CASE;
    
    (* 故障检测和处理 *)
    DetectFaults();
    HandleFaults();
    
    (* 数据记录和远程通讯 *)
    data_logger(trigger := TRUE);
    alarm_manager(trigger := TRUE);
    
END_PROGRAM

(*=======================================================*)
(* 照明控制模块                                           *)
(*=======================================================*)

FUNCTION_BLOCK LightingControl
VAR_INPUT
    enable : BOOL;                    (* 使能信号 *)
    brightness_setpoint : INT := 500; (* 亮度设定值 0-1000 *)
    occupancy : BOOL;                 (* 占用传感器 *)
    daylight : INT;                   (* 日光强度 0-1000 *)
END_VAR

VAR_OUTPUT
    light_level : INT;                (* 当前亮度值 *)
    light_status : BOOL;              (* 灯光状态 *)
END_VAR

VAR
    pid_controller : PID;             (* PID控制器 *)
    auto_dimming_enabled : BOOL := TRUE;
    min_brightness : INT := 200;
    max_brightness : INT := 1000;
END_VAR

BEGIN
    IF NOT enable THEN
        light_status := FALSE;
        light_level := 0;
        RETURN;
    END_IF;
    
    (* 自动调光逻辑 *)
    IF auto_dimming_enabled THEN
        (* 根据日光强度自动调整 *)
        IF daylight > 300 THEN
            light_level := brightness_setpoint - (daylight / 2);
        ELSE
            light_level := brightness_setpoint;
        END_IF;
    ELSE
        light_level := brightness_setpoint;
    END_IF;
    
    (* 限制亮度范围 *)
    IF light_level < min_brightness THEN
        light_level := min_brightness;
    ELSIF light_level > max_brightness THEN
        light_level := max_brightness;
    END_IF;
    
    (* 根据占用情况控制 *)
    IF occupancy THEN
        light_status := TRUE;
    ELSE
        light_level := 0;
        light_status := FALSE;
    END_IF;
    
END_FUNCTION_BLOCK

(*=======================================================*)
(* HVAC（空调通风）控制模块                               *)
(*=======================================================*)

FUNCTION_BLOCK HVACControl
VAR_INPUT
    enable : BOOL;
    temp_setpoint : REAL := 22.0;     (* 温度设定值 °C *)
    humidity_setpoint : INT := 50;    (* 湿度设定值 % *)
    current_temp : REAL;              (* 当前温度 *)
    current_humidity : INT;           (* 当前湿度 *)
    occupancy : BOOL;
END_VAR

VAR_OUTPUT
    fan_speed : INT := 0;             (* 风扇速度 0-100% *)
    cooling_valve : REAL := 0.0;      (* 冷却阀 0.0-1.0 *)
    heating_valve : REAL := 0.0;      (* 加热阀 0.0-1.0 *)
    status : BYTE;                    (* 状态: 0=停止 1=供暖 2=制冷 3=除湿 *)
END_VAR

VAR
    temp_error : REAL;
    humidity_error : INT;
    pid_temp : PID;
END_VAR

BEGIN
    IF NOT enable OR NOT occupancy THEN
        fan_speed := 0;
        cooling_valve := 0.0;
        heating_valve := 0.0;
        status := 0;
        RETURN;
    END_IF;
    
    (* 温度控制 *)
    temp_error := current_temp - temp_setpoint;
    
    IF temp_error > 2.0 THEN
        (* 温度过高 - 启动制冷 *)
        cooling_valve := 0.5 + (temp_error / 10.0);
        heating_valve := 0.0;
        fan_speed := 70;
        status := 2;
    ELSIF temp_error < -2.0 THEN
        (* 温度过低 - 启动供暖 *)
        heating_valve := 0.5 + (ABS(temp_error) / 10.0);
        cooling_valve := 0.0;
        fan_speed := 50;
        status := 1;
    ELSE
        (* 温度正常 - 低速运行 *)
        cooling_valve := 0.1;
        heating_valve := 0.1;
        fan_speed := 30;
        status := 0;
    END_IF;
    
    (* 限制阀门范围 *)
    cooling_valve := LIMIT(0.0, cooling_valve, 1.0);
    heating_valve := LIMIT(0.0, heating_valve, 1.0);
    
    (* 湿度控制 *)
    humidity_error := current_humidity - humidity_setpoint;
    IF humidity_error > 10 THEN
        status := 3; (* 除湿模式 *)
        fan_speed := 80;
    END_IF;
    
END_FUNCTION_BLOCK

(*=======================================================*)
(* 给排水系统控制模块                                     *)
(*=======================================================*)

FUNCTION_BLOCK WaterSystemControl
VAR_INPUT
    enable : BOOL;
    pump_enable : BOOL;
    water_level : REAL;               (* 水位 0-100% *)
    level_high : REAL := 80.0;        (* 高液位警告 *)
    level_low : REAL := 20.0;         (* 低液位警告 *)
    flow_rate : REAL;                 (* 流量 L/min *)
END_VAR

VAR_OUTPUT
    pump_status : BOOL := FALSE;      (* 泵运行状态 *)
    inlet_valve : REAL := 0.0;        (* 进水阀 0.0-1.0 *)
    outlet_valve : REAL := 0.0;       (* 排水阀 0.0-1.0 *)
    alarm_high_level : BOOL := FALSE;
    alarm_low_level : BOOL := FALSE;
    alarm_flow_error : BOOL := FALSE;
END_VAR

VAR
    pump_timer : TON;
    level_check_timer : TON;
END_VAR

BEGIN
    IF NOT enable THEN
        pump_status := FALSE;
        inlet_valve := 0.0;
        outlet_valve := 0.0;
        RETURN;
    END_IF;
    
    (* 液位检测 *)
    IF water_level > level_high THEN
        alarm_high_level := TRUE;
        inlet_valve := 0.0;     (* 关闭进水 *)
        outlet_valve := 1.0;    (* 打开排水 *)
    ELSIF water_level < level_low THEN
        alarm_low_level := TRUE;
        inlet_valve := 1.0;     (* 打开进水 *)
        outlet_valve := 0.0;    (* 关闭排水 *)
    ELSE
        alarm_high_level := FALSE;
        alarm_low_level := FALSE;
        inlet_valve := 0.2;
        outlet_valve := 0.2;
    END_IF;
    
    (* 泵控制 *)
    IF pump_enable AND (water_level > level_low) THEN
        pump_status := TRUE;
    ELSIF water_level < level_low THEN
        pump_status := FALSE;
    END_IF;
    
    (* 流量监测 *)
    IF pump_status AND flow_rate < 5.0 THEN
        alarm_flow_error := TRUE;
    ELSE
        alarm_flow_error := FALSE;
    END_IF;
    
END_FUNCTION_BLOCK

(*=======================================================*)
(* 电力监测模块                                           *)
(*=======================================================*)

FUNCTION_BLOCK PowerMonitoring
VAR_INPUT
    enable : BOOL;
    voltage_phase_a : REAL;           (* A相电压 V *)
    voltage_phase_b : REAL;
    voltage_phase_c : REAL;
    current_phase_a : REAL;           (* A相电流 A *)
    current_phase_b : REAL;
    current_phase_c : REAL;
    power_frequency : REAL := 50.0;   (* 频率 Hz *)
END_VAR

VAR_OUTPUT
    total_power : REAL;               (* 总功率 kW *)
    power_factor : REAL;              (* 功率因数 *)
    voltage_unbalance : REAL;         (* 电压不平衡度 % *)
    current_unbalance : REAL;         (* 电流不平衡度 % *)
    alarm_overvoltage : BOOL := FALSE;
    alarm_undervoltage : BOOL := FALSE;
    alarm_overcurrent : BOOL := FALSE;
END_VAR

VAR
    voltage_avg : REAL;
    voltage_nominal : REAL := 380.0;  (* 标称电压 V *)
    voltage_tolerance : REAL := 0.1;  (* 允许偏差 ±10% *)
    current_max : REAL := 100.0;      (* 最大允许电流 A *)
END_VAR

BEGIN
    IF NOT enable THEN
        RETURN;
    END_IF;
    
    (* 计算平均电压 *)
    voltage_avg := (voltage_phase_a + voltage_phase_b + voltage_phase_c) / 3.0;
    
    (* 计算功率 *)
    total_power := (voltage_phase_a * current_phase_a + 
                   voltage_phase_b * current_phase_b + 
                   voltage_phase_c * current_phase_c) / 1000.0;
    
    (* 电压监测 *)
    IF voltage_avg > (voltage_nominal * (1.0 + voltage_tolerance)) THEN
        alarm_overvoltage := TRUE;
    ELSIF voltage_avg < (voltage_nominal * (1.0 - voltage_tolerance)) THEN
        alarm_undervoltage := TRUE;
    ELSE
        alarm_overvoltage := FALSE;
        alarm_undervoltage := FALSE;
    END_IF;
    
    (* 电流监测 *)
    IF current_phase_a > current_max OR 
       current_phase_b > current_max OR 
       current_phase_c > current_max THEN
        alarm_overcurrent := TRUE;
    ELSE
        alarm_overcurrent := FALSE;
    END_IF;
    
    (* 计算不平衡度 *)
    voltage_unbalance := (MAX(voltage_phase_a, voltage_phase_b, voltage_phase_c) - 
                         MIN(voltage_phase_a, voltage_phase_b, voltage_phase_c)) / voltage_avg * 100.0;
    
    current_unbalance := (MAX(current_phase_a, current_phase_b, current_phase_c) - 
                         MIN(current_phase_a, current_phase_b, current_phase_c)) / 
                         ((current_phase_a + current_phase_b + current_phase_c) / 3.0) * 100.0;
    
END_FUNCTION_BLOCK

(*=======================================================*)
(* 辅助函数                                               *)
(*=======================================================*)

PROCEDURE DisableAllSystems()
VAR
    i : INT;
END_VAR
BEGIN
    (* 关闭所有系统 *)
    lighting.enable := FALSE;
    hvac.enable := FALSE;
    water.enable := FALSE;
    power.enable := FALSE;
END_PROCEDURE;

PROCEDURE AutomaticMode()
BEGIN
    (* 自动模式下的系统协调逻辑 *)
    (* 根据时间表、传感器数据自动控制各子系统 *)
END_PROCEDURE;

PROCEDURE ManualMode()
BEGIN
    (* 手动模式下可由操作员直接控制 *)
END_PROCEDURE;

PROCEDURE MaintenanceMode()
BEGIN
    (* 维护模式下系统以安全状态运行 *)
    hvac.fan_speed := 50;
    lighting.auto_dimming_enabled := FALSE;
END_PROCEDURE;

PROCEDURE DetectFaults()
BEGIN
    (* 故障检测逻辑 *)
END_PROCEDURE;

PROCEDURE HandleFaults()
BEGIN
    (* 故障处理逻辑 *)
END_PROCEDURE;

(*=======================================================*)
(* 数据记录和报警管理                                     *)
(*=======================================================*)

FUNCTION_BLOCK DataLogger
VAR_INPUT
    trigger : BOOL;
END_VAR

VAR
    log_timer : TON;
    log_interval : TIME := T#1M; (* 每分钟记录一次 *)
END_VAR

BEGIN
    log_timer(IN := trigger, PT := log_interval);
    IF log_timer.Q THEN
        (* 记录系统数据到数据库或SD卡 *)
        (* 包括: 温度、湿度、功率、故障信息等 *)
    END_IF;
END_FUNCTION_BLOCK;

FUNCTION_BLOCK AlarmManager
VAR_INPUT
    trigger : BOOL;
END_VAR

VAR
    alarm_queue : ARRAY[1..100] OF AlarmRecord;
    alarm_count : INT := 0;
END_VAR

TYPE AlarmRecord :
    STRUCT
        alarm_id : INT;
        alarm_code : INT;
        alarm_text : STRING;
        timestamp : DT;
        severity : BYTE; (* 0=信息 1=警告 2=严重 *)
        cleared : BOOL;
    END_STRUCT;
END_TYPE;

BEGIN
    (* 报警管理逻辑 *)
    (* 将报警信息发送到上位机 *)
END_FUNCTION_BLOCK;