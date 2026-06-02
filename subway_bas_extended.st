(*=======================================================*)
(* 地铁BAS系统 - 扩展模块                                  *)
(* Subway BAS Extended Modules                          *)
(* 包含: 门禁系统、消防报警、应急疏散                      *)
(* Version: 1.0                                         *)
(*=======================================================*)

(*=======================================================*)
(* 门禁控制模块                                           *)
(*=======================================================*)

FUNCTION_BLOCK AccessControlSystem
VAR_INPUT
    enable : BOOL;
    emergency_unlock : BOOL := FALSE;     (* 紧急解锁信号 *)
    alarm_triggered : BOOL;                (* 报警触发信号 *)
    system_mode : BYTE;                    (* 0=正常 1=维护 2=应急 *)
END_VAR

VAR_OUTPUT
    all_gates_locked : BOOL := TRUE;       (* 所有闸门上锁状态 *)
    status : BYTE;                         (* 0=正常 1=报警 2=应急疏散 *)
END_VAR

VAR
    gates : ARRAY[1..16] OF GateControl;   (* 16个闸门 *)
    access_log : ARRAY[1..1000] OF AccessLogEntry;
    log_index : INT := 0;
    gate_count : INT := 16;
    i : INT;
END_VAR

TYPE GateControl :
    STRUCT
        gate_id : INT;
        gate_name : STRING;
        locked : BOOL := TRUE;
        access_allowed : BOOL := FALSE;
        door_open : BOOL := FALSE;
        tamper_alarm : BOOL := FALSE;
        unlock_timer : TON;
        unlock_time : TIME := T#3S;        (* 默认开启3秒 *)
        access_log_enabled : BOOL := TRUE;
    END_STRUCT;
END_TYPE;

TYPE AccessLogEntry :
    STRUCT
        timestamp : DT;
        gate_id : INT;
        event_type : BYTE;                 (* 0=刷卡 1=解锁 2=报警 *)
        user_id : STRING;
        card_id : STRING;
        granted : BOOL;
    END_STRUCT;
END_TYPE;

