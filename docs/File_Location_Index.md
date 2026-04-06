# 项目文件位置索引

> **项目根目录**: `/Users/yuke/Desktop/Godot Microverse/Microverse/`

---

## 一、核心系统文件

### 1. 中央时序系统
| 文件 | 路径 | 说明 |
|------|------|------|
| TimingSystem.gd | `script/system/TimingSystem.gd` | 全局时钟 + Click触发 |
| TimelineState.gd | `script/system/TimelineState.gd` | 课程表 + 行为约束 |
| ActionRequest.gd | `script/data/ActionRequest.gd` | 行动请求数据结构 |

### 2. AI核心
| 文件 | 路径 | 说明 |
|------|------|------|
| AIAgent.gd | `script/ai/AIAgent.gd` | Agent认知循环（重构后） |
| AIAgent_backup_20250406.gd | `script/ai/AIAgent_backup_20250406.gd` | 原AIAgent备份 |
| PromptBuilder.gd | `script/ai/PromptBuilder.gd` | Prompt构建器 |

### 3. 感知与体验（保留）
| 文件 | 路径 | 说明 |
|------|------|------|
| PerceptionSystem.gd | `script/ai/PerceptionSystem.gd` | 贝叶斯感知系统 |
| AgentRewardReceiver.gd | `script/ai/AgentRewardReceiver.gd` | 奖赏接收器 |
| MemoryManager.gd | `script/ai/memory/MemoryManager.gd` | 记忆管理 |
| DailyReflectionSystem.gd | `script/ai/DailyReflectionSystem.gd` | 每日反思 |
| DynamicPersonality.gd | `script/ai/DynamicPersonality.gd` | 动态人格 |

### 4. 角色控制（原项目）
| 文件 | 路径 | 说明 |
|------|------|------|
| CharacterController.gd | `script/CharacterController.gd` | 角色移动控制器 |
| CharacterManager.gd | `script/CharacterManager.gd` | 角色管理 |
| RoomManager.gd | `script/RoomManager.gd` | 房间管理 |
| RoomArea.gd | `script/RoomArea.gd` | 房间区域 |

---

## 二、场景文件

### 主场景
| 文件 | 路径 | 说明 |
|------|------|------|
| School.tscn | `scene/maps/School.tscn` | 学校主场景 |

### 角色场景（示例）
| 文件 | 路径 | 说明 |
|------|------|------|
| StudentXiaoming.tscn | `scene/characters/StudentXiaoming.tscn` | 学生小明 |
| TeacherWang.tscn | `scene/characters/TeacherWang.tscn` | 王老师 |
| ... | `scene/characters/` | 其他角色 |

---

## 三、Prompt模板

| 文件 | 路径 | 说明 |
|------|------|------|
| decision_prompt_template.txt | `prompts/decision_prompt_template.txt` | 决策Prompt模板 |
| dialogue_reply_template.txt | `prompts/dialogue_reply_template.txt` | 对话回复模板 |
| basic_info_fragment.txt | `prompts/fragments/basic_info_fragment.txt` | 基础信息片段 |

---

## 四、文档

| 文件 | 路径 | 说明 |
|------|------|------|
| TODOLIST.md | `TODOLIST.md` | 重构任务清单 |
| Phase1_TimingSystem_Implementation.md | `docs/Phase1_TimingSystem_Implementation.md` | 第一阶段实施计划 |
| Phase2_AIAgent_Refactor_Plan.md | `docs/Phase2_AIAgent_Refactor_Plan.md` | 第二阶段实施计划 |
| AIAgent_Refactor_Analysis.md | `docs/AIAgent_Refactor_Analysis.md` | AIAgent重构分析 |
| AIAgent_Timing_Logic.md | `docs/AIAgent_Timing_Logic.md` | 时序逻辑文档 |

---

## 五、关键函数位置

### 5.1 时序系统
```gdscript
# TimingSystem.gd
func start_day(day: int)           # 启动一天
func _trigger_click()              # 触发Click
func submit_action_request()       # 提交行动请求
func _execute_pending_requests()   # 执行待处理请求
```

### 5.2 AIAgent核心
```gdscript
# AIAgent.gd
func _on_click_triggered()         # Click回调入口
func _perform_cognitive_cycle()    # 认知循环
func _perceive()                   # 感知阶段
func _experience()                 # 体验阶段
func _make_decision()              # 决策阶段
func _execute_action()             # 执行阶段

# 8个行动执行
func _execute_move()               # 移动
func _execute_start_dialogue()     # 开始对话
func _execute_join_dialogue()      // 加入对话
func _execute_exit_dialogue()      // 退出对话
func _execute_start_sports()       // 开始体育
func _execute_end_sports()         // 结束体育
func _execute_start_study()        // 开始自习
func _execute_end_study()          // 结束自习
```

### 5.3 Prompt构建
```gdscript
# PromptBuilder.gd
static func build_decision_prompt()     // 构建决策Prompt
static func build_dialogue_reply_prompt() // 构建对话Prompt
static func _load_template()            // 加载模板文件
static func _fill_template()            // 填充变量
```

### 5.4 角色移动（原项目）
```gdscript
# CharacterController.gd
func move_to(target: Vector2)           // 设置移动目标
func _calculate_avoidance_direction()   // 计算避障方向
func _is_direction_clear()              // 检测方向是否通畅
func _check_if_stuck()                  // 检测是否卡住
```

### 5.5 感知系统
```gdscript
# PerceptionSystem.gd
static func perceive_gain()             // 感知收益（加噪声）
static func add_sample()                // 添加观测样本
static func _update_beliefs()           // 贝叶斯更新
static func get_perceived_params()      // 获取感知参数
```

---

## 六、快速访问命令

```bash
# 进入项目目录
cd "/Users/yuke/Desktop/Godot Microverse/Microverse"

# 查看核心AI文件
ls -la script/ai/*.gd

# 查看系统文件
ls -la script/system/*.gd

# 查看Prompt模板
ls -la prompts/

# 查看角色场景
ls -la scene/characters/

# 查看文档
ls -la docs/
```

---

## 七、文件关系图

```
School.tscn
├── TimingSystem (Node)
│   └── TimelineState (Node)
├── RoomManager (Node2D)
└── 角色实例 (CharacterBody2D)
    ├── AnimatedSprite2D
    ├── CollisionShape2D
    └── AIAgent (Node) [脚本]
        ├── AgentRewardReceiver [组件]
        └── 连接到 TimingSystem.signal

script/ai/AIAgent.gd
├── 调用 PromptBuilder.build_decision_prompt()
├── 调用 PerceptionSystem.get_perceived_params()
├── 调用 MemoryManager.get_formatted_memories()
└── 调用 character.move_to() [CharacterController]

prompts/
├── decision_prompt_template.txt [模板文件]
└── dialogue_reply_template.txt [模板文件]
```

---

*最后更新: 2026-04-06*
