# 动态人设系统设计方案 - 抑郁水平与认知机制

> **创建日期**: 2026-04-05
> **关联项目**: Godot-Microverse-predict
> **设计目标**: 实现抑郁水平(PHQ-9)和认知计算机制四个指标的动态更新

---

## 一、理论基础

### 1.1 认知计算机制四参数

根据研究一的努力导向决策动态调节计算模型：

| 参数 | 符号 | 含义 | 健康Agent基准 | 抑郁Agent基准 |
|------|------|------|--------------|--------------|
| 离开阈值 | p_base | 对环境平均奖赏率的估计 | 0.5-0.6 | 0.3-0.4 |
| 初始奖赏感知权重 | η_s | 根据情境初始丰富度调节停留时间的敏感度 | 0.5-0.7 | 异常 |
| 衰减率感知权重 | η_a | 感知奖赏消耗速度的准确性 | 0.5 | ↑ (高估衰减) |
| 努力敏感性 | β_effort | 努力成本对离开阈值的调节作用 | 0.4 | 0.8 (核心差异) |

### 1.2 抑郁水平(PHQ-9)

- **范围**: 0-27分（模拟中归一化为0-1）
- **分级**:
  - 0-4 (0-0.15): 无抑郁
  - 5-9 (0.15-0.33): 轻度抑郁
  - 10-14 (0.33-0.52): 中度抑郁
  - 15-19 (0.52-0.70): 中重度抑郁
  - 20-27 (0.70-1.0): 重度抑郁

### 1.3 动态更新理论依据

抑郁水平和认知机制参数应随以下因素动态演化：

1. **日常行为反馈**
   - 任务成功/失败
   - 社交互动质量
   - 情境参与体验

2. **环境反馈**
   - 教师评价
   - 同伴反馈
   - 任务结果

3. **时间累积效应**
   - 连续负面事件累积
   - 成功经验的保护作用

---

## 二、设计方案

### 2.1 系统架构

```
┌─────────────────────────────────────────────────────────────┐
│  触发事件层                                                  │
│  ├─ 任务完成/失败                                            │
│  ├─ 社交互动（积极/消极）                                     │
│  ├─ 教师评价（表扬/批评）                                     │
│  └─ 每日自评（PHQ-9）                                        │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  动态更新引擎 (DynamicPersonality.gd)                        │
│  ├─ 事件解析 → 影响评估                                       │
│  ├─ 参数更新计算                                             │
│  ├─ 边界检查（防止过度偏离基线）                               │
│  └─ 记忆记录（变化原因）                                      │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  动态参数存储                                                │
│  ├─ daily_depression_level: 当日抑郁水平                      │
│  ├─ p_base: 离开阈值（动态）                                  │
│  ├─ eta_s: 初始奖赏感知权重（动态）                           │
│  ├─ eta_a: 衰减率感知权重（动态）                             │
│  └─ beta_effort: 努力敏感性（核心，动态）                      │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  应用层                                                      │
│  ├─ 影响MVT决策（最优停留时间计算）                            │
│  ├─ 影响效用评估（U = G^α - β_effort × E）                    │
│  ├─ 影响感知精度（η_s, η_a调节感知噪声）                       │
│  └─ 影响AI Prompt（动态特质描述）                             │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 更新规则设计

#### 规则1: 任务反馈影响

```gdscript
# 任务成功
update_trait(character, "beta_effort", -0.05, "任务成功增强自信，降低努力敏感性")
update_trait(character, "p_base", +0.03, "任务成功提升对环境奖赏的估计")
update_trait(character, "daily_depression_level", -0.02, "任务成功缓解抑郁情绪")

# 任务失败
update_trait(character, "beta_effort", +0.08, "任务失败增加努力成本感知（抑郁恶化）")
update_trait(character, "p_base", -0.05, "任务失败降低对环境奖赏的估计")
update_trait(character, "daily_depression_level", +0.05, "任务失败加重抑郁情绪")
```

#### 规则2: 社交互动影响

```gdscript
# 积极社交（被接纳、获得支持）
update_trait(character, "daily_depression_level", -0.03, "获得同伴支持，情绪改善")
update_trait(character, "eta_s", +0.02, "积极体验提升对初始奖赏的敏感度")

# 消极社交（被忽视、被拒绝）
update_trait(character, "daily_depression_level", +0.06, "社交 rejection 加重抑郁")
update_trait(character, "beta_effort", +0.04, "社交回避倾向增加")
update_trait(character, "eta_a", +0.03, "负面预期增强，高估奖赏衰减")
```

#### 规则3: 教师评价影响

```gdscript
# 表扬
update_trait(character, "beta_effort", -0.04, "获得认可，降低努力敏感性")
update_trait(character, "daily_depression_level", -0.04, "获得认可，情绪改善")

# 批评
update_trait(character, "beta_effort", +0.06, "批评增加努力成本感知")
update_trait(character, "daily_depression_level", +0.05, "批评加重抑郁情绪")
```

#### 规则4: 每日PHQ-9自评

```gdscript
# 每日结束时根据当天经历计算PHQ-9变化
# 基于当日净情绪变化调整抑郁水平
# 抑郁水平反过来影响认知参数

