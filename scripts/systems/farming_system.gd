class_name FarmingSystem
extends RefCounted


func plant_seed(world: WorldData, inventory: Inventory, player_id: String, target: Vector2i, can_interact: Callable, seed_refund_chance: float, rng: RandomNumberGenerator) -> Dictionary:
	if not world.is_inside(target):
		return {"ok": false, "message": "Target di luar batas world."}
	if not can_interact.call(target):
		return {"ok": false, "message": "Target terlalu jauh untuk tanam."}
	if not world.can_modify(player_id, target):
		return {"ok": false, "message": "Tidak punya permission untuk tanam di area ini."}
	if not inventory.remove_item(ItemDB.ID.SEED, 1):
		return {"ok": false, "message": "Seed habis."}
	if not world.can_plant_at(target):
		inventory.add_item(ItemDB.ID.SEED, 1)
		return {"ok": false, "message": "Tidak bisa tanam di %s (harus udara di atas dirt)." % str(target)}
	var now := Time.get_unix_time_from_system()
	var fruit_bonus := 0
	var roll := rng.randf()
	if roll <= 0.18:
		fruit_bonus = 2
	elif roll <= 0.48:
		fruit_bonus = 1
	var growth_factor := rng.randf_range(WorldData.MIN_GROWTH_FACTOR, WorldData.MAX_GROWTH_FACTOR)
	world.set_cell(target, ItemDB.ID.PLANT_0, int(now), {
		"fruit_bonus": fruit_bonus,
		"growth_factor": growth_factor
	})
	if seed_refund_chance > 0.0 and rng.randf() <= seed_refund_chance:
		inventory.add_item(ItemDB.ID.SEED, 1)
		return {"ok": true, "message": "Tanam seed di %s. Passive Farmer: seed kembali 1." % str(target)}
	return {"ok": true, "message": "Tanam seed di %s." % str(target)}


func tick_growth(world: WorldData) -> bool:
	var now := int(Time.get_unix_time_from_system())
	return world.advance_growth(now)
