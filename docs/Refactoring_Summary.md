# Godot-Microverse-predict 项目重构总结

> **重构时间**: 2026-04-06 至 2026-04-07
> **项目**: 抑郁风险学生模拟系统
> **仓库**: https://github.com/qianzhouji/Godot-Microverse-predict

---

## 一、重构背景

原系统采用传统的1对1对话系统和随机任务生成，缺乏统一的时序管理和精确的对话范围控制。新架构引入中央时序系统、中范围划分和广播式对话，实现更真实的学校场景模拟。

---

## 二、架构变革

### 原架构 vs 新架构

| 方面 | 原架构 | 新架构 |
|------|--------|--------|
| 时序管理 | 各Agent独立定时器 | 中央时序系统（5分钟Click周期） |
| 对话系统 | 1对1直接对话 | 广播式对话（行为/内容分离） |
| 空间感知 | 距离阈值判断 | 中范围划分（4象限/左右/单区） |
| 任务生成 | 随机生成 | 课程表驱动 |
| Prompt管理 | 硬编码在代码中 | 配置文件+模板分离 |

---

## 三、已完成工作

### 1. 中央时序系统（100%）

#### 核心文件
| 文件 | 路径 | 功能 |
|------|------|------|
| TimingSystem.gd | `script/system/TimingSystem.gd` | 全局时钟+Click触发+请求队列 |
| TimelineState.gd | `script/system/TimelineState.gd` | 课程表+行为约束+时间状态 |
| ActionRequest.gd | `script/data/ActionRequest.gd` | 行动请求数据结构 |

#### 关键特性
- **Click周期**: 5分钟游戏时间一个Click
- **上升沿触发**: 所有Agent活动同步在Click时刻执行
- **请求缓存**: 决策→缓存→Click执行的两步机制
- **课程表驱动**: 6节课的时间安排和行为约束
- **放学机制**: 17:00后只接受结束请求，17:30强制结束

#### 课程表
| 时间 | 活动 | 位置 |
|------|------|------|
| 8:00 | 班主任课 | 教室（主教学区） |
| 8:55 | 英语课 | 教室（主教学区） |
| 9:50 | 小组讨论 | 教室（小组讨论区） |
| 10:45 | 午休 | 食堂 |
| 11:45 | 数学课 | 教室（主教学区） |
| 12:40 | 体育活动 | 体育馆 |

---

### 2. AIAgent核心重构（95%）

#### 核心文件
| 文件 | 路径 | 功能 |
|------|------|------|
| AIAgent.gd | `script/ai/AIAgent.gd` | Agent认知循环+行动执行 |
| AIAgent_backup_20250406.gd | `script/ai/AIAgent_backup_20250406.gd` | 原AIAgent备份 |

#### 认知循环（4阶段）
```
感知(Perceiving) → 体验(Experiencing) → 决策(Deciding) → 执行(Executing)
     │                    │                    │                  │
     ▼                    ▼                    ▼                  ▼
收集场景信息        贝叶斯更新信念       生成ActionRequest    在Click时刻执行
```

#### Agent状态（8种）
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

#### 行动类型（10种）
```gdscript
enum ActionType {
    MOVE_TO_RANGE,      # 移动（编号1）
    START_DIALOGUE,     # 开始普通对话
    START_WHISPER,      # 开始悄悄话
    JOIN_DIALOGUE,      # 加入对话
    EXIT_DIALOGUE,      # 退出对话
    START_SPORTS,       # 开始体育活动
    END_SPORTS,         # 结束体育活动
    START_STUDY,        # 开始自习
    END_STUDY,          # 结束自习
    WAIT                # 等待
}
```

#### 移动系统
**定位函数** (`_calculate_move_target`):
- 输入: 目标名称（子场景名或角色名）+ 是否悄悄话
- 输出: 目标坐标 Vector2
- 逻辑:
  - 悄悄话模式 → 贴身位置（±15px）
  - 同一中范围 → 目标身边小范围（±30px）
  - 不同中范围 → 目标中范围中心（±20%）

**移动输出格式**:
```
"1 目标名称"
```
- `1` - 移动行动编号
- ` ` - 一个空格
- `目标名称` - 场景精确名称或人物精确全名

**示例**:
- `1 教室（主教学区）` - 移动到该场景
- `1 小明` - 移动到小明附近
- `1 小红` - 移动到小红附近（悄悄话时贴身）

#### 中范围划分系统

**划分规则**:
| 房间类型 | 划分方式 | 说明 |
|---------|---------|------|
| 教室/图书馆/自习室/食堂 | 4象限 | 右上1、左上2、左下3、右下4 |
| 大走廊 | 左右2区 | 左区、右区 |
| 小走廊 | 单区域 | 中心区域 |

