class_name WorldData
extends RefCounted

const AIR := ItemDB.ID.AIR
const DIRT := ItemDB.ID.DIRT
const STONE := ItemDB.ID.STONE
const LAVA := ItemDB.ID.LAVA
const BEDROCK := ItemDB.ID.BEDROCK
const MAIN_DOOR := ItemDB.ID.MAIN_DOOR
const PLANT_0 := ItemDB.ID.PLANT_0
const PLANT_1 := ItemDB.ID.PLANT_1
const PLANT_2 := ItemDB.ID.PLANT_2

const WORLD_WIDTH := 100
const WORLD_HEIGHT := 60
const GROUND_TOP_Y := 38
const SMALL_LOCK_RADIUS := 10
const STAGE_SECONDS := 10
const CHUNK_SIZE := 16
const MIN_GROWTH_FACTOR := 0.8
const MAX_GROWTH_FACTOR := 1.35

var chunks: Dictionary = {}
var dirty_chunks: Dictionary = {}
var world_name := "START"
var owner_id := ""
var world_locked := false
var world_time_unix := 0
var main_door_pos := Vector2i(int(WORLD_WIDTH / 2), GROUND_TOP_Y - 1)
var access_list: Array[String] = []
var area_locks: Array[Dictionary] = []


func _cell_key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]


func _chunk_coord(pos: Vector2i) -> Vector2i:
	return Vector2i(int(floor(float(pos.x) / float(CHUNK_SIZE))), int(floor(float(pos.y) / float(CHUNK_SIZE))))


func _chunk_key(coord: Vector2i) -> String:
	return "%d,%d" % [coord.x, coord.y]


func _local_pos(pos: Vector2i) -> Vector2i:
	return Vector2i(posmod(pos.x, CHUNK_SIZE), posmod(pos.y, CHUNK_SIZE))


func _ensure_chunk(coord: Vector2i) -> Dictionary:
	var key: String = _chunk_key(coord)
	if not chunks.has(key):
		chunks[key] = {"cells": {}}
	return chunks[key] as Dictionary


func _mark_dirty(coord: Vector2i) -> void:
	dirty_chunks[_chunk_key(coord)] = true


func _chunk_cells(coord: Vector2i) -> Dictionary:
	var key: String = _chunk_key(coord)
	if not chunks.has(key):
		return {}
	return (chunks[key] as Dictionary).get("cells", {}) as Dictionary


