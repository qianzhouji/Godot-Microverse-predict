# Activity System V2 集成测试配置指南

**创建时间**: 2026-04-08

---

## 前置条件

1. **Ollama已安装并运行**
   ```bash
   ollama serve
   ```

2. **模型已下载**
   ```bash
   ollama pull qwen2.5:7b
   ```

3. **Godot 4.x 已安装**

---

## 场景配置步骤

### 步骤1: 添加 ActivityManager

1. 打开 `scene/maps/School.tscn`
2. 在场景树根节点下添加子节点
3. 节点名: `ActivityManager`
4. 脚本: `script/system/ActivityManager.gd`

### 步骤2: 添加 ActivityCoordinator

1. 在场景树根节点下添加子节点
2. 节点名: `ActivityCoordinator`
3. 脚本: `script/system/ActivityCoordinator.gd`

### 步骤3: 确认现有系统节点

确保以下节点已存在:
- `TimingSystem` (已有)
- `TimelineState` (已有)
- `RoomManager` (已有)
- `RewardSystem` (需要确认)

### 步骤4: 添加 RewardSystem (如缺失)

1. 添加子节点
2. 节点名: `RewardSystem`
3. 脚本: `script/system/RewardSystem.gd`

---

## 测试Agent配置

选择2-3个Agent进行测试:

推荐测试角色:
- `StudentXiaoming` (抑郁风险学生)
- `StudentXiaohong` (健康学生)
- `TeacherWang` (教师)

确保这些角色:
1. 已添加到场景中
2. 有AIAgent脚本
3. 有CharacterPersonality配置

---

## 启动测试

### 方法1: 通过Godot编辑器

1. 按F5运行场景
2. 观察控制台输出
3. 检查是否有错误

### 方法2: 通过代码启动

在School场景的`_ready()`中添加:
```gdscript
func _ready():
    # 等待所有系统初始化
    await get_tree().create_timer(1.0).timeout
    
    # 启动时序系统
    if TimingSystem.instance:
        TimingSystem.instance.start_day(1)
        print("[School] 第1天开始")
```

---

## 验证检查清单

### 系统初始化
- [ ] TimingSystem 初始化完成
- [ ] TimelineState 初始化完成
- [ ] ActivityManager 初始化完成
- [ ] ActivityCoordinator 初始化完成
- [ ] RewardSystem 初始化完成

### 第一次Click
- [ ] Click #1 正常触发
- [ ] Agent生成自然语言决策
- [ ] Agent提交决策到协调器
- [ ] 协调器调用LLM成功
- [ ] Agent接收活动序列

### 活动执行
- [ ] Agent执行MOVE_TO
- [ ] Agent到达目标位置
- [ ] ActivityManager记录活动

### 后续Click
- [ ] Click #2 正常触发
- [ ] ActivityManager更新活动状态
- [ ] 累积奖赏计算正确

---

## 常见问题

### Q1: LLM调用超时
**解决**: 首次调用可能较慢，等待模型加载完成

### Q2: Agent不移动
**解决**: 检查Character节点是否有NavigationAgent2D

### Q3: 协调器找不到Agent
**解决**: 确保Agent在"character"组中

### Q4: 活动不执行
**解决**: 检查activity_cache是否正确接收

---

## 测试通过标准

- [ ] 控制台无红色错误
- [ ] Agent生成自然语言决策
- [ ] 协调器成功分配活动
- [ ] Agent执行活动并移动
- [ ] 专注度影响奖赏计算

---

*文档维护者: 百舟楫*
