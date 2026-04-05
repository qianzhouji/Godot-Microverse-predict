# 场景情境配置指南

> **创建日期**: 2026-04-05
> **用途**: 指导如何在School.tscn中配置符合MVT理论的情境参数

---

## 一、项目情境设定回顾

根据PROJECT_OVERVIEW.md，项目包含以下5个核心情境：

| 情境 | 初始收益率(S) | 衰减率(a) | 努力成本(E) | 适合活动 |
|------|--------------|----------|------------|---------|
| 教室（主教学区） | 0.5 (中) | 0.7 (快) | 0.8 (高) | 课堂发言 |
| 教室（小组讨论区） | 0.7 (高) | 0.3 (慢) | 0.6 (中) | 小组合作、竞选 |
| 食堂 | 0.8 (高) | 0.3 (慢) | 0.2 (低) | 同伴互动 |
| 走廊 | 0.3 (低) | 0.3 (慢) | 0.2 (低) | 偶遇互动 |
| 体育馆 | 0.8 (高) | 0.7 (快) | 0.8 (高) | 体育活动 |

---

## 二、当前场景问题分析

### 2.1 现有RoomArea结构问题

当前School.tscn中：
- 只有1个RoomArea节点（类型为Area2D）
- 8个独立的CollisionShape2D节点
- CollisionShape2D不是RoomArea的子节点
- 无法正确检测Agent进入/离开房间

### 2.2 需要修复的结构

**正确结构应该是**：
```
School.tscn
├── RoomArea_ClassroomMain (Area2D) - 教室（主教学区）
│   └── CollisionShape2D
├── RoomArea_ClassroomGroup (Area2D) - 教室（小组讨论区）
│   └── CollisionShape2D
├── RoomArea_Canteen (Area2D) - 食堂
│   └── CollisionShape2D
├── RoomArea_Corridor (Area2D) - 走廊
│   └── CollisionShape2D
├── RoomArea_Gym (Area2D) - 体育馆
│   └── CollisionShape2D
└── RoomManager (Node2D)
```

---

## 三、Godot编辑器配置步骤

### 步骤1: 删除现有的错误节点

1. 在场景树中找到以下节点并删除：
   - RoomArea（现有的单个Area2D）
   - RoomArea_MeetingRoomArea#CollisionShape2D
   - RoomArea_HrOfficeRoomArea#CollisionShape2D
   - RoomArea_ToiletRoomArea#CollisionShape2D
   - RoomArea_BossOfficeRoomArea#CollisionShape2D
   - RoomArea_OfficeRoomArea#CollisionShape2D
   - RoomArea_GymRoomArea#CollisionShape2D
   - RoomArea_TeaRoomArea#CollisionShape2D
   - RoomArea_ReceptionRoomArea#CollisionShape2D
   - RoomArea_WaitingHallRoomArea#CollisionShape2D

### 步骤2: 创建5个RoomArea节点

#### 2.1 创建"教室（主教学区）"

1. 右键点击 **School** 节点 → **添加子节点**
2. 选择 **Area2D**，命名为 `RoomArea_ClassroomMain`
3. 在检查器中设置：
   - **Script**: RoomArea.gd
   - **Room Name**: 教室（主教学区）
   - **Room Desc**: 教室的北侧是主教学区，有多个课桌，用于日常课堂教学和课外活动
   - **Initial Reward Rate**: 0.5
   - **Reward Decay Rate**: 0.7
   - **Effort Level**: 0.8
   - **Activity Types**: ["课堂发言"]

4. 右键点击 **RoomArea_ClassroomMain** → **添加子节点**
5. 选择 **CollisionShape2D**
6. 在检查器中设置：
   - **Shape**: 新建 RectangleShape2D
   - 调整大小和位置，覆盖教室主教学区

#### 2.2 创建"教室（小组讨论区）"

1. 右键点击 **School** 节点 → **添加子节点**
2. 选择 **Area2D**，命名为 `RoomArea_ClassroomGroup`
3. 在检查器中设置：
   - **Script**: RoomArea.gd
   - **Room Name**: 教室（小组讨论区）
   - **Room Desc**: 教室的南侧是小组讨论区，有四张课桌，适合课堂发言、小组合作和竞选活动
   - **Initial Reward Rate**: 0.7
   - **Reward Decay Rate**: 0.3
   - **Effort Level**: 0.6
   - **Activity Types**: ["小组合作", "竞选"]

4. 添加 **CollisionShape2D** 子节点，调整大小和位置

#### 2.3 创建"食堂"

