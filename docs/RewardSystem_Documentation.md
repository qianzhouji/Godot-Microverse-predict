# 奖赏系统详细文档

> **系统名称**: RewardSystem + PerceptionSystem + AgentRewardReceiver
> **版本**: 1.0
> **最后更新**: 2026-04-07

---

## 目录

1. [系统概述](#系统概述)
2. [架构设计](#架构设计)
3. [系统层：RewardSystem](#系统层rewardsystem)
4. [感知层：AgentRewardReceiver](#感知层agentrewardreceiver)
5. [认知层：PerceptionSystem](#认知层perceptionsystem)
6. [数据流详解](#数据流详解)
7. [核心公式](#核心公式)
8. [API参考](#api参考)
9. [使用示例](#使用示例)
10. [实现状态](#实现状态)

---

## 系统概述

### 设计目标

奖赏系统是 Godot-Microverse-predict 项目的核心数据流系统，负责：
- **系统层**：维护客观情境参数，计算客观收益
- **感知层**：接收并缓存奖赏，添加感知噪声
- **认知层**：贝叶斯更新信念，推断情境特征

### 核心原则

| 原则 | 说明 |
|------|------|
| **分层隔离** | Agent不能直接访问RoomArea参数，只能通过RewardSystem接收奖赏 |
| **客观统一** | 所有Agent在同一情境中获得相同的客观收益 |
| **主观差异** | 感知噪声和先验信念导致不同的主观感知 |
| **极小感知噪声** | 感知层噪声仅2%，主要噪声在决策层（ε） |

### 三层架构

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 1: 系统层（客观现实）- Agent不可见                        │
│  ├─ RoomArea.gd          - 定义情境参数(S, a, E)                 │
│  ├─ RewardSystem.gd      - 计算客观收益 G(t)                     │
│  └─ RoomManager.gd       - 房间管理                              │
│                                                                 │
│  公式: G(t) = (S/a)[1 - exp(-at)]                               │
│  原则: Agent不能直接读取S,a,E                                    │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    【通过信号发放奖赏】
                    （Agent只接收"gain"数值）
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  Layer 2: 感知层（奖赏接收）                                      │
│  ├─ AgentRewardReceiver.gd - 订阅信号、接收奖赏                  │
│  │   ├─ 添加极小感知噪声(σ=2%)                                   │
│  │   └─ 缓存奖赏历史                                             │
│  │                                                               │
│  └─ 传递给PerceptionSystem                                       │
│                                                                 │
│  公式: perceived_gain = actual_gain + N(0, σ²)                  │
│  其中: σ = 0.02 × (1 - avg(η_s, η_a) × 0.3)                     │
└─────────────────────────────────────────────────────────────────┘
                              ↓
              【观测样本】(time, perceived_gain)
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  Layer 3: 认知层（信念更新）                                      │
│  ├─ PerceptionSystem.gd  - 贝叶斯感知系统                        │
│  │   ├─ 维护BeliefState（后验分布）                              │
│  │   ├─ 非线性拟合 G(t) = (S/a)[1 - exp(-at)]                   │
│  │   └─ 贝叶斯更新：后验 = 先验 × 似然                          │
│  │                                                               │
│  └─ 输出感知参数(Ŝ, â) 用于决策                                  │
│                                                                 │
│  先验差异: 健康Agent乐观(S=0.5), 抑郁Agent悲观(S=0.3)            │
└─────────────────────────────────────────────────────────────────┘
```

---

## 架构设计

### 类关系图

```
┌─────────────────┐         ┌─────────────────────┐
│   RoomArea      │◄────────│    RoomManager      │
│   (S, a, E)     │         │   (房间管理)         │
└────────┬────────┘         └─────────────────────┘
         │
         │ 读取参数
         ▼
┌─────────────────┐    signal    ┌─────────────────────┐
│  RewardSystem   │─────────────►│ AgentRewardReceiver │
│  (计算G(t))     │ reward_      │   (接收+噪声)        │
│                 │  distributed │                     │
└─────────────────┘              └──────────┬──────────┘
                                            │
                                            │ 添加样本
                                            ▼
                                   ┌─────────────────────┐
                                   │  PerceptionSystem   │
                                   │  (贝叶斯更新)        │
                                   │                     │
                                   │  ┌───────────────┐  │
                                   │  │  BeliefState  │  │
                                   │  │  (Ŝ, â)       │  │
                                   │  └───────────────┘  │
                                   └─────────────────────┘
```

### 数据流时序

```
t=0: Agent进入情境
    │
    ▼
t=5s: 第一次体验采样
    │
    ├── RewardSystem.distribute_reward(agent, room, 5s)
    │       │
    │       ├── 读取 RoomArea(S=0.8, a=0.3, E=0.2)
    │       ├── 计算 G(5) = (0.8/0.3)[1-exp(-0.3×5)] = 0.72
    │       └── 发射信号 reward_distributed(agent, "食堂", 5, 0.72, 0.2)
    │
    ├── AgentRewardReceiver._on_reward_received()
    │       │
    │       ├── 验证 agent_name 匹配
    │       ├── 添加噪声: σ = 0.02×(1-0.5×0.3) = 0.017
    │       ├── perceived = 0.72 + N(0, 0.017²) = 0.71
    │       └── 缓存到 reward_history
    │
    └── PerceptionSystem.add_sample(time=5, gain=0.71)
            │
            └── 添加到 belief.samples
    │
    ▼
t=10s: 第二次体验采样
    │
    ├── RewardSystem.distribute_reward(agent, room, 10s)
    │       └── G(10) = 0.85
    │
    ├── AgentRewardReceiver 接收并添加噪声 → 0.84
    │
    └── PerceptionSystem.add_sample(time=10, gain=0.84)
            │
            ├── samples.size() >= 3 ? 否，继续采样
            └── （等待更多样本）
    │
    ▼
t=15s: 第三次体验采样
    │
    ├── RewardSystem.distribute_reward(agent, room, 15s)
    │       └── G(15) = 0.91
    │
    ├── AgentRewardReceiver 接收并添加噪声 → 0.90
    │
    └── PerceptionSystem.add_sample(time=15, gain=0.90)
            │
            ├── samples.size() >= 3 ? 是，触发更新
            │
            └── _update_beliefs()
                    │
                    ├── 非线性拟合 G(t) = (S/a)[1-exp(-at)]
                    │   网格搜索最优 S, a
                    │   拟合结果: S=0.75, a=0.35
                    │
                    ├── 贝叶斯更新 S:
                    │   prior: S~N(0.3, 0.15)  (抑郁Agent悲观先验)
                    │   likelihood: S~N(0.75, 0.05)
                    │   posterior: S~N(0.58, 0.12)
                    │
                    └── 贝叶斯更新 a:
                        prior: a~N(0.6, 0.15)
                        likelihood: a~N(0.35, 0.05)
                        posterior: a~N(0.42, 0.12)
    │
    ▼
输出: 感知参数 Ŝ=0.58, â=0.42
```

---

## 系统层：RewardSystem

### 类定义

```gdscript
extends Node

# 注意：此类通过AutoLoad配置为单例
# 在project.godot中配置: RewardSystem="*res://script/system/RewardSystem.gd"

static var instance: RewardSystem

signal reward_distributed(agent_name: String, room_name: String, 
                          time: float, gain: float, effort: float)
```

### 核心函数

#### distribute_reward()

```gdscript
func distribute_reward(agent_name: String, room_name: String, 
                       time_in_room: float) -> Dictionary
```

**功能**: 向Agent发放奖赏（系统层唯一合法接口）

**输入参数**:
| 参数 | 类型 | 说明 |
|------|------|------|
| agent_name | String | 接收奖赏的Agent名称 |
| room_name | String | 情境/房间名称 |
| time_in_room | float | 在情境中停留的时间（秒） |

**返回值** (Dictionary):
| 键 | 类型 | 说明 |
|----|------|------|
| `gain` | float | 客观收益值（0-1） |
| `effort` | float | 情境的努力成本（0-1） |
| `room_name` | String | 房间名称 |
| `time` | float | 停留时间 |
| `error` | String | 错误信息（如有） |

**执行流程**:
```gdscript
func distribute_reward(agent_name, room_name, time_in_room):
    # 1. 获取房间客观参数（系统层内部操作，Agent不可见）
    room_data = _get_room_objective_params(room_name)
    S = room_data.S  # Agent不可见
    a = room_data.a  # Agent不可见
    E = room_data.E  # Agent不可见
    
    # 2. 计算客观收益 G(t) = (S/a)[1 - exp(-at)]
    actual_gain = _calculate_objective_gain(S, a, time_in_room)
    
    # 3. 发放奖赏（通过信号通知，Agent通过接收器订阅）
    reward_distributed.emit(agent_name, room_name, time_in_room, actual_gain, E)
    
    return {"gain": actual_gain, "effort": E, ...}
```

---

#### _calculate_objective_gain()

```gdscript
func _calculate_objective_gain(S: float, a: float, time: float) -> float
```

**功能**: 计算客观收益（系统层私有函数）

**输入参数**:
| 参数 | 类型 | 说明 |
|------|------|------|
| S | float | 初始收益率 |
| a | float | 收益衰减率 |
| time | float | 停留时间 |

**返回值**: float - 客观收益值（0-1）

**公式**:
```
G(t) = (S/a)[1 - exp(-at)]
```

**实现代码**:
```gdscript
func _calculate_objective_gain(S: float, a: float, time: float) -> float:
    if a < 0.001:
        a = 0.001  # 避免除零
    
    var gain = (S / a) * (1.0 - exp(-a * time))
    return clamp(gain, 0.0, 1.0)
```

**示例计算**:
| S | a | t | G(t) |
|---|---|---|------|
| 0.8 | 0.3 | 5s | 0.72 |
| 0.8 | 0.3 | 10s | 0.85 |
| 0.8 | 0.3 | 60s | 0.93 |

---

#### _get_room_objective_params()

```gdscript
func _get_room_objective_params(room_name: String) -> Dictionary
```

**功能**: 获取房间客观参数（系统层内部使用，Agent不可调用）

**⚠️ 警告**: 此函数仅供系统层组件调用，Agent不应直接访问

**输入参数**:
| 参数 | 类型 | 说明 |
|------|------|------|
| room_name | String | 房间名称 |

**返回值** (Dictionary):
| 键 | 类型 | 说明 |
|----|------|------|
| `S` | float | 初始收益率 |
| `a` | float | 收益衰减率 |
| `E` | float | 努力成本 |

**实现逻辑**:
```gdscript
func _get_room_objective_params(room_name: String) -> Dictionary:
    # 通过RoomManager获取，不直接暴露RoomArea节点
    room_manager = get_node("/root/School/RoomManager")
    
    if room_manager.has_method("get_room_objective_params_internal"):
        # 使用内部接口（推荐）
        return room_manager.get_room_objective_params_internal(room_name)
    else:
        # 降级方案（不推荐，但为了兼容性保留）
        return _fallback_get_room_params(room_name)
```

---

## 感知层：AgentRewardReceiver

### 类定义

```gdscript
class_name AgentRewardReceiver
extends Node

var ai_agent: AIAgent = null
var reward_history: Array = []
```

### 核心函数

#### _ready() - 初始化

```gdscript
func _ready()
```

**功能**: 初始化时连接RewardSystem信号

**执行逻辑**:
```gdscript
func _ready():
    # 连接RewardSystem的信号
    if RewardSystem.instance:
        RewardSystem.instance.reward_distributed.connect(_on_reward_received)
```

---

#### _on_reward_received()

```gdscript
func _on_reward_received(agent_name: String, room_name: String,
                         time: float, gain: float, effort: float) -> void
```

**功能**: 接收奖赏回调（信号处理函数）

**输入参数**:
| 参数 | 类型 | 说明 |
|------|------|------|
| agent_name | String | 接收者名称 |
| room_name | String | 房间名称 |
| time | float | 停留时间 |
| gain | float | 客观收益 |
| effort | float | 努力成本 |

**执行流程**:
```gdscript
func _on_reward_received(agent_name, room_name, time, gain, effort):
    # 1. 检查是否发给自己
    if agent_name != ai_agent.character.name:
        return  # 忽略其他Agent的奖赏
    
    # 2. 获取Agent的认知参数（用于计算感知噪声）
    personality = CharacterPersonality.get_personality(agent_name)
    cognitive = personality.get("cognitive_mechanism", {})
    eta_s = cognitive.get("eta_s", 0.5)
    eta_a = cognitive.get("eta_a", 0.5)
    
    # 3. 添加感知噪声
    perceived_gain = PerceptionSystem.perceive_gain(gain, eta_s, eta_a)
    
    # 4. 缓存奖赏
    reward_history.append({
        "room": room_name,
        "time": time,
        "gain": gain,
        "perceived_gain": perceived_gain,
        "effort": effort,
        "timestamp": Time.get_unix_time_from_system()
    })
    
    # 5. 传递给PerceptionSystem更新信念
    is_depression = personality.get("role_type", "") == "depression_risk_student"
    PerceptionSystem.add_sample(agent_name, room_name, time, gain, eta_s, eta_a, is_depression)
```

---

#### get_last_reward()

```gdscript
func get_last_reward() -> Dictionary
```

**功能**: 获取最近一次接收的奖赏

**返回值** (Dictionary):
| 键 | 类型 | 说明 |
|----|------|------|
| `room` | String | 房间名称 |
| `time` | float | 停留时间 |
| `gain` | float | 客观收益 |
| `perceived_gain` | float | 感知收益（加噪声后） |
| `effort` | float | 努力成本 |
| `timestamp` | int | Unix时间戳 |

**实现**:
```gdscript
func get_last_reward() -> Dictionary:
    if reward_history.size() > 0:
        return reward_history[-1]
    return {}
```

---

## 认知层：PerceptionSystem

### 类定义

```gdscript
class_name PerceptionSystem
extends Node

# 先验分布参数
const PRIOR_S_MEAN = 0.5
const PRIOR_S_VAR = 0.25
const PRIOR_A_MEAN = 0.5
const PRIOR_A_VAR = 0.25

# 抑郁风险Agent的悲观先验
const DEPRESSION_PRIOR_S_MEAN = 0.3
const DEPRESSION_PRIOR_S_VAR = 0.15
const DEPRESSION_PRIOR_A_MEAN = 0.6
const DEPRESSION_PRIOR_A_VAR = 0.15

# 感知噪声基准（极小，2%）
const BASE_PERCEPTION_NOISE = 0.02

# 信念缓存
static var agent_beliefs: Dictionary = {}
```

### BeliefState 类

```gdscript
class BeliefState:
    var S_mean: float      # 对初始收益率的后验均值
    var S_var: float       # 对初始收益率的后验方差
    var a_mean: float      # 对衰减率的后验均值
    var a_var: float       # 对衰减率的后验方差
    var samples: Array     # 观测样本缓存 [{time, gain}]
    var last_update_time: int  # 上次更新时间
    
    func _init(is_depression_risk: bool = false):
        if is_depression_risk:
            # 抑郁Agent：悲观先验
            S_mean = DEPRESSION_PRIOR_S_MEAN  # 0.3
            S_var = DEPRESSION_PRIOR_S_VAR    # 0.15
            a_mean = DEPRESSION_PRIOR_A_MEAN  # 0.6
            a_var = DEPRESSION_PRIOR_A_VAR    # 0.15
        else:
            # 健康Agent：中性先验
            S_mean = PRIOR_S_MEAN  # 0.5
            S_var = PRIOR_S_VAR    # 0.25
            a_mean = PRIOR_A_MEAN  # 0.5
            a_var = PRIOR_A_VAR    # 0.25
```

### 核心函数

#### perceive_gain()

```gdscript
static func perceive_gain(actual_gain: float, eta_s: float, eta_a: float) -> float
```

**功能**: 感知收益（添加极小的感知噪声）

**输入参数**:
| 参数 | 类型 | 说明 |
|------|------|------|
| actual_gain | float | 客观收益 |
| eta_s | float | 初始奖赏感知权重 |
| eta_a | float | 衰减率感知权重 |

**返回值**: float - 感知收益（加噪声后）

**噪声公式**:
```
avg_eta = (eta_s + eta_a) / 2
noise_std = BASE_PERCEPTION_NOISE × (1 - avg_eta × 0.3)
noise ~ N(0, noise_std²)
perceived = actual_gain + noise
```

**示例**:
| eta_s | eta_a | avg_eta | noise_std | 实际噪声范围 |
|-------|-------|---------|-----------|-------------|
| 0.5 | 0.5 | 0.5 | 0.017 | ±3.4% |
| 1.0 | 1.0 | 1.0 | 0.014 | ±2.8% |
| 0.3 | 0.3 | 0.3 | 0.018 | ±3.6% |

**实现代码**:
```gdscript
static func perceive_gain(actual_gain: float, eta_s: float, eta_a: float) -> float:
    var avg_eta = (eta_s + eta_a) / 2.0
    var noise_std = BASE_PERCEPTION_NOISE * (1.0 - avg_eta * 0.3)
    var noise = randfn(0.0, noise_std)
    return clamp(actual_gain + noise, 0.0, 1.0)
```

---

#### add_sample()

```gdscript
static func add_sample(agent_name: String, room_name: String, 
                       time: float, actual_gain: float,
                       eta_s: float, eta_a: float, 
                       is_depression_risk: bool = false) -> void
```

**功能**: 添加观测样本，触发信念更新

**输入参数**:
| 参数 | 类型 | 说明 |
|------|------|------|
| agent_name | String | Agent名称 |
| room_name | String | 房间名称 |
| time | float | 停留时间 |
| actual_gain | float | 客观收益 |
| eta_s | float | 初始奖赏感知权重 |
| eta_a | float | 衰减率感知权重 |
| is_depression_risk | bool | 是否是抑郁风险Agent |

**执行流程**:
```gdscript
static func add_sample(agent_name, room_name, time, actual_gain, eta_s, eta_a, is_depression_risk):
    # 1. 获取或创建信念状态
    belief = get_belief(agent_name, room_name, is_depression_risk)
    
    # 2. 感知收益（添加噪声）
    perceived_gain = perceive_gain(actual_gain, eta_s, eta_a)
    
    # 3. 添加样本
    belief.samples.append({"time": time, "gain": perceived_gain})
    
    # 4. 样本数量达到阈值时更新信念
    if belief.samples.size() >= 3:
        _update_beliefs(agent_name, room_name)
```

---

#### _update_beliefs()

```gdscript
static func _update_beliefs(agent_name: String, room_name: String) -> void
```

**功能**: 贝叶斯更新信念（使用非线性最小二乘拟合）

**输入参数**:
| 参数 | 类型 | 说明 |
|------|------|------|
| agent_name | String | Agent名称 |
| room_name | String | 房间名称 |

**执行流程**:
```gdscript
static func _update_beliefs(agent_name, room_name):
    belief = agent_beliefs[agent_name][room_name]
    
    # 1. 提取样本
    times = []
    gains = []
    for sample in belief.samples:
        times.append(sample.time)
        gains.append(sample.gain)
    
    # 2. 非线性最小二乘拟合 G(t) = (S/a)[1 - exp(-at)]
    # 网格搜索最优 S 和 a
    best_S = belief.S_mean
    best_a = belief.a_mean
    best_error = 999999.0
    
    S_candidates = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
    a_candidates = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
    
    for S in S_candidates:
        for a in a_candidates:
            if a < 0.01:
                continue
            total_error = 0.0
            for i in range(times.size()):
                t = times[i]
                observed = gains[i]
                predicted = (S / a) * (1.0 - exp(-a * t))
                error = pow(observed - predicted, 2)
                total_error += error
            
            if total_error < best_error:
                best_error = total_error
                best_S = S
                best_a = a
    
    # 3. 贝叶斯更新 S
    observation_variance = clamp(best_error / times.size(), 0.01, 0.25)
    prior_precision = 1.0 / belief.S_var
    likelihood_precision = 1.0 / observation_variance
    posterior_var = 1.0 / (prior_precision + likelihood_precision)
    posterior_mean = posterior_var * (prior_precision * belief.S_mean + 
                                      likelihood_precision * best_S)
    belief.S_mean = clamp(posterior_mean, 0.0, 1.0)
    belief.S_var = clamp(posterior_var, 0.01, 0.25)
    
    # 4. 贝叶斯更新 a（类似）
    # ...
    
    # 5. 清空样本缓存
    belief.samples.clear()
```

---

#### get_perceived_params()

```gdscript
static func get_perceived_params(agent_name: String, room_name: String,
                                 is_depression_risk: bool = false) -> Dictionary
```

**功能**: 获取感知到的情境参数

**输入参数**:
| 参数 | 类型 | 说明 |
|------|------|------|
| agent_name | String | Agent名称 |
| room_name | String | 房间名称 |
| is_depression_risk | bool | 是否是抑郁风险Agent |

**返回值** (Dictionary):
| 键 | 类型 | 说明 |
|----|------|------|
| `S` | float | 感知到的初始收益率 |
| `a` | float | 感知到的衰减率 |
| `S_uncertainty` | float | S的不确定性（标准差） |
| `a_uncertainty` | float | a的不确定性（标准差） |
| `confidence` | float | 总体置信度（0-1） |

**实现**:
```gdscript
static func get_perceived_params(agent_name, room_name, is_depression_risk):
    belief = get_belief(agent_name, room_name, is_depression_risk)
    
    return {
        "S": belief.S_mean,
        "a": belief.a_mean,
        "S_uncertainty": sqrt(belief.S_var),
        "a_uncertainty": sqrt(belief.a_var),
        "confidence": 1.0 - (belief.S_var + belief.a_var)
    }
```

---

#### get_belief_description()

```gdscript
static func get_belief_description(agent_name: String, room_name: String,
                                   is_depression_risk: bool = false) -> String
```

**功能**: 格式化信念状态为Prompt文本

**返回值**: String - 用于AI Prompt的描述文本

**输出示例**:
```
【你对当前情境的感知】
（基于你的经验和观察，你对这个情境有以下判断）
- 你觉得这个情境一开始能获得的收益：45%（较低）
- 你觉得收益消耗的速度：65%（较快）
- 你对这个情境还不太熟悉，判断可能不太准确
```

---

## 数据流详解

### 完整数据流

```
┌─────────────────────────────────────────────────────────────────┐
│  1. 体验采样触发（TimingSystem Click或定时器）                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. RewardSystem.distribute_reward(agent, room, time)            │
│     ├── 读取 RoomArea(S, a, E)  【Agent不可见】                  │
│     ├── 计算 G(t) = (S/a)[1 - exp(-at)]                         │
│     └── 发射信号 reward_distributed(agent, room, time, G, E)     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. AgentRewardReceiver._on_reward_received()                    │
│     ├── 验证 agent_name 匹配                                     │
│     ├── 获取认知参数(η_s, η_a)                                   │
│     ├── 计算噪声 σ = 0.02×(1-avg(η)×0.3)                        │
│     ├── perceived = G + N(0, σ²)                                │
│     ├── 缓存到 reward_history                                    │
│     └── PerceptionSystem.add_sample(time, perceived)             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. PerceptionSystem.add_sample()                                │
│     ├── 获取/创建 BeliefState                                    │
│     ├── 添加样本到 belief.samples                                │
│     └── 如果 samples.size() >= 3:                                │
│         └── _update_beliefs()                                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. PerceptionSystem._update_beliefs()                           │
│     ├── 提取样本(times, gains)                                   │
│     ├── 非线性拟合 G(t) = (S/a)[1 - exp(-at)]                   │
│     │   └── 网格搜索最优 S, a                                    │
│     ├── 贝叶斯更新 S: 后验 = 先验 × 似然                         │
│     ├── 贝叶斯更新 a: 后验 = 先验 × 似然                         │
│     └── 清空 samples                                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  6. 输出感知参数(Ŝ, â) 用于决策                                   │
│     PerceptionSystem.get_perceived_params()                      │
│     └── 返回 {"S": Ŝ, "a": â, "confidence": conf}               │
└─────────────────────────────────────────────────────────────────┘
```

---

## 核心公式

### 1. 客观收益函数

```
G(t) = (S/a)[1 - exp(-at)]

其中:
- S: 初始收益率 (0-1)
- a: 收益衰减率 (0-1)
- t: 停留时间 (秒)
- G(t): 累积收益 (0-1)
```

**特性**:
- 当 t → 0, G(t) → 0
- 当 t → ∞, G(t) → S/a
- 收益增长递减（指数衰减）

### 2. 感知噪声

```
perceived_gain = actual_gain + ε

其中:
ε ~ N(0, σ²)
σ = 0.02 × (1 - avg(η_s, η_a) × 0.3)
```

**设计原则**:
- 基础噪声仅2%（极小）
- 高η（感知权重高）→ 更低噪声
- 主要噪声在决策层，不在感知层

### 3. 贝叶斯更新

```
后验分布 = 先验分布 × 似然函数

对于参数 S:
先验: S ~ N(S_prior, σ²_prior)
似然: S ~ N(S_observed, σ²_observation)
后验: S ~ N(S_posterior, σ²_posterior)

其中:
1/σ²_posterior = 1/σ²_prior + 1/σ²_observation
S_posterior = σ²_posterior × (S_prior/σ²_prior + S_observed/σ²_observation)
```

### 4. 非线性拟合

```
最小化: Σ(observed_gain_i - predicted_gain_i)²

其中:
predicted_gain_i = (S/a)[1 - exp(-a × time_i)]

方法: 网格搜索（S ∈ {0.1, 0.2, ..., 1.0}, a ∈ {0.1, 0.2, ..., 1.0}）
```

---

## API参考

### RewardSystem

| 函数 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `distribute_reward()` | agent_name, room_name, time | Dictionary | 发放奖赏 |
| `_calculate_objective_gain()` | S, a, time | float | 计算客观收益 |
| `_get_room_objective_params()` | room_name | Dictionary | 获取房间参数（内部） |

### AgentRewardReceiver

| 函数 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `_on_reward_received()` | agent_name, room_name, time, gain, effort | void | 接收奖赏回调 |
| `get_last_reward()` | - | Dictionary | 获取最近奖赏 |

### PerceptionSystem

| 函数 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `perceive_gain()` | actual_gain, eta_s, eta_a | float | 添加感知噪声 |
| `add_sample()` | agent_name, room_name, time, gain, eta_s, eta_a, is_depression | void | 添加样本 |
| `_update_beliefs()` | agent_name, room_name | void | 贝叶斯更新（内部） |
| `get_perceived_params()` | agent_name, room_name, is_depression | Dictionary | 获取感知参数 |
| `get_belief_description()` | agent_name, room_name, is_depression | String | 格式化描述 |
| `predict_gain()` | agent_name, room_name, time, is_depression | float | 预测未来收益 |
| `reset_all_beliefs()` | - | void | 重置所有信念 |
| `reset_agent_beliefs()` | agent_name | void | 重置特定Agent信念 |

---

## 使用示例

### 示例1：发放奖赏

```gdscript
# 在TimingSystem的Click触发时发放奖赏
func _on_click_triggered(game_time, day, click_num):
    for agent in all_agents:
        var room_name = agent.get_current_room().room_name
        var time_in_room = 5.0  # 5秒体验采样
        
        # 发放奖赏
        var result = RewardSystem.instance.distribute_reward(
            agent.character.name,
            room_name,
            time_in_room
        )
        
        print("向 %s 发放奖赏: %.3f" % [agent.character.name, result.gain])
```

### 示例2：接收奖赏并更新信念

```gdscript
# AgentRewardReceiver自动处理
func _on_reward_received(agent_name, room_name, time, gain, effort):
    # 1. 验证是否发给自己
    if agent_name != ai_agent.character.name:
        return
    
    # 2. 获取认知参数
    var personality = CharacterPersonality.get_personality(agent_name)
    var cognitive = personality.get("cognitive_mechanism", {})
    var eta_s = cognitive.get("eta_s", 0.5)
    var eta_a = cognitive.get("eta_a", 0.5)
    
    # 3. 添加感知噪声（自动）
    var perceived_gain = PerceptionSystem.perceive_gain(gain, eta_s, eta_a)
    
    # 4. 更新信念（自动）
    var is_depression = personality.get("role_type", "") == "depression_risk_student"
    PerceptionSystem.add_sample(agent_name, room_name, time, gain, eta_s, eta_a, is_depression)
```

### 示例3：获取感知参数用于决策

```gdscript
# 在决策阶段获取感知参数
func _make_decision(perception):
    var personality = CharacterPersonality.get_personality(character.name)
    var is_depression = personality.get("role_type", "") == "depression_risk_student"
    
    # 获取感知参数
    var params = PerceptionSystem.get_perceived_params(
        character.name,
        perception.current_room,
        is_depression
    )
    
    print("感知到的初始收益: %.2f" % params.S)
    print("感知到的衰减率: %.2f" % params.a)
    print("置信度: %.2f" % params.confidence)
    
    # 用于构建Prompt...
```

### 示例4：预测未来收益

```gdscript
# 预测10秒后的收益
var predicted = PerceptionSystem.predict_gain(
    "StudentXiaoming",
    "食堂",
    10.0,  # 10秒后
    true   # 抑郁Agent
)

print("预测10秒后的收益: %.3f" % predicted)
```

### 示例5：重置信念（重新开始模拟）

```gdscript
# 重置所有Agent的所有信念
PerceptionSystem.reset_all_beliefs()

# 或重置特定Agent的信念
PerceptionSystem.reset_agent_beliefs("StudentXiaoming")
```

---

## 实现状态

### 已实现 ✅

| 组件 | 文件 | 功能状态 |
|------|------|---------|
| RewardSystem | `script/system/RewardSystem.gd` | ✅ 完整实现 |
| AgentRewardReceiver | `script/ai/AgentRewardReceiver.gd` | ✅ 完整实现 |
| PerceptionSystem | `script/ai/PerceptionSystem.gd` | ✅ 完整实现 |
| BeliefState | `PerceptionSystem.gd` 内部类 | ✅ 完整实现 |

### 核心功能检查表

| 功能 | 状态 | 说明 |
|------|------|------|
| 客观收益计算 G(t) | ✅ | RewardSystem._calculate_objective_gain() |
| 奖赏发放信号 | ✅ | RewardSystem.reward_distributed |
| 感知噪声添加 | ✅ | PerceptionSystem.perceive_gain() |
| 贝叶斯更新 | ✅ | PerceptionSystem._update_beliefs() |
| 非线性拟合 | ✅ | 网格搜索拟合 G(t) |
| 先验差异 | ✅ | 健康vs抑郁不同先验 |
| 信念缓存 | ✅ | agent_beliefs 字典 |
| 样本积累 | ✅ | 3个样本触发更新 |

### 关键参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 基础感知噪声 | 0.02 (2%) | BASE_PERCEPTION_NOISE |
| 健康Agent S先验 | 0.5 ± 0.25 | 中性乐观 |
| 抑郁Agent S先验 | 0.3 ± 0.15 | 悲观 |
| 健康Agent a先验 | 0.5 ± 0.25 | 中性 |
| 抑郁Agent a先验 | 0.6 ± 0.15 | 高估衰减 |
| 样本触发阈值 | 3 | 3个样本后更新信念 |
| S候选值 | 0.1-1.0 (步长0.1) | 网格搜索 |
| a候选值 | 0.1-1.0 (步长0.1) | 网格搜索 |

---

## 附录：与理论框架的对应

### 理论公式 vs 实现

| 理论公式 | 实现函数 | 文件 |
|---------|---------|------|
| G(t) = (S/a)[1 - exp(-at)] | _calculate_objective_gain() | RewardSystem.gd |
| 感知噪声 ε ~ N(0, σ²) | perceive_gain() | PerceptionSystem.gd |
| 贝叶斯更新：后验 ∝ 先验 × 似然 | _update_beliefs() | PerceptionSystem.gd |
| 非线性拟合 min Σ(G_obs - G_pred)² | _update_beliefs() | PerceptionSystem.gd |

### 理论假设验证

| 假设 | 实现 | 验证 |
|------|------|------|
| Agent不能直接读取S,a,E | 通过RewardSystem信号发放 | ✅ 已实现 |
| 客观收益所有Agent相同 | 统一计算G(t)后广播 | ✅ 已实现 |
| 感知噪声极小(σ=2%) | BASE_PERCEPTION_NOISE = 0.02 | ✅ 已实现 |
| 先验信念个体差异 | 健康/抑郁不同先验参数 | ✅ 已实现 |
| 主要噪声在决策层 | 感知噪声小，决策有ε | ✅ 已实现 |

---

*文档维护者：百舟楫*
*最后更新：2026-04-07*
*对应代码版本：main@1b2e539*