# 重构实施计划：从中央时序系统开始

> **阶段一：中央时序系统搭建**
> **目标**：建立全局时钟和上升沿触发机制

---

## 第一步：创建 TimingSystem.gd（核心控制器）

### 1.1 基础结构

```gdscript
# script/system/TimingSystem.gd
extends Node
class_name TimingSystem

# 单例模式
static var instance: TimingSystem

# 时间配置
const CLICK_INTERVAL_MINUTES: float = 5.0  # 游戏时间5分钟
const REAL_SECONDS_PER_GAME_MINUTE: float = 1.0  # 1现实秒 = 1游戏分钟

# 状态
var is_running: bool = false
var current_game_time: float = 8.0 * 60.0  # 从8:00开始（分钟）
var current_day: int = 1
var click_count: int = 0

# 信号
signal click_triggered(game_time: float, day: int, click_num: int)
signal day_started(day: int, start_time: float)
signal day_ended(day: int, end_time: float)
signal before_click(game_time: float)
signal after_click(game_time: float)

# 请求队列
var pending_requests: Dictionary = {}  # agent_id -> ActionRequest

func _init():
    instance = self

func _ready():
    print("[TimingSystem] 时序系统初始化完成")

# 启动时序系统
func start_day(day: int = 1):
    current_day = day
    current_game_time = 8.0 * 60.0  # 8:00
    click_count = 0
    is_running = true
    
    day_started.emit(current_day, current_game_time)
    print("[TimingSystem] 第%d天开始，时间：%s" % [current_day, format_time(current_game_time)])
    
    # 第一次Click（8:00统一感知+决策）
    _trigger_click()

# 停止时序系统
func end_day():
    is_running = false
    day_ended.emit(current_day, current_game_time)
    print("[TimingSystem] 第%d天结束，时间：%s" % [current_day, format_time(current_game_time)])

# 主循环
func _process(delta: float):
    if not is_running:
        return
    
    # 更新游戏时间
    var game_delta = delta * (60.0 / REAL_SECONDS_PER_GAME_MINUTE)
    current_game_time += game_delta
    
    # 检查是否到达Click时刻
    var minutes_since_last_click = fmod(current_game_time, CLICK_INTERVAL_MINUTES)
    if minutes_since_last_click < game_delta:  # 刚越过5分钟边界
        _trigger_click()
    
    # 检查是否到达17:00（放学时间）
    if current_game_time >= 17.0 * 60.0 and current_game_time < 17.5 * 60.0:
        _enter_after_school_phase()
    
    # 检查是否到达17:30（强制结束）
    if current_game_time >= 17.5 * 60.0:
        _force_end_day()

# 触发Click（上升沿）
func _trigger_click():
    click_count += 1
    
    print("\n[TimingSystem] ===== CLICK #%d =====" % click_count)
    print("[TimingSystem] 游戏时间：%s" % format_time(current_game_time))
    
    before_click.emit(current_game_time)
    
    # 1. 批准并执行所有待处理请求
    _execute_pending_requests()
    
    # 2. 触发所有Agent的感知+体验+决策
    click_triggered.emit(current_game_time, current_day, click_count)
    
    after_click.emit(current_game_time)
    
    print("[TimingSystem] ===== CLICK END =====\n")

# 执行待处理请求
func _execute_pending_requests():
    if pending_requests.is_empty():
        print("[TimingSystem] 无待处理请求")
        return
    
    print("[TimingSystem] 执行 %d 个待处理请求" % pending_requests.size())
    
    for agent_id in pending_requests.keys():
        var request = pending_requests[agent_id]
        print("[TimingSystem] 执行请求：%s -> %s" % [agent_id, request.action_type])
        
        # 调用Agent执行行动
        var agent = AgentManager.get_agent(agent_id)
        if agent:
            agent.execute_action(request)
    
    # 清空请求队列
    pending_requests.clear()

# Agent提交行动请求
func submit_action_request(agent_id: String, request: ActionRequest) -> bool:
    if not is_running:
        print("[TimingSystem] 错误：时序系统未运行")
        return false
    
    # 17:00后不接受新的开始请求
    if current_game_time >= 17.0 * 60.0 and not request.is_end_action:
        print("[TimingSystem] %s 的请求被拒绝：已进入放学阶段" % agent_id)
        return false
    
    pending_requests[agent_id] = request
    print("[TimingSystem] %s 提交请求：%s" % [agent_id, request.action_type])
    return true

# 进入放学阶段（17:00-17:30）
func _enter_after_school_phase():
    print("[TimingSystem] 进入放学阶段（17:00-17:30）")
    print("[TimingSystem] 只接受结束请求，不接受开始请求")

# 强制结束一天（17:30）
func _force_end_day():
    print("[TimingSystem] 强制结束当前活动")
    
    # 强制结束所有Agent的当前活动
    for agent in AgentManager.get_all_agents():
        agent.force_end_current_activity()
    
    end_day()

# 格式化时间显示
func format_time(minutes: float) -> String:
    var h = int(minutes / 60)
    var m = int(fmod(minutes, 60))
    return "%02d:%02d" % [h, m]

# 获取当前时段类型
func get_current_period() -> String:
    var hour = current_game_time / 60.0
    
    if hour < 8.0:
        return "before_school"
    elif hour < 12.0:
        return "morning_class"
    elif hour < 14.0:
        return "lunch_break"
    elif hour < 17.0:
        return "afternoon_class"
    elif hour < 17.5:
        return "after_school"
    else:
        return "day_ended"
```

