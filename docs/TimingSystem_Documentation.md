# 中央时序系统详细文档

> **系统名称**: TimingSystem + TimelineState + ActionRequest
> **版本**: 1.0
> **最后更新**: 2026-04-07

---

## 目录

1. [系统概述](#系统概述)
2. [核心概念](#核心概念)
3. [TimingSystem 详解](#timingsystem-详解)
4. [TimelineState 详解](#timelinestate-详解)
5. [ActionRequest 详解](#actionrequest-详解)
6. [系统交互流程](#系统交互流程)
7. [使用示例](#使用示例)

---

## 系统概述

### 设计目标

中央时序系统是 Godot-Microverse-predict 项目的核心控制器，负责：
- 提供全局统一的时间基准
- 协调所有 Agent 的同步活动
- 管理行动请求的缓存与执行
- 驱动课程表和日常流程

### 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│                    第一层：中央时序系统                        │
│  ├─ TimingSystem.gd      - 全局时钟 + Click触发              │
│  ├─ TimelineState.gd     - 课程表 + 行为约束                 │
│  └─ ActionRequest.gd     - 行动请求数据结构                   │
└─────────────────────────────────────────────────────────────┘
                              ↓
                    触发所有 Agent 认知循环
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                    第二层：Agent认知系统                       │
│  ├─ 感知 → 体验 → 决策 → 行动请求缓存                         │
│  └─ 提交请求到 TimingSystem                                  │
└─────────────────────────────────────────────────────────────┘
```

### 核心特性

| 特性 | 说明 |
|------|------|
| **Click周期** | 5分钟游戏时间一个周期 |
| **上升沿触发** | 所有 Agent 活动在 Click 时刻同步执行 |
| **请求缓存** | 决策和执行分离，支持复杂计划 |
| **课程表驱动** | 6节课的时间安排和行为约束 |
| **放学机制** | 17:00后只接受结束请求，17:30强制结束 |

---

## 核心概念

### Click 机制

Click 是中央时序系统的核心概念，代表一个同步时间点：

```
时间轴：  8:00    8:05    8:10    8:15    ...    17:00    17:30
          │       │       │       │              │        │
Click:    #1      #2      #3      #4      ...    #108     结束
          │       │       │       │              │
          └───────┴───────┴───────┘              └─放学阶段
              正常运行阶段
```

每个 Click 触发以下流程：
1. 执行上一个 Click 缓存的所有请求
2. 触发所有 Agent 的感知+体验+决策
3. Agent 提交新请求到缓存队列
4. 等待下一个 Click

### 游戏时间 vs 现实时间

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `CLICK_INTERVAL_MINUTES` | 5.0 | 游戏时间5分钟一个Click |
| `REAL_SECONDS_PER_GAME_MINUTE` | 1.0 | 1现实秒 = 1游戏分钟 |
| 现实时间/Click | 5秒 | 每5秒触发一个Click |
| 一天游戏时间 | 8:00-17:30 | 共9.5小时 = 570分钟 |
| 一天Click数量 | 114个 | 570/5 = 114 |
| 一天现实时间 | 约9.5分钟 | 114×5秒 |

---

## TimingSystem 详解

### 类定义

```gdscript
extends Node
class_name TimingSystem
```

### 单例访问

```gdscript
static var instance: TimingSystem

# 使用方式
if TimingSystem.instance:
    TimingSystem.instance.start_day(1)
```

### 常量定义

| 常量 | 类型 | 值 | 说明 |
|------|------|-----|------|
| `CLICK_INTERVAL_MINUTES` | float | 5.0 | Click间隔（游戏时间分钟） |
| `REAL_SECONDS_PER_GAME_MINUTE` | float | 1.0 | 现实秒/游戏分钟比例 |

### 成员变量

| 变量 | 类型 | 说明 |
|------|------|------|
| `is_running` | bool | 时序系统是否运行中 |
| `current_game_time` | float | 当前游戏时间（从0:00开始的分钟数） |
| `current_day` | int | 当前天数 |
| `click_count` | int | 当前Click计数 |
| `pending_requests` | Dictionary | 待执行请求队列 {agent_id: ActionRequest} |

### 信号定义

```gdscript
# Click触发信号（核心信号）
signal click_triggered(game_time: float, day: int, click_num: int)

# 一天开始/结束
signal day_started(day: int, start_time: float)
signal day_ended(day: int, end_time: float)

# Click前后钩子
signal before_click(game_time: float)
signal after_click(game_time: float)
```

### 函数详解

#### _init()

```gdscript
func _init()
```

**功能**: 构造函数，初始化单例实例

**调用时机**: 节点创建时自动调用

**副作用**: 设置 `instance = self`

---

#### _ready()

```gdscript
func _ready()
```

**功能**: 初始化完成回调

**调用时机**: 节点进入场景树时

**输出**: 控制台输出 "[TimingSystem] 时序系统初始化完成"

---

#### _process(delta)

```gdscript
func _process(delta: float)
```

**功能**: 主循环，每帧检查是否需要触发 Click

**输入**:
| 参数 | 类型 | 说明 |
|------|------|------|
| delta | float | 上一帧到当前帧的时间间隔（秒） |

**逻辑**:
1. 如果 `is_running == false`，直接返回
2. 计算游戏时间增量：`game_delta = delta * 60`
3. 更新 `current_game_time`
4. 检查是否越过 Click 边界（`minutes_since_last_click < game_delta`）
5. 检查是否到达 17:00（放学）
6. 检查是否到达 17:30（强制结束）

---

#### start_day()

```gdscript
func start_day(day: int = 1)
```

**功能**: 启动一天的游戏时间

**输入**:
| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| day | int | 1 | 天数编号 |

**副作用**:
- 设置 `current_day = day`
- 重置 `current_game_time = 8:00`（480分钟）
- 重置 `click_count = 0`
- 设置 `is_running = true`
- 发射 `day_started` 信号
- 触发第一个 Click

**输出**: 控制台输出 "第X天开始，时间：08:00"

**使用示例**:
```gdscript
# 开始第1天
TimingSystem.instance.start_day(1)

# 开始第2天
TimingSystem.instance.start_day(2)
```

---

#### end_day()

```gdscript
func end_day()
```

**功能**: 结束当前游戏日

**副作用**:
- 设置 `is_running = false`
- 发射 `day_ended` 信号

**输出**: 控制台输出 "第X天结束，时间：XX:XX"

---

#### _trigger_click()

```gdscript
func _trigger_click()
```

**功能**: 触发一个 Click 周期（私有方法）

**调用时机**: 
- `_process` 中检测到 Click 边界
- `start_day` 启动时

**执行流程**:
```
1. click_count += 1
2. 发射 before_click 信号
3. 调用 _execute_pending_requests()
4. 发射 click_triggered 信号（核心）
5. 发射 after_click 信号
```

**输出**: 控制台输出 Click 开始/结束标记和当前时间

---

#### _execute_pending_requests()

```gdscript
func _execute_pending_requests()
```

**功能**: 执行待处理的行动请求（私有方法）

**执行流程**:
1. 遍历 `pending_requests` 字典
2. 对每个请求，调用对应 Agent 的 `execute_action(request)`
3. 清空 `pending_requests`

**输出**: 控制台输出执行的请求数量和详情

---

#### submit_action_request()

```gdscript
func submit_action_request(agent_id: String, request: ActionRequest) -> bool
```

**功能**: Agent 提交行动请求到缓存队列

**输入**:
| 参数 | 类型 | 说明 |
|------|------|------|
| agent_id | String | 提交请求的 Agent ID |
| request | ActionRequest | 行动请求对象 |

**返回值**: 
- `true` - 提交成功
- `false` - 提交失败（系统未运行或已进入放学阶段）

**约束检查**:
- 如果 `is_running == false`，拒绝提交
- 如果当前时间 >= 17:00 且请求不是结束类行动，拒绝提交

**副作用**: 将请求添加到 `pending_requests[agent_id]`

**输出**: 控制台输出提交结果

**使用示例**:
```gdscript
var request = ActionRequest.new("StudentXiaoming", ActionRequest.ActionType.MOVE_TO_RANGE)
request.target_id = "食堂"
var success = TimingSystem.instance.submit_action_request("StudentXiaoming", request)
```

---

#### _enter_after_school_phase()

```gdscript
func _enter_after_school_phase()
```

**功能**: 进入放学阶段（17:00-17:30）（私有方法）

**触发条件**: 当前时间 >= 17:00 且 < 17:30

**行为**: 
- 只接受结束类请求（EXIT_DIALOGUE, END_SPORTS, END_STUDY）
- 拒绝新的开始类请求

**输出**: 控制台输出放学阶段提示

---

#### _force_end_day()

```gdscript
func _force_end_day()
```

**功能**: 强制结束一天（17:30）（私有方法）

**触发条件**: 当前时间 >= 17:30

**执行流程**:
1. 强制结束所有 Agent 的当前活动
2. 调用 `end_day()`

**输出**: 控制台输出强制结束提示

---

#### format_time()

```gdscript
func format_time(minutes: float) -> String
```

**功能**: 将分钟数格式化为 HH:MM 字符串

**输入**:
| 参数 | 类型 | 说明 |
|------|------|------|
| minutes | float | 从0:00开始的分钟数 |

**返回值**: 格式化时间字符串，如 "08:30"

**使用示例**:
```gdscript
var time_str = TimingSystem.instance.format_time(510.0)  # 返回 "08:30"
```

---

#### get_current_period()

```gdscript
func get_current_period() -> String
```

**功能**: 获取当前时段类型

**返回值**:
| 返回值 | 说明 | 时间范围 |
|--------|------|----------|
| "before_school" | 到校前 | < 8:00 |
| "morning_class" | 上午课程 | 8:00-12:00 |
| "lunch_break" | 午休 | 12:00-14:00 |
| "afternoon_class" | 下午课程 | 14:00-17:00 |
| "after_school" | 放学阶段 | 17:00-17:30 |
| "day_ended" | 已结束 | >= 17:30 |

---

## TimelineState 详解

### 类定义

```gdscript
extends Node
class_name TimelineState
```

### 单例访问

```gdscript
# TimelineState 作为 TimingSystem 的子节点
# 通过 TimingSystem.instance.get_node("TimelineState") 访问
# 或直接在场景树中引用
```

### 常量定义

```gdscript
const SCHEDULE = {
    8.0:   {"subject": "班主任课", "room": "教室（主教学区）", "type": "class"},
    8.916: {"subject": "英语课",   "room": "教室（主教学区）", "type": "class"},
    9.833: {"subject": "小组讨论", "room": "教室（小组讨论区）", "type": "discussion"},
    10.75: {"subject": "午休",     "room": "食堂", "type": "break"},
    11.75: {"subject": "数学课",   "room": "教室（主教学区）", "type": "class"},
    12.666:{"subject": "体育活动", "room": "体育馆", "type": "activity"}
}
```

### 成员变量

| 变量 | 类型 | 说明 |
|------|------|------|
| `current_period` | String | 当前时段类型 |
| `current_subject` | String | 当前课程/活动名称 |
| `current_room` | String | 当前应所在的场景 |
| `is_class_time` | bool | 是否上课时间 |

### 函数详解

#### _ready()

```gdscript
func _ready()
```

**功能**: 初始化，连接 TimingSystem 信号

**副作用**: 连接 `TimingSystem.instance.click_triggered` 到 `_on_click`

---

#### _on_click()

```gdscript
func _on_click(game_time: float, day: int, click_num: int)
```

**功能**: Click 触发回调

**输入**:
| 参数 | 类型 | 说明 |
|------|------|------|
| game_time | float | 当前游戏时间（分钟） |
| day | int | 当前天数 |
| click_num | int | Click 计数 |

**副作用**: 调用 `update_state(game_time)`

---

#### update_state()

```gdscript
func update_state(game_time: float)
```

**功能**: 根据游戏时间更新当前状态

**输入**:
| 参数 | 类型 | 说明 |
|------|------|------|
| game_time | float | 当前游戏时间（分钟） |

**执行逻辑**:
1. 将分钟转换为小时
2. 在 SCHEDULE 中查找当前课程
3. 更新 `current_subject`, `current_room`, `is_class_time`, `current_period`

---

#### get_constraints()

```gdscript
func get_constraints() -> Dictionary
```

**功能**: 获取当前时段的行为约束

**返回值** (Dictionary):
| 键 | 类型 | 说明 |
|----|------|------|
| `can_speak_freely` | bool | 是否可以自由发言 |
| `can_leave_room` | bool | 是否可以离开当前场景 |
| `must_follow_teacher` | bool | 是否必须跟随教师指令 |
| `can_start_dialogue` | bool | 是否可以开始对话 |
| `description` | String | 约束描述文本 |

**不同时段的约束**:

| 时段 | can_speak_freely | can_leave_room | must_follow_teacher | can_start_dialogue |
|------|------------------|----------------|---------------------|-------------------|
| class_time | false | false | true | false |
| break_time | true | true | false | true |
| activity_time | true | false | true | true |
| free_time | true | true | false | true |

**使用示例**:
```gdscript
var constraints = TimelineState.instance.get_constraints()
if constraints.can_start_dialogue:
    # 可以开始对话
    pass
```

---

## ActionRequest 详解

### 类定义

```gdscript
class_name ActionRequest
```

### 枚举定义

```gdscript
enum ActionType {
    MOVE_TO_RANGE,      # 0 - 移动到指定中范围
    START_DIALOGUE,     # 1 - 开始对话
    START_WHISPER,      # 2 - 开始悄悄话
    JOIN_DIALOGUE,      # 3 - 加入对话
    EXIT_DIALOGUE,      # 4 - 退出对话
    START_SPORTS,       # 5 - 开始体育活动
    END_SPORTS,         # 6 - 结束体育活动
    START_STUDY,        # 7 - 开始自习
    END_STUDY,          # 8 - 结束自习
    WAIT                # 9 - 等待
}
```

### 成员变量

| 变量 | 类型 | 说明 |
|------|------|------|
| `agent_id` | String | 执行请求的 Agent ID |
| `action_type` | ActionType | 行动类型 |
| `target_id` | String | 目标 Agent ID（对话用） |
| `target_range_id` | String | 目标中范围 ID（移动用） |
| `target_position` | Vector2 | 目标位置坐标（移动用） |
| `cached_step2` | ActionRequest | 第二步缓存（可选） |
| `timestamp` | float | 请求提交时间戳 |
| `is_end_action` | bool | 是否是结束类行动 |

### 构造函数

```gdscript
func _init(p_agent_id: String, p_action_type: ActionType)
```

**输入**:
| 参数 | 类型 | 说明 |
|------|------|------|
| p_agent_id | String | Agent ID |
| p_action_type | ActionType | 行动类型 |

**初始化逻辑**:
- 设置 `agent_id` 和 `action_type`
- 设置 `timestamp = Time.get_unix_time_from_system()`
- 根据 `action_type` 自动设置 `is_end_action`

**结束类行动判断**:
```gdscript
is_end_action = (p_action_type in [ActionType.EXIT_DIALOGUE, 
                                   ActionType.END_SPORTS, 
                                   ActionType.END_STUDY])
```

### 使用示例

```gdscript
# 创建移动请求
var move_request = ActionRequest.new("StudentXiaoming", ActionRequest.ActionType.MOVE_TO_RANGE)
move_request.target_id = "食堂"

# 创建对话请求（带第二步缓存）
var dialogue_request = ActionRequest.new("StudentXiaoming", ActionRequest.ActionType.START_DIALOGUE)
dialogue_request.target_id = "StudentXiaohong"

# 缓存第二步（移动到目标附近）
dialogue_request.cached_step2 = ActionRequest.new("StudentXiaoming", ActionRequest.ActionType.MOVE_TO_RANGE)
dialogue_request.cached_step2.target_id = "StudentXiaohong"

# 提交请求
TimingSystem.instance.submit_action_request("StudentXiaoming", dialogue_request)
```

---

## 系统交互流程

### 完整一天流程

```
08:00 游戏日开始
    │
    ▼
[start_day() 被调用]
    │
    ├── 初始化状态
    ├── 发射 day_started 信号
    └── 触发 Click #1
            │
            ▼
    [Click #1 执行]
            │
            ├── _execute_pending_requests() 
            │   └── (无待处理请求，第一次)
            │
            ├── 发射 click_triggered 信号
            │       │
            │       ▼
            │   [所有 Agent 接收信号]
            │       │
            │       ├── Agent A: 感知 → 体验 → 决策
            │       │       └── 提交请求: MOVE_TO_RANGE
            │       │
            │       ├── Agent B: 感知 → 体验 → 决策
            │       │       └── 提交请求: START_STUDY
            │       │
            │       └── Agent C: 感知 → 体验 → 决策
            │               └── 提交请求: WAIT
            │
            └── 请求缓存到 pending_requests
                        │
08:05 Click #2        ▼
    │
    ▼
[Click #2 执行]
    │
    ├── _execute_pending_requests()
    │   ├── 执行 Agent A: MOVE_TO_RANGE
    │   ├── 执行 Agent B: START_STUDY
    │   └── 执行 Agent C: WAIT
    │
    ├── 发射 click_triggered 信号
    │       └── [Agent 新一轮决策...]
    │
    └── 新请求缓存...
            │
            │ (重复直到 17:00)
            ▼
17:00 放学阶段
    │
    ▼
[_enter_after_school_phase()]
    │
    └── 只接受结束类请求
            │
17:30 强制结束
    │
    ▼
[_force_end_day()]
    │
    ├── 强制结束所有 Agent 活动
    └── 调用 end_day()
            │
            ▼
    发射 day_ended 信号
```

### Agent 与 TimingSystem 交互

```gdscript
# Agent 连接信号
func _ready():
    TimingSystem.instance.click_triggered.connect(_on_click_triggered)

# Click 触发回调
func _on_click_triggered(game_time: float, day: int, click_num: int):
    # 1. 如果有缓存请求，执行它
    if is_waiting_execution and cached_request:
        _execute_cached_request()
        return
    
    # 2. 否则开始新的认知循环
    _perform_cognitive_cycle()

# 认知循环
func _perform_cognitive_cycle():
    # 感知
    var perception = _perceive()
    
    # 体验（如果有上一周期活动）
    if not last_activity.is_empty():
        _experience(last_activity)
    
    # 决策
    var request = _make_decision(perception)
    
    # 提交请求
    _submit_request(request)

# 提交请求
func _submit_request(request: ActionRequest):
    cached_request = request
    is_waiting_execution = true
    TimingSystem.instance.submit_action_request(character.name, request)
```

---

## 使用示例

### 示例1：启动时序系统

```gdscript
# 在 School.tscn 的 _ready() 中
func _ready():
    # 等待所有系统初始化
    await get_tree().create_timer(1.0).timeout
    
    # 启动第1天
    TimingSystem.instance.start_day(1)
```

### 示例2：监听 Click 信号

```gdscript
# 在调试面板中
func _ready():
    TimingSystem.instance.click_triggered.connect(_on_click)
    TimingSystem.instance.day_ended.connect(_on_day_end)

func _on_click(game_time: float, day: int, click_num: int):
    print("Click #%d, 时间: %s" % [click_num, 
        TimingSystem.instance.format_time(game_time)])

func _on_day_end(day: int, end_time: float):
    print("第%d天结束" % day)
```

### 示例3：获取当前约束

```gdscript
# 在 Agent 决策时
func _make_decision(perception: Dictionary) -> ActionRequest:
    # 获取当前行为约束
    var constraints = TimelineState.instance.get_constraints()
    
    # 根据约束调整决策
    if not constraints.can_start_dialogue:
        # 上课时间不能开始对话
        return ActionRequest.new(agent_id, ActionRequest.ActionType.WAIT)
    
    # 正常决策...
```

### 示例4：创建复杂行动序列

```gdscript
# Agent 想先移动，然后开始对话
func _create_complex_request() -> ActionRequest:
    # 第一步：移动
    var step1 = ActionRequest.new("AgentA", ActionRequest.ActionType.MOVE_TO_RANGE)
    step1.target_id = "食堂"
    
    # 第二步：开始对话（缓存）
    step1.cached_step2 = ActionRequest.new("AgentA", ActionRequest.ActionType.START_DIALOGUE)
    step1.cached_step2.target_id = "AgentB"
    
    return step1
```

---

## 注意事项

1. **单例模式**: TimingSystem 使用静态变量 `instance` 实现单例，确保全局唯一

2. **信号连接**: Agent 应在 `_ready()` 中连接 `click_triggered` 信号，确保时序系统已初始化

3. **请求提交**: 必须在 Click 触发后的决策阶段提交请求，否则会被延迟到下一个 Click

4. **放学约束**: 17:00后只接受结束类请求，Agent 应注意检查返回值

5. **时间格式**: `current_game_time` 使用分钟为单位，从0:00开始计算

---

*文档维护者：百舟楫*
*最后更新：2026-04-07*
