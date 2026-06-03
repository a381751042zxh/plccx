(*==============================================================
  地铁机电能源管理系统 - 主程序
  Metro Electro-mechanical Energy Management System - Main Program
  
  系统功能：
  1. 变压器负荷监测与调度
  2. 配电网能源分配与平衡
  3. 电机启停控制与保护
  4. 能源消耗统计与优化
  5. 故障报警与应急处理
  
  编程语言：IEC 61131-3 (Structured Text)
  更新日期：2026-06-03
==============================================================*)

PROGRAM MetroEnergyManagement

  (* ============ 系统常量定义 ============ *)
  CONST
    MAX_TRANSFORMERS : INT := 8;          (* 最大变压器数量 *)
    MAX_MOTORS : INT := 32;               (* 最大电机数量 *)
    MAX_FEEDERS : INT := 16;              (* 最大馈线数量 *)
    VOLTAGE_NOMINAL : REAL := 10000.0;    (* 额定电压 10kV *)
    FREQUENCY_NOMINAL : REAL := 50.0;     (* 标准频率 50Hz *)
    POWER_FACTOR_MIN : REAL := 0.9;       (* 最小功率因数 *)
    TEMP_WARNING : REAL := 80.0;          (* 温度警告值 °C *)
    TEMP_ALARM : REAL := 95.0;            (* 温度报警值 °C *)
    CURRENT_MAX : REAL := 1000.0;         (* 最大电流值 A *)
    POWER_MAX : REAL := 5000.0;           (* 最大功率值 kW *)
  END_CONST

  (* ============ 数据类型定义 ============ *)
  TYPE TransformerData : STRUCT
    id : INT;                    (* 变压器ID *)
    enabled : BOOL;              (* 是否启用 *)
    voltage_primary : REAL;      (* 一次电压 kV *)
    voltage_secondary : REAL;    (* 二次电压 kV *)
    current_load : REAL;         (* 负载电流 A *)
    power_output : REAL;         (* 输出功率 kW *)
    temperature : REAL;          (* 温度 °C *)
    efficiency : REAL;           (* 效率 % *)
    alarm_status : BOOL;         (* 报警状态 *)
    status_code : INT;           (* 状态代码 *)
  END_STRUCT

  TYPE MotorData : STRUCT
    id : INT;                    (* 电机ID *)
    enabled : BOOL;              (* 是否启用 *)
    running : BOOL;              (* 运行状态 *)
    speed : REAL;                (* 转速 rpm *)
    voltage : REAL;              (* 电压 V *)
    current : REAL;              (* 电流 A *)
    power_consumption : REAL;    (* 功率消耗 kW *)
    temperature : REAL;          (* 温度 °C *)
    efficiency : REAL;           (* 效率 % *)
    fault_count : INT;           (* 故障计数 *)
    last_fault_time : TIME;      (* 最后故障时间 *)
  END_STRUCT

  TYPE FeederData : STRUCT
    id : INT;                    (* 馈线ID *)
    enabled : BOOL;              (* 是否启用 *)
    voltage : REAL;              (* 电压 V *)
    current : REAL;              (* 电流 A *)
    power : REAL;                (* 功率 kW *)
    power_factor : REAL;         (* 功率因数 *)
    reactive_power : REAL;       (* 无功功率 kVar *)
    overload_flag : BOOL;        (* 过载标志 *)
    breaker_status : BOOL;       (* 断路器状态 *)
  END_STRUCT

  TYPE EnergyStatistics : STRUCT
    total_energy_consumed : REAL;        (* 总能耗 kWh *)
    peak_power : REAL;                  (* 峰值功率 kW *)
    off_peak_power : REAL;              (* 谷值功率 kW *)
    average_power : REAL;               (* 平均功率 kW *)
    power_factor_avg : REAL;            (* 平均功率因数 *)
    efficiency_avg : REAL;              (* 平均效率 % *)
    energy_saved : REAL;                (* 节省能源 kWh *)
  END_STRUCT

  (* ============ 全局变量 ============ *)
  VAR
    (* 设备数组 *)
    transformers : ARRAY[0..MAX_TRANSFORMERS-1] OF TransformerData;
    motors : ARRAY[0..MAX_MOTORS-1] OF MotorData;
    feeders : ARRAY[0..MAX_FEEDERS-1] OF FeederData;
    
    (* 系统状态 *)
    system_enabled : BOOL := TRUE;
    system_time : TIME := T#0s;
    cycle_counter : INT := 0;
    
    (* 能源统计 *)
    energy_stats : EnergyStatistics;
    
    (* 故障管理 *)
    fault_log : ARRAY[0..99] OF STRING;
    fault_count : INT := 0;
    alarm_active : BOOL := FALSE;
    
    (* 时间管理 *)
    peak_hours_start : INT := 7;     (* 峰值时段开始 7点 *)
    peak_hours_end : INT := 23;      (* 峰值时段结束 23点 *)
    is_peak_hours : BOOL := FALSE;
    total_power : REAL := 0.0;
    
  END_VAR

  (* ============ 主程序逻辑 ============ *)

  (* 初始化系统 *)
  IF cycle_counter = 0 THEN
    InitializeSystem();
  END_IF
  
  (* 周期性任务 *)
  IF cycle_counter MOD 10 = 0 THEN
    (* 每10个周期读取传感器数据 *)
    ReadSensorData();
  END_IF
  
  IF cycle_counter MOD 20 = 0 THEN
    (* 每20个周期检查变压器状态 *)
    MonitorTransformers();
  END_IF
  
  IF cycle_counter MOD 15 = 0 THEN
    (* 每15个周期检查电机状态 *)
    MonitorMotors();
  END_IF
  
  IF cycle_counter MOD 25 = 0 THEN
    (* 每25个周期更新能源统计 *)
    UpdateEnergyStatistics();
  END_IF
  
  IF cycle_counter MOD 30 = 0 THEN
    (* 每30个周期执行负荷优化 *)
    OptimizeLoadDistribution();
  END_IF
  
  (* 实时故障检测 *)
  DetectFaults();
  
  (* 控制电机启停 *)
  ControlMotors();
  
  (* 过载保护 *)
  OverloadProtection();
  
  (* 能源优化 *)
  EnergyOptimization();
  
  (* 数据输出 *)
  OutputSystemData();
  
  (* 更新周期计数器 *)
  cycle_counter := cycle_counter + 1;
  IF cycle_counter > 100 THEN
    cycle_counter := 0;
  END_IF

