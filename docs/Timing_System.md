# Timing System 技术文档

> **系统名称**: TimingSystem + TimelineState + ActivityManager
> **版本**: 2.0
> **最后更新**: 2026-04-08

---

## 目录

1. [系统概述](#1-系统概述)
2. [核心概念](#2-核心概念)
3. [TimingSystem 详解](#3-timingsystem-详解)
4. [TimelineState 详解](#4-timelinestate-详解)
5. [ActivityManager 详解](#5-activitymanager-详解)
6. [V2时序逻辑](#6-v2时序逻辑)
7. [系统交互流程](#7-系统交互流程)
8. [使用示例](#8-使用示例)

---

## 1. 系统概述

### 1.1 设计目标

时序系统是 Godot-Microverse-predict 项目的核心控制器，负责：
- 提供全局统一的时间基准
- 协调所有 Agent 的同步活动
- 管理活动生命周期和奖赏计算
- 驱动课程表和日常流程
- **V2新增**: 活动中持续决策（体验+决策）

### 1.2 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│                    第一层：时序系统                            │
│  ├─ TimingSystem.gd      - 全局时钟 + Click触发              │
│  ├─ TimelineState.gd     - 课程表 + 行为约束                 │
│  └─ ActivityManager.gd   - 活动生命周期 + 奖赏计算            │
└─────────────────────────────────────────────────────────────┘
                              ↓
                    触发所有 Agent 认知循环
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                    第二层：Agent认知系统                       │
│  ├─ 感知 → 体验 → 决策 → 提交协调器                          │
│  └─ 执行活动序列                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.3 核心特性

| 特性 | 说明 |
|------|------|
| **Click周期** | 5分钟游戏时间一个周期 |
| **上升沿触发** | 所有 Agent 活动在 Click 时刻同步执行 |
| **V2协调器** | 自然语言决策 + LLM活动分配 |
| **活动中决策** | 每次Click都可决策继续/停止/更换 |
| **累积奖赏** | 活动收益随时间累积计算 |
| **课程表驱动** | 6节课的时间安排和行为约束 |
| **放学机制** | 17:00后只接受结束请求，17:30强制结束 |

---

## 2. 核心概念

### 2.1 Click 机制

Click 是时序系统的核心概念，代表一个同步时间点：

```
时间轴：  8:00    8:05    8:10    8:15    ...    17:00    17:30
          │       │       │       │              │        │
Click:    #1      #2      #3      #4      ...    #108     结束
          │       │       │       │              │
          └───────┴───────┴───────┘              └─放学阶段
              正常运行阶段
```

每个 Click 触发以下流程：
1. ActivityManager 更新所有活动状态（累积奖赏）
2. 触发所有 Agent 的感知+体验+决策
3. Agent 生成自然语言决策
4. ActivityCoordinator 协调分配活动序列
5. Agent 接收并缓存活动序列

### 2.2 游戏时间 vs 现实时间

| 配置项 | 值 | 说明 |
|--------|-----|------|
| `CLICK_INTERVAL_MINUTES` | 5.0 | 游戏时间5分钟一个Click |
| `REAL_SECONDS_PER_GAME_MINUTE` | 1.0 | 1现实秒 = 1游戏分钟 |
| 现实时间/Click | 5秒 | 每5秒触发一个Click |
| 一天游戏时间 | 8:00-17:30 | 共9.5小时 = 570分钟 |
| 一天Click数量 | 114个 | 570/5 = 114 |
| 一天现实时间 | 约9.5分钟 | 114×5秒 |

### 2.3 V1 vs V2 时序对比

```
V1流程（离散决策）:
Click #1: 感知 → 决策 → 开始听课(等待)
         ↓
Click #2: 体验(5分钟) → 决策 → 继续等待
         ↓
Click #3: 体验(10分钟) → 决策 → 停止活动

V2流程（持续决策）:
Click #1: 感知 → 决策 → 开始听课(ActivityManager记录)
         ↓
Click #2: 体验(累积5分钟) → 决策(继续/停止/更换) → 继续听课
         ↓
Click #3: 体验(累积10分钟) → 决策(继续/停止/更换) → 停止活动
         ↓
Click #4: 感知 → 决策 → 开始新活动
```

| 方面 | V1 | V2 |
|------|-----|-----|
| 决策方式 | 结构化JSON | 自然语言描述 |
| 协调方式 | TimingSystem缓存 | ActivityCoordinator LLM协调 |
| 活动中决策 | 不支持 | 支持（每次Click） |
| 活动缓存 | 1步 | 3步 |
| 奖赏计算 | 离散 | 累积 |

---

## 3. TimingSystem 详解

### 3.1 类定义

```gdscript
extends Node
class_name TimingSystem
```

### 3.2 单例访问

```gdscript
static var instance: TimingSystem

# 使用方式
if TimingSystem.instance:
    TimingSystem.instance.start_day(1)
```

### 3.3 常量定义

| 常量 | 类型 | 值 | 说明 |
|------|------|-----|------|
| `CLICK_INTERVAL_MINUTES` | float | 5.0 | Click间隔（游戏时间分钟） |
| `REAL_SECONDS_PER_GAME_MINUTE` | float | 1.0 | 现实秒/游戏分钟比例 |

### 3.4 成员变量

| 变量 | 类型 | 说明 |
|------|------|------|
| `is_running` | bool | 时序系统是否运行中 |
| `current_game_time` | float | 当前游戏时间（分钟） |
| `current_day` | int | 当前天数 |
| `click_count` | int | 当前Click计数 |

### 3.5 信号定义

```gdscript
signal click_triggered(game_time: float, day: int, click_num: int)
signal day_started(day: int, start_time: float)
signal day_ended(day: int, end_time: float)
signal before_click(game_time: float)
signal after_click(game_time: float)
```

### 3.6 核心函数

#### start_day()

```gdscript
func start_day(day: int = 1)
```

**功能**: 启动一天的游戏时间

**副作用**:
- 设置 `current_day = day`
- 重置 `current_game_time = 8:00`
- 重置 `click_count = 0`
- 设置 `is_running = true`
- 触发第一个 Click

---

#### _trigger_click()

```gdscript
func _trigger_click()
```

**功能**: 触发一个 Click 周期

**V2执行流程**:
```
1. click_count += 1
2. 发射 before_click 信号
3. ActivityManager._on_click_triggered() - 更新活动状态
4. 发射 click_triggered 信号 - Agent开始决策
5. 等待 0.5秒 - Agent提交决策
6. ActivityCoordinator.execute_coordination() - LLM协调
7. 发射 after_click 信号
```

---

#### format_time()

```gdscript
func format_time(minutes: float) -> String
```

**功能**: 将分钟数格式化为 HH:MM

**返回值**: 如 "08:30"

---

## 4. TimelineState 详解

### 4.1 类定义

```gdscript
extends Node
class_name TimelineState
```

### 4.2 课程表定义

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

### 4.3 核心函数

#### get_constraints()

```gdscript
func get_constraints() -> Dictionary
```

**返回值**:
| 键 | 类型 | 说明 |
|----|------|------|
| `can_speak_freely` | bool | 是否可以自由发言 |
| `can_leave_room` | bool | 是否可以离开场景 |
| `must_follow_teacher` | bool | 是否必须跟随教师 |
| `can_start_dialogue` | bool | 是否可以开始对话 |
| `description` | String | 约束描述 |

---

## 5. ActivityManager 详解

### 5.1 类定义

```gdscript
extends Node
class_name ActivityManager
```

### 5.2 核心属性

```gdscript
static var instance: ActivityManager
var registered_activities: Dictionary  # {activity_type: Activity}
var scene_activity_map: Dictionary     # 场景-活动映射
var agent_activities: Dictionary       # {agent_id: ActivityRecord}
```

### 5.3 活动记录类

```gdscript
class ActivityRecord:
    var agent_id: String
    var activity_type: ActivityType
    var start_time: float          # 游戏时间（分钟）
    var last_click_time: float     # 上次Click时间
    var total_duration: float      # 总持续时间
    var current_duration: float    # 本次Click持续时间
    var context: Dictionary        # 活动上下文
```

### 5.4 核心函数

#### start_activity()

```gdscript
func start_activity(agent_id: String, activity_type: ActivityType, context: Dictionary = {}) -> bool
```

**输入**:
- `agent_id`: Agent标识
- `activity_type`: 活动类型
- `context`: {room_name, focus_level, ...}

**返回值**: bool 是否成功

---

#### end_activity()

```gdscript
func end_activity(agent_id: String, reason: String = "") -> Dictionary
```

**返回值**: {agent_id, activity_type, total_duration, final_gain, reason}

---

#### _on_click_triggered()

```gdscript
func _on_click_triggered(game_time: float, day: int, click_num: int)
```

**功能**: Click触发时更新所有活动状态

**执行逻辑**:
1. 遍历所有活动中的Agent
2. 计算本次Click持续时间
3. 累积总持续时间
4. 计算累积收益 G(t)
5. 发放增量奖赏
6. 发射 activity_updated 信号

---

## 6. V2时序逻辑

### 6.1 活动中持续决策

**核心改进**: Agent开始活动后，每次Click都可决策继续/停止/更换

**实现流程**:
```
Agent._on_click_triggered()
    │
    ├── 检查是否有活动缓存 → 执行下一步
    │
    ├── 检查ActivityManager是否有活动 → _perform_activity_update()
    │       │
    │       ├── _experience_current_activity() - 获取累积奖赏
    │       ├── _perceive() - 更新环境感知
    │       ├── _make_activity_decision() - MVT+LLM决策
    │       │       │
    │       │       ├── 计算MVT最优停留时间
    │       │       ├── 检查是否达到最优时间
    │       │       └── LLM确认决策
    │       │
    │       └── _execute_activity_decision()
    │               ├── continue: 无操作
    │               ├── stop: end_activity() → 新决策周期
    │               └── switch: end_activity() → 新决策周期
    │
    └── 空闲状态 → _perform_v2_cognitive_cycle()
            │
            ├── _perceive()
            ├── _experience()
            ├── _make_natural_decision() - 生成自然语言描述
            └── _submit_decision_to_coordinator()
```

### 6.2 决策Prompt示例

```
你是StudentXiaoming，正在进行上课。

【当前活动状态】
- 活动类型：上课
- 已持续时间：10.0分钟
- 累积收益：0.725
- 感知情境收益：45%
- 感知衰减速度：55%

【MVT模型建议】
已停留10.0分钟，达到MVT预测的最优时间(10.2分钟)
建议：停止活动

【当前环境】
- 当前场景：教室（主教学区）
- 附近角色：2人

请决定：
1. CONTINUE - 继续当前活动
2. STOP - 停止当前活动，转为空闲
3. SWITCH - 更换为其他活动
```

---

## 7. 系统交互流程

### 7.1 完整V2流程

```
08:00 游戏日开始
    │
    ▼
[start_day()]
    │
    ├── 初始化状态
    ├── 发射 day_started 信号
    └── 触发 Click #1
            │
            ▼
    [Click #1 执行]
            │
            ├── ActivityManager._on_click_triggered()
            │   └── (无活动，第一次)
            │
            ├── 发射 click_triggered 信号
            │       │
            │       ▼
            │   [所有 Agent]
            │       │
            │       ├── 感知 → 体验 → _make_natural_decision()
            │       │       └── "我想去图书馆自习数学"
            │       │
            │       └── submit_decision_to_coordinator()
            │
            ├── 等待 0.5秒
            │
            ├── ActivityCoordinator.execute_coordination()
            │       │
            │       ├── 收集所有决策
            │       ├── 调用LLM分配活动
            │       └── 下发活动序列
            │
            └── Agent.receive_activity_sequence()
                        │
08:05 Click #2        ▼
    │
    ▼
[Click #2 执行]
    │
    ├── ActivityManager._on_click_triggered()
    │   └── 更新活动状态，累积奖赏
    │
    ├── 发射 click_triggered 信号
    │       └── [Agent _perform_activity_update()]
    │               │
    │               ├── 体验累积奖赏
    │               ├── 感知环境
    │               ├── MVT+LLM决策
    │               └── 继续/停止/更换
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

---

## 8. 使用示例

### 8.1 启动时序系统

```gdscript
func _ready():
    await get_tree().create_timer(1.0).timeout
    TimingSystem.instance.start_day(1)
```

### 8.2 监听 Click 信号

```gdscript
func _ready():
    TimingSystem.instance.click_triggered.connect(_on_click)
    TimingSystem.instance.day_ended.connect(_on_day_end)

func _on_click(game_time: float, day: int, click_num: int):
    print("Click #%d, 时间: %s" % [click_num, 
        TimingSystem.instance.format_time(game_time)])
```

### 8.3 获取当前约束

```gdscript
func _make_decision(perception: Dictionary):
    var constraints = TimelineState.instance.get_constraints()
    if not constraints.can_start_dialogue:
        return  # 上课时间不能开始对话
```

### 8.4 开始活动

```gdscript
# 开始上课活动
ActivityManager.instance.start_activity(
    "StudentXiaoming",
    ActivityManager.ActivityType.CLASS,
    {
        "room_name": "教室",
        "focus_level": 1.0,
        "activity_name": "听课"
    }
)
```

---

## 附录

### A. 文件清单

| 文件 | 路径 | 说明 |
|------|------|------|
| TimingSystem.gd | script/system/ | 时序系统 |
| TimelineState.gd | script/system/ | 课程表状态 |
| ActivityManager.gd | script/system/ | 活动管理器 |
| Timing_System.md | docs/ | 本文档 |

### B. 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 2.0 | 2026-04-08 | 合并TIMING_LOGIC_V2和TimingSystem_Documentation，添加V2时序逻辑 |
| 1.0 | - | 初始版本 |

---

*文档维护者：百舟楫*
