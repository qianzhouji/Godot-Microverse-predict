# Godot-Microverse-predict 技术文档

> **项目**: 抑郁风险学生校园情境模拟系统  
> **仓库**: https://github.com/qianzhouji/Godot-Microverse-predict  
> **最后更新**: 2026-04-15

---

## 目录

1. [项目概述](#项目概述)
2. [系统架构总览](#系统架构总览)
3. [第一层：中央时序系统](#第一层中央时序系统)
4. [第二层：活动管理系统](#第二层活动管理系统)
5. [第三层：Agent认知与决策系统](#第三层agent认知与决策系统)
6. [第四层：感知与记忆系统](#第四层感知与记忆系统)
7. [第五层：客观现实系统](#第五层客观现实系统)
8. [对话系统](#对话系统)
9. [MVT理论实现](#mvt理论实现)
10. [项目配置](#项目配置)
11. [文件索引](#文件索引)

---

## 项目概述

### 研究目标

基于**努力决策理论**和**边际价值定理(MVT)**，构建AI Agent模拟系统，探究**抑郁风险青少年**与**健康青少年**在动态社会情境中的认知机制差异。

### 核心研究问题

- 抑郁风险学生是否对**努力成本**过度敏感？
- 抑郁风险学生是否对**奖赏衰减**感知异常？
- 这些认知偏差如何影响其**情境选择**和**社交行为**？

### 理论框架

**边际价值定理 (Marginal Value Theorem)**:
```
log(T) = log[η_s · log(S)] − log(ρ_base) − β_effort · effort − η_a · log(a) + ε
```

| 参数 | 符号 | 抑郁风险 | 健康 | 含义 |
|------|------|---------|------|------|
| 离开阈值 | ρ_base | 0.3-0.4 | 0.5-0.6 | 对环境平均奖赏率的估计 |
| 初始奖赏感知权重 | η_s | 0.4 | 0.5 | 对初始丰富度的敏感度 |
| 衰减率感知权重 | η_a | 0.7 | 0.5 | 对奖赏衰减的敏感度 |
| 努力敏感性 | β_effort | **0.8** | **0.4** | **核心差异参数** |
| 收益敏感性 | α | 0.55 | 0.8 | 收益的非线性效用 |

---

## 系统架构总览

### 五层架构设计

```
┌─────────────────────────────────────────────────────────────────┐
│  第一层：中央时序系统 (TimingSystem)                              │
│  ├─ 全局时钟管理：5分钟游戏时间 = 1个Click周期                    │
│  ├─ 上升沿触发：所有Agent同步开始认知循环                         │
│  └─ 协调器调度：ActivityCoordinator LLM驱动决策分配               │
└─────────────────────────────────────────────────────────────────┘
                              ↓ 触发
┌─────────────────────────────────────────────────────────────────┐
│  第二层：活动管理系统                                             │
│  ├─ ActivityCoordinator：收集决策 → LLM协调 → 分配活动序列        │
│  ├─ ActivityManager：活动生命周期管理、累积奖赏计算               │
│  └─ 专注度系统：30%/65%/100% 三档，影响努力成本与奖赏收益         │
└─────────────────────────────────────────────────────────────────┘
                              ↓ 下发活动
┌─────────────────────────────────────────────────────────────────┐
│  第三层：Agent认知与决策系统                                      │
│  ├─ AIAgent：认知循环中枢（感知 → 体验 → 决策 → 执行）            │
│  ├─ 自然语言决策：生成意图描述，提交协调器                        │
│  ├─ 三步活动缓存：支持复杂多步活动序列                            │
│  └─ 活动中决策：每次Click评估继续/停止/更换                       │
└─────────────────────────────────────────────────────────────────┘
                              ↓ 调用
┌─────────────────────────────────────────────────────────────────┐
│  第四层：感知与记忆系统                                           │
│  ├─ PerceptionSystem：贝叶斯感知、信念更新、情境推断              │
│  ├─ MemorySystem：分层记忆架构（事件/社交/情感）                  │
│  │   ├─ EventMemory：活动事件历史记录                             │
│  │   ├─ SocialMemory：社交关系与互动历史                          │
│  │   └─ EmotionMemory：情感态度与变化追踪                         │
│  └─ DynamicPersonality：动态特质管理（PHQ-9评估、参数调整）       │
└─────────────────────────────────────────────────────────────────┘
                              ↓ 读取/写入
┌─────────────────────────────────────────────────────────────────┐
│  第五层：客观现实系统                                             │
│  ├─ RoomArea：定义情境参数 (S, a, E)                              │
│  ├─ RewardSystem：计算客观收益 G(t) = (S/a)[1 - exp(-at)]         │
│  ├─ RoomManager：房间管理与中范围划分                             │
│  └─ TimelineState：课程表与行为约束                               │
└─────────────────────────────────────────────────────────────────┘
```

### 数据流向

```
客观现实 (S, a, E)
      ↓
RewardSystem 计算 G(t)
      ↓
Agent接收奖赏数值
      ↓
PerceptionSystem 贝叶斯推断 (Ŝ, â)
      ↓
UtilitySystem MVT决策
      ↓
AIAgent 生成自然语言意图
      ↓
ActivityCoordinator LLM协调
      ↓
下发活动序列 → 执行 → 记录记忆
```

---

## 第一层：中央时序系统

### TimingSystem.gd

**核心职责**：提供全局时钟，Click周期触发所有Agent同步活动。

#### Click周期机制

```
现实时间          游戏时间
─────────        ─────────
  2分钟     =     5分钟 (1 Click)
  1秒       =     2.5秒
  
一天时长：约22现实分钟（8:00-17:30）
```

#### 时序流程

```
Click N 触发
    │
    ├── 发射 click_triggered 信号
    │       └── 所有AIAgent._on_click_triggered()
    │
    ├── AIAgent._perform_v2_cognitive_cycle()
    │       ├── 感知环境
    │       ├── 体验累积奖赏（如正在活动中）
    │       ├── 自然语言决策
    │       └── submit_decision() → ActivityCoordinator
    │
    ├── 等待 0.5秒收集所有决策
    │
    ├── ActivityCoordinator.execute_coordination()
    │       ├── _build_coordination_input() - 构建上下文
    │       ├── _call_llm() - LLM协调分配
    │       ├── _parse_coordination_response() - 解析响应
    │       └── _distribute_activities() - 下发活动
    │
    └── Click结束，等待下一个周期

Click N+1
    └── AIAgent._execute_next_cached_activity() - 执行缓存活动
```

#### 每日流程

| 时间 | 事件 | 说明 |
|------|------|------|
| 8:00 | 游戏日开始 | 所有Agent初始化，开始认知循环 |
| 8:00-17:00 | 正常运行 | 每5分钟一个Click周期 |
| 17:00 | 放学时间 | 不接受新的开始请求，只允许结束当前活动 |
| 17:30 | 强制结束 | 所有Agent进入反思阶段，更新记忆和情感关系 |

---

## 第二层：活动管理系统

### 2.1 ActivityCoordinator.gd

**核心职责**：中央协调器，收集所有Agent的自然语言决策，调用LLM进行活动分配。

#### 工作流程

```
1. submit_decision(agent_id, decision)
   └── pending_decisions[agent_id] = decision

2. execute_coordination()
   ├── _build_coordination_input() - 构建游戏上下文
   ├── _build_coordination_prompt() - 构建LLM Prompt
   ├── _call_llm() - 调用本地LLM (qwen2.5:1.5b)
   ├── _parse_coordination_response() - 解析JSON响应
   │       └── 支持多种字段名：assignments/agents/steps/activities
   └── _distribute_activities() - 下发活动序列
```

#### 双向奔赴机制

**原则**：只有双方意图匹配时才协调到相同位置，否则各自独立行动。

```
示例1：双向奔赴 ✅
小明: "我想和小红讨论数学"
小红: "我想和小明讨论数学"
→ LLM检测到匹配
→ 计算中间位置
→ 双方分配到相同目标

示例2：单向扑空 ❌
小明: "我想和小红悄悄话"
小红: "我想去图书馆自习"
→ 非双向奔赴
→ 各自独立执行
→ 小明到达后发现小红不在，下次决策处理
```

### 2.2 ActivityManager.gd

**核心职责**：管理Agent活动生命周期，计算累积奖赏。

#### 活动类型

| 活动类型 | 场景限制 | 专注度 | 说明 |
|----------|----------|--------|------|
| MOVE_TO | 无 | 无 | 移动到目标位置 |
| NORMAL_DIALOGUE | 无 | 无 | 普通对话（中范围） |
| WHISPER | 无 | 无 | 悄悄话（贴身50px） |
| LISTEN | 教室 | 30/65/100 | 听课 |
| QA_TEACHER | 教室 | 30/65/100 | 课堂问答 |
| SELF_STUDY | 图书馆/自习室 | 30/65/100 | 自习 |
| SPORTS | 体育馆/操场 | 30/65/100 | 体育活动 |
| GROUP_DISCUSSION | 教室/讨论室 | 30/65/100 | 小组讨论（2-7人） |

#### 专注度系统

| 档位 | 值 | 努力成本 | 奖赏收益 | 信息接收 |
|------|-----|----------|----------|----------|
| LOW | 30% | ×0.3 | ×0.3 | 30% |
| MEDIUM | 65% | ×0.65 | ×0.65 | 65% |
| HIGH | 100% | ×1.0 | ×1.0 | 100% |

#### 累积奖赏计算

```
每个Click触发时：
    1. 计算本次持续时间
    2. 累积总持续时间
    3. 计算累积收益 G(t) = (S/a)[1 - exp(-at)]
    4. 应用专注度调整：adjusted_gain = gain × focus_level
    5. 通过RewardSystem发放奖赏增量
```

### 2.3 Activity.gd

**核心职责**：活动数据结构，支持专注度和参数传递。

```gdscript
class Activity:
    var activity_id: String
    var activity_type: ActivityType
    var parameters: Dictionary
    var focus_level: FocusLevel  # LOW/MEDIUM/HIGH
    var step_index: int  # 在多步序列中的位置
```

---

## 第三层：Agent认知与决策系统

### 3.1 AIAgent.gd

**核心职责**：Agent认知循环中枢，执行感知→体验→决策→执行流程。

#### 认知循环流程

```
_on_click_triggered()
    │
    ├── 检查活动缓存
    │       ├── 有缓存 → _execute_next_cached_activity()
    │       └── 无缓存 → _perform_v2_cognitive_cycle()
    │
    └── _perform_v2_cognitive_cycle()
            ├── _perform_perception() - 感知环境
            │       ├── 获取当前房间、中范围
            │       ├── 获取可见Agent列表
            │       └── 获取当前活动信息
            │
            ├── _perform_experience() - 体验累积奖赏（如正在活动中）
            │       ├── 获取当前累积收益
            │       ├── MVT决策：是否达到最优时间
            │       └── 决定继续/停止/更换
            │
            ├── _make_natural_decision() - 自然语言决策
            │       ├── 构建Prompt（人设+状态+环境+记忆）
            │       ├── 调用LLM生成意图描述
            │       └── 解析为决策文本
            │
            └── submit_decision() → ActivityCoordinator
```

#### 三步活动缓存

```
场景：小明想和不在同一中范围的小红对话

决策结果（3步缓存）：
├─ Step1: MOVE_TO → 进入小红所在中范围
├─ Step2: NORMAL_DIALOGUE → 开始对话
└─ Step3: 设置专注度65%

Click N:   执行Step1（移动）
Click N+1: 执行Step2（开始对话）
Click N+2: 执行Step3（专注度设置）
```

#### Agent状态机

```gdscript
enum AgentState {
    IDLE,               # 空闲
    PERCEIVING,         # 感知中
    EXPERIENCING,       # 体验中
    DECIDING,           # 决策中
    WAITING_FOR_CLICK,  # 等待Click执行
    EXECUTING_ACTION,   # 执行行动中
    IN_DIALOGUE,        # 在对话中
    IN_ACTIVITY,        # 在活动中
    MOVING              # 移动中
}
```

### 3.2 中范围划分系统

**目的**：将大房间划分为子区域，实现更精细的空间感知和社交范围控制。

| 房间类型 | 划分方式 | 区域标识 |
|----------|----------|----------|
| 教室/图书馆/自习室/食堂 | 4象限 | Q1(右上), Q2(左上), Q3(左下), Q4(右下) |
| 大走廊 | 左右2区 | LEFT, RIGHT |
| 小走廊 | 单区域 | CENTER |

---

## 第四层：感知与记忆系统

### 4.1 PerceptionSystem.gd

**核心职责**：贝叶斯感知，从奖赏序列推断情境特征。

#### 贝叶斯推断流程

```
接收奖赏数值序列
    ↓
非线性最小二乘拟合
    ↓
估计情境参数 (Ŝ, â)
    ↓
计算不确定性
    ↓
更新信念状态
```

#### 个体差异（先验分布）

| Agent类型 | S先验 | 含义 |
|-----------|-------|------|
| 健康 | Uniform(0.5, 0.25) | 中性乐观 |
| 抑郁风险 | Uniform(0.3, 0.15) | 悲观预期 |

### 4.2 MemorySystem.gd

**核心职责**：分层记忆架构，统一接口管理事件、社交、情感记忆。

#### 架构设计

```
MemorySystem (主控)
    │
    ├── EventMemory - 事件记忆
    │       └── 记录：移动、对话、上课、自习、体育等活动
    │
    ├── SocialMemory - 社交记忆
    │       └── 记录：互动历史、关系分数(-1.0~1.0)、互动统计
    │
    └── EmotionMemory - 情感记忆
            └── 记录：好感、信任、尊重、恐惧、厌恶、愤怒
```

#### 集成点

| 调用方 | 记录内容 | 方法 |
|--------|----------|------|
| AIAgent._execute_v2_* | 各类活动事件 | record_agent_activity() |
| AIAgent._execute_v2_dialogue | 对话社交互动 | record_interaction() |
| AIAgent._execute_v2_whisper | 悄悄话社交互动 | record_interaction() |
| AIAgent._execute_v2_discussion | 小组讨论互动 | record_interaction() |
| ActivityCoordinator | 活动分配事件 | record_agent_activity() |
| ActivityManager | 活动开始/结束 | record_event() |
| DialogueManager | 对话摘要、社交互动 | add_memory(), record_interaction() |

#### 数据持久化

```
user://memory/
├── global_memory.json           # 全局配置
├── agents/
│   ├── StudentXiaoming.json     # 每个Agent的记忆
│   ├── StudentXiaohong.json
│   └── ...
└── relationships/
    ├── StudentXiaoming_StudentXiaohong.json
    └── ...
```

### 4.3 DynamicPersonality.gd

**核心职责**：动态特质管理，PHQ-9评估，认知参数调整。

#### 每日反思流程

```
conduct_daily_reflection(character)
    │
    ├── _collect_daily_memories() - 收集当日记忆
    ├── _analyze_reflection() - LLM分析情绪主题
    ├── _decide_cognitive_adjustments() - 决定参数调整
    ├── _apply_cognitive_adjustments() - 应用调整
    ├── _conduct_phq9_assessment() - PHQ-9评估
    └── _update_depression_level() - 更新抑郁水平
```

---

## 第五层：客观现实系统

### 5.1 RoomArea.gd

**核心职责**：定义情境参数 (S, a, E)。

| 参数 | 符号 | 范围 | 含义 |
|------|------|------|------|
| 初始奖赏 | S | 0-1 | 情境的初始丰富度 |
| 衰减率 | a | 0-1 | 奖赏随时间的衰减速度 |
| 努力成本 | E | 0-1 | 维持活动所需的努力 |

### 5.2 RewardSystem.gd

**核心职责**：计算客观收益，发放奖赏。

#### 收益函数

```gdscript
# G(t) = (S/a)[1 - exp(-at)]
func calculate_gain(S: float, a: float, time: float) -> float:
    return (S / a) * (1.0 - exp(-a * time))
```

#### 三层奖赏架构

```
Layer 1: RoomArea - 定义客观参数 (S, a, E)
    ↓
Layer 2: RewardSystem - 计算 G(t)，发放奖赏数值
    ↓
Layer 3: AgentRewardReceiver - Agent接收奖赏
    ↓
Layer 4: PerceptionSystem - 从奖赏推断情境
```

### 5.3 RoomManager.gd

**核心职责**：房间管理，中范围划分，内部接口。

### 5.4 TimelineState.gd

**核心职责**：课程表管理，行为约束。

---

## 对话系统

### 6.1 架构设计

```
MultiAgentDialogueIntegration (统一集成接口)
    │
    ├── GroupDialogueManager - 群组对话管理（2-7人）
    │       ├── 三种范围：WHISPER(50px)/NORMAL(200px)/BROADCAST(全房间)
    │       └── 与中范围系统对接
    │
    ├── DialogueInterruptionManager - 对话打断/插入机制
    │       └── 四种模式：礼貌/紧急/随意/旁听
    │
    ├── DialogueContextManager - 对话上下文同步
    │       └── 确保多方对话内容一致性
    │
    └── SpeakerQueueManager - 智能发言队列
            └── 基于优先级的发言管理
```

### 6.2 对话范围

| 范围 | 距离 | 人数 | 特点 |
|------|------|------|------|
| WHISPER | 50px | 2-3人 | 私密，不允许第三方加入 |
| NORMAL | 200px | 2-7人 | 中范围内可加入 |
| BROADCAST | 全房间 | 2-7人 | 跨中范围，公开讨论 |

### 6.3 发言队列优先级

```
当前优先级 = 基础优先级(10-90)
         + 连续发言惩罚(-20×n)
         + 沉默奖励(+5/轮, max+15)
         + 被打断补偿(+10)
         + 话题相关度加成(±20)
         + 发言意愿加成(±10)
```

---

## MVT理论实现

### 7.1 核心公式

#### 客观收益函数
```gdscript
# G(t) = (S/a)[1 - exp(-at)]
func calculate_objective_gain(S: float, a: float, time: float) -> float:
    var gain = (S / a) * (1.0 - exp(-a * time))
    return clamp(gain, 0.0, 1.0)
```

#### 主观效用函数
```gdscript
# U = G^α - β_effort × E
func calculate_utility(gain: float, effort: float, 
                       alpha: float, beta_effort: float) -> float:
    var gain_utility = pow(max(gain, 0.0), alpha)
    var effort_cost = beta_effort * effort
    return gain_utility - effort_cost
```

#### 最优停留时间
```gdscript
# log(T) = log[η_s·log(S)] − log(ρ_base) − β_effort·effort − η_a·log(a) + ε
func calculate_optimal_time(perceived_S, perceived_a, effort,
                            alpha, beta_effort, p_base, eta_s, eta_a):
    var term1 = log(eta_s * log(perceived_S))
    var term2 = -log(p_base)
    var term3 = -beta_effort * effort
    var term4 = -eta_a * log(perceived_a)
    var epsilon = randfn(0.0, 0.1)
    return clamp(exp(term1 + term2 + term3 + term4 + epsilon), 1.0, 60.0)
```

### 7.2 决策逻辑

```
当前已停留时间 t
    ↓
计算最优停留时间 T_optimal
    ↓
比较：t >= T_optimal ?
    ├── 是 → 应该离开（边际收益 <= 边际成本）
    └── 否 → 继续停留（边际收益 > 边际成本）
```

---

## 项目配置

### AutoLoad配置

| 顺序 | 脚本路径 | 单例名 |
|------|---------|--------|
| 1 | `script/RoomManager.gd` | RoomManager |
| 2 | `script/system/RewardSystem.gd` | RewardSystem |
| 3 | `script/ai/APIManager.gd` | APIManager |
| 4 | `script/ai/memory/MemoryManager.gd` | MemoryManager |
| 5 | `script/CharacterManager.gd` | CharacterManager |
| 6 | `script/system/TimingSystem.gd` | TimingSystem |
| 7 | `script/system/TimelineState.gd` | TimelineState |
| 8 | `script/system/ActivityManager.gd` | ActivityManager |
| 9 | `script/system/ActivityCoordinator.gd` | ActivityCoordinator |
| 10 | `script/ai/DialogueManager.gd` | DialogueManager |
| 11 | `script/ai/memory/MemorySystem.gd` | MemorySystem |

### LLM配置

| 用途 | 模型 | 温度 | 最大Token |
|------|------|------|----------|
| 协调器 | qwen2.5:1.5b | 0.3 | 2000 |
| Agent决策 | qwen2.5:7b/14b | 0.7 | 500 |

---

## 文件索引

### 核心系统

| 文件 | 路径 | 说明 |
|------|------|------|
| TimingSystem.gd | `script/system/TimingSystem.gd` | 中央时序系统 |
| TimelineState.gd | `script/system/TimelineState.gd` | 课程表管理 |
| ActivityManager.gd | `script/system/ActivityManager.gd` | 活动生命周期 |
| ActivityCoordinator.gd | `script/system/ActivityCoordinator.gd` | 活动协调器 |
| Activity.gd | `script/system/Activity.gd` | 活动数据结构 |
| RewardSystem.gd | `script/system/RewardSystem.gd` | 奖赏系统 |
| RoomManager.gd | `script/RoomManager.gd` | 房间管理 |
| RoomArea.gd | `script/RoomArea.gd` | 房间区域定义 |

### AI核心

| 文件 | 路径 | 说明 |
|------|------|------|
| AIAgent.gd | `script/ai/AIAgent.gd` | Agent认知循环 |
| PromptBuilder.gd | `script/ai/PromptBuilder.gd` | Prompt构建器 |
| PerceptionSystem.gd | `script/ai/PerceptionSystem.gd` | 贝叶斯感知 |
| AgentRewardReceiver.gd | `script/ai/AgentRewardReceiver.gd` | 奖赏接收器 |
| UtilitySystem.gd | `script/ai/UtilitySystem.gd` | MVT效用计算 |
| DynamicPersonality.gd | `script/ai/DynamicPersonality.gd` | 动态特质管理 |
| DailyReflectionSystem.gd | `script/ai/DailyReflectionSystem.gd` | 每日反思 |

### 记忆系统

| 文件 | 路径 | 说明 |
|------|------|------|
| MemorySystem.gd | `script/ai/memory/MemorySystem.gd` | 记忆系统主控 |
| EventMemory.gd | `script/ai/memory/EventMemory.gd` | 事件记忆 |
| SocialMemory.gd | `script/ai/memory/SocialMemory.gd` | 社交记忆 |
| EmotionMemory.gd | `script/ai/memory/EmotionMemory.gd` | 情感记忆 |
| MemoryPersistence.gd | `script/ai/memory/MemoryPersistence.gd` | 持久化存储 |
| MemoryFormatter.gd | `script/ai/memory/MemoryFormatter.gd` | 格式化工具 |
| MemoryManager.gd | `script/ai/memory/MemoryManager.gd` | 兼容层 |

### 对话系统

| 文件 | 路径 | 说明 |
|------|------|------|
| DialogueManager.gd | `script/ai/DialogueManager.gd` | 对话管理器 |
| GroupDialogueManager.gd | `script/ai/GroupDialogueManager.gd` | 群组对话管理 |
| DialogueInterruptionManager.gd | `script/ai/DialogueInterruptionManager.gd` | 打断/插入机制 |
| DialogueContextManager.gd | `script/ai/DialogueContextManager.gd` | 上下文同步 |
| SpeakerQueueManager.gd | `script/ai/SpeakerQueueManager.gd` | 发言队列管理 |
| MultiAgentDialogueIntegration.gd | `script/ai/MultiAgentDialogueIntegration.gd` | 统一集成器 |

### 辅助工具

| 文件 | 路径 | 说明 |
|------|------|------|
| MovementExecutor.gd | `script/system/MovementExecutor.gd` | 移动执行器 |
| InformationReceiver.gd | `script/system/InformationReceiver.gd` | 信息接收器 |
| Logger.gd | `script/system/Logger.gd` | 日志系统 |
| DialogBubble.gd | `script/ui/DialogBubble.gd` | 对话框UI |

---

*文档维护者：百舟楫*  
*最后更新：2026-04-15*
