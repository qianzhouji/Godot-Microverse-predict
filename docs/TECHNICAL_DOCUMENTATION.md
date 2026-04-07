# Godot-Microverse-predict 项目技术文档

> **项目**: 抑郁风险学生校园情境模拟系统
> **仓库**: https://github.com/qianzhouji/Godot-Microverse-predict
> **最后更新**: 2026-04-07

---

## 目录

1. [项目概述](#项目概述)
2. [架构概述](#架构概述)
3. [中央时序系统](#中央时序系统)
4. [AIAgent认知循环](#aiagent认知循环)
5. [MVT理论实现](#mvt理论实现)
6. [项目进度](#项目进度)
7. [项目配置](#项目配置)
8. [文件索引](#文件索引)
9. [重构历史](#重构历史)

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

### 四层系统架构

```
┌─────────────────────────────────────────────────────────────┐
│  第一层：中央时序系统                                          │
│  - 全局时钟（5分钟/周期）                                      │
│  - 上升沿触发所有Agent活动                                     │
│  - 请求缓存与批准执行                                          │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  第二层：全局状态系统                                          │
│  - 时间轴状态（课程表：上课/午休/放学）                         │
│  - 场景状态（各子场景的当前活动）                               │
│  - 活动管理系统（奖赏计算与发放）                               │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  第三层：Agent认知系统                                         │
│  - 感知（场景信息获取）                                        │
│  - 体验（主观体验奖赏）                                        │
│  - 决策（行动请求生成）                                        │
│  - 行动请求缓存（最多2步）                                     │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  第四层：对话管理系统                                          │
│  - 中范围对话（小组讨论）                                      │
│  - 大范围对话（教师提问）                                      │
│  - 发言优先级队列                                              │
│  - 对话生命周期管理                                            │
└─────────────────────────────────────────────────────────────┘
```

### 核心设计原则

| 原则 | 说明 |
|------|------|
| **Click周期机制** | 5分钟游戏时间一个周期，上升沿触发所有Agent同步活动 |
| **感知-体验-决策循环** | 每个Click自动执行：感知→体验→决策→缓存请求 |
| **两步缓存** | Agent可缓存最多2步行动请求，Step1执行后验证Step2有效性 |
| **对话独立时序** | 对话发言不等待Click，按优先级队列即时处理 |
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

## 中央时序系统

### 时序周期（5分钟游戏时间）

```
Click N (上升沿触发)
    │
    ├── 批准Click N-1缓存的所有请求
    │   ├── Agent A: 开始移动
    │   ├── Agent B: 结束对话
    │   └── Agent C: 开始对话
    │
    ├── 执行所有批准的行动
    │   └── （移动、开始/结束对话等）
    │
    ├── 行动完成后 → 触发体验+感知
    │   ├── 体验：基于场景参数计算客观奖赏
    │   └── 感知：获取当前场景信息
    │
    ├── 感知完成后 → 自动触发决策
    │   └── 生成行动请求 → 缓存到下一次Click
    │
    └── 等待下一次Click...

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

### 核心代码

**TimingSystem.gd**:
```gdscript
extends Node
class_name TimingSystem

static var instance: TimingSystem
const CLICK_INTERVAL_MINUTES: float = 5.0

signal click_triggered(game_time: float, day: int, click_num: int)

func _trigger_click():
    click_count += 1
    # 1. 批准并执行所有待处理请求
    _execute_pending_requests()
    # 2. 触发所有Agent的感知+体验+决策
    click_triggered.emit(current_game_time, current_day, click_count)
```

**ActionRequest.gd**:
```gdscript
class_name ActionRequest

enum ActionType {
    MOVE_TO_RANGE,      # 移动到指定中范围
    START_DIALOGUE,     # 开始对话
    JOIN_DIALOGUE,      # 加入对话
    EXIT_DIALOGUE,      # 退出对话
    START_SPORTS,       # 开始体育活动
    END_SPORTS,         # 结束体育活动
    START_STUDY,        # 开始自习
    END_STUDY,          # 结束自习
    WAIT                # 等待
}

var action_type: ActionType
var cached_step2: ActionRequest  # 第二步缓存
```

---

## AIAgent认知循环

### 认知循环：感知 → 体验 → 决策

```
Click触发
    │
    ▼
┌─────────────┐
│   感知阶段   │  ← 获取当前场景信息
│  (自动执行)  │
└─────────────┘
    │
    ├── 当前子场景
    ├── 子场景内其他Agent
    ├── 可见的对话行为
    ├── 可听到的对话内容
    └── 时间轴状态（上课/休息）
    │
    ▼
┌─────────────┐
│   体验阶段   │  ← 主观体验系统层奖赏
│  (自动执行)  │
└─────────────┘
    │
    ├── 接收系统层奖赏（客观值）
    ├── 贝叶斯更新主观感知
    └── 更新认知参数（p_base, η_s, η_a, β_effort）
    │
    ▼
┌─────────────┐
│   决策阶段   │  ← 生成行动请求
│  (自动执行)  │
└─────────────┘
    │
    ├── 结合感知信息
    ├── 结合认知参数
    ├── 结合时间轴约束
    └── 生成行动请求（最多缓存2步）
    │
    ▼
等待下一次Click执行
```

### Agent状态（8种）

```gdscript
enum AgentState {
    IDLE,               # 空闲
    PERCEIVING,         # 感知中
    EXPERIENCING,       # 体验中
    DECIDING,           # 决策中
    WAITING_FOR_CLICK,  # 等待Click执行
    EXECUTING_ACTION,   # 执行行动中
    IN_DIALOGUE,        # 对话中
    IN_ACTIVITY         # 活动中
}
```

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

### 中范围划分系统

**划分规则**:
| 房间类型 | 划分方式 | 说明 |
|---------|---------|------|
| 教室/图书馆/自习室/食堂 | 4象限 | 右上1、左上2、左下3、右下4 |
| 大走廊 | 左右2区 | 左区、右区 |
| 小走廊 | 单区域 | 中心区域 |

**象限定义**:
```
y↑
 │  第2象限  │  第1象限
 │   (左上)  │  (右上)
─┼───────────┼──────────→x
 │  第3象限  │  第4象限
 │   (左下)  │  (右下)
```

### 移动系统

**定位函数** (`_calculate_move_target`):
- 悄悄话模式 → 贴身位置（±15px）
- 同一中范围 → 目标身边小范围（±30px）
- 不同中范围 → 目标中范围中心（±20%）

**移动输出格式**:
```
"1 目标名称"
```
- `1` - 移动行动编号
- `目标名称` - 场景精确名称或人物精确全名

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

#### 4. 信念更新（PerceptionSystem.gd）
```gdscript
# 使用非线性最小二乘拟合 G(t) = (S/a)[1 - exp(-at)]
# 网格搜索最优 S 和 a，然后贝叶斯更新
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
[完成度: 75%]

中央时序系统     ████████████████████ 100%
AIAgent核心      ███████████████████░  95%
Prompt系统       ████████████████████ 100%
感知体验系统     ████████████████████ 100%
中范围划分系统   ████████████████████ 100%
ActivityManager  ░░░░░░░░░░░░░░░░░░░░   0%
DialogueManager  ░░░░░░░░░░░░░░░░░░░░   0%
情感关系系统     ░░░░░░░░░░░░░░░░░░░░   0%
测试调试         ░░░░░░░░░░░░░░░░░░░░   0%
```

### 已完成工作

#### 第一阶段：中央时序系统（100%完成）

| 组件 | 文件 | 状态 |
|------|------|------|
| 时序系统核心 | `script/system/TimingSystem.gd` | ✅ 完成 |
| 时间轴状态 | `script/system/TimelineState.gd` | ✅ 完成 |
| 行动请求 | `script/data/ActionRequest.gd` | ✅ 完成 |
| 场景集成 | `scene/maps/School.tscn` | ✅ 已添加节点 |

#### 第二阶段：AIAgent核心重构（95%完成）

| 组件 | 文件 | 状态 |
|------|------|------|
| AIAgent核心 | `script/ai/AIAgent.gd` | ✅ 完成框架 |
| Prompt构建器 | `script/ai/PromptBuilder.gd` | ✅ 完成 |
| Prompt模板 | `prompts/*.txt` | ✅ 完成 |
| 原AIAgent备份 | `script/ai/AIAgent_backup_20250406.gd` | ✅ 已备份 |

**已完成**:
- 清理旧代码（定时器、旧任务系统、旧对话系统）
- 新增认知循环（感知→体验→决策→执行）
- 8个行动执行方法框架
- 本地LLM API调用（Ollama）
- 两步缓存验证机制
- 中范围划分系统
- MVT理论公式完整实现

#### 第三阶段：Prompt系统（100%完成）

| 组件 | 文件 | 状态 |
|------|------|------|
| 决策Prompt模板 | `prompts/decision_prompt_template.txt` | ✅ 完成 |
| 对话回复模板 | `prompts/dialogue_reply_template.txt` | ✅ 完成 |
| Prompt构建器 | `script/ai/PromptBuilder.gd` | ✅ 完成 |

#### 第四阶段：感知层分离（100%完成）

| 系统 | 文件 | 说明 |
|------|------|------|
| 奖赏系统 | `RewardSystem.gd` | 系统层奖赏发放 |
| 奖赏接收 | `AgentRewardReceiver.gd` | 感知层接收 |
| 感知系统 | `PerceptionSystem.gd` | 贝叶斯感知 |

### 待完成工作

#### 高优先级（下一步）

| 优先级 | 任务 | 说明 | 预计时间 |
|--------|------|------|---------|
| P0 | ActivityManager | 活动管理与奖赏计算闭环 | 2-3小时 |
| P0 | DialogueManager | 对话生命周期管理 | 3-4小时 |
| P0 | 集成测试 | 测试Agent认知循环和移动功能 | 2-3小时 |

#### 中优先级

| 优先级 | 任务 | 说明 | 预计时间 |
|--------|------|------|---------|
| P1 | 情感关系系统 | 情感类型定义、每日反思集成 | 3-4小时 |
| P1 | 对话系统完善 | 行为与内容分离、发言优先级队列 | 4-5小时 |
| P1 | UI和调试工具 | 时序系统状态面板、Agent实时监控 | 2-3小时 |

#### 低优先级

| 优先级 | 任务 | 说明 | 预计时间 |
|--------|------|------|---------|
| P2 | 性能优化 | API调用批处理、决策缓存机制 | 2-3小时 |
| P2 | 文档完善 | API文档、使用手册、架构图更新 | 1-2小时 |

### 下一步计划

**建议执行顺序**:

1. **选项A：实现ActivityManager**（2-3小时）
   - 创建活动管理系统，计算和发放奖赏
   - 收益：完成体验闭环

2. **选项B：实现DialogueManager**（3-4小时）
   - 创建对话管理系统，支持对话生命周期
   - 收益：可以测试对话功能

3. **选项C：集成测试**（2-3小时）
   - 启动时序系统，验证Click触发
   - 测试Agent认知循环、移动功能、对话功能

---

## 项目配置

### AutoLoad配置

在Godot编辑器中：**项目 → 项目设置 → AutoLoad**

| 顺序 | 脚本路径 | 单例名 |
|------|---------|--------|
| 1 | `res://script/RoomManager.gd` | RoomManager |
| 2 | `res://script/system/RewardSystem.gd` | RewardSystem |
| 3 | `res://script/ai/APIManager.gd` | APIManager |
| 4 | `res://script/ai/memory/MemoryManager.gd` | MemoryManager |
| 5 | `res://script/CharacterManager.gd` | CharacterManager |

**project.godot**:
```ini
[autoload]
RoomManager="*res://script/RoomManager.gd"
RewardSystem="*res://script/system/RewardSystem.gd"
APIManager="*res://script/ai/APIManager.gd"
MemoryManager="*res://script/ai/memory/MemoryManager.gd"
CharacterManager="*res://script/CharacterManager.gd"
```

### 本地LLM配置

- **API端点**: `http://localhost:11434/api/generate`
- **默认模型**: `qwen2.5:14b`
- **温度**: 0.7
- **最大token**: 500

---

## 文件索引

### 核心系统文件

| 文件 | 路径 | 说明 |
|------|------|------|
| TimingSystem.gd | `script/system/TimingSystem.gd` | 全局时钟 + Click触发 |
| TimelineState.gd | `script/system/TimelineState.gd` | 课程表 + 行为约束 |
| ActionRequest.gd | `script/data/ActionRequest.gd` | 行动请求数据结构 |
| RewardSystem.gd | `script/system/RewardSystem.gd` | 奖赏系统 |

### AI核心

| 文件 | 路径 | 说明 |
|------|------|------|
| AIAgent.gd | `script/ai/AIAgent.gd` | Agent认知循环 |
| AIAgent_backup_20250406.gd | `script/ai/AIAgent_backup_20250406.gd` | 原AIAgent备份 |
| PromptBuilder.gd | `script/ai/PromptBuilder.gd` | Prompt构建器 |
| PerceptionSystem.gd | `script/ai/PerceptionSystem.gd` | 贝叶斯感知系统 |
| AgentRewardReceiver.gd | `script/ai/AgentRewardReceiver.gd` | 奖赏接收器 |
| MemoryManager.gd | `script/ai/memory/MemoryManager.gd` | 记忆管理 |
| DailyReflectionSystem.gd | `script/ai/DailyReflectionSystem.gd` | 每日反思 |
| DynamicPersonality.gd | `script/ai/DynamicPersonality.gd` | 动态人格 |
| UtilitySystem.gd | `script/ai/UtilitySystem.gd` | MVT效用计算 |

### 场景文件

| 文件 | 路径 | 说明 |
|------|------|------|
| School.tscn | `scene/maps/School.tscn` | 学校主场景 |
| StudentXiaoming.tscn | `scene/characters/StudentXiaoming.tscn` | 学生小明 |
| TeacherWang.tscn | `scene/characters/TeacherWang.tscn` | 王老师 |

### Prompt模板

| 文件 | 路径 | 说明 |
|------|------|------|
| decision_prompt_template.txt | `prompts/decision_prompt_template.txt` | 决策Prompt模板 |
| dialogue_reply_template.txt | `prompts/dialogue_reply_template.txt` | 对话回复模板 |

---

## 重构历史

### 架构变革

| 方面 | 原架构 | 新架构 |
|------|--------|--------|
| 时序管理 | 各Agent独立定时器 | 中央时序系统（5分钟Click周期） |
| 对话系统 | 1对1直接对话 | 广播式对话（行为/内容分离） |
| 空间感知 | 距离阈值判断 | 中范围划分（4象限/左右/单区） |
| 任务生成 | 随机生成 | 课程表驱动 |
| Prompt管理 | 硬编码在代码中 | 配置文件+模板分离 |

### 2026-04-07 MVT公式修正

- ✅ **修正 UtilitySystem.gd**
  - 重写 `calculate_optimal_time()` 使用理论解析公式
  - 更新 `get_agent_utility_params()` 返回全部四个MVT核心参数
  - 更新 `get_utility_params_description()` 添加MVT参数描述
- ✅ **修正 AIAgent.gd**
  - 实现 `_check_mvt_leave_decision()` 完整MVT离开决策检查
- ✅ **修正 PerceptionSystem.gd**
  - 重写 `_update_beliefs()` 使用非线性最小二乘拟合理论收益函数
- ✅ **更新项目文档**
  - 更新 README.md、PROJECT_STRUCTURE.md、IMPLEMENTATION_LOGIC.md

### 2026-04-06 重大更新日

#### 上午：感知层与系统层分离完成
- ✅ 创建 RewardSystem.gd（系统层奖赏发放）
- ✅ 创建 AgentRewardReceiver.gd（感知层接收器）
- ✅ 修改 AIAgent.gd（移除直接RoomArea访问）
- ✅ 修改 RoomManager.gd（添加内部接口）
- ✅ 修改 RoomArea.gd（移除直接暴露参数的接口）
- ✅ 配置 AutoLoad（RewardSystem设置为单例）

#### 下午：动态人设系统扩展
- ✅ 扩展 DynamicPersonality.gd（任务反馈、社交反馈、教师评价）
- ✅ 新增边界保护机制（偏离基线≤20%）

#### 傍晚：每日反思系统实现
- ✅ 创建 DailyReflectionSystem.gd
- ✅ LLM-based反思分析
- ✅ 四项认知参数动态调整
- ✅ 完整PHQ-9九项评估

### 完全保留的系统

- **PerceptionSystem** - 贝叶斯感知
- **AgentRewardReceiver** - 奖赏接收
- **MemoryManager** - 记忆管理
- **DailyReflectionSystem** - 每日反思
- **DynamicPersonality** - 动态人格

### 完全舍弃的系统

- **ConversationManager** - 旧1对1对话
- **DialogManager** - 旧对话管理
- **DialogService** - 旧对话服务
- **TaskManager** - 旧任务系统

---

*本文档合并了以下历史文档*:
- PROJECT_STATUS.md
- Progress_Report.md
- Refactoring_Summary.md
- Phase1_TimingSystem_Implementation.md
- Phase2_AIAgent_Refactor_Plan.md
- AUTOLOAD_SETUP.md
- File_Location_Index.md
- AIAgent_Refactor_Analysis.md

*维护者：百舟楫*