END_PROGRAM


(*==============================================================
  初始化程序
==============================================================*)
PROGRAM InitializeSystem

  VAR
    i : INT;
  END_VAR

  (* 初始化变压器 *)
  FOR i := 0 TO MAX_TRANSFORMERS-1 DO
    transformers[i].id := i + 1;
    transformers[i].enabled := TRUE;
    transformers[i].voltage_primary := 110.0;
    transformers[i].voltage_secondary := 10.0;
    transformers[i].current_load := 0.0;
    transformers[i].power_output := 0.0;
    transformers[i].temperature := 25.0;
    transformers[i].efficiency := 98.5;
    transformers[i].alarm_status := FALSE;
    transformers[i].status_code := 0;
  END_FOR
  
  (* 初始化电机 *)
  FOR i := 0 TO MAX_MOTORS-1 DO
    motors[i].id := i + 1;
    motors[i].enabled := TRUE;
    motors[i].running := FALSE;
    motors[i].speed := 0.0;
    motors[i].voltage := 0.0;
    motors[i].current := 0.0;
    motors[i].power_consumption := 0.0;
    motors[i].temperature := 25.0;
    motors[i].efficiency := 0.0;
    motors[i].fault_count := 0;
  END_FOR
  
  (* 初始化馈线 *)
  FOR i := 0 TO MAX_FEEDERS-1 DO
    feeders[i].id := i + 1;
    feeders[i].enabled := TRUE;
    feeders[i].voltage := 10000.0;
    feeders[i].current := 0.0;
    feeders[i].power := 0.0;
    feeders[i].power_factor := 1.0;
    feeders[i].reactive_power := 0.0;
    feeders[i].overload_flag := FALSE;
    feeders[i].breaker_status := TRUE;
  END_FOR
  
  (* 初始化能源统计 *)
  energy_stats.total_energy_consumed := 0.0;
  energy_stats.peak_power := 0.0;
  energy_stats.off_peak_power := 0.0;
  energy_stats.average_power := 0.0;
  energy_stats.power_factor_avg := 0.95;
  energy_stats.efficiency_avg := 95.0;
  energy_stats.energy_saved := 0.0;

END_PROGRAM