**象限定义**（平面直角坐标系）:
```
y↑
 │  第2象限  │  第1象限
 │   (左上)  │  (右上)
─┼───────────┼──────────→x
 │  第3象限  │  第4象限
 │   (左下)  │  (右下)
```

**关键函数**:
- `_is_in_same_medium_range()` - 判断是否同一中范围
- `_get_quadrant_at_position()` - 获取位置所在象限（1-4）
- `_get_left_right_zone_at_position()` - 获取左右分区
- `_get_medium_range_description()` - 获取中范围描述字符串
- `_get_medium_range_center_position()` - 获取中范围中心位置

#### 两步缓存验证
```
Step1: 决策生成ActionRequest
    │
    ▼
执行移动（如果需要）
    │
    ▼
Step2: 验证缓存的有效性
    - 目标是否仍然存在？
    - 时间约束是否变化？
    │
    ├── 有效 → 执行Step2
    └── 无效 → 重新决策
```

#### 本地LLM集成
- **API端点**: `http://localhost:11434/api/generate`
- **默认模型**: `qwen2.5:14b`
- **温度**: 0.7
- **最大token**: 500
- **调用方式**: 非流式JSON响应

---

### 3. Prompt系统（100%）

#### 核心文件
| 文件 | 路径 | 功能 |
|------|------|------|
| decision_prompt_template.txt | `prompts/decision_prompt_template.txt` | 决策Prompt模板 |
| dialogue_reply_template.txt | `prompts/dialogue_reply_template.txt` | 对话回复模板 |
| PromptBuilder.gd | `script/ai/PromptBuilder.gd` | Prompt构建器 |

#### 决策Prompt模板结构
1. **角色定义** - 基本信息、人格特质、心理状态
2. **认知参数** - MVT模型参数（S, a, β_effort等）
3. **当前状态** - 时间、位置、时段、约束
4. **周围环境** - 所有场景列表、当前场景、中范围划分
5. **感知参数** - 贝叶斯感知结果
6. **记忆** - 相关记忆
7. **活动状态** - 当前进行的活动
8. **决策指令** - 行动选择原则、输出格式、示例

#### 中范围划分说明（Prompt中）
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

#### 场景描述生成
**输出格式**:
```
【所有可用场景】
- 教室（主教学区）：教室的北侧是主教学区...
- 食堂：提供午餐的场所...
...

【当前场景】
你当前所在场景：教室（主教学区）
场景功能：教室的北侧是主教学区...

【你对当前情境的感知】
- 你觉得这个情境一开始能获得的收益：50%（中等）
- 你觉得收益消耗的速度：40%（较慢）

【场景内角色】
你当前所在中范围：第2象限

【同一中范围内（可普通对话）】
- 小明（学生）
- 小红（学生）

【其他中范围（需移动才能对话）】
第1象限:
  - 小刚（学生），距离约180米
第4象限:
  - 老师（教师），距离约220米

【时间信息】
现在是上课时间,班主任课正在进行中。
```

#### 对话类型区分
| 类型 | 移动要求 | 说明 |
|------|---------|------|
| **普通对话** | 同一中范围无需移动 | 公开对话，范围内可见 |
| **悄悄话** | 必须移动到贴身位置（±15px） | 私密对话，仅双方可见 |

---

### 4. 保留的系统（无需修改）

| 系统 | 文件 | 说明 |
|------|------|------|
| 感知系统 | `PerceptionSystem.gd` | 贝叶斯感知，主观参数估计 |
| 奖赏接收 | `AgentRewardReceiver.gd` | 接收系统层奖赏信号 |
| 记忆管理 | `MemoryManager.gd` | 记忆存储与检索 |
| 每日反思 | `DailyReflectionSystem.gd` | 日终反思与情感更新 |
| 动态人格 | `DynamicPersonality.gd` | 人格特质动态变化 |
| 角色控制 | `CharacterController.gd` | 移动控制（原项目）|
| 房间管理 | `RoomManager.gd` | 房间数据管理 |

---

## 四、舍弃的旧系统

| 旧系统 | 文件 | 替代方案 |
|--------|------|---------|
| 旧任务系统 | TaskManager.gd（原） | TimelineState + 新课程表驱动 |
| 1对1对话 | ConversationManager.gd | 广播式DialogueManager（待实现）|
| 旧对话管理 | DialogManager.gd, DialogService.gd | 新DialogueManager（待实现）|
| 随机移动 | 旧移动逻辑 | 精准路径+中范围划分 |

---

## 五、待完成工作

### 高优先级

#### 1. ActivityManager（活动管理与奖赏计算）
- 活动注册与结束
- 基于场景参数计算客观奖赏
- 与RewardSystem集成
- 活动时长追踪

#### 2. DialogueManager（对话生命周期管理）
- 对话注册与销毁
- 发言优先级队列
- 行为与内容分离广播
- 教师监控能力（大范围对话）