1. 右键点击 **School** 节点 → **添加子节点**
2. 选择 **Area2D**，命名为 `RoomArea_Canteen`
3. 在检查器中设置：
   - **Script**: RoomArea.gd
   - **Room Name**: 食堂
   - **Room Desc**: 食堂是学生们用餐和交流的地方，有饮料贩卖机、饮水机和多个座位
   - **Initial Reward Rate**: 0.8
   - **Reward Decay Rate**: 0.3
   - **Effort Level**: 0.2
   - **Activity Types**: ["同伴互动"]

4. 添加 **CollisionShape2D** 子节点，调整大小和位置

#### 2.4 创建"走廊"

1. 右键点击 **School** 节点 → **添加子节点**
2. 选择 **Area2D**，命名为 `RoomArea_Corridor`
3. 在检查器中设置：
   - **Script**: RoomArea.gd
   - **Room Name**: 走廊
   - **Room Desc**: 走廊连接各个教室，是学生课间走动和偶遇互动的地方
   - **Initial Reward Rate**: 0.3
   - **Reward Decay Rate**: 0.3
   - **Effort Level**: 0.2
   - **Activity Types**: ["偶遇互动"]

4. 添加 **CollisionShape2D** 子节点，调整大小和位置

#### 2.5 创建"体育馆"

1. 右键点击 **School** 节点 → **添加子节点**
2. 选择 **Area2D**，命名为 `RoomArea_Gym`
3. 在检查器中设置：
   - **Script**: RoomArea.gd
   - **Room Name**: 体育馆
   - **Room Desc**: 体育馆内有运动场地和器材，适合体育活动和锻炼
   - **Initial Reward Rate**: 0.8
   - **Reward Decay Rate**: 0.7
   - **Effort Level**: 0.8
   - **Activity Types**: ["体育活动"]

4. 添加 **CollisionShape2D** 子节点，调整大小和位置

### 步骤3: 配置RoomManager

1. 在场景树中找到 **RoomManager** 节点
2. 确保它已经附加了 **RoomManager.gd** 脚本
3. 不需要额外配置，脚本会自动识别所有RoomArea

### 步骤4: 保存并测试

1. 按 **Ctrl+S** 保存场景
2. 按 **F6** 运行测试
3. 检查Agent是否能正确检测房间进入/离开

---

## 四、情境参数说明

### 4.1 初始收益率 (S)

| 取值 | 含义 | 示例情境 |
|------|------|---------|
| 0.0-0.4 | 低 | 走廊（0.3）|
| 0.4-0.7 | 中 | 教室主教学区（0.5）|
| 0.7-1.0 | 高 | 食堂、体育馆（0.8）|

**心理意义**: S高表示情境一开始就能提供较多奖赏，吸引Agent停留

### 4.2 收益衰减率 (a)

| 取值 | 含义 | 示例情境 |
|------|------|---------|
| 0.0-0.3 | 慢 | 食堂、走廊（0.3）|
| 0.3-0.6 | 中 | 小组讨论区（0.3）|
| 0.6-1.0 | 快 | 教室主教学区、体育馆（0.7）|

**心理意义**: a高表示奖赏消耗快，Agent会觉得"很快就不值了"

### 4.3 努力成本 (E)

| 取值 | 含义 | 示例情境 |
|------|------|---------|
| 0.0-0.3 | 低 | 食堂、走廊（0.2）|
| 0.3-0.6 | 中 | 小组讨论区（0.6）|
| 0.6-1.0 | 高 | 教室主教学区、体育馆（0.8）|

**心理意义**: E高表示需要付出很多努力，抑郁Agent（高β_effort）会回避

---

## 五、预期行为差异

### 抑郁Agent (StudentXiaoming, β_effort=0.8)

| 情境 | 预期行为 |
|------|---------|
| 食堂 (E=0.2) | 愿意参与，停留时间较长 |
| 教室主教学区 (E=0.8) | 回避或提前离开，感到疲惫 |
| 体育馆 (E=0.8) | 回避，努力成本太高 |

### 健康Agent (StudentXiaohong, β_effort=0.4)

| 情境 | 预期行为 |
|------|---------|
| 食堂 (E=0.2) | 积极参与 |
| 教室主教学区 (E=0.8) | 正常参与，不觉得特别累 |
| 体育馆 (E=0.8) | 愿意参与体育活动 |

---

## 六、验证清单

- [ ] 5个RoomArea节点创建完成
- [ ] 每个RoomArea都有CollisionShape2D子节点
- [ ] 情境参数(S, a, E)设置正确
- [ ] RoomManager能识别所有RoomArea
- [ ] Agent能正确检测房间进入/离开
- [ ] 抑郁Agent和健康Agent表现出不同的情境偏好

---

*本文档由AI助手百舟楫创建，用于指导场景情境配置。*
