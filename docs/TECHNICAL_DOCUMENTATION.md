# Godot-Microverse-predict 项目技术文档

> **项目**: 抑郁风险学生校园情境模拟系统
> **仓库**: https://github.com/qianzhouji/Godot-Microverse-predict
> **最后更新**: 2026-04-07

---

## 目录

1. [架构概述](#架构概述)
2. [中央时序系统](#中央时序系统)
3. [AIAgent认知循环](#aiagent认知循环)
4. [项目配置](#项目配置)
5. [文件索引](#文件索引)
6. [重构历史](#重构历史)

---

## 架构概述

### 四层系统架构

```
┌─────────────────────────────────────────────────────────────┐
│  第一层：中央时序系统                                          │
│  - 全局时钟（5分钟/周期）                                      │
│  - 上升沿触发所有Agent活动                                     │
│  - 请求缓存与批准执行                                          │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  第二层：全局状态系统                                          │
│  - 时间轴状态（课程表：上课/午休/放学）                         │
│  - 场景状态（各子场景的当前活动）                               │
│  - 活动管理系统（奖赏计算与发放）                               │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  第三层：Agent认知系统                                         │
│  - 感知（场景信息获取）                                        │
│  - 体验（主观体验奖赏）                                        │
│  - 决策（行动请求生成）                                        │
│  - 行动请求缓存（最多2步）                                     │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  第四层：对话管理系统                                          │
│  - 中范围对话（小组讨论）                                      │
│  - 大范围对话（教师提问）                                      │
│  - 发言优先级队列                                              │
│  - 对话生命周期管理                                            │
└─────────────────────────────────────────────────────────────┘
```

### 核心设计原则

| 原则 | 说明 |
|------|------|
| **Click周期机制** | 5分钟游戏时间一个周期，上升沿触发所有Agent同步活动 |
| **感知-体验-决策循环** | 每个Click自动执行：感知→体验→决策→缓存请求 |
| **两步缓存** | Agent可缓存最多2步行动请求，Step1执行后验证Step2有效性 |
| **对话独立时序** | 对话发言不等待Click，按优先级队列即时处理 |
| **行为/内容分离** | 对话行为全场景可见，对话内容仅范围内可见 |

---

## 中央时序系统

### 时序周期（5分钟游戏时间）

```
Click N (上升沿触发)
    │
    ├── 批准Click N-1缓存的所有请求
    │   ├── Agent A: 开始移动
    │   ├── Agent B: 结束对话
    │   └── Agent C: 开始对话
    │
    ├── 执行所有批准的行动
    │   └── （移动、开始/结束对话等）
    │
    ├── 行动完成后 → 触发体验+感知
    │   ├── 体验：基于场景参数计算客观奖赏
    │   └── 感知：获取当前场景信息
    │
    ├── 感知完成后 → 自动触发决策
    │   └── 生成行动请求 → 缓存到下一次Click
    │
    └── 等待下一次Click...

Click N+1 (5分钟后)
    └── 重复上述流程
```

### 每日流程

```
08:00 游戏日开始
    └── 所有Agent统一感知+决策

08:00-17:00 正常运行
    └── 每5分钟一个Click周期

17:00 放学时间
    └── 不接受新的开始请求
    └── 只允许结束当前活动

17:30 强制结束
    └── 所有Agent进入反思阶段
    └── 更新记忆、情感关系
    └── 完成后通知时序系统

次日08:00 新游戏日开始
```

### 课程表

| 时间 | 活动 | 位置 | 类型 |
|------|------|------|------|
| 8:00 | 班主任课 | 教室（主教学区） | class |
| 8:55 | 英语课 | 教室（主教学区） | class |
| 9:50 | 小组讨论 | 教室（小组讨论区） | discussion |
| 10:45 | 午休 | 食堂 | break |
| 11:45 | 数学课 | 教室（主教学区） | class |
| 12:40 | 体育活动 | 体育馆 | activity |

### 核心代码

**TimingSystem.gd**:
```gdscript
extends Node
class_name TimingSystem

static var instance: TimingSystem
const CLICK_INTERVAL_MINUTES: float = 5.0

signal click_triggered(game_time: float, day: int, click_num: int)

func _trigger_click():
    click_count += 1
    # 1. 批准并执行所有待处理请求
    _execute_pending_requests()
    # 2. 触发所有Agent的感知+体验+决策
    click_triggered.emit(current_game_time, current_day, click_count)
```

**ActionRequest.gd**:
```gdscript
class_name ActionRequest

enum ActionType {
    MOVE_TO_RANGE,      # 移动到指定中范围
    START_DIALOGUE,     # 开始对话
    JOIN_DIALOGUE,      # 加入对话
    EXIT_DIALOGUE,      # 退出对话
    START_SPORTS,       # 开始体育活动
    END_SPORTS,         # 结束体育活动
    START_STUDY,        # 开始自习
    END_STUDY,          # 结束自习
    WAIT                # 等待
}

var action_type: ActionType
var cached_step2: ActionRequest  # 第二步缓存
```

---

## AIAgent认知循环

### 认知循环：感知 → 体验 → 决策

```
Click触发
    │
    ▼
┌─────────────┐
│   感知阶段   │  ← 获取当前场景信息
│  (自动执行)  │
└─────────────┘
    │
    ├── 当前子场景
    ├── 子场景内其他Agent
    ├── 可见的对话行为
    ├── 可听到的对话内容
    └── 时间轴状态（上课/休息）
    │
    ▼
┌─────────────┐
│   体验阶段   │  ← 主观体验系统层奖赏
│  (自动执行)  │
└─────────────┘
    │
    ├── 接收系统层奖赏（客观值）
    ├── 贝叶斯更新主观感知
    └── 更新认知参数（p_base, η_s, η_a, β_effort）
    │
    ▼
┌─────────────┐
│   决策阶段   │  ← 生成行动请求
│  (自动执行)  │
└─────────────┘
    │
    ├── 结合感知信息
    ├── 结合认知参数
    ├── 结合时间轴约束
    └── 生成行动请求（最多缓存2步）
    │
    ▼
等待下一次Click执行
```

### Agent状态（8种）

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

### 两步缓存机制

```
Agent A想和Agent B对话，但不在同一中范围

决策结果：
├─ Step1: 移动路径（进入B所在中范围）
└─ Step2: 开始对话（缓存，待确认）

Click N: 执行Step1（移动）
    │
    └── 到达后 → 立即感知（无体验）
        │
        └── 检查：
            ├─ B是否还在？ → 是
            ├─ B是否已在对话？ → 否
            └─ 是否上课了？ → 否
        │
        └── 全部通过 → 执行Step2（开始对话）
        
        任一检查失败 → 重新决策
```

### 中范围划分系统

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

### 移动系统

**定位函数** (`_calculate_move_target`):
- 悄悄话模式 → 贴身位置（±15px）
- 同一中范围 → 目标身边小范围（±30px）
- 不同中范围 → 目标中范围中心（±20%）

**移动输出格式**:
```
"1 目标名称"
```
- `1` - 移动行动编号
- `目标名称` - 场景精确名称或人物精确全名

---

## 项目配置

### AutoLoad配置

在Godot编辑器中：**项目 → 项目设置 → AutoLoad**

| 顺序 | 脚本路径 | 单例名 |
|------|---------|--------|
| 1 | `res://script/RoomManager.gd` | RoomManager |
| 2 | `res://script/system/RewardSystem.gd` | RewardSystem |
| 3 | `res://script/ai/APIManager.gd` | APIManager |
| 4 | `res://script/ai/memory/MemoryManager.gd` | MemoryManager |
| 5 | `res://script/CharacterManager.gd` | CharacterManager |

**project.godot**:
```ini
[autoload]
RoomManager="*res://script/RoomManager.gd"
RewardSystem="*res://script/system/RewardSystem.gd"
APIManager="*res://script/ai/APIManager.gd"
MemoryManager="*res://script/ai/memory/MemoryManager.gd"
CharacterManager="*res://script/CharacterManager.gd"
```

### 本地LLM配置

- **API端点**: `http://localhost:11434/api/generate`
- **默认模型**: `qwen2.5:14b`
- **温度**: 0.7
- **最大token**: 500

---

## 文件索引

### 核心系统文件

| 文件 | 路径 | 说明 |
|------|------|------|
| TimingSystem.gd | `script/system/TimingSystem.gd` | 全局时钟 + Click触发 |
| TimelineState.gd | `script/system/TimelineState.gd` | 课程表 + 行为约束 |
| ActionRequest.gd | `script/data/ActionRequest.gd` | 行动请求数据结构 |
| RewardSystem.gd | `script/system/RewardSystem.gd` | 奖赏系统 |

### AI核心

| 文件 | 路径 | 说明 |
|------|------|------|
| AIAgent.gd | `script/ai/AIAgent.gd` | Agent认知循环 |
| AIAgent_backup_20250406.gd | `script/ai/AIAgent_backup_20250406.gd` | 原AIAgent备份 |
| PromptBuilder.gd | `script/ai/PromptBuilder.gd` | Prompt构建器 |
| PerceptionSystem.gd | `script/ai/PerceptionSystem.gd` | 贝叶斯感知系统 |
| AgentRewardReceiver.gd | `script/ai/AgentRewardReceiver.gd` | 奖赏接收器 |
| MemoryManager.gd | `script/ai/memory/MemoryManager.gd` | 记忆管理 |
| DailyReflectionSystem.gd | `script/ai/DailyReflectionSystem.gd` | 每日反思 |
| DynamicPersonality.gd | `script/ai/DynamicPersonality.gd` | 动态人格 |

### 场景文件

| 文件 | 路径 | 说明 |
|------|------|------|
| School.tscn | `scene/maps/School.tscn` | 学校主场景 |
| StudentXiaoming.tscn | `scene/characters/StudentXiaoming.tscn` | 学生小明 |
| TeacherWang.tscn | `scene/characters/TeacherWang.tscn` | 王老师 |

### Prompt模板

| 文件 | 路径 | 说明 |
|------|------|------|
| decision_prompt_template.txt | `prompts/decision_prompt_template.txt` | 决策Prompt模板 |
| dialogue_reply_template.txt | `prompts/dialogue_reply_template.txt` | 对话回复模板 |

---

## 重构历史

### 架构变革

| 方面 | 原架构 | 新架构 |
|------|--------|--------|
| 时序管理 | 各Agent独立定时器 | 中央时序系统（5分钟Click周期） |
| 对话系统 | 1对1直接对话 | 广播式对话（行为/内容分离） |
| 空间感知 | 距离阈值判断 | 中范围划分（4象限/左右/单区） |
| 任务生成 | 随机生成 | 课程表驱动 |
| Prompt管理 | 硬编码在代码中 | 配置文件+模板分离 |

### 已完成工作

**中央时序系统（100%）**:
- TimingSystem.gd - 全局时钟 + Click触发
- TimelineState.gd - 课程表 + 行为约束
- ActionRequest.gd - 行动请求数据结构

**AIAgent核心重构（95%）**:
- 清理旧代码（定时器、旧任务系统、旧对话系统）
- 新增认知循环（感知→体验→决策→执行）
- 8个行动执行方法框架
- 本地LLM API调用（Ollama）
- 两步缓存验证机制
- 中范围划分系统

**Prompt系统（100%）**:
- 模板与代码分离
- 变量自动填充
- 支持热更新

**感知层分离（100%）**:
- RewardSystem.gd - 系统层奖赏发放
- AgentRewardReceiver.gd - 感知层接收
- PerceptionSystem.gd - 贝叶斯感知

### 待完成工作

| 优先级 | 任务 | 说明 |
|--------|------|------|
| P0 | ActivityManager | 活动管理与奖赏计算闭环 |
| P0 | DialogueManager | 对话生命周期管理 |
| P1 | 情感关系系统 | 情感类型定义、每日反思集成 |
| P1 | UI和调试工具 | 时序系统状态面板、Agent实时监控 |
| P2 | 性能优化 | API调用批处理、决策缓存 |

### 当前进度

```
[完成度: 75%]

中央时序系统     ████████████████████ 100%
AIAgent核心      ███████████████████░  95%
Prompt系统       ████████████████████ 100%
感知体验系统     ████████████████████ 100%
中范围划分系统   ████████████████████ 100%
ActivityManager  ░░░░░░░░░░░░░░░░░░░░   0%
DialogueManager  ░░░░░░░░░░░░░░░░░░░░   0%
测试调试         ░░░░░░░░░░░░░░░░░░░░   0%
```

---

*本文档合并了以下历史文档*:
- Phase1_TimingSystem_Implementation.md
- Phase2_AIAgent_Refactor_Plan.md
- AUTOLOAD_SETUP.md
- File_Location_Index.md
- AIAgent_Refactor_Analysis.md（部分内容）

*维护者：百舟楫*
