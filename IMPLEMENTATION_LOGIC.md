# 项目实现逻辑文档 - Godot-Microverse-predict

> 本文档用于维护项目的代码实现逻辑，记录各模块的职责、交互方式及与理论框架的对应关系。
> 
> **最后更新：** 2026-04-05

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
  - [2.11 DayNightSystem.gd](#211-daynightsystemgd)
  - [2.12 ScheduleSystem.gd](#212-schedulesystemgd)
- [三、关键实现问题](#三关键实现问题)
- [四、待办事项](#四待办事项)

---

## 一、项目架构总览

### 1.1 三层架构与代码映射（2026-04-05更新：感知层与系统层分离完成）

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 1: 客观现实（系统层）- Agent不可见 ⭐ 分离完成              │
│  ├─ RoomArea.gd          - 定义情境参数(S, a, E)                 │
│  ├─ RewardSystem.gd      - 【新增】奖赏发放中介 ⭐               │
│  ├─ RoomManager.gd       - 房间管理与内部接口 ⭐                 │
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
│  Layer 2: 感知推断（认知层）- 个体差异 ⭐ 分离完成                │
│  ├─ AgentRewardReceiver.gd - 【新增】Agent奖赏接收器 ⭐          │
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
│  ├─ AIAgent.gd           - Agent决策中枢 ⭐ 已移除直接RoomArea访问 │
│  └─ DynamicPersonality.gd - 动态特质管理（外部控制）              │
│                                                                 │
│  职责：计算主观效用，驱动行为决策                                  │
│  公式：U = G̃^α - β_effort × E                                   │
│  抑郁Agent：α↓ (0.55), β↑ (0.8)                                 │
│  健康Agent：α↑ (0.8), β↓ (0.4)                                  │
└─────────────────────────────────────────────────────────────────┘
```

**⭐ 2026-04-05重大更新**: 完成感知层与系统层分离，Agent不再直接访问RoomArea参数

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

**当前局限：**
- 贝叶斯更新使用简化线性回归
- 理论上应拟合 `G(t) = (S/a)[1 - exp(-at)]`

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
                                   alpha, beta_effort, p_base):
    # 离散搜索最优时间（当前实现）
    # 理论上应解析求解：g(T) = R_B(T)
```

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

**与理论框架的差距：**
- ✅ 感知参数已注入Prompt
- ✅ 效用参数已注入Prompt
- ❌ **MVT计算结果未直接驱动行为**
- ❌ `_get_perceived_optimal_time()` 定义但未调用

**关键待实现：**
```gdscript
# 应该在决策循环中调用：
var optimal_time = _get_perceived_optimal_time(room_name)
if time_in_room >= optimal_time:
    leave_current_room()  # MVT驱动离开
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

### 2.6 DynamicPersonality.gd - 动态特质管理 ⭐ 2026-04-05重大扩展

**职责：** 管理随时间变化的心理特质和认知计算机制参数

**核心功能（2026-04-05新增）：**

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

### 2.8 DailyReflectionSystem.gd - 每日反思系统 ⭐ 2026-04-05新增

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

### 2.8 CharacterController.gd - 角色控制器

**职责：** 执行物理层面的移动、交互、动画

**关键功能：**
| 功能 | 说明 |
|------|------|
| `move_to()` | 导航寻路移动 |
| `sit_on_chair()` | 坐下交互 |
| `update_animation()` | 动画状态更新 |
| `_calculate_avoidance_direction()` | 避障逻辑 |

**与AIAgent的关系：**
- AIAgent决策 → CharacterController执行
- 分离决策层与执行层

---

## 三、数据流详细说明

### 3.1 正常决策循环（2026-04-05更新：感知层与系统层分离）

```
[系统层] ⭐ Agent不可见
RewardSystem.distribute_reward(agent_name, room_name, time=5)
    ↓
内部读取 RoomArea(S=0.8, a=0.3, E=0.2) 【Agent不可访问】
    ↓
计算 G(t=5) = (0.8/0.3)[1-exp(-0.3×5)] = 0.72
    ↓
发射信号 reward_distributed(agent_name, "食堂", 5, 0.72, 0.2)

[感知层] ⭐ 接收信号
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

[决策层] ⭐ MVT驱动
AIAgent._check_mvt_leave_decision()
- 当前已停留5秒 < T*(13秒)
- 但效用开始下降，可能触发离开
    ↓
MVT决策：STAY / LEAVE / SWITCH
    ↓
CharacterController执行移动/交互
```

**⭐ 关键变更**: Agent不再直接访问RoomArea，只能通过RewardSystem接收奖赏

### 3.2 抑郁vs健康Agent差异示例

**相同情境：** 食堂(S=0.8, a=0.3, E=0.2)，停留5秒，客观收益=0.72

| 层面 | 健康Agent | 抑郁Agent |
|------|----------|----------|
| **感知** | Ŝ=0.78, â=0.32 | Ŝ=0.65, â=0.40（悲观估计） |
| **效用计算** | U = 0.72^0.8 - 0.4×0.2 = 0.67 | U = 0.65^0.55 - 0.8×0.2 = 0.31 |
| **决策倾向** | 效用为正，继续停留 | 效用较低，可能提前离开或回避 |

---

## 四、与理论框架的对应检查表（2026-04-05更新）

| 理论要求 | 实现状态 | 实现文件 | 备注 |
|---------|---------|---------|------|
| 三类智能体架构 | ✅ | CharacterPersonality.gd | 完整实现 |
| 情境参数(S,a,E) | ✅ | RoomArea.gd | 完整实现 |
| 客观收益函数G(t) | ✅ | RewardSystem.gd ⭐ | 系统层计算 |
| **感知层与系统层分离** | ✅ | 多层协作 ⭐ | **2026-04-05完成** |
| 贝叶斯感知系统 | ⚠️ | PerceptionSystem.gd | 简化实现 |
| 先验信念差异 | ✅ | PerceptionSystem.gd | 健康vs抑郁 |
| 感知噪声 | ✅ | PerceptionSystem.gd ⭐ | σ=2%，极小噪声 |
| 效用函数U=G^α-βE | ✅ | UtilitySystem.gd | 完整实现 |
| 参数个体差异 | ✅ | CharacterPersonality.gd | α和β差异 |
| MVT最优时间计算 | ⚠️ | UtilitySystem.gd | 离散搜索非解析解 |
| **MVT驱动行为决策** | ✅ | AIAgent.gd ⭐ | **2026-04-05实现** |
| PHQ-9动态追踪 | ⚠️ | DynamicPersonality.gd | 有变量未完整集成 |
| 记忆系统 | ✅ | MemoryManager.gd | 完整实现 |

**图例：** ✅ 完整实现 | ⚠️ 简化/部分实现 | ❌ 未实现  
**⭐** 2026-04-05新增或重大更新

---

## 五、关键待办事项（2026-04-05更新）

### 已完成的重大改进 ✅

1. **MVT驱动行为决策** ✅ 2026-04-05完成
   - 实现 `_check_mvt_leave_decision()` 函数
   - 三种触发条件：超过最优时间 / 效用为负 / 抑郁Agent提前离开
   - 实现 `_select_next_room_by_mvt()` 效用最大化选择

2. **感知层与系统层分离** ✅ 2026-04-05完成
   - 创建 `RewardSystem.gd` - 系统层奖赏发放
   - 创建 `AgentRewardReceiver.gd` - 感知层接收器
   - 修改 `AIAgent.gd` - 移除所有直接RoomArea访问
   - 修改 `RoomManager.gd` - 添加内部接口
   - 修改 `RoomArea.gd` - 移除直接暴露参数的接口
   - 配置 `AutoLoad` - RewardSystem设置为单例
   - Agent只能通过RewardSystem接收"奖赏"，不能直接读取S,a,E

3. **感知噪声调整** ✅ 2026-04-05完成
   - 将 `BASE_PERCEPTION_NOISE` 从0.1降至0.02（σ=2%）
   - 理论依据：主要噪声应在决策层（ε），感知层仅轻微不确定性

### 待完成事项 ⏳

### 高优先级
（暂无）

### 中优先级
1. **PHQ-9每日自评机制**
   - 完善抑郁水平的动态更新
   - 与行为反馈（任务成功/失败）关联

2. **贝叶斯更新优化**
   - 将线性回归改为非线性拟合
   - 拟合真实的 `G(t) = (S/a)[1 - exp(-at)]`

### 低优先级
3. **MVT解析解计算**
   - 当前离散搜索效率较低
   - 可改为解析求解最优时间

### 中优先级
3. **PHQ-9每日自评机制**
   - 完善抑郁水平的动态更新
   - 与行为反馈（任务成功/失败）关联

4. **贝叶斯更新优化**
   - 将线性回归改为非线性拟合
   - 拟合真实的 `G(t) = (S/a)[1 - exp(-at)]`

### 低优先级
5. **MVT解析解计算**
   - 当前离散搜索效率较低
   - 可改为解析求解最优时间

---

## 六、文件结构速查（2026-04-05更新：感知层分离）

```
res://
├── script/
│   ├── ai/                         # AI系统层
│   │   ├── AIAgent.gd              # Agent决策中枢 ⭐ 已移除RoomArea访问
│   │   ├── PerceptionSystem.gd     # 贝叶斯感知系统（Layer 2）
│   │   ├── UtilitySystem.gd        # 效用计算系统（Layer 3）
│   │   ├── AgentRewardReceiver.gd  # 【新增】Agent奖赏接收器 ⭐
│   │   ├── DynamicPersonality.gd   # 动态特质管理
│   │   ├── DialogManager.gd        # 对话管理
│   │   ├── ConversationManager.gd  # 对话内容生成
│   │   ├── APIManager.gd           # AI API调用
│   │   └── memory/
│   │       └── MemoryManager.gd    # 记忆系统
│   ├── system/                     # 【新增】系统层目录 ⭐
│   │   └── RewardSystem.gd         # 【新增】奖赏发放中介 ⭐
│   ├── CharacterPersonality.gd     # 角色人设配置
│   ├── CharacterController.gd      # 角色物理控制
│   ├── CharacterManager.gd         # 角色管理
│   ├── RoomArea.gd                 # 情境参数定义（Layer 1）
│   ├── RoomData.gd                 # 房间数据结构
│   ├── RoomManager.gd              # 房间管理 ⭐ 已添加内部接口
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
├── PROJECT_STRUCTURE.md            # 【新增】完整项目结构文档 ⭐
└── TODO_Perception_System_Separation_2026-04-05.md  # 【新增】分离实施待办 ⭐
```

**⭐ 2026-04-05新增文件**:
- `script/system/RewardSystem.gd` - 系统层奖赏发放
- `script/ai/AgentRewardReceiver.gd` - 感知层接收器
- `script/ai/DailyReflectionSystem.gd` - 每日反思与认知调整系统
- `PROJECT_STRUCTURE.md` - 完整项目结构文档
- `TODO_Perception_System_Separation_2026-04-05.md` - 分离实施待办
- `docs/DYNAMIC_PERSONALITY_DESIGN.md` - 动态人设设计文档
- `docs/DAILY_REFLECTION_DESIGN.md` - 每日反思设计文档

---

## 七、核心参数速查表

### 情境参数（RoomArea）
| 参数 | 范围 | 低 | 中 | 高 |
|------|------|----|----|----|
| S (initial_reward_rate) | 0.0-1.0 | 0.0-0.4 | 0.4-0.7 | 0.7-1.0 |
| a (reward_decay_rate) | 0.0-1.0 | 0.0-0.3 | 0.3-0.6 | 0.6-1.0 |
| E (effort_level) | 0.0-1.0 | 0.0-0.3 | 0.3-0.6 | 0.6-1.0 |

### 认知机制参数（CharacterPersonality）
| 参数 | 健康Agent | 抑郁Agent | 功能 |
|------|----------|----------|------|
| p_base | 0.5-0.6 | 0.3-0.4 | 离开阈值 |
| η_s | 0.5-0.7 | 异常 | 初始奖赏感知权重 |
| η_a | 0.5 | ↑ | 衰减率感知权重 |
| α | 0.8 | 0.5-0.6 | 收益敏感性 |
| β_effort | 0.4 | 0.8 | 努力敏感性（核心差异）|

---

---

## 八、最近更新记录

### 2026-04-05 重大更新日

#### 上午：感知层与系统层分离完成
- ✅ **MVT驱动行为决策实现** - AIAgent现在根据MVT计算结果直接驱动停留/离开行为
- ✅ **感知层与系统层分离全部完成** - Agent不再直接访问RoomArea参数
  - ✅ 新增RewardSystem.gd - 系统层奖赏发放中介
  - ✅ 新增AgentRewardReceiver.gd - 感知层奖赏接收器
  - ✅ 修改AIAgent.gd - 移除所有直接RoomArea访问
  - ✅ 修改RoomManager.gd - 添加内部接口
  - ✅ 修改RoomArea.gd - 移除直接暴露参数的接口
  - ✅ 配置AutoLoad - RewardSystem设置为单例
- ✅ **感知噪声调整** - 从10%降至2%（σ=0.02）
- ✅ **新增项目文档** - PROJECT_STRUCTURE.md, TODO_Perception_System_Separation_2026-04-05.md, docs/AUTOLOAD_SETUP.md

#### 下午：动态人设系统扩展
- ✅ **扩展DynamicPersonality.gd** - 新增事件反馈影响函数
  - `apply_task_feedback()` - 任务成功/失败影响
  - `apply_social_feedback()` - 社交互动影响
  - `apply_teacher_feedback()` - 教师评价影响
  - `daily_phq9_update()` - 每日PHQ-9更新
  - `_apply_boundary_protection()` - 边界保护机制
- ✅ **新增设计文档** - docs/DYNAMIC_PERSONALITY_DESIGN.md

#### 傍晚：每日反思系统实现
- ✅ **创建DailyReflectionSystem.gd** - 完整的每日反思与认知调整系统
  - LLM-based反思分析（情绪主题、关键事件、认知变化）
  - 四项认知参数动态调整（严重程度1-5映射到1%-12%）
  - 个体差异（抑郁Agent负面×1.5，健康Agent有韧性）
  - 完整PHQ-9九项评估（总分0-27，五个等级）
- ✅ **新增设计文档** - docs/DAILY_REFLECTION_DESIGN.md

---

*本文档应与PROJECT_OVERVIEW.md（理论基础）同步维护。*