func is_inside(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < WORLD_WIDTH and pos.y >= 0 and pos.y < WORLD_HEIGHT


func clamp_inside(pos: Vector2i) -> Vector2i:
	return Vector2i(clamp(pos.x, 0, WORLD_WIDTH - 1), clamp(pos.y, 0, WORLD_HEIGHT - 1))


func get_spawn_position() -> Vector2i:
	return main_door_pos


func get_cell_data(pos: Vector2i) -> Dictionary:
	if not is_inside(pos):
		return {"block": AIR}
	var chunk_coord: Vector2i = _chunk_coord(pos)
	var cells: Dictionary = _chunk_cells(chunk_coord)
	if cells.is_empty():
		return {"block": AIR}
	var local_key: String = _cell_key(_local_pos(pos))
	if not cells.has(local_key):
		return {"block": AIR}
	return (cells[local_key] as Dictionary).duplicate(true)


func get_block(pos: Vector2i) -> int:
	if not is_inside(pos):
		return AIR
	return int(get_cell_data(pos).get("block", AIR))


func is_solid(pos: Vector2i) -> bool:
	if not is_inside(pos):
		return true
	return ItemDB.is_solid(get_block(pos))


func get_break_hits(pos: Vector2i) -> int:
	return ItemDB.break_hits(get_block(pos))


func get_damage(pos: Vector2i) -> int:
	if not is_inside(pos):
		return 0
	return int(get_cell_data(pos).get("damage", 0))


func get_break_progress(pos: Vector2i) -> float:
	var max_hits: int = get_break_hits(pos)
	if max_hits <= 0:
		return 0.0
	return clampf(float(get_damage(pos)) / float(max_hits), 0.0, 1.0)


func set_cell(pos: Vector2i, block: int, planted_at: int = 0, metadata: Dictionary = {}) -> void:
	if not is_inside(pos):
		return
	var coord: Vector2i = _chunk_coord(pos)
	var chunk: Dictionary = _ensure_chunk(coord)
	var cells: Dictionary = chunk.get("cells", {}) as Dictionary
	var key: String = _cell_key(_local_pos(pos))
	if block == AIR:
		cells.erase(key)
		chunk["cells"] = cells
		chunks[_chunk_key(coord)] = chunk
		_mark_dirty(coord)
		return
	var value: Dictionary = {"block": block}
	if planted_at > 0:
		value["planted_at"] = planted_at
	for meta_key in metadata.keys():
		value[str(meta_key)] = metadata[meta_key]
	cells[key] = value
	chunk["cells"] = cells
	chunks[_chunk_key(coord)] = chunk
	_mark_dirty(coord)


func can_plant_at(pos: Vector2i) -> bool:
	if not is_inside(pos):
		return false
	if get_block(pos) != AIR:
		return false
	var below := pos + Vector2i.DOWN
	return get_block(below) == DIRT


func can_break(pos: Vector2i) -> bool:
	if not is_inside(pos):
		return false
	var block: int = get_block(pos)
	if block == AIR:
		return false
	return ItemDB.is_breakable(block)


func can_modify(player_id: String, pos: Vector2i) -> bool:
	if not is_inside(pos):
		return false
	if owner_id == "":
		return true
	if player_id == owner_id or access_list.has(player_id):
		return true
	if world_locked:
		return false
	return not is_in_any_area_lock(pos)


func is_in_any_area_lock(pos: Vector2i) -> bool:
	for lock_entry in area_locks:
		var center: Vector2i = lock_entry.get("center", Vector2i.ZERO)
		var radius: int = int(lock_entry.get("radius", SMALL_LOCK_RADIUS))
		if abs(pos.x - center.x) <= radius and abs(pos.y - center.y) <= radius:
			return true
	return false


func can_place_small_lock(player_id: String, pos: Vector2i) -> bool:
	if not is_inside(pos):
		return false
	if get_block(pos) != AIR:
		return false
	if owner_id != "" and player_id != owner_id:
		return false
	return true


func place_small_lock(player_id: String, pos: Vector2i) -> bool:
	if not can_place_small_lock(player_id, pos):
		return false
	if owner_id == "":
		owner_id = player_id
	access_list = _ensure_unique(access_list)
	if not access_list.has(owner_id):
		access_list.append(owner_id)
	area_locks.append({
		"owner_id": player_id,
		"center": pos,
		"radius": SMALL_LOCK_RADIUS
	})
	return true


func can_place_big_lock(player_id: String, pos: Vector2i) -> bool:
	if not is_inside(pos):
		return false
	if get_block(pos) != AIR:
		return false
	if owner_id == "":
		return true
	return player_id == owner_id


func place_big_lock(player_id: String, _pos: Vector2i) -> bool:
	if owner_id != "" and owner_id != player_id:
		return false
	owner_id = player_id
	world_locked = true
	access_list = _ensure_unique(access_list)
	if not access_list.has(owner_id):
		access_list.append(owner_id)
	return true


func add_access(player_id: String, granted_player_id: String) -> bool:
	if player_id != owner_id:
		return false
	if granted_player_id == "":
		return false
	if access_list.has(granted_player_id):
		return true
	access_list.append(granted_player_id)
	return true


func _ensure_unique(input: Array[String]) -> Array[String]:
	var seen := {}
	var result: Array[String] = []
	for value in input:
		if seen.has(value):
			continue
		seen[value] = true
		result.append(value)
	return result


func break_block(pos: Vector2i) -> Dictionary:
	if not can_break(pos):
		return {}
	var block: int = get_block(pos)
	var cell_data: Dictionary = get_cell_data(pos)
	set_cell(pos, AIR)
	var drops: Dictionary = {}
	if block == PLANT_0 or block == PLANT_1:
		drops[ItemDB.ID.SEED] = 1
		return drops
	if block == PLANT_2:
		drops[ItemDB.ID.SEED] = 2
		drops[ItemDB.ID.FRUIT] = 1 + int(cell_data.get("fruit_bonus", 0))
		return drops
	for entry in ItemDB.drops_for(block):
		var item_id: int = int(entry.get("item_id", -1))
		var amount: int = int(entry.get("amount", 0))
		if item_id < 0 or amount <= 0:
			continue
		drops[item_id] = int(drops.get(item_id, 0)) + max(amount, 0)
	return drops


func apply_break_damage(pos: Vector2i, amount: int = 1) -> Dictionary:
	if not can_break(pos):
		return {"ok": false}
	var max_hits: int = get_break_hits(pos)
	if max_hits <= 0:
		return {"ok": false}
	var coord: Vector2i = _chunk_coord(pos)
	var chunk: Dictionary = _ensure_chunk(coord)
	var cells: Dictionary = chunk.get("cells", {}) as Dictionary
	var key: String = _cell_key(_local_pos(pos))
	var entry: Dictionary = (cells.get(key, {}) as Dictionary).duplicate(true)
	var current_damage: int = int(entry.get("damage", 0)) + max(1, amount)
	entry["damage"] = current_damage
	entry["block"] = get_block(pos)
	cells[key] = entry
	chunk["cells"] = cells
	chunks[_chunk_key(coord)] = chunk
	_mark_dirty(coord)

	if current_damage < max_hits:
		return {
			"ok": true,
			"destroyed": false,
			"damage": current_damage,
			"max_hits": max_hits,
			"progress": clampf(float(current_damage) / float(max_hits), 0.0, 1.0),
			"drops": {}
		}

	var drops := break_block(pos)
	return {
		"ok": true,
		"destroyed": true,
		"damage": max_hits,
		"max_hits": max_hits,
		"progress": 1.0,
		"drops": drops
	}


func advance_growth(now_unix: int) -> bool:
	world_time_unix = now_unix
	var changed := false
	for chunk_key in chunks.keys():
		var chunk: Dictionary = chunks[chunk_key]
		var cells: Dictionary = chunk.get("cells", {}) as Dictionary
		var edited := false
		for local_key in cells.keys():
			var entry: Dictionary = cells[local_key]
			var block: int = int(entry.get("block", AIR))
			if block != PLANT_0 and block != PLANT_1 and block != PLANT_2:
				continue
			var planted_at := int(entry.get("planted_at", now_unix))
			var growth_factor: float = clampf(float(entry.get("growth_factor", 1.0)), MIN_GROWTH_FACTOR, MAX_GROWTH_FACTOR)
			var elapsed: int = max(0, now_unix - planted_at)
			var stage_window: float = float(STAGE_SECONDS) * growth_factor
			var stage: int = min(2, int(floor(float(elapsed) / max(stage_window, 1.0))))
			var target: int = PLANT_0
			if stage == 1:
				target = PLANT_1
			elif stage >= 2:
				target = PLANT_2
			if block != target:
				entry["block"] = target
				cells[local_key] = entry
				changed = true
				edited = true
		if edited:
			chunk["cells"] = cells
			chunks[chunk_key] = chunk
			dirty_chunks[chunk_key] = true
	return changed


func bootstrap_ground(seed_world_name: String = "START") -> void:
	chunks.clear()
	dirty_chunks.clear()
	world_name = seed_world_name.to_upper()
	world_time_unix = int(Time.get_unix_time_from_system())
	owner_id = ""
	world_locked = false
	area_locks = []
	access_list = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash(world_name))

	var terrain_noise := FastNoiseLite.new()
	terrain_noise.seed = int(hash("%s_terrain" % world_name))
	terrain_noise.frequency = 0.055

	var cave_noise := FastNoiseLite.new()
	cave_noise.seed = int(hash("%s_cave" % world_name))
	cave_noise.frequency = 0.11

	var spawn_x: int = int(WORLD_WIDTH / 2)
	var base_ground: int = int(WORLD_HEIGHT * 0.58)
	var surface_by_x: Array[int] = []
	surface_by_x.resize(WORLD_WIDTH)

	for x in range(WORLD_WIDTH):
		var offset: int = int(round(terrain_noise.get_noise_1d(float(x)) * 3.0))
		var surface_y: int = clamp(base_ground + offset, 30, WORLD_HEIGHT - 8)
		surface_by_x[x] = surface_y
		for y in range(WORLD_HEIGHT):
			var pos := Vector2i(x, y)
			if y >= WORLD_HEIGHT - 2:
				set_cell(pos, BEDROCK)
			elif y >= surface_y + 6:
				set_cell(pos, STONE)
			elif y >= surface_y:
				set_cell(pos, DIRT)

	for x in range(WORLD_WIDTH):
		var surface_y: int = surface_by_x[x]
		for y in range(surface_y + 4, WORLD_HEIGHT - 2):
			if cave_noise.get_noise_2d(float(x), float(y)) > 0.42:
				set_cell(Vector2i(x, y), AIR)

	for x in range(2, WORLD_WIDTH - 2):
		if abs(x - spawn_x) < 6:
			continue
		if rng.randf() > 0.07:
			continue
		var root_y: int = surface_by_x[x] - 1
		if root_y < 3:
			continue
		if get_block(Vector2i(x, root_y)) != AIR:
			continue
		if get_block(Vector2i(x, root_y + 1)) != DIRT:
			continue
		set_cell(Vector2i(x, root_y), PLANT_2, world_time_unix, {"growth_factor": 1.0, "fruit_bonus": rng.randi_range(0, 2)})
		if get_block(Vector2i(x - 1, root_y - 1)) == AIR:
			set_cell(Vector2i(x - 1, root_y - 1), PLANT_1, world_time_unix, {"growth_factor": 1.0, "fruit_bonus": 0})
		if get_block(Vector2i(x + 1, root_y - 1)) == AIR:
			set_cell(Vector2i(x + 1, root_y - 1), PLANT_1, world_time_unix, {"growth_factor": 1.0, "fruit_bonus": 0})

	var spawn_surface_y: int = surface_by_x[spawn_x]
	main_door_pos = Vector2i(spawn_x, spawn_surface_y - 1)
	for x in range(spawn_x - 1, spawn_x + 2):
		for y in range(main_door_pos.y - 1, main_door_pos.y + 1):
			var pos := Vector2i(x, y)
			if is_inside(pos):
				set_cell(pos, AIR)
	_apply_main_door_layout()


