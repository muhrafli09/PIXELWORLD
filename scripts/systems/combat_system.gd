class_name CombatSystem
extends RefCounted


func break_target(world: WorldData, inventory_system: InventorySystem, entity_registry: EntityRegistry, player_id: String, player_pos: Vector2i, target: Vector2i, can_interact: Callable, miner_bonus_dirt_chance: float, rng: RandomNumberGenerator) -> Dictionary:
	if not can_interact.call(target):
		return {"ok": false, "message": "Target terlalu jauh untuk di-break."}
	if not world.is_inside(target):
		return {"ok": false, "message": "Target di luar batas world."}
	if not world.can_modify(player_id, target):
		return {"ok": false, "message": "Aksi ditolak: area/world ini terkunci."}
	if not world.can_break(target):
		var blocked_block: int = world.get_block(target)
		if blocked_block == ItemDB.ID.BEDROCK or blocked_block == ItemDB.ID.LAVA:
			return {"ok": false, "message": "Block %s tidak bisa dihancurkan." % blocked_block}
		return {"ok": false, "message": "Tidak ada block di %s." % str(target)}
	if not inventory_system.is_active_break_tool():
		return {"ok": false, "message": "Pilih break tool di hotbar dulu (punch/pickaxe)."}
	var tool_id: int = inventory_system.active_item_id()
	var tool_damage: int = inventory_system.active_tool_power()
	if tool_damage <= 0:
		return {"ok": false, "message": "Tool '%s' tidak valid untuk break." % tool_id}

	var block_before: int = world.get_block(target)
	var break_result: Dictionary = world.apply_break_damage(target, tool_damage)
	if not bool(break_result.get("ok", false)):
		return {"ok": false, "message": "Block di %s tidak bisa dipukul." % str(target)}
	if not bool(break_result.get("destroyed", false)):
		return {
			"ok": true,
			"message": "Punch %s [%s]: %d/%d hit." % [str(target), tool_id, int(break_result.get("damage", 0)), int(break_result.get("max_hits", 0))],
			"destroyed": false
		}

	var drops: Dictionary = break_result.get("drops", {})
	if miner_bonus_dirt_chance > 0.0 and block_before == ItemDB.ID.DIRT and rng.randf() <= miner_bonus_dirt_chance:
		drops[ItemDB.ID.DIRT] = int(drops.get(ItemDB.ID.DIRT, 0)) + 1

	for item_id in drops.keys():
		entity_registry.spawn_drop(int(item_id), int(drops[item_id]), target, player_id)

	return {
		"ok": true,
		"destroyed": true,
		"drops": drops,
		"message": "Break block di %s, drop: %s." % [str(target), str(drops)]
	}


func place_dirt(world: WorldData, inventory: Inventory, player_id: String, target: Vector2i, can_interact: Callable) -> Dictionary:
	if not world.is_inside(target):
		return {"ok": false, "message": "Target di luar batas world."}
	if not can_interact.call(target):
		return {"ok": false, "message": "Target terlalu jauh untuk place."}
	if not world.can_modify(player_id, target):
		return {"ok": false, "message": "Tidak punya permission untuk place di area ini."}
	if world.get_block(target) != ItemDB.ID.AIR:
		return {"ok": false, "message": "Target %s tidak kosong." % str(target)}
	if not inventory.remove_item(ItemDB.ID.DIRT, 1):
		return {"ok": false, "message": "Dirt habis."}
	world.set_cell(target, ItemDB.ID.DIRT)
	return {"ok": true, "message": "Place dirt di %s." % str(target)}


func place_small_lock(world: WorldData, inventory: Inventory, player_id: String, target: Vector2i, can_interact: Callable) -> Dictionary:
	if not world.is_inside(target):
		return {"ok": false, "message": "Target di luar batas world."}
	if not can_interact.call(target):
		return {"ok": false, "message": "Target terlalu jauh untuk place lock."}
	if not inventory.has_item(ItemDB.ID.SMALL_LOCK, 1):
		return {"ok": false, "message": "Small Lock habis."}
	if not world.can_place_small_lock(player_id, target):
		return {"ok": false, "message": "Gagal place Small Lock (cek owner/target)."}
	inventory.remove_item(ItemDB.ID.SMALL_LOCK, 1)
	world.place_small_lock(player_id, target)
	return {"ok": true, "message": "Small Lock dipasang di %s." % str(target)}


func place_big_lock(world: WorldData, inventory: Inventory, player_id: String, player_name: String, target: Vector2i, can_interact: Callable) -> Dictionary:
	if not world.is_inside(target):
		return {"ok": false, "message": "Target di luar batas world."}
	if not can_interact.call(target):
		return {"ok": false, "message": "Target terlalu jauh untuk place lock."}
	if not inventory.has_item(ItemDB.ID.WORLD_LOCK, 1):
		return {"ok": false, "message": "World Lock habis."}
	if not world.can_place_big_lock(player_id, target):
		return {"ok": false, "message": "Gagal place Big Lock (owner sudah orang lain)."}
	inventory.remove_item(ItemDB.ID.WORLD_LOCK, 1)
	world.place_big_lock(player_id, target)
	return {"ok": true, "message": "Big Lock aktif. World terkunci oleh %s." % player_name}
