# 每日反思与认知机制动态调整系统 - 设计方案

> **创建日期**: 2026-04-05
> **设计目标**: 实现Agent每日自动反思，动态调整认知计算机制四项参数，并完成PHQ-9评估

---

## 一、核心设计思想

### 1.1 与传统方法的区别

| 传统方法 | 新设计 |
|---------|--------|
| 固定规则触发更新（任务成功-0.05） | Agent自主反思，LLM判断调整方向 |
| 固定数值变化 | 基于严重程度动态调整幅度 |
| 单独更新每个参数 | 四项参数联动调整，符合心理机制 |
| 简化的抑郁水平 | 完整的PHQ-9九项评估 |

### 1.2 设计原则

1. **自主性**: Agent基于当日记忆自主反思，而非被动接受固定规则
2. **整体性**: 四项认知参数联动调整，符合真实心理机制
3. **动态性**: 调整幅度基于事件严重程度和累积效应
4. **可解释性**: 每次调整都有明确的反思依据

---

## 二、系统架构

```
┌─────────────────────────────────────────────────────────────┐
│  每日结束触发                                                │
│  └─> 收集当日所有记忆                                        │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  反思分析阶段 (LLM-based)                                    │
│  ├─ 输入: 当日记忆 + 静态人设 + 当前抑郁水平                  │
│  ├─ 处理: LLM分析当日经历的心理影响                          │
│  └─ 输出: 反思报告 {情绪主题, 关键事件, 心理影响评估}         │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  认知参数调整决策 (LLM-based)                                │
│  ├─ 输入: 反思报告 + 当前四项参数值                          │
│  ├─ 处理: LLM判断四项参数的调整方向和严重程度                 │
│  └─ 输出: 调整决策 {参数名, 方向(↑/↓/→), 严重程度(1-5)}      │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  动态幅度计算                                                │
│  ├─ 基于严重程度计算基础调整幅度                              │
│  ├─ 应用个体差异乘数（抑郁vs健康）                           │
│  ├─ 应用边界保护（防止偏离基线太多）                          │
│  └─ 输出: 最终调整数值                                       │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  PHQ-9完整评估 (LLM-based)                                   │
│  ├─ 基于反思报告评估PHQ-9九项                                │
│  ├─ 每项0-3分，总分0-27                                      │
│  └─ 输出: PHQ-9分数和等级                                    │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  记忆记录                                                    │
│  └─ 记录反思内容、参数变化、PHQ-9结果                        │
└─────────────────────────────────────────────────────────────┘
```

---

## 三、详细设计

### 3.1 反思分析阶段

**输入构建**:
```gdscript
var reflection_prompt = """
你是{角色名}，{角色职位}。

【你的静态人设】
{personality}

【你当前的心理状态】
- 当日抑郁水平: {current_depression}%
- 离开阈值(p_base): {p_base}%
- 初始奖赏感知权重(η_s): {eta_s}%
- 衰减率感知权重(η_a): {eta_a}%
- 努力敏感性(β_effort): {beta_effort}%

【你今天的经历】
{formatted_memories}

请进行深度自我反思：
1. 今天你经历的主要情绪主题是什么？（如：挫败感、孤独感、成就感等）
2. 哪些事件对你影响最大？为什么？
3. 这些经历如何影响你的认知模式？
   - 对环境的整体预期（乐观/悲观）
   - 对努力的看法（值得/不值得）
   - 对奖赏的敏感度（提高/降低）
   - 对时间压力的感知（焦虑/放松）

请以第一人称"我"回答，体现真实的心理变化。
"""
```

**LLM输出格式**:
```json
{
  "emotional_theme": "深深的挫败感和孤独感",
  "key_events": [
    {
      "event": "数学课上回答问题错误，被同学嘲笑",
      "impact": "高",
      "psychological_effect": "感到自己无能，害怕再次尝试"
    },
    {
      "event": "午餐时想加入同学但被忽视",
      "impact": "中",
      "psychological_effect": "感到被排斥，社交焦虑增加"
    }
  ],
  "cognitive_changes": {
    "environment_expectation": "悲观 - 觉得学校环境充满威胁",
    "effort_attitude": "不值得 - 努力也不会有好结果",
    "reward_sensitivity": "降低 - 对奖赏的期待减少",
    "time_pressure": "焦虑 - 总觉得时间不够用"
  }
}
```