func get_dirty_chunk_payloads() -> Dictionary:
	var out: Dictionary = {}
	for key in dirty_chunks.keys():
		var chunk: Dictionary = chunks.get(key, {"cells": {}})
		out[key] = {"cells": (chunk.get("cells", {}) as Dictionary).duplicate(true)}
	return out


func get_all_chunk_payloads() -> Dictionary:
	var out: Dictionary = {}
	for key in chunks.keys():
		var chunk: Dictionary = chunks.get(key, {"cells": {}})
		out[key] = {"cells": (chunk.get("cells", {}) as Dictionary).duplicate(true)}
	return out


func clear_dirty_chunks() -> void:
	dirty_chunks.clear()


func to_dict() -> Dictionary:
	var serialized_locks: Array[Dictionary] = []
	for lock_entry in area_locks:
		var center: Vector2i = lock_entry.get("center", Vector2i.ZERO)
		serialized_locks.append({
			"owner_id": str(lock_entry.get("owner_id", "")),
			"radius": int(lock_entry.get("radius", SMALL_LOCK_RADIUS)),
			"center": {"x": center.x, "y": center.y}
		})
	return {
		"world_name": world_name,
		"owner_id": owner_id,
		"world_locked": world_locked,
		"world_time_unix": world_time_unix,
		"main_door_pos": {"x": main_door_pos.x, "y": main_door_pos.y},
		"access_list": access_list.duplicate(true),
		"area_locks": serialized_locks,
		"cells": _flatten_cells()
	}


