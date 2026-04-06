# 抑郁风险学生模拟系统 - 重构任务清单

> **创建日期**: 2026-04-06
> **项目**: Godot-Microverse-predict
> **状态**: 进行中

---

## 一、任务系统重构 ✅

### 已完成
- [x] 删除初始任务分配逻辑
- [x] 简化任务系统，仅保留课程表驱动的移动任务
- [x] 上课时间强制Agent移动到对应教室
- [x] 删除 `_generate_initial_tasks()` 及相关函数
- [x] 修复AIAgent.gd语法错误

### 实现细节
- **TaskManager.gd**: 完全重写，根据课程表分配移动任务
- **AIAgent.gd**: 新增 `_execute_class_movement()` 直接处理课程移动
- **课程表**: 8:00班主任课 → 8:55英语课 → 9:50小组讨论 → 10:45午休 → 11:45数学课 → 12:40体育活动
- **逃课机制**: 抑郁风险学生根据 `beta_effort` 有概率逃课

---

## 二、对话系统重构（广播式对话 + 场景集成）⏳

### 设计目标
将对话系统与场景系统深度集成，基于子场景（RoomArea）定义对话范围，实现自然的社交互动。

### 核心设计

#### 1. 三层对话范围架构

| 层级 | 定义方式 | 范围 | 使用场景 |
|------|---------|------|---------|
| **大范围** | 整个子场景（RoomArea） | 教室/讨论室的全部区域 | 教师讲课、广播通知 |
| **中范围** | 子场景内的分区 | 子场景划分为多个区域 | 正常交谈、小组讨论 |
| **小范围** | 以Agent为中心的圆形 | 极近距离（约60px半径） | 悄悄话、私密对话 |

#### 2. 大范围（子场景级）

**适用场景**: 仅教室（主教学区）和教室（小组讨论区）

```gdscript
# 大范围 = 整个RoomArea的边界框
func get_large_range(room_area: Area2D) -> Rect2:
    var collision_shape = room_area.get_node("CollisionShape2D")
    var shape = collision_shape.shape
    var size = shape.size
    var pos = collision_shape.position
    return Rect2(pos - size/2, size)
```

**使用权限**: 
- 教师角色可以使用大范围广播
- 特殊场景（如紧急通知）

#### 3. 中范围（子场景分区）

**分区规则**:

| 子场景类型 | 分区方式 | 中范围数量 |
|-----------|---------|-----------|
| 健身房、食堂、图书馆、自习室 | 均分为4个象限 | 4个中范围 |
| 教室（主教学区） | 均分为4个象限 | 4个中范围 |
| 教室（小组讨论区） | 均分为4个象限 | 4个中范围 |
| 大走廊 | 均分为左右两个区域 | 2个中范围 |
| 小走廊 | 整个区域作为一个中范围 | 1个中范围 |

```gdscript
# 计算中范围分区
func get_medium_ranges(room_area: Area2D) -> Array[Rect2]:
    var collision_shape = room_area.get_node("CollisionShape2D")
    var shape = collision_shape.shape
    var size = shape.size
    var center = collision_shape.position
    var ranges = []
    
    match room_area.room_name:
        "大走廊":
            # 左右两个分区
            ranges.append(Rect2(center - Vector2(size.x/2, size.y/2), Vector2(size.x/2, size.y)))
            ranges.append(Rect2(center + Vector2(0, -size.y/2), Vector2(size.x/2, size.y)))
        "小走廊":
            # 整个区域
            ranges.append(Rect2(center - size/2, size))
        _:
            # 4象限分区
            var quadrant_size = size / 2
            ranges.append(Rect2(center - size/2, quadrant_size))  # 左上
            ranges.append(Rect2(center + Vector2(0, -size.y/2), quadrant_size))  # 右上
            ranges.append(Rect2(center + Vector2(-size.x/2, 0), quadrant_size))  # 左下
            ranges.append(Rect2(center, quadrant_size))  # 右下
    
    return ranges
```

**对话触发机制**:
- Agent可以感知整个子场景内的所有Agent（保留原有设计）
- 想要开启对话，需要进入目标Agent所在的**中范围**
- 对话广播只发送到同一中范围内的Agent

