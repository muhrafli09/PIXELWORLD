class_name GameAction
extends RefCounted

enum ActionType {
	BREAK,
	PLACE_DIRT,
	PLANT_SEED,
	LOCK_SMALL,
	LOCK_BIG,
	TRADE,
	MOVE
}

var type: int = ActionType.BREAK
var actor_id := ""
var target := Vector2i.ZERO
var payload := {}
var client_tick := 0


func _init(p_type: int = ActionType.BREAK, p_actor_id: String = "", p_target: Vector2i = Vector2i.ZERO, p_payload: Dictionary = {}, p_client_tick: int = 0) -> void:
	type = p_type
	actor_id = p_actor_id
	target = p_target
	payload = p_payload.duplicate(true)
	client_tick = p_client_tick
