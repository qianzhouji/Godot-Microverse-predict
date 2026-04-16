# 角色状态系统详细文档

> **系统名称**: CharacterPersonality + DynamicPersonality + MemorySystem + AIAgent
> **版本**: 2.0
> **最后更新**: 2026-04-16

---

## 目录

1. [系统概述](#系统概述)
2. [静态人设状态](#静态人设状态)
3. [动态特质状态](#动态特质状态)
4. [自然语言记忆系统](#自然语言记忆系统)
5. [运行时状态](#运行时状态)
6. [感知信念状态](#感知信念状态)
7. [状态交互关系](#状态交互关系)
8. [使用示例](#使用示例)

---

## 系统概述

### 设计目标

角色状态系统是 Godot-Microverse-predict 项目的核心数据层，负责：
- 定义角色的静态人设（性格、能力、背景）
- 追踪角色的动态心理变化（MVT参数）
- 存储角色的经历和**自然语言情感体验**
- 管理角色的实时活动状态

### 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│  数据层（Data Layer）                                         │
│  ├─ CharacterPersonality     - 静态人设配置                  │
│  ├─ DynamicPersonality       - 动态特质管理                  │
│  ├─ MemorySystem             - 自然语言记忆与情感体验        │
│  └─ PerceptionSystem         - 感知信念状态                  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  运行时层（Runtime Layer）                                    │
│  ├─ AIAgent                  - 实时活动状态与情感评估        │
│  ├─ AgentRewardReceiver      - 奖赏历史                      │
│  └─ CharacterBody2D          - 物理位置和动画                │
└─────────────────────────────────────────────────────────────┘
```

### 状态分类

| 层级 | 状态类型 | 存储位置 | 更新频率 |
|------|---------|---------|---------|
| 静态层 | 人设配置 | CharacterPersonality.PERSONALITY_CONFIG | 永不更新 |
| 动态层 | 心理特质 | character_data.dynamic_traits | 事件触发 / 每日反思 |
| 记忆层 | 自然语言体验 | MemorySystem._natural_memories | 每次活动体验 |
| 感知层 | 信念状态 | PerceptionSystem.agent_beliefs | 体验采样 |
| 运行时 | 活动状态 | AIAgent成员变量 | 实时更新 |

---

## 静态人设状态

### 类定义

```gdscript
class_name CharacterPersonality
extends Node
```

### 配置结构

所有角色人设存储在 `PERSONALITY_CONFIG` 字典中，以角色名称为键。

### 1. 基础信息（所有角色）

| 字段 | 类型 | 说明 | 示例 |
|------|------|------|------|
| `position` | String | 职位 | "学生"、"班主任" |
| `personality` | String | 性格描述 | "内向、敏感、缺乏自信" |
| `speaking_style` | String | 说话风格 | "说话轻声，经常自我否定" |
| `work_duties` | String | 工作职责 | "完成学业任务、参与班级活动" |
| `work_habits` | String | 工作习惯 | "经常独自坐在角落" |
| `role_type` | String | 角色类型 | "teacher"、"depression_risk_student" |

### 2. 人口学信息（学生角色）

```gdscript
"demographics": {
    "age": 15,                           # 年龄
    "gender": "男",                      # 性别
    "grade": "初三",                     # 年级
    "family_structure": "单亲家庭",       # 家庭结构
    "socioeconomic_status": "中等偏下",   # 社会经济地位
    "only_child": false                  # 是否独生子女
}
```

### 3. 大五人格（OCEAN模型）

```gdscript
"big_five": {
    "openness": 0.4,           # 开放性
    "conscientiousness": 0.6,  # 尽责性
    "extraversion": 0.3,       # 外向性（抑郁Agent较低）
    "agreeableness": 0.5,      # 宜人性
    "neuroticism": 0.7         # 神经质（抑郁Agent较高）
}
```

### 4. MVT认知机制参数（核心差异）

```gdscript
"cognitive_mechanism": {
    "p_base": 0.4,           # 离开阈值（抑郁Agent较低）
    "eta_s": 0.6,            # 初始奖赏感知权重
    "eta_a": 0.7,            # 衰减率感知权重（抑郁Agent较高）
    "beta_effort": 0.8,      # 努力敏感性（抑郁Agent核心差异）
    "alpha": 0.55            # 收益敏感性（抑郁Agent较低）
}
```

**健康 vs 抑郁Agent 参数对比：**

| 参数 | 健康Agent | 抑郁Agent | 功能 |
|------|----------|----------|------|
| p_base | 0.5-0.6 | 0.3-0.4 | 离开阈值 |
| eta_s | 0.5 | 0.4 | 初始奖赏感知权重 |
| eta_a | 0.5 | 0.7 | 衰减率感知权重 |
| beta_effort | 0.4 | **0.8** | **努力敏感性（核心差异）** |
| alpha | 0.8 | 0.5-0.6 | 收益敏感性 |

---

## 动态特质状态

### 类定义

```gdscript
class_name DynamicPersonality
extends Node
```

### 设计变更（v2.0）

**旧设计（已移除）：**
- 事件直接触发数值更新（如 beta_effort += 0.05）
- 系统预定义更新规则

**新设计：**
- 事件触发 → **每日反思时LLM统一评估**
- Agent自主判断认知参数调整
- 自然语言记录调整原因

### 动态特质列表

| 特质 | 字段 | 范围 | 基线来源 | 更新方式 |
|------|------|------|---------|---------|
| 当日抑郁水平 | `daily_depression_level` | 0-1 | 0.5 | **每日反思LLM评估** |
| 离开阈值 | `p_base` | 0-1 | cognitive_mechanism.p_base | **每日反思LLM评估** |
| 初始奖赏感知权重 | `eta_s` | 0-1 | cognitive_mechanism.eta_s | **每日反思LLM评估** |
| 衰减率感知权重 | `eta_a` | 0-1 | cognitive_mechanism.eta_a | **每日反思LLM评估** |
| 努力敏感性 | `beta_effort` | 0-1 | cognitive_mechanism.beta_effort | **每日反思LLM评估** |

### 边界保护机制

动态特质不能偏离基线超过20%：
```gdscript
new_value = clamp(new_value, baseline - 0.2, baseline + 0.2)
```

### 每日反思流程（v2.0）

```
收集当日所有自然语言记忆
    ↓
LLM分析情绪主题和关键事件
    ↓
LLM判断四项认知参数调整方向和严重程度(1-5)
    ↓
动态幅度计算：基础幅度(1%-12%) × 个体差异乘数
    ↓
PHQ-9九项完整评估
    ↓
更新抑郁水平和认知参数
    ↓
自然语言记录反思结果
```

### API接口

```gdscript
# 获取动态特质
var traits = DynamicPersonality.get_dynamic_traits(character)

# 获取PHQ-9等级描述
var desc = DynamicPersonality.get_phq9_level_description(0.45)
# 返回: "中度抑郁 (PHQ-9: 10-14)"

# 获取特质用于Prompt
var prompt_text = DynamicPersonality.get_traits_for_prompt(character)
```

---

## 自然语言记忆系统

### 类定义

```gdscript
# MemorySystem.gd
extends Node
```

### 设计变更（v2.0重大重构）

**旧设计（已移除）：**
```
SocialMemory - 数值关系分数(-1.0~1.0)
EmotionMemory - 6维度情感值(0-1)
系统自动更新数值
```

**新设计：**
```
NaturalMemory - 自然语言情感描述
Agent自主LLM评估
活动体验阶段触发
```

### 记忆类型

| 类型 | 说明 | 触发时机 |
|------|------|---------|
| `EVENT` | 结构化事件（移动、对话、上课） | 活动执行时 |
| `NATURAL_EMOTION` | 自然语言情感体验 | **活动体验阶段** |

### 自然语言记忆结构

```gdscript
{
    "type": "NATURAL_EMOTION",
    "content": "今天和小红讨论数学作业，她主动分享笔记，感觉她人还不错，愿意继续合作。",
    "context": "小组讨论",
    "timestamp": "第1天 10:45",
    "real_timestamp": 1712485800
}
```

### 情感评估流程

```
活动执行完成
    ↓
体验阶段 (_experience_current_activity)
    ↓
构建Prompt（完整上下文）
    - 活动信息（类型、参与者、地点、时长、专注度）
    - 当前心情、收益感知
    - 对相关参与者的先前记忆
    ↓
LLM情感评估 (_call_llm_for_emotion)
    ↓
自然语言输出（1-2句话，Agent自由发挥）
    ↓
存储到 MemorySystem.add_natural_memory()
    ↓
用于后续决策的上下文检索
```

### Prompt示例

```
你是StudentXiaoming，刚刚完成了以下活动。

【活动信息】
- 活动类型：小组讨论
- 参与者：小红
- 地点：教室（小组讨论区）
- 持续时间：15.0分钟
- 专注度：80%

【你的状态】
- 当前心情：有点累
- 活动收益感知：0.72

【相关记忆】
- 之前对小红的印象：不太熟悉

请用简洁的自然语言（1-2句话）记录这次活动带给你的感受，
以及对参与者的评价。可以自由发挥，像写日记一样。
```

### API接口

```gdscript
# 添加自然语言记忆（情感体验）
MemorySystem.instance.add_natural_memory(
    agent_id,                                    # Agent名称
    "今天和小红讨论数学，她人还不错...",         # 自然语言内容
    "小组讨论",                                  # 上下文
    game_time                                    # 游戏时间
)

# 获取关于某人的记忆（用于情感评估Prompt）
var memories = MemorySystem.instance.get_memories_about(
    "StudentXiaoming",   # Agent名称
    "小红",              # 目标名称
    3                    # 最多返回3条
)
# 返回: ["上次和小红...", "之前对小红..."]

# 记录结构化事件
MemorySystem.instance.record_event(
    agent_id,
    "DIALOGUE",
    game_time,
    "教室",
    {"topic": "数学作业"},
    3
)
```

### 与旧系统的对比

| 特性 | 旧系统 (Social/EmotionMemory) | 新系统 (NaturalMemory) |
|------|------------------------------|------------------------|
| 数据形式 | 数值参数 | 自然语言文本 |
| 评估主体 | 系统自动计算 | Agent自主LLM评估 |
| 更新时机 | 每次互动自动更新 | 活动体验阶段统一评估 |
| 可解释性 | 低（只有数字） | 高（有原因和情境） |
| 灵活性 | 固定维度（好感/信任等） | 自由发挥 |

---

## 运行时状态

### 类定义

```gdscript
class_name AIAgent
extends Node
```

### AgentState 枚举（8种状态）

```gdscript
enum AgentState {
    IDLE,                # 空闲 - 无活动
    PERCEIVING,          # 感知中 - 收集场景信息
    EXPERIENCING,        # 体验中 - 处理奖赏反馈 + **情感评估**
    DECIDING,            # 决策中 - 调用LLM决策
    WAITING_FOR_CLICK,   # 等待Click执行 - 请求已缓存
    EXECUTING_ACTION,    # 执行行动中 - 移动、对话等
    IN_DIALOGUE,         # 在对话中 - 参与对话
    IN_ACTIVITY          # 在活动中 - 体育/自习
}
```

### 核心成员变量

| 变量 | 类型 | 说明 |
|------|------|------|
| `current_state` | AgentState | 当前状态 |
| `current_activity` | String | 当前活动类型 |
| `activity_start_time` | float | 活动开始时间 |
| `last_activity` | String | 上一周期活动（用于体验） |
| `cached_request` | ActionRequest | 缓存的行动请求 |
| `is_waiting_execution` | bool | 是否等待Click执行 |

### 新增：情感评估相关

| 变量 | 类型 | 说明 |
|------|------|------|
| `_emotion_evaluation_prompt` | String | 情感评估Prompt模板 |
| `_last_emotional_record` | String | 上一次情感记录（调试用） |

### 状态流转图

```
IDLE
  │
  ├── Click触发 ──→ PERCEIVING ──→ EXPERIENCING（+情感评估）──→ DECIDING ──→ WAITING_FOR_CLICK
  │                                                                              │
  │                                                                              │
  └──←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←┘
                                          │
                                          ▼
                              Click执行 → EXECUTING_ACTION
                                          │
                          ┌───────────────┼───────────────┐
                          │               │               │
                          ▼               ▼               ▼
                      IN_DIALOGUE    IN_ACTIVITY       IDLE
                          │               │               │
                          └───────────────┴───────────────┘
                                          │
                                          ▼
                                    活动结束 → IDLE
```

---

## 感知信念状态

### 类定义

```gdscript
class_name PerceptionSystem
extends Node
```

### BeliefState 类

每个Agent对每个房间的信念状态：

```gdscript
class BeliefState:
    var S_mean: float      # 对初始收益率的后验均值
    var S_var: float       # 对初始收益率的后验方差
    var a_mean: float      # 对衰减率的后验均值
    var a_var: float       # 对衰减率的后验方差
    var samples: Array     # 观测样本缓存 [{time, gain}]
    var last_update_time: int  # 上次更新时间
```

### 先验分布

**健康Agent**:
```gdscript
S_mean = 0.5, S_var = 0.25
a_mean = 0.5, a_var = 0.25
```

**抑郁Agent**（悲观先验）:
```gdscript
S_mean = 0.3, S_var = 0.15  # 低估初始收益
a_mean = 0.6, a_var = 0.15  # 高估衰减速度
```

### API接口

```gdscript
# 获取感知参数
var params = PerceptionSystem.get_perceived_params(
    "StudentXiaoming",      # Agent名称
    "教室（主教学区）",      # 房间名称
    true                     # 是否是抑郁风险Agent
)
# 返回: {"S": 0.45, "a": 0.65, "confidence": 0.7}

# 获取信念描述（用于Prompt）
var desc = PerceptionSystem.get_belief_description(
    "StudentXiaoming",
    "教室（主教学区）",
    true
)
```

---

## 状态交互关系

### 状态更新流程

```
┌─────────────────────────────────────────────────────────────┐
│  1. 活动触发                                                 │
│     ActivityManager 分配活动 → AIAgent 执行                  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  2. 体验阶段（新增情感评估）                                  │
│     - 接收累积奖赏 (RewardSystem)                            │
│     - 贝叶斯更新信念 (PerceptionSystem)                      │
│     - **LLM情感评估** → 自然语言记忆 (MemorySystem)          │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  3. 决策阶段                                                 │
│     - 获取感知参数 (PerceptionSystem)                        │
│     - 获取相关记忆 (MemorySystem)                            │
│     - 计算MVT最优时间 (UtilitySystem)                        │
│     - LLM生成决策 (AIAgent)                                  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  4. 每日反思（v2.0）                                         │
│     - 收集所有自然语言记忆                                   │
│     - LLM分析情绪主题和认知变化                              │
│     - 更新动态特质 (DynamicPersonality)                      │
│     - PHQ-9完整评估                                          │
└─────────────────────────────────────────────────────────────┘
```

### 记忆在决策中的作用

```gdscript
# AIAgent 决策时构建Prompt
func _make_natural_decision(perception):
    # 1. 获取基础信息
    var personality = _get_personality()
    
    # 2. 获取相关记忆（自然语言）
    var memory_text = MemorySystem.instance.get_formatted_memories_for_prompt(character, 5)
    # 返回: "- 今天和小红讨论数学，感觉她人还不错..."
    
    # 3. 构建完整Prompt
    var prompt = PromptBuilder.build_natural_decision_prompt(self, perception)
    # 包含：人格 + 状态 + 自然语言记忆 + 当前情境
    
    # 4. LLM生成决策
    var decision = await _call_local_llm(prompt)
```

---

## 使用示例

### 示例1：查看角色完整状态

```gdscript
# 获取角色节点
var character = get_node("StudentXiaoming")
var agent = character.get_node("AIAgent")

# 1. 静态人设
var personality = CharacterPersonality.get_personality("StudentXiaoming")
print("角色: %s" % personality.name)
print("类型: %s" % personality.role_type)
print("努力敏感性: %.2f" % personality.cognitive_mechanism.beta_effort)

# 2. 动态特质
var traits = DynamicPersonality.get_dynamic_traits(character)
print("当前beta_effort: %.2f" % traits.beta_effort)
print("抑郁水平: %.2f" % traits.daily_depression_level)

# 3. 自然语言记忆
var memories = MemorySystem.instance.get_memories_about("StudentXiaoming", "小红", 3)
for mem in memories:
    print("记忆: %s" % mem)

# 4. 当前状态
print("当前状态: %s" % agent.current_state)
print("当前活动: %s" % agent.current_activity)
```

### 示例2：追踪情感变化

```gdscript
# 获取Agent对小红的所有情感记录
var all_memories = MemorySystem.instance._natural_memories.get("StudentXiaoming", [])
var xiaohong_memories = []

for mem in all_memories:
    if "小红" in mem.content:
        xiaohong_memories.append(mem)

# 按时间排序查看情感变化
for mem in xiaohong_memories:
    print("[%s] %s" % [mem.timestamp, mem.content])

# 输出示例:
// [第1天 10:45] 今天和小红讨论数学，她主动分享笔记，感觉人还不错。
// [第3天 14:20] 小红又在课堂上嘲笑我，真的很讨厌她。
// [第5天 09:15] 小红今天帮我捡起了掉落的笔，或许她也没那么坏。
```

### 示例3：调试情感评估

```gdscript
# 在AIAgent中查看最近一次情感评估
func _evaluate_activity_emotion(activity_info):
    var prompt = _build_emotion_evaluation_prompt(activity_info)
    print("情感评估Prompt:\n%s" % prompt)
    
    var emotional_record = await _call_llm_for_emotion(prompt)
    print("情感评估结果: %s" % emotional_record)
    
    # 存储...
```

---

## 版本历史

### v2.0 (2026-04-16)
- **重大重构**: 社交/情感记忆系统改为自然语言评估
- **移除**: SocialMemory.gd, EmotionMemory.gd（数值系统）
- **新增**: AIAgent._evaluate_activity_emotion()（LLM情感评估）
- **新增**: MemorySystem.add_natural_memory()（自然语言存储）
- **变更**: 动态特质更新改为每日反思时LLM统一评估

### v1.0 (2026-04-07)
- 初始版本
- SocialMemory/EmotionMemory数值系统
- 事件直接触发数值更新

---

*本文档由AI助手百舟楫维护*