(*==============================================================
  读取传感器数据程序
==============================================================*)
PROGRAM ReadSensorData

  VAR
    i : INT;
    sensor_value : REAL;
  END_VAR

  (* 读取变压器传感器 *)
  FOR i := 0 TO MAX_TRANSFORMERS-1 DO
    IF transformers[i].enabled THEN
      (* 模拟读取电流 (实际应连接模拟输入) *)
      sensor_value := 200.0 + (i * 15.0);
      transformers[i].current_load := sensor_value;
      
      (* 根据电流计算输出功率: P = √3 × U × I × cosφ *)
      transformers[i].power_output := 
        1.732 * transformers[i].voltage_secondary * sensor_value * 0.95 / 1000.0;
      
      (* 模拟温度读取 *)
      transformers[i].temperature := 25.0 + (sensor_value / 50.0);
    END_IF
  END_FOR
  
  (* 读取电机传感器 *)
  FOR i := 0 TO MAX_MOTORS-1 DO
    IF motors[i].enabled AND motors[i].running THEN
      (* 模拟转速读取 *)
      motors[i].speed := 1450.0;
      
      (* 模拟电流读取 *)
      sensor_value := 50.0 + (i * 2.0);
      motors[i].current := sensor_value;
      
      (* 计算功率消耗 *)
      motors[i].power_consumption := 1.732 * 400.0 * sensor_value * 0.92 / 1000.0;
      
      (* 模拟温度 *)
      motors[i].temperature := 30.0 + (sensor_value / 10.0);
      
      (* 计算效率 *)
      motors[i].efficiency := 88.0 + (15.0 * (motors[i].speed / 1500.0));
    ELSE
      motors[i].speed := 0.0;
      motors[i].current := 0.0;
      motors[i].power_consumption := 0.0;
      motors[i].temperature := 25.0;
      motors[i].efficiency := 0.0;
    END_IF
  END_FOR
  
  (* 读取馈线传感器 *)
  FOR i := 0 TO MAX_FEEDERS-1 DO
    IF feeders[i].enabled THEN
      (* 模拟电压读取 *)
      feeders[i].voltage := 9800.0 + (i * 5.0);
      
      (* 模拟电流读取 *)
      feeders[i].current := 150.0 + (i * 20.0);
      
      (* 计算功率 *)
      feeders[i].power := 1.732 * feeders[i].voltage * feeders[i].current * 0.92 / 1000.0;
      
      (* 功率因数 *)
      feeders[i].power_factor := 0.92 + (i * 0.005);
      IF feeders[i].power_factor > 0.99 THEN
        feeders[i].power_factor := 0.99;
      END_IF
      
      (* 无功功率 *)
      feeders[i].reactive_power := feeders[i].power * 0.43;
    END_IF
  END_FOR

END_PROGRAM


(*==============================================================
  变压器监控程序
==============================================================*)
PROGRAM MonitorTransformers

  VAR
    i : INT;
  END_VAR

  FOR i := 0 TO MAX_TRANSFORMERS-1 DO
    IF transformers[i].enabled THEN
      
      (* 温度检测 *)
      IF transformers[i].temperature > TEMP_ALARM THEN
        transformers[i].alarm_status := TRUE;
        transformers[i].status_code := 2;
      ELSIF transformers[i].temperature > TEMP_WARNING THEN
        transformers[i].alarm_status := TRUE;
        transformers[i].status_code := 1;
      ELSE
        transformers[i].alarm_status := FALSE;
        transformers[i].status_code := 0;
      END_IF
      
      (* 负荷率检测 *)
      IF transformers[i].current_load > CURRENT_MAX * 0.9 THEN
        transformers[i].alarm_status := TRUE;
      END_IF
      
      (* 效率检测 *)
      IF transformers[i].efficiency < 95.0 THEN
        transformers[i].alarm_status := TRUE;
      END_IF
      
    END_IF
  END_FOR

END_PROGRAM


(*==============================================================
  电机监控程序
==============================================================*)
PROGRAM MonitorMotors

  VAR
    i : INT;
  END_VAR

  FOR i := 0 TO MAX_MOTORS-1 DO
    IF motors[i].enabled THEN
      
      (* 温度过高保护 *)
      IF motors[i].temperature > TEMP_ALARM THEN
        motors[i].running := FALSE;
        motors[i].fault_count := motors[i].fault_count + 1;
      END_IF
      
      (* 过电流保护 *)
      IF motors[i].running AND motors[i].current > CURRENT_MAX THEN
        motors[i].running := FALSE;
        motors[i].fault_count := motors[i].fault_count + 1;
      END_IF
      
      (* 异常停止检测 *)
      IF motors[i].running AND motors[i].speed < 100.0 THEN
        motors[i].fault_count := motors[i].fault_count + 1;
      END_IF
      
      (* 多次故障判定 *)
      IF motors[i].fault_count > 5 THEN
        motors[i].enabled := FALSE;
      END_IF
      
    END_IF
  END_FOR

END_PROGRAM


(*==============================================================
  能源统计更新程序
==============================================================*)
PROGRAM UpdateEnergyStatistics

  VAR
    i : INT;
    total_motors_power : REAL;
    active_motor_count : INT;
  END_VAR

  (* 计算总功率 *)
  total_power := 0.0;
  total_motors_power := 0.0;
  active_motor_count := 0;
  
  (* 累计变压器功率 *)
  FOR i := 0 TO MAX_TRANSFORMERS-1 DO
    IF transformers[i].enabled THEN
      total_power := total_power + transformers[i].power_output;
    END_IF
  END_FOR
  
  (* 累计电机功率 *)
  FOR i := 0 TO MAX_MOTORS-1 DO
    IF motors[i].enabled AND motors[i].running THEN
      total_motors_power := total_motors_power + motors[i].power_consumption;
      active_motor_count := active_motor_count + 1;
    END_IF
  END_FOR
  
  (* 更新统计数据 *)
  energy_stats.total_energy_consumed := energy_stats.total_energy_consumed + 
                                       (total_power / 360.0);
  
  IF total_power > energy_stats.peak_power THEN
    energy_stats.peak_power := total_power;
  END_IF
  
  IF total_power < energy_stats.off_peak_power OR energy_stats.off_peak_power = 0.0 THEN
    energy_stats.off_peak_power := total_power;
  END_IF
  
  (* 计算平均功率因数 *)
  energy_stats.power_factor_avg := 0.0;
  FOR i := 0 TO MAX_FEEDERS-1 DO
    IF feeders[i].enabled THEN
      energy_stats.power_factor_avg := energy_stats.power_factor_avg + 
                                       feeders[i].power_factor;
    END_IF
  END_FOR
  energy_stats.power_factor_avg := energy_stats.power_factor_avg / MAX_FEEDERS;
  
  (* 计算平均效率 *)
  IF active_motor_count > 0 THEN
    energy_stats.efficiency_avg := 0.0;
    FOR i := 0 TO MAX_MOTORS-1 DO
      IF motors[i].enabled AND motors[i].running THEN
        energy_stats.efficiency_avg := energy_stats.efficiency_avg + 
                                       motors[i].efficiency;
      END_IF
    END_FOR
    energy_stats.efficiency_avg := energy_stats.efficiency_avg / active_motor_count;
  END_IF

END_PROGRAM


(*==============================================================
  负荷优��程序
==============================================================*)
PROGRAM OptimizeLoadDistribution

  VAR
    i : INT;
    max_load_transformer : INT;
    min_load_transformer : INT;
    max_load : REAL;
    min_load : REAL;
    load_diff : REAL;
  END_VAR

  (* 找到负荷最重和最轻的变压器 *)
  max_load := 0.0;
  min_load := CURRENT_MAX;
  max_load_transformer := 0;
  min_load_transformer := 0;
  
  FOR i := 0 TO MAX_TRANSFORMERS-1 DO
    IF transformers[i].enabled THEN
      IF transformers[i].current_load > max_load THEN
        max_load := transformers[i].current_load;
        max_load_transformer := i;
      END_IF
      
      IF transformers[i].current_load < min_load THEN
        min_load := transformers[i].current_load;
        min_load_transformer := i;
      END_IF
    END_IF
  END_FOR
  
  (* 负荷均衡 *)
  load_diff := max_load - min_load;
  IF load_diff > CURRENT_MAX * 0.2 THEN
    (* 负荷差异超过20%，需要调度 *)
  END_IF
  
  (* 能源节省计算 *)
  IF energy_stats.power_factor_avg < 0.95 THEN
    energy_stats.energy_saved := energy_stats.total_energy_consumed * 
                                (0.95 - energy_stats.power_factor_avg) / 0.95;
  END_IF

END_PROGRAM


(*==============================================================
  故障检测程序
==============================================================*)
PROGRAM DetectFaults

  VAR
    i : INT;
    fault_detected : BOOL := FALSE;
  END_VAR

  fault_detected := FALSE;
  
  (* 检查变压器故障 *)
  FOR i := 0 TO MAX_TRANSFORMERS-1 DO
    IF transformers[i].enabled AND transformers[i].alarm_status THEN
      fault_detected := TRUE;
    END_IF
  END_FOR
  
  (* 检查电机故障 *)
  FOR i := 0 TO MAX_MOTORS-1 DO
    IF motors[i].enabled AND motors[i].fault_count > 0 THEN
      fault_detected := TRUE;
    END_IF
  END_FOR
  
  (* 检查馈线过载 *)
  FOR i := 0 TO MAX_FEEDERS-1 DO
    IF feeders[i].enabled THEN
      IF feeders[i].current > CURRENT_MAX * 0.95 THEN
        feeders[i].overload_flag := TRUE;
        fault_detected := TRUE;
      ELSE
        feeders[i].overload_flag := FALSE;
      END_IF
    END_IF
  END_FOR
  
  (* 更新系统警报状态 *)
  alarm_active := fault_detected;

