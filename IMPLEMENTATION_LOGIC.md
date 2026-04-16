# 项目实现逻辑文档 - Godot-Microverse-predict

> 本文档用于维护项目的代码实现逻辑，记录各模块的职责、交互方式及与理论框架的对应关系。

---

## 目录

- [一、项目架构总览](#一项目架构总览)
  - [1.1 三层架构与代码映射](#11-三层架构与代码映射)
  - [1.2 核心数据流](#12-核心数据流)
- [二、核心模块详解](#二核心模块详解)
  - [2.1 RoomArea.gd](#21-roomareagd)
  - [2.2 PerceptionSystem.gd](#22-perceptionsystemgd)
  - [2.3 UtilitySystem.gd](#23-utilitysystemgd)
  - [2.4 AIAgent.gd](#24-aiagentgd)
  - [2.5 CharacterPersonality.gd](#25-characterpersonalitygd)
  - [2.6 DynamicPersonality.gd](#26-dynamicpersonalitygd)
  - [2.7 MemoryManager.gd](#27-memorymanagergd)
  - [2.8 DailyReflectionSystem.gd](#28-dailyreflectionsystemgd)
  - [2.9 RewardSystem.gd](#29-rewardsystemgd)
  - [2.10 AgentRewardReceiver.gd](#210-agentrewardreceivergd)
- [三、数据流详细说明](#三数据流详细说明)
- [四、待办事项](#四待办事项)
- [五、文件结构速查](#五文件结构速查)
- [六、核心参数速查表](#六核心参数速查表)
- [七、MVT公式实现速查](#七mvt公式实现速查)

---

## 一、项目架构总览

### 1.1 三层架构与代码映射

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 1: 客观现实（系统层）- Agent不可见                        │
│  ├─ RoomArea.gd          - 定义情境参数(S, a, E)                 │
│  ├─ RewardSystem.gd      - 奖赏发放中介                          │
│  ├─ RoomManager.gd       - 房间管理与内部接口                    │
│  └─ RoomData.gd          - 房间数据结构                          │
│                                                                 │
│  职责：维护客观世界，通过RewardSystem发放"奖赏"                  │
│  原则：Agent不能直接读取S,a,E，只能接收系统发放的奖赏数值        │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    【通过RewardSystem发放】
                    （Agent只接收"奖赏"数值）
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  Layer 2: 感知推断（认知层）- 个体差异                           │
│  ├─ AgentRewardReceiver.gd - Agent奖赏接收器                     │
│  └─ PerceptionSystem.gd  - 贝叶斯感知系统                        │
│                                                                 │
│  职责：从奖赏序列推断情境特征，个体差异体现在先验和感知精度      │
│  • 健康Agent：中性乐观先验 S~Uniform(0.5, 0.25)                  │
│  • 抑郁Agent：悲观预期先验 S~Uniform(0.3, 0.15)                  │
│  • 感知噪声：极小（σ=2%），主要噪声在决策层                      │
└─────────────────────────────────────────────────────────────────┘
                              ↓
              【主观感知】(Ŝ, â, 不确定性)
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  Layer 3: 效用评估（决策层）                                      │
│  ├─ UtilitySystem.gd     - 效用计算与MVT决策                     │
│  ├─ AIAgent.gd           - Agent决策中枢                         │
│  └─ DynamicPersonality.gd - 动态特质管理（外部控制）              │
│                                                                 │
│  职责：计算主观效用，驱动行为决策                                  │
│  公式：U = G̃^α - β_effort × E                                   │
│  抑郁Agent：α↓ (0.55), β↑ (0.8)                                 │
│  健康Agent：α↑ (0.8), β↓ (0.4)                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 核心数据流

```
RoomArea(S,a,E) 
    ↓
系统计算 G(t) = (S/a)[1 - exp(-at)]
    ↓
发放【客观奖赏】给Agent
    ↓
PerceptionSystem: 接收奖赏 → 贝叶斯推断 → (Ŝ, â)
    ↓
UtilitySystem: 计算 U = (Ĝ)^α - β_effort × E
    ↓
AIAgent: 决策 → 行为执行
    ↓
CharacterController: 移动/交互/对话
```

---

## 二、核心模块详解

### 2.1 RoomArea.gd - 情境参数定义

**职责：** 定义MVT理论中的三类情境参数，计算客观收益

**关键属性：**
```gdscript
@export var initial_reward_rate: float = 0.5  # S: 初始收益率
@export var reward_decay_rate: float = 0.5    # a: 收益衰减率  
@export var effort_level: float = 0.5         # E: 努力成本
```

**与理论对应：**
- 完全对应理论文档中的情境参数表
- 食堂：S=0.8(高), a=0.3(慢), E=0.2(低) → 同伴互动
- 教室：S=0.5(中), a=0.7(快), E=0.8(高) → 课堂发言

**重要原则：**
- Agent**不应直接读取**这些参数
- 只能通过系统发放的"奖赏"间接感知

---

### 2.2 PerceptionSystem.gd - 贝叶斯感知系统

**职责：** 管理Agent对情境的主观感知，实现Layer 2的认知功能

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
| `predict_gain()` | 基于信念预测未来收益 |

**信念更新实现：**
- 使用非线性最小二乘拟合理论收益函数 `G(t) = (S/a)[1 - exp(-at)]`
- 通过网格搜索找到最优的 S 和 a 参数
- 后验 = 先验 × 似然（正态分布共轭先验）

---

### 2.3 UtilitySystem.gd - 效用计算系统

**职责：** 计算主观效用，实现Layer 3的决策功能

**核心公式实现：**
```gdscript
static func calculate_utility(gain: float, effort: float, 
                              alpha: float, beta_effort: float) -> float:
    var gain_utility = pow(max(gain, 0.0), alpha)  # G^α
    var effort_cost = beta_effort * effort          # β×E
    return gain_utility - effort_cost               # U = G^α - β×E
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
static func calculate_optimal_time(perceived_S, perceived_a, effort, 
                                   alpha, beta_effort, p_base, eta_s, eta_a):
    # 使用理论解析公式：
    # log(T) = log[ηS·log(S)] − log(ρbase) − βeffort·effort − ηa·log(a) + ε
    
    var term1 = log(eta_s * log(perceived_S))      # log[ηS·log(S)]
    var term2 = -log(p_base)                        # −log(ρbase)
    var term3 = -beta_effort * effort               # −βeffort·effort
    var term4 = -eta_a * log(perceived_a)           # −ηa·log(a)
    var epsilon = randfn(0.0, 0.1)                  # ε (随机噪声)
    
    var log_T = term1 + term2 + term3 + term4 + epsilon
    var optimal_time = exp(log_T)
    return clamp(optimal_time, 1.0, 60.0)
```

**公式说明：**
- 完全对应理论文档中的MVT停留时间预测公式
- 包含全部四个核心认知参数：ρ_base, η_s, η_a, β_effort
- ε 为决策层随机噪声（标准差0.1）

---

### 2.4 AIAgent.gd - Agent决策中枢

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
# _check_mvt_leave_decision() 已实现完整MVT决策逻辑
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

### 2.5 CharacterPersonality.gd - 角色人设配置

**职责：** 定义三类智能体的基线参数

**角色类型：**
| 角色 | role_type | 核心特征 |
|------|-----------|---------|
| TeacherWang/PrincipalLi/LibrarianZhang | teacher | 制度性环境 |
| StudentXiaoming | depression_risk_student | 高β_effort(0.8), 低α(0.55) |
| StudentXiaohong/StudentXiaogang | healthy_student | 正常参数 |

**配置结构：**
```gdscript
"StudentXiaoming": {
    "role_type": "depression_risk_student",
    "demographics": {...},        # 人口学
    "big_five": {...},            # 大五人格
    "initial_depression": {...},  # PHQ-9基线
    "functioning_level": {...},   # 功能水平
    "specific_ability": {...},    # 专能性
    "cognitive_mechanism": {      # MVT核心参数
        "p_base": 0.4,
        "eta_s": 0.6,
        "eta_a": 0.7,
        "beta_effort": 0.8,       # 核心差异参数
        "alpha": 0.55
    }
}
```

---

### 2.6 DynamicPersonality.gd - 动态特质管理

**职责：** 管理随时间变化的心理特质和认知计算机制参数

**核心功能：**

| 函数 | 触发条件 | 影响 |
|------|---------|------|
| `apply_task_feedback()` | 任务完成/失败 | beta_effort, p_base, daily_depression_level |
| `apply_social_feedback()` | 社交互动后 | daily_depression_level, eta_s, beta_effort |
| `apply_teacher_feedback()` | 收到评价后 | beta_effort, daily_depression_level |
| `daily_phq9_update()` | 每日结束 | 基于当日事件净变化更新抑郁水平 |
| `_apply_boundary_protection()` | 所有更新 | 防止偏离基线超过20% |

**可动态调整的特质（四项认知机制）：**
```gdscript
var base_traits = {
    "daily_depression_level": 0.5,  # 当日抑郁水平
    "p_base": 0.5,                  # 离开阈值
    "eta_s": 0.5,                   # 初始奖赏感知权重
    "eta_a": 0.5,                   # 衰减率感知权重
    "beta_effort": 0.5              # 努力敏感性（核心差异指标）
}
```

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

**使用方式：**
```gdscript
# 方式1: 直接更新（带原因说明）
DynamicPersonality.update_trait(
    character, 
    "beta_effort", 
    -0.05, 
    "任务成功增强自信，降低努力敏感性"
)

# 方式2: 调用封装好的反馈函数
DynamicPersonality.apply_task_feedback(
    character, 
    success=true, 
    effort_level=0.8
)
```

---

### 2.7 MemoryManager.gd - 记忆系统

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
- 任务成功/失败记忆通过外部系统影响动态特质
- **每日反思的基础**：所有当日记忆被收集用于反思分析

---

### 2.8 DailyReflectionSystem.gd - 每日反思系统

**职责：** 每日结束时自动反思，动态调整认知参数，完成PHQ-9评估

**核心流程：**
```
收集当日记忆 → LLM反思分析 → 参数调整决策 → 动态幅度计算 → PHQ-9评估 → 记录结果
```

**关键函数：**

| 函数 | 职责 |
|------|------|
| `conduct_daily_reflection()` | 主入口，执行完整流程 |
| `_analyze_reflection()` | LLM分析当日经历，输出情绪主题和认知变化 |
| `_decide_cognitive_adjustments()` | LLM判断四项参数调整方向和严重程度 |
| `_calculate_adjustment_magnitude()` | 基于严重程度(1-5)和个体差异计算幅度 |
| `_conduct_phq9_assessment()` | LLM评估PHQ-9九项症状 |

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

**使用方式：**
```gdscript
# 每日结束时调用
func _on_day_end():
    var result = await DailyReflectionSystem.conduct_daily_reflection(character)
    # result包含: reflection_report, adjustments, phq9_assessment
```

---

### 2.9 RewardSystem.gd - 奖赏发放中介

**职责：** 系统层核心组件，封装RoomArea访问，计算并发放奖赏

**核心功能：**
- 封装RoomArea访问（Agent不可见）
- 计算客观收益 G(t) = (S/a)[1 - exp(-at)]
- 通过信号向Agent发放奖赏

**设计原则：** Agent不能直接读取S,a,E，只能通过此接口接收"奖赏"

**信号：** `reward_distributed(agent_name, room_name, time, gain, effort)`

---

### 2.10 AgentRewardReceiver.gd - Agent奖赏接收器

**职责：** Agent端的奖赏接收器，感知层组件

**核心功能：**
- 订阅RewardSystem信号
- 接收并缓存奖赏历史
- 添加感知噪声（极小）
- 传递给PerceptionSystem

**依赖：** RewardSystem, PerceptionSystem

---

## 三、数据流详细说明

### 3.1 正常决策循环

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

**关键变更**: Agent不再直接访问RoomArea，只能通过RewardSystem接收奖赏

### 3.2 抑郁vs健康Agent差异示例

**相同情境：** 食堂(S=0.8, a=0.3, E=0.2)，停留5秒，客观收益=0.72

| 层面 | 健康Agent | 抑郁Agent |
|------|----------|----------|
| **感知** | Ŝ=0.78, â=0.32 | Ŝ=0.65, â=0.40（悲观估计） |
| **效用计算** | U = 0.72^0.8 - 0.4×0.2 = 0.67 | U = 0.65^0.55 - 0.8×0.2 = 0.31 |
| **决策倾向** | 效用为正，继续停留 | 效用较低，可能提前离开或回避 |

---

## 四、待办事项

### 高优先级
（暂无）

### 中优先级
1. **PHQ-9每日自评机制**
   - 完善抑郁水平的动态更新
   - 与行为反馈（任务成功/失败）关联

### 低优先级
2. **性能优化**
   - API调用批处理
   - 决策缓存机制

---

## 五、文件结构速查

```
res://
├── script/
│   ├── ai/                         # AI系统层
│   │   ├── AIAgent.gd              # Agent决策中枢
│   │   ├── PerceptionSystem.gd     # 贝叶斯感知系统（Layer 2）
│   │   ├── UtilitySystem.gd        # 效用计算系统（Layer 3）
│   │   ├── AgentRewardReceiver.gd  # Agent奖赏接收器
│   │   ├── DynamicPersonality.gd   # 动态特质管理
│   │   ├── DialogueManager.gd      # 对话管理
│   │   ├── ConversationManager.gd  # 对话内容生成
│   │   ├── APIManager.gd           # AI API调用
│   │   └── memory/
│   │       └── MemoryManager.gd    # 记忆系统
│   ├── system/                     # 系统层目录
│   │   └── RewardSystem.gd         # 奖赏发放中介
│   ├── CharacterPersonality.gd     # 角色人设配置
│   ├── CharacterController.gd      # 角色物理控制
│   ├── CharacterManager.gd         # 角色管理
│   ├── RoomArea.gd                 # 情境参数定义（Layer 1）
│   ├── RoomData.gd                 # 房间数据结构
│   ├── RoomManager.gd              # 房间管理
│   └── ...
├── scene/
│   ├── maps/
│   │   └── School.tscn             # 学校主场景
│   ├── characters/
│   │   └── *.tscn                  # 角色场景
│   └── ui/
│       └── *.tscn                  # UI场景
├── PROJECT_OVERVIEW.md             # 理论基础文档
├── IMPLEMENTATION_LOGIC.md         # 实现逻辑文档（本文档）
└── PROJECT_STRUCTURE.md            # 完整项目结构文档
```

---

## 六、核心参数速查表

### 情境参数（RoomArea）
| 参数 | 范围 | 低 | 中 | 高 |
|------|------|----|----|----|
| S (initial_reward_rate) | 0.0-1.0 | 0.0-0.4 | 0.4-0.7 | 0.7-1.0 |
| a (reward_decay_rate) | 0.0-1.0 | 0.0-0.3 | 0.3-0.6 | 0.6-1.0 |
| E (effort_level) | 0.0-1.0 | 0.0-0.3 | 0.3-0.6 | 0.6-1.0 |

### 认知机制参数（CharacterPersonality）
| 参数 | 健康Agent | 抑郁Agent | 功能 |
|------|----------|----------|------|
| ρ_base | 0.5-0.6 | 0.3-0.4 | 离开阈值（环境平均奖赏率估计）|
| η_s | 0.5 | 0.4 | 初始奖赏感知权重 |
| η_a | 0.5 | 0.7 | 衰减率感知权重 |
| α | 0.8 | 0.5-0.6 | 收益敏感性 |
| β_effort | 0.4 | 0.8 | 努力敏感性（核心差异）|

---

## 七、MVT公式实现速查

### 7.1 客观收益函数（RewardSystem.gd）
```gdscript
# G(t) = (S/a)[1 - exp(-at)]
func _calculate_objective_gain(S: float, a: float, time: float) -> float:
    var gain = (S / a) * (1.0 - exp(-a * time))
    return clamp(gain, 0.0, 1.0)
```

### 7.2 主观效用函数（UtilitySystem.gd）
```gdscript
# U(G) = G^α - β_effort × E
static func calculate_utility(gain: float, effort: float, 
                              alpha: float, beta_effort: float) -> float:
    var gain_utility = pow(max(gain, 0.0), alpha)
    var effort_cost = beta_effort * effort
    return gain_utility - effort_cost
```

### 7.3 最优停留时间公式（UtilitySystem.gd）
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

### 7.4 信念更新（PerceptionSystem.gd）
```gdscript
# 使用非线性最小二乘拟合 G(t) = (S/a)[1 - exp(-at)]
# 网格搜索最优 S 和 a，然后贝叶斯更新
```

---

*本文档应与PROJECT_OVERVIEW.md（理论基础）同步维护。*
