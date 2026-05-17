# Agent认知系统详细文档

> **系统名称**: AIAgent + PerceptionSystem + AgentRewardReceiver + UtilitySystem
> **版本**: 1.1
> **最后更新**: 2026-04-07

---

## 目录

1. [系统概述](#系统概述)
2. [核心概念](#核心概念)
3. [AIAgent 详解](#aiagent-详解)
4. [PerceptionSystem 详解](#perceptionsystem-详解)
5. [AgentRewardReceiver 详解](#agentrewardreceiver-详解)
6. [认知循环流程](#认知循环流程)
7. [行动执行详解](#行动执行详解)
8. [使用示例](#使用示例)

---

## 系统概述

### 设计目标

Agent认知系统是 Godot-Microverse-predict 项目的核心AI组件，负责：
- 感知当前场景和环境信息（含其他Agent活动状态）
- 体验系统层发放的奖赏并更新信念
- 基于MVT理论计算最优停留时间
- 基于认知参数做出决策
- 执行行动并与环境交互

### 实现状态

| 组件 | 状态 | 说明 |
|------|------|------|
| 感知阶段 | ✅ 已完成 | 场景信息 + 其他Agent活动状态 |
| 体验阶段 | ✅ 已完成 | 奖赏接收 + 贝叶斯更新 |
| 决策阶段 | ✅ 已完成 | LLM决策 + MVT参数注入 |
| 行动执行 | ✅ 已完成 | 8种行动类型 + 两步缓存 |
| ActivityManager | ✅ 已完成 | 活动注册、活动追踪与奖赏闭环 |
| DialogueManager | ✅ 已完成 | 对话生命周期管理 |

### 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│  系统层（System Layer）                                       │
│  ├─ TimingSystem         - 触发认知循环                      │
│  ├─ RewardSystem         - 发放客观奖赏                      │
│  ├─ TimelineState        - 提供时间表与时段引导                │
│  └─ ActivityManager      - 活动生命周期管理                    │
└─────────────────────────────────────────────────────────────┘
                              ↓ click_triggered 信号
┌─────────────────────────────────────────────────────────────┐
│  感知层（Perception Layer）                                   │
│  ├─ AgentRewardReceiver  - 接收并缓存奖赏                    │
│  └─ PerceptionSystem     - 贝叶斯更新信念                    │
└─────────────────────────────────────────────────────────────┘
                              ↓ 感知参数
┌─────────────────────────────────────────────────────────────┐
│  认知层（Cognitive Layer）                                    │
│  ├─ AIAgent              - 认知循环中枢                      │
│  ├─ UtilitySystem        - MVT效用计算                       │
│  ├─ PromptBuilder        - 构建决策Prompt                    │
│  └─ DynamicPersonality   - 动态人格特质                      │
└─────────────────────────────────────────────────────────────┘
                              ↓ 行动请求
┌─────────────────────────────────────────────────────────────┐
│  执行层（Execution Layer）                                    │
│  ├─ CharacterController  - 角色移动控制                      │
│  └─ DialogueManager      - 对话生命周期管理                  │
└─────────────────────────────────────────────────────────────┘
```

### 核心特性

| 特性 | 说明 | 状态 |
|------|------|------|
| **四层认知架构** | 感知 → 体验 → 决策 → 执行 | ✅ 已实现 |
| **贝叶斯感知** | 基于观测样本更新对情境的信念 | ✅ 已实现 |
| **MVT决策** | 基于边际价值定理计算最优停留时间 | ✅ 已实现 |
| **两步缓存** | 支持复杂行动计划的缓存和验证 | ✅ 已实现 |
| **中范围划分** | 精确的空间感知和移动定位 | ✅ 已实现 |
| **活动状态感知** | 感知其他Agent的活动状态 | ✅ 已实现 |
| **活动管理闭环** | 活动注册、追踪、奖赏发放 | ✅ 已实现 |
| **对话管理** | 对话生命周期、发言队列 | ✅ 已实现 |

---

## 核心概念

### 认知循环

```
Click触发
    │
    ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   感知阶段   │ --> │   体验阶段   │ --> │   决策阶段   │ --> │   执行阶段   │
│  Perceiving │     │ Experiencing│     │  Deciding   │     │  Executing  │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
      │                   │                   │                   │
      ▼                   ▼                   ▼                   ▼
  收集场景信息        贝叶斯更新信念      调用LLM决策        在Click时刻执行
  获取时间约束        更新认知参数        生成ActionRequest    移动/对话/活动
```

### 认知参数（MVT模型）

| 参数 | 符号 | 范围 | 健康Agent | 抑郁Agent | 说明 |
|------|------|------|----------|----------|------|
| 离开阈值 | ρ_base | 0-1 | 0.5-0.6 | 0.3-0.4 | 对环境平均奖赏率的估计 |
| 初始奖赏感知权重 | η_s | 0-1 | 0.5 | 0.4 | 对初始丰富度的敏感度 |
| 衰减率感知权重 | η_a | 0-1 | 0.5 | 0.7 | 对奖赏衰减的敏感度 |
| 收益敏感性 | α | 0-1 | 0.8 | 0.5-0.6 | 收益的非线性效用 |
| **努力敏感性** | **β_effort** | **0-1** | **0.4** | **0.8** | **核心差异参数** |

### MVT理论公式

**客观收益函数**:
```
G(t) = (S/a)[1 - exp(-at)]
```

**主观效用函数**:
```
U(G) = G^α - β_effort × E
```

**最优停留时间（解析解）**:
```
log(T) = log[ηS·log(S)] − log(ρbase) − βeffort·effort − ηa·log(a) + ε
```

其中 ε 为决策层随机噪声（标准差0.1）

---

## AIAgent 详解

### 类定义

```gdscript
class_name AIAgent
extends Node
```

### 状态枚举

```gdscript
enum AgentState {
    IDLE,                    # 空闲状态
    PERCEIVING,              # 感知中
    EXPERIENCING,            # 体验中
    DECIDING,                # 决策中
    WAITING_FOR_CLICK,       # 等待Click执行
    EXECUTING_ACTION,        # 执行行动中
    IN_DIALOGUE,             # 在对话中
    IN_ACTIVITY              # 在活动中
}
```

### 核心成员变量

| 变量 | 类型 | 说明 |
|------|------|------|
| `character` | CharacterBody2D | 角色节点引用 |
| `room_manager` | RoomManager | 房间管理器引用 |
| `reward_receiver` | AgentRewardReceiver | 奖赏接收器 |
| `current_state` | AgentState | 当前Agent状态 |
| `current_activity` | String | 当前活动类型 |
| `activity_start_time` | float | 活动开始时间 |
| `last_activity` | String | 上一周期活动 |
| `cached_request` | ActionRequest | 缓存的行动请求 |
| `is_waiting_execution` | bool | 是否等待执行 |
| `is_player_controlled` | bool | 是否玩家控制 |

### 函数详解

#### _ready()

```gdscript
func _ready()
```

**功能**: 初始化AIAgent

**执行流程**:
1. 获取父节点（CharacterBody2D）
2. 获取RoomManager
3. 创建AgentRewardReceiver
4. 连接时序系统信号（延迟1秒）

**输出**: "[AIAgent] {name} 初始化完成"

---

#### _on_click_triggered()

```gdscript
func _on_click_triggered(game_time: float, day: int, click_num: int)
```

**功能**: Click触发回调（核心入口）

**输入**:
| 参数 | 类型 | 说明 |
|------|------|------|
| game_time | float | 当前游戏时间（分钟） |
| day | int | 当前天数 |
| click_num | int | Click计数 |

**执行逻辑**:
```
if 玩家控制:
    返回

if 有缓存请求且等待执行:
    执行缓存请求
else:
    开始新的认知循环
```

---

#### _perform_cognitive_cycle()

```gdscript
func _perform_cognitive_cycle()
```

**功能**: 执行完整认知循环

**执行流程**:
1. **感知阶段**: `current_state = PERCEIVING`，调用 `_perceive()`
2. **体验阶段**: `current_state = EXPERIENCING`，调用 `_experience(last_activity)`
3. **决策阶段**: `current_state = DECIDING`，调用 `_make_decision(perception)`
4. **提交请求**: 调用 `_submit_request(request)`

---

#### _perceive()

```gdscript
func _perceive() -> Dictionary
```

**功能**: 感知阶段 - 收集场景信息

**返回值** (Dictionary):
| 键 | 类型 | 说明 |
|----|------|------|
| `current_room` | String | 当前房间名称 |
| `nearby_agents` | Array | 同场景其他Agent（含活动状态） |
| `visible_behaviors` | Array | 可见的对话行为 |
| `audible_contents` | Array | 可听到的对话内容 |
| `time_constraints` | Dictionary | 时间轴约束 |
| `current_time` | float | 当前游戏时间 |

**nearby_agents 结构**:
```gdscript
{
    "name": "角色名称",
    "position": Vector2,
    "state": AgentState,
    "activity": "活动类型",
    "activity_status": "活动状态描述"  // 如："正在与 B 对话"
}
```

---

#### _experience()

```gdscript
func _experience(previous_activity: String) -> float
```

**功能**: 体验阶段 - 主观体验奖赏并更新信念

**输入**:
| 参数 | 类型 | 说明 |
|------|------|------|
| previous_activity | String | 上一周期活动名称 |

**返回值**: float - 感知到的收益值

**执行流程**:
1. 从reward_receiver获取最近奖赏
2. 获取客观收益和感知收益
3. 调用PerceptionSystem获取感知参数
4. 返回感知收益

---

#### _make_decision()

```gdscript
func _make_decision(perception: Dictionary) -> ActionRequest
```

**功能**: 决策阶段 - 生成行动请求

**输入**:
| 参数 | 类型 | 说明 |
|------|------|------|
| perception | Dictionary | 感知结果 |

**返回值**: ActionRequest - 行动请求对象

**执行流程**:
1. 调用 `PromptBuilder.build_decision_prompt()` 构建Prompt
2. 调用 `_call_local_llm()` 调用本地LLM
3. 调用 `_parse_decision_response()` 解析响应
4. 返回ActionRequest

---

#### _call_local_llm()

```gdscript
func _call_local_llm(prompt: String) -> String
```

**功能**: 调用本地部署的大模型API

**输入**:
| 参数 | 类型 | 说明 |
|------|------|------|
| prompt | String | 决策Prompt |

**返回值**: String - LLM响应文本

**API配置**:
| 配置项 | 值 |
|--------|-----|
| URL | http://localhost:11434/api/generate |
| 模型 | qwen2.5:14b |
| 温度 | 0.7 |
| 最大token | 500 |

---

#### _execute_action()

```gdscript
func _execute_action(request: ActionRequest)
```

**功能**: 行动执行分发

**输入**:
| 参数 | 类型 | 说明 |
|------|------|------|
| request | ActionRequest | 行动请求 |

**分发逻辑**:
```gdscript
match request.action_type:
    MOVE_TO_RANGE:      _execute_move(request)
    START_DIALOGUE:     _execute_start_dialogue(request)
    START_WHISPER:      _execute_start_whisper(request)
    JOIN_DIALOGUE:      _execute_join_dialogue(request)
    EXIT_DIALOGUE:      _execute_exit_dialogue(request)
    START_SPORTS:       _execute_start_sports(request)
    END_SPORTS:         _execute_end_sports(request)
    START_STUDY:        _execute_start_study(request)
    END_STUDY:          _execute_end_study(request)
    WAIT:               _execute_wait(request)
```

---

#### _calculate_move_target()

```gdscript
func _calculate_move_target(target_name: String, is_whisper: bool = false) -> Vector2
```

**功能**: 定位函数 - 根据目标名称计算移动目标坐标

**输入**:
| 参数 | 类型 | 说明 |
|------|------|------|
| target_name | String | 子场景名或角色名 |
| is_whisper | bool | 是否是悄悄话移动 |

**返回值**: Vector2 - 目标坐标

**定位逻辑**:
```
if target_name 是角色名:
    if is_whisper:
        return 目标位置 + 贴身偏移(±15px)
    elif 同一中范围:
        return 目标位置 + 小范围偏移(±30px)
    else:
        return 目标中范围中心 + 偏移(±20%)
else:
    # 是子场景名
    return 子场景内随机位置(中心±30%)
```

---

## PerceptionSystem 详解

### 类定义

```gdscript
class_name PerceptionSystem
extends Node
```

### 核心常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `PRIOR_S_MEAN` | 0.5 | 健康Agent S先验均值 |
| `DEPRESSION_PRIOR_S_MEAN` | 0.3 | 抑郁Agent S先验均值（悲观） |
| `BASE_PERCEPTION_NOISE` | 0.02 | 基础感知噪声（2%） |

### 核心函数

#### perceive_gain()

```gdscript
static func perceive_gain(actual_gain: float, eta_s: float, eta_a: float) -> float
```

**功能**: 感知收益（添加感知噪声）

**输入**:
| 参数 | 类型 | 说明 |
|------|------|------|
| actual_gain | float | 客观收益 |
| eta_s | float | 初始奖赏感知权重 |
| eta_a | float | 衰减率感知权重 |

**返回值**: float - 感知收益

**噪声公式**:
```
avg_eta = (eta_s + eta_a) / 2
noise_std = 0.02 * (1.0 - avg_eta * 0.3)
perceived = actual_gain + N(0, noise_std²)
```

---

#### get_perceived_params()

```gdscript
static func get_perceived_params(agent_name: String, room_name: String,
                                 is_depression_risk: bool = false) -> Dictionary
```

**功能**: 获取感知到的情境参数

**返回值**:
| 键 | 类型 | 说明 |
|----|------|------|
| `S` | float | 感知到的初始收益率 |
| `a` | float | 感知到的衰减率 |
| `confidence` | float | 总体置信度 |

---

## AgentRewardReceiver 详解

### 类定义

```gdscript
class_name AgentRewardReceiver
extends Node
```

### 核心函数

#### _on_reward_received()

```gdscript
func _on_reward_received(agent_name: String, room_name: String,
                         time: float, gain: float, effort: float) -> void
```

**功能**: 接收奖赏回调

**输入**:
| 参数 | 类型 | 说明 |
|------|------|------|
| agent_name | String | 接收者名称 |
| room_name | String | 房间名称 |
| time | float | 停留时间 |
| gain | float | 客观收益 |
| effort | float | 努力成本 |

**执行流程**:
1. 检查是否发给自己
2. 获取Agent的认知参数
3. 调用 `PerceptionSystem.perceive_gain()` 添加噪声
4. 记录到历史
5. 调用 `PerceptionSystem.add_sample()` 更新信念

---

## 认知循环流程

### 完整流程

```
Click触发
    │
    ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. 检查是否有缓存请求                                            │
│     ├─ 有 → 执行缓存请求 → 返回                                  │
│     └─ 无 → 继续认知循环                                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. 感知阶段 (_perceive)                                         │
│     ├─ 获取当前房间                                              │
│     ├─ 获取同场景其他Agent                                        │
│     ├─ 获取时间约束 (TimelineState)                               │
│     └─ 返回 perception Dictionary                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. 体验阶段 (_experience)                                       │
│     ├─ 从 reward_receiver 获取最近奖赏                           │
│     ├─ 获取感知参数 (PerceptionSystem)                            │
│     └─ 返回 perceived_gain                                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. 决策阶段 (_make_decision)                                    │
│     ├─ 构建Prompt (PromptBuilder)                                │
│     ├─ 调用LLM (_call_local_llm)                                 │
│     ├─ 解析响应 (_parse_decision_response)                        │
│     └─ 返回 ActionRequest                                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. 提交请求 (_submit_request)                                   │
│     ├─ 缓存请求                                                  │
│     ├─ 设置状态为 WAITING_FOR_CLICK                              │
│     └─ 提交到 TimingSystem                                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## 行动执行详解

### 10种行动类型

| 行动 | 编号 | 场景限制 | 说明 | 状态 |
|------|------|---------|------|------|
| MOVE_TO_RANGE | 0 | 任意 | 移动到指定中范围 | ✅ 已实现 |
| START_DIALOGUE | 1 | 同一中范围 | 开始普通对话 | ✅ 已实现 |
| START_WHISPER | 2 | 贴身位置 | 开始悄悄话 | ✅ 已实现 |
| JOIN_DIALOGUE | 3 | 任意 | 加入已有对话 | ✅ 已实现 |
| EXIT_DIALOGUE | 4 | 对话中 | 退出对话 | ✅ 已实现 |
| START_SPORTS | 5 | 体育馆 | 开始体育活动 | ✅ 已实现 |
| END_SPORTS | 6 | 体育馆 | 结束体育活动 | ✅ 已实现 |
| START_STUDY | 7 | 图书馆/自习室 | 开始自习 | ✅ 已实现 |
| END_STUDY | 8 | 图书馆/自习室 | 结束自习 | ✅ 已实现 |
| WAIT | 9 | 任意 | 等待 | ✅ 已实现 |

**注意**：START_DIALOGUE、START_WHISPER、JOIN_DIALOGUE 需要 DialogueManager 配合才能实现完整的对话生命周期管理。

### 两步缓存机制

```
Agent A想和Agent B对话，但不在同一中范围

决策结果：
├─ Step1: 移动路径（进入B所在中范围）
└─ Step2: 开始对话（缓存，待确认）

Click N: 执行Step1（移动）
    │
    └── 到达后 → 立即感知（无体验）
        │
        └── 检查：
            ├─ B是否还在？ → 是
            ├─ B是否已在对话？ → 否
            └─ 是否上课了？ → 否
        │
        └── 全部通过 → 执行Step2（开始对话）

        任一检查失败 → 重新决策
```

---

## 使用示例

### 示例1：认知循环入口

```gdscript
# AIAgent 连接Click信号
func _ready():
    await get_tree().create_timer(1.0).timeout
    TimingSystem.instance.click_triggered.connect(_on_click_triggered)

# Click触发回调
func _on_click_triggered(game_time: float, day: int, click_num: int):
    if is_player_controlled:
        return

    # 执行认知循环
    _perform_cognitive_cycle()
```

### 示例2：获取感知参数

```gdscript
# 在决策时使用感知参数
func _make_decision(perception: Dictionary) -> ActionRequest:
    var personality = CharacterPersonality.get_personality(character.name)
    var is_depression = personality.get("role_type", "") == "depression_risk_student"

    # 获取感知参数
    var perceived_params = PerceptionSystem.get_perceived_params(
        character.name,
        perception.current_room,
        is_depression
    )

    # 构建包含感知参数的Prompt
    var prompt = PromptBuilder.build_decision_prompt(self, perception)
    # ...
```

### 示例3：移动定位

```gdscript
# 执行移动
func _execute_move(request: ActionRequest):
    var is_whisper = false
    if cached_request and cached_request.cached_step2:
        if cached_request.cached_step2.action_type == ActionRequest.ActionType.START_WHISPER:
            is_whisper = true

    var target_pos = _calculate_move_target(request.target_id, is_whisper)

    if character.has_method("move_to"):
        character.move_to(target_pos)
        _is_moving = true
```

### 示例4：MVT最优停留时间计算

```gdscript
# 使用UtilitySystem计算最优停留时间
func _check_mvt_leave_decision(room_name: String, time_in_room: float,
                               personality: Dictionary, is_depression: bool) -> Dictionary:
    # 获取认知参数
    var params = UtilitySystem.get_agent_utility_params(personality)

    # 获取感知参数
    var perceived_params = PerceptionSystem.get_perceived_params(
        character.name, room_name, is_depression
    )

    # 获取情境努力成本
    var effort = 0.5
    if RewardSystem.instance:
        var room_data = RewardSystem.instance._get_room_objective_params(room_name)
        effort = room_data.get("E", 0.5)

    # 计算最优停留时间
    var optimal_time = UtilitySystem.calculate_optimal_time(
        perceived_params.S,
        perceived_params.a,
        effort,
        params.alpha,
        params.beta_effort,
        params.p_base,
        params.eta_s,
        params.eta_a
    )

    # 决策：是否离开
    var should_leave = time_in_room >= optimal_time

    return {
        "should_leave": should_leave,
        "optimal_time": optimal_time,
        "current_time": time_in_room,
        "reason": "MVT预测的最优停留时间"
    }
```

### 示例5：感知其他Agent活动状态

```gdscript
# 生成场景描述，包含其他Agent的活动状态
func _get_characters_in_medium_range_description() -> String:
    var desc = "\n\n【场景内角色】"
    var current_room = _get_current_room()
    var room_characters = get_room_characters(current_room)

    # 按中范围分组
    var characters_by_range = {}

    for char in room_characters:
        var char_medium_range = _get_medium_range_description(current_room, char.global_position)
        var char_personality = CharacterPersonality.get_personality(char.name)
        var position = char_personality.get("position", "未知职位")

        # 获取活动状态
        var activity_status = _get_character_activity_status(char)

        var char_info = {
            "name": char.name,
            "position": position,
            "activity_status": activity_status  // 如："正在与 B 对话"
        }

        if not characters_by_range.has(char_medium_range):
            characters_by_range[char_medium_range] = []
        characters_by_range[char_medium_range].append(char_info)

    # 输出格式示例：
    # 【同一中范围内(可普通对话)】
    # - A(学生)：未在进行活动
    # - B(学生)：正在与 C 对话
    # - C(学生)：正在与 B 对话

    return desc
```

---

## 附录：系统实现状态清单

### 已实现 ✅

| 组件 | 文件 | 功能 |
|------|------|------|
| AIAgent核心 | `script/ai/AIAgent.gd` | 认知循环中枢、行动执行 |
| PerceptionSystem | `script/ai/PerceptionSystem.gd` | 贝叶斯感知、信念更新 |
| AgentRewardReceiver | `script/ai/AgentRewardReceiver.gd` | 奖赏接收、添加噪声 |
| UtilitySystem | `script/ai/UtilitySystem.gd` | MVT效用计算、最优停留时间 |
| PromptBuilder | `script/ai/PromptBuilder.gd` | Prompt构建 |
| TimingSystem | `script/system/TimingSystem.gd` | Click触发 |
| TimelineState | `script/system/TimelineState.gd` | 时间表与时段引导 |
| RewardSystem | `script/system/RewardSystem.gd` | 奖赏发放 |

---

*文档维护者：百舟楫*
*最后更新：2026-04-07*
