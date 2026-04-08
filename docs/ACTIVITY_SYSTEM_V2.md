# Activity System V2 技术文档

**版本**: 2.0  
**创建时间**: 2026-04-08  
**状态**: 已实现（阶段一至四完成）

---

## 目录

1. [系统架构](#1-系统架构)
2. [核心概念](#2-核心概念)
3. [脚本详解](#3-脚本详解)
4. [工作流程](#4-工作流程)
5. [双向奔赴机制](#5-双向奔赴机制)
6. [专注度系统](#6-专注度系统)
7. [扩展指南](#7-扩展指南)

---

## 1. 系统架构

### 1.1 整体架构图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              TimingSystem                                │
│                         (时序触发与协调调度)                               │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ Click触发
                                ↓
┌─────────────────────────────────────────────────────────────────────────┐
│                           ActivityCoordinator                            │
│                    (中央协调器 - LLM驱动决策分配)                          │
│  - 收集所有Agent自然语言决策                                              │
│  - 调用LLM解析并分配活动序列                                              │
│  - 处理双向奔赴等社交协调                                                 │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ 下发活动序列
                ┌───────────────┼───────────────┐
                ↓               ↓               ↓
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│   Agent A     │   │   Agent B     │   │   Agent C     │
│  ┌─────────┐  │   │  ┌─────────┐  │   │  ┌─────────┐  │
│  │AIAgent  │  │   │  │AIAgent  │  │   │  │AIAgent  │  │
│  │- 3步缓存 │  │   │  │- 3步缓存 │  │   │  │- 3步缓存 │  │
│  │- 活动执行│  │   │  │- 活动执行│  │   │  │- 活动执行│  │
│  │- 信息接收│  │   │  │- 信息接收│  │   │  │- 信息接收│  │
│  └─────────┘  │   │  └─────────┘  │   │  └─────────┘  │
└───────────────┘   └───────────────┘   └───────────────┘
```

### 1.2 核心组件

| 组件 | 职责 | 关键脚本 |
|------|------|----------|
| **时序系统** | Click周期管理、协调触发 | `TimingSystem.gd` |
| **中央协调器** | LLM调用、活动分配 | `ActivityCoordinator.gd` |
| **活动管理器** | 活动生命周期、奖赏计算 | `ActivityManager.gd` |
| **Agent核心** | 决策生成、活动执行 | `AIAgent.gd` |
| **数据结构** | 活动定义、专注度 | `Activity.gd` |
| **执行器** | 移动执行 | `MovementExecutor.gd` |
| **信息接收** | 专注度过滤 | `InformationReceiver.gd` |

---

## 2. 核心概念

### 2.1 基础活动类型

| 活动类型 | 场景限制 | 专注度 | 说明 |
|----------|----------|--------|------|
| `MOVE_TO` | 无 | 无 | 移动到目标位置或房间 |
| `NORMAL_DIALOGUE` | 无 | 无 | 普通对话 |
| `WHISPER` | 无 | 无 | 悄悄话（需贴身） |
| `LISTEN` | 教室 | 30/65/100 | 听课 |
| `QA_TEACHER` | 教室 | 30/65/100 | 课堂问答 |
| `SELF_STUDY` | 图书馆/自习室 | 30/65/100 | 自习 |
| `SPORTS` | 体育馆/操场 | 30/65/100 | 体育活动 |
| `GROUP_DISCUSSION` | 教室/讨论室 | 30/65/100 | 小组讨论 |

### 2.2 专注度档位

| 档位 | 值 | 效果 |
|------|-----|------|
| `LOW` | 30% | 努力×0.3, 奖赏×0.3, 信息接收30% |
| `MEDIUM` | 65% | 努力×0.65, 奖赏×0.65, 信息接收65% |
| `HIGH` | 100% | 努力×1.0, 奖赏×1.0, 信息接收100% |

### 2.3 三步缓存

每个Agent可缓存最多3个活动，支持复杂组合：
```
[移动到图书馆] → [自习数学] → [专注度65%]
```

---

## 3. 脚本详解

### 3.1 Activity.gd

**路径**: `script/system/Activity.gd`

**功能**: 定义活动数据结构，支持专注度机制和场景约束。

#### 类定义

```gdscript
class_name Activity
extends RefCounted
```

#### 枚举

```gdscript
enum ActivityType {
    MOVE_TO, NORMAL_DIALOGUE, WHISPER,
    LISTEN, QA_TEACHER, SELF_STUDY, SPORTS, GROUP_DISCUSSION
}

enum FocusLevel { LOW = 30, MEDIUM = 65, HIGH = 100 }
```

#### 核心属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `activity_id` | String | 唯一标识 |
| `activity_type` | ActivityType | 活动类型 |
| `activity_name` | String | 显示名称 |
| `allowed_scenes` | Array[String] | 允许的场景（空=无限制） |
| `requires_focus` | bool | 是否需要专注度 |
| `focus_level` | FocusLevel | 专注度档位 |
| `effort_multiplier` | float | 努力倍数 |
| `reward_multiplier` | float | 奖赏倍数 |
| `parameters` | Dictionary | 活动特定参数 |

#### 工厂方法

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `create_move_to()` | target_location, target_room | Activity | 创建移动活动 |
| `create_normal_dialogue()` | target_agent, topic | Activity | 创建对话活动 |
| `create_whisper()` | target_agent, content | Activity | 创建悄悄话活动 |
| `create_listen()` | target_teacher, focus | Activity | 创建听课活动 |
| `create_qa_teacher()` | question, is_answer, focus | Activity | 创建问答活动 |
| `create_self_study()` | subject, focus | Activity | 创建自习活动 |
| `create_sports()` | sport_type, intensity, focus | Activity | 创建体育活动 |
| `create_group_discussion()` | topic, members, focus | Activity | 创建讨论活动 |

#### 核心方法

```gdscript
# 设置专注度
func set_focus_level(level: FocusLevel) -> void

# 获取信息接收比例（用于对话类活动）
func get_information_reception_ratio() -> float

# 检查场景约束
func is_allowed_in_scene(scene_name: String) -> bool
func can_execute(scene_name: String, agent_state: String) -> Dictionary

# 序列化
func to_dictionary() -> Dictionary
static func from_dictionary(data: Dictionary) -> Activity
```

---

### 3.2 ActivityCoordinator.gd

**路径**: `script/system/ActivityCoordinator.gd`

**功能**: 中央协调器，收集Agent决策，调用LLM分配活动。

#### 类定义

```gdscript
class_name ActivityCoordinator
extends Node
```

#### 单例

```gdscript
static var instance: ActivityCoordinator
```

#### 配置属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `llm_api_url` | String | "http://localhost:11434/api/generate" | Ollama API地址 |
| `llm_model` | String | "qwen2.5:7b" | 模型名称 |
| `llm_temperature` | float | 0.3 | 温度参数 |
| `llm_max_tokens` | int | 2000 | 最大token数 |

#### 核心方法

```gdscript
# 提交Agent决策到协调器
# 输入: agent_id - Agent标识, decision - 自然语言决策
# 输出: 无（存储在pending_decisions中）
func submit_decision(agent_id: String, decision: String) -> void

# 执行协调 - 调用LLM分配活动
# 输入: game_context - 游戏上下文 {current_time, current_location, period}
# 输出: Dictionary {agent_id: Array[Activity]}
func execute_coordination(game_context: Dictionary = {}) -> Dictionary

# 获取分配给指定Agent的活动序列
# 输入: agent_id - Agent标识
# 输出: Array[Activity]
func get_assigned_activities(agent_id: String) -> Array[Activity]
```

#### 信号

```gdscript
signal coordination_started(agent_count: int)
signal coordination_completed(results: Dictionary)
signal coordination_failed(reason: String)
signal activity_assigned(agent_id: String, activities: Array)
```

---

### 3.3 ActivityManager.gd

**路径**: `script/system/ActivityManager.gd`

**功能**: 管理活动生命周期，计算奖赏（支持专注度）。

#### 核心属性

```gdscript
static var instance: ActivityManager
var registered_activities: Dictionary  # {activity_type: Activity}
var scene_activity_map: Dictionary     # 场景-活动映射
var agent_activities: Dictionary       # {agent_id: ActivityRecord}
```

#### 核心方法

```gdscript
# 开始新活动
# 输入: agent_id, activity_type, context {room_name, focus_level, ...}
# 输出: bool 是否成功
func start_activity(agent_id: String, activity_type: ActivityType, context: Dictionary = {}) -> bool

# 结束活动
# 输入: agent_id, reason
# 输出: Dictionary 活动总结 {agent_id, activity_type, total_duration, final_gain, reason}
func end_activity(agent_id: String, reason: String = "") -> Dictionary

# 获取Agent当前活动信息
# 输入: agent_id
# 输出: Dictionary {has_activity, activity_type, duration, state, context}
func get_activity_info(agent_id: String) -> Dictionary

# 检查Agent是否有活动
# 输入: agent_id
# 输出: bool
func has_activity(agent_id: String) -> bool

# V2: 创建移动活动
# 输入: agent_id, target_location, target_room
# 输出: Activity
func create_move_activity(agent_id: String, target_location: Vector2, target_room: String = "") -> Activity

# V2: 验证活动可行性
# 输入: activity, agent_id, current_scene, agent_state
# 输出: Dictionary {can_execute: bool, reason: String}
func validate_activity(activity: Activity, agent_id: String, current_scene: String, agent_state: String = "") -> Dictionary
```

#### 信号

```gdscript
signal activity_started(agent_id: String, activity_type: ActivityType, start_time: float)
signal activity_updated(agent_id: String, duration: float, cumulative_gain: float)
signal activity_ended(agent_id: String, activity_type: ActivityType, total_duration: float, final_gain: float)
signal activity_interrupted(agent_id: String, reason: String)
```

---

### 3.4 AIAgent.gd

**路径**: `script/ai/AIAgent.gd`

**功能**: Agent核心，生成自然语言决策，执行活动序列。

#### 核心属性

```gdscript
var activity_cache: Array[Activity]       # 三步活动缓存
var current_activity_index: int = 0       # 当前执行索引
var movement_executor: MovementExecutor   # 移动执行器
var information_receiver: InformationReceiver  # 信息接收器
var last_natural_decision: String = ""    # 上次自然语言决策
```

#### 核心方法

```gdscript
# 接收协调器分配的活动序列
# 输入: activities - Array[Activity]（最多3个）
# 输出: 无
func receive_activity_sequence(activities: Array[Activity]) -> void

# 生成自然语言决策
# 输入: perception - 感知数据
# 输出: String - 自然语言决策描述
func _make_natural_decision(perception: Dictionary) -> String

# 执行缓存的下一个活动
# 输入: 无
# 输出: 无
func _execute_next_cached_activity() -> void

# 执行具体活动
# 输入: activity - Activity对象
# 输出: 无
func _execute_v2_activity(activity: Activity) -> void

# 执行各类活动（内部调用）
func _execute_v2_move(activity: Activity) -> void
func _execute_v2_dialogue(activity: Activity) -> void
func _execute_v2_whisper(activity: Activity) -> void
func _execute_v2_listen(activity: Activity) -> void
func _execute_v2_qa(activity: Activity) -> void
func _execute_v2_study(activity: Activity) -> void
func _execute_v2_sports(activity: Activity) -> void
func _execute_v2_discussion(activity: Activity) -> void
```

---

### 3.5 MovementExecutor.gd

**路径**: `script/system/MovementExecutor.gd`

**功能**: 封装移动逻辑，支持导航和直线移动。

#### 类定义

```gdscript
class_name MovementExecutor
extends RefCounted
```

#### 核心方法

```gdscript
# 执行移动活动
# 输入: activity - Activity类型为MOVE_TO的活动
# 输出: Dictionary {success: bool, reason: String, estimated_duration: float}
func execute_move_activity(activity: Activity) -> Dictionary

# 更新移动状态（每帧调用）
# 输入: delta - 时间增量
# 输出: 无
func update(delta: float) -> void

# 检查状态
func is_moving() -> bool
func has_arrived() -> bool
func get_remaining_distance() -> float

# 停止移动
func stop_movement() -> void

# 静态工具方法
static func calculate_target_position_for_character(from_pos: Vector2, target_char: CharacterBody2D, is_whisper: bool = false, room_manager = null) -> Vector2
static func calculate_target_position_for_room(room_data: Dictionary, max_offset_ratio: float = 0.3) -> Vector2
```

---

### 3.6 InformationReceiver.gd

**路径**: `script/system/InformationReceiver.gd`

**功能**: 处理对话类活动的信息接收，根据专注度过滤内容。

#### 类定义

```gdscript
class_name InformationReceiver
extends RefCounted
```

#### 核心方法

```gdscript
# 接收对话信息
# 输入: source_id, content, focus_level (0.0-1.0), topic
# 输出: InformationRecord
func receive_dialogue(source_id: String, content: String, focus_level: float, topic: String = "") -> InformationRecord

# 接收课堂讲授信息
# 输入: teacher_id, content, focus_level, subject
# 输出: InformationRecord
func receive_lecture(teacher_id: String, content: String, focus_level: float, subject: String = "") -> InformationRecord

# 接收小组讨论信息
# 输入: participants, content, focus_level, topic
# 输出: InformationRecord
func receive_discussion(participants: Array[String], content: String, focus_level: float, topic: String = "") -> InformationRecord

# 查询信息
func get_recent_information(count: int = 5) -> Array[InformationRecord]
func get_information_from_source(source_id: String, count: int = 10) -> Array[InformationRecord]
func get_missed_important_info() -> Array[InformationRecord]

# 格式化输出（用于Prompt）
func format_for_prompt(count: int = 5) -> String
func format_missed_important() -> String
```

---

### 3.7 TimingSystem.gd

**路径**: `script/system/TimingSystem.gd`

**功能**: 时序管理，Click触发，协调调度。

#### 核心修改

```gdscript
# Click触发时执行协调
func _trigger_click():
    # ... 原有逻辑 ...
    
    # 触发Agent决策收集
    click_triggered.emit(current_game_time, current_day, click_count)
    
    # 延迟执行协调
    await get_tree().create_timer(0.5).timeout
    
    # 执行协调
    if ActivityCoordinator.instance:
        var game_context = {
            "current_time": format_time(current_game_time),
            "current_location": "学校",
            "period": _get_current_period()
        }
        var coordination_results = await ActivityCoordinator.instance.execute_coordination(game_context)
```

---

### 3.8 RewardSystem.gd

**路径**: `script/system/RewardSystem.gd`

**功能**: 奖赏分发（支持专注度上下文）。

#### 核心方法

```gdscript
# 带上下文的奖赏分发（支持专注度）
# 输入: agent_name, room_name, time_in_room, context {focus_level, base_effort, adjusted_effort, base_gain, adjusted_gain}
# 输出: Dictionary {gain, effort, room_name, time, context}
func distribute_reward_with_context(agent_name: String, room_name: String, time_in_room: float, context: Dictionary) -> Dictionary
```

---

## 4. 工作流程

### 4.1 完整时序图

```
Time  │  TimingSystem  │  ActivityCoordinator  │     AIAgent      │  ActivityManager
──────┼────────────────┼───────────────────────┼──────────────────┼─────────────────
  t0  │  _trigger_click│                       │                  │
      │       ↓        │                       │                  │
  t1  │  click_triggered.emit()                │                  │
      │       ↓        │                       │                  │
  t2  │                │                       │ _on_click_triggered()
      │                │                       │       ↓          │
  t3  │                │                       │ _perform_v2_cognitive_cycle()
      │                │                       │       ↓          │
  t4  │                │                       │ _make_natural_decision()
      │                │                       │       ↓          │
  t5  │                │  submit_decision()    │                  │
      │       ↓        │                       │                  │
  t6  │  await 0.5s    │                       │                  │
      │       ↓        │                       │                  │
  t7  │                │  execute_coordination()                  │
      │                │       ↓               │                  │
  t8  │                │  _call_llm()          │                  │
      │                │       ↓               │                  │
  t9  │                │  _parse_coordination_response()          │
      │                │       ↓               │                  │
  t10 │                │  _distribute_activities()                │
      │                │       ↓               │                  │
  t11 │                │                       │ receive_activity_sequence()
      │       ↓        │                       │                  │
  t12 │  Click结束      │                       │                  │
      │                │                       │                  │
  t13 │  _trigger_click│                       │                  │
      │       ↓        │                       │                  │
  t14 │                │                       │ _execute_next_cached_activity()
      │                │                       │       ↓          │
  t15 │                │                       │ _execute_v2_*()  │
      │                │                       │       ↓          │
  t16 │                │                       │                  │ start_activity()
```

### 4.2 Agent状态流转

```
                    ┌─────────────┐
                    │    IDLE     │
                    └──────┬──────┘
                           │ Click触发
                           ↓
                    ┌─────────────┐
                    │  PERCEIVING │
                    └──────┬──────┘
                           │
                           ↓
                    ┌─────────────┐
                    │ EXPERIENCING│ (如果有上一活动)
                    └──────┬──────┘
                           │
                           ↓
                    ┌─────────────┐
                    │   DECIDING  │ → 生成自然语言决策
                    └──────┬──────┘
                           │ 提交到协调器
                           ↓
         ┌─────────────────┴─────────────────┐
         │                                   │
         ↓                                   ↓
┌─────────────────┐                 ┌─────────────────┐
│  WAITING_FOR    │                 │   IN_ACTIVITY   │
│  COORDINATION   │                 │                 │
└────────┬────────┘                 └────────┬────────┘
         │                                   │
         │ 收到活动序列                        │ Click触发
         ↓                                   ↓
┌─────────────────┐                 ┌─────────────────┐
│  EXECUTING      │                 │  EXPERIENCING   │
│  ACTION         │                 │  (累积奖赏)     │
└─────────────────┘                 └─────────────────┘
```

---

## 5. 双向奔赴机制

### 5.1 核心规则

**原则**: 只有双方意图匹配时才协调，否则各自独立行动。

### 5.2 判断逻辑

```
IF (Agent A想和Agent B互动) AND (Agent B想和Agent A互动):
    → 双向奔赴 ✅
    → 分配共同目标位置
    → 目标位置 = (A位置 + B位置) / 2
ELSE:
    → 单向意图 ❌
    → 各自独立执行
    → 可能扑空
```

### 5.3 场景示例

**示例1：双向奔赴** ✅
```
输入:
- 小明(100,200): "我想和小红讨论数学"
- 小红(300,400): "我想和小明讨论数学"

LLM处理:
- 检测到双向奔赴
- 计算中间点: ((100+300)/2, (200+400)/2) = (200, 300)
- 分配共同目标

输出:
- 小明 → MOVE_TO(200±10, 300±10) → NORMAL_DIALOGUE(小红)
- 小红 → MOVE_TO(200±10, 300±10) → NORMAL_DIALOGUE(小明)
```

**示例2：单向扑空** ❌
```
输入:
- 小明(100,200): "我想和小红悄悄话"
- 小红(300,400): "我想去图书馆自习"

LLM处理:
- 非双向奔赴
- 各自独立执行

输出:
- 小明 → MOVE_TO(300,400) → WHISPER(小红)
- 小红 → MOVE_TO(图书馆)

结果:
- 小明到达后发现小红不在
- 下次感知/决策时处理此情况
- 可能产生失落/困惑情绪
```

### 5.4 Prompt实现

双向奔赴逻辑完全由LLM Prompt驱动，详见 `docs/prompts/coordinator_prompt.md`。

---

## 6. 专注度系统

### 6.1 专注度影响

| 专注度 | 努力成本 | 奖赏收益 | 信息接收 |
|--------|----------|----------|----------|
| 30% | ×0.3 | ×0.3 | 30% |
| 65% | ×0.65 | ×0.65 | 65% |
| 100% | ×1.0 | ×1.0 | 100% |

### 6.2 代码实现

**ActivityManager**:
```gdscript
# 应用专注度调整
var focus_level = record.context.get("focus_level", 1.0)
var adjusted_effort = effort_level * focus_level
var adjusted_gain = cumulative_gain * focus_level
```

**InformationReceiver**:
```gdscript
# 根据专注度过滤内容
func _filter_content(full_content: String, ratio: float) -> String:
    if ratio >= 0.95:
        return full_content
    # 按比例保留词
    var keep_count = max(1, int(total_words * ratio))
    # ...
```

### 6.3 信息过滤示例

```
原始内容: "明天数学考试，重点复习第三章"
专注度30% → 可能接收: "明天...考试..."
专注度100% → 完整接收: "明天数学考试，重点复习第三章"
```

---

## 7. 扩展指南

### 7.1 添加新活动类型

1. **Activity.gd**: 添加枚举值和工厂方法
2. **ActivityManager.gd**: 更新场景映射
3. **AIAgent.gd**: 添加 `_execute_v2_newactivity()` 方法
4. **coordinator_prompt.md**: 更新活动定义

### 7.2 调整专注度档位

修改 `Activity.gd`:
```gdscript
enum FocusLevel {
    LOW = 20,      # 改为20%
    MEDIUM = 50,   # 改为50%
    HIGH = 100
}
```

### 7.3 更换LLM模型

修改 `ActivityCoordinator.gd`:
```gdscript
var llm_model: String = "qwen2.5:14b"  # 更换模型
var llm_api_url: String = "http://localhost:11434/api/generate"  # 或更换API
```

---

## 附录

### A. 文件清单

| 文件 | 路径 | 说明 |
|------|------|------|
| Activity.gd | script/system/ | 活动数据结构 |
| ActivityCoordinator.gd | script/system/ | 中央协调器 |
| ActivityManager.gd | script/system/ | 活动管理器 |
| MovementExecutor.gd | script/system/ | 移动执行器 |
| InformationReceiver.gd | script/system/ | 信息接收器 |
| AIAgent.gd | script/ai/ | Agent核心 |
| TimingSystem.gd | script/system/ | 时序系统 |
| RewardSystem.gd | script/system/ | 奖赏系统 |
| coordinator_prompt.md | docs/prompts/ | 协调器Prompt |
| natural_decision_template.txt | prompts/ | 自然语言决策Prompt |
| dialogue_reply_template.txt | prompts/ | 对话回复Prompt |
| basic_info_fragment.txt | prompts/fragments/ | 基础信息片段 |

### B. 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 2.0 | 2026-04-08 | 初始实现，阶段一至四完成 |

---

_文档结束_
