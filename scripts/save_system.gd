class_name SaveSystem
extends RefCounted

const WORLD_DIR := "user://worlds"
const PLAYER_PATH := "user://player.json"
const SAVE_FORMAT_VERSION := 2


func _ensure_world_dir() -> bool:
	if DirAccess.dir_exists_absolute(WORLD_DIR):
		return true
	return DirAccess.make_dir_recursive_absolute(WORLD_DIR) == OK


func _legacy_world_path(world_name: String) -> String:
	return "%s/%s.json" % [WORLD_DIR, world_name.to_upper()]


func _world_base_dir(world_name: String) -> String:
	return "%s/%s" % [WORLD_DIR, world_name.to_upper()]


func _world_meta_path(world_name: String) -> String:
	return "%s/meta.json" % _world_base_dir(world_name)


func _world_chunk_dir(world_name: String) -> String:
	return "%s/chunks" % _world_base_dir(world_name)


func _world_chunk_path(world_name: String, chunk_key: String) -> String:
	var safe_key := chunk_key.replace(",", "_")
	return "%s/%s.json" % [_world_chunk_dir(world_name), safe_key]


func _has_chunk_files(world_name: String) -> bool:
	var dir := DirAccess.open(_world_chunk_dir(world_name))
	if dir == null:
		return false
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json"):
			dir.list_dir_end()
			return true
		entry = dir.get_next()
	dir.list_dir_end()
	return false


func _ensure_world_paths(world_name: String) -> bool:
	if not _ensure_world_dir():
		return false
	if DirAccess.make_dir_recursive_absolute(_world_chunk_dir(world_name)) != OK and not DirAccess.dir_exists_absolute(_world_chunk_dir(world_name)):
		return false
	return true


func save_world(world_name: String, world: WorldData) -> bool:
	var normalized_name := world_name.to_upper()
	if not _ensure_world_paths(normalized_name):
		return false

	var meta := {
		"version": SAVE_FORMAT_VERSION,
		"world_name": world.world_name,
		"owner_id": world.owner_id,
		"world_locked": world.world_locked,
		"world_time_unix": world.world_time_unix,
		"main_door_pos": {"x": world.main_door_pos.x, "y": world.main_door_pos.y},
		"access_list": world.access_list.duplicate(true),
		"area_locks": _serialize_locks(world.area_locks),
		"chunk_size": WorldData.CHUNK_SIZE
	}
	if not _write_json(_world_meta_path(normalized_name), meta):
		return false

	var dirty_payloads: Dictionary = world.get_dirty_chunk_payloads()
	if dirty_payloads.is_empty() and not _has_chunk_files(normalized_name):
		dirty_payloads = world.get_all_chunk_payloads()
	for chunk_key in dirty_payloads.keys():
		if not _write_json(_world_chunk_path(normalized_name, String(chunk_key)), dirty_payloads[chunk_key]):
			return false
	world.clear_dirty_chunks()
	return true


func load_world(world_name: String, world: WorldData) -> bool:
	var normalized_name := world_name.to_upper()
	if FileAccess.file_exists(_world_meta_path(normalized_name)):
		var meta: Dictionary = _read_json(_world_meta_path(normalized_name))
		var version: int = int(meta.get("version", 0))
		if version < SAVE_FORMAT_VERSION:
			return false
		if _load_chunk_world(normalized_name, world):
			if not world.chunks.is_empty() and _is_world_terrain_valid(world):
				return true
		return false
	if FileAccess.file_exists(_legacy_world_path(normalized_name)):
		return false
	return false


func _load_chunk_world(world_name: String, world: WorldData) -> bool:
	var meta: Dictionary = _read_json(_world_meta_path(world_name))
	if meta.is_empty():
		return false
	world.chunks.clear()
	world.dirty_chunks.clear()
	world.world_name = str(meta.get("world_name", world_name))
	world.owner_id = str(meta.get("owner_id", ""))
	world.world_locked = bool(meta.get("world_locked", false))
	world.world_time_unix = int(meta.get("world_time_unix", Time.get_unix_time_from_system()))
	var door_data: Dictionary = meta.get("main_door_pos", {})
	world.main_door_pos = world.clamp_inside(Vector2i(int(door_data.get("x", int(WorldData.WORLD_WIDTH / 2))), int(door_data.get("y", WorldData.GROUND_TOP_Y - 1))))
	world.access_list = []
	for access in meta.get("access_list", []):
		world.access_list.append(str(access))
	world.area_locks = _deserialize_locks(meta.get("area_locks", []))

	var dir := DirAccess.open(_world_chunk_dir(world_name))
	if dir != null:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if not dir.current_is_dir() and entry.ends_with(".json"):
				var chunk_key := entry.trim_suffix(".json").replace("_", ",")
				var payload := _read_json("%s/%s" % [_world_chunk_dir(world_name), entry])
				if not payload.is_empty():
					world.chunks[chunk_key] = {"cells": (payload.get("cells", {}) as Dictionary).duplicate(true)}
			entry = dir.get_next()
		dir.list_dir_end()

	if world.get_block(world.main_door_pos) == ItemDB.ID.AIR:
		world.set_cell(world.main_door_pos, ItemDB.ID.MAIN_DOOR)
	world.clear_dirty_chunks()
	return true


