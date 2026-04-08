# 角色状态系统详细文档

> **系统名称**: CharacterPersonality + DynamicPersonality + MemoryManager + AIAgent
> **版本**: 1.0
> **最后更新**: 2026-04-07

---

## 目录

1. [系统概述](#系统概述)
2. [静态人设状态](#静态人设状态)
3. [动态特质状态](#动态特质状态)
4. [记忆系统](#记忆系统)
5. [运行时状态](#运行时状态)
6. [感知信念状态](#感知信念状态)
7. [状态交互关系](#状态交互关系)
8. [使用示例](#使用示例)

---

## 系统概述

### 设计目标

角色状态系统是 Godot-Microverse-predict 项目的核心数据层，负责：
- 定义角色的静态人设（性格、能力、背景）
- 追踪角色的动态心理变化
- 存储角色的经历和记忆
- 管理角色的实时活动状态

### 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│  数据层（Data Layer）                                         │
│  ├─ CharacterPersonality     - 静态人设配置                  │
│  ├─ DynamicPersonality       - 动态特质管理                  │
│  ├─ MemoryManager            - 记忆存储与检索                │
│  └─ PerceptionSystem         - 感知信念状态                  │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  运行时层（Runtime Layer）                                    │
│  ├─ AIAgent                  - 实时活动状态                  │
│  ├─ AgentRewardReceiver      - 奖赏历史                      │
│  └─ CharacterBody2D          - 物理位置和动画                │
└─────────────────────────────────────────────────────────────┘
```

### 状态分类

| 层级 | 状态类型 | 存储位置 | 更新频率 |
|------|---------|---------|---------|
| 静态层 | 人设配置 | CharacterPersonality.PERSONALITY_CONFIG | 永不更新 |
| 动态层 | 心理特质 | character_data.dynamic_traits | 事件触发 |
| 记忆层 | 经历记忆 | character_data.memories | 持续累积 |
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

| 维度 | 字段 | 范围 | 健康Agent | 抑郁Agent | 含义 |
|------|------|------|----------|----------|------|
| 开放性 | `openness` | 0-100 | 70 | 45 | 想象力、好奇心 |
| 尽责性 | `conscientiousness` | 0-100 | 65 | 70 | 自律、组织性 |
| 外向性 | `extraversion` | 0-100 | 85 | 30 | 社交活跃度 |
| 宜人性 | `agreeableness` | 0-100 | 75 | 55 | 合作、信任 |
| 神经质 | `neuroticism` | 0-100 | 35 | 75 | 情绪稳定性 |

### 4. 初始抑郁状态

```gdscript
"initial_depression": {
    "phq9_baseline": 12,                 # PHQ-9基线分数 (0-27)
    "severity_level": "中度",             # 严重程度等级
    "symptom_duration_weeks": 8,         # 症状持续周数
    "key_symptoms": ["兴趣减退", "疲劳感", "睡眠问题", "自我否定"]
}
```

**PHQ-9分数对应表**:
| 分数 | 等级 | 抑郁水平 |
|------|------|---------|
| 0-4 | 无 | 0-0.15 |
| 5-9 | 轻度 | 0.15-0.33 |
| 10-14 | 中度 | 0.33-0.52 |
| 15-19 | 中重度 | 0.52-0.70 |
| 20-27 | 重度 | 0.70-1.0 |

### 5. 功能水平

```gdscript
"functioning_level": {
    "academic_functioning": 65,          # 学业功能 (0-100)
    "social_functioning": 40,            # 社交功能 (0-100)
    "daily_living": 70,                  # 日常生活 (0-100)
    "peer_relationships": 35,            # 同伴关系 (0-100)
    "teacher_relationships": 60          # 师生关系 (0-100)
}
```

### 6. 专能性

```gdscript
"specific_ability": {
    "mathematics": 75,                   # 数学
    "verbal_expression": 50,             # 语言表达
    "visual_spatial": 60,                # 视觉空间
    "physical_coordination": 45,         # 身体协调
    "creative_thinking": 55,             # 创造性思维
    "problem_solving": 70,               # 问题解决
    "memory": 65,                        # 记忆力
    "attention_span": 50                 # 注意力持续时间
}
```

### 7. 认知机制参数（MVT模型）

```gdscript
"cognitive_mechanism": {
    "p_base": 0.4,                       # 离开阈值
    "eta_s": 0.6,                        # 初始奖赏感知权重
    "eta_a": 0.7,                        # 衰减率感知权重
    "beta_effort": 0.8,                  # 努力敏感性（核心差异参数）
    "alpha": 0.55                        # 收益敏感性
}
```

**参数对比表**:
| 参数 | 健康Agent | 抑郁Agent | 功能说明 |
|------|----------|----------|---------|
| `p_base` | 0.5-0.6 | 0.3-0.4 | 对环境平均奖赏的估计 |
| `eta_s` | 0.5-0.7 | 0.6 | 对初始丰富度的敏感度 |
| `eta_a` | 0.4-0.55 | 0.7-0.75 | 对奖赏衰减的敏感度 |
| `beta_effort` | 0.4 | **0.8** | 努力成本对决策的影响 |
| `alpha` | 0.8 | 0.5-0.6 | 收益的非线性效用 |

### 获取人设数据

```gdscript
# 获取完整人设
var personality = CharacterPersonality.get_personality("StudentXiaoming")

# 获取特定字段
var role_type = personality.get("role_type", "healthy_student")
var big_five = personality.get("big_five", {})
var cognitive = personality.get("cognitive_mechanism", {})
```

---

## 动态特质状态

### 类定义

```gdscript
class_name DynamicPersonality
extends Node
```

### 存储位置

动态特质存储在角色的 `character_data.dynamic_traits` 元数据中。

### 动态特质列表

| 特质 | 字段 | 范围 | 基线来源 | 变化触发 |
|------|------|------|---------|---------|
| 当日抑郁水平 | `daily_depression_level` | 0-1 | 0.5 | 每日反思、事件反馈 |
| 离开阈值 | `p_base` | 0-1 | cognitive_mechanism.p_base | 任务成功/失败 |
| 初始奖赏感知权重 | `eta_s` | 0-1 | cognitive_mechanism.eta_s | 积极/消极社交 |
| 衰减率感知权重 | `eta_a` | 0-1 | cognitive_mechanism.eta_a | 负面预期 |
| 努力敏感性 | `beta_effort` | 0-1 | cognitive_mechanism.beta_effort | 任务反馈、教师评价 |

### 边界保护机制

动态特质不能偏离基线超过20%：
```gdscript
new_value = clamp(new_value, baseline - 0.2, baseline + 0.2)
```

### 更新规则

#### 任务反馈影响

| 事件 | 影响参数 | 抑郁Agent | 健康Agent |
|------|---------|----------|----------|
| 任务成功 | beta_effort↓, p_base↑, 抑郁↓ | ×0.7 | ×1.2 |
| 任务失败 | beta_effort↑, p_base↓, 抑郁↑ | ×1.5 | ×0.8 |

#### 社交互动影响

| 事件 | 影响参数 | 抑郁Agent | 健康Agent |
|------|---------|----------|----------|
| 积极社交 | 抑郁↓, eta_s↑ | ×0.7 | ×1.2 |
| 消极社交 | beta_effort↑, eta_a↑, 抑郁↑ | ×1.5 | ×0.8 |

#### 教师评价影响

| 事件 | 影响参数 | 抑郁Agent | 健康Agent |
|------|---------|----------|----------|
| 表扬 | beta_effort↓, 抑郁↓ | ×0.7 | ×1.2 |
| 批评 | beta_effort↑, 抑郁↑ | ×1.5 | ×0.8 |

### API接口

```gdscript
# 获取动态特质
var traits = DynamicPersonality.get_dynamic_traits(character)

# 更新特质
DynamicPersonality.update_trait(
    character,           # 角色节点
    "beta_effort",       # 特质名称
    -0.05,               # 变化量（负值减少）
    "任务成功增强自信"    # 原因（用于记忆）
)

# 获取PHQ-9等级描述
var desc = DynamicPersonality.get_phq9_level_description(0.45)
# 返回: "中度抑郁 (PHQ-9: 10-14)"

# 获取特质用于Prompt
var prompt_text = DynamicPersonality.get_traits_for_prompt(character)
```

---

## 记忆系统

### 类定义

```gdscript
# MemoryManager.gd
extends Node
```

### 记忆类型枚举

```gdscript
enum MemoryType {
    PERSONAL,      # 个人记忆（内心想法、感受）
    INTERACTION,   # 互动记忆（与他人对话）
    TASK,          # 任务记忆（完成任务的经历）
    EMOTION,       # 情感记忆（强烈的情绪体验）
    EVENT          # 事件记忆（重要事件）
}
```

### 重要性等级

```gdscript
enum MemoryImportance {
    LOW = 1,       # 低重要性
    NORMAL = 3,    # 普通重要性
    HIGH = 5,      # 高重要性
    CRITICAL = 10  # 关键重要性
}
```

### 记忆结构

```gdscript
{
    "content": "记忆内容文本",
    "timestamp": "2026-04-07 15:30",  # 可读时间
    "type": MemoryType.INTERACTION,    # 记忆类型
    "importance": 5,                   # 重要性等级
    "created_at": 1712485800          # Unix时间戳（用于排序）
}
```

### 记忆存储位置

记忆存储在角色的 `character_data.memories` 数组中。

### API接口

```gdscript
# 添加记忆
MemoryManager.add_memory(
    character,                              # 角色节点
    "今天和小红在食堂吃饭，聊得很开心",       # 记忆内容
    MemoryManager.MemoryType.INTERACTION,   # 记忆类型
    MemoryManager.MemoryImportance.NORMAL   # 重要性
)

# 获取所有记忆
var memories = MemoryManager.get_character_memories(character)

# 获取格式化的记忆文本（用于AI Prompt）
var memory_text = MemoryManager.get_formatted_memories_for_prompt(character, 5)
# 返回: "\n\n记忆信息：\n- [互动] 今天和小红在食堂吃饭...\n- [任务] 完成了数学作业..."

# 获取特定类型的记忆
var interaction_memories = MemoryManager.get_memories_by_type(
    character, 
    MemoryManager.MemoryType.INTERACTION
)
```

### 记忆清理机制

- 自动清理：当记忆数量超过阈值时，删除最不重要、最旧的记忆
- 保留策略：高重要性记忆优先保留

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
    EXPERIENCING,        # 体验中 - 处理奖赏反馈
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
| `current_activity` | String | 当前活动类型（"对话"、"体育活动"、"自习"） |
| `activity_start_time` | float | 活动开始时间（Unix时间戳） |
| `last_activity` | String | 上一周期活动（用于体验阶段） |
| `cached_request` | ActionRequest | 缓存的行动请求 |
| `is_waiting_execution` | bool | 是否等待Click执行 |
| `is_player_controlled` | bool | 是否由玩家控制 |

### 移动状态

| 变量 | 类型 | 说明 |
|------|------|------|
| `_is_moving` | bool | 是否正在移动 |
| `_target_position` | Vector2 | 目标位置坐标 |
| `_movement_check_timer` | float | 移动检查计时器 |

### 状态流转图

```
IDLE
  │
  ├── Click触发 ──→ PERCEIVING ──→ EXPERIENCING ──→ DECIDING ──→ WAITING_FOR_CLICK
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

### 存储结构

```gdscript
static var agent_beliefs: Dictionary = {
    "AgentName": {
        "RoomName": BeliefState,
        "AnotherRoom": BeliefState
    }
}
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
# 返回: "\n\n【你对当前情境的感知】\n- 你觉得这个情境一开始能获得的收益：45%（较低）..."

# 预测未来收益
var predicted = PerceptionSystem.predict_gain(
    "StudentXiaoming",
    "教室（主教学区）",
    10.0,  # 10分钟后的收益
    true
)
```

---

## 状态交互关系

### 状态更新流程

```
事件触发
    │
    ├──→ 更新动态特质（DynamicPersonality.update_trait）
    │       └── 修改 character_data.dynamic_traits
    │
    ├──→ 添加记忆（MemoryManager.add_memory）
    │       └── 添加到 character_data.memories
    │
    ├──→ 更新感知信念（PerceptionSystem.add_sample）
    │       └── 修改 agent_beliefs[agent][room]
    │
    └──→ 更新运行时状态（AIAgent）
            └── 修改 current_state, current_activity等
```

### 数据流向

```
静态人设（CharacterPersonality）
    │
    ├──→ 初始化动态特质基线
    │
    ├──→ 提供Prompt构建信息
    │
    └──→ 决策时读取认知参数

动态特质（DynamicPersonality）
    │
    ├──→ 影响决策（通过Prompt）
    │
    ├──→ 触发记忆记录
    │
    └──→ 每日反思时更新

记忆（MemoryManager）
    │
    ├──→ 影响决策（通过Prompt）
    │
    └──→ 情感关系计算

感知信念（PerceptionSystem）
    │
    └──→ 影响决策（通过Prompt）

运行时状态（AIAgent）
    │
    ├──→ 驱动行为执行
    │
    └──→ 触发体验采样
```

---

## 使用示例

### 示例1：获取角色完整状态

```gdscript
func get_character_full_status(character: Node) -> Dictionary:
    var status = {}
    
    # 1. 静态人设
    status["personality"] = CharacterPersonality.get_personality(character.name)
    
    # 2. 动态特质
    status["dynamic_traits"] = DynamicPersonality.get_dynamic_traits(character)
    
    # 3. 记忆
    status["memories"] = MemoryManager.get_character_memories(character)
    
    # 4. 运行时状态
    var agent = character.get_node("AIAgent")
    if agent:
        status["current_state"] = agent.current_state
        status["current_activity"] = agent.current_activity
    
    return status
```

### 示例2：处理事件并更新状态

```gdscript
func on_task_completed(character: Node, success: bool):
    # 1. 更新动态特质
    var effort_level = 0.5
    DynamicPersonality.apply_task_feedback(character, success, effort_level)
    
    # 2. 添加记忆
    var result = "成功" if success else "失败"
    MemoryManager.add_memory(
        character,
        "任务%s完成" % result,
        MemoryManager.MemoryType.TASK,
        MemoryManager.MemoryImportance.HIGH
    )
```

### 示例3：构建决策Prompt

```gdscript
func build_decision_context(character: Node) -> String:
    var context = ""
    
    # 静态人设
    var personality = CharacterPersonality.get_personality(character.name)
    context += "【人格特质】" + personality.get("personality", "")
    
    # 动态特质
    context += DynamicPersonality.get_traits_for_prompt(character)
    
    # 记忆
    context += MemoryManager.get_formatted_memories_for_prompt(character, 5)
    
    # 感知参数
    var current_room = get_current_room(character)
    context += PerceptionSystem.get_belief_description(
        character.name, current_room, is_depression_risk(character)
    )
    
    return context
```

---

*文档维护者：百舟楫*
*最后更新：2026-04-07*
