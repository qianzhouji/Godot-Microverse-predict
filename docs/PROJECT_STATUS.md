# 项目进度与重构总结

> **项目**: Godot-Microverse-predict 抑郁风险学生模拟系统
> **仓库**: https://github.com/qianzhouji/Godot-Microverse-predict
> **重构时间**: 2026-04-06 至 2026-04-07
> **最后更新**: 2026-04-07

---

## 目录

1. [重构背景](#重构背景)
2. [架构变革](#架构变革)
3. [已完成工作](#已完成工作)
4. [待完成工作](#待完成工作)
5. [当前进度](#当前进度)
6. [下一步计划](#下一步计划)

---

## 重构背景

原系统采用传统的1对1对话系统和随机任务生成，缺乏统一的时序管理和精确的对话范围控制。新架构引入中央时序系统、中范围划分和广播式对话，实现更真实的学校场景模拟。

### 原架构 vs 新架构

| 方面 | 原架构 | 新架构 |
|------|--------|--------|
| 时序管理 | 各Agent独立定时器 | 中央时序系统（5分钟Click周期） |
| 对话系统 | 1对1直接对话 | 广播式对话（行为/内容分离） |
| 空间感知 | 距离阈值判断 | 中范围划分（4象限/左右/单区） |
| 任务生成 | 随机生成 | 课程表驱动 |
| Prompt管理 | 硬编码在代码中 | 配置文件+模板分离 |

---

## 已完成工作

### 第一阶段：中央时序系统（100%完成）

| 组件 | 文件 | 状态 |
|------|------|------|
| 时序系统核心 | `script/system/TimingSystem.gd` | ✅ 完成 |
| 时间轴状态 | `script/system/TimelineState.gd` | ✅ 完成 |
| 行动请求 | `script/data/ActionRequest.gd` | ✅ 完成 |
| 场景集成 | `scene/maps/School.tscn` | ✅ 已添加节点 |

**功能**:
- 5分钟游戏时间一个Click周期
- 上升沿触发所有Agent活动
- 请求缓存与批准执行
- 17:00放学阶段，17:30强制结束
- 课程表管理（6节课）

#### 课程表

| 时间 | 活动 | 位置 | 类型 |
|------|------|------|------|
| 8:00 | 班主任课 | 教室（主教学区） | class |
| 8:55 | 英语课 | 教室（主教学区） | class |
| 9:50 | 小组讨论 | 教室（小组讨论区） | discussion |
| 10:45 | 午休 | 食堂 | break |
| 11:45 | 数学课 | 教室（主教学区） | class |
| 12:40 | 体育活动 | 体育馆 | activity |

---

### 第二阶段：AIAgent核心重构（95%完成）

| 组件 | 文件 | 状态 |
|------|------|------|
| AIAgent核心 | `script/ai/AIAgent.gd` | ✅ 完成框架 |
| Prompt构建器 | `script/ai/PromptBuilder.gd` | ✅ 完成 |
| Prompt模板 | `prompts/*.txt` | ✅ 完成 |
| 原AIAgent备份 | `script/ai/AIAgent_backup_20250406.gd` | ✅ 已备份 |

**已完成**:
- 清理旧代码（定时器、旧任务系统、旧对话系统）
- 保留核心组件（reward_receiver、场景描述工具函数）
- 新增认知循环（感知→体验→决策→执行）
- 8个行动执行方法框架
- 本地LLM API调用（Ollama）
- 两步缓存验证机制
- 使用CharacterController.move_to()移动

**待完善**:
- 从备份文件复制保留的工具函数实现
- 填充场景描述生成函数的完整逻辑
- 测试和调试

#### 认知循环（4阶段）

```
感知(Perceiving) → 体验(Experiencing) → 决策(Deciding) → 执行(Executing)
     │                    │                    │                  │
     ▼                    ▼                    ▼                  ▼
收集场景信息        贝叶斯更新信念       生成ActionRequest    在Click时刻执行
```

#### Agent状态（8种）

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

#### 行动类型（10种）

```gdscript
enum ActionType {
    MOVE_TO_RANGE,      # 移动（编号1）
    START_DIALOGUE,     # 开始普通对话
    START_WHISPER,      # 开始悄悄话
    JOIN_DIALOGUE,      # 加入对话
    EXIT_DIALOGUE,      # 退出对话
    START_SPORTS,       # 开始体育活动
    END_SPORTS,         # 结束体育活动
    START_STUDY,        # 开始自习
    END_STUDY,          # 结束自习
    WAIT                # 等待
}
```

#### 中范围划分系统

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

---

### 第三阶段：Prompt系统（100%完成）

| 组件 | 文件 | 状态 |
|------|------|------|
| 决策Prompt模板 | `prompts/decision_prompt_template.txt` | ✅ 完成 |
| 对话回复模板 | `prompts/dialogue_reply_template.txt` | ✅ 完成 |
| Prompt构建器 | `script/ai/PromptBuilder.gd` | ✅ 完成 |

**功能**:
- 模板与代码分离
- 变量自动填充
- 支持热更新
- 详细的决策示例和说明

---

### 第四阶段：感知层分离（100%完成）

| 系统 | 文件 | 说明 |
|------|------|------|
| 奖赏系统 | `RewardSystem.gd` | 系统层奖赏发放 |
| 奖赏接收 | `AgentRewardReceiver.gd` | 感知层接收 |
| 感知系统 | `PerceptionSystem.gd` | 贝叶斯感知 |

---

### 保留的系统（无需修改）

| 系统 | 文件 | 说明 |
|------|------|------|
| 感知系统 | `PerceptionSystem.gd` | 贝叶斯感知 |
| 奖赏接收 | `AgentRewardReceiver.gd` | 接收系统层奖赏 |
| 记忆管理 | `MemoryManager.gd` | 记忆存储与检索 |
| 每日反思 | `DailyReflectionSystem.gd` | 日终反思 |
| 动态人格 | `DynamicPersonality.gd` | 人格动态变化 |
| 角色控制 | `CharacterController.gd` | 移动控制（原项目）|

---

### 舍弃的旧系统

| 旧系统 | 文件 | 替代方案 |
|--------|------|---------|
| 旧任务系统 | TaskManager.gd（原） | TimelineState + 新课程表驱动 |
| 1对1对话 | ConversationManager.gd | 广播式DialogueManager（待实现）|
| 旧对话管理 | DialogManager.gd, DialogService.gd | 新DialogueManager（待实现）|
| 随机移动 | 旧移动逻辑 | 精准路径+中范围划分 |

---

## 待完成工作

### 高优先级（下一步）

#### 1. 填充AIAgent工具函数（2-3小时）

从备份文件复制以下函数到新的AIAgent.gd：

```gdscript
# 场景描述生成
func generate_scene_description() -> String
func get_environment_info() -> String
func get_character_status_info() -> String
func get_room_objects() -> Array
func get_room_characters() -> Array

# 移动辅助
func _get_room_entrance_position() -> Vector2
func _start_arrival_tracking()

# 其他工具
func _get_direction_description() -> String
func _find_target_by_name() -> Node
func _choose_random_target() -> Dictionary
```

#### 2. 实现缺失的系统（4-6小时）

| 系统 | 文件 | 说明 |
|------|------|------|
| ActivityManager | `script/system/ActivityManager.gd` | 活动管理与奖赏计算 |
| DialogueManager | `script/ai/DialogueManager.gd` | 对话生命周期管理 |
| PriorityQueue | `script/ai/PriorityQueue.gd` | 发言优先级队列 |

#### 3. 集成测试（2-3小时）

- 启动时序系统
- 验证Click触发
- 测试Agent认知循环
- 测试移动功能
- 测试对话功能

---

### 中优先级

#### 4. 情感关系系统（3-4小时）

- 情感类型定义（FRIENDSHIP/ROMANTIC_LOVE/RESPECT/TRUST/RIVALRY/INDIFFERENCE）
- DailyReflectionSystem集成
- 情感影响决策

#### 5. 对话系统完善（4-5小时）

- 行为与内容分离
- 中范围对话管理
- 大范围对话（教师提问）
- 发言优先级队列

#### 6. UI和调试工具（2-3小时）

- 时序系统状态面板
- Agent状态实时监控
- 对话状态监控

---

### 低优先级

#### 7. 性能优化（2-3小时）

- API调用批处理
- 决策缓存机制
- 并发处理优化

#### 8. 文档完善（1-2小时）

- API文档
- 使用手册
- 架构图更新

---

## 当前进度

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

---

## 下一步计划

### 推荐顺序

1. **选项A：填充工具函数**（2-3小时）
   - 从备份复制工具函数，使AIAgent能完整运行
   - 收益：可以开始测试基础功能

2. **选项B：实现ActivityManager**（2-3小时）
   - 创建活动管理系统，计算和发放奖赏
   - 收益：完成体验闭环

3. **选项C：实现DialogueManager**（3-4小时）
   - 创建对话管理系统，支持对话生命周期
   - 收益：可以测试对话功能

### 建议执行顺序

**先完成选项A（填充工具函数），然后选项B（ActivityManager）**

**原因**:
1. 工具函数是AIAgent正常运行的基础
2. ActivityManager完成体验闭环，可以测试完整循环
3. 然后再实现DialogueManager，添加对话功能

---

## 关键设计决策

### 1. 时序系统
- **5分钟Click周期**: 平衡实时性和计算开销
- **上升沿触发**: 所有Agent同步执行，避免竞态条件
- **请求缓存**: 决策和执行分离，支持复杂计划

### 2. 对话系统
- **行为/内容分离**: 行为全子场景可见，内容仅范围内可见
- **三层范围**: 大范围（教师）、中范围（4象限/左右）、小范围（贴身）
- **悄悄话机制**: 必须贴身，私密性强

### 3. 移动系统
- **精准定位**: 中范围中心+随机偏移
- **智能判断**: 自动识别场景名vs角色名
- **距离自适应**: 同一中范围贴身，不同中范围到中心

### 4. Prompt管理
- **模板分离**: 配置文件+代码分离，支持热更新
- **详细说明**: 中范围规则、输出格式、决策示例
- **场景感知**: 完整的环境描述，包括中范围信息

---

## 技术栈

| 组件 | 技术 |
|------|------|
| 游戏引擎 | Godot 4.x |
| 编程语言 | GDScript |
| AI模型 | Ollama本地服务 (qwen2.5:14b) |
| API端点 | http://localhost:11434/api/generate |
| 版本控制 | Git + GitHub |

---

## 项目结构

```
/Users/yuke/Desktop/Godot Microverse/Microverse/
├── script/
│   ├── ai/
│   │   ├── AIAgent.gd                    # Agent核心（重构后）
│   │   ├── AIAgent_backup_20250406.gd    # 原AIAgent备份
│   │   ├── PerceptionSystem.gd           # 感知系统（保留）
│   │   ├── AgentRewardReceiver.gd        # 奖赏接收（保留）
│   │   ├── PromptBuilder.gd              # Prompt构建器
│   │   ├── memory/
│   │   │   └── MemoryManager.gd          # 记忆管理（保留）
│   │   └── ...
│   ├── system/
│   │   ├── TimingSystem.gd               # 时序系统（新增）
│   │   └── TimelineState.gd              # 时间轴状态（新增）
│   ├── data/
│   │   └── ActionRequest.gd              # 行动请求（新增）
│   ├── CharacterController.gd            # 角色控制（保留）
│   └── ...
├── prompts/
│   ├── decision_prompt_template.txt      # 决策Prompt（新增）
│   ├── dialogue_reply_template.txt       # 对话Prompt（新增）
│   └── fragments/                        # Prompt片段
├── scene/
│   ├── maps/School.tscn                  # 主场景
│   └── characters/                       # 角色场景
├── docs/                                 # 文档目录
└── TODOLIST.md                           # 任务清单
```

---

*本文档合并了以下历史文档*:
- Progress_Report.md
- Refactoring_Summary.md

*维护者：百舟楫*
