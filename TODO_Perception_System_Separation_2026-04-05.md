# 感知层与系统层分离实施方案

> **创建日期**: 2026-04-05
> **关联项目**: Godot-Microverse-predict
> **文档状态**: 待实施

---

## 一、问题背景

当前实现存在**感知层与系统层未分离**的问题：

| 问题 | 现状 | 风险 |
|------|------|------|
| Agent直接访问RoomArea | `AIAgent._get_actual_gain_from_room()` 直接读取 `area.initial_reward_rate` | 违反"Agent不可见客观参数"原则 |
| RoomArea暴露所有参数 | `get_situation_params_description()` 直接返回S,a,E给AI Prompt | Agent"偷看"了客观现实 |
| 感知与系统耦合 | 同一脚本中既有客观计算又有主观感知 | 逻辑混杂，难以维护 |

**理论要求**：Agent不能直接感知情境参数(S,a,E)，只能通过系统发放的"奖赏"间接推断。

---

## 二、目标架构

```
┌─────────────────────────────────────────────────────────────┐
│  系统层 (System Layer) - 客观现实，Agent不可见                │
│  ├─ RoomArea.gd          - 只存储和计算客观参数               │
│  ├─ RewardSystem.gd      - 【新增】统一发放奖赏的中介          │
│  └─ RoomManager.gd       - 管理房间，协调系统层               │
│                                                              │
│  原则：Agent不能直接引用RoomArea，不能读取S,a,E              │
└─────────────────────────────────────────────────────────────┘
                              ↓
                    【通过RewardSystem发放】
                    （Agent只接收"奖赏"数值）
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  感知层 (Perception Layer) - 主观推断，个体差异               │
│  ├─ PerceptionSystem.gd  - 贝叶斯感知（已存在）               │
│  └─ AgentRewardReceiver.gd - 【新增】Agent端的奖赏接收器       │
│                                                              │
│  原则：Agent只能通过接收器获取带噪声的奖赏，据此推断情境       │
└─────────────────────────────────────────────────────────────┘
```

---

## 三、具体实施步骤

### 步骤1: 创建 RewardSystem.gd

**文件路径**: `res://script/system/RewardSystem.gd`

**核心功能**:
- 单例模式管理
- 计算客观收益 G(t) = (S/a)[1 - exp(-at)]
- 通过信号向Agent发放奖赏
- 封装RoomArea访问，Agent不可直接调用

**关键代码框架**:
```gdscript
extends Node
class_name RewardSystem

static var instance: RewardSystem
signal reward_distributed(agent_name: String, room_name: String, 
                          time: float, gain: float, effort: float)

func distribute_reward(agent_name: String, room_name: String, time_in_room: float) -> Dictionary:
    # 1. 内部获取客观参数（Agent不可见）
    # 2. 计算客观收益
    # 3. 发射信号发放奖赏
    pass
```

---

### 步骤2: 创建 AgentRewardReceiver.gd

**文件路径**: `res://script/ai/AgentRewardReceiver.gd`

**核心功能**:
- 订阅RewardSystem信号
- 接收并缓存奖赏历史
- 添加感知噪声
- 传递给PerceptionSystem

**关键代码框架**:
```gdscript
extends Node
class_name AgentRewardReceiver

var ai_agent: AIAgent
var reward_history: Array = []

func _on_reward_received(agent_name: String, room_name: String, 
                         time: float, gain: float, effort: float):
    # 只处理发给自己的奖赏
    # 添加感知噪声
    # 传递给PerceptionSystem
    pass
```

---

### 步骤3: 修改 AIAgent.gd

**修改内容**:
1. **删除** `_get_actual_gain_from_room()` 函数
2. **删除** 所有直接访问 `area.initial_reward_rate` 的代码
3. **新增** `AgentRewardReceiver` 子节点
4. **修改** `_on_experience_sample()` 使用RewardSystem请求奖赏

**变更前后对比**:
```gdscript
# ❌ 删除：直接访问RoomArea
func _get_actual_gain_from_room(room_name: String, time: float) -> float:
    for area in room_areas:
        var S = area.initial_reward_rate  # 直接读取！违规！
        ...

# ✅ 改为：通过RewardSystem请求
func _on_experience_sample():
    if RewardSystem.instance:
        RewardSystem.instance.distribute_reward(character.name, ...)
```

---

### 步骤4: 修改 RoomManager.gd

**新增接口**:
```gdscript
# 系统层内部使用的接口（不推荐Agent直接调用）
func get_room_objective_params_internal(room_name: String) -> Dictionary:
    # 只有RewardSystem等系统层组件调用
    pass
```

---

### 步骤5: 修改 RoomArea.gd