#### 3. 测试与调试
- 启动时序系统
- 验证Click触发
- 测试Agent认知循环
- 测试移动功能
- 测试对话功能

### 中优先级

#### 4. 情感关系系统
- 情感类型定义（FRIENDSHIP/ROMANTIC_LOVE/RESPECT/TRUST/RIVALRY/INDIFFERENCE）
- DailyReflectionSystem集成
- 情感影响决策

#### 5. UI和调试工具
- 时序系统状态面板
- Agent状态实时监控
- 对话状态监控

### 低优先级

#### 6. 性能优化
- API调用批处理
- 决策缓存机制
- 并发处理优化

---

## 六、关键设计决策

### 1. 时序系统
- **5分钟Click周期**: 平衡实时性和计算开销
- **上升沿触发**: 所有Agent同步执行，避免竞态条件
- **请求缓存**: 决策和执行分离，支持复杂计划

### 2. 对话系统
- **行为/内容分离**: 行为全子场景可见，内容仅范围内可见
- **三层范围**: 大范围（教师）、中范围（4象限/左右）、小范围（贴身）
- **悄悄话机制**: 必须贴身，私密性强

### 3. 移动系统
- **精准定位**: 中范围中心+随机偏移
- **智能判断**: 自动识别场景名vs角色名
- **距离自适应**: 同一中范围贴身，不同中范围到中心

### 4. Prompt管理
- **模板分离**: 配置文件+代码分离，支持热更新
- **详细说明**: 中范围规则、输出格式、决策示例
- **场景感知**: 完整的环境描述，包括中范围信息

---

## 七、技术栈

| 组件 | 技术 |
|------|------|
| 游戏引擎 | Godot 4.x |
| 编程语言 | GDScript |
| AI模型 | Ollama本地服务 (qwen2.5:14b) |
| API端点 | http://localhost:11434/api/generate |
| 版本控制 | Git + GitHub |

---

## 八、项目结构

```
/Users/yuke/Desktop/Godot Microverse/Microverse/
├── script/
│   ├── ai/
│   │   ├── AIAgent.gd                    # Agent核心（重构后）
│   │   ├── AIAgent_backup_20250406.gd    # 原AIAgent备份
│   │   ├── PerceptionSystem.gd           # 感知系统（保留）
│   │   ├── AgentRewardReceiver.gd        # 奖赏接收（保留）
│   │   ├── PromptBuilder.gd              # Prompt构建器
│   │   ├── memory/
│   │   │   └── MemoryManager.gd          # 记忆管理（保留）
│   │   └── ...
│   ├── system/
│   │   ├── TimingSystem.gd               # 时序系统（新增）
│   │   └── TimelineState.gd              # 时间轴状态（新增）
│   ├── data/
│   │   └── ActionRequest.gd              # 行动请求（新增）
│   ├── CharacterController.gd            # 角色控制（保留）
│   └── ...
├── prompts/
│   ├── decision_prompt_template.txt      # 决策Prompt（新增）
│   ├── dialogue_reply_template.txt       # 对话Prompt（新增）
│   └── fragments/                        # Prompt片段
├── scene/
│   ├── maps/School.tscn                  # 主场景
│   └── characters/                       # 角色场景
├── docs/
│   ├── File_Location_Index.md            # 文件位置索引
│   ├── Progress_Report.md                # 进度报告
│   └── Refactoring_Summary.md            # 本文件
└── TODOLIST.md                           # 任务清单
```

---

## 九、Git提交历史

| 提交 | 说明 |
|------|------|
| 327315b | 更新决策Prompt模板：强调无需移动即可行动 |
| a94842c | 修复移动实现：使用CharacterController的move_to方法 |
| 24ec304 | 添加项目文件位置索引文档 |
| 1ca6a71 | 添加项目重构进度报告 |
| 93a9453 | 填充AIAgent工具函数 |
| d8f9fc5 | 删除未使用的 _choose_random_target() 函数 |
| ed86a36 | 完善移动系统：实现中范围ID到坐标的转换 |
| 2c82d76 | 删除未使用的 _get_direction_description() 函数 |
| 06f8e4c | 重构移动系统：实现新的定位函数 |
| ba8df68 | 重构场景描述和移动系统，添加悄悄话功能 |
| 59a7e3c | 实现完整的中范围划分系统 |
| bfd6c59 | 修复移动函数：支持悄悄话模式参数传递 |

---

## 十、下一步行动

### 推荐顺序
1. **实现ActivityManager** - 完成体验闭环
2. **实现DialogueManager** - 完成对话系统
3. **集成测试** - 验证整体功能
4. **情感关系系统** - 完善社交机制

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

*文档生成时间: 2026-04-07*
*最后更新: 2026-04-07*
