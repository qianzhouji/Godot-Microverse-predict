# 对话系统设计文档

> **项目**: Godot-Microverse-predict 抑郁风险学生校园情境模拟系统
> **当前状态**: 以 `main` 分支现行实现为准
> **最后更新**: 2026-05-18

---

## 1. 系统定位

当前对话系统由 `script/ai/DialogueManager.gd` 统一管理。它是 Godot AutoLoad 单例，单例名为 `DialogueManager`，代码中应通过 `/root/DialogueManager` 或 `DialogueManager` 访问。

对话系统本身负责“能否创建、加入、离开、发言、结束对话”的客观规则；是否想说话、何时说话、是否应该离开课堂等主观判断，主要交给 AIAgent 与 LLM prompt 决定。

---

## 2. 核心脚本

| 脚本 | 路径 | 当前职责 |
|------|------|----------|
| `DialogueManager.gd` | `script/ai/` | 统一对话生命周期、范围校验、消息记录 |
| `SpeakerQueueManager.gd` | `script/ai/` | 对话内发言队列与发言权调度 |
| `DialogueContextManager.gd` | `script/ai/` | 对话上下文辅助管理 |
| `ActivityCoordinator.gd` | `script/system/` | 将 LLM 输出解析为 `INITIATE_DIALOGUE` / `JOIN_DIALOGUE` / `LEAVE_DIALOGUE` 活动 |
| `AIAgent.gd` | `script/ai/` | 执行对话活动，调用 DialogueManager，并生成/接收对话内容 |

历史文档中提到的 `GroupDialogueManager.gd`、`MultiAgentDialogueIntegration.gd`、`DialogueInterruptionManager.gd` 不属于当前 `main` 分支的有效主流程。

---

## 3. 对话范围

`DialogueManager.RangeType` 定义三种范围：

| 范围 | 边界 | 人数限制 | 说明 |
|------|------|----------|------|
| `WHISPER` | 发起者附近小范围，且通常要求同一中范围 | 最多3人 | 悄悄话，不允许第三方随意加入 |
| `NORMAL` | 发起者所在中范围 | 最多7人 | 普通对话，同中范围角色可加入 |
| `BROADCAST` | 发起者所在 RoomArea | 无上限 | 广播式对话，例如教师面向全房间讲话 |

可见性分两层：

- 行为可见：同一子场景内的角色可能感知到“有人在对话”。
- 内容可见：只有满足范围边界的角色能听到具体内容。

---

## 4. 标准流程

### 4.1 发起对话

1. AIAgent 产生自然语言意图，例如“我想和小红聊一下刚才的课程”。
2. ActivityCoordinator 收集多个 Agent 的意图。
3. LLM 为某个角色分配 `INITIATE_DIALOGUE`。
4. AIAgent 执行活动，调用 `DialogueManager.start_dialogue()`。
5. DialogueManager 生成 `dialogue_id`，记录发起者、范围、房间、中范围、主题与起始时间。

### 4.2 加入对话

1. LLM 可以输出 `JOIN_DIALOGUE`。
2. 如果没有可靠的 `dialogue_id`，系统会尝试使用当前位置可加入的活跃对话。
3. DialogueManager 校验房间、中范围、人数限制和悄悄话限制。
4. 校验通过后角色加入，并进入对应对话状态。

### 4.3 对话进行

1. SpeakerQueueManager 选择下一位发言者。
2. 发言者通过 LLM 生成回复。
3. DialogueManager 记录消息历史。
4. 同范围内角色在后续感知中可以读取对话内容。

### 4.4 对话结束

对话可能因为以下原因结束：

| 原因 | 说明 |
|------|------|
| `SILENCE` | 多轮无人继续发言 |
| `TIMEOUT` | 对话持续过久 |
| `MANUAL` | 活动或角色主动结束 |
| `EMPTY` | 参与人数不足 |

---

## 5. 与课表的关系

TimelineState 会提供当前时间段、课程名、建议房间等上下文，但不在系统层强制禁止对话，也不强制角色回教室。

也就是说：

- 上课时“是否应该说话”由 AIAgent prompt 和 LLM 判断。
- DialogueManager 只判断对话范围、人数、房间/中范围等客观可行性。
- ActivityCoordinator 不会因为课表直接覆盖 LLM 分配结果。

这是为了让正式接入更强大模型 API 后，角色行为更多体现主观判断，而不是硬编码课表控制。

---

## 6. 常见注意点

- AutoLoad 名是 `DialogueManager`，不是 `DialogManager`。
- `JOIN_DIALOGUE` 不应依赖 LLM 编造的 `dialogue_id`。如果同轮结果里没有真实 ID，Coordinator 会清空不可用 ID，并尽量让角色加入当前位置可见对话。
- 对话活动应跟随移动活动之后执行。角色不在同房间/同中范围时，DialogueManager 会拒绝加入普通对话。
- 本地 1.5B 模型输出奇怪文本时，优先判断是否是模型能力问题；只在状态机、解析、范围校验、ID 传递等系统逻辑错误时修改代码。
