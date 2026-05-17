# Godot-Microverse-predict 完整运行流程与实现逻辑

> **视角**：以学生"小明"（StudentXiaoming）的第一人称视角，带你完整体验整个系统的运行流程
> 
> **文档位置**：`docs/COMPLETE_WORKFLOW.md`

---

## 目录

1. [系统概览](#一系统概览)
2. [启动与初始化](#二启动与初始化)
3. [时间系统：Click周期](#三时间系统click周期)
4. [认知循环：感知→决策→执行](#四认知循环感知决策执行)
5. [活动协调：多Agent协作](#五活动协调多agent协作)
6. [对话系统：社交交互](#六对话系统社交交互)
7. [记忆系统：经验积累](#七记忆系统经验积累)
8. [货币系统：收益与成本](#八货币系统收益与成本)
9. [完整流程示例](#九完整流程示例)

---

## 一、系统概览

### 1.1 我是谁？

我是**StudentXiaoming**，一名初三学生，也是这个模拟系统中的一个AI Agent。我拥有：

- **人格特质**：内向、敏感、缺乏自信，有早期抑郁症状
- **认知参数**：高努力敏感性（β_effort=0.8），低收益敏感性（α=0.55）
- **记忆系统**：记录我的经历、情感和社交关系
- **决策系统**：基于MVT（边际价值定理）决定行为

### 1.2 我在哪里？

我在一个虚拟的学校场景中，包括：
- 教室、图书馆、食堂、体育馆、走廊
- 其他12个角色（学生和老师）
- 中央时序系统管理着整个世界的运行

### 1.3 系统架构（五层）

```
┌─────────────────────────────────────────┐
│  Layer 1: 中央时序系统 (TimingSystem)    │
│  - 全局时钟管理，Click周期触发           │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  Layer 2: 活动管理系统                   │
│  - ActivityCoordinator: LLM协调分配      │
│  - ActivityManager: 活动生命周期         │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  Layer 3: Agent认知与决策 (AIAgent)      │
│  - 感知 → 体验 → 决策 → 执行            │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  Layer 4: 感知与记忆系统                 │
│  - PerceptionSystem: 贝叶斯感知         │
│  - MemorySystem: 自然语言记忆           │
│  - DynamicPersonality: 动态特质         │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  Layer 5: 客观现实系统                   │
│  - RoomArea: 情境参数 (S, a, E)         │
│  - RewardSystem: 收益计算与发放          │
└─────────────────────────────────────────┘
```

---

## 二、启动与初始化

### 2.1 场景加载

当游戏启动时：

1. **School.tscn 场景加载**
   - 加载地图、房间区域、导航网格
   - 实例化12个角色（包括我）
   - 每个角色包含：CharacterBody2D + AIAgent脚本

2. **AutoLoad单例初始化**（按顺序）
   ```
   RoomManager → RewardSystem → APIManager → MemoryManager
   → CharacterManager → TimingSystem → TimelineState
   → ActivityManager → ActivityCoordinator → DialogueManager
   → MemorySystem
   ```

3. **我的初始化**（AIAgent._ready()）
   ```gdscript
   func _ready():
       # 获取父节点（我的角色实体）
       character = get_parent() as CharacterBody2D
       
       # 创建感知层组件
       _create_reward_receiver()
       _create_information_receiver()
       
       # 连接时序系统信号
       _connect_to_timing_system()
       
       # 添加到ai_agents组
       add_to_group("ai_agents")
       
       print("[AIAgent] StudentXiaoming 初始化完成")
   ```

### 2.2 我的初始状态

```
当前位置：教室 (242, 86)
当前时间：8:00（第1天）
心理状态：PHQ-9基线12分（中度抑郁风险）
记忆：空（新的一天开始）
```

---

## 三、时间系统：Click周期

### 3.1 什么是Click？

**Click**是系统的核心时间单位：
- **现实时间**：1分钟 = 1个Click
- **游戏时间**：1个Click = 5分钟
- **时间比例**：1现实秒 = 2.5游戏秒

### 3.2 Click触发流程

当TimingSystem触发Click时：

```
[TimingSystem] ===== CLICK #1 START =====
         ↓
[TimingSystem] 发射 click_triggered 信号
         ↓
[所有AIAgent] 接收信号，开始认知循环
         ↓
[TimingSystem] 等待15秒（决策收集时间）
         ↓
[ActivityCoordinator] 执行协调，分配活动
         ↓
[TimingSystem] ===== CLICK END =====
```

### 3.3 我的Click响应

当我收到Click信号时：

```gdscript
func _on_click_triggered(game_time, day, click_count):
    # 检查是否有缓存活动
    if activity_cache.size() > 0:
        _execute_next_cached_activity()
    elif 正在活动中:
        _perform_activity_update()  # 体验+决策
    else:
        _perform_v2_cognitive_cycle()  # 完整认知循环
```

---

## 四、认知循环：感知→决策→执行

### 4.1 完整认知循环流程

作为小明，我的每个Click周期可能经历以下流程：

```
┌─────────────────────────────────────────┐
│  Step 1: 感知 (PERCEIVING)              │
│  - 获取当前房间、位置                     │
│  - 获取周围可见的其他Agent               │
│  - 获取时间约束（是否上课等）             │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  Step 2: 体验 (EXPERIENCING)             │
│  - 如果上一周期有活动，接收累积收益       │
│  - MVT决策：是否达到最优停留时间          │
│  - 决定继续/停止/更换活动                │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  Step 3: 决策 (DECIDING)                 │
│  - 构建Prompt（人格+状态+环境+记忆）      │
│  - 调用LLM生成自然语言决策               │
│  - 示例："我想去食堂和小红聊天"          │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  Step 4: 提交协调器                       │
│  - submit_decision_to_coordinator()      │
│  - 等待ActivityCoordinator分配活动        │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│  Step 5: 执行 (EXECUTING)                │
│  - 接收分配的活动序列                     │
│  - 执行MOVE_TO、INITIATE_DIALOGUE等       │
│  - 更新状态、记录日志、更新记忆           │
└─────────────────────────────────────────┘
```

### 4.2 感知阶段详解

```gdscript
func _perceive() -> Dictionary:
    var perception = {
        "current_room": "教室A",           # 当前所在房间
        "nearby_agents": [                 # 周围可见的Agent
            {"name": "StudentXiaohong", "distance": 150},
            {"name": "StudentXiaogang", "distance": 200}
        ],
        "dialogue_behaviors": [],          # 观察到的对话行为
        "audible_contents": [],            # 听到的对话内容
        "time_constraints": {              # 时间约束
            "can_leave": true,
            "can_dialogue": true
        }
    }
    return perception
```

### 4.3 体验阶段与MVT决策

当我正在一个活动中（比如在食堂吃饭），每个Click我会：

1. **接收累积收益**：RewardSystem根据停留时间计算收益
   ```
   G(t) = (S/a)[1 - exp(-at)]
   ```

2. **MVT决策**：计算最优停留时间
   ```
   log(T) = log[η_s·S] − log(ρ_base) − β_effort·effort − η_a·log(a) + ε
   ```

3. **决策结果**：
   - 如果当前时间 < 最优时间：继续停留
   - 如果当前时间 ≥ 最优时间：考虑离开

### 4.4 决策阶段：自然语言生成

我构建一个详细的Prompt，包含：
- 我的人设（内向、抑郁风险）
- 当前状态（位置、心情）
- 周围环境（谁在旁边）
- 我的记忆（上次和小红聊天很开心）
- 认知参数（我对努力很敏感）

然后调用LLM生成决策：
```
"我想去食堂，但感觉走那么远好累...不过小红说想和我聊天，
也许我应该去？"
```

---

## 五、活动协调：多Agent协作

### 5.1 ActivityCoordinator的工作

ActivityCoordinator收集所有Agent的决策，然后：

1. **构建输入数据**：每个Agent的位置、决策内容
2. **调用LLM**：让LLM协调分配活动
3. **解析响应**：将JSON转换为Activity对象
4. **下发活动**：每个Agent收到自己的活动序列

### 5.2 对话测试模式

在测试模式下，Prompt被简化为：
```markdown
## 协调规则

**核心任务：让所有角色聚在一起对话**

1. 如果角色不在一起 → 安排他们移动到同一位置
2. 安排**一个**角色发起对话（INITIATE_DIALOGUE）
3. 安排**其他**角色加入对话（JOIN_DIALOGUE）
```

### 5.3 我的活动执行

当我收到分配的活动：

```gdscript
func _execute_v2_initiate_dialogue(activity):
    # 获取对话参数
    var range_type = activity.parameters["range_type"]  # 1 = NORMAL
    var topic = activity.parameters["topic"]            # "日常闲聊"
    
    # 调用DialogueManager启动对话
    var dialogue_id = DialogueManager.start_dialogue(
        character, range_type, topic, "", "", click, time
    )
    
    # 更新状态
    current_state = AgentState.IN_DIALOGUE
    current_activity = "普通对话"
```

---

## 六、对话系统：社交交互

### 6.1 对话范围

系统支持三种对话范围：

| 范围 | 距离 | 人数限制 | 说明 |
|------|------|----------|------|
| WHISPER | 30px | 最多3人 | 悄悄话，私密 |
| NORMAL | 中范围 | 最多7人 | 普通对话，同中范围可见 |
| BROADCAST | 全房间 | 无限制 | 广播，如教师讲课 |

### 6.2 对话流程

当我发起对话：

```
[我] INITIATE_DIALOGUE (NORMAL范围)
         ↓
[DialogueManager] 创建对话，生成dialogue_id
         ↓
[其他Agent] JOIN_DIALOGUE (使用dialogue_id加入)
         ↓
[SpeakerQueueManager] 管理发言顺序
         ↓
[对话进行] 每个Click轮流发言
```

### 6.3 发言队列

对话使用智能发言队列：
```
优先级 = 基础优先级(10-90)
       + 连续发言惩罚(-20×n)
       + 沉默奖励(+5/轮)
       + 话题相关度(±20)
```

---

## 七、记忆系统：经验积累

### 7.1 记忆类型

我的记忆分为：

| 类型 | 内容 | 用途 |
|------|------|------|
| 事件记忆 | "我去了食堂" | 回顾经历 |
| 情感记忆 | "和小红聊天很开心" | 影响决策 |
| 社交记忆 | "小红是我的朋友" | 关系判断 |

### 7.2 记忆形成

每次活动结束，系统会：

1. **记录事件**：时间、地点、参与者
2. **LLM情感评估**："这次经历让你感到..."
3. **存储自然语言**："和小红在食堂聊天，感觉轻松愉快"

### 7.3 记忆使用

在决策时，Prompt会包含相关记忆：
```
## 你的记忆
- 昨天和小红聊天很开心
- 数学课让你感到压力很大
- 你喜欢图书馆的安静氛围
```

---

## 八、货币系统：收益与成本

### 8.1 三层架构

```
Layer 1: RoomArea (客观参数 S, a, E)
         ↓
Layer 2: RewardSystem (计算 G(t))
         ↓
Layer 3: PerceptionSystem (我的感知 Ŝ, â)
         ↓
Layer 4: UtilitySystem (我的决策)
```

### 8.2 核心公式

**客观收益**：
```
G(t) = (S/a)[1 - exp(-at)]
```

**主观效用**：
```
U = G^α - β_effort × E
```

**我的参数**（抑郁风险）：
- α = 0.55（收益贬值）
- β_effort = 0.8（努力放大）

这意味着同样的活动，我觉得更累、收获更少。

---

## 九、完整流程示例

### 场景：课间休息，我在教室

**Click #1：**
```
[我] 感知：在教室，小红在旁边
[我] 决策："我想和小红聊天"
[我] 提交决策 → ActivityCoordinator
[协调器] 分配：INITIATE_DIALOGUE (我)
[我] 执行：开始对话，对话ID="dlg_Xiaoming_480"
```

**Click #2：**
```
[小红] 加入对话：JOIN_DIALOGUE ("dlg_Xiaoming_480")
[对话系统] 两人对话开始
[我] 发言："小红，你觉得今天的数学课怎么样？"
[小红] 回复："我觉得好难啊..."
```

**Click #3：**
```
[我] 体验：对话持续中，累积情感收益
[我] MVT决策：对话很愉快，继续停留
[我] 继续对话...
```

**Click #4：**
```
[我] 体验：收益开始下降（话题变少）
[我] MVT决策：达到最优时间，考虑离开
[我] 决策："我想去图书馆自习了"
[协调器] 分配：MOVE_TO (图书馆)
[我] 执行：离开对话，移动到图书馆
```

---

## 附录：关键文件位置

| 文件 | 路径 | 说明 |
|------|------|------|
| 完整流程文档 | `docs/COMPLETE_WORKFLOW.md` | 本文档 |
| 技术文档 | `docs/TECHNICAL_DOCUMENTATION.md` | 系统架构详情 |
| 项目结构 | `PROJECT_STRUCTURE.md` | 脚本清单与数据流 |
| 协调器Prompt | `prompts/coordinator_prompt.md` | LLM协调指令 |
| 决策Prompt | `prompts/natural_decision_template.md` | Agent决策指令 |

---

*文档完成时间：2026-04-21*  
*维护者：百舟楫*
