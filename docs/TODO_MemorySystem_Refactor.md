# 记忆系统改造 TodoList

## 项目概述

对现有 MemoryManager 进行重构，实现分层存储（短期+长期）、持久化保存、与V2系统深度集成，同时保持向后兼容性。

---

## 阶段一：准备工作（保持兼容）

### 1.1 修复现有 Bug
- [ ] 修复 DailyReflectionSystem.gd:96 `get_memories()` → `get_character_memories()`
- [ ] 修复 ConversationManager.gd:336 `MemoryManager.new()` → 直接使用 `MemoryManager` 单例
- [ ] 测试现有功能是否正常工作

### 1.2 备份现有系统
- [ ] 备份 `script/ai/memory/MemoryManager.gd` 到 `script/ai/memory/MemoryManager_backup.gd`
- [ ] 记录所有使用 MemoryManager 的调用点
- [ ] 创建兼容性测试用例

---

## 阶段二：核心架构实现

### 2.1 创建新文件结构
```
script/ai/memory/
├── MemorySystem.gd          # 新的主系统（替换 MemoryManager）
├── EventMemory.gd           # 事件记忆管理
├── SocialMemory.gd          # 社交记忆管理
├── EmotionMemory.gd         # 情感记忆管理
├── MemoryFormatter.gd       # Prompt格式化工具
└── MemoryPersistence.gd     # 持久化存储
```

### 2.2 MemorySystem.gd - 主系统
**必须保持兼容的接口：**
- [ ] `get_character_memories(character: Node) -> Array`
- [ ] `add_memory(character: Node, content: String, memory_type: MemoryType, importance: MemoryImportance)`
- [ ] `get_formatted_memories_for_prompt(character: Node, max_count: int = -1) -> String`
- [ ] `_format_memory_for_display(memory: Dictionary) -> String`
- [ ] 枚举 `MemoryType` 和 `MemoryImportance`

**新增接口：**
- [ ] `record_event(agent_id: String, event_type: String, details: Dictionary)`
- [ ] `record_interaction(agent_a: String, agent_b: String, interaction_type: String, context: Dictionary)`
- [ ] `update_emotion(agent_id: String, target: String, emotion_type: String, delta: float)`
- [ ] `get_recent_events(agent_id: String, game_hours: float) -> Array`
- [ ] `get_relationship_summary(agent_a: String, agent_b: String) -> Dictionary`
- [ ] `save_to_disk()` - 保存到文件
- [ ] `load_from_disk()` - 从文件加载
- [ ] `migrate_from_old_format()` - 从旧格式迁移

### 2.3 EventMemory.gd - 事件记忆
- [ ] 定义事件数据结构
- [ ] 实现事件记录接口
- [ ] 实现按时间范围查询
- [ ] 实现按事件类型查询
- [ ] 实现事件重要性自动评估

### 2.4 SocialMemory.gd - 社交记忆
- [ ] 定义社交关系数据结构
- [ ] 实现互动记录（对话、悄悄话、共同活动等）
- [ ] 实现关系分数计算（-1.0 ~ 1.0）
- [ ] 实现关系摘要生成（用于AI Prompt）
- [ ] 实现最近互动历史查询

### 2.5 EmotionMemory.gd - 情感记忆
- [ ] 定义情感数据结构（好感、信任、尊重等维度）
- [ ] 实现情感值更新（带衰减机制）
- [ ] 实现主导情感计算
- [ ] 实现情感变化记录

### 2.6 MemoryFormatter.gd - 格式化工具
- [ ] 实现事件记忆格式化（用于Prompt）
- [ ] 实现社交记忆格式化
- [ ] 实现情感记忆格式化
- [ ] 实现综合记忆摘要生成

### 2.7 MemoryPersistence.gd - 持久化存储
- [ ] 定义文件存储格式（JSON）
- [ ] 实现保存功能
- [ ] 实现加载功能
- [ ] 实现版本兼容性检查
- [ ] 实现自动备份机制

---

## 阶段三：V2系统集成

### 3.1 TimingSystem 集成
- [ ] 监听 `click_triggered` 信号
- [ ] 每个 CLICK 结束时自动记录关键事件
- [ ] 实现事件去重（避免重复记录）

### 3.2 AIAgent 集成
- [ ] 决策前自动检索相关记忆
- [ ] 活动执行后自动记录事件
- [ ] 对话结束后自动记录社交互动

### 3.3 ActivityCoordinator 集成
- [ ] 监听活动分配完成信号
- [ ] 记录 Agent 之间的互动（如共同活动）

