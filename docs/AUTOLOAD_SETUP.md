# AutoLoad配置说明 - RewardSystem

> **创建日期**: 2026-04-05
> **用途**: 指导如何在Godot编辑器中配置RewardSystem为AutoLoad单例

---

## 配置步骤

### 步骤1: 打开项目设置

1. 打开Godot编辑器
2. 点击顶部菜单 **"项目" → "项目设置"** (或按 `Shift+Ctrl+S`)

### 步骤2: 切换到AutoLoad标签

1. 在项目设置窗口中，点击顶部的 **"AutoLoad"** 标签

### 步骤3: 添加RewardSystem

1. 在路径输入框中，输入或选择：
   ```
   res://script/system/RewardSystem.gd
   ```

2. 在节点名称输入框中，输入：
   ```
   RewardSystem
   ```

3. 点击 **"添加"** 按钮

### 步骤4: 调整加载顺序（重要）

确保AutoLoad的加载顺序如下：

| 顺序 | 脚本路径 | 单例名 | 说明 |
|------|---------|--------|------|
| 1 | `res://script/RoomManager.gd` | RoomManager | 房间管理 |
| 2 | `res://script/system/RewardSystem.gd` | RewardSystem | 奖赏系统 ⭐新增 |
| 3 | `res://script/ai/APIManager.gd` | APIManager | API管理 |
| 4 | `res://script/ai/memory/MemoryManager.gd` | MemoryManager | 记忆系统 |
| 5 | `res://script/CharacterManager.gd` | CharacterManager | 角色管理 |

**调整方法**: 使用右侧的上下箭头按钮调整顺序

### 步骤5: 启用单例模式

确保RewardSystem的 **"启用"** 复选框已勾选（默认勾选）

### 步骤6: 保存设置

点击 **"关闭"** 按钮保存设置

---

## 验证配置

### 方法1: 检查project.godot文件

打开项目根目录的 `project.godot` 文件，确认包含以下内容：

```ini
[autoload]

RoomManager="*res://script/RoomManager.gd"
RewardSystem="*res://script/system/RewardSystem.gd"
APIManager="*res://script/ai/APIManager.gd"
MemoryManager="*res://script/ai/memory/MemoryManager.gd"
CharacterManager="*res://script/CharacterManager.gd"
```

### 方法2: 运行时验证

运行项目，检查输出日志中是否包含：

```
[RewardSystem] 奖赏系统初始化完成
```

如果没有此输出，说明AutoLoad配置可能有问题。

---

## 配置检查清单

- [ ] 项目设置中已添加RewardSystem到AutoLoad
- [ ] 路径正确: `res://script/system/RewardSystem.gd`
- [ ] 单例名正确: `RewardSystem`
- [ ] 加载顺序在RoomManager之后
- [ ] 启用复选框已勾选
- [ ] project.godot文件中包含RewardSystem配置
- [ ] 运行时日志显示"奖赏系统初始化完成"

---

## 常见问题

### Q1: RewardSystem.instance为null
**原因**: AutoLoad未正确配置或脚本有错误  
**解决**: 
1. 检查AutoLoad配置
2. 检查脚本是否有语法错误
3. 确保脚本路径正确

### Q2: 加载顺序错误
**原因**: RewardSystem在RoomManager之前加载  
**解决**: 在AutoLoad设置中使用上下箭头调整顺序

### Q3: 信号未连接
**原因**: AgentRewardReceiver在RewardSystem之前初始化  
**解决**: AgentRewardReceiver使用延迟订阅（已内置）

---

## 代码中的使用方式

配置完成后，在代码中通过以下方式访问RewardSystem：

```gdscript
# 方式1: 通过全局单例名（推荐）
if RewardSystem.instance:
    RewardSystem.instance.distribute_reward(agent_name, room_name, time)

# 方式2: 通过get_node()（不推荐，但可用）
var rs = get_node("/root/RewardSystem")
if rs:
    rs.distribute_reward(agent_name, room_name, time)
```

---

## 相关文档

- [PROJECT_STRUCTURE.md](./PROJECT_STRUCTURE.md) - 项目结构说明
- [IMPLEMENTATION_LOGIC.md](./IMPLEMENTATION_LOGIC.md) - 实现逻辑
- [TODO_Perception_System_Separation_2026-04-05.md](./TODO_Perception_System_Separation_2026-04-05.md) - 分离实施待办

---

*本文档由AI助手百舟楫创建，用于指导Godot AutoLoad配置。*