**修改内容**:
- 删除或修改 `get_situation_params_description()`
- 该函数直接返回S,a,E给AI Prompt，违反分离原则
- 改为只返回基本信息，或完全删除

---

### 步骤6: 配置AutoLoad

**在 Godot 项目设置中**:
1. 添加 `RewardSystem` 为 AutoLoad（单例）
2. 确保加载顺序: RoomManager → RewardSystem → 其他

---

## 四、分离后的数据流

```
[体验采样触发]
        ↓
[AIAgent] 请求 RewardSystem.distribute_reward()
        ↓
[RewardSystem] 读取 RoomArea 客观参数 (S,a,E) 【系统层内部】
        ↓
[RewardSystem] 计算客观收益 G(t)
        ↓
[RewardSystem] 发射信号 reward_distributed
        ↓
[AgentRewardReceiver] 接收信号（只处理自己的）
        ↓
[AgentRewardReceiver] 添加感知噪声 → 感知收益
        ↓
[PerceptionSystem] 添加样本 → 贝叶斯更新 → 信念状态
        ↓
[AIAgent] 从 PerceptionSystem 获取感知参数 (Ŝ, â)
        ↓
[AIAgent] MVT决策（基于感知，而非客观）
```

---

## 五、验证方法

### 代码审查清单

- [ ] `AIAgent.gd` 中没有直接引用 `RoomArea`
- [ ] `AIAgent.gd` 中没有直接读取 `initial_reward_rate`, `reward_decay_rate`, `effort_level`
- [ ] 所有客观参数访问都通过 `RewardSystem`
- [ ] 所有主观感知都通过 `PerceptionSystem`

### 运行时验证

- [ ] 日志显示Agent接收到的"奖赏"与客观收益不同（有噪声）
- [ ] 不同Agent对同一情境的感知不同（个体差异）
- [ ] 抑郁Agent的感知更悲观（先验影响）

---

## 六、Godot实现要点

| 技术点 | 实现方式 |
|--------|---------|
| **单例模式** | `RewardSystem` 作为AutoLoad，或使用 `static var instance` |
| **信号通信** | `reward_distributed` 信号连接所有Agent的接收器 |
| **访问控制** | GDScript无private，通过命名约定 `_internal` 和文档说明 |
| **解耦验证** | 搜索代码中所有 `area.initial_reward_rate` 引用，确保只在系统层 |

---

## 七、风险与注意事项

### 风险1: 现有代码依赖
- **问题**: 可能还有其他脚本直接访问RoomArea
- **解决**: 全局搜索 `room_area`、`initial_reward_rate` 等关键词，逐一检查

### 风险2: 信号连接失败
- **问题**: RewardSystem信号可能未正确连接
- **解决**: 添加连接验证日志，确保每个Agent的接收器正确订阅

### 风险3: 性能影响
- **问题**: 信号通信可能带来轻微性能开销
- **解决**: 信号是Godot原生机制，开销极小；如担心可优化为直接调用

---

## 八、关联文档

- [PROJECT_OVERVIEW.md](./PROJECT_OVERVIEW.md) - 理论基础
- [IMPLEMENTATION_LOGIC.md](./IMPLEMENTATION_LOGIC.md) - 实现逻辑
- 本文档 - 感知层与系统层分离方案

---

## 九、实施优先级

| 优先级 | 步骤 | 预估工作量 |
|--------|------|-----------|
| P0 | 步骤1: 创建RewardSystem.gd | 30分钟 |
| P0 | 步骤2: 创建AgentRewardReceiver.gd | 30分钟 |
| P0 | 步骤3: 修改AIAgent.gd | 45分钟 |
| P1 | 步骤4: 修改RoomManager.gd | 15分钟 |
| P1 | 步骤5: 修改RoomArea.gd | 15分钟 |
| P1 | 步骤6: 配置AutoLoad | 5分钟 |
| P2 | 验证与测试 | 30分钟 |

**总计**: 约2.5-3小时

---

## 十、完成标准

- [ ] RewardSystem.gd 创建并配置为AutoLoad
- [ ] AgentRewardReceiver.gd 创建并集成到AIAgent
- [ ] AIAgent.gd 移除所有直接RoomArea访问
- [ ] RoomManager.gd 添加内部接口
- [ ] RoomArea.gd 移除直接暴露参数的函数
- [ ] 代码审查通过（无直接参数访问）
- [ ] 运行时验证通过（感知有噪声，个体差异明显）
- [ ] 文档更新（IMPLEMENTATION_LOGIC.md 标记为已完成）
- [ ] Git提交并推送

---

*本文档由AI助手百舟楫创建，用于指导感知层与系统层分离的实施工作。*