func _flatten_cells() -> Dictionary:
	var out: Dictionary = {}
	for chunk_key in chunks.keys():
		var chunk: Dictionary = chunks[chunk_key]
		var cells: Dictionary = chunk.get("cells", {}) as Dictionary
		var parts: PackedStringArray = String(chunk_key).split(",")
		if parts.size() != 2:
			continue
		var cx: int = int(parts[0])
		var cy: int = int(parts[1])
		for local_key in cells.keys():
			var local_parts: PackedStringArray = String(local_key).split(",")
			if local_parts.size() != 2:
				continue
			var lx: int = int(local_parts[0])
			var ly: int = int(local_parts[1])
			var gx: int = (cx * CHUNK_SIZE) + lx
			var gy: int = (cy * CHUNK_SIZE) + ly
			out[_cell_key(Vector2i(gx, gy))] = (cells[local_key] as Dictionary).duplicate(true)
	return out


func from_dict(data: Dictionary) -> void:
	chunks.clear()
	dirty_chunks.clear()
	world_name = str(data.get("world_name", "START"))
	owner_id = str(data.get("owner_id", ""))
	world_locked = bool(data.get("world_locked", false))
	world_time_unix = int(data.get("world_time_unix", Time.get_unix_time_from_system()))
	var door_data: Dictionary = data.get("main_door_pos", {})
	main_door_pos = clamp_inside(Vector2i(int(door_data.get("x", int(WORLD_WIDTH / 2))), int(door_data.get("y", GROUND_TOP_Y - 1))))
	access_list = []
	var raw_access: Array = data.get("access_list", [])
	for player_id in raw_access:
		access_list.append(str(player_id))
	access_list = _ensure_unique(access_list)
	area_locks = []
	var raw_locks: Array = data.get("area_locks", [])
	for raw_lock in raw_locks:
		if typeof(raw_lock) != TYPE_DICTIONARY:
			continue
		var center_data: Dictionary = raw_lock.get("center", {})
		var center := clamp_inside(Vector2i(int(center_data.get("x", 0)), int(center_data.get("y", 0))))
		area_locks.append({
			"owner_id": str(raw_lock.get("owner_id", "")),
			"radius": int(raw_lock.get("radius", SMALL_LOCK_RADIUS)),
			"center": center
		})

	var raw_cells: Dictionary = data.get("cells", {})
	for key in raw_cells.keys():
		var parts: PackedStringArray = String(key).split(",")
		if parts.size() != 2:
			continue
		var pos := Vector2i(int(parts[0]), int(parts[1]))
		if not is_inside(pos):
			continue
		var entry: Dictionary = (raw_cells[key] as Dictionary).duplicate(true)
		var block: int = int(entry.get("block", AIR))
		if block == AIR:
			continue
		var planted_at: int = int(entry.get("planted_at", 0))
		var metadata := entry.duplicate(true)
		metadata.erase("block")
		metadata.erase("planted_at")
		set_cell(pos, block, planted_at, metadata)
		if entry.has("damage"):
			var coord: Vector2i = _chunk_coord(pos)
			var chunk: Dictionary = _ensure_chunk(coord)
			var cells: Dictionary = chunk.get("cells", {}) as Dictionary
			var local_key: String = _cell_key(_local_pos(pos))
			if cells.has(local_key):
				var saved_entry: Dictionary = cells[local_key]
				saved_entry["damage"] = int(entry.get("damage", 0))
				cells[local_key] = saved_entry
				chunk["cells"] = cells
				chunks[_chunk_key(coord)] = chunk

	_apply_main_door_layout()
	clear_dirty_chunks()


func _apply_main_door_layout() -> void:
	main_door_pos = clamp_inside(main_door_pos)
	for x in range(main_door_pos.x - 1, main_door_pos.x + 2):
		for y in range(main_door_pos.y - 1, main_door_pos.y + 1):
			var open_pos := Vector2i(x, y)
			if is_inside(open_pos):
				set_cell(open_pos, AIR)
	set_cell(main_door_pos, MAIN_DOOR)
	var door_support: Vector2i = main_door_pos + Vector2i.DOWN
	if is_inside(door_support):
		set_cell(door_support, BEDROCK)