#### 4. 小范围（贴身范围）

**定义**: 以Agent为中心，半径约60px的圆形区域

```gdscript
const SMALL_RANGE_RADIUS = 60.0

func get_small_range(agent_position: Vector2) -> Dictionary:
    return {
        "center": agent_position,
        "radius": SMALL_RANGE_RADIUS
    }

func is_in_small_range(listener_pos: Vector2, speaker_pos: Vector2) -> bool:
    return listener_pos.distance_to(speaker_pos) <= SMALL_RANGE_RADIUS
```

**对话触发机制**:
- Agent想要进行私密对话，需要进入目标Agent的**小范围**
- 小范围对话不会被中范围或大范围内的其他Agent听到
- 适用于悄悄话、私密交流

#### 5. 对话广播流程

```
Agent A 决定发言
    ↓
确定对话范围类型（大/中/小）
    ↓
获取该范围内的所有Agent
    ↓
向范围内的Agent广播对话内容
    ↓
每个接收Agent：
  - 基于内容、身份、情感关系决定是否回复
  - 如需回复，进入自己的发言流程
```

#### 6. 范围选择策略

| 场景 | 自动选择 | 手动切换 |
|------|---------|---------|
| 教师在教室讲课 | 大范围 | 教师可主动切换为中/小 |
| 学生在教室自习 | 中范围（所在象限） | 可切换为小范围 |
| 走廊偶遇 | 中范围 | 可切换为小范围 |
| 想要私密对话 | - | 必须进入小范围 |

```gdscript
# Agent选择对话范围
func select_voice_range(context: Dictionary) -> int:
    if context.is_teacher and context.in_classroom:
        return VOICE_RANGE_LARGE
    elif context.want_private_talk:
        return VOICE_RANGE_SMALL
    else:
        return VOICE_RANGE_MEDIUM
```

#### 7. 典型使用场景示例

**场景1: 课堂授课（大范围）**
```
时间: 上课时间
地点: 教室（主教学区）
触发者: 教师
对话范围: 大范围（整个教室）

教师提问: "谁能回答这个问题？"
    ↓ 大范围广播
教室内所有学生收到
    ↓
学生A（知道答案）: 举手/回答
学生B（不知道）: 保持沉默
学生C（抑郁风险）: 低头回避（基于beta_effort可能跳过）
```

**场景2: 小组讨论（中范围）**
```
时间: 上课时间（教师布置小组任务后）
地点: 教室（主教学区）
触发者: 学生
对话范围: 中范围（所在象限/小组区域）

教师: "现在进行小组讨论，每组讨论5分钟"
    ↓ 大范围广播
学生移动到各自小组区域（中范围）
    ↓
学生A（小组1）: "我觉得这个问题..."
    ↓ 中范围广播（仅小组1成员收到）
小组1成员B: "我同意，但是..."
小组1成员C: "我有不同看法..."
    ↓
小组2成员X: （未收到小组1的讨论，正在进行自己的讨论）
```

**场景3: 课间私语（小范围）**
```
时间: 课间休息
地点: 走廊
触发者: 学生
对话范围: 小范围（贴身）

学生A看到学生B
    ↓
学生A移动到学生B的小范围内
    ↓
学生A: "我跟你说个秘密..."
    ↓ 小范围广播（仅学生B收到）
学生B: "真的吗？我也告诉你..."
    ↓
附近的学生C、D: （未听到对话，继续自己的活动）
```

**场景4: 食堂偶遇（中范围）**
```
时间: 午休时间
地点: 食堂
触发者: 任意学生
对话范围: 中范围（食堂的某个象限）

学生A在食堂取餐（食堂左上象限）
    ↓
学生B也来到同一象限取餐
    ↓
学生A（基于情感关系+概率）: "嗨，你也来这里吃饭？"
    ↓ 中范围广播
学生B（认识学生A）: "是啊，今天的菜看起来不错"
同一象限的学生C（听到对话，但不认识）: （继续吃饭，不加入）
其他象限的学生X、Y、Z: （未收到广播）
```

