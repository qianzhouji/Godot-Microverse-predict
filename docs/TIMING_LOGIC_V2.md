# 时序逻辑 V2 - 活动中持续决策

> **创建日期**: 2026-04-08
> **关联项目**: Godot-Microverse-predict
> **文档状态**: 已实现

---

## 一、设计目标

解决原有时序逻辑的局限性：
- **原问题**: Agent开始活动后，需要等待下次Click才能体验，决策与体验分离
- **新方案**: 活动中每次Click自动触发体验(累积奖赏) + 决策(继续/停止/更换)

---

## 二、核心变更

### 时序对比

```
原流程（离散决策）:
Click #1: 感知 → 决策 → 开始听课(等待)
         ↓
Click #2: 体验(5分钟) → 决策 → 继续等待
         ↓
Click #3: 体验(10分钟) → 决策 → 停止活动

新流程（持续决策）:
Click #1: 感知 → 决策 → 开始听课(ActivityManager记录)
         ↓
Click #2: 体验(累积5分钟) → 决策(继续/停止/更换) → 继续听课
         ↓
Click #3: 体验(累积10分钟) → 决策(继续/停止/更换) → 停止活动
         ↓
Click #4: 感知 → 决策 → 开始新活动
```

### 关键差异

| 方面 | 原逻辑 | 新逻辑 |
|------|--------|--------|
| 活动状态 | 由AIAgent内部维护 | ActivityManager统一管理 |
| 体验触发 | 下次Click时一次性体验 | 每次Click累积体验 |
| 决策时机 | 活动开始前 | 活动中每次Click都可决策 |
| 奖赏计算 | 离散计算 | 累积计算 G(t) = (S/a)[1-exp(-at)] |
| 中断支持 | 不支持 | 支持中断/恢复 |

---

## 三、系统架构

### 组件交互

```
TimingSystem (Click触发)
    │
    ├──► ActivityManager._on_click_triggered()
    │        │
    │        ├──► 遍历所有活动中的Agent
    │        │        │
    │        │        ├──► 计算本次Click持续时间
    │        │        ├──► 累积总持续时间
    │        │        ├──► 计算累积收益 G(t)
    │        │        └──► RewardSystem.distribute_reward() (增量)
    │        │
    │        └──► 发射 activity_updated 信号
    │
    └──► AIAgent._on_click_triggered()
             │
             ├──► 检查是否有活动 (ActivityManager.has_activity)
             │
             ├──► 【有活动】_perform_activity_update()
             │        │
             │        ├──► _experience_current_activity()
             │        │        └──► 从RewardReceiver获取累积奖赏
             │        │
             │        ├──► _perceive() (更新环境)
             │        │
             │        ├──► _make_activity_decision()
             │        │        │
             │        │        ├──► MVT计算最优停留时间
             │        │        ├──► 检查是否达到最优时间
             │        │        ├──► 检查是否有更好替代
             │        │        └──► LLM决策 (继续/停止/更换)
             │        │
             │        └──► _execute_activity_decision()
             │                 │
             │                 ├──► continue: 无操作
             │                 ├──► stop: ActivityManager.end_activity() → 新决策周期
             │                 └──► switch: ActivityManager.end_activity() → 新决策周期
             │
             └──► 【无活动】_perform_cognitive_cycle() (原逻辑)
                      │
                      ├──► _perceive()
                      ├──► _experience() (上一周期)
                      ├──► _make_decision()
                      └──► _submit_request()
```

---

## 四、核心实现

### 1. ActivityManager

```gdscript
# 活动记录类
class ActivityRecord:
    var agent_id: String
    var activity_type: ActivityType
    var start_time: float          # 游戏时间（分钟）
    var last_click_time: float     # 上次Click时间
    var total_duration: float      # 总持续时间
    var current_duration: float    # 本次Click持续时间
    var context: Dictionary        # 活动上下文（房间、努力成本等）

# Click时更新
func _on_click_triggered(game_time: float, day: int, click_num: int):
    for agent_id in agent_activities.keys():
        var record = agent_activities[agent_id]
        _update_activity_on_click(agent_id, record, game_time)

# 更新单个活动
func _update_activity_on_click(agent_id: String, record: ActivityRecord, game_time: float):
    # 计算本次Click持续时间
    var click_duration = game_time - record.last_click_time
    record.total_duration += click_duration
    record.last_click_time = game_time
    
    # 计算累积收益
    var cumulative_gain = _calculate_cumulative_gain(agent_id, room_name, record.total_duration)
    
    # 发放增量奖赏
    _distribute_click_reward(agent_id, room_name, record.total_duration, click_duration, effort)
```