func world_exists(world_name: String) -> bool:
	var normalized_name := world_name.to_upper()
	return FileAccess.file_exists(_world_meta_path(normalized_name)) or FileAccess.file_exists(_legacy_world_path(normalized_name))


func save_player(payload: Dictionary) -> bool:
	return _write_json(PLAYER_PATH, payload)


func load_player() -> Dictionary:
	if not FileAccess.file_exists(PLAYER_PATH):
		return {}
	return _read_json(PLAYER_PATH)


func _write_json(path: String, payload: Dictionary) -> bool:
	var tmp_path: String = "%s.tmp" % path
	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveSystem gagal membuka temp file: %s" % tmp_path)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return _replace_file_atomic(tmp_path, path)


func _replace_file_atomic(tmp_path: String, final_path: String) -> bool:
	if FileAccess.file_exists(final_path):
		var remove_existing: Error = DirAccess.remove_absolute(final_path)
		if remove_existing != OK:
			DirAccess.remove_absolute(tmp_path)
			push_warning("SaveSystem gagal replace file (remove old): %s" % final_path)
			return false
	var rename_result: Error = DirAccess.rename_absolute(tmp_path, final_path)
	if rename_result != OK:
		DirAccess.remove_absolute(tmp_path)
		push_warning("SaveSystem gagal rename temp file ke target: %s" % final_path)
		return false
	return true


func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var raw: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


func _serialize_locks(area_locks: Array[Dictionary]) -> Array[Dictionary]:
	var serialized: Array[Dictionary] = []
	for lock_entry in area_locks:
		var center: Vector2i = lock_entry.get("center", Vector2i.ZERO)
		serialized.append({
			"owner_id": str(lock_entry.get("owner_id", "")),
			"radius": int(lock_entry.get("radius", WorldData.SMALL_LOCK_RADIUS)),
			"center": {"x": center.x, "y": center.y}
		})
	return serialized


func _deserialize_locks(raw_locks: Array) -> Array[Dictionary]:
	var locks: Array[Dictionary] = []
	for raw_lock in raw_locks:
		if typeof(raw_lock) != TYPE_DICTIONARY:
			continue
		var center_data: Dictionary = raw_lock.get("center", {})
		locks.append({
			"owner_id": str(raw_lock.get("owner_id", "")),
			"radius": int(raw_lock.get("radius", WorldData.SMALL_LOCK_RADIUS)),
			"center": Vector2i(int(center_data.get("x", 0)), int(center_data.get("y", 0)))
		})
	return locks


func _is_world_terrain_valid(world: WorldData) -> bool:
	var sample_x: Array[int] = [0, int(WorldData.WORLD_WIDTH / 4), int(WorldData.WORLD_WIDTH / 2), int(WorldData.WORLD_WIDTH * 3 / 4), WorldData.WORLD_WIDTH - 1]
	var solid_bottom_count := 0
	for x in sample_x:
		var block: int = world.get_block(Vector2i(x, WorldData.WORLD_HEIGHT - 1))
		if block == WorldData.BEDROCK:
			solid_bottom_count += 1
	if solid_bottom_count < 3:
		return false
	var spawn_support_pos: Vector2i = world.get_spawn_position() + Vector2i.DOWN
	if not world.is_solid(spawn_support_pos):
		return false
	var mid_solid_count := 0
	var mid_y: int = int(WorldData.WORLD_HEIGHT * 0.70)
	for x in sample_x:
		if world.is_solid(Vector2i(x, mid_y)):
			mid_solid_count += 1
	if mid_solid_count < 2:
		return false
	return true