#### 8. 对话行为与内容分离机制

**核心设计**: 对话"行为"在整个子场景广播，对话"内容"仅在范围内可见

```gdscript
# 对话消息结构
class DialogueMessage:
    var speaker: Agent                    # 发言者
    var range_type: int                   # 范围类型（大/中/小）
    var range_id: String                  # 范围标识（如"教室_左上象限"）
    var behavior_summary: String          # 行为摘要（全子场景可见）
    var full_content: String              # 完整内容（仅范围内可见）
    var timestamp: float                  # 时间戳
    var topic_id: String                  # 话题ID

# 发送对话
func broadcast_dialogue(speaker: Agent, content: String, range_type: int):
    var message = DialogueMessage.new()
    message.speaker = speaker
    message.range_type = range_type
    message.range_id = get_current_range_id(speaker, range_type)
    message.full_content = content
    message.timestamp = Time.get_time_dict_from_system()
    message.topic_id = current_topic_id
    
    # 生成行为摘要（不含具体内容）
    message.behavior_summary = generate_behavior_summary(speaker, range_type)
    # 例如: "学生A正在与小组成员讨论" / "教师正在讲课"
    
    # 1. 向整个子场景广播行为摘要
    for agent in get_agents_in_same_room(speaker):
        agent.receive_dialogue_behavior(message)
    
    # 2. 向范围内Agent广播完整内容
    for agent in get_agents_in_range(speaker, range_type):
        agent.receive_dialogue_content(message)

# 生成行为摘要（保护隐私的抽象描述）
func generate_behavior_summary(speaker: Agent, range_type: int) -> String:
    var range_desc = ""
    match range_type:
        VOICE_RANGE_LARGE: range_desc = "正在对大家说话"
        VOICE_RANGE_MEDIUM: range_desc = "正在与附近的人交谈"
        VOICE_RANGE_SMALL: range_desc = "正在与身边的人私语"
    
    return f"{speaker.name}{range_desc}"
```

**感知层级**:

| 信息层级 | 可见范围 | 内容 | 用途 |
|---------|---------|------|------|
| **行为层** | 整个子场景 | "学生A正在与小组成员讨论" | 感知社交活动，决定是否靠近 |
| **内容层** | 仅对话范围内 | "我觉得这个问题应该..." | 实际对话内容，参与讨论 |

**典型场景示例**:

**场景: 教师监控课堂**
```
时间: 上课时间
地点: 教室（主教学区）
教师: 正在讲课（大范围）

教师视角:
    ├─ [大范围内容] "所以这道题的解法是..."
    ├─ [行为感知] 学生A正在与附近的人交谈 ⚠️
    ├─ [行为感知] 学生B正在认真听讲 ✓
    └─ [行为感知] 学生C和D正在私语 ⚠️

教师决策:
    选项1: 继续讲课（忽略）
    选项2: 大范围警告: "请安静听讲"
    选项3: 走到学生A的中范围，小范围制止: "专心听讲"
    选项4: 走到学生C/D的小范围，直接对话

学生A视角:
    ├─ [听到] 教师讲课内容（大范围）
    ├─ [听到] 同桌B的提问（中范围）
    └─ [未听到] 后排C/D的私语（不在范围内）
```

**场景: 课间社交感知**
```
时间: 课间休息
地点: 走廊
学生A: 独自在走廊

学生A感知到的行为:
    ├─ [走廊左侧] 学生B、C正在交谈
    ├─ [走廊右侧] 学生D正在独自走路
    └─ [小走廊] 教师正在与学生E私语

学生A决策:
    选项1: 走向B/C，进入他们的中范围加入对话
    选项2: 走向D，发起新对话
    选项3: 避开教师，选择其他路线
    选项4: 继续独自待着
```

**AI Agent决策逻辑**:

