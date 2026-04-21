# Activity Coordinator Prompt

## 可用活动

| 活动 | 说明 |
|------|------|
| MOVE_TO | 移动到指定位置，参数：target_location {x, y} |
| NORMAL_DIALOGUE | 发起/加入普通对话，参数：topic |

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
          "activity_type": "NORMAL_DIALOGUE",
          "parameters": {"topic": "日常闲聊"},
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
2. 安排一个角色发起对话（NORMAL_DIALOGUE）
3. 如果其他角色没有发起对话 → 安排他们加入对话

**坐标分配：** 围绕中心点(600,400)分布，半径50-80px

**只输出JSON，不要其他文字。**