if daily_depression_level > 0.6:
    # 高抑郁水平恶化认知参数
    update_trait(character, "beta_effort", +0.02, "高抑郁水平导致努力敏感性升高")
    update_trait(character, "p_base", -0.02, "高抑郁水平降低对环境奖赏的估计")
    update_trait(character, "eta_a", +0.01, "高抑郁水平导致悲观预期")
```

#### 规则5: 边界保护机制

```gdscript
# 参数不能偏离基线太多（保持个体稳定性）
# 例如：beta_effort 基线为0.8（抑郁Agent），允许范围 [0.6, 1.0]

func _apply_boundary_protection(character, trait_name, new_value):
    var baseline = _get_baseline_value(character, trait_name)
    var max_deviation = 0.2  # 最大偏离20%
    
    return clamp(new_value, baseline - max_deviation, baseline + max_deviation)
```

### 2.3 更新时机

| 触发时机 | 更新内容 | 频率 |
|---------|---------|------|
| 任务完成时 | beta_effort, p_base, daily_depression_level | 事件触发 |
| 社交互动后 | daily_depression_level, eta_s, beta_effort | 事件触发 |
| 收到教师评价 | beta_effort, daily_depression_level | 事件触发 |
| 每日结束 | daily_depression_level（PHQ-9自评） | 每日1次 |
| 情境切换时 | 检查累积效应，可能触发更新 | 事件触发 |

### 2.4 个体差异保护

```gdscript
# 健康Agent和抑郁Agent有不同的基线和变化敏感度

# 抑郁Agent（如StudentXiaoming）
- 基线: beta_effort = 0.8
- 负面事件影响: ×1.5倍（恶化更快）
- 正面事件影响: ×0.7倍（恢复更慢）
- 边界: [0.6, 1.0]（不能低于健康水平太多）

# 健康Agent（如StudentXiaohong）
- 基线: beta_effort = 0.4
- 负面事件影响: ×0.8倍（有韧性）
- 正面事件影响: ×1.2倍（恢复更快）
- 边界: [0.2, 0.6]（不能高于抑郁水平太多）
```

---

## 三、实现计划

### 阶段1: 扩展DynamicPersonality.gd

1. **新增更新规则函数**
   - `apply_task_feedback()` - 任务反馈影响
   - `apply_social_feedback()` - 社交互动影响
   - `apply_teacher_feedback()` - 教师评价影响
   - `daily_phq9_update()` - 每日PHQ-9自评

2. **新增边界保护机制**
   - `_get_baseline_value()` - 获取基线值
   - `_apply_boundary_protection()` - 应用边界保护
   - `_get_individual_sensitivity()` - 获取个体敏感度

3. **新增PHQ-9模拟**
   - `simulate_phq9_score()` - 根据当日经历模拟PHQ-9分数
   - `get_phq9_level_description()` - 获取PHQ-9等级描述

### 阶段2: 集成到AIAgent决策流程

1. **在关键决策点调用更新**
   - 任务完成时
   - 社交互动后
   - 收到评价后
   - 每日结束时

2. **更新AI Prompt生成**
   - 在`generate_scene_description()`中加入动态特质
   - 让LLM知道当前的抑郁水平和认知状态

### 阶段3: 验证和调试

1. **日志记录**
   - 记录每次参数变化
   - 记录变化原因
   - 记录PHQ-9演化轨迹

2. **可视化（可选）**
   - GodUI面板显示实时参数
   - 绘制PHQ-9时间序列图

---

## 四、预期效果

### 4.1 抑郁风险学生（StudentXiaoming）

**初始状态**:
- daily_depression_level: 0.5（中度）
- beta_effort: 0.8（高努力敏感性）
- p_base: 0.4（低离开阈值）

**负面事件累积后**:
- daily_depression_level: 0.75（中重度）
- beta_effort: 0.95（极高努力敏感性，严重回避）
- p_base: 0.25（极低离开阈值，容易放弃）

**行为表现**:
- 更频繁地提前离开情境
- 更回避高努力活动
- 对奖赏的感知更悲观

### 4.2 健康学生（StudentXiaohong）

**初始状态**:
- daily_depression_level: 0.2（无/轻度）
- beta_effort: 0.4（正常努力敏感性）
- p_base: 0.6（正常离开阈值）

**负面事件后（恢复）**:
- daily_depression_level: 0.25（短暂轻度）→ 0.18（恢复）
- beta_effort: 0.42（轻微上升）→ 0.38（恢复）

**行为表现**:
- 有韧性，能快速从负面事件中恢复
- 保持正常的社交和学习参与

---

## 五、待办清单

- [ ] 扩展DynamicPersonality.gd，添加更新规则函数
- [ ] 实现边界保护机制
- [ ] 实现PHQ-9模拟和每日更新
- [ ] 在AIAgent中集成更新触发点
- [ ] 更新AI Prompt生成，包含动态特质
- [ ] 添加详细的日志记录
- [ ] 验证抑郁Agent和健康Agent的差异演化
- [ ] 更新项目文档

---

*本文档由AI助手百舟楫创建，用于指导动态人设系统的实现。*
