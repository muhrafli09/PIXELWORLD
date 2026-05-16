class_name PlayerSystem
extends RefCounted

enum PlayerState { IDLE, MOVE, JUMP, FALL, PUNCH }

var player_pos := Vector2i.ZERO
var facing := Vector2i.RIGHT
var manual_target_enabled := false
var manual_target_pos := Vector2i.ZERO
var state := PlayerState.IDLE


func set_position(pos: Vector2i) -> void:
	player_pos = pos


func set_manual_target(target: Vector2i) -> void:
	manual_target_enabled = true
	manual_target_pos = target
	_update_facing_from_target()


func target_pos() -> Vector2i:
	if manual_target_enabled:
		return manual_target_pos
	return player_pos + facing


func apply_state_from_velocity(velocity: Vector2, on_ground: bool) -> void:
	if not on_ground:
		state = PlayerState.JUMP if velocity.y < 0.0 else PlayerState.FALL
		return
	if absf(velocity.x) > 0.05:
		state = PlayerState.MOVE
	else:
		state = PlayerState.IDLE


func mark_punch() -> void:
	state = PlayerState.PUNCH


func _update_facing_from_target() -> void:
	var delta := manual_target_pos - player_pos
	if delta == Vector2i.ZERO:
		return
	if abs(delta.x) >= abs(delta.y):
		facing = Vector2i.RIGHT if delta.x >= 0 else Vector2i.LEFT
	else:
		facing = Vector2i.DOWN if delta.y >= 0 else Vector2i.UP


func state_name() -> String:
	match state:
		PlayerState.IDLE:
			return "IDLE"
		PlayerState.MOVE:
			return "MOVE"
		PlayerState.JUMP:
			return "JUMP"
		PlayerState.FALL:
			return "FALL"
		PlayerState.PUNCH:
			return "PUNCH"
		_:
			return "UNKNOWN"
