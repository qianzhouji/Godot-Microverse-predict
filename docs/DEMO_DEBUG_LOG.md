# 对话系统Demo调试日志

> **项目**: Godot-Microverse-predict  
> **分支**: test/dialogue-system  
> **目标**: 硬编码Demo测试多Agent对话系统  
> **创建时间**: 2026-04-22

---

## 测试目标

实现一个硬编码的测试Demo，完全控制流程，不依赖LLM：
- **Click 1**: 所有角色移动到教室
- **Click 2**: 小明发起普通对话
- **Click 3**: 其他角色加入对话
- **Click 4+**: 继续对话

---

## 调试记录

### 问题1: class_name与AutoLoad冲突

**时间**: 2026-04-22 17:11  
**错误信息**: `Class "HardcodedDemoController" hides an autoload singleton`

**原因**: 同时使用 `class_name` 和 AutoLoad 配置

**修复**:
```gdscript
# 修改前
extends Node
class_name HardcodedDemoController

# 修改后
extends Node
# 注意：不使用class_name，因为此脚本已配置为AutoLoad
```

**提交**: `72dd7f9`

---

### 问题2: Activity缺少step_index属性

**时间**: 2026-04-22 17:21  
**错误信息**: `Invalid assignment of property or key 'step_index'`

**原因**: `Activity.gd` 中没有定义 `step_index` 属性

**修复**:
```gdscript
# 在Activity.gd中添加
var step_index: int = 0  # 在活动序列中的步骤索引
```

**提交**: `21251dc`

---

### 问题3: 类型不匹配 - 普通Array vs Array[Activity]

**时间**: 2026-04-22 17:33  
**错误信息**: `The array of argument 1 (Array) does not have the same element type as the expected typed array`

**原因**: `receive_activity_sequence` 期望 `Array[Activity]`，但传递的是普通 `Array`

**修复**:
```gdscript
# 修改前
assignments[agent_id] = [activity]

# 修改后
var activity_array: Array[Activity] = [activity]
assignments[agent_id] = activity_array
```

**提交**: `bb404fd`

---

### 问题4: Dictionary vs Vector2 类型错误

**时间**: 2026-04-22 17:35  
**错误信息**: `Trying to assign value of type 'Dictionary' to a variable of type 'Vector2'`

**原因**: `MovementExecutor` 期望 `target_location` 是 `Vector2`，但传递的是 Dictionary `{"x": ..., "y": ...}`

**修复**:
```gdscript
# 修改前
activity.parameters = {
    "target_location": {
        "x": CLASSROOM_CENTER.x + randf_range(-30, 30),
        "y": CLASSROOM_CENTER.y + randf_range(-30, 30)
    }
}

# 修改后
activity.parameters = {
    "target_location": Vector2(
        CLASSROOM_CENTER.x + randf_range(-30, 30),
        CLASSROOM_CENTER.y + randf_range(-30, 30)
    )
}
```

**提交**: `9a8e451`

---

### 问题5: DialogManager路径错误（最严重）

**时间**: 2026-04-22 17:46-21:52  
**错误信息**: `DialogueManager未找到，无法启动对话`

**根本原因**:
- 脚本文件名: `DialogueManager.gd`（类名也是DialogueManager）
- project.godot中AutoLoad名: `DialogManager`（没有"ue"）
- 代码中使用: `/root/DialogueManager` ❌
- 正确路径: `/root/DialogManager` ✅

**影响**: Click 2的INITIATE_DIALOGUE活动执行失败，无法创建对话，导致Click 3无法加入对话

**修复**: 批量替换所有 `/root/DialogueManager` 为 `/root/DialogManager`

**涉及的方法**:
- `_execute_v2_initiate_dialogue`
- `_execute_v2_join_dialogue`
- `_execute_start_dialogue`
- `_execute_start_whisper`
- `_execute_join_dialogue`
- `_execute_v2_discussion`

**提交**: `9f5fb00`

**教训**: 
1. 修改代码前务必先检查project.godot中的AutoLoad配置
2. 节点路径必须与AutoLoad名完全一致（包括拼写）
3. 添加注释说明AutoLoad名，避免混淆文件名和AutoLoad名

**检查方法**:
```bash
grep "DialogManager" project.godot  # 查看AutoLoad名
grep "DialogueManager" script/ai/AIAgent.gd  # 检查代码中的路径
```

---

## 测试结果

**2026-04-22 22:10** - ✅ **测试成功！**

Click 2:
```
[AIAgent] StudentXiaoming 尝试获取DialogManager: DialogueManager:<Node#44761613804>
[DialogueManager] 普通对话开始: dlg_StudentXiaoming_485
[AIAgent] StudentXiaoming 成功启动普通对话，对话ID: dlg_StudentXiaoming_485
[HardcodedDemoController] 记录小明的对话ID: dlg_StudentXiaoming_485
```

Click 3:
```
[AIAgent] StudentXiaohong 成功加入对话 dlg_StudentXiaoming_485
[AIAgent] StudentXiaogang 成功加入对话 dlg_StudentXiaoming_485
[SpeakerQueueManager] 添加参与者: StudentXiaohong
[SpeakerQueueManager] 添加参与者: StudentXiaogang
```

**所有Click均成功执行！**

---

## 文件变更

| 文件 | 变更 |
|------|------|
| `script/system/HardcodedDemoController.gd` | 新增硬编码Demo控制器 |
| `script/system/TimingSystem.gd` | 添加Demo模式支持 |
| `script/ai/AIAgent.gd` | 添加Demo模式检测、JOIN_DIALOGUE处理、修复DialogManager路径 |
| `script/system/Activity.gd` | 添加step_index属性 |
| `project.godot` | 添加HardcodedDemoController为AutoLoad |

---

## 相关提交

```
bf3d609 修复AIAgent中dialog_service引用错误（手动编辑版）
4e44499 修复：移除DialogueManager的class_name避免与AutoLoad冲突
10b59b2 修复：统一使用DialogueManager命名
a6547ac 添加调试日志：打印DialogManager获取结果
1f881d2 添加对话系统Demo调试日志
05c723d 添加硬编码Demo控制器
5247855 更新Demo控制器注释
72dd7f9 修复：移除class_name避免与AutoLoad冲突
21251dc 修复：Activity类添加step_index属性
8560ed3 修复TimingSystem的Agent查找逻辑
bb404fd 修复：使用类型化的Array[Activity]
9a8e451 修复：MOVE_TO活动的target_location使用Vector2
9f5fb00 修复：AIAgent中DialogManager路径错误
```

---

## 后续建议

1. **统一命名**: 考虑将project.godot中的AutoLoad名改为DialogueManager，与脚本文件名保持一致
2. **添加检查**: 在代码中添加运行时检查，如果DialogManager未找到，打印明确的错误信息
3. **文档化**: 在DialogueManager.gd顶部添加注释，说明AutoLoad名是DialogManager

---

*维护者：百舟楫*  
*最后更新：2026-04-22*