### 1.2 行动请求数据结构

```gdscript
# script/data/ActionRequest.gd
class_name ActionRequest

enum ActionType {
    MOVE_TO_RANGE,           # 移动到指定中范围
    START_DIALOGUE,          # 开始对话
    JOIN_DIALOGUE,           # 加入对话
    EXIT_DIALOGUE,           # 退出对话
    START_SPORTS,            # 开始体育活动
    END_SPORTS,              # 结束体育活动
    START_STUDY,             # 开始自习
    END_STUDY,               # 结束自习
    WAIT                     # 等待（无行动）
}

var agent_id: String
var action_type: ActionType
var target_id: String           # 目标AgentID（对话用）
var target_range_id: String     # 目标中范围ID（移动用）
var target_position: Vector2    # 目标位置（移动用）
var cached_step2: ActionRequest # 第二步缓存（可选）
var timestamp: float            # 请求提交时间
var is_end_action: bool         # 是否是结束类行动

func _init(p_agent_id: String, p_action_type: ActionType):
    agent_id = p_agent_id
    action_type = p_action_type
    timestamp = Time.get_unix_time_from_system()
    is_end_action = (p_action_type in [ActionType.EXIT_DIALOGUE, 
                                       ActionType.END_SPORTS, 
                                       ActionType.END_STUDY])
```

---

## 第二步：修改 School.tscn 添加 TimingSystem

在场景根节点下添加 TimingSystem：

```gdscript
[node name="TimingSystem" type="Node" parent="."]
script = ExtResource("xx_xxxxx")  # TimingSystem.gd

[node name="TimelineState" type="Node" parent="TimingSystem"]
script = ExtResource("xx_xxxxx")  # TimelineState.gd

[node name="ActivityManager" type="Node" parent="TimingSystem"]
script = ExtResource("xx_xxxxx")  # ActivityManager.gd
```

---

## 第三步：创建 TimelineState.gd（时间轴状态）

