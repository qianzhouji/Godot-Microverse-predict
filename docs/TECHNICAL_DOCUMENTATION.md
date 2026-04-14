# Godot-Microverse-predict 项目技术文档

> **项目**: 抑郁风险学生校园情境模拟系统
> **仓库**: https://github.com/qianzhouji/Godot-Microverse-predict
> **最后更新**: 2026-04-08

---

## 目录

1. [项目概述](#项目概述)
2. [架构概述](#架构概述)
3. [Activity System V2](#activity-system-v2)
4. [中央时序系统](#中央时序系统)
5. [AIAgent认知循环](#aiagent认知循环)
6. [MVT理论实现](#mvt理论实现)
7. [项目进度](#项目进度)
8. [项目配置](#项目配置)
9. [文件索引](#文件索引)
10. [重构历史](#重构历史)

---

## 项目概述

这是一个基于**努力决策理论**和**边际价值定理(MVT)**的AI Agent模拟系统，用于探究**抑郁风险青少年**与**健康青少年**在动态社会情境中的认知机制差异。

### 核心研究问题

**抑郁风险学生是否在努力导向决策中存在系统性偏差？**

- 抑郁风险学生是否对**努力成本**过度敏感？
- 抑郁风险学生是否对**奖赏衰减**感知异常？
- 这些认知偏差如何影响其**情境选择**和**社交行为**？

---

## 架构概述

### 五层系统架构 (V2)

```
┌─────────────────────────────────────────────────────────────┐
│  第一层：中央时序系统                                          │
│  - 全局时钟（5分钟/周期）                                      │
│  - 上升沿触发所有Agent活动                                     │
│  - ActivityCoordinator协调分配                                 │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  第二层：活动管理系统 (V2新增)                                  │
│  - ActivityManager：活动生命周期、奖赏计算                      │
│  - ActivityCoordinator：LLM驱动决策分配                        │
│  - 专注度系统：30%/65%/100%三档                                │
│  - 双向奔赴机制：社交意图匹配                                   │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  第三层：Agent认知系统                                         │
│  - 感知（场景信息获取）                                        │
│  - 体验（主观体验奖赏）                                        │
│  - 自然语言决策（V2）                                          │
│  - 三步活动缓存（V2）                                          │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  第四层：感知与记忆系统                                         │
│  - PerceptionSystem：贝叶斯感知、信念更新                       │
│  - MemoryManager：经历记忆存储与检索                            │
│  - DynamicPersonality：动态特质管理                             │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  第五层：系统层（客观现实）                                     │
│  - RoomArea：定义情境参数(S, a, E)                             │
│  - RewardSystem：计算客观收益 G(t)                             │
│  - TimelineState：课程表与行为约束                              │
└─────────────────────────────────────────────────────────────┘
```

### 核心设计原则 (V2)

| 原则 | 说明 |
|------|------|
| **Click周期机制** | 5分钟游戏时间一个周期，上升沿触发所有Agent同步活动 |
| **自然语言决策** | Agent生成自然语言描述，协调器调用LLM分配活动 |
| **三步缓存** | Agent可缓存最多3步活动序列，支持复杂组合 |
| **活动中决策** | 每次Click自动触发体验(累积) + 决策(继续/停止/更换) |
| **专注度系统** | 30%/65%/100%三档，影响努力成本、奖赏收益、信息接收 |
| **双向奔赴** | 只有双方意图匹配时才协调，否则各自独立行动 |
| **行为/内容分离** | 对话行为全场景可见，对话内容仅范围内可见 |

### 三层认知架构与代码映射

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

---

## Activity System V2

### V2核心改进

| 方面 | V1 | V2 |
|------|-----|-----|
| 决策方式 | 结构化JSON | 自然语言描述 |
| 协调方式 | TimingSystem缓存 | ActivityCoordinator LLM协调 |
| 活动缓存 | 1步 | 3步 |
| 活动中决策 | 不支持 | 支持（每次Click） |
| 奖赏计算 | 离散 | 累积 |
| 专注度 | 无 | 30%/65%/100%三档 |
| 双向奔赴 | 无 | 有 |

### 基础活动类型

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

### 专注度档位

| 档位 | 值 | 努力成本 | 奖赏收益 | 信息接收 |
|------|-----|----------|----------|----------|
| LOW | 30% | ×0.3 | ×0.3 | 30% |
| MEDIUM | 65% | ×0.65 | ×0.65 | 65% |
| HIGH | 100% | ×1.0 | ×1.0 | 100% |

### 双向奔赴机制

**原则**: 只有双方意图匹配时才协调，否则各自独立行动。

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
```

### V2工作流程

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

---

## 中央时序系统

### 时序周期（5分钟游戏时间）

```
Click N (上升沿触发)
    │
    ├── ActivityManager._on_click_triggered()
    │   └── 更新所有活动状态，累积奖赏
    │
    ├── 发射 click_triggered 信号
    │       └── 所有Agent开始决策
    │
    ├── 等待 0.5秒
    │
    ├── ActivityCoordinator.execute_coordination()
    │   └── LLM协调分配活动
    │
    └── 下发活动序列给各Agent

Click N+1 (5分钟后)
    └── 重复上述流程
```

### 每日流程

```
08:00 游戏日开始
    └── 所有Agent统一感知+决策

08:00-17:00 正常运行
    └── 每5分钟一个Click周期

17:00 放学时间
    └── 不接受新的开始请求
    └── 只允许结束当前活动

17:30 强制结束
    └── 所有Agent进入反思阶段
    └── 更新记忆、情感关系
    └── 完成后通知时序系统

次日08:00 新游戏日开始
```

### 课程表

| 时间 | 活动 | 位置 | 类型 |
|------|------|------|------|
| 8:00 | 班主任课 | 教室（主教学区） | class |
| 8:55 | 英语课 | 教室（主教学区） | class |
| 9:50 | 小组讨论 | 教室（小组讨论区） | discussion |
| 10:45 | 午休 | 食堂 | break |
| 11:45 | 数学课 | 教室（主教学区） | class |
| 12:40 | 体育活动 | 体育馆 | activity |

---

## AIAgent认知循环

### V2认知循环

```
Click触发
    │
    ▼
┌─────────────────────────────────────┐
│  检查活动缓存                        │
│  ├─ 有缓存 → 执行下一步              │
│  └─ 无缓存 → 检查当前活动            │
└─────────────────────────────────────┘
    │
    ├── 正在活动中 → _perform_activity_update()
    │       ├── 体验累积奖赏
    │       ├── 感知环境
    │       ├── MVT+LLM决策（继续/停止/更换）
    │       └── 执行决策
    │
    └── 空闲状态 → _perform_v2_cognitive_cycle()
            ├── 感知
            ├── 体验（如果有上一活动）
            ├── 自然语言决策
            └── 提交协调器
```

### Agent状态（9种）

```gdscript
enum AgentState {
    IDLE,               # 空闲
    PERCEIVING,         # 感知中
    EXPERIENCING,       # 体验中
    DECIDING,           # 决策中
    WAITING_FOR_CLICK,  # 等待Click执行
    EXECUTING_ACTION,   # 执行行动中
    IN_DIALOGUE,        # 对话中
    IN_ACTIVITY,        # 活动中
    MOVING              # 移动中
}
```

### 三步缓存机制

```
Agent A想和Agent B对话，但不在同一中范围

决策结果：
├─ Step1: 移动路径（进入B所在中范围）
├─ Step2: 开始对话
└─ Step3: 专注度65%

Click N: 执行Step1（移动）
Click N+1: 执行Step2（开始对话）
Click N+2: 执行Step3（专注度设置）
```

### 中范围划分系统

**划分规则**:
| 房间类型 | 划分方式 | 说明 |
|---------|---------|------|
| 教室/图书馆/自习室/食堂 | 4象限 | 右上1、左上2、左下3、右下4 |
| 大走廊 | 左右2区 | 左区、右区 |
| 小走廊 | 单区域 | 中心区域 |

---

## MVT理论实现

### 核心公式实现

#### 1. 客观收益函数（RewardSystem.gd）
```gdscript
# G(t) = (S/a)[1 - exp(-at)]
func _calculate_objective_gain(S: float, a: float, time: float) -> float:
    var gain = (S / a) * (1.0 - exp(-a * time))
    return clamp(gain, 0.0, 1.0)
```

#### 2. 主观效用函数（UtilitySystem.gd）
```gdscript
# U(G) = G^α - β_effort × E
static func calculate_utility(gain: float, effort: float, 
                              alpha: float, beta_effort: float) -> float:
    var gain_utility = pow(max(gain, 0.0), alpha)
    var effort_cost = beta_effort * effort
    return gain_utility - effort_cost
```

#### 3. 最优停留时间公式（UtilitySystem.gd）
```gdscript
# log(T) = log[ηS·log(S)] − log(ρbase) − βeffort·effort − ηa·log(a) + ε
static func calculate_optimal_time(perceived_S, perceived_a, effort,
                                   alpha, beta_effort, p_base, eta_s, eta_a):
    var term1 = log(eta_s * log(perceived_S))      # log[ηS·log(S)]
    var term2 = -log(p_base)                        # −log(ρbase)
    var term3 = -beta_effort * effort               # −βeffort·effort
    var term4 = -eta_a * log(perceived_a)           # −ηa·log(a)
    var epsilon = randfn(0.0, 0.1)                  # ε (随机噪声)
    var log_T = term1 + term2 + term3 + term4 + epsilon
    return clamp(exp(log_T), 1.0, 60.0)
```

### 认知机制参数

| 参数 | 符号 | 健康Agent | 抑郁Agent | 功能 |
|------|------|----------|----------|------|
| 离开阈值 | ρ_base | 0.5-0.6 | 0.3-0.4 | 对环境平均奖赏率的估计 |
| 初始奖赏感知权重 | η_s | 0.5 | 0.4 | 对初始丰富度的敏感度 |
| 衰减率感知权重 | η_a | 0.5 | 0.7 | 对奖赏衰减的敏感度 |
| 收益敏感性 | α | 0.8 | 0.5-0.6 | 收益的非线性效用 |
| **努力敏感性** | **β_effort** | **0.4** | **0.8** | **核心差异参数** |

---

## 项目进度

### 当前进度概览

```
[完成度: 90%]

中央时序系统         ████████████████████ 100%
Activity System V2   ████████████████████ 100%
AIAgent核心          ████████████████████ 100%
Prompt系统           ████████████████████ 100%
感知体验系统         ████████████████████ 100%
中范围划分系统       ████████████████████ 100%
角色状态系统         ████████████████████ 100%
奖赏系统             ████████████████████ 100%
集成测试             ████████████░░░░░░░░  60%
DialogueManager      ████████████████████ 100%
多Agent对话系统       ████████████████████ 100%
情感关系系统         ░░░░░░░░░░░░░░░░░░░░   0%
```

### 系统实现状态

| 系统 | 状态 | 文件 | 说明 |
|------|------|------|------|
| 中央时序系统 | ✅ 100% | TimingSystem.gd | Click触发与协调 |
| Activity System V2 | ✅ 100% | ActivityManager.gd, ActivityCoordinator.gd, Activity.gd | 活动生命周期、LLM协调、专注度 |
| AIAgent核心 | ✅ 100% | AIAgent.gd | 自然语言决策、三步缓存 |
| Prompt系统 | ✅ 100% | PromptBuilder.gd | V2自然语言决策Prompt |
| 感知体验系统 | ✅ 100% | PerceptionSystem.gd, RewardSystem.gd | 贝叶斯感知、奖赏发放 |
| 中范围划分系统 | ✅ 100% | AIAgent.gd | 4象限/左右/单区 |
| 角色状态系统 | ✅ 100% | CharacterPersonality.gd, DynamicPersonality.gd | 静态人设、动态特质 |
| 奖赏系统 | ✅ 100% | RewardSystem.gd, AgentRewardReceiver.gd | 三层奖赏架构 |
| 移动执行器 | ✅ 100% | MovementExecutor.gd | 导航和直线移动 |
| 信息接收器 | ✅ 100% | InformationReceiver.gd | 专注度过滤 |
| **DialogueManager** | ✅ **100%** | DialogManager.gd, DialogService.gd, DialogueLifecycleManager.gd | 对话生命周期管理 |
| **多Agent对话系统** | ✅ **100%** | GroupDialogueManager.gd, DialogueInterruptionManager.gd, DialogueContextManager.gd, MultiAgentDialogueIntegration.gd | 群组对话、打断/插入、上下文同步 |
| **情感关系系统** | ⏳ **0%** | - | 情感类型、关系网络 |

### 已完成工作 (2026-04-08)

#### Activity System V2 完成
- ✅ 创建 Activity.gd - 活动数据结构，支持专注度
- ✅ 创建 ActivityCoordinator.gd - 中央协调器，LLM驱动决策分配
- ✅ 创建 ActivityManager.gd - 活动生命周期管理，累积奖赏计算
- ✅ 创建 MovementExecutor.gd - 移动执行器
- ✅ 创建 InformationReceiver.gd - 信息接收器，专注度过滤
- ✅ 更新 AIAgent.gd - V2自然语言决策，三步缓存
- ✅ 更新 TimingSystem.gd - 集成ActivityCoordinator
- ✅ 创建集成测试计划和配置指南

#### 核心特性实现
- ✅ 自然语言决策生成
- ✅ LLM协调活动分配
- ✅ 三步活动缓存
- ✅ 专注度系统（30%/65%/100%）
- ✅ 双向奔赴机制
- ✅ 活动中持续决策
- ✅ 累积奖赏计算

### 待完成工作

#### 高优先级

| 优先级 | 任务 | 说明 | 预计时间 |
|--------|------|------|---------|
| P0 | 集成测试 | 执行TC01-TC06，验证V2系统 | 2-3小时 |
| P0 | DialogueManager | 对话生命周期管理 | 3-4小时 |
| P1 | 情感关系系统 | 情感类型定义、关系网络 | 3-4小时 |
| P1 | UI和调试工具 | 时序系统状态面板、Agent监控 | 2-3小时 |

---

## 项目配置

### AutoLoad配置

在Godot编辑器中：**项目 → 项目设置 → AutoLoad**

| 顺序 | 脚本路径 | 单例名 | 说明 |
|------|---------|--------|------|
| 1 | `res://script/RoomManager.gd` | RoomManager | 房间管理 |
| 2 | `res://script/system/RewardSystem.gd` | RewardSystem | 奖赏系统 |
| 3 | `res://script/ai/APIManager.gd` | APIManager | API管理 |
| 4 | `res://script/ai/memory/MemoryManager.gd` | MemoryManager | 记忆系统 |
| 5 | `res://script/CharacterManager.gd` | CharacterManager | 角色管理 |
| 6 | `res://script/system/TimingSystem.gd` | TimingSystem | 时序系统 |
| 7 | `res://script/system/TimelineState.gd` | TimelineState | 时间轴状态 |
| 8 | `res://script/system/ActivityManager.gd` | ActivityManager | 活动管理（V2） |
| 9 | `res://script/system/ActivityCoordinator.gd` | ActivityCoordinator | 活动协调（V2） |
| 10 | `res://script/ai/DialogManager.gd` | DialogManager | 对话管理 |
| 11 | `res://script/ai/memory/MemorySystem.gd` | MemorySystem | 记忆系统（V2） |

### 场景节点配置（School.tscn）

需要在场景中添加以下节点：

```
School (根节点)
├── RoomManager
├── RewardSystem
├── TimingSystem
├── TimelineState
├── ActivityManager (V2新增)
├── ActivityCoordinator (V2新增)
├── MultiAgentDialogueIntegration (2026-04-14新增)
│   ├── GroupDialogueManager
│   ├── DialogueInterruptionManager
│   └── DialogueContextManager
├── StudentXiaoming
│   └── AIAgent
├── StudentXiaohong
│   └── AIAgent
└── TeacherWang
    └── AIAgent
```

### 本地LLM配置

- **API端点**: `http://localhost:11434/api/generate`
- **默认模型**: `qwen2.5:7b` (协调器) / `qwen2.5:14b` (决策)
- **温度**: 0.3 (协调器) / 0.7 (决策)
- **最大token**: 2000 (协调器) / 500 (决策)

---

## 文件索引

### Activity System V2 文件

| 文件 | 路径 | 说明 |
|------|------|------|
| Activity.gd | `script/system/Activity.gd` | 活动数据结构 |
| ActivityCoordinator.gd | `script/system/ActivityCoordinator.gd` | 中央协调器 |
| ActivityManager.gd | `script/system/ActivityManager.gd` | 活动管理器 |
| MovementExecutor.gd | `script/system/MovementExecutor.gd` | 移动执行器 |
| InformationReceiver.gd | `script/system/InformationReceiver.gd` | 信息接收器 |
| natural_decision_template.md | `prompts/natural_decision_template.md` | V2决策Prompt |
| coordinator_prompt.md | `docs/prompts/coordinator_prompt.md` | 协调器Prompt |

### 核心系统文件

| 文件 | 路径 | 说明 |
|------|------|------|
| TimingSystem.gd | `script/system/TimingSystem.gd` | 全局时钟 + Click触发 |
| TimelineState.gd | `script/system/TimelineState.gd` | 课程表 + 行为约束 |
| RewardSystem.gd | `script/system/RewardSystem.gd` | 奖赏系统 |

### AI核心

| 文件 | 路径 | 说明 |
|------|------|------|
| AIAgent.gd | `script/ai/AIAgent.gd` | Agent认知循环（V2） |
| PromptBuilder.gd | `script/ai/PromptBuilder.gd` | Prompt构建器 |
| PerceptionSystem.gd | `script/ai/PerceptionSystem.gd` | 贝叶斯感知系统 |
| AgentRewardReceiver.gd | `script/ai/AgentRewardReceiver.gd` | 奖赏接收器 |
| MemoryManager.gd | `script/ai/memory/MemoryManager.gd` | 记忆管理 |
| DailyReflectionSystem.gd | `script/ai/DailyReflectionSystem.gd` | 每日反思 |
| DynamicPersonality.gd | `script/ai/DynamicPersonality.gd` | 动态人格 |
| UtilitySystem.gd | `script/ai/UtilitySystem.gd` | MVT效用计算 |
| GroupDialogueManager.gd | `script/ai/GroupDialogueManager.gd` | 群组对话管理（3-5人） |
| DialogueInterruptionManager.gd | `script/ai/DialogueInterruptionManager.gd` | 对话打断/插入机制 |
| DialogueContextManager.gd | `script/ai/DialogueContextManager.gd` | 对话上下文同步 |
| MultiAgentDialogueIntegration.gd | `script/ai/MultiAgentDialogueIntegration.gd` | 多Agent对话统一集成 |
| SpeakerQueueManager.gd | `script/ai/SpeakerQueueManager.gd` | 智能发言队列管理器（优先级系统） |

### 文档

| 文件 | 路径 | 说明 |
|------|------|------|
| Activity_System.md | `docs/Activity_System.md` | Activity System V2 技术文档 |
| Agent_Cognitive_System.md | `docs/Agent_Cognitive_System.md` | Agent认知系统详细文档 |
| Character_State_System.md | `docs/Character_State_System.md` | 角色状态系统文档 |
| Reward_System.md | `docs/Reward_System.md` | 奖赏系统详细文档 |
| Prompt_System.md | `docs/Prompt_System.md` | Prompt系统详细文档 |
| Timing_System.md | `docs/Timing_System.md` | 时序系统技术文档 |
| Integration_Test_Plan.md | `docs/Integration_Test_Plan.md` | 集成测试计划 |
| Integration_Test_Setup.md | `docs/Integration_Test_Setup.md` | 集成测试配置指南 |
| MultiAgent_Dialogue_System.md | `docs/MultiAgent_Dialogue_System.md` | 多Agent对话系统文档 |
| Speaker_Queue_System.md | `docs/Speaker_Queue_System.md` | 发言队列管理系统设计文档 |

---

## 重构历史

### 2026-04-14 - 多Agent对话系统实现

#### 核心实现
- ✅ 创建 GroupDialogueManager.gd - 群组对话管理（3-5人）
  - 支持动态加入/退出
  - 发言队列管理（避免多人同时说话）
  - 自动群组形成检测
- ✅ 创建 DialogueInterruptionManager.gd - 对话打断/插入机制
  - 四种打断类型：礼貌/紧急/随意/旁听
  - 基于关系和紧急度的智能决策
  - 投票机制决定是否允许打断
- ✅ 创建 DialogueContextManager.gd - 对话上下文同步管理
  - 确保多方对话内容一致性
  - 自动情感分析
  - 对话摘要和关键信息提取
- ✅ 创建 MultiAgentDialogueIntegration.gd - 统一集成器
  - 提供简洁的统一接口
  - 自动判断对话类型
  - 智能对话机会推荐

#### 关键特性
- 支持1对1对话和群组对话（3-5人）
- 第三方Agent可礼貌/紧急/随意插入正在进行的对话
- 对话上下文自动同步到所有参与者
- 当3人以上聚集时自动形成群组对话
- 与MemorySystem、PerceptionSystem深度集成

### 2026-04-13 - 对话系统基础生命周期实现

#### 核心实现
- ✅ 创建 DialogService.gd - 对话服务，管理多并行对话
- ✅ 创建 DialogueLifecycleManager.gd - 完整生命周期管理
- ✅ 实现对话状态机（INITIATING → ACTIVE → PAUSED/ENDING → ENDED）
- ✅ 实现对话超时检测（5分钟无交互）
- ✅ 实现范围检测（一方离开150px范围暂停对话）
- ✅ 实现对话总结自动记录到记忆系统
- ✅ 修复 ConversationManager 和 DailyReflectionSystem 的 MemoryManager 调用
- ✅ AIAgent 集成对话状态检查和感知

#### 关键特性
- 最大消息数限制（10条）自动结束对话
- 情感分析（简化版）记录对话氛围
- 对话被打断/离开范围自动处理
- 对话数据持久化到记忆系统

### 2026-04-08 - Activity System V2 完成

#### 核心实现
- ✅ 创建 Activity System V2 完整架构
- ✅ 实现自然语言决策 + LLM协调分配
- ✅ 实现三步活动缓存机制
- ✅ 实现专注度系统（30%/65%/100%）
- ✅ 实现双向奔赴机制
- ✅ 实现活动中持续决策
- ✅ 修复AIAgent和ActivityCoordinator编译错误

#### 关键修复
- ✅ 添加V1兼容变量 `cached_request` 和 `is_waiting_execution`
- ✅ 添加 `MOVING` 状态到 `AgentState` 枚举
- ✅ 修复AIAgent类名冲突（注释备份文件的class_name）
- ✅ 使用preload避免ActivityCoordinator循环依赖
- ✅ 统一 `_perform_v2_cognitive_cycle` 函数名

### 2026-04-07 - MVT公式修正

- ✅ 修正 UtilitySystem.gd - 使用理论解析公式
- ✅ 修正 AIAgent.gd - 完整MVT离开决策检查
- ✅ 修正 PerceptionSystem.gd - 非线性最小二乘拟合
- ✅ 更新项目文档

### 2026-04-06 - 感知层与系统层分离

- ✅ 创建 RewardSystem.gd
- ✅ 创建 AgentRewardReceiver.gd
- ✅ 修改 AIAgent.gd
- ✅ 修改 RoomManager.gd
- ✅ 配置 AutoLoad

---

## 附录：集成测试用例

### TC01: 基本流程测试
验证完整V2流程跑通：Agent生成自然语言决策 → 协调器调用LLM → Agent执行活动

### TC02: 双向奔赴测试
验证双向奔赴机制：双方意图匹配时分配到相同目标位置

### TC03: 单向意图测试
验证非双向奔赴时各自独立执行

### TC04: 专注度系统测试
验证专注度影响奖赏计算和信息接收

### TC05: 三步缓存测试
验证三步活动缓存正确执行

### TC06: 活动中决策测试
验证活动中可决策继续/停止/更换

---

*本文档维护者：百舟楫*
*最后更新：2026-04-13*
