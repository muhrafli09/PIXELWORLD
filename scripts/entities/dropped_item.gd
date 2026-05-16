class_name DroppedItem
extends RefCounted

var item_id := -1
var amount := 0
var pos := Vector2.ZERO
var velocity := Vector2.ZERO
var age_ticks := 0
var pickup_delay_ticks := 0
var owner_id := ""
var despawn_ticks := 1200


func _init(p_item_id: int = -1, p_amount: int = 0, p_pos: Vector2 = Vector2.ZERO, p_owner_id: String = "") -> void:
	item_id = p_item_id
	amount = p_amount
	pos = p_pos
	owner_id = p_owner_id
	velocity = Vector2(randf_range(-0.08, 0.08), -0.12)


func tick(_delta_ticks: int, world: WorldData) -> void:
	age_ticks += 1
	if pickup_delay_ticks > 0:
		pickup_delay_ticks -= 1
	velocity.y = min(velocity.y + 0.05, 0.25)
	var candidate := pos + velocity
	var tile := Vector2i(roundi(candidate.x), roundi(candidate.y))
	if not world.is_inside(tile) or world.get_block(tile) != ItemDB.ID.AIR:
		velocity = Vector2.ZERO
	else:
		pos = candidate


func can_pickup(player_pos: Vector2i, magnet_range: float) -> bool:
	if pickup_delay_ticks > 0:
		return false
	return pos.distance_to(Vector2(player_pos.x, player_pos.y)) <= magnet_range


func is_expired() -> bool:
	return age_ticks >= despawn_ticks


func to_render_dict() -> Dictionary:
	return {
		"item_id": item_id,
		"amount": amount,
		"pos": Vector2i(roundi(pos.x), roundi(pos.y))
	}