### 3.2 认知参数调整决策

**输入构建**:
```gdscript
var adjustment_prompt = """
基于以下反思结果，判断四项认知计算机制参数的调整方向：

【反思结果】
{reflection_report}

【当前参数值】
- 离开阈值(p_base): {current_p_base}%
- 初始奖赏感知权重(η_s): {current_eta_s}%
- 衰减率感知权重(η_a): {current_eta_a}%
- 努力敏感性(β_effort): {current_beta_effort}%

【参数含义】
- p_base: 对环境平均奖赏率的估计（高=乐观，低=悲观）
- η_s: 对初始奖赏的敏感度（高=容易被初始印象影响）
- η_a: 对奖赏衰减的感知（高=容易觉得"不值了"）
- β_effort: 努力成本敏感度（高=回避努力，抑郁核心指标）

请判断每个参数的调整方向：
- ↑ 增加
- ↓ 减少
- → 不变

并评估调整的严重程度（1-5，5为最严重）。
"""
```

**LLM输出格式**:
```json
{
  "adjustments": [
    {
      "parameter": "p_base",
      "direction": "↓",
      "severity": 4,
      "reason": "连续的负面事件让我对环境更加悲观"
    },
    {
      "parameter": "eta_s",
      "direction": "↓",
      "severity": 3,
      "reason": "对情境的第一印象不再那么重要，因为预期都是负面的"
    },
    {
      "parameter": "eta_a",
      "direction": "↑",
      "severity": 4,
      "reason": "更容易觉得事情"不值得"继续，奖赏消耗感增强"
    },
    {
      "parameter": "beta_effort",
      "direction": "↑",
      "severity": 5,
      "reason": "核心变化：努力带来的挫败感太强，严重回避努力"
    }
  ],
  "overall_assessment": "今天是非常糟糕的一天，认知模式向抑郁方向明显恶化"
}
```

### 3.3 动态幅度计算

**严重程度与基础幅度映射**:
```gdscript
var severity_to_magnitude = {
    1: 0.01,  # 轻微: ±1%
    2: 0.03,  # 轻度: ±3%
    3: 0.05,  # 中度: ±5%
    4: 0.08,  # 重度: ±8%
    5: 0.12   # 严重: ±12%
}
```

**个体差异乘数**:
```gdscript
# 抑郁Agent
if is_depression:
    negative_multiplier = 1.5  # 负面变化更严重
    positive_multiplier = 0.7  # 正面变化更弱
else:
    # 健康Agent
    negative_multiplier = 0.8  # 负面变化较轻（韧性）
    positive_multiplier = 1.2  # 正面变化更强（恢复）
```

**累积效应加成**:
```gdscript
# 如果连续多天负面，增加额外加成
var consecutive_negative_days = _get_consecutive_negative_days(character)
var cumulative_bonus = min(consecutive_negative_days * 0.02, 0.1)  # 最多+10%
```

**最终计算**:
```gdscript
func calculate_adjustment_magnitude(character, direction, severity, is_negative):
    var base = severity_to_magnitude[severity]
    
    # 应用个体差异
    var multiplier = negative_multiplier if is_negative else positive_multiplier
    
    # 应用累积效应
    var cumulative = _get_cumulative_bonus(character, is_negative)
    
    var final = base * multiplier + cumulative
    
    # 应用方向
    return final if direction == "↑" else -final if direction == "↓" else 0.0
```

### 3.4 PHQ-9完整评估

**PHQ-9九项**:
```gdscript
var phq9_items = [
    "对事物几乎没有兴趣或愉悦感",
    "感到沮丧、抑郁或绝望",
    "入睡困难、睡眠不安或睡眠过多",
    "感到疲倦或精力不足",
    "食欲不振或暴饮暴食",
    "觉得自己很失败或让自己或家人失望",
    "难以集中注意力",
    "动作或说话缓慢，或相反地烦躁不安",
    "有伤害自己或自杀的念头"
]
```