```gdscript
func process_perceived_behaviors(behaviors: Array[DialogueMessage]):
    for behavior in behaviors:
        # 1. 判断是否感兴趣
        var interest_level = calculate_interest(behavior)
        
        # 2. 判断是否可以加入
        var can_join = can_enter_range(behavior.speaker, behavior.range_type)
        
        # 3. 决策
        if interest_level > INTEREST_THRESHOLD and can_join:
            # 有兴趣且能加入 → 移动到对应范围
            move_to_range(behavior.speaker, behavior.range_type)
        elif behavior.speaker.is_teacher and behavior.range_type == VOICE_RANGE_LARGE:
            # 教师在大范围讲话 → 注意听讲
            focus_on_teacher(behavior.speaker)
        elif is_friend(behavior.speaker) and behavior.range_type == VOICE_RANGE_SMALL:
            # 朋友在私语但不包括我 → 可能感到被排斥
            update_emotion("excluded", -0.1)

func teacher_intervention_decision(behaviors: Array[DialogueMessage]):
    for behavior in behaviors:
        if behavior.speaker.is_student and behavior.range_type != VOICE_RANGE_LARGE:
            # 发现学生在私下交谈
            if is_class_time():
                # 上课时间 → 选择干预方式
                var options = [
                    {"action": "ignore", "priority": 10},
                    {"action": "large_range_warning", "priority": 30},
                    {"action": "move_to_medium_range", "priority": 50},
                    {"action": "move_to_small_range", "priority": 70}
                ]
                
                # 基于学生历史行为、当前课程重要性等选择
                var chosen = select_action(options)
                execute_intervention(chosen, behavior.speaker)
```

**优势**:

1. **隐私保护**: 不在范围内的Agent只能看到"有人在说话"，听不到内容
2. **社交感知**: Agent可以感知周围的社交活动，做出靠近/远离决策
3. **教师权威**: 教师可以监控整个教室，选择适当的干预方式
4. **情感模拟**: 看到朋友私语但不包括自己，可能产生被排斥感
5. **自然行为**: 模拟真实世界中"看到有人在聊天但听不到说什么"的体验

#### 9. 多人同时发言处理机制

**问题**: 同一中范围内，多个Agent同时想要发言怎么办？

**方案: 话题队列 + 打断机制**

```gdscript
# 中范围对话管理器
class MediumRangeConversationManager:
    var topic_queue: Array[Topic] = []  # 话题队列
    var current_topic: Topic = null     # 当前进行中的话题
    var last_speaker: Agent = null      # 最后发言者
    var silence_timer: float = 0.0      # 沉默计时器
    
    const SILENCE_THRESHOLD = 3.0       # 3秒沉默视为话题结束
    const MAX_TOPIC_TIME = 30.0         # 单个话题最长30秒
    
    func process_speak_request(agent: Agent, content: String, priority: float) -> bool:
        # 计算发言优先级
        var final_priority = calculate_priority(agent, priority)
        
        if current_topic == null:
            # 当前没有话题，直接开始新话题
            start_new_topic(agent, content)
            return true
        elif can_interrupt(agent, final_priority):
            # 可以打断当前话题
            interrupt_current_topic(agent, content)
            return true
        else:
            # 加入话题队列
            topic_queue.append(Topic.new(agent, content, final_priority))
            return false
    
    func calculate_priority(agent: Agent, base_priority: float) -> float:
        var priority = base_priority
        
        # 教师优先级加成
        if agent.is_teacher:
            priority += 100.0
        
        # 最后发言者优先级降低（避免一人垄断）
        if agent == last_speaker:
            priority -= 20.0
        
        # 外向性格加成
        priority += agent.personality.extraversion * 10.0
        
        # 情感关系加成（对当前话题相关者的情感）
        if current_topic:
            var relationship = agent.get_relationship(current_topic.initiator)
            priority += relationship.intensity * 5.0
        
        return priority
    
    func can_interrupt(agent: Agent, priority: float) -> bool:
        # 教师可以随时打断
        if agent.is_teacher and not current_topic.speaker.is_teacher:
            return true
        
        # 优先级显著高于当前发言者
        if priority > current_topic.current_priority + 30.0:
            return true
        
        # 当前话题已持续很长时间
        if current_topic.duration > MAX_TOPIC_TIME:
            return true
        
        return false
    
    func _process(delta):
        # 更新沉默计时器
        if current_topic:
            silence_timer += delta
            current_topic.duration += delta
            
            # 检查话题是否应该结束
            if silence_timer > SILENCE_THRESHOLD or current_topic.duration > MAX_TOPIC_TIME:
                end_current_topic()
        
        # 从队列中选取下一个发言者
        if current_topic == null and not topic_queue.is_empty():
            topic_queue.sort_custom(func(a, b): return a.priority > b.priority)
            var next_topic = topic_queue.pop_front()
            start_new_topic(next_topic.agent, next_topic.content)
```

