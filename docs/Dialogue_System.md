# 对话系统设计文档

> **项目**: Godot-Microverse-predict 抑郁风险学生校园情境模拟系统  
> **最后更新**: 2026-04-14

---

## 1. 系统概述

### 1.1 设计目标

- 完全移除1v1对话系统，所有对话统一使用群组对话架构
- 支持大/中/小三种范围，由发起人决定
- 支持2-7人同时对话（悄悄话最多3人）
- 智能发言队列，避免多人同时说话

### 1.2 核心特性

| 特性 | 说明 |
|------|------|
| 统一架构 | 所有对话使用GroupDialogueManager |
| 三种范围 | 小(30px)/中(150px)/大(300px) |
| 动态加入 | 中/大范围允许第三方加入，悄悄话不允许 |
| 智能队列 | 基于优先级的发言管理 |
| 打断机制 | 四种打断模式 |

---

## 2. 架构设计

### 2.1 系统架构

```
┌─────────────────────────────────────────┐
│   MultiAgentDialogueIntegration         │
│            (统一集成接口)                │
└─────────────────┬───────────────────────┘
                  │
    ┌─────────────┼─────────────┐
    │             │             │
    ▼             ▼             ▼
┌────────┐  ┌──────────┐  ┌──────────┐
│ Group  │  │Dialogue  │  │Dialogue  │
│Dialogue│  │Interrup- │  │Context   │
│Manager │  │tion      │  │Manager   │
└────────┘  │Manager   │  └──────────┘
            └──────────┘
                  │
                  ▼
            ┌──────────┐
            │ Speaker  │
            │ Queue    │
            │ Manager  │
            └──────────┘
```

### 2.2 脚本清单

| 脚本 | 路径 | 功能 | 大小 |
|------|------|------|------|
| GroupDialogueManager.gd | script/ai/ | 群组对话管理 | 17KB |
| DialogueInterruptionManager.gd | script/ai/ | 对话打断/插入 | 17KB |
| DialogueContextManager.gd | script/ai/ | 对话上下文同步 | 14KB |
| SpeakerQueueManager.gd | script/ai/ | 智能发言队列 | 14KB |
| MultiAgentDialogueIntegration.gd | script/ai/ | 统一集成器 | 16KB |

---

## 3. 对话范围

### 3.1 范围配置

```gdscript
enum DialogueRange {
    SMALL,    # 小范围 - 悄悄话 (30px)
    MEDIUM,   # 中范围 - 普通对话 (150px)
    LARGE     # 大范围 - 公开讨论 (300px)
}

const RANGE_SMALL: float = 30.0
const RANGE_MEDIUM: float = 150.0
const RANGE_LARGE: float = 300.0
```

### 3.2 人数限制

| 范围 | 最小 | 最大 | 说明 |
|------|------|------|------|
| SMALL (悄悄话) | 2 | 3 | 私密，不允许第三方加入 |
| MEDIUM (普通对话) | 2 | 7 | 附近人可听到，可加入 |
| LARGE (公开讨论) | 2 | 7 | 公开，任何人可加入 |

---

## 4. API参考

### 4.1 统一集成接口

**MultiAgentDialogueIntegration**

```gdscript
# 开始对话
func start_dialogue(
    initiator: CharacterBody2D,
    target: CharacterBody2D,
    dialogue_range: int = DialogueRange.MEDIUM,
    topic: String = ""
) -> bool

# 开始群组对话
func start_group_dialogue(
    initiator: CharacterBody2D,
    participants: Array[CharacterBody2D],
    topic: String = "",
    dialogue_range: int = DialogueRange.MEDIUM,
    primary_target: CharacterBody2D = null
) -> bool

# 请求加入对话
func request_join_dialogue(
    requester: CharacterBody2D,
    target_dialogue: Variant,
    interruption_type: int = 0
) -> bool

# 离开对话
func leave_dialogue(character: CharacterBody2D) -> bool

# 检查是否在对话中
func is_character_in_any_dialogue(character: CharacterBody2D) -> bool

# 获取对话模式
func get_character_dialogue_mode(character: CharacterBody2D) -> String
```

