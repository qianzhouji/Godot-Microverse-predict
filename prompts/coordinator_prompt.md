# Activity Coordinator Prompt

## 可用活动

| 活动 | 说明 |
|------|------|
| MOVE_TO | 移动到指定位置，参数：target_location {x, y} |
| INITIATE_DIALOGUE | 发起对话，参数：range_type (0=悄悄话, 1=普通对话, 2=广播), topic |
| JOIN_DIALOGUE | 加入已有对话，参数：dialogue_id（不知道ID时可省略，系统会自动加入当前位置可见对话） |

## 输出格式

```json
{
  "agents": [
    {
      "agent_id": "角色名",
      "steps": [
        {
          "step": 1,
          "activity_type": "MOVE_TO",
          "parameters": {"target_location": {"x": 600, "y": 400}},
          "reason": "移动到集合点"
        },
        {
          "step": 2,
          "activity_type": "INITIATE_DIALOGUE",
          "parameters": {"range_type": 1, "topic": "日常闲聊"},
          "reason": "发起对话"
        }
      ]
    }
  ]
}
```

## 协调规则

**核心任务：让所有角色聚在一起对话**

1. 如果角色不在一起 → 安排他们移动到同一位置（食堂中心约600,400）
2. 安排**一个**角色发起对话（INITIATE_DIALOGUE，range_type=1普通对话）
3. 安排**其他**角色加入对话（JOIN_DIALOGUE；如果不知道对话ID，可以留空）

**注意：** 只有一个角色发起对话，其他角色都加入这个对话！

**坐标分配：** 围绕中心点(600,400)分布，半径50-80px

**只输出JSON，不要其他文字。**
