# Activity System V2 实施计划

**创建时间**: 2026-04-08  
**目标**: 重构活动系统为中央协调式架构，引入自由决策+系统分配模式

---

## 架构概览

```
【决策阶段】每个Agent独立进行
Agent → LLM(prompt含意图+环境) → 自然语言决策("我想去图书馆自习")

          ↓ 所有决策上报

【协调阶段】ActivityManager集中处理
ActivityManager → LLM(所有决策+基础活动表+场景约束) → 活动分配方案
                  • 解析每个Agent意图
                  • 映射到基础活动或组合
                  • 检查场景/状态约束
                  • 处理冲突

          ↓ 分配结果下发各Agent

【缓存阶段】各Agent存储
Agent → 接收分配的活动序列（最多3步）→ 存入action_cache

          ↓ 等待Click触发

【执行阶段】Click上升沿
TimingSystem → 所有Agent同步执行缓存的Step1
             → 验证Step2有效性
             → 继续执行或等待下次Click
```

---

## 核心机制

### 1. 基础活动表

| 活动ID | 名称 | 场景限制 | 专注度 | 参数 |
|--------|------|----------|--------|------|
| `move_to` | 移动 | 无 | - | target_location |
| `normal_dialogue` | 普通对话 | 无 | - | target_agent, topic |
| `whisper` | 悄悄话 | 无 | - | target_agent, content |
| `listen` | 聆听 | 仅限上课 | 30/65/100 | - |
| `qa_teacher` | 提问/回答 | 仅限上课 | 30/65/100 | question/answer |
| `self_study` | 自习 | 图书馆/自习室 | 30/65/100 | subject |
| `sports` | 体育活动 | 体育馆 | 30/65/100 | sport_type |
| `group_discussion` | 小组讨论 | 教室/讨论室 | 30/65/100 | topic, members |

### 2. 专注度机制

```
实际努力 = 基础努力 × 专注度比例
实际奖赏 = 理论奖赏 × 专注度比例

信息接收（对话类）：
接收内容比例 = 专注度比例
```

### 3. 三步缓存

每个Agent可缓存最多3步活动，支持复杂活动组合：
- 例: [移动到教室] → [开始小组讨论] → [专注度65%参与]

---

## 实施阶段

### 阶段一：基础活动系统 🔄

| 任务 | 状态 | 文件 | 备注 |
|------|------|------|------|
| 定义活动数据结构 | ✅ 已完成 | `script/system/Activity.gd` | Activity类，8种活动类型，专注度机制 |
| 重构基础活动实现 | ✅ 已完成 | `script/system/MovementExecutor.gd` | 移动功能封装为Activity |
| 更新ActivityManager | ✅ 已完成 | `script/system/ActivityManager.gd` | 活动注册表+移动创建接口 |
| 更新AIAgent模型配置 | ✅ 已完成 | `script/ai/AIAgent.gd` | qwen2.5:14b → qwen2.5:7b |

**预计耗时**: 1-2天

---

### 阶段二：中央协调LLM ✅

| 任务 | 状态 | 文件 | 备注 |
|------|------|------|------|
| 设计协调Prompt | ✅ 已完成 | `docs/prompts/coordinator_prompt.md` | 完整Prompt模板，含示例和规则 |
| 实现协调器 | ✅ 已完成 | `script/system/ActivityCoordinator.gd` | LLM调用、解析、活动下发 |
| 本地LLM接入 | ✅ 已完成 | `ActivityCoordinator.gd` | Ollama配置，qwen2.5:7b |

**预计耗时**: 2-3天

---

### 阶段三：Agent改造 ✅

| 任务 | 状态 | 文件 | 备注 |
|------|------|------|------|
| 修改决策逻辑 | ✅ 已完成 | `script/ai/AIAgent.gd` | 自然语言决策，提交协调器 |
| 三步缓存系统 | ✅ 已完成 | `script/ai/AIAgent.gd` | activity_cache数组，最多3步 |
| 活动执行接口 | ✅ 已完成 | `script/ai/AIAgent.gd` | 8种活动执行方法 |
| V1兼容保留 | ✅ 已完成 | `script/ai/AIAgent.gd` | 原逻辑保留用于回退 |

**预计耗时**: 1-2天

---

### 阶段四：专注度与信息机制 ✅

| 任务 | 状态 | 文件 | 备注 |
|------|------|------|------|
| 专注度系统 | ✅ 已完成 | `script/system/ActivityManager.gd` | 奖赏计算应用专注度比例 |
| 信息接收机制 | ✅ 已完成 | `script/system/InformationReceiver.gd` | 专注度过滤对话内容 |
| Agent集成 | ✅ 已完成 | `script/ai/AIAgent.gd` | 信息接收器创建，对话方法集成 |