**优先级计算因素**:

| 因素 | 影响 | 说明 |
|------|------|------|
| 身份 | +100（教师） | 教师拥有最高发言权 |
| 连续发言 | -20 | 避免同一人垄断对话 |
| 外向性格 | +0~10 | 外向者更愿意发言 |
| 情感关系 | +0~5 | 与话题相关者的情感强度 |
| 基础优先级 | 基础值 | 由AI决策时计算 |

**打断规则**:

1. **教师特权**: 教师可以随时打断学生的发言
2. **显著优先**: 优先级高出30以上可以打断
3. **超时打断**: 当前话题超过30秒可以被中断

**话题结束条件**:

1. **自然结束**: 3秒内无人继续发言
2. **超时结束**: 单个话题持续超过30秒
3. **强制结束**: 教师发言自动结束当前话题

**示例场景**:

```
场景: 小组讨论（中范围）
成员: 学生A、B、C、D

学生A: "我认为这个问题应该..."（开始话题T1）
    ↓
学生B（同时）: "我觉得..."（优先级较低，进入队列）
学生C（同时）: "等等，我有不同看法！"（优先级较高，打断成功）
    ↓
学生C: "我觉得我们应该从另一个角度..."（话题T1，发言者变为C）
    ↓
2秒后...
学生D: "我同意C的观点..."（继续话题T1）
    ↓
3秒沉默...
    ↓
话题T1结束，从队列中取出学生B的发言
    ↓
学生B: "刚才我想说..."（开始话题T2）
```

---

## 三、情感关系系统（新增）⏳

### 设计目标
建立Agent之间的双向情感关系，影响对话触发和互动方式。

### 数据结构

```gdscript
# 情感关系类型
enum RelationshipType {
    FRIENDSHIP,      # 友情
    ROMANTIC_LOVE,   # 爱情
    RESPECT,         # 敬爱/尊敬
    TRUST,           # 信任
    RIVALRY,         # 竞争/敌意
    INDIFFERENCE     # 无感/陌生
}

# 情感关系结构（存储在character_data["relationships"]中）
{
    "AgentB": {
        "type": RelationshipType,
        "intensity": 0.0-1.0,      # 情感强度
        "history": "交集历史摘要",  # 关键事件记录
        "last_updated": 时间戳
    }
}
```

### 集成到每日反思系统

**新增步骤8：情感关系评估**

```gdscript
static func _evaluate_relationships(character: Node, daily_memories: Array) -> Dictionary:
    # 1. 从记忆中提取今天接触过的Agent
    var contacted_agents = _extract_contacted_agents(daily_memories)
    
    # 2. 对每个接触的Agent进行情感评估（LLM）
    for agent_name in contacted_agents:
        var relationship = await _assess_relationship_with_agent(...)
        _update_relationship(character, agent_name, relationship)
```

**情感评估Prompt**:
```
【你今天与{AgentB}的互动】
- 互动场景：...
- 互动内容：...
- 你的感受：...

请评估你对{AgentB}的情感：
1. 情感类型（友情/爱情/敬爱/信任/竞争/无感）
2. 情感强度（0-100%）
3. 简要理由

以JSON格式输出：
{"type": "...", "intensity": 0-100, "reason": "..."}
```

### 在对话系统中的使用

当Agent收到对话广播时：
```gdscript
var relationship = get_relationship(character, speaker_name)

# 影响回复决策：
- 情感类型（是否愿意搭理对方）
- 情感强度（回复的积极程度）
- 结合当前心情、任务状态、性格
```

