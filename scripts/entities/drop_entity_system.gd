class_name DropEntitySystem
extends RefCounted

const DEFAULT_PICKUP_RANGE := 1.25

var dropped_items: Array[DroppedItem] = []


func clear() -> void:
	dropped_items.clear()


func spawn_drop(item_id: int, amount: int, pos: Vector2i, owner_id: String = "") -> void:
	if item_id < 0 or amount <= 0:
		return
	for drop in dropped_items:
		if drop.item_id != item_id:
			continue
		if Vector2i(roundi(drop.pos.x), roundi(drop.pos.y)) == pos:
			drop.amount += amount
			return
	var entity := DroppedItem.new(item_id, amount, Vector2(pos.x, pos.y), owner_id)
	entity.pickup_delay_ticks = 6
	dropped_items.append(entity)


func tick_all(world: WorldData) -> void:
	var alive: Array[DroppedItem] = []
	for drop in dropped_items:
		drop.tick(1, world)
		if not drop.is_expired():
			alive.append(drop)
	dropped_items = alive


func pickup_near(player_pos: Vector2i, inventory: Inventory, pickup_range: float = DEFAULT_PICKUP_RANGE) -> Dictionary:
	var remain: Array[DroppedItem] = []
	var picked := {}
	for drop in dropped_items:
		if drop.can_pickup(player_pos, pickup_range):
			if drop.item_id >= 0 and drop.amount > 0:
				inventory.add_item(drop.item_id, drop.amount)
				picked[drop.item_id] = int(picked.get(drop.item_id, 0)) + drop.amount
		else:
			remain.append(drop)
	dropped_items = remain
	return picked


func to_render_array() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for drop in dropped_items:
		out.append(drop.to_render_dict())
	return out


func count() -> int:
	return dropped_items.size()