**评估Prompt**:
```gdscript
var phq9_prompt = """
基于以下反思结果，评估PHQ-9的九项症状（过去2周内，包括今天）：

【反思结果】
{reflection_report}

【评分标准】
0 = 完全没有
1 = 几天
2 = 一半以上的天数
3 = 几乎每天

请对每项评分，并简要说明理由。
"""
```

**LLM输出格式**:
```json
{
  "phq9_scores": [
    {"item": "对事物几乎没有兴趣或愉悦感", "score": 2, "reason": "今天对平时喜欢的活动也提不起兴趣"},
    {"item": "感到沮丧、抑郁或绝望", "score": 3, "reason": "持续的挫败感和孤独感"},
    {"item": "入睡困难、睡眠不安或睡眠过多", "score": 1, "reason": "偶尔失眠"},
    {"item": "感到疲倦或精力不足", "score": 2, "reason": "情绪消耗导致疲惫"},
    {"item": "食欲不振或暴饮暴食", "score": 1, "reason": "食欲略有下降"},
    {"item": "觉得自己很失败", "score": 3, "reason": "课堂上被嘲笑强化了失败感"},
    {"item": "难以集中注意力", "score": 2, "reason": "焦虑影响注意力"},
    {"item": "动作或说话缓慢，或烦躁不安", "score": 1, "reason": "轻度烦躁不安"},
    {"item": "有伤害自己或自杀的念头", "score": 0, "reason": "没有此类想法"}
  ],
  "total_score": 15,
  "severity_level": "中重度抑郁"
}
```

---

## 四、实现计划

### 4.1 新增脚本

**DailyReflectionSystem.gd**:
- `conduct_daily_reflection(character)` - 主入口
- `_build_reflection_prompt(character)` - 构建反思Prompt
- `_parse_reflection_response(response)` - 解析反思结果
- `_build_adjustment_prompt(character, reflection)` - 构建调整决策Prompt
- `_calculate_adjustment_magnitude(...)` - 计算调整幅度
- `_build_phq9_prompt(character, reflection)` - 构建PHQ-9 Prompt
- `_update_cognitive_parameters(character, adjustments)` - 更新参数

### 4.2 集成到AIAgent

在AIAgent中添加每日结束时的调用:
```gdscript
func _on_day_end():
    # 触发每日反思
    DailyReflectionSystem.conduct_daily_reflection(character)
```

### 4.3 记忆记录

每次反思后记录:
- 反思报告摘要
- 四项参数变化
- PHQ-9分数变化
- 整体心理状态评估

---

## 五、预期效果

### 5.1 抑郁Agent（StudentXiaoming）

**第1天**:
- 事件: 数学课被嘲笑
- 反思: "我感到无能和孤独"
- 调整: beta_effort ↑5% (严重), p_base ↓3%
- PHQ-9: 8分 → 轻度抑郁

**第5天（连续负面）**:
- 事件: 多次社交失败 + 任务失败
- 反思: "我不属于这里，努力没有意义"
- 调整: beta_effort ↑12% (严重+累积), p_base ↓8%
- PHQ-9: 16分 → 中重度抑郁

**行为表现**: 严重回避社交和努力活动，经常提前离开情境

### 5.2 健康Agent（StudentXiaohong）

**第1天**:
- 事件: 数学课回答错误
- 反思: "有点尴尬，但下次会更好"
- 调整: beta_effort ↑2% (轻微), p_base → (不变)
- PHQ-9: 3分 → 无抑郁

**第5天（有成功也有失败）**:
- 反思: "虽然有挫折，但也有开心的时候"
- 调整: 参数基本稳定，小幅波动
- PHQ-9: 4分 → 仍无抑郁

**行为表现**: 保持正常参与，有韧性

---

## 六、待办清单

- [ ] 创建DailyReflectionSystem.gd脚本
- [ ] 实现反思分析功能（LLM调用）
- [ ] 实现认知参数调整决策（LLM调用）
- [ ] 实现动态幅度计算
- [ ] 实现PHQ-9完整评估（LLM调用）
- [ ] 集成到AIAgent的每日结束流程
- [ ] 添加记忆记录功能
- [ ] 测试抑郁Agent和健康Agent的差异演化
- [ ] 更新项目文档

---

*本文档由AI助手百舟楫创建，用于指导每日反思与认知机制动态调整系统的实现。*
