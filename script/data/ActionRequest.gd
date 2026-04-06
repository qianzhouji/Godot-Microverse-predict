class_name ActionRequest

enum ActionType {
    MOVE_TO_RANGE,           # 移动到指定位置
    START_DIALOGUE,          # 开始普通对话
    START_WHISPER,           # 开始悄悄话（私密对话）
    JOIN_DIALOGUE,           # 加入对话
    EXIT_DIALOGUE,           # 退出对话
    START_SPORTS,            # 开始体育活动
    END_SPORTS,              # 结束体育活动
    START_STUDY,             # 开始自习
    END_STUDY,               # 结束自习
    WAIT                     # 等待（无行动）
}

var agent_id: String
var action_type: ActionType
var target_id: String           # 目标AgentID（对话用）
var target_range_id: String     # 目标中范围ID（移动用）
var target_position: Vector2    # 目标位置（移动用）
var cached_step2: ActionRequest # 第二步缓存（可选）
var timestamp: float            # 请求提交时间
var is_end_action: bool         # 是否是结束类行动

func _init(p_agent_id: String, p_action_type: ActionType):
    agent_id = p_agent_id
    action_type = p_action_type
    timestamp = Time.get_unix_time_from_system()
    is_end_action = (p_action_type in [ActionType.EXIT_DIALOGUE, 
                                       ActionType.END_SPORTS, 
                                       ActionType.END_STUDY])

func get_action_name() -> String:
    match action_type:
        ActionType.MOVE_TO_RANGE:
            return "移动"
        ActionType.START_DIALOGUE:
            return "开始对话"
        ActionType.START_WHISPER:
            return "开始悄悄话"
        ActionType.JOIN_DIALOGUE:
            return "加入对话"
        ActionType.EXIT_DIALOGUE:
            return "退出对话"
        ActionType.START_SPORTS:
            return "开始体育活动"
        ActionType.END_SPORTS:
            return "结束体育活动"
        ActionType.START_STUDY:
            return "开始自习"
        ActionType.END_STUDY:
            return "结束自习"
        ActionType.WAIT:
            return "等待"
        _:
            return "未知行动"

func to_dict() -> Dictionary:
    return {
        "agent_id": agent_id,
        "action_type": action_type,
        "action_name": get_action_name(),
        "target_id": target_id,
        "target_range_id": target_range_id,
        "target_position": target_position,
        "has_step2": cached_step2 != null,
        "timestamp": timestamp,
        "is_end_action": is_end_action
    }
