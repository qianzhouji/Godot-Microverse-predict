# 项目结构与实现逻辑文档 - Godot-Microverse-predict

> **文档用途**: 维护项目所有脚本的完整清单、职责说明、架构关系及实现逻辑

---

## 目录

- [一、项目概述](#一项目概述)
- [二、目录结构总览](#二目录结构总览)
- [三、核心脚本清单](#三核心脚本清单)
- [四、三层架构与数据流](#四三层架构与数据流)
- [五、核心模块详解](#五核心模块详解)
- [六、数据流详细说明](#六数据流详细说明)
- [七、AutoLoad配置](#七autoload配置)
- [八、核心参数速查表](#八核心参数速查表)
- [九、MVT公式实现速查](#九mvt公式实现速查)
- [十、文档关联](#十文档关联)

---

## 一、项目概述

**项目名称**: Godot-Microverse-predict  
**核心目标**: 基于努力决策理论和边际价值定理(MVT)，模拟抑郁风险学生与健康学生在校园情境中的行为差异  
**技术栈**: Godot 4.x, GDScript, LLM API

---

## 二、目录结构总览

```
res://
├── script/                          # 核心脚本目录
│   ├── ai/                          # AI系统层
│   ├── system/                      # 系统层
│   ├── ui/                          # UI系统
│   ├── utils/                       # 工具脚本
│   └── *.gd                         # 根级脚本
├── scene/                           # 场景资源
│   ├── maps/                        # 地图场景
│   ├── characters/                  # 角色场景
│   └── ui/                          # UI场景
├── assets/                          # 美术资源
└── *.md                             # 项目文档
```

---

## 三、核心脚本清单

> **详细技术说明请参考**: [docs/TECHNICAL_DOCUMENTATION.md](./docs/TECHNICAL_DOCUMENTATION.md)

### 3.1 AI系统层 (script/ai/)

| 脚本 | 类型 | 核心职责 |
|------|------|----------|
| AIAgent.gd | Node | Agent决策中枢，认知循环（感知→体验→决策→执行） |
| PerceptionSystem.gd | 静态类 | 贝叶斯感知系统，情境参数推断 |
| UtilitySystem.gd | 静态类 | MVT效用计算与最优停留时间决策 |
| AgentRewardReceiver.gd | Node | 奖赏接收器，感知层组件 |
| DynamicPersonality.gd | 静态类 | 动态特质管理，PHQ-9评估与参数调整 |
| DialogueManager.gd | Node | 统一对话管理器（大/中/小三种范围） |
| SpeakerQueueManager.gd | Node | 智能发言队列管理 |
| PromptBuilder.gd | 静态类 | Prompt模板构建 |
| DailyReflectionSystem.gd | 静态类 | 每日反思与认知机制动态调整 |
| memory/MemoryManager.gd | AutoLoad | 记忆系统管理 |
| memory/MemorySystem.gd | AutoLoad | 分层记忆架构（事件/社交/情感） |

### 3.2 系统层 (script/system/)

| 脚本 | 类型 | 核心职责 |
|------|------|----------|
| TimingSystem.gd | 单例 | 中央时序系统，Click周期管理 |
| ActivityCoordinator.gd | 单例 | LLM协调器，活动分配 |
| ActivityManager.gd | AutoLoad | 活动生命周期管理 |
| RewardSystem.gd | 单例 | 奖赏发放中介，客观收益计算 |
| TimelineState.gd | AutoLoad | 课程表与行为约束 |
| Logger.gd | AutoLoad | 游戏日志系统（活动/移动/对话） |

### 3.3 角色系统 (script/)

| 脚本 | 类型 | 核心职责 |
|------|------|----------|
| CharacterPersonality.gd | 静态类 | 13个角色的完整人设配置 |
| CharacterController.gd | CharacterBody2D | 角色物理控制与移动 |
| CharacterManager.gd | AutoLoad | 角色注册与批量管理 |

### 3.4 房间/情境系统 (script/)

| 脚本 | 类型 | 核心职责 |
|------|------|----------|
| RoomArea.gd | Area2D | 情境参数定义（S, a, E） |
| RoomManager.gd | Node | 房间管理与中范围划分 |

### 3.5 UI系统 (script/ui/)

- MainMenu.gd, DialogBubble.gd, GodUI.gd
- CharacterAISettings.gd, GlobalSettingsUI.gd, SaveLoadUI.gd

### 3.6 工具脚本 (script/utils/)

- APIConfig.gd, Config.gd

---

## 四、三层架构与数据流

### 4.1 架构图

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: 客观现实（系统层）- Agent不可见                      │
│  ├─ RoomArea.gd          - 定义情境参数(S, a, E)             │
│  ├─ RewardSystem.gd      - 计算客观收益，发放奖赏            │
│  └─ RoomManager.gd       - 房间管理                          │
│                                                              │
│  原则：Agent不能直接引用RoomArea，不能读取S,a,E              │
└─────────────────────────────────────────────────────────────┘
                              ↓
                    【通过RewardSystem发放】
                    （Agent只接收"奖赏"数值）
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  Layer 2: 感知推断（认知层）- 个体差异                         │
│  ├─ AgentRewardReceiver.gd - 接收奖赏，添加感知噪声          │
│  └─ PerceptionSystem.gd  - 贝叶斯感知，推断情境参数          │
│                                                              │
│  原则：Agent只能通过接收器获取奖赏，据此推断(Ŝ, â)           │
│  噪声设计：感知噪声极小(σ=2%)，主要噪声在决策层(ε)           │
└─────────────────────────────────────────────────────────────┘
                              ↓
                    【主观感知】(Ŝ, â, 不确定性)
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  Layer 3: 效用评估（决策层）- 核心差异                         │
│  ├─ UtilitySystem.gd     - 效用计算与MVT决策                 │
│  ├─ AIAgent.gd           - Agent决策中枢                     │
│  └─ DynamicPersonality.gd - 动态特质管理                     │
│                                                              │
│  原则：计算主观效用，驱动行为决策                              │
│  公式：U = G̃^α - β_effort × E                               │
│  噪声：决策噪声ε（理论公式中的误差项）                        │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 数据流详解

```
[体验采样触发]
        ↓
[AIAgent] 请求 RewardSystem.distribute_reward()
        ↓
[RewardSystem] 读取 RoomArea 客观参数 (S,a,E) 【系统层内部】
        ↓
[RewardSystem] 计算客观收益 G(t) = (S/a)[1 - exp(-at)]
        ↓
[RewardSystem] 发射信号 reward_distributed
        ↓
[AgentRewardReceiver] 接收信号（只处理自己的）
        ↓
[AgentRewardReceiver] 添加极小感知噪声(σ≈2%) → 感知收益
        ↓
[PerceptionSystem] 添加样本 → 贝叶斯更新 → 信念状态(Ŝ, â)
        ↓
[AIAgent] 从 PerceptionSystem 获取感知参数
        ↓
[UtilitySystem] 计算最优停留时间 T* 和当前效用 U
        ↓
[AIAgent] MVT决策（是否离开）+ 决策噪声ε
        ↓
[CharacterController] 执行移动/交互
```

---

## 五、核心模块详解

### 5.1 RoomArea.gd - 情境参数定义

**职责：** 定义MVT理论中的三类情境参数

**关键属性：**
```gdscript
@export var initial_reward_rate: float = 0.5  # S: 初始收益率
@export var reward_decay_rate: float = 0.5    # a: 收益衰减率  
@export var effort_level: float = 0.5         # E: 努力成本
```

**重要原则：** Agent**不应直接读取**这些参数，只能通过系统发放的"奖赏"间接感知

---

### 5.2 PerceptionSystem.gd - 贝叶斯感知系统

**职责：** 管理Agent对情境的主观感知

**核心类：**
```gdscript
class BeliefState:
    var S_mean: float      # 对初始收益率的后验估计
    var S_var: float       # 估计的不确定性
    var a_mean: float      # 对衰减率的后验估计
    var a_var: float
    var samples: Array     # 观测样本缓存
```

**个体差异实现：**
```gdscript
# 健康Agent：中性乐观先验
const PRIOR_S_MEAN = 0.5
const PRIOR_S_VAR = 0.25

# 抑郁Agent：悲观预期先验
const DEPRESSION_PRIOR_S_MEAN = 0.3
const DEPRESSION_PRIOR_S_VAR = 0.15
```

**关键函数：**
| 函数 | 职责 |
|------|------|
| `add_sample()` | 接收系统奖赏，添加感知噪声 |
| `_update_beliefs()` | 贝叶斯更新后验信念 |
| `get_perceived_params()` | 输出感知到的情境参数(Ŝ, â) |

**信念更新实现：**
- 使用非线性最小二乘拟合理论收益函数 `G(t) = (S/a)[1 - exp(-at)]`
- 通过网格搜索找到最优的 S 和 a 参数

---

### 5.3 UtilitySystem.gd - 效用计算系统

**职责：** 计算主观效用，实现MVT决策

**核心公式实现：**
```gdscript
# U(G) = G^α - β_effort × E
static func calculate_utility(gain: float, effort: float, 
                              alpha: float, beta_effort: float) -> float:
    var gain_utility = pow(max(gain, 0.0), alpha)
    var effort_cost = beta_effort * effort
    return gain_utility - effort_cost
```

**个体差异参数：**
```gdscript
const DEFAULT_ALPHA = 0.8           # 健康Agent
const DEFAULT_BETA_EFFORT = 0.4     # 健康Agent
const DEPRESSION_ALPHA = 0.55       # 抑郁Agent（收益贬值）
const DEPRESSION_BETA_EFFORT = 0.8  # 抑郁Agent（努力放大）
```

**最优停留时间计算：**
```gdscript
# log(T) = log[ηS·log(S)] − log(ρbase) − βeffort·effort − ηa·log(a) + ε
static func calculate_optimal_time(perceived_S, perceived_a, effort, 
                                   alpha, beta_effort, p_base, eta_s, eta_a):
    var term1 = log(eta_s * log(perceived_S))
    var term2 = -log(p_base)
    var term3 = -beta_effort * effort
    var term4 = -eta_a * log(perceived_a)
    var epsilon = randfn(0.0, 0.1)
    var log_T = term1 + term2 + term3 + term4 + epsilon
    return clamp(exp(log_T), 1.0, 60.0)
```

---

### 5.4 AIAgent.gd - Agent决策中枢

**职责：** 整合感知、效用、记忆，驱动Agent行为

**当前决策流程：**
```
1. 生成场景描述（包含感知参数）
2. 构建Prompt（人格+状态+记忆+情境）
3. 调用LLM生成决策
4. 执行行为（移动/对话/任务）
```

**MVT驱动行为决策实现：**
```gdscript
func _check_mvt_leave_decision(room_name, time_in_room, personality, is_depression):
    var params = UtilitySystem.get_agent_utility_params(personality)
    var optimal_time = UtilitySystem.calculate_optimal_time(
        perceived_S, perceived_a, effort, 
        params.alpha, params.beta_effort, 
        params.p_base, params.eta_s, params.eta_a
    )
    
    var should_leave = time_in_room >= optimal_time
    return {
        "should_leave": should_leave,
        "optimal_time": optimal_time,
        "reason": "MVT预测的最优停留时间"
    }
```

---

### 5.5 CharacterPersonality.gd - 角色人设配置

**职责：** 定义三类智能体的基线参数

**角色类型：**
| 角色 | role_type | 核心特征 |
|------|-----------|---------|
| TeacherWang/PrincipalLi/LibrarianZhang | teacher | 制度性环境 |
| StudentXiaoming | depression_risk_student | 高β_effort(0.8), 低α(0.55) |
| StudentXiaohong/StudentXiaogang | healthy_student | 正常参数 |

**MVT核心参数配置：**
```gdscript
"StudentXiaoming": {
    "role_type": "depression_risk_student",
    "cognitive_mechanism": {
        "p_base": 0.4,
        "eta_s": 0.6,
        "eta_a": 0.7,
        "beta_effort": 0.8,       # 核心差异参数
        "alpha": 0.55
    }
}
```

---

### 5.6 DynamicPersonality.gd - 动态特质管理

**职责：** 管理随时间变化的心理特质和认知计算机制参数

**核心功能：**

| 函数 | 触发条件 | 影响 |
|------|---------|------|
| `apply_task_feedback()` | 任务完成/失败 | beta_effort, p_base, daily_depression_level |
| `apply_social_feedback()` | 社交互动后 | daily_depression_level, eta_s, beta_effort |
| `apply_teacher_feedback()` | 收到评价后 | beta_effort, daily_depression_level |
| `daily_phq9_update()` | 每日结束 | 基于当日事件净变化更新抑郁水平 |
| `_apply_boundary_protection()` | 所有更新 | 防止偏离基线超过20% |

**个体差异设计：**
```gdscript
# 抑郁Agent（如StudentXiaoming）
- 基线: beta_effort = 0.8
- 负面事件影响: ×1.5（恶化更快）
- 正面事件影响: ×0.7（恢复更慢）
- 边界: [0.6, 1.0]

# 健康Agent（如StudentXiaohong）
- 基线: beta_effort = 0.4
- 负面事件影响: ×0.8（有韧性）
- 正面事件影响: ×1.2（恢复更快）
- 边界: [0.2, 0.6]
```

---

### 5.7 MemoryManager.gd - 记忆系统

**职责：** 管理Agent的经验记忆，影响后续决策

**记忆类型：**
```gdscript
enum MemoryType {
    PERSONAL,      # 个人记忆
    INTERACTION,   # 互动记忆
    TASK,          # 任务记忆
    EMOTION,       # 情感记忆
    EVENT          # 事件记忆
}
```

**与理论关联：**
- 记忆影响Agent的先验信念
- 负面记忆可能强化抑郁Agent的悲观预期
- **每日反思的基础**：所有当日记忆被收集用于反思分析

---

### 5.8 DailyReflectionSystem.gd - 每日反思系统

**职责：** 每日结束时自动反思，动态调整认知参数，完成PHQ-9评估

**核心流程：**
```
收集当日记忆 → LLM反思分析 → 参数调整决策 → 动态幅度计算 → PHQ-9评估 → 记录结果
```

**动态幅度计算：**
```gdscript
# 严重程度 → 基础幅度
1 → ±1%    # 轻微
2 → ±3%    # 轻度
3 → ±5%    # 中度
4 → ±8%    # 重度
5 → ±12%   # 严重

# 最终幅度 = 基础幅度 × 个体差异乘数
# 抑郁Agent负面: ×1.5, 正面: ×0.7
# 健康Agent负面: ×0.8, 正面: ×1.2
```

**PHQ-9评估：**
- 九项症状，每项0-3分
- 总分0-27，转换为抑郁水平(0-1)
- 五个等级：无/轻度/中度/中重度/重度抑郁

---

### 5.9 RewardSystem.gd - 奖赏发放中介

**职责：** 系统层核心组件，封装RoomArea访问，计算并发放奖赏

**核心功能：**
- 封装RoomArea访问（Agent不可见）
- 计算客观收益 G(t) = (S/a)[1 - exp(-at)]
- 通过信号向Agent发放奖赏

**设计原则：** Agent不能直接读取S,a,E，只能通过此接口接收"奖赏"

**信号：** `reward_distributed(agent_name, room_name, time, gain, effort)`

---

### 5.10 AgentRewardReceiver.gd - Agent奖赏接收器

**职责：** Agent端的奖赏接收器，感知层组件

**核心功能：**
- 订阅RewardSystem信号
- 接收并缓存奖赏历史
- 添加感知噪声（σ=2%）
- 传递给PerceptionSystem

---

## 六、数据流详细说明

### 6.1 正常决策循环

```
[系统层] - Agent不可见
RewardSystem.distribute_reward(agent_name, room_name, time=5)
    ↓
内部读取 RoomArea(S=0.8, a=0.3, E=0.2) 【Agent不可访问】
    ↓
计算 G(t=5) = (0.8/0.3)[1-exp(-0.3×5)] = 0.72
    ↓
发射信号 reward_distributed(agent_name, "食堂", 5, 0.72, 0.2)

[感知层] - 接收信号
AgentRewardReceiver._on_reward_received()
    ↓
添加极小噪声(σ=2%) → 感知gain = 0.71
    ↓
PerceptionSystem.add_sample(time=5, gain=0.71)
    ↓
贝叶斯更新 → Ŝ=0.74, â=0.32

[效用层]
UtilitySystem.calculate_optimal_time(Ŝ=0.74, â=0.32, E=0.2, 
                                     α=0.55, β=0.8, p_base=0.4)
    ↓
计算得最优时间 T* = 13秒

[决策层] - MVT驱动
AIAgent._check_mvt_leave_decision()
- 当前已停留5秒 < T*(13秒)
- 但效用开始下降，可能触发离开
    ↓
MVT决策：STAY / LEAVE / SWITCH
    ↓
CharacterController执行移动/交互
```

### 6.2 抑郁vs健康Agent差异示例

**相同情境：** 食堂(S=0.8, a=0.3, E=0.2)，停留5秒，客观收益=0.72

| 层面 | 健康Agent | 抑郁Agent |
|------|----------|----------|
| **感知** | Ŝ=0.78, â=0.32 | Ŝ=0.65, â=0.40（悲观估计） |
| **效用计算** | U = 0.72^0.8 - 0.4×0.2 = 0.67 | U = 0.65^0.55 - 0.8×0.2 = 0.31 |
| **决策倾向** | 效用为正，继续停留 | 效用较低，可能提前离开或回避 |

---

## 七、AutoLoad配置

在Godot项目设置中，以下脚本应配置为AutoLoad：

| 脚本路径 | 单例名 | 用途 |
|---------|-------|------|
| script/ai/APIManager.gd | APIManager | API调用管理 |
| script/ai/memory/MemoryManager.gd | MemoryManager | 记忆系统 |
| script/ai/DialogManager.gd | DialogManager | 对话管理 |
| script/CharacterManager.gd | CharacterManager | 角色管理 |
| script/system/RewardSystem.gd | RewardSystem | 奖赏系统 |
| script/system/TimelineState.gd | TimelineState | 课程表与行为约束 |
| script/system/Logger.gd | Logger | 日志系统 |

---

## 八、核心参数速查表

### 8.1 情境参数（RoomArea）
| 参数 | 范围 | 低 | 中 | 高 |
|------|------|----|----|----|
| S (initial_reward_rate) | 0.0-1.0 | 0.0-0.4 | 0.4-0.7 | 0.7-1.0 |
| a (reward_decay_rate) | 0.0-1.0 | 0.0-0.3 | 0.3-0.6 | 0.6-1.0 |
| E (effort_level) | 0.0-1.0 | 0.0-0.3 | 0.3-0.6 | 0.6-1.0 |

### 8.2 认知机制参数（CharacterPersonality）
| 参数 | 健康Agent | 抑郁Agent | 功能 |
|------|----------|----------|------|
| ρ_base | 0.5-0.6 | 0.3-0.4 | 离开阈值（环境平均奖赏率估计）|
| η_s | 0.5 | 0.4 | 初始奖赏感知权重 |
| η_a | 0.5 | 0.7 | 衰减率感知权重 |
| α | 0.8 | 0.5-0.6 | 收益敏感性 |
| β_effort | 0.4 | 0.8 | 努力敏感性（核心差异）|

---

## 九、MVT公式实现速查

### 9.1 客观收益函数（RewardSystem.gd）
```gdscript
# G(t) = (S/a)[1 - exp(-at)]
func _calculate_objective_gain(S: float, a: float, time: float) -> float:
    var gain = (S / a) * (1.0 - exp(-a * time))
    return clamp(gain, 0.0, 1.0)
```

### 9.2 主观效用函数（UtilitySystem.gd）
```gdscript
# U(G) = G^α - β_effort × E
static func calculate_utility(gain: float, effort: float, 
                              alpha: float, beta_effort: float) -> float:
    var gain_utility = pow(max(gain, 0.0), alpha)
    var effort_cost = beta_effort * effort
    return gain_utility - effort_cost
```

### 9.3 最优停留时间公式（UtilitySystem.gd）
```gdscript
# log(T) = log[ηS·log(S)] − log(ρbase) − βeffort·effort − ηa·log(a) + ε
static func calculate_optimal_time(perceived_S, perceived_a, effort,
                                   alpha, beta_effort, p_base, eta_s, eta_a):
    var term1 = log(eta_s * log(perceived_S))
    var term2 = -log(p_base)
    var term3 = -beta_effort * effort
    var term4 = -eta_a * log(perceived_a)
    var epsilon = randfn(0.0, 0.1)
    var log_T = term1 + term2 + term3 + term4 + epsilon
    return clamp(exp(log_T), 1.0, 60.0)
```

### 9.4 信念更新（PerceptionSystem.gd）
```gdscript
# 使用非线性最小二乘拟合 G(t) = (S/a)[1 - exp(-at)]
# 网格搜索最优 S 和 a，然后贝叶斯更新
```

---

## 十、文档关联

| 文档 | 用途 |
|------|------|
| [README.md](./README.md) | 项目简介、理论基础和研究设计 |
| [本文档](./PROJECT_STRUCTURE.md) | 项目结构、脚本清单与实现逻辑 |
| [docs/TECHNICAL_DOCUMENTATION.md](./docs/TECHNICAL_DOCUMENTATION.md) | 系统架构与技术实现详情 |
| [docs/Dialogue_System.md](./docs/Dialogue_System.md) | 对话系统设计 |

---

*本文档由AI助手百舟楫维护*
