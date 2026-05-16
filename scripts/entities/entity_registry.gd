class_name EntityRegistry
extends RefCounted

var drop_system: DropEntitySystem = DropEntitySystem.new()


func clear() -> void:
	drop_system.clear()


func spawn_drop(item_id: int, amount: int, pos: Vector2i, owner_id: String = "") -> void:
	drop_system.spawn_drop(item_id, amount, pos, owner_id)


func tick_all(world: WorldData) -> void:
	drop_system.tick_all(world)


func pickup_near(player_pos: Vector2i, inventory: Inventory, pickup_range: float = DropEntitySystem.DEFAULT_PICKUP_RANGE) -> Dictionary:
	return drop_system.pickup_near(player_pos, inventory, pickup_range)


func to_render_array() -> Array[Dictionary]:
	return drop_system.to_render_array()


func count() -> int:
	return drop_system.count()
