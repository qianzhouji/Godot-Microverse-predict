# 项目完整结构文档 - Godot-Microverse-predict

> **创建日期**: 2026-04-05
> **最后更新**: 2026-04-05
> **文档用途**: 维护项目所有脚本的完整清单、职责说明及架构关系

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
  - 体验采样定时触发（每5秒）
  - MVT驱动行为决策（离开/停留/切换情境）
  - LLM-based对话生成
  - 任务管理与执行
- **依赖**: PerceptionSystem, UtilitySystem, RewardSystem, AgentRewardReceiver
- **关键函数**:
  - `_on_experience_sample()` - 体验采样
  - `_check_mvt_leave_decision()` - MVT决策检查
  - `_select_next_room_by_mvt()` - 基于效用选择下一个房间

#### PerceptionSystem.gd
- **路径**: `res://script/ai/PerceptionSystem.gd`
- **类型**: Node (静态类)
- **职责**: 贝叶斯感知系统，管理Agent对情境的主观推断
- **核心功能**:
  - 维护Agent对每个情境的信念状态
  - 贝叶斯更新后验信念
  - 先验信念差异（健康vs抑郁）
- **关键参数**:
  - `BASE_PERCEPTION_NOISE = 0.02` - 极小的感知噪声（标准差2%）
  - 健康Agent先验: S~Uniform(0.5, 0.25)
  - 抑郁Agent先验: S~Uniform(0.3, 0.15)
- **理论依据**: 感知层噪声仅表示轻微不确定性，主要噪声在决策层（ε）

#### UtilitySystem.gd
- **路径**: `res://script/ai/UtilitySystem.gd`
- **类型**: Node (静态类)
- **职责**: 效用计算系统，实现MVT决策
- **核心功能**:
  - 计算主观效用: U = G^α - β_effort × E
  - 计算最优停留时间 T*
  - 管理个体差异参数
- **关键参数**:
  - 健康Agent: α=0.8, β_effort=0.4
  - 抑郁Agent: α=0.55, β_effort=0.8

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
- **可调整特质**: self_efficacy, effort_sensitivity, motivation_level, attachment_security, pleasure_anticipation, reward_sensitivity

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
- **配置角色**: TeacherWang, PrincipalLi, LibrarianZhang, StudentXiaoming等

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
| script/CharacterManager.gd | CharacterManager | 角色管理 |
| script/system/RewardSystem.gd | RewardSystem | 奖赏系统（新增） |

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

### 2026-04-05 - 感知层与系统层分离完成
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

---

*本文档由为项目结构维护文档。*