```gdscript
# script/system/TimelineState.gd
extends Node
class_name TimelineState

# 课程表配置
const SCHEDULE = {
    8.0: {"subject": "班主任课", "room": "教室（主教学区）", "type": "class"},
    8.916: {"subject": "英语课", "room": "教室（主教学区）", "type": "class"},
    9.833: {"subject": "小组讨论", "room": "教室（小组讨论区）", "type": "discussion"},
    10.75: {"subject": "午休", "room": "食堂", "type": "break"},
    11.75: {"subject": "数学课", "room": "教室（主教学区）", "type": "class"},
    12.666: {"subject": "体育活动", "room": "体育馆", "type": "activity"}
}

# 当前状态
var current_period: String = ""
var current_subject: String = ""
var current_room: String = ""
var is_class_time: bool = false

func _ready():
    TimingSystem.instance.click_triggered.connect(_on_click)

func _on_click(game_time: float, day: int, click_num: int):
    update_state(game_time)

func update_state(game_time: float):
    var hour = game_time / 60.0
    
    # 查找当前课程
    var current_schedule = null
    var schedule_hours = SCHEDULE.keys()
    schedule_hours.sort()
    
    for i in range(schedule_hours.size()):
        var schedule_hour = schedule_hours[i]
        var next_hour = schedule_hours[i + 1] if i + 1 < schedule_hours.size() else 17.0
        
        if hour >= schedule_hour and hour < next_hour:
            current_schedule = SCHEDULE[schedule_hour]
            break
    
    if current_schedule:
        current_subject = current_schedule.subject
        current_room = current_schedule.room
        is_class_time = (current_schedule.type == "class")
        
        if is_class_time:
            current_period = "class_time"
        elif current_schedule.type == "break":
            current_period = "break_time"
        else:
            current_period = "activity_time"
    else:
        current_period = "free_time"
        current_subject = ""
        current_room = ""
        is_class_time = false

# 获取当前行为约束
func get_constraints() -> Dictionary:
    match current_period:
        "class_time":
            return {
                "can_speak_freely": false,
                "can_leave_room": false,
                "must_follow_teacher": true,
                "can_start_dialogue": false,
                "description": "上课时间，需遵守课堂纪律"
            }
        "break_time":
            return {
                "can_speak_freely": true,
                "can_leave_room": true,
                "must_follow_teacher": false,
                "can_start_dialogue": true,
                "description": "午休时间，可自由活动"
            }
        "activity_time":
            return {
                "can_speak_freely": true,
                "can_leave_room": false,
                "must_follow_teacher": true,
                "can_start_dialogue": true,
                "description": "活动时间，在指定场景内活动"
            }
        _:
            return {
                "can_speak_freely": true,
                "can_leave_room": true,
                "must_follow_teacher": false,
                "can_start_dialogue": true,
                "description": "自由时间"
            }
```

---

## 第四步：测试时序系统

创建测试脚本：

```gdscript
# test_timing_system.gd
extends Node

func _ready():
    # 等待所有系统初始化
    await get_tree().create_timer(1.0).timeout
    
    # 启动时序系统
    TimingSystem.instance.start_day(1)
    
    # 连接信号用于调试
    TimingSystem.instance.click_triggered.connect(_on_click)
    TimingSystem.instance.day_ended.connect(_on_day_end)

func _on_click(game_time: float, day: int, click_num: int):
    print("\n[Test] 收到Click信号 #%d" % click_num)
    print("[Test] 当前时段：%s" % TimelineState.instance.current_period)
    print("[Test] 当前课程：%s" % TimelineState.instance.current_subject)

func _on_day_end(day: int, end_time: float):
    print("\n[Test] 第%d天结束" % day)
```

---

## 实施检查清单

### Step 1: 创建基础文件
- [ ] `script/system/TimingSystem.gd`
- [ ] `script/data/ActionRequest.gd`
- [ ] `script/system/TimelineState.gd`

### Step 2: 修改场景
- [ ] 在 School.tscn 添加 TimingSystem 节点
- [ ] 配置脚本引用

### Step 3: 测试验证
- [ ] 启动游戏，观察Click触发
- [ ] 验证时间推进（5分钟间隔）
- [ ] 验证17:00进入放学阶段
- [ ] 验证17:30强制结束

### Step 4: 集成准备
- [ ] 确认信号连接正常
- [ ] 准备与Agent系统的接口

---

**预计完成时间**: 2-3小时
**下一步**: 搭建完成后，开始重构AIAgent的感知-体验-决策循环

需要我开始编写这些代码吗？