END_PROGRAM


(*==============================================================
  电机控制程序
==============================================================*)
PROGRAM ControlMotors

  VAR
    i : INT;
  END_VAR

  FOR i := 0 TO MAX_MOTORS-1 DO
    IF motors[i].enabled THEN
      
      (* 如果设备在峰值时段过载，则关闭非关键电机 *)
      IF is_peak_hours AND total_power > POWER_MAX * 0.9 THEN
        IF i > 15 AND motors[i].running THEN
          motors[i].running := FALSE;
        END_IF
      END_IF
      
      (* 温度过高时停止 *)
      IF motors[i].temperature > TEMP_ALARM THEN
        motors[i].running := FALSE;
      END_IF
      
    END_IF
  END_FOR

END_PROGRAM


(*==============================================================
  过载保护程序
==============================================================*)
PROGRAM OverloadProtection

  VAR
    i : INT;
    total_current : REAL := 0.0;
  END_VAR

  (* 计算总电流 *)
  FOR i := 0 TO MAX_FEEDERS-1 DO
    IF feeders[i].enabled THEN
      total_current := total_current + feeders[i].current;
    END_IF
  END_FOR
  
  (* 如果总电流超过安全值，立即分断某些馈线 *)
  IF total_current > CURRENT_MAX * 0.95 THEN
    FOR i := MAX_FEEDERS-1 TO 0 BY -1 DO
      IF feeders[i].enabled AND feeders[i].breaker_status THEN
        feeders[i].breaker_status := FALSE;
        total_current := total_current - feeders[i].current;
        
        IF total_current <= CURRENT_MAX * 0.9 THEN
          EXIT;
        END_IF
      END_IF
    END_FOR
  ELSE
    (* 尝试恢复被打开的馈线 *)
    FOR i := 0 TO MAX_FEEDERS-1 DO
      IF feeders[i].enabled AND NOT feeders[i].breaker_status THEN
        IF total_current + feeders[i].current <= CURRENT_MAX * 0.9 THEN
          feeders[i].breaker_status := TRUE;
          total_current := total_current + feeders[i].current;
        END_IF
      END_IF
    END_FOR
  END_IF

END_PROGRAM


(*==============================================================
  能源优化程序
==============================================================*)
PROGRAM EnergyOptimization

  VAR
    i : INT;
    reactive_power_total : REAL;
  END_VAR

  (* 无功功率补偿 *)
  reactive_power_total := 0.0;
  FOR i := 0 TO MAX_FEEDERS-1 DO
    IF feeders[i].enabled THEN
      reactive_power_total := reactive_power_total + feeders[i].reactive_power;
    END_IF
  END_FOR
  
  (* 如果无功功率过高，需要投入无功补偿装置 *)
  IF reactive_power_total > energy_stats.average_power * 0.5 THEN
    (* 触发无功补偿 *)
  END_IF
  
  (* 削峰填谷策略 *)
  IF is_peak_hours THEN
    (* 在峰值时段，尝试关闭非必需设备 *)
    FOR i := MAX_MOTORS-1 TO (MAX_MOTORS/2) BY -1 DO
      IF motors[i].enabled AND motors[i].running THEN
        (* 关闭非关键电机 *)
      END_IF
    END_FOR
  ELSE
    (* 在谷值时段，可以启动允许的设备 *)
    FOR i := 0 TO (MAX_MOTORS/2)-1 DO
      IF motors[i].enabled AND NOT motors[i].running THEN
        IF energy_stats.average_power < POWER_MAX * 0.7 THEN
          motors[i].running := TRUE;
        END_IF
      END_IF
    END_FOR
  END_IF

END_PROGRAM


(*==============================================================
  数据输出程序
==============================================================*)
PROGRAM OutputSystemData

  VAR
    i : INT;
  END_VAR

  (* 输出系统状态数据到外部接口 *)
  (* 此处应连接到HMI、远程监控系统或数据库 *)

END_PROGRAM
