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

## 二、对话系统重构（广播式对话）⏳

### 设计目标
从1对1结构化对话转向更自然的广播式社交，Agent在特定范围内听到对话，自主决定是否参与。

### 核心设计

#### 1. 广播机制
```
Agent A 发言
    ↓ 广播到范围内所有Agent
Agent B 收到 → 决定是否回复
Agent C 收到 → 决定是否回复
Agent D 收到 → 决定忽略
```

#### 2. 三种声音范围

| 范围 | 场景 | 大小参考 | 使用方式 |
|------|------|---------|---------|
| **大范围** | 老师上课 | 比教室略大 | 教师主动使用 |
| **中范围** | 小组讨论 | 1/6～1/8教室 | 正常交谈默认 |
| **小范围** | 悄悄话/1v1 | 极近（2-3人贴身） | 私密对话使用 |

#### 3. 触发机制（无任务时）
```
Agent无任务
    ↓
感知中范围内其他Agent
    ↓
综合评估：
  - 当前情境
  - 当前心情
  - 人物间情感关系
  - 记忆
  - 性格（外向/内向）
    ↓
概率触发对话
```

**触发概率设计**:
- 毫无交集 + 心情一般 + 内向 → 极低概率
- 有交集 + 心情好 + 外向 → 较高概率

#### 4. 回复机制
对于接收到对话广播的Agent：
- 基于发言内容、发言者身份、情感关系决定是否回复
- 思考回复内容
- Prompt中只包含自己的信息 + 其他Agent的名字和职业

#### 5. 多人同时回复处理
- 待设计：并行处理还是串行处理
- 待设计：如何管理对话线程

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
- [ ] 如何决定使用哪种声音范围？Agent能否主动切换？
- [ ] 多人同时回复如何处理？并行还是串行？
- [ ] 是否需要对话ID或话题追踪？
- [ ] 对话的"热度"如何衰减？（避免无限对话）

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
| P1 | 三种声音范围实现 | 2小时 |
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

*最后更新：2026-04-06*
*维护者：百舟楫*