### 3.4 DialogueManager 集成（未来）
- [ ] 对话开始时记录上下文
- [ ] 对话结束时记录内容和结果
- [ ] 记录对话对关系的影响

---

## 阶段四：数据迁移与测试

### 4.1 数据迁移
- [ ] 实现旧格式到新格式的转换
- [ ] 测试迁移后的数据完整性
- [ ] 保留旧数据备份

### 4.2 兼容性测试
- [ ] 测试 GodUI 的所有记忆相关功能
- [ ] 测试 AIAgent 的记忆获取和添加
- [ ] 测试 DailyReflectionSystem
- [ ] 测试 ConversationManager
- [ ] 测试 DynamicPersonality

### 4.3 性能测试
- [ ] 测试大量记忆时的加载速度
- [ ] 测试保存/加载性能
- [ ] 测试内存占用

---

## 阶段五：优化与文档

### 5.1 性能优化
- [ ] 实现记忆缓存机制
- [ ] 优化频繁查询的索引
- [ ] 实现异步保存（避免卡顿）

### 5.2 调试工具
- [ ] 添加记忆系统调试面板（GodUI）
- [ ] 实现记忆查看器
- [ ] 添加手动编辑记忆功能

### 5.3 文档更新
- [ ] 更新 API 文档
- [ ] 添加使用示例
- [ ] 添加架构说明文档

---

## 数据结构定义

### 事件记忆 (EventMemory)
```gdscript
{
    "id": "uuid",
    "timestamp": "2024-04-09 14:30",      # 游戏时间
    "real_timestamp": 1712649000,          # 现实时间戳
    "agent_id": "StudentXiaoming",
    "event_type": "MOVE_TO",               # MOVE_TO, DIALOGUE, CLASS, etc.
    "location": "图书馆",
    "details": {
        "from": "教室",
        "to": "图书馆",
        "duration": 5.0,                   # 游戏分钟
        "participants": ["StudentXiaohong"],
        "topic": "数学讨论",               # 如果有
        "result": "success"                # 活动结果
    },
    "emotional_valence": 0.2,              # -1.0 ~ 1.0
    "importance": 3                        # 1, 3, 5, 10
}
```

### 社交记忆 (SocialMemory)
```gdscript
{
    "agent_a": "StudentXiaoming",
    "agent_b": "StudentXiaohong",
    "total_interactions": 15,
    "relationship_score": 0.6,             # -1.0 ~ 1.0
    "last_interaction": "2024-04-09 14:30",
    "interaction_history": [
        {
            "type": "DIALOGUE",
            "topic": "数学",
            "time": "2024-04-09 14:30",
            "duration": 10.0,
            "emotional_impact": 0.1
        }
    ],
    "emotions": {
        "好感": 0.5,
        "信任": 0.3,
        "尊重": 0.4
    }
}
```

### 情感记忆 (EmotionMemory)
```gdscript
{
    "agent_id": "StudentXiaoming",
    "target": "StudentXiaohong",           # 可以是角色、地点、活动类型
    "target_type": "AGENT",                # AGENT, LOCATION, ACTIVITY_TYPE
    "emotions": {
        "好感": 0.5,
        "信任": 0.3,
        "尊重": 0.4,
        "恐惧": 0.0,
        "厌恶": 0.0
    },
    "dominant_emotion": "好感",
    "last_updated": "2024-04-09 14:30",
    "history": [
        {"timestamp": "...", "emotions": {...}, "trigger_event": "..."}
    ]
}
```

---

## 文件存储格式

```
user://memory/
├── global_memory.json           # 全局记忆配置
├── agents/
│   ├── StudentXiaoming.json     # 每个Agent的记忆
│   ├── StudentXiaohong.json
│   └── ...
└── relationships/
    ├── StudentXiaoming_StudentXiaohong.json
    └── ...
```

---

## 注意事项

1. **向后兼容性**：所有现有接口必须保持行为一致
2. **性能考虑**：记忆数量可能很大，需要高效的查询和存储
3. **数据安全**：定期自动备份，避免数据丢失
4. **调试友好**：提供丰富的调试信息和工具
5. **扩展性**：预留接口供未来系统使用

---

## 时间估计

- 阶段一：1-2 小时
- 阶段二：4-6 小时
- 阶段三：2-3 小时
- 阶段四：2-3 小时
- 阶段五：2-3 小时

**总计：约 12-18 小时**

---

_创建时间：2024-04-09_
_最后更新：2024-04-09_
