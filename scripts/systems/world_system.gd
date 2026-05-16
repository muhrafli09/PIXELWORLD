class_name WorldSystem
extends RefCounted

const SAVE_THROTTLE_MS := 1500

var _last_save_world_ms := 0


func join_world(world: WorldData, save_system: SaveSystem, world_name: String, player_id: String) -> Dictionary:
	if world.world_name != "":
		save_system.save_world(world.world_name, world)
	var normalized_name: String = world_name.strip_edges().to_upper()
	if normalized_name == "":
		normalized_name = "START"
	var loaded_ok: bool = save_system.load_world(normalized_name, world)
	if loaded_ok:
		return {"created": false, "world_name": world.world_name}
	world.bootstrap_ground(normalized_name)
	save_system.save_world(normalized_name, world)
	return {"created": true, "world_name": normalized_name}


func save_world_if_dirty(save_system: SaveSystem, world: WorldData, force: bool = false) -> bool:
	var now := Time.get_ticks_msec()
	if not force and (now - _last_save_world_ms) < SAVE_THROTTLE_MS:
		return false
	if not force and world.dirty_chunks.is_empty():
		return false
	var ok := save_system.save_world(world.world_name, world)
	if ok:
		_last_save_world_ms = now
	return ok


func lock_summary(world: WorldData, player_id: String, player_name: String) -> String:
	if world.owner_id == "":
		return "Unlocked world"
	var owner_text := world.owner_id
	if world.owner_id == player_id:
		owner_text = "%s (you)" % player_name
	var mode: String = "BigLock" if world.world_locked else "AreaLock"
	return "%s by %s" % [mode, owner_text]
