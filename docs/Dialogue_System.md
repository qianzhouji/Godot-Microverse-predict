# 对话系统设计文档

> **项目**: Godot-Microverse-predict 抑郁风险学生校园情境模拟系统  
> **最后更新**: 2026-04-14

---

## 1. 系统概述

### 1.1 设计目标

- 完全移除1v1对话系统，所有对话统一使用群组对话架构
- 与AIAgent的中范围划分系统对接（4象限/左右/单区）
- 支持2-7人同时对话（悄悄话最多3人）
- 智能发言队列，避免多人同时说话

### 1.2 核心特性

| 特性 | 说明 |
|------|------|
| 统一架构 | 所有对话使用GroupDialogueManager |
| 中范围对接 | 与AIAgent感知系统使用同一套中范围划分 |
| 三种范围 | 悄悄话(同中范围+贴身)/普通对话(同中范围)/广播(同房间) |
| 动态加入 | 普通/广播范围允许第三方加入，悄悄话不允许 |
| 智能队列 | 基于优先级的发言管理 |

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
| GroupDialogueManager.gd | script/ai/ | 群组对话管理（与中范围对接） | 17KB |
| DialogueInterruptionManager.gd | script/ai/ | 对话打断/插入机制 | 17KB |
| DialogueContextManager.gd | script/ai/ | 对话上下文同步 | 14KB |
| SpeakerQueueManager.gd | script/ai/ | 智能发言队列 | 14KB |
| MultiAgentDialogueIntegration.gd | script/ai/ | 统一集成器 | 16KB |

---

## 3. 对话范围（与场景中范围对接）

### 3.1 中范围划分系统

与AIAgent感知系统使用同一套中范围划分：

| 类型 | 适用场景 | 划分方式 |
|------|----------|----------|
| **FOUR_QUADRANT** | 教室、图书馆、自习室、食堂 | 右上Q1、左上Q2、左下Q3、右下Q4 |
| **LEFT_RIGHT** | 大走廊 | 左区LEFT、右区RIGHT |
| **SINGLE** | 小走廊 | 中心CENTER |

### 3.2 三种对话范围

| 范围 | 中范围要求 | 距离 | 人数限制 | 特点 |
|------|------------|------|----------|------|
| **WHISPER (悄悄话)** | 同一中范围 | 50px | 2-3人 | 私密，不允许第三方加入 |
| **NORMAL (普通对话)** | 同一中范围 | 200px | 2-7人 | 中范围内可加入 |
| **BROADCAST (广播)** | 同一房间 | 不限 | 2-7人 | 跨中范围，全房间可加入 |

### 3.3 范围配置

```gdscript
enum DialogueRange {
    WHISPER,      # 悄悄话 - 同一中范围+贴身
    NORMAL,       # 普通对话 - 同一中范围
    BROADCAST     # 广播 - 同一房间
}

# 距离配置
const WHISPER_DISTANCE: float = 50.0       # 悄悄话距离
const NORMAL_DISTANCE: float = 200.0       # 普通对话距离

# 人数限制
const GROUP_MIN_PARTICIPANTS: int = 2
const GROUP_MAX_PARTICIPANTS: int = 7      # 普通/广播
const WHISPER_MAX_PARTICIPANTS: int = 3    # 悄悄话
```

---

## 4. API参考

### 4.1 统一集成接口

**MultiAgentDialogueIntegration**

```gdscript
# 开始对话
func start_dialogue(
    initiator: CharacterBody2D,
    target: CharacterBody2D,
    dialogue_range: int = DialogueRange.NORMAL,
    topic: String = ""
) -> bool

# 开始群组对话
func start_group_dialogue(
    initiator: CharacterBody2D,
    participants: Array[CharacterBody2D],
    topic: String = "",
    dialogue_range: int = DialogueRange.NORMAL,
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

# 普通对话（同一中范围）
integration.start_dialogue(agent_a, agent_b, GroupDialogueManager.DialogueRange.NORMAL)

# 悄悄话（同一中范围，贴身）
integration.start_dialogue(agent_a, agent_b, GroupDialogueManager.DialogueRange.WHISPER)

# 广播（全房间，跨中范围）
var participants = [agent_a, agent_b, agent_c, agent_d]
integration.start_group_dialogue(
    agent_a, 
    participants, 
    "讨论作业",
    GroupDialogueManager.DialogueRange.BROADCAST
)
```

### 4.3 中范围接口

**GroupDialogueManager** 提供与AIAgent中范围系统对接的接口：

```gdscript
# 获取角色的中范围信息
func _get_character_medium_range_info(character: CharacterBody2D) -> Dictionary
# 返回: {"room_name": "", "medium_range_type": -1, "medium_range_id": ""}

# 检查两个角色是否在同一个中范围
func _is_in_same_medium_range(char1: CharacterBody2D, char2: CharacterBody2D) -> bool
```

---

## 5. 发言队列系统

### 5.1 优先级计算

```
当前优先级 = 基础优先级 (10-90)
         + 连续发言惩罚 (-20*n)
         + 沉默奖励 (+5/轮, max+15)
         + 被打断补偿 (+10)
         + 话题相关度加成 (±20)
         + 发言意愿加成 (±10)
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
# 普通对话 - 同一中范围
func _execute_start_dialogue(request: ActionRequest):
    integration.start_dialogue(character, target, GroupDialogueManager.DialogueRange.NORMAL)

# 悄悄话 - 同一中范围+贴身
func _execute_start_whisper(request: ActionRequest):
    integration.start_dialogue(character, target, GroupDialogueManager.DialogueRange.WHISPER)

# 加入对话
func _execute_join_dialogue(request: ActionRequest):
    integration.request_join_dialogue(character, target, InterruptionType.POLITE)

# 退出对话
func _execute_exit_dialogue(request: ActionRequest):
    integration.leave_dialogue(character)
```

### 6.2 中范围信息存储

角色元数据中存储中范围信息：
```gdscript
character.set_meta("current_room", "教室")
character.set_meta("medium_range_id", "Q1")  # 第一象限
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
- ✅ 与AIAgent中范围划分系统对接（4象限/左右/单区）
- ✅ 三种范围：悄悄话/普通对话/广播
- ✅ 最小参与人数改为2人
- ✅ 悄悄话最多3人，普通/广播2-7人

---

*文档维护者：百舟楫*  
*最后更新：2026-04-14*
