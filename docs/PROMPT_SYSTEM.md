# Prompt System 文档

**版本**: 2.0  
**创建时间**: 2026-04-08  
**状态**: V2统一管理模式

---

## 目录

1. [概述](#1-概述)
2. [Prompt文件结构](#2-prompt文件结构)
3. [Prompt详解](#3-prompt详解)
4. [加载机制](#4-加载机制)
5. [变量系统](#5-变量系统)
6. [扩展指南](#6-扩展指南)

---

## 1. 概述

本系统采用统一的Prompt文件管理模式，所有Prompt均从外部文件加载，便于：
- 热更新（无需重启游戏）
- 版本控制
- 多人协作
- A/B测试

### 设计原则

1. **文件化**: 所有Prompt存储在 `prompts/` 目录
2. **模板化**: 使用 `{{variable}}` 格式定义变量
3. **缓存化**: PromptBuilder缓存已加载的模板
4. **统一化**: 通过PromptBuilder集中管理

---

## 2. Prompt文件结构

```
prompts/
├── natural_decision_template.txt      # V2自然语言决策
├── dialogue_reply_template.txt        # 对话回复
├── decision_prompt_template.txt       # V1决策（已弃用）
└── fragments/
    └── basic_info_fragment.txt        # 基础信息片段

docs/prompts/
└── coordinator_prompt.md              # 协调器Prompt
```

---

## 3. Prompt详解

### 3.1 natural_decision_template.txt

**路径**: `prompts/natural_decision_template.txt`

**用途**: V2 Agent生成自然语言决策描述

**调用**: `PromptBuilder.build_natural_decision_prompt(agent, perception)`

**输入变量**:

| 变量 | 类型 | 说明 |
|------|------|------|
| `agent_name` | String | Agent名称 |
| `basic_info` | String | 基础信息（身份、性格等） |
| `current_room` | String | 当前场景 |
| `current_time` | String | 当前时间 |
| `current_period` | String | 当前时段 |
| `nearby_agents` | String | 附近角色列表 |
| `time_constraints` | String | 时间约束 |

**输出**: 自然语言字符串

**示例输出**:
```
我想去图书馆准备明天的数学考试
```

---

### 3.2 dialogue_reply_template.txt

**路径**: `prompts/dialogue_reply_template.txt`

**用途**: Agent在对话中决定是否回复及回复内容

**调用**: `PromptBuilder.build_dialogue_reply_prompt(agent, dialogue_context)`

**输入变量**:

| 变量 | 类型 | 说明 |
|------|------|------|
| `role_description` | String | 角色描述 |
| `agent_name` | String | Agent名称 |
| `basic_info` | String | 基础信息 |
| `big_five_traits` | String | 大五人格 |
| `mood_status` | String | 心情状态 |
| `dialogue_initiator` | String | 对话发起者 |
| `current_speaker` | String | 当前发言者 |
| `dialogue_range` | String | 对话范围 |
| `dialogue_duration` | String | 对话时长 |
| `dialogue_history` | String | 对话历史 |
| `heard_content` | String | 听到的内容 |
| `relationship_with_speaker` | String | 与发言者关系 |
| `topic_interest` | String | 话题兴趣 |
| `time_constraints` | String | 时间约束 |

**输出格式**:
```json
{
    "should_reply": true,
    "priority": 80,
    "reply_content": "回复内容",
    "reasoning": "决策理由",
    "emotion_tags": ["开心", "感兴趣"]
}
```

---

### 3.3 coordinator_prompt.md

**路径**: `docs/prompts/coordinator_prompt.md`

**用途**: Activity Coordinator调用LLM进行活动分配

**调用**: `ActivityCoordinator._build_coordination_prompt(input_data)`

**输入数据**:

```json
{
  "game_context": {
    "current_time": "08:30",
    "current_location": "学校",
    "period": "早自习"
  },
  "agents": [
    {
      "agent_id": "StudentXiaoming",
      "role": "student",
      "current_scene": "教室A",
      "current_position": {"x": 100, "y": 200},
      "current_state": "idle",
      "decision": "我想去图书馆准备明天的数学考试"
    }
  ],
  "available_activities": ["MOVE_TO", "NORMAL_DIALOGUE", ...],
  "scene_constraints": {
    "classroom": ["LISTEN", "QA_TEACHER", "GROUP_DISCUSSION"],
    "library": ["SELF_STUDY"]
  }
}
```

**核心功能**:
- 解析自然语言决策
- 检测双向奔赴
- 分配活动序列（最多3步）
- 计算目标坐标

**双向奔赴规则**:
```
IF (A想和B互动) AND (B想和A互动):
    → 双向奔赴，分配共同目标位置
ELSE:
    → 各自独立执行
```

---

### 3.4 basic_info_fragment.txt

**路径**: `prompts/fragments/basic_info_fragment.txt`

**用途**: 基础信息片段，被其他Prompt引用

**变量**:
- `position`: 身份
- `personality`: 性格
- `speaking_style`: 说话风格
- `work_duties`: 职责
- `work_habits`: 行为特点
- `age`: 年龄
- `gender`: 性别
- `grade`: 年级
- `family_structure`: 家庭结构
- `socioeconomic_status`: 经济状况
- `only_child`: 是否独生子女

---

## 4. 加载机制

### 4.1 PromptBuilder

**单例**: 静态类，无需实例化

**核心方法**:

```gdscript
# 构建V2自然语言决策Prompt
static func build_natural_decision_prompt(agent: AIAgent, perception: Dictionary) -> String

# 构建对话回复Prompt
static func build_dialogue_reply_prompt(agent: AIAgent, dialogue_context: Dictionary) -> String

# 清除缓存（热更新用）
static func clear_cache()
```

### 4.2 缓存机制

```gdscript
static var template_cache: Dictionary = {}  # path -> content

# 首次加载后缓存，后续直接从内存读取
```

### 4.3 加载流程

```
调用 build_xxx_prompt()
    ↓
_load_template(filename)
    ↓
检查 template_cache
    ↓
已缓存 → 直接返回
未缓存 → FileAccess.open() → 读取 → 缓存 → 返回
    ↓
_fill_template(template, variables)
    ↓
替换所有 {{variable}} 为实际值
    ↓
返回完整Prompt
```

---

## 5. 变量系统

### 5.1 变量格式

使用双大括号包裹: `{{variable_name}}`

### 5.2 变量构建

在PromptBuilder中统一构建：

```gdscript
var variables = {}
variables["agent_name"] = agent.character.name
variables["current_time"] = TimingSystem.instance.format_time(...)
// ... 更多变量

return _fill_template(template, variables)
```

### 5.3 变量缺失处理

如果模板中存在未定义的变量，将保持原样（`{{variable}}`）

---

## 6. 扩展指南

### 6.1 添加新Prompt

1. **创建模板文件** `prompts/new_prompt_template.txt`
2. **定义变量** 使用 `{{variable}}` 格式
3. **添加构建方法** 在PromptBuilder中:
   ```gdscript
   static func build_new_prompt(agent: AIAgent, context: Dictionary) -> String:
       var template = _load_template("new_prompt_template.txt")
       var variables = {}
       // 构建变量
       return _fill_template(template, variables)
   ```
4. **调用** 在AIAgent中使用

### 6.2 修改现有Prompt

直接编辑模板文件，无需重启（下次加载自动生效）

或使用热更新:
```gdscript
PromptBuilder.clear_cache()  # 清除缓存，强制重新加载
```

### 6.3 添加变量

1. 在模板中添加 `{{new_variable}}`
2. 在PromptBuilder的构建方法中添加:
   ```gdscript
   variables["new_variable"] = value
   ```

---

## 附录

### A. 文件清单

| 文件 | 路径 | 说明 |
|------|------|------|
| natural_decision_template.txt | prompts/ | V2自然语言决策 |
| dialogue_reply_template.txt | prompts/ | 对话回复 |
| decision_prompt_template.txt | prompts/ | V1决策（已弃用） |
| basic_info_fragment.txt | prompts/fragments/ | 基础信息片段 |
| coordinator_prompt.md | docs/prompts/ | 协调器Prompt |
| PromptBuilder.gd | script/ai/ | Prompt构建器 |

### B. 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 2.0 | 2026-04-08 | V2统一管理模式，添加natural_decision_template.txt |
| 1.0 | - | V1初始版本 |

---

_文档结束_