BEGIN
    IF NOT enable THEN
        FOR i := 1 TO gate_count DO
            gates[i].locked := TRUE;
            gates[i].access_allowed := FALSE;
        END_FOR;
        RETURN;
    END_IF;
    
    (* 紧急解锁 *)
    IF emergency_unlock OR alarm_triggered THEN
        FOR i := 1 TO gate_count DO
            gates[i].locked := FALSE;
            gates[i].access_allowed := TRUE;
            gates[i].unlock_timer(IN := TRUE, PT := T#30S);
        END_FOR;
        status := 2; (* 应急疏散模式 *)
        all_gates_locked := FALSE;
        RETURN;
    END_IF;
    
    (* 正常模式 - 按权限控制各闸门 *)
    status := 0;
    all_gates_locked := TRUE;
    
    FOR i := 1 TO gate_count DO
        IF gates[i].access_allowed THEN
            gates[i].locked := FALSE;
            gates[i].unlock_timer(IN := TRUE, PT := gates[i].unlock_time);
            
            (* 解锁计时器到期后关闭 *)
            IF gates[i].unlock_timer.Q THEN
                gates[i].locked := TRUE;
                gates[i].access_allowed := FALSE;
            END_IF;
        ELSE
            gates[i].locked := TRUE;
        END_IF;
        
        all_gates_locked := all_gates_locked AND gates[i].locked;
        
        (* 门被撬开报警 *)
        IF gates[i].locked AND gates[i].door_open THEN
            gates[i].tamper_alarm := TRUE;
            status := 1; (* 报警状态 *)
        END_IF;
    END_FOR;
    
END_FUNCTION_BLOCK;

(*=======================================================*)
(* 人员进出管理                                           *)
(*=======================================================*)

FUNCTION_BLOCK PassengerFlowControl
VAR_INPUT
    enable : BOOL;
    gate_id : INT;
    card_data : STRING;                   (* IC卡数据 *)
    person_detected : BOOL;               (* 红外探测 *)
    ambient_light : REAL;                 (* 环境光强度 *)
END_VAR

VAR_OUTPUT
    access_granted : BOOL := FALSE;
    entry_allowed : BOOL := FALSE;
    exit_allowed : BOOL := FALSE;
    crowd_level : INT := 0;               (* 0=低 1=中 2=高 3=拥挤 *)
    person_count : INT := 0;
    alarm_overcrowd : BOOL := FALSE;
END_VAR

VAR
    card_reader : CardReader;
    crowd_detector : CrowdDetector;
    max_persons_allowed : INT := 5000;   (* 单位最大容纳人数 *)
    emergency_evacuation : BOOL := FALSE;
END_VAR

FUNCTION_BLOCK CardReader
VAR_INPUT
    card_data : STRING;
END_VAR

VAR_OUTPUT
    card_valid : BOOL := FALSE;
    user_id : STRING;
    user_name : STRING;
    access_level : BYTE;                 (* 1=普通 2=员工 3=管理 *)
    entry_time : DT;
    last_access : DT;
END_VAR

BEGIN
    (* 卡片有效性检查 *)
    IF LEN(card_data) = 16 AND card_data[1..2] = 'C' THEN
        card_valid := TRUE;
        user_id := card_data[3..8];
        access_level := BYTE(card_data[10]);
    ELSE
        card_valid := FALSE;
    END_IF;
    
END_FUNCTION_BLOCK;

FUNCTION_BLOCK CrowdDetector
VAR_INPUT
    person_detected : BOOL;
    current_count : INT;
    max_capacity : INT;
END_VAR

VAR_OUTPUT
    crowd_density : INT;                  (* 0-100% *)
    safe : BOOL := TRUE;
END_VAR

BEGIN
    crowd_density := (current_count * 100) / max_capacity;
    
    IF crowd_density > 90 THEN
        safe := FALSE;
    ELSE
        safe := TRUE;
    END_IF;
    
END_FUNCTION_BLOCK;

BEGIN
    IF NOT enable THEN
        access_granted := FALSE;
        entry_allowed := FALSE;
        RETURN;
    END_IF;
    
    (* 卡片验证 *)
    card_reader(card_data := card_data);
    
    (* 拥挤度检测 *)
    crowd_detector(
        person_detected := person_detected,
        current_count := person_count,
        max_capacity := max_persons_allowed
    );
    
    (* 判断进出权限 *)
    IF card_reader.card_valid THEN
        access_granted := TRUE;
        
        (* 根据拥挤度控制进入 *)
        IF person_count < (max_persons_allowed * 90 / 100) THEN
            entry_allowed := TRUE;
        ELSE
            entry_allowed := FALSE;
            alarm_overcrowd := TRUE;
        END_IF;
        
        (* 员工和管理员可随时出去 *)
        IF card_reader.access_level >= 2 THEN
            exit_allowed := TRUE;
        ELSE
            exit_allowed := TRUE;
        END_IF;
    ELSE
        access_granted := FALSE;
        entry_allowed := FALSE;
    END_IF;
    
    (* 根据人员判断拥挤等级 *)
    IF person_count > (max_persons_allowed * 80 / 100) THEN
        crowd_level := 3;
    ELSIF person_count > (max_persons_allowed * 60 / 100) THEN
        crowd_level := 2;
    ELSIF person_count > (max_persons_allowed * 40 / 100) THEN
        crowd_level := 1;
    ELSE
        crowd_level := 0;
    END_IF;
    
END_FUNCTION_BLOCK;

(*=======================================================*)
(* 消防报警和火灾探测系统                                 *)
(*=======================================================*)

FUNCTION_BLOCK FireAlarmSystem
VAR_INPUT
    enable : BOOL;
    manual_alarm : BOOL;                  (* 手动报警按钮 *)
    fire_detected : BOOL;                 (* 火灾确认信号 *)
END_VAR

VAR_OUTPUT
    alarm_status : BYTE;                  (* 0=正常 1=预警 2=火灾报警 *)
    all_alarms_activated : BOOL := FALSE;
    evacuation_mode : BOOL := FALSE;
    emergency_lights_on : BOOL := FALSE;
    sprinkler_on : BOOL := FALSE;
    elevator_to_ground : BOOL := FALSE;   (* 强制电梯回到1楼 *)
    door_open_command : BOOL := FALSE;    (* 强制开门 *)
    ventilation_stop : BOOL := FALSE;     (* 停止通风系统 *)
    status_message : STRING;
END_VAR

VAR
    detectors : ARRAY[1..50] OF FireDetector;  (* 50个火灾探测器 *)
    detector_count : INT := 50;
    alarm_timer : TON;
    alarm_delay : TIME := T#10S;          (* 10秒确认延迟 *)
    i : INT;
    alarm_confirmed : BOOL := FALSE;
END_VAR

TYPE FireDetector :
    STRUCT
        detector_id : INT;
        location : STRING;
        detector_type : BYTE;             (* 0=烟感 1=温感 2=火焰 *)
        triggered : BOOL := FALSE;
        temperature : REAL := 20.0;       (* °C *)
        smoke_level : INT := 0;           (* 0-100% *)
        flame_detected : BOOL := FALSE;
        sensitivity : REAL := 0.8;        (* 灵敏度 0.0-1.0 *)
        last_alarm : DT;
        fault_flag : BOOL := FALSE;
        status : BYTE;                    (* 0=正常 1=异常 2=故障 *)
    END_STRUCT;
END_TYPE;

BEGIN
    IF NOT enable THEN
        alarm_status := 0;
        evacuation_mode := FALSE;
        RETURN;
    END_IF;
    
    (* ============ 火灾探测逻辑 ============ *)
    FOR i := 1 TO detector_count DO
        
        (* 烟感报警 *)
        IF detectors[i].detector_type = 0 THEN
            IF detectors[i].smoke_level > 50 * detectors[i].sensitivity THEN
                detectors[i].triggered := TRUE;
                alarm_status := 1;        (* 预警 *)
            END_IF;
        END_IF;
        
        (* 温感报警 *)
        IF detectors[i].detector_type = 1 THEN
            IF detectors[i].temperature > (60.0 * detectors[i].sensitivity) THEN
                detectors[i].triggered := TRUE;
                alarm_status := 1;
            END_IF;
        END_IF;
        
        (* 火焰报警 *)
        IF detectors[i].detector_type = 2 THEN
            IF detectors[i].flame_detected THEN
                detectors[i].triggered := TRUE;
                alarm_status := 2;        (* 直接触发火灾报警 *)
                alarm_confirmed := TRUE;
            END_IF;
        END_IF;
        
    END_FOR;
    
    (* 手动报警按钮 *)
    IF manual_alarm THEN
        alarm_status := 2;
        alarm_confirmed := TRUE;
        status_message := 'Manual Fire Alarm Activated';
    END_IF;
    
    (* 火灾确认延迟 *)
    IF alarm_status >= 1 THEN
        alarm_timer(IN := TRUE, PT := alarm_delay);
        IF alarm_timer.Q THEN
            alarm_confirmed := TRUE;
            alarm_status := 2;            (* 确认为火灾报警 *)
        END_IF;
    ELSE
        alarm_timer(IN := FALSE);
        alarm_confirmed := FALSE;
    END_IF;
    
    (* ============ 消防响应逻辑 ============ *)
    IF alarm_confirmed THEN
        evacuation_mode := TRUE;
        all_alarms_activated := TRUE;
        
        (* 应急照明启动 *)
        emergency_lights_on := TRUE;
        
        (* 喷水灭火系统 *)
        sprinkler_on := TRUE;
        
        (* 电梯强制返回一楼 *)
        elevator_to_ground := TRUE;
        
        (* 防火门打开 *)
        door_open_command := TRUE;
        
        (* 停止送风系统，防止火势蔓延 *)
        ventilation_stop := TRUE;
        
        status_message := 'FIRE ALARM - EMERGENCY EVACUATION INITIATED';
        
    ELSE
        emergency_lights_on := FALSE;
        sprinkler_on := FALSE;
        elevator_to_ground := FALSE;
        door_open_command := FALSE;
        ventilation_stop := FALSE;
        all_alarms_activated := FALSE;
    END_IF;
    
END_FUNCTION_BLOCK;

(*=======================================================*)
(* 烟雾和气体监测                                         *)
(*=======================================================*)

FUNCTION_BLOCK SmokeAndGasMonitoring
VAR_INPUT
    enable : BOOL;
END_VAR

VAR_OUTPUT
    smoke_level : INT := 0;              (* 烟雾浓度 0-100% *)
    co_level : REAL := 0.0;              (* 一氧化碳 ppm *)
    co2_level : REAL := 400.0;           (* 二氧化碳 ppm *)
    temperature : REAL := 20.0;          (* 温度 °C *)
    alarm_smoke : BOOL := FALSE;
    alarm_co : BOOL := FALSE;
    alarm_co2 : BOOL := FALSE;
END_VAR

VAR
    smoke_threshold : INT := 70;
    co_threshold : REAL := 35.0;         (* WHO标准 *)
    co2_threshold : REAL := 1000.0;      (* 室内空气质量标准 *)
    temp_high_threshold : REAL := 65.0;
    temp_low_threshold : REAL := 5.0;
END_VAR

BEGIN
    IF NOT enable THEN
        RETURN;
    END_IF;
    
    (* 烟雾监测 *)
    IF smoke_level > smoke_threshold THEN
        alarm_smoke := TRUE;
    ELSE
        alarm_smoke := FALSE;
    END_IF;
    
    (* CO监测 *)
    IF co_level > co_threshold THEN
        alarm_co := TRUE;
    ELSE
        alarm_co := FALSE;
    END_IF;
    
    (* CO2监测 *)
    IF co2_level > co2_threshold THEN
        alarm_co2 := TRUE;
    ELSE
        alarm_co2 := FALSE;
    END_IF;
    
END_FUNCTION_BLOCK;

(*=======================================================*)
(* 紧急疏散和应急照明控制                                 *)
(*=======================================================*)

FUNCTION_BLOCK EmergencyEvacuation
VAR_INPUT
    enable : BOOL;
    evacuation_trigger : BOOL;           (* 疏散触发信号 *)
    fire_alarm : BOOL;
    manual_evacuation : BOOL;
    system_fault : BOOL;
END_VAR

VAR_OUTPUT
    evacuation_active : BOOL := FALSE;
    all_exit_lights_on : BOOL := FALSE;  (* 所有出口灯 *)
    emergency_lighting : REAL := 100.0;  (* 应急照明亮度 *)
    evacuation_route_lights : ARRAY[1..20] OF BOOL;  (* 疏散路线灯 *)
    audio_announcement : STRING;         (* 语音播报 *)
    audio_enabled : BOOL := FALSE;
    strobe_lights : BOOL := FALSE;       (* 闪烁灯 *)
    evacuation_timer : TON;
    evacuation_duration : TIME := T#30M; (* 疏散预计时间 *)
END_VAR

VAR
    i : INT;
    announcement_queue : ARRAY[1..10] OF STRING;
    announcement_index : INT := 0;
END_VAR

BEGIN
    IF NOT enable THEN
        evacuation_active := FALSE;
        all_exit_lights_on := FALSE;
        RETURN;
    END_IF;
    
    (* 疏散触发条件 *)
    IF evacuation_trigger OR fire_alarm OR manual_evacuation OR system_fault THEN
        evacuation_active := TRUE;
        evacuation_timer(IN := TRUE, PT := evacuation_duration);
    END_IF;
    
    IF evacuation_active THEN
        
        (* 所有出口灯全开 *)
        all_exit_lights_on := TRUE;
        emergency_lighting := 100.0;
        
        (* 疏散路线灯亮起 *)
        FOR i := 1 TO 20 DO
            evacuation_route_lights[i] := TRUE;
        END_FOR;
        
        (* 闪烁灯警示 *)
        strobe_lights := TRUE;
        
        (* 语音播报 *)
        audio_enabled := TRUE;
        IF fire_alarm THEN
            audio_announcement := 'Fire alarm detected. Emergency evacuation in progress. Please exit through the nearest emergency exit. Do not use elevators.';
        ELSIF manual_evacuation THEN
            audio_announcement := 'Emergency evacuation activated. Please exit the building using the nearest emergency exit.';
        ELSIF system_fault THEN
            audio_announcement := 'System fault detected. Evacuation procedure initiated. Please exit the building.';
        ELSE
            audio_announcement := 'Emergency evacuation. Please exit immediately.';
        END_IF;
        
        (* 疏散时间到 *)
        IF evacuation_timer.Q THEN
            evacuation_active := FALSE;
            all_exit_lights_on := FALSE;
            emergency_lighting := 0.0;
            FOR i := 1 TO 20 DO
                evacuation_route_lights[i] := FALSE;
            END_FOR;
            strobe_lights := FALSE;
        END_IF;
        
    ELSE
        all_exit_lights_on := FALSE;
        emergency_lighting := 0.0;
        strobe_lights := FALSE;
        audio_enabled := FALSE;
    END_IF;
    
END_FUNCTION_BLOCK;

(*=======================================================*)
(* 监视和报警统计分析                                     *)
(*=======================================================*)

FUNCTION_BLOCK SecurityMonitoring
VAR_INPUT
    enable : BOOL;
END_VAR

VAR_OUTPUT
    total_alarms_today : INT := 0;
    false_alarms : INT := 0;
    alarm_response_time : TIME;          (* 平均响应时间 *)
    system_reliability : REAL := 99.5;   (* 系统可靠性 % *)
END_VAR

VAR
    alarm_history : ARRAY[1..500] OF AlarmEvent;
    history_index : INT := 0;
    last_alarm_time : DT;
    response_time_sum : TIME;
END_VAR

TYPE AlarmEvent :
    STRUCT
        timestamp : DT;
        alarm_type : BYTE;                (* 0=火灾 1=入侵 2=其他 *)
        location : STRING;
        confirmed : BOOL;
        response_time : TIME;
        resolved_by : STRING;
    END_STRUCT;
END_TYPE;

BEGIN
    IF NOT enable THEN
        RETURN;
    END_IF;
    
    (* 报警统计和分析 *)
    (* 计算系统可靠性等指标 *)
    
END_FUNCTION_BLOCK;

(*=======================================================*)
(* 集成系统控制 - BAS主程序                                *)
(*=======================================================*)

PROGRAM BAS_MainControl
VAR
    (* 各子系统 *)
    access_control : AccessControlSystem;
    passenger_flow : PassengerFlowControl;
    fire_alarm : FireAlarmSystem;
    smoke_gas : SmokeAndGasMonitoring;
    emergency_evacuation : EmergencyEvacuation;
    security_monitoring : SecurityMonitoring;
    
    (* 系统状态 *)
    system_enabled : BOOL := TRUE;
    system_mode : BYTE := 0;              (* 0=正常 1=应急 2=维护 *)
    master_alarm : BOOL := FALSE;
    emergency_stop : BOOL := FALSE;
    
    (* 逻辑计时器 *)
    system_watchdog : TON;                (* 系统监控 *)
    fault_check_timer : TON;              (* 故障检测 *)
    
    (* 通讯和数据 *)
    remote_status : STRING;
    log_data : STRING;
    
    (* 联动逻辑标志 *)
    elevator_emergency : BOOL := FALSE;
    door_override : BOOL := FALSE;
    ventilation_emergency : BOOL := FALSE;
END_VAR

BEGIN
    
    (* ============ 系统初始化和使能 ============ *)
    IF NOT system_enabled THEN
        access_control.enable := FALSE;
        fire_alarm.enable := FALSE;
        emergency_evacuation.enable := FALSE;
        RETURN;
    END_IF;
    
    (* ============ 启动各个子系统 ============ *)
    access_control.enable := TRUE;
    passenger_flow.enable := TRUE;
    fire_alarm.enable := TRUE;
    smoke_gas.enable := TRUE;
    emergency_evacuation.enable := TRUE;
    security_monitoring.enable := TRUE;
    
    (* ============ 系统监控 ============ *)
    system_watchdog(IN := TRUE, PT := T#30S);
    
    (* ============ 火灾报警联动 ============ *)
    IF fire_alarm.evacuation_mode THEN
        system_mode := 1;                 (* 应急模式 *)
        
        (* 联动1: 强制开门 *)
        access_control.emergency_unlock := fire_alarm.door_open_command;
        door_override := TRUE;
        
        (* 联动2: 停止送风 *)
        ventilation_emergency := fire_alarm.ventilation_stop;
        
        (* 联动3: 电梯返回一楼 *)
        elevator_emergency := fire_alarm.elevator_to_ground;
        
        (* 联动4: 应急疏散 *)
        emergency_evacuation.evacuation_trigger := fire_alarm.all_alarms_activated;
        
    ELSE
        system_mode := 0;                 (* 正常模式 *)
        access_control.emergency_unlock := FALSE;
        door_override := FALSE;
    END_IF;
    
    (* ============ 拥挤预警处理 ============ *)
    IF passenger_flow.alarm_overcrowd THEN
        (* 限流 - 关闭部分入口 *)
        access_control.gates[1].access_allowed := FALSE;
        access_control.gates[2].access_allowed := FALSE;
    END_IF;
    
    (* ============ 气体污染处理 ============ *)
    IF smoke_gas.alarm_smoke OR smoke_gas.alarm_co THEN
        ventilation_emergency := TRUE;
        emergency_evacuation.evacuation_trigger := TRUE;
    END_IF;
    
    (* ============ 紧急停止 ============ *)
    IF emergency_stop THEN
        system_enabled := FALSE;
        access_control.enable := FALSE;
        fire_alarm.enable := FALSE;
    END_IF;
    
    (* ============ 远程状态报告 ============ *)
    remote_status := 'System Mode: ' + BYTE_TO_STRING(system_mode) + 
                     '| Fire Alarm: ' + BOOL_TO_STRING(fire_alarm.evacuation_mode) +
                     '| Passenger Count: ' + INT_TO_STRING(passenger_flow.person_count) +
                     '| Emergency Active: ' + BOOL_TO_STRING(emergency_evacuation.evacuation_active);
    
END_PROGRAM;

(*=======================================================*)
(* 数据类型定义和辅助函数                                 *)
(*=======================================================*)

(* 整数转字符串 *)
FUNCTION INT_TO_STRING : STRING
VAR_INPUT
    value : INT;
END_VAR
BEGIN
    (* 实现整数到字符串的转换 *)
END_FUNCTION;

(* 布尔值转字符串 *)
FUNCTION BOOL_TO_STRING : STRING
VAR_INPUT
    value : BOOL;
END_VAR
BEGIN
    IF value THEN
        BOOL_TO_STRING := 'TRUE';
    ELSE
        BOOL_TO_STRING := 'FALSE';
    END_IF;
END_FUNCTION;

(* 字节转字符串 *)
FUNCTION BYTE_TO_STRING : STRING
VAR_INPUT
    value : BYTE;
END_VAR
BEGIN
    (* 实现字节到字符串的转换 *)
END_FUNCTION;

(* 获取字符串长度 *)
FUNCTION LEN : INT
VAR_INPUT
    str : STRING;
END_VAR
BEGIN
    (* 实现获取字符串长度 *)
END_FUNCTION;

(* 获取最大值 *)
FUNCTION MAX : REAL
VAR_INPUT
    a : REAL;
    b : REAL;
    c : REAL := 0.0;
END_VAR
BEGIN
    IF a > b THEN
        IF a > c THEN
            MAX := a;
        ELSE
            MAX := c;
        END_IF;
    ELSE
        IF b > c THEN
            MAX := b;
        ELSE
            MAX := c;
        END_IF;
    END_IF;
END_FUNCTION;

(* 获取最小值 *)
FUNCTION MIN : REAL
VAR_INPUT
    a : REAL;
    b : REAL;
    c : REAL := 999999.0;
END_VAR
BEGIN
    IF a < b THEN
        IF a < c THEN
            MIN := a;
        ELSE
            MIN := c;
        END_IF;
    ELSE
        IF b < c THEN
            MIN := b;
        ELSE
            MIN := c;
        END_IF;
    END_IF;
END_FUNCTION;

(*=======================================================*)
(* 程序结束                                               *)
(*=======================================================*)