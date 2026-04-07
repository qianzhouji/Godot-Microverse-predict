# 项目完整结构文档 - Godot-Microverse-predict

> **创建日期**: 2026-04-05
> **最后更新**: 2026-04-05
> **文档用途**: 维护项目所有脚本的完整清单、职责说明及架构关系

---

## 目录

- [一、项目概述](#一项目概述)
- [二、目录结构总览](#二目录结构总览)
- [三、核心脚本详解](#三核心脚本详解)
  - [3.1 AI系统层](#31-ai系统层)
  - [3.2 系统层](#32-系统层)
  - [3.3 角色系统](#33-角色系统)
  - [3.4 房间/情境系统](#34-房间情境系统)
  - [3.5 UI系统](#35-ui系统)
  - [3.6 工具脚本](#36-工具脚本)
- [四、三层架构与数据流](#四三层架构与数据流)
- [五、噪声设计说明](#五噪声设计说明)
- [六、AutoLoad配置](#六autoload配置)
- [七、文档关联](#七文档关联)
- [八、最近变更记录](#八最近变更记录)
- [九、系统架构总览](#九系统架构总览)

---

## 一、项目概述

**项目名称**: Godot-Microverse-predict  
**核心目标**: 基于努力决策理论和边际价值定理(MVT)，模拟抑郁风险学生与健康学生在校园情境中的行为差异  
**技术栈**: Godot 4.x, GDScript, LLM API

---

## 二、目录结构总览

```
res://
├── script/                          # 核心脚本目录
│   ├── ai/                          # AI系统层
│   ├── system/                      # 系统层（新增）
│   ├── ui/                          # UI系统
│   ├── utils/                       # 工具脚本
│   └── *.gd                         # 根级脚本
├── scene/                           # 场景资源
│   ├── maps/                        # 地图场景
│   ├── characters/                  # 角色场景
│   └── ui/                          # UI场景
├── assets/                          # 美术资源
└── *.md                             # 项目文档
```

---

## 三、核心脚本详解

### 3.1 AI系统层 (script/ai/)

#### AIAgent.gd
- **路径**: `res://script/ai/AIAgent.gd`
- **类型**: Node
- **职责**: Agent决策中枢，协调感知、效用、记忆系统
- **核心功能**:
  - **新时序逻辑**: 每次Click触发体验(累积) + 决策(继续/停止/更换)
  - MVT驱动行为决策（离开/停留/切换情境）
  - LLM-based对话生成
  - 活动生命周期管理
- **依赖**: PerceptionSystem, UtilitySystem, RewardSystem, AgentRewardReceiver, ActivityManager
- **关键函数**:
  - `_on_click_triggered()` - Click触发入口（区分空闲/活动中状态）
  - `_perform_activity_update()` - 活动中更新：体验 + 决策
  - `_make_activity_decision()` - 活动决策（继续/停止/更换）
  - `_experience_current_activity()` - 体验当前活动累积奖赏
  - `_check_mvt_leave_decision()` - MVT决策检查
  - `_select_next_room_by_mvt()` - 基于效用选择下一个房间

#### PerceptionSystem.gd
- **路径**: `res://script/ai/PerceptionSystem.gd`
- **类型**: Node (静态类)
- **职责**: 贝叶斯感知系统，管理Agent对情境的主观推断
- **核心功能**:
  - 维护Agent对每个情境的信念状态
  - 贝叶斯更新后验信念（使用非线性最小二乘拟合理论收益函数）
  - 先验信念差异（健康vs抑郁）
- **关键参数**:
  - `BASE_PERCEPTION_NOISE = 0.02` - 极小的感知噪声（标准差2%）
  - 健康Agent先验: S~Uniform(0.5, 0.25)
  - 抑郁Agent先验: S~Uniform(0.3, 0.15)
- **理论依据**: 
  - 感知层噪声仅表示轻微不确定性，主要噪声在决策层（ε）
  - 信念更新使用非线性拟合: `G(t) = (S/a)[1 - exp(-at)]`

#### UtilitySystem.gd
- **路径**: `res://script/ai/UtilitySystem.gd`
- **类型**: Node (静态类)
- **职责**: 效用计算系统，实现MVT决策
- **核心功能**:
  - 计算主观效用: U = G^α - β_effort × E
  - 计算最优停留时间 T*（使用理论解析公式）
  - 管理个体差异参数（四个MVT核心参数）
- **关键公式**:
  - 主观效用: `U(G) = G^α - β_effort × E`
  - 最优停留时间: `log(T) = log[ηS·log(S)] − log(ρbase) − βeffort·effort − ηa·log(a) + ε`
- **关键参数**:
  - 健康Agent: α=0.8, β_effort=0.4, ρ_base=0.5, η_s=0.5, η_a=0.5
  - 抑郁Agent: α=0.55, β_effort=0.8, ρ_base=0.35, η_s=0.4, η_a=0.7

#### AgentRewardReceiver.gd ⭐ 新增
- **路径**: `res://script/ai/AgentRewardReceiver.gd`
- **类型**: Node
- **职责**: Agent端的奖赏接收器，感知层组件
- **核心功能**:
  - 订阅RewardSystem信号
  - 接收并缓存奖赏历史
  - 添加感知噪声（极小）
  - 传递给PerceptionSystem
- **依赖**: RewardSystem, PerceptionSystem

#### DynamicPersonality.gd
- **路径**: `res://script/ai/DynamicPersonality.gd`
- **类型**: Node (静态类)
- **职责**: 动态特质管理，追踪可变化的心理特质
- **核心功能**:
  - 管理每日抑郁水平（PHQ-9）
  - 动态调整认知机制参数
  - 外部显式调用更新（无自动触发）
- **可调整特质**: p_base, eta_s, eta_a, beta_effort, daily_depression_level
- **更新规则**:
  - 任务成功: beta_effort↓, p_base↑, 抑郁↓
  - 任务失败: beta_effort↑, p_base↓, 抑郁↑
  - 积极社交: 抑郁↓, eta_s↑
  - 消极社交: beta_effort↑, eta_a↑, 抑郁↑
  - 教师表扬: beta_effort↓, 抑郁↓
  - 教师批评: beta_effort↑, 抑郁↑
- **个体差异**: 抑郁Agent负面×1.5/正面×0.7，健康Agent负面×0.8/正面×1.2
- **边界保护**: 偏离基线≤20%

#### DialogManager.gd
- **路径**: `res://script/ai/DialogManager.gd`
- **类型**: Node
- **职责**: 对话管理系统，协调角色间对话
- **核心功能**:
  - 管理活跃对话
  - 触发对话事件
  - 对话历史记录

#### ConversationManager.gd
- **路径**: `res://script/ai/ConversationManager.gd`
- **类型**: Node
- **职责**: 对话内容生成，调用LLM生成自然对话
- **核心功能**:
  - 构建对话Prompt
  - 调用API生成回复
  - 管理对话上下文

#### APIManager.gd
- **路径**: `res://script/ai/APIManager.gd`
- **类型**: Node (AutoLoad)
- **职责**: LLM API管理，统一接口调用不同模型
- **核心功能**:
  - 支持多种API（Kimi, OpenAI等）
  - 请求队列管理
  - 响应解析

#### memory/MemoryManager.gd
- **路径**: `res://script/ai/memory/MemoryManager.gd`
- **类型**: Node (AutoLoad)
- **职责**: 记忆系统，管理Agent的经验记忆
- **核心功能**:
  - 添加、查询、遗忘记忆
  - 记忆重要性评估
  - 为Prompt格式化记忆
- **记忆类型**: PERSONAL, INTERACTION, TASK, EMOTION, EVENT
- **重要性等级**: LOW(1), NORMAL(3), HIGH(5), CRITICAL(10)

#### DailyReflectionSystem.gd ⭐ 2026-04-05新增
- **路径**: `res://script/ai/DailyReflectionSystem.gd`
- **类型**: Node (静态类)
- **职责**: 每日反思与认知机制动态调整系统（LLM-based）
- **核心功能**:
  - `conduct_daily_reflection()` - 执行完整每日反思流程
  - `_analyze_reflection()` - LLM分析当日经历，输出{情绪主题, 关键事件, 认知变化}
  - `_decide_cognitive_adjustments()` - LLM判断四项参数调整方向和严重程度(1-5)
  - `_calculate_adjustment_magnitude()` - 动态幅度计算（严重程度→基础幅度×个体差异）
  - `_conduct_phq9_assessment()` - 完整PHQ-9九项评估
- **严重程度映射**: 1→1%, 2→3%, 3→5%, 4→8%, 5→12%
- **个体差异**: 抑郁Agent负面×1.5，健康Agent负面×0.8
- **PHQ-9评估**: 九项症状，总分0-27，五个等级
  - `_conduct_phq9_assessment()` - 完整PHQ-9九项评估
- **调整幅度设计**:
  - 严重程度1-5映射到1%-12%
  - 个体差异：抑郁Agent负面×1.5，健康Agent有韧性
  - 边界保护：偏离基线≤20%
- **PHQ-9评估**: 九项症状，总分0-27，五个等级

---

### 3.2 系统层 (script/system/) ⭐ 新增

#### RewardSystem.gd ⭐ 新增
- **路径**: `res://script/system/RewardSystem.gd`
- **类型**: Node (单例)
- **职责**: 奖赏发放中介，系统层核心组件
- **核心功能**:
  - 封装RoomArea访问（Agent不可见）
  - 计算客观收益 G(t) = (S/a)[1 - exp(-at)]
  - 通过信号向Agent发放奖赏
- **设计原则**: Agent不能直接读取S,a,E，只能通过此接口接收"奖赏"
- **信号**: `reward_distributed(agent_name, room_name, time, gain, effort)`

#### DayNightSystem.gd ⭐ 2026-04-05新增
- **路径**: `res://script/system/DayNightSystem.gd`
- **类型**: Node (AutoLoad)
- **职责**: 游戏时间管理系统，模拟一天的时间流逝
- **核心功能**:
  - 1现实分钟 = 1游戏小时，24分钟 = 1游戏天
  - 从早上7点开始，17点放学，周末休息
  - 信号：day_started, hour_changed, day_ended, school_time_started/ended
  - 自动触发所有学生的每日反思（一天结束时）
- **时间配置**:
  - `REAL_SECONDS_PER_GAME_HOUR = 60.0`
  - `SCHOOL_START_HOUR = 7.0`
  - `SCHOOL_END_HOUR = 17.0`

#### ScheduleSystem.gd ⭐ 2026-04-05新增
- **路径**: `res://script/system/ScheduleSystem.gd`
- **类型**: Node (AutoLoad)
- **职责**: 课程表与任务管理系统
- **核心功能**:
  - 为所有Agent分配个性化课程任务
  - 根据角色类型（抑郁/健康/教师）调整任务优先级
  - 监听DayNightSystem信号，上学日自动分配任务
- **课程表**:
  - 上午：班主任课 → 英语课 → 小组讨论
  - 午休：食堂用餐
  - 下午：数学课 → 体育活动
- **个性化分配**:
  - 抑郁风险学生：高努力情境低优先级（可能回避）
  - 健康学生：正常参与所有活动
  - 教师：按课程表教学

#### ActivityManager.gd ⭐ 2026-04-08新增
- **路径**: `res://script/system/ActivityManager.gd`
- **类型**: Node (AutoLoad)
- **职责**: 活动管理系统，支持新时序逻辑
- **核心功能**:
  - `start_activity()` - 开始新活动，记录活动上下文
  - `end_activity()` - 结束活动，计算最终收益
  - `_on_click_triggered()` - Click时更新所有活动状态
  - `_update_activity_on_click()` - 计算累积奖赏，触发RewardSystem
  - `interrupt_activity()` / `resume_activity()` - 中断/恢复活动
- **活动类型**: CLASS, STUDY, DIALOGUE, SPORTS, MEAL, WALK, REST
- **活动状态**: IDLE, ACTIVE, PAUSED, ENDING
- **新时序逻辑**: 每次Click自动触发体验(累积奖赏) + 决策(继续/停止/更换)

#### TaskManager.gd ⭐ 2026-04-05新增
- **路径**: `res://script/system/TaskManager.gd`
- **类型**: Node (AutoLoad)
- **职责**: 任务管理核心系统，强制执行课程出勤
- **核心功能**:
  - `_enforce_class_attendance()` - 强制上课时间Agent在教室
  - `_should_attend_class()` - 根据人设判断是否逃课
  - `_add_class_task()` - 添加课程任务（优先级8）
  - `trigger_class_interaction()` - 触发课堂互动
  - `can_freely_move()` - 判断是否可以自由移动
- **逃课机制**: 抑郁Agent根据beta_effort有30%概率逃课
- **课堂互动**: 老师提问、学生回答、同桌讨论、小组闲聊（30%被发现）
- **常量**:
  - MAX_TASKS = 5
  - CLASS_TASK_PRIORITY = 8

#### Logger.gd ⭐ 2026-04-05新增
- **路径**: `res://script/system/Logger.gd`
- **类型**: Node (AutoLoad)
- **职责**: 游戏日志系统，按游戏时间记录三种日志
- **日志文件**:
  - `activity_log.txt` - 角色移动和活动
  - `monologue_log.txt` - 任务内心独白
  - `dialogue_log.txt` - 角色对话
- **核心函数**:
  - `log_activity()` - 记录活动
  - `log_movement()` - 记录移动
  - `log_monologue()` - 记录内心独白
  - `log_dialogue()` - 记录对话
- **时间戳格式**: `[第X天 周X HH:MM]`

---

### 3.3 角色系统 (script/)

#### CharacterPersonality.gd
- **路径**: `res://script/CharacterPersonality.gd`
- **类型**: Node (静态类)
- **职责**: 角色人设配置，定义三类智能体参数
- **核心功能**:
  - 定义抑郁风险学生、健康学生、教师的基线参数
  - 人口学、大五人格、PHQ-9基线、功能水平、专能性
  - MVT核心参数: p_base, η_s, η_a, β_effort, α
- **配置角色** (13个):
  - **抑郁风险学生** (2): StudentXiaoming, StudentXiaoyu
  - **健康学生** (6): StudentXiaohong, StudentXiaogang, StudentXiaoli, StudentXiaojun, StudentXiaomei, StudentXiaowei
  - **教师** (5): TeacherWang, PrincipalLi, LibrarianZhang, TeacherLi, TeacherChen

#### CharacterController.gd
- **路径**: `res://script/CharacterController.gd`
- **类型**: CharacterBody2D
- **职责**: 角色物理控制器，处理移动、交互、动画
- **核心功能**:
  - 导航寻路移动
  - 避障逻辑
  - 坐下/站起交互
  - 动画状态管理

#### CharacterManager.gd
- **路径**: `res://script/CharacterManager.gd`
- **类型**: Node (AutoLoad)
- **职责**: 角色管理，协调所有角色
- **核心功能**:
  - 角色注册与查找
  - 批量操作

---

### 3.4 房间/情境系统 (script/)

#### RoomArea.gd
- **路径**: `res://script/RoomArea.gd`
- **类型**: Area2D
- **职责**: 定义情境参数（MVT模型参数）
- **核心参数**:
  - `initial_reward_rate` (S): 初始收益率
  - `reward_decay_rate` (a): 收益衰减率
  - `effort_level` (E): 努力成本
- **设计变更**: 移除直接暴露参数给AI的接口，改为仅通过RewardSystem访问

#### RoomManager.gd
- **路径**: `res://script/RoomManager.gd`
- **类型**: Node
- **职责**: 房间管理，协调房间系统
- **核心功能**:
  - 管理所有房间数据
  - 位置判断（Agent在哪个房间）
  - 内部接口: `get_room_objective_params_internal()`（仅供系统层使用）

#### RoomData.gd
- **路径**: `res://script/RoomData.gd`
- **类型**: RefCounted
- **职责**: 房间数据结构
- **属性**: name, position, size, description, important_locations

---

### 3.5 UI系统 (script/ui/)

#### MainMenu.gd
- **职责**: 主菜单逻辑

#### DialogBubble.gd
- **职责**: 对话气泡显示

#### GodUI.gd
- **职责**: 上帝视角UI（全局控制面板）

#### CharacterAISettings.gd / AIModelLabel.gd
- **职责**: AI模型设置与显示

#### GlobalSettingsUI.gd / SettingsManager.gd
- **职责**: 全局设置管理

#### SaveLoadUI.gd
- **职责**: 存档/读档功能

---

### 3.6 工具脚本 (script/utils/)

#### APIConfig.gd
- **职责**: API配置管理

#### Config.gd
- **职责**: 项目配置

#### Logger.gd
- **职责**: 日志系统

---

## 四、三层架构与数据流

### 4.1 架构图

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: 客观现实（系统层）- Agent不可见                      │
│  ├─ RoomArea.gd          - 定义情境参数(S, a, E)             │
│  ├─ RewardSystem.gd      - 计算客观收益，发放奖赏            │
│  └─ RoomManager.gd       - 房间管理                          │
│                                                              │
│  原则：Agent不能直接引用RoomArea，不能读取S,a,E              │
└─────────────────────────────────────────────────────────────┘
                              ↓
                    【通过RewardSystem发放】
                    （Agent只接收"奖赏"数值）
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  Layer 2: 感知推断（认知层）- 个体差异                         │
│  ├─ AgentRewardReceiver.gd - 接收奖赏，添加感知噪声          │
│  └─ PerceptionSystem.gd  - 贝叶斯感知，推断情境参数          │
│                                                              │
│  原则：Agent只能通过接收器获取奖赏，据此推断(Ŝ, â)           │
│  噪声设计：感知噪声极小(σ=2%)，主要噪声在决策层(ε)           │
└─────────────────────────────────────────────────────────────┘
                              ↓
                    【主观感知】(Ŝ, â, 不确定性)
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  Layer 3: 效用评估（决策层）- 核心差异                         │
│  ├─ UtilitySystem.gd     - 效用计算与MVT决策                 │
│  ├─ AIAgent.gd           - Agent决策中枢                     │
│  └─ DynamicPersonality.gd - 动态特质管理                     │
│                                                              │
│  原则：计算主观效用，驱动行为决策                              │
│  公式：U = G̃^α - β_effort × E                               │
│  噪声：决策噪声ε（理论公式中的误差项）                        │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 数据流详解

```
[体验采样触发]
        ↓
[AIAgent] 请求 RewardSystem.distribute_reward()
        ↓
[RewardSystem] 读取 RoomArea 客观参数 (S,a,E) 【系统层内部】
        ↓
[RewardSystem] 计算客观收益 G(t) = (S/a)[1 - exp(-at)]
        ↓
[RewardSystem] 发射信号 reward_distributed
        ↓
[AgentRewardReceiver] 接收信号（只处理自己的）
        ↓
[AgentRewardReceiver] 添加极小感知噪声(σ≈2%) → 感知收益
        ↓
[PerceptionSystem] 添加样本 → 贝叶斯更新 → 信念状态(Ŝ, â)
        ↓
[AIAgent] 从 PerceptionSystem 获取感知参数
        ↓
[UtilitySystem] 计算最优停留时间 T* 和当前效用 U
        ↓
[AIAgent] MVT决策（是否离开）+ 决策噪声ε
        ↓
[CharacterController] 执行移动/交互
```

---

## 五、噪声设计说明

### 5.1 两层噪声架构

根据理论公式和实现需求，项目采用**两层噪声架构**：

| 噪声层级 | 位置 | 大小 | 理论依据 | 实现方式 |
|---------|------|------|---------|---------|
| **感知噪声** | PerceptionSystem | σ = 2% (极小) | 感知不确定性 | `perceive_gain()` 添加高斯噪声 |
| **决策噪声** | AIAgent (待实现) | ε (公式中的误差项) | 随机决策噪声 | 在计算T*后添加 |

### 5.2 为什么感知噪声要足够小？

1. **理论一致性**: 理论公式中的ε是决策噪声，不是感知噪声
2. **避免双重噪声**: 如果感知噪声太大，加上决策噪声会导致行为过于随机
3. **保留个体差异**: 即使感知噪声小，不同Agent的(η_s, η_a)差异仍会导致不同的感知精度
4. **贝叶斯更新有效性**: 噪声太大会使样本不可靠，影响信念更新

### 5.3 当前实现

```gdscript
# PerceptionSystem.gd
const BASE_PERCEPTION_NOISE = 0.02  # 标准差仅2%

static func perceive_gain(actual_gain, eta_s, eta_a):
    var avg_eta = (eta_s + eta_a) / 2.0
    var noise_std = BASE_PERCEPTION_NOISE * (1.0 - avg_eta * 0.3)
    # 当eta=0.5时，噪声 ≈ 1.7%
    # 当eta=1.0时，噪声 ≈ 1.4%
    return clamp(actual_gain + randfn(0, noise_std), 0, 1)
```

---

## 六、AutoLoad配置

在Godot项目设置中，以下脚本应配置为AutoLoad：

| 脚本路径 | 单例名 | 用途 |
|---------|-------|------|
| script/ai/APIManager.gd | APIManager | API调用管理 |
| script/ai/memory/MemoryManager.gd | MemoryManager | 记忆系统 |
| script/ai/DialogManager.gd | DialogManager | 对话管理 |
| script/CharacterManager.gd | CharacterManager | 角色管理 |
| script/system/RewardSystem.gd | RewardSystem | 奖赏系统 |
| script/system/DayNightSystem.gd | DayNightSystem | 游戏时间管理系统 |
| script/system/ScheduleSystem.gd | ScheduleSystem | 课程表与任务管理 |
| script/system/TaskManager.gd | TaskManager | 任务管理（课程出勤） |
| script/system/Logger.gd | Logger | 日志系统 |

---

## 七、文档关联

| 文档 | 用途 |
|------|------|
| [PROJECT_OVERVIEW.md](./PROJECT_OVERVIEW.md) | 理论基础和研究设计 |
| [IMPLEMENTATION_LOGIC.md](./IMPLEMENTATION_LOGIC.md) | 实现逻辑和架构说明 |
| [本文档](./PROJECT_STRUCTURE.md) | 完整项目结构和脚本清单 |
| [TODO_Perception_System_Separation_2026-04-05.md](./TODO_Perception_System_Separation_2026-04-05.md) | 感知层分离实施待办 |

---

## 八、最近变更记录

### 2026-04-05 - 重大更新日

#### 上午：感知层与系统层分离完成
- ✅ 创建 RewardSystem.gd（系统层奖赏发放）
- ✅ 创建 AgentRewardReceiver.gd（感知层接收器）
- ✅ 修改 AIAgent.gd（移除直接RoomArea访问，集成RewardSystem）
- ✅ 修改 RoomManager.gd（添加内部接口）
- ✅ 修改 RoomArea.gd（移除直接暴露参数的接口）
- ✅ 修改 PerceptionSystem.gd（降低感知噪声至2%）
- ✅ 配置 AutoLoad（RewardSystem设置为单例）
- ✅ 创建 PROJECT_STRUCTURE.md（项目完整结构）
- ✅ 创建 TODO_Perception_System_Separation_2026-04-05.md（分离实施待办）
- ✅ 创建 docs/AUTOLOAD_SETUP.md（AutoLoad配置说明）

#### 下午：动态人设系统实现
- ✅ 扩展 DynamicPersonality.gd
  - 新增任务反馈影响（apply_task_feedback）
  - 新增社交互动影响（apply_social_feedback）
  - 新增教师评价影响（apply_teacher_feedback）
  - 新增每日PHQ-9更新（daily_phq9_update）
  - 新增边界保护机制（_apply_boundary_protection）
- ✅ 创建 docs/DYNAMIC_PERSONALITY_DESIGN.md（设计文档）

#### 傍晚：每日反思系统实现
- ✅ 创建 DailyReflectionSystem.gd
  - 完整的每日反思流程（conduct_daily_reflection）
  - LLM-based反思分析（_analyze_reflection）
  - 四项认知参数动态调整（_decide_cognitive_adjustments）
  - 动态幅度计算（严重程度1-5映射到1%-12%）
  - 完整的PHQ-9九项评估（_conduct_phq9_assessment）
  - 个体差异（抑郁Agent负面×1.5，健康Agent有韧性）
- ✅ 创建 docs/DAILY_REFLECTION_DESIGN.md（设计文档）

#### 晚上：场景重构与角色扩展
- ✅ 重构 School.tscn 的 RoomArea 结构
  - 删除错误的独立CollisionShape2D节点
  - 创建5个符合MVT理论的情境（主教学区、小组讨论区、食堂、走廊、体育馆）
  - 配置正确的S, a, E参数
- ✅ 删除不需要的通用角色（Alice, Grace, Jack等8个）
- ✅ 创建5个特定角色场景文件（StudentXiaoming, StudentXiaohong, TeacherWang, PrincipalLi, LibrarianZhang）
- ✅ 添加8个新角色
  - 5个健康学生：Xiaogang, Xiaoli, Xiaojun, Xiaomei, Xiaowei
  - 1个抑郁风险学生：Xiaoyu
  - 2个教师：TeacherLi（数学）, TeacherChen（英语）
- ✅ 更新 CharacterPersonality.gd，添加13个角色的完整人设

#### 深夜：时间系统与课程表
- ✅ 创建 DayNightSystem.gd
  - 游戏内时间缩放（1现实分钟=1游戏小时）
  - 学校时间7:00-17:00，周末休息
  - 自动触发每日反思（一天结束时）
- ✅ 创建 ScheduleSystem.gd
  - 完整的课程表（上午3节课+午休+下午2节课）
  - 个性化任务分配（根据角色类型调整优先级）
  - 集成DayNightSystem，上学日自动分配任务
- ✅ 修改 AIAgent.gd
  - 优先使用ScheduleSystem的课程表任务
  - 修复环境描述使用游戏内时间
  - 改进学校场景描述

#### 凌晨：Bug修复与优化
- ✅ 修复DayNightSystem访问错误
  - 移除class_name避免与AutoLoad冲突
  - 使用get_node_or_null安全获取（解决_ready前调用问题）
  - 修复is_school_day属性错误（使用is_weekend()判断）
- ✅ 修复场景描述错误
  - School.tscn根节点名为Office，添加匹配处理
  - 使用游戏内时间而非真实时间
- ✅ 修复任务刷新逻辑
  - 优先使用ScheduleSystem课程表任务
  - 周末生成10个默认任务，平时3个
- ✅ 重构默认任务池
  - 学生上学日任务池（20个任务）
  - 学生周末任务池（20个任务）
  - 教师任务池（按科目定制）
  - 完全替换办公室任务为学校场景任务

### 2026-04-05 - 晚间更新

#### 任务系统重构
- ✅ 创建 TaskManager.gd
  - 强制执行课程出勤（上课时间强制Agent在教室）
  - 最多5个任务，初始分配3个
  - 课程任务优先级8（留出9-10给人生大事）
  - 人设化逃课（抑郁Agent根据beta_effort有概率逃课）
  - 课堂互动机制（老师提问、学生回答、同桌讨论、小组闲聊）
  - 闲聊被老师发现的风险（30%概率）
- ✅ 修改AIAgent任务优先级评估
  - Agent自主判断渴望值（1-10）
  - 提供完整的判断标准和示例
  - 大部分日常任务应该是3-5

#### 角色感知与对话
- ✅ 添加Agent感知附近角色功能
  - _check_nearby_characters()函数
  - 根据性格决定对话概率（抑郁10%，外向40%，内向15%，普通25%）
  - 距离阈值100px
- ✅ 修复对话触发机制
  - 在决策流程中检查附近角色
  - 自动发起对话

#### 办公室内容清理
- ✅ 彻底清理所有"员工"和"办公室"残留
  - AIAgent.gd: 修改"公司员工信息"为"学校师生信息"
  - ConversationManager.gd: 动态角色描述（教师/学生）
  - CharacterPersonality.gd: 默认人设改为"学生"
  - DialogManager.gd: 替换公司相关描述

#### 日志系统
- ✅ 创建 Logger.gd
  - 三种日志文件：activity_log.txt, monologue_log.txt, dialogue_log.txt
  - 按照游戏时间戳记录
  - 集成到AIAgent和DialogManager

---

## 九、系统架构总览

### 9.1 核心系统交互图

```
DayNightSystem (时间)
    ↓ day_started信号
ScheduleSystem (课程表)
    ↓ 分配任务
AIAgent (决策)
    ↓ API调用 / 默认决策
CharacterController (执行)
    ↓ 移动/交互
场景更新
    ↓
RewardSystem (奖赏)
    ↓ 信号
AgentRewardReceiver (感知)
    ↓
PerceptionSystem (贝叶斯更新)
    ↓
UtilitySystem (MVT决策)
    ↓
AIAgent (新决策)
```

### 9.2 数据流

1. **时间驱动**: DayNightSystem推进时间，触发信号
2. **任务分配**: ScheduleSystem根据时间分配课程任务
3. **决策执行**: AIAgent根据任务和MVT计算做出决策
4. **感知更新**: 在情境中获得奖赏，更新信念
5. **每日反思**: 一天结束时自动触发，更新认知参数

### 9.3 本地LLM集成

- **Ollama**: 本地大模型服务
- **默认模型**: qwen2.5:1.5b（中文优化）
- **API配置**: APIConfig.gd统一管理
- **故障回退**: API失败时自动使用默认决策

### 2026-04-07 - MVT公式修正

#### 上午：MVT理论公式实现修正
- ✅ 修正 UtilitySystem.gd
  - 重写 `calculate_optimal_time()` 使用理论解析公式：`log(T) = log[ηS·log(S)] − log(ρbase) − βeffort·effort − ηa·log(a) + ε`
  - 更新 `get_agent_utility_params()` 返回全部四个MVT核心参数（ρ_base, η_s, η_a, β_effort）
  - 更新 `get_utility_params_description()` 添加MVT参数描述
  - 更新 `get_decision_analysis()` 集成MVT建议停留时间
- ✅ 修正 AIAgent.gd
  - 实现 `_check_mvt_leave_decision()` 完整MVT离开决策检查
- ✅ 修正 PerceptionSystem.gd
  - 重写 `_update_beliefs()` 使用非线性最小二乘拟合理论收益函数 `G(t) = (S/a)[1 - exp(-at)]`
  - 替代原来的线性近似
- ✅ 更新项目文档
  - 更新 README.md 中的MVT公式说明
  - 更新 PROJECT_STRUCTURE.md 中的实现描述

---

*本文档由AI助手百舟楫维护，最后更新：2026-04-07*
