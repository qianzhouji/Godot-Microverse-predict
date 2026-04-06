# AIAgent 时序逻辑文档

> **创建日期**: 2026-04-06
> **说明**: 本文档描述AIAgent的运行时序逻辑

---

## 一、当前时序逻辑

### 1. 初始化阶段 (_ready)

```
AIAgent._ready()
    ├── 创建 decision_timer (决策定时器)
    │   └── wait_time = 60秒 (每1分钟决策一次)
    ├── 创建 experience_timer (体验采样定时器)
    │   └── wait_time = 5秒 (每5秒采样一次)
    └── 启动两个定时器
```

### 2. 运行时的两个独立循环

#### 循环A: 决策循环 (每60秒)

```
decision_timer.timeout
    └── _on_decision_timer_timeout()
        └── make_decision()          # 进行AI决策
            ├── 构建决策Prompt
            ├── 调用API获取决策
            └── 执行决策结果
                ├── 移动任务
                ├── 对话任务
                └── 其他行为
```

**决策内容**:
- 选择下一个行动目标
- 决定是否发起对话
- 决定是否离开当前房间
- 其他行为选择

#### 循环B: 体验采样循环 (每5秒)

```
experience_timer.timeout
    └── _on_experience_sample()
        ├── 获取当前房间
        ├── 计算在当前房间的停留时间
        ├── 通过RewardSystem获取奖赏
        │   └── RewardSystem.distribute_reward()
        │       └── AgentRewardReceiver 接收奖赏
        │           └── PerceptionSystem 贝叶斯更新
        └── _check_mvt_leave_decision()  # MVT决策是否离开
```

**体验采样的作用**:
- 感知当前情境的奖赏率
- 更新对房间的主观评价
- 基于MVT决定是否离开

---

## 二、时序问题分析

### 当前设计的问题

| 问题 | 说明 |
|------|------|
| **决策频率过低** | 60秒一次，无法及时响应环境变化 |
| **决策与感知分离** | 决策时可能基于60秒前的旧信息 |
| **对话触发不灵活** | 需要等待决策周期才能发起对话 |
| **无事件驱动机制** | 无法及时响应突发情况（如教师提问） |

### 理想时序应该是

```
事件驱动 + 周期性检查
    ├── 事件驱动 (即时响应)
    │   ├── 感知到对话行为 → 立即决策是否靠近
    │   ├── 被提问 → 立即决策是否回答
    │   ├── 进入新范围 → 立即决策是否加入对话
    │   └── 情感变化 → 立即调整行为
    │
    └── 周期性检查 (低频率)
        ├── 每30秒：检查长期目标
        ├── 每60秒：反思当前状态
        └── 每5分钟：评估情感关系
```

---

## 三、新对话系统需要的时序调整

### 建议的新时序架构

#### 1. 高频感知循环 (每1-2秒)

```gdscript
# 新的感知定时器
var perception_timer: Timer
perception_timer.wait_time = 1.0  # 每秒检查一次

func _on_perception_check():
    # 1. 检查周围对话行为
    var visible_behaviors = dialogue_manager.get_visible_behaviors(self)
    
    # 2. 检查可听到的对话内容
    var audible_contents = dialogue_manager.get_audible_contents(self)
    
    # 3. 更新对话感知状态
    dialogue_perception.update(visible_behaviors, audible_contents)
    
    # 4. 触发即时决策（如果需要）
    if should_react_to_dialogue():
        make_immediate_decision()
```

#### 2. 对话响应决策 (事件驱动)

```gdscript
# 当听到对话内容时立即决策
func on_dialogue_content_received(message: DialogueMessage):
    # 立即决策是否回复（不等待决策周期）
    var should_reply = decide_reply_immediately(message)
    
    if should_reply:
        # 计算回复优先级
        var priority = calculate_reply_priority(message)
        
        # 提交到话题队列
        topic_manager.submit_speak_request(self, reply_content, priority)
```