### 4.2 使用示例

```gdscript
var integration = MultiAgentDialogueIntegration.instance

# 普通对话（中范围150px）
integration.start_dialogue(agent_a, agent_b, GroupDialogueManager.DialogueRange.MEDIUM)

# 悄悄话（小范围30px）
integration.start_dialogue(agent_a, agent_b, GroupDialogueManager.DialogueRange.SMALL)

# 公开讨论（大范围300px）
var participants = [agent_a, agent_b, agent_c, agent_d]
integration.start_group_dialogue(
    agent_a, 
    participants, 
    "讨论作业",
    GroupDialogueManager.DialogueRange.LARGE
)
```

### 4.3 群组对话管理

**GroupDialogueManager**

```gdscript
# 开始群组对话
func try_start_group_dialogue(
    initiator: CharacterBody2D,
    participants: Array[CharacterBody2D],
    topic: String = "",
    dialogue_range: int = DialogueRange.MEDIUM,
    primary_target: CharacterBody2D = null
) -> bool

# 加入对话
func try_join_group_dialogue(character: CharacterBody2D, dialogue_id: String) -> bool

# 离开对话
func leave_group_dialogue(character: CharacterBody2D, dialogue_id: String) -> bool

# 查询
func is_character_in_group_dialogue(character: CharacterBody2D) -> bool
func get_character_group_dialogue(character: CharacterBody2D) -> String
```

### 4.4 打断管理

**DialogueInterruptionManager**

```gdscript
enum InterruptionType {
    POLITE,      # 礼貌打断
    URGENT,      # 紧急打断
    CASUAL,      # 随意插入
    LISTEN_ONLY  # 只旁听
}

func request_interruption(
    requester: CharacterBody2D,
    target_character: CharacterBody2D,
    interruption_type: int = InterruptionType.POLITE,
    reason: String = ""
) -> bool
```

---

## 5. 发言队列系统

### 5.1 优先级计算

```
当前优先级 = 基础优先级
         + 连续发言惩罚(-20*n)
         + 沉默奖励(+5/轮, max+15)
         + 被打断补偿(+10)
         + 话题相关度加成(±20)
         + 发言意愿加成(±10)
```

### 5.2 基础优先级

- 大五人格 - 外向性 (±20)
- 大五人格 - 宜人性 (±10)
- 沟通风格 (主动型+15, 被动型-15)
- 依恋风格 (回避型-10, 焦虑型+10)

### 5.3 发言延迟

```
延迟 = 基础2秒
     - 外向性加成
     - 话题相关度加成
     - 发言意愿加成
     + 随机因素
```
范围: 2-8秒

---

## 6. AIAgent集成

### 6.1 对话执行函数

```gdscript
# 普通对话 - 中范围
func _execute_start_dialogue(request: ActionRequest):
    integration.start_dialogue(character, target, GroupDialogueManager.DialogueRange.MEDIUM)

# 悄悄话 - 小范围
func _execute_start_whisper(request: ActionRequest):
    integration.start_dialogue(character, target, GroupDialogueManager.DialogueRange.SMALL)

# 加入对话
func _execute_join_dialogue(request: ActionRequest):
    integration.request_join_dialogue(character, target, InterruptionType.POLITE)

# 退出对话
func _execute_exit_dialogue(request: ActionRequest):
    integration.leave_dialogue(character)
```

---

## 7. 场景配置

```
School (根节点)
├── MultiAgentDialogueIntegration
│   ├── GroupDialogueManager
│   ├── DialogueInterruptionManager
│   ├── DialogueContextManager
│   └── SpeakerQueueManager
└── ...其他节点
```

---

## 8. 改动记录

### 2026-04-14 架构重构

- ✅ 完全移除1v1对话系统
- ✅ 所有对话统一使用GroupDialogueManager
- ✅ 支持大/中/小三种范围
- ✅ 最小参与人数改为2人
- ✅ 悄悄话最多3人，普通/公开讨论2-7人

---

*文档维护者：百舟楫*  
*最后更新：2026-04-14*
