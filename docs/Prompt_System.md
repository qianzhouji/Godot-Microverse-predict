# Prompt系统详细文档

> **系统名称**: PromptBuilder + Prompt模板
> **版本**: 2.0
> **最后更新**: 2026-04-08

---

## 目录

1. [系统概述](#系统概述)
2. [PromptBuilder详解](#promptbuilder详解)
3. [自然语言决策Prompt模板](#自然语言决策prompt模板)
4. [决策Prompt模板](#决策prompt模板)
5. [对话回复Prompt模板](#对话回复prompt模板)
6. [Prompt片段](#prompt片段)
7. [变量映射](#变量映射)
8. [使用示例](#使用示例)

---

## 系统概述

### 设计目标

Prompt系统是 Godot-Microverse-predict 项目的AI交互层，负责：
- 将代码数据转换为LLM可理解的文本格式
- 分离模板与代码，支持热更新
- 提供丰富的上下文信息供LLM决策
- 标准化决策输出格式

### 架构位置

```
┌─────────────────────────────────────────────────────────────┐
│  AIAgent认知系统                                              │
│  ├─ _make_decision()         - 决策入口                      │
│  └─ _call_local_llm()        - LLM调用                       │
└─────────────────────────────────────────────────────────────┘
                              ↓
                    调用PromptBuilder
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  Prompt系统                                                   │
│  ├─ PromptBuilder.gd         - 构建器                        │
│  ├─ prompts/*.md             - 模板文件                      │
│  └─ prompts/fragments/*.md   - 片段文件                      │
└─────────────────────────────────────────────────────────────┘
                              ↓
                    生成完整Prompt
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  本地LLM (Ollama)                                             │
│  └─ qwen2.5:14b              - 默认模型                      │
└─────────────────────────────────────────────────────────────┘
```

### 核心特性

| 特性 | 说明 |
|------|------|
| **模板分离** | Prompt模板存储在独立文件，支持热更新 |
| **变量填充** | 使用 `{{variable}}` 语法自动填充 |
| **缓存机制** | 模板文件缓存，避免重复读取 |
| **片段复用** | 常用片段可独立维护，多模板共享 |

---

## PromptBuilder详解

### 类定义

```gdscript
class_name PromptBuilder
extends Node
```

### 常量定义

```gdscript
const PROMPTS_DIR = "res://prompts/"
const FRAGMENTS_DIR = "res://prompts/fragments/"
```

### 静态变量

```gdscript
static var template_cache: Dictionary = {}
# 缓存已加载的模板，避免重复文件IO
```

### 核心函数

#### build_natural_decision_prompt()

```gdscript
static func build_natural_decision_prompt(agent: AIAgent, perception: Dictionary) -> String
```

**功能**: 构建V2自然语言决策Prompt

**输入**:
| 参数 | 类型 | 说明 |
|------|------|------|
| agent | AIAgent | Agent实例 |
| perception | Dictionary | 感知结果 |

**返回值**: String - 完整的自然语言决策Prompt

**执行流程**:
1. 加载自然语言决策模板文件
2. 获取Agent人设数据
3. 构建变量映射
4. 填充模板
5. 返回完整Prompt

**变量映射**:
| 变量名 | 来源 | 说明 |
|--------|------|------|
| `agent_name` | agent.character.name | Agent名称 |
| `basic_info` | _build_basic_info() | 基本信息 |
| `current_time` | TimingSystem | 当前时间 |
| `current_room` | perception | 当前房间 |
| `current_period` | TimelineState | 当前时段 |
| `nearby_agents` | _build_nearby_agents() | 附近角色 |
| `time_constraints` | _build_behavior_constraints() | 时间约束 |

**输出示例**:
```
我想去图书馆准备明天的数学考试
```

---

#### build_decision_prompt()

```gdscript
static func build_decision_prompt(agent: AIAgent, perception: Dictionary) -> String
```

**功能**: 构建决策Prompt

**输入**:
| 参数 | 类型 | 说明 |
|------|------|------|
| agent | AIAgent | Agent实例 |
| perception | Dictionary | 感知结果 |

**返回值**: String - 完整的决策Prompt

**执行流程**:
1. 加载决策模板文件
2. 获取Agent人设数据
3. 构建变量映射
4. 填充模板
5. 返回完整Prompt

**变量映射**:
| 变量名 | 来源 | 说明 |
|--------|------|------|
| `role_description` | CharacterPersonality | 角色描述 |
| `agent_name` | agent.character.name | Agent名称 |
| `basic_info` | _build_basic_info() | 基本信息 |
| `big_five_traits` | _build_big_five_traits() | 大五人格 |
| `mental_health_status` | _build_mental_health_status() | 心理健康 |
| `functioning_level` | _build_functioning_level() | 功能水平 |
| `specific_abilities` | _build_specific_abilities() | 专能性 |
| `cognitive_parameters` | _build_cognitive_parameters() | 认知参数 |
| `current_time` | TimingSystem | 当前时间 |
| `current_room` | perception | 当前房间 |
| `current_period` | TimelineState | 当前时段 |
| `behavior_constraints` | _build_behavior_constraints() | 行为约束 |
| `environment_info` | agent.get_environment_info() | 环境信息 |
| `perceived_params` | _build_perceived_params() | 感知参数 |
| `memories` | MemoryManager | 记忆 |
| `activity_status` | _build_activity_status() | 活动状态 |

---

#### build_dialogue_reply_prompt()

```gdscript
static func build_dialogue_reply_prompt(agent: AIAgent, dialogue_context: Dictionary) -> String
```

**功能**: 构建对话回复Prompt

**输入**:
| 参数 | 类型 | 说明 |
|------|------|------|
| agent | AIAgent | Agent实例 |
| dialogue_context | Dictionary | 对话上下文 |

**返回值**: String - 完整的对话回复Prompt

**dialogue_context结构**:
| 键 | 类型 | 说明 |
|----|------|------|
| `initiator` | String | 对话发起者 |
| `current_speaker` | String | 当前发言者 |
| `range` | String | 对话范围（中范围/大范围） |
| `duration` | String | 对话时长 |
| `history` | Array | 对话历史 |
| `content` | String | 听到的内容 |
| `topic_interest` | String | 话题兴趣度 |

---

#### _load_template()

```gdscript
static func _load_template(filename: String) -> String
```

**功能**: 加载模板文件

**输入**:
| 参数 | 类型 | 说明 |
|------|------|------|
| filename | String | 模板文件名 |

**返回值**: String - 模板内容

**缓存机制**:
- 首次加载时读取文件并缓存
- 后续调用直接返回缓存内容
- 支持热更新（调用clear_cache()清除缓存）

---

#### _fill_template()

```gdscript
static func _fill_template(template: String, variables: Dictionary) -> String
```

**功能**: 填充模板变量

**输入**:
| 参数 | 类型 | 说明 |
|------|------|------|
| template | String | 模板文本 |
| variables | Dictionary | 变量映射 |

**返回值**: String - 填充后的文本

**替换规则**:
- 查找 `{{variable_name}}` 格式
- 替换为 `variables[variable_name]` 的值
- 未找到的变量保持原样

---

#### clear_cache()

```gdscript
static func clear_cache()
```

**功能**: 清除模板缓存

**使用场景**:
- 模板文件修改后需要重新加载
- 开发调试时
- 内存优化

---

## 自然语言决策Prompt模板

### 文件位置

```
prompts/natural_decision_template.txt
```

### 模板结构

```
你是{{agent_name}}，请描述你接下来想要做什么。

## 角色信息
{{basic_info}}

## 当前状态
- 当前场景：{{current_room}}
- 当前时间：{{current_time}}
- 当前时段：{{current_period}}
- 附近角色：{{nearby_agents}}

## 时间约束
{{time_constraints}}

## 决策要求
请用一句话描述你接下来想要进行的活动。

示例：
- "我想去图书馆准备明天的数学考试"
- "我想和小明讨论一下物理问题"
- "我想去体育馆打篮球"
- "这节课我想认真听讲"
- "我有点累了，随便听听课吧"

请直接输出你的决策描述，不需要解释：
```

### 使用场景

V2活动系统中，Agent生成自然语言决策描述，提交给中央协调器进行活动分配。

---

## 决策Prompt模板

### 文件位置

```
prompts/decision_prompt_template.md
```

### 模板结构

```
# 抑郁风险学生校园情境模拟系统 - 决策Prompt

## 角色定义
你是{{agent_name}}，一名{{role_description}}。

### 基本信息
{{basic_info}}

### 人格特质（大五人格）
{{big_five_traits}}

### 心理健康状况
{{mental_health_status}}

### 功能水平
{{functioning_level}}

### 专能性
{{specific_abilities}}

### 认知计算机制参数
{{cognitive_parameters}}

## 当前状态
- 当前时间：{{current_time}}
- 当前位置：{{current_room}}
- 当前时段：{{current_period}}
- 行为约束：{{behavior_constraints}}

## 周围环境
{{environment_info}}

## 感知参数
{{perceived_params}}

## 记忆
{{memories}}

## 活动状态
{{activity_status}}

## 决策指令
基于以上信息，请做出决策...

### 可选行动
1. 移动（编号1）
2. 开始对话（编号2）
...

### 输出格式
请以JSON格式输出...
```

### 关键段落说明

#### 中范围划分规则

```
### 中范围划分规则
- **教室/图书馆/自习室/食堂**：分为4个象限（按平面直角坐标系）
  - 第1象限：右上（x > 中心, y < 中心）
  - 第2象限：左上（x < 中心, y < 中心）
  - 第3象限：左下（x < 中心, y > 中心）
  - 第4象限：右下（x > 中心, y > 中心）
- **大走廊**：分为左区和右区
- **小走廊**：单区域（中心区域）

**重要**：只有当两个角色在同一中范围内时，才能直接开始普通对话。
```

#### 移动说明

```
### 移动说明
- **悄悄话模式**：必须移动到目标身边15像素内（贴身）
- **普通对话**：如果在同一中范围，无需移动即可对话
- **跨中范围对话**：需要先移动到目标所在中范围

**移动输出格式**："1 目标名称"
- 示例："1 食堂" - 移动到食堂
- 示例："1 小明" - 移动到小明附近
```

#### 输出格式示例

```json
{
  "action_type": "MOVE_TO_RANGE",
  "target_id": "食堂",
  "reasoning": "现在是午休时间，我需要去食堂用餐",
  "cached_step2": {
    "action_type": "START_DIALOGUE",
    "target_id": "小红",
    "reasoning": "到达食堂后和小红一起吃饭"
  }
}
```

---

## 对话回复Prompt模板

### 文件位置

```
prompts/dialogue_reply_template.md
```

### 模板结构

```
# 对话回复Prompt

## 角色定义
你是{{agent_name}}，一名{{role_description}}。

### 基本信息
{{basic_info}}

### 人格特质
{{big_five_traits}}

### 当前心情
{{mood_status}}

## 对话上下文
- 对话发起者：{{dialogue_initiator}}
- 当前发言者：{{current_speaker}}
- 对话范围：{{dialogue_range}}
- 对话时长：{{dialogue_duration}}

## 对话历史
{{dialogue_history}}

## 你听到的内容
{{heard_content}}

## 关系信息
{{relationship_with_speaker}}

## 时间约束
{{time_constraints}}

## 回复指令
基于以上信息，请决定是否回复以及如何回复...

### 输出格式
{
  "should_reply": true/false,
  "reply_content": "回复内容",
  "reply_tone": "语气",
  "reasoning": "决策理由"
}
```

---

## Prompt片段

### 片段目录

```
prompts/fragments/
├── basic_info_fragment.md
├── big_five_fragment.txt
└── ...
```

### 片段使用

片段可以在多个模板中复用，通过 `_load_template()` 加载后插入到主模板中。

---

## 变量映射

### 基础信息变量

| 变量名 | 构建函数 | 示例值 |
|--------|----------|--------|
| `basic_info` | _build_basic_info() | "- 身份：学生\n- 性格：内向敏感..." |
| `big_five_traits` | _build_big_five_traits() | "开放性45、尽责性70、外向性30..." |
| `mental_health_status` | _build_mental_health_status() | "PHQ-9基线分数：12 (中度)" |
| `functioning_level` | _build_functioning_level() | "学业功能65、社交功能40..." |
| `specific_abilities` | _build_specific_abilities() | "数学75、语文50..." |
| `cognitive_parameters` | _build_cognitive_parameters() | "- 离开阈值：40%\n- 努力敏感性：80%..." |

### 状态变量

| 变量名 | 来源 | 示例值 |
|--------|------|--------|
| `current_time` | TimingSystem | "08:30" |
| `current_room` | perception | "教室（主教学区）" |
| `current_period` | TimelineState | "class_time" |
| `behavior_constraints` | _build_behavior_constraints() | "上课时间，需遵守课堂纪律" |

### 环境变量

| 变量名 | 来源 | 说明 |
|--------|------|------|
| `environment_info` | agent.generate_scene_description() | 完整场景描述 |
| `perceived_params` | PerceptionSystem | 贝叶斯感知结果 |
| `memories` | MemoryManager | 格式化记忆 |
| `activity_status` | _build_activity_status() | 当前活动状态 |

---

## 使用示例

### 示例1：构建决策Prompt

```gdscript
# 在AIAgent._make_decision()中
func _make_decision(perception: Dictionary) -> ActionRequest:
    # 构建Prompt
    var prompt = PromptBuilder.build_decision_prompt(self, perception)
    
    if prompt.is_empty():
        push_error("[AIAgent] Prompt构建失败")
        return ActionRequest.new(character.name, ActionRequest.ActionType.WAIT)
    
    # 调用LLM
    var response = await _call_local_llm(prompt)
    
    # 解析响应
    var request = _parse_decision_response(response)
    
    return request
```

### 示例2：构建对话回复Prompt

```gdscript
# 在对话系统中
func generate_reply(dialogue_context: Dictionary) -> Dictionary:
    var prompt = PromptBuilder.build_dialogue_reply_prompt(self, dialogue_context)
    
    var response = await _call_local_llm(prompt)
    
    # 解析JSON响应
    var json = JSON.new()
    json.parse(response)
    return json.get_data()
```

### 示例3：热更新模板

```gdscript
# 在调试面板中
func _on_reload_templates_button_pressed():
    PromptBuilder.clear_cache()
    print("模板缓存已清除，下次将重新加载")
```

### 示例4：自定义Prompt

```gdscript
# 加载自定义模板
var custom_template = PromptBuilder._load_template("custom_decision.txt")

# 构建自定义变量
var custom_vars = {
    "custom_var1": "value1",
    "custom_var2": "value2"
}

# 填充模板
var custom_prompt = PromptBuilder._fill_template(custom_template, custom_vars)
```

---

## 模板编写规范

### 变量命名

- 使用小写字母和下划线
- 使用描述性名称
- 示例：`current_time`, `agent_name`, `behavior_constraints`

### 段落结构

- 使用Markdown格式
- 使用三级标题（###）分隔段落
- 使用列表呈现结构化信息

### 输出格式

- 明确指定输出格式（JSON）
- 提供输出示例
- 说明每个字段的含义

### 注释

- 使用 `#` 添加注释
- 注释应解释"为什么"而非"是什么"

---

## 调试技巧

### 查看生成的Prompt

```gdscript
# 在AIAgent中添加调试输出
func _make_decision(perception: Dictionary) -> ActionRequest:
    var prompt = PromptBuilder.build_decision_prompt(self, perception)
    
    # 输出到控制台或文件
    print("=" * 50)
    print("生成的Prompt:")
    print(prompt)
    print("=" * 50)
    
    # ...
```

### 测试模板填充

```gdscript
# 测试特定变量
var test_vars = {
    "agent_name": "测试Agent",
    "current_time": "12:00"
}
var result = PromptBuilder._fill_template("{{agent_name}}在{{current_time}}", test_vars)
print(result)  # 输出: 测试Agent在12:00
```

---

*文档维护者：百舟楫*
*最后更新：2026-04-08*