#### 3. 行为感知决策 (事件驱动)

```gdscript
# 当看到有人说话但没听到内容时
func on_dialogue_behavior_visible(behavior: DialogueMessage):
    # 计算好奇心
    var curiosity = calculate_curiosity(behavior)
    
    if curiosity > threshold:
        # 立即决策是否移动过去
        var should_move = decide_move_to_range(behavior.range_id)
        
        if should_move:
            move_to_range(behavior.range_id)
```

#### 4. 保留的周期性决策

```gdscript
# 降低频率的长期决策
decision_timer.wait_time = 30.0  # 改为30秒

func _on_decision_timer_timeout():
    # 长期目标决策
    ├── 评估当前任务进度
    ├── 选择下一个主要目标
    ├── 更新情感关系评估
    └── 规划未来行动
```

---

## 四、关键时序问题解答

### Q1: AI什么时候决定进行活动？

**当前**: 每60秒的决策周期

**建议改为**:
- **即时响应**: 感知到对话、被提问、看到有趣行为时立即决策
- **周期性**: 每30秒评估长期目标和任务进度

### Q2: AI什么时候进行思考？

**当前**: 决策时调用API进行思考

**建议改为**:
- **快速思考** (本地规则): 是否回复、是否移动、优先级计算
- **深度思考** (API调用): 复杂决策、情感评估、长期规划

```gdscript
func make_immediate_decision(context: Dictionary) -> Decision:
    # 简单决策：使用本地规则（快速，无API调用）
    if context.type == "dialogue_heard":
        return local_decide_reply(context)
    elif context.type == "behavior_visible":
        return local_decide_move(context)
    
func make_deep_decision(context: Dictionary) -> Decision:
    # 复杂决策：调用API（慢速，需要思考）
    var prompt = build_deep_decision_prompt(context)
    var response = await api_call(prompt)
    return parse_decision(response)
```

### Q3: 如何避免API调用过于频繁？

**策略**:
1. **分层决策**: 简单决策用本地规则，复杂决策用API
2. **冷却时间**: API调用间隔至少5-10秒
3. **批处理**: 累积多个决策需求，一次性处理
4. **缓存**: 相似情境的决策结果缓存复用

---

## 五、建议的新时序实现

```gdscript
class AIAgent:
    # 定时器
    var perception_timer: Timer      # 1秒 - 感知检查
    var decision_timer: Timer        # 30秒 - 长期决策
    var api_cooldown_timer: Timer    # 10秒 - API冷却
    
    # 状态
    var can_call_api: bool = true
    var pending_decisions: Array = []
    
    func _ready():
        # 高频感知
        perception_timer = Timer.new()
        perception_timer.wait_time = 1.0
        perception_timer.timeout.connect(_on_perception_check)
        
        # 低频长期决策
        decision_timer = Timer.new()
        decision_timer.wait_time = 30.0
        decision_timer.timeout.connect(_on_long_term_decision)
        
        # API冷却
        api_cooldown_timer = Timer.new()
        api_cooldown_timer.wait_time = 10.0
        api_cooldown_timer.one_shot = true
        api_cooldown_timer.timeout.connect(func(): can_call_api = true)
    
    # 每秒检查感知
    func _on_perception_check():
        check_dialogue_perception()
        check_environment_changes()
        check_social_opportunities()
    
    # 事件驱动：听到对话
    func on_dialogue_received(message: DialogueMessage):
        # 本地快速决策
        var decision = local_decide_reply(message)
        
        if decision.should_reply:
            if can_call_api:
                # 调用API生成回复内容
                generate_reply_with_api(message)
            else:
                # 使用模板回复
                generate_reply_from_template(message)
    
    # 每30秒长期决策
    func _on_long_term_decision():
        if can_call_api:
            evaluate_long_term_goals()
            update_relationships()
            plan_future_actions()
```

---

*最后更新：2026-04-06*