**预计耗时**: 1-2天

---

## 当前完成状态总结

**总体进度**: 80%  
**已完成阶段**: 一、二、三、四  
**待完成**: 阶段五（集成测试）

---

### 阶段五：集成测试 ⏳

| 任务 | 状态 | 文件 | 备注 |
|------|------|------|------|
| 端到端测试 | ⏳ 待开始 | - | 多Agent协调场景 |
| 冲突处理测试 | ⏳ 待开始 | - | 资源竞争场景 |
| 性能优化 | ⏳ 待开始 | - | LLM调用优化 |

**预计耗时**: 1-2天

---

## 当前进度

**总体进度**: 60%  
**当前阶段**: 阶段四 - 专注度与信息机制  
**最后更新**: 2026-04-08

---

## 已完成脚本清单

### 核心数据结构
| 文件 | 功能 | 关键类/函数 |
|------|------|-------------|
| `script/system/Activity.gd` | 活动数据结构 | `Activity`类, 8种活动类型枚举, 专注度机制, 工厂方法 |

### 执行器
| 文件 | 功能 | 关键类/函数 |
|------|------|-------------|
| `script/system/MovementExecutor.gd` | 移动执行 | `MovementExecutor`类, `execute_move_activity()`, 导航/直线移动 |

### 管理器
| 文件 | 功能 | 关键类/函数 |
|------|------|-------------|
| `script/system/ActivityManager.gd` | 活动管理 | 活动注册表, 场景约束, 专注度奖赏计算, 生命周期管理 |
| `script/system/ActivityCoordinator.gd` | 中央协调 | `submit_decision()`, `execute_coordination()`, LLM调用, 活动下发 |

### 信息接收
| 文件 | 功能 | 关键类/函数 |
|------|------|-------------|
| `script/system/InformationReceiver.gd` | 信息过滤 | `InformationReceiver`类, `receive_dialogue()`, `receive_lecture()`, 专注度过滤 |

### Agent
| 文件 | 功能 | 关键类/函数 |
|------|------|-------------|
| `script/ai/AIAgent.gd` | Agent核心 | `activity_cache`(3步), `information_receiver`, `_make_natural_decision()`, `receive_activity_sequence()`, 8种`_execute_v2_*()`方法 |

### 配置
| 文件 | 功能 | 内容 |
|------|------|------|
| `docs/prompts/coordinator_prompt.md` | 协调器Prompt | 输入/输出格式, 决策规则, 示例 |

---

## 技术配置

- ✅ 本地LLM: Ollama
- ✅ 模型: qwen2.5:7b
- ✅ API端点: http://localhost:11434
- ✅ 统一模型: Agent决策和协调器使用同一模型

---

## 变更日志

| 日期 | 变更 |
|------|------|
| 2026-04-08 | 创建本文档，完成阶段一、二、三 |

---

## 设计决策记录

### 双向奔赴机制 (2026-04-08)

**决策：** 只有双方意图匹配时才协调，否则各自独立行动

**场景处理：**

| 场景 | 处理方式 | 结果 |
|------|----------|------|
| A想和B悄悄话 + B想和A悄悄话 | ✅ 协调 | 分配共同目标点，双向奔赴 |
| A想和B悄悄话 + B想和C悄悄话 | ❌ 不协调 | A去B原位置，B去C位置，A扑空 |
| A想和B对话 + B想和A讨论 | ✅ 协调 | 协调为共同活动 |

**现实模拟效果：**
- 双方都想互动 → 完美相遇，愉悦情绪
- 单方意图 → 扑空，失落/困惑情绪
- 符合真实社交动态，Agent自主感知和反应

**实现：**
- `ActivityCoordinator._detect_mutual_intentions()` - 检测双向奔赴
- `ActivityCoordinator._apply_mutual_coordination()` - 协调共同位置

---

## 问题修复记录

### 2026-04-08 逻辑检查与修复

| 问题 | 描述 | 修复方案 |
|------|------|----------|
| **协调器触发缺失** | Agent提交决策后无人调用execute_coordination() | TimingSystem._trigger_click()中添加协调触发逻辑 |
| **MovementExecutor未更新** | 移动执行器需要每帧更新 | AIAgent._physics_process()中添加movement_executor.update(delta) |
| **RewardSystem缺少V2接口** | 需要distribute_reward_with_context支持专注度 | RewardSystem中添加新方法 |

---

_本文档随开发进度持续更新_