### 2. AIAgent 新入口

```gdscript
func _on_click_triggered(game_time: float, day: int, click_num: int):
    if ActivityManager.instance and ActivityManager.instance.has_activity(character.name):
        # 正在活动中：体验 + 决策
        _perform_activity_update()
    elif is_waiting_execution and cached_request:
        # 有缓存请求：执行
        _execute_cached_request()
    else:
        # 空闲状态：感知 + 决策
        _perform_cognitive_cycle()
```

### 3. 活动决策流程

```gdscript
func _make_activity_decision(perception, activity_info, experience) -> Dictionary:
    # 1. 获取MVT参数
    var optimal_time = UtilitySystem.calculate_optimal_time(
        perceived_S, perceived_a, effort, alpha, beta_effort, p_base, eta_s, eta_a
    )
    
    # 2. MVT决策建议
    if current_duration >= optimal_time:
        decision_type = "stop"
    else:
        decision_type = "continue" (或 "switch" 如果有更好选项)
    
    # 3. LLM确认决策
    var prompt = _build_activity_decision_prompt(...)
    var response = await _call_local_llm(prompt)
    
    return {
        "decision_type": llm_decision,
        "mvt_suggestion": mvt_suggestion,
        "optimal_time": optimal_time,
        "current_duration": current_duration
    }
```

---

## 五、决策Prompt示例

### 活动中决策Prompt

```
你是StudentXiaoming，正在进行上课。

【当前活动状态】
- 活动类型：上课
- 已持续时间：10.0分钟
- 累积收益：0.725
- 感知情境收益：45%
- 感知衰减速度：55%

【MVT模型建议】
已停留10.0分钟，达到MVT预测的最优时间(10.2分钟)
建议：停止活动

【当前环境】
- 当前场景：教室（主教学区）
- 附近角色：2人

请决定：
1. CONTINUE - 继续当前活动
2. STOP - 停止当前活动，转为空闲
3. SWITCH - 更换为其他活动

请以JSON格式输出：{"decision": "STOP", "reason": "...", "target_action": "..."}
```

---

## 六、时序示例

### StudentXiaoming 的一天（新时序）

```
08:00 Click #1
├── 状态：空闲
├── 感知：教室、班主任课开始、TeacherWang在讲台
├── 决策：开始听课
└── ActivityManager.start_activity(CLASS, {room: "教室", effort: 0.7})

08:05 Click #2
├── 状态：活动中(听课)
├── ActivityManager更新：持续5分钟，累积收益0.45
├── 体验：接收奖赏增量
├── 感知：同桌在记笔记、老师在讲解
├── MVT决策：已停留5分钟，距离最优时间还有5分钟 → 继续
└── 决策：CONTINUE

08:10 Click #3
├── 状态：活动中(听课)
├── ActivityManager更新：持续10分钟，累积收益0.72
├── 体验：接收奖赏增量
├── 感知：感到疲惫、收益增长变慢
├── MVT决策：已停留10分钟，达到最优时间 → 建议停止
├── LLM确认：STOP（感到疲惫，想休息）
└── ActivityManager.end_activity() → 进入空闲

08:15 Click #4
├── 状态：空闲
├── 感知：课间休息、同学在聊天
├── 决策：开始与同桌对话
└── ActivityManager.start_activity(DIALOGUE, {...})
```

---

## 七、文件变更

### 新增文件

| 文件 | 路径 | 说明 |
|------|------|------|
| ActivityManager.gd | `script/system/ActivityManager.gd` | 活动管理系统 |

### 修改文件

| 文件 | 修改内容 |
|------|----------|
| AIAgent.gd | 新增 `_perform_activity_update()`, `_make_activity_decision()`, `_experience_current_activity()` |
| PROJECT_STRUCTURE.md | 更新AIAgent和新增ActivityManager描述 |

---

## 八、优势

1. **更自然的决策节奏**: Agent可以在活动中随时决定停止，而不是固定周期
2. **累积奖赏计算**: 更符合MVT理论，收益随时间累积
3. **支持活动中断**: 可以被外部事件（如老师点名）中断
4. **更细粒度的体验**: 每次Click都更新体验，感知更连续

---

*文档维护者：百舟楫*