---

## 四、Prompt设计原则更新 ⏳

### 严格信息隔离
```
Agent A 的 Prompt：
✅ 包含Agent A自己的完整信息（性格、心理特质、记忆、情感）
✅ 其他Agent：仅名字 + 职业
❌ 不包含其他Agent的心理特质、记忆、情感等私人信息
```

### 对话Prompt结构
1. **自己的完整人设**（性格、心理特质、当前状态）
2. **自己的记忆**（相关经历）
3. **自己的情感关系**（对发言者的感觉）
4. **当前情境**（在哪里、在做什么）
5. **接收到的对话内容**
6. **发言者信息**（名字、职业）
7. **决策指导**（是否回复、如何回复）

---

## 五、待讨论问题

### 对话系统
- [x] 如何决定使用哪种声音范围？→ **基于子场景类型和Agent意图**
- [x] Agent能否主动切换？→ **可以，教师可切换，学生可切换中/小范围**
- [x] 多人同时回复如何处理？→ **话题队列 + 打断机制**
- [ ] 是否需要对话ID或话题追踪？→ **是，需要话题ID和发言队列**
- [ ] 对话的"热度"如何衰减？（避免无限对话）
- [ ] 中范围分区算法实现（4象限/左右分区/整个区域）

### 情感系统
- [ ] 情感随时间衰减的机制？（长期不联系会淡化吗？）
- [ ] 情感是否有上限/下限？（如极度厌恶某人）
- [ ] 是否需要情感冲突处理？（如又爱又恨）
- [ ] 情感是否影响其他行为（如任务选择、移动路径）？

### 记忆系统
- [ ] 情感关系是否作为独立记忆类型？
- [ ] 如何快速检索与某人的所有互动历史？
- [ ] 记忆压缩：长期记忆如何简化为"情感印象"？

---

## 六、实施优先级

| 优先级 | 任务 | 预估工作量 |
|--------|------|-----------|
| P0 | 情感关系系统基础实现 | 2-3小时 |
| P0 | 集成到DailyReflectionSystem | 1-2小时 |
| P1 | 对话系统广播机制 | 3-4小时 |
| P1 | 三种声音范围实现（与场景集成） | 3-4小时 |
| P2 | 中范围分区算法 | 2小时 |
| P2 | 对话触发概率系统 | 2-3小时 |
| P2 | Prompt重构（信息隔离） | 2小时 |
| P3 | 多人回复处理机制 | 2-3小时 |
| P3 | 情感衰减机制 | 1-2小时 |

---

## 七、相关文件

| 文件 | 路径 | 状态 |
|------|------|------|
| TaskManager | `script/system/TaskManager.gd` | ✅ 已重构 |
| AIAgent | `script/ai/AIAgent.gd` | ✅ 已修改 |
| DailyReflectionSystem | `script/ai/DailyReflectionSystem.gd` | ⏳ 待添加情感评估 |
| ConversationManager | `script/ai/ConversationManager.gd` | ⏳ 待重写 |
| DialogManager | `script/ai/DialogManager.gd` | ⏳ 待重写 |
| DialogService | `script/ai/DialogService.gd` | ⏳ 待重写 |
| MemoryManager | `script/ai/memory/MemoryManager.gd` | ⏳ 待添加情感关系存储 |

---

## 八、参考文档

- [原对话系统设计](#) - 1对1对话实现
- [PROJECT_STRUCTURE.md](./PROJECT_STRUCTURE.md) - 项目结构
- [IMPLEMENTATION_LOGIC.md](./IMPLEMENTATION_LOGIC.md) - 实现逻辑

---

*最后更新：2026-04-06 13:55*
*维护者：百舟楫*

## 九、设计变更记录

### 2026-04-06 对话系统与场景集成设计更新
- **大范围**: 整个子场景（仅教室和讨论室可用）
- **中范围**: 子场景内分区（4象限/左右分区/整个区域）
- **小范围**: 以Agent为中心的圆形贴身范围
- **感知机制**: 保留子场景级感知，对话需进入对应范围
- **权限控制**: 大范围仅限教师使用
