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
- [ ] 多人同时回复如何处理？并行还是串行？
- [ ] 是否需要对话ID或话题追踪？
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
