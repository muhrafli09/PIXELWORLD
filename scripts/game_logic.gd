class_name GameLogic
extends RefCounted

signal state_changed(message: String)

const ACTION_COOLDOWN_MS := 220
const TRADE_POS := Vector2i(50, 34)
const DEFAULT_CHARACTER_ID := "farmer"
const LOCAL_PLAYER_ID := "local_player"
const LOCAL_PLAYER_NAME := "Player"

var world: WorldData = WorldData.new()
var save_system: SaveSystem = SaveSystem.new()
var rng := RandomNumberGenerator.new()

var player_system: PlayerSystem = PlayerSystem.new()
var inventory_system: InventorySystem = InventorySystem.new()
var character_system: CharacterSystem = CharacterSystem.new()
var world_system: WorldSystem = WorldSystem.new()
var farming_system: FarmingSystem = FarmingSystem.new()
var combat_system: CombatSystem = CombatSystem.new()
var trade_system: TradeSystem = TradeSystem.new()
var entity_registry: EntityRegistry = EntityRegistry.new()
var tick_loop: TickLoop = TickLoop.new()
var dispatcher: ActionDispatcher
var local_adapter: LocalAdapter
var remote_adapter := RemoteAdapter.new()
var adapter: Variant

var current_world_name := "START"
var player_id := LOCAL_PLAYER_ID
var player_name := LOCAL_PLAYER_NAME
var _state_dirty := true
var _public_state := {
	"player_pos": Vector2i.ZERO,
	"facing": Vector2i.RIGHT,
	"hotbar": [],
	"selected_hotbar_index": 0,
	"inventory": null,
	"dropped_items": []
}
var _action_cooldown_ms := {
	GameAction.ActionType.BREAK: ACTION_COOLDOWN_MS,
	GameAction.ActionType.PLACE_DIRT: ACTION_COOLDOWN_MS,
	GameAction.ActionType.PLANT_SEED: ACTION_COOLDOWN_MS,
	GameAction.ActionType.LOCK_SMALL: 400,
	GameAction.ActionType.LOCK_BIG: 400,
	GameAction.ActionType.TRADE: 300
}
var _last_action_at_ms: Dictionary = {}


func _init() -> void:
	rng.randomize()
	dispatcher = ActionDispatcher.new(self)
	local_adapter = LocalAdapter.new(dispatcher)
	adapter = local_adapter
	tick_loop.tick_emitted.connect(_on_tick)
	_sync_public_state()


func bootstrap_demo_world() -> void:
	if not _load_player_profile():
		_seed_new_player()
	join_world(current_world_name)
	emit_signal("state_changed", "Login sukses. Nama: %s | Character: %s." % [player_name, current_character_name()])


func apply_session_override(session_username: String, _session_character_id: String, session_world_name: String) -> void:
	var normalized_name: String = session_username.strip_edges()
	if normalized_name != "":
		player_name = normalized_name
		player_id = "local_%s" % normalized_name.to_lower().replace(" ", "_")
	character_system.set_current_character(DEFAULT_CHARACTER_ID)
	var normalized_world: String = session_world_name.strip_edges().to_upper()
	if normalized_world != "":
		if normalized_world != current_world_name:
			join_world(normalized_world)
		else:
			_save_player_profile()
	emit_signal("state_changed", "Session aktif: %s | Character: %s | World: %s" % [player_name, current_character_name(), current_world_name])


func _seed_new_player() -> void:
	player_id = LOCAL_PLAYER_ID
	player_name = LOCAL_PLAYER_NAME
	inventory_system.seed_new_player()
	character_system.set_current_character(DEFAULT_CHARACTER_ID)
	current_world_name = "START"
	_mark_dirty()


func _save_player_profile() -> void:
	var payload := {
		"player_id": player_id,
		"player_name": player_name,
		"current_character_id": character_system.current_character_id,
		"current_world_name": current_world_name
	}
	payload.merge(inventory_system.to_profile(), true)
	save_system.save_player(payload)


func _load_player_profile() -> bool:
	var payload := save_system.load_player()
	if payload.is_empty():
		return false
	player_id = str(payload.get("player_id", LOCAL_PLAYER_ID))
	player_name = str(payload.get("player_name", LOCAL_PLAYER_NAME))
	inventory_system.from_profile(payload)
	character_system.set_current_character(str(payload.get("current_character_id", DEFAULT_CHARACTER_ID)))
	current_world_name = str(payload.get("current_world_name", "START")).to_upper()
	if inventory_system.inventory.get_count(ItemDB.ID.SMALL_LOCK) <= 0:
		inventory_system.inventory.add_item(ItemDB.ID.SMALL_LOCK, 1)
	if inventory_system.inventory.get_count(ItemDB.ID.WORLD_LOCK) <= 0:
		inventory_system.inventory.add_item(ItemDB.ID.WORLD_LOCK, 1)
	_mark_dirty()
	return true


func join_world(world_name: String) -> void:
	var result: Dictionary = world_system.join_world(world, save_system, world_name, player_id)
	current_world_name = str(result.get("world_name", world_name)).to_upper()
	player_system.set_position(world.get_spawn_position())
	player_system.facing = Vector2i.RIGHT
	entity_registry.clear()
	_save_player_profile()
	_mark_dirty()
	if bool(result.get("created", false)):
		emit_signal("state_changed", "World baru '%s' dibuat. Spawn di Main Door." % current_world_name)
	else:
		emit_signal("state_changed", "Masuk world '%s'. Owner: %s" % [current_world_name, _owner_text()])


func quick_join_next_world() -> void:
	emit_signal("state_changed", "Gunakan input nama world dari menu (PLAY -> Enter World). World baru akan auto-generate saat pertama diakses.")


func set_manual_target(target: Vector2i) -> void:
	player_system.set_manual_target(target)


func set_player_position(pos: Vector2i) -> void:
	player_system.set_position(world.clamp_inside(pos))
	_mark_dirty()


func set_facing(direction: Vector2i) -> void:
	if direction == Vector2i.ZERO:
		return
	player_system.facing = direction
	_mark_dirty()


func update_player_motion_state(velocity: Vector2, on_ground: bool) -> void:
	player_system.apply_state_from_velocity(velocity, on_ground)


func player_state_name() -> String:
	return player_system.state_name()


func target_pos() -> Vector2i:
	return player_system.target_pos()


func break_target() -> void:
	break_at(target_pos())


func break_at(target: Vector2i) -> void:
	_run_action(GameAction.ActionType.BREAK, target)


func primary_action(target: Vector2i) -> void:
	var item: int = active_item_id()
	match item:
		-1, ItemDB.ID.PUNCH, ItemDB.ID.WOOD_PICKAXE, ItemDB.ID.STONE_PICKAXE, ItemDB.ID.IRON_PICKAXE:
			break_at(target)
		ItemDB.ID.DIRT, ItemDB.ID.SEED, ItemDB.ID.SMALL_LOCK, ItemDB.ID.WORLD_LOCK:
			use_active_item_at(target)
		_:
			use_active_item_at(target)


func target_preview_color(target: Vector2i) -> Color:
	var item: int = active_item_id()
	if item == ItemDB.ID.DIRT or item == ItemDB.ID.SEED or item == ItemDB.ID.SMALL_LOCK or item == ItemDB.ID.WORLD_LOCK:
		return Color(0.35, 1.0, 0.45, 0.9) if can_use_active_item_at(target) else Color(1.0, 0.35, 0.35, 0.9)
	return Color(1.0, 1.0, 1.0, 0.8)


func can_use_active_item_at(target: Vector2i) -> bool:
	var item: int = active_item_id()
	if item == ItemDB.ID.DIRT:
		return _can_place_dirt(target)
	if item == ItemDB.ID.SEED:
		return _can_plant_seed(target)
	if item == ItemDB.ID.SMALL_LOCK:
		return _can_place_small_lock(target)
	if item == ItemDB.ID.WORLD_LOCK:
		return _can_place_big_lock(target)
	return false


func select_hotbar(index: int) -> void:
	var item: int = inventory_system.select_hotbar(index)
	_mark_dirty()
	if item < 0:
		emit_signal("state_changed", "Slot %d kosong." % (index + 1))
	else:
		emit_signal("state_changed", "Slot %d aktif: %s." % [index + 1, _item_label(item)])


func cycle_hotbar(step: int) -> void:
	var item: int = inventory_system.cycle_hotbar(step)
	_mark_dirty()
	var active_index: int = inventory_system.selected_hotbar_index
	if item < 0:
		emit_signal("state_changed", "Slot %d kosong." % (active_index + 1))
	else:
		emit_signal("state_changed", "Slot %d aktif: %s." % [active_index + 1, _item_label(item)])


func active_item_id() -> int:
	return inventory_system.active_item_id()


func use_active_item() -> void:
	use_active_item_at(target_pos())


func use_active_item_at(target: Vector2i) -> void:
	var item: int = active_item_id()
	if item == ItemDB.ID.DIRT:
		_run_action(GameAction.ActionType.PLACE_DIRT, target)
		return
	if item == ItemDB.ID.SEED:
		_run_action(GameAction.ActionType.PLANT_SEED, target)
		return
	if item == ItemDB.ID.SMALL_LOCK:
		_run_action(GameAction.ActionType.LOCK_SMALL, target)
		return
	if item == ItemDB.ID.WORLD_LOCK:
		_run_action(GameAction.ActionType.LOCK_BIG, target)
		return
	if item < 0:
		emit_signal("state_changed", "Slot aktif kosong.")
		return
	emit_signal("state_changed", "Item '%s' belum punya aksi use." % _item_label(item))


func _can_place_dirt(target: Vector2i) -> bool:
	if not world.is_inside(target):
		return false
	if not _can_interact(target):
		return false
	if not world.can_modify(player_id, target):
		return false
	if world.get_block(target) != ItemDB.ID.AIR:
		return false
	if not inventory_system.inventory.has_item(ItemDB.ID.DIRT, 1):
		return false
	return true


func _can_plant_seed(target: Vector2i) -> bool:
	if not world.is_inside(target):
		return false
	if not _can_interact(target):
		return false
	if not world.can_modify(player_id, target):
		return false
	if not inventory_system.inventory.has_item(ItemDB.ID.SEED, 1):
		return false
	if not world.can_plant_at(target):
		return false
	return true


func _can_place_small_lock(target: Vector2i) -> bool:
	if not world.is_inside(target):
		return false
	if not _can_interact(target):
		return false
	if not inventory_system.inventory.has_item(ItemDB.ID.SMALL_LOCK, 1):
		return false
	return world.can_place_small_lock(player_id, target)


func _can_place_big_lock(target: Vector2i) -> bool:
	if not world.is_inside(target):
		return false
	if not _can_interact(target):
		return false
	if not inventory_system.inventory.has_item(ItemDB.ID.WORLD_LOCK, 1):
		return false
	return world.can_place_big_lock(player_id, target)


func try_trade() -> void:
	_run_action(GameAction.ActionType.TRADE, TRADE_POS)


func switch_character(_delta: int) -> void:
	character_system.set_current_character(DEFAULT_CHARACTER_ID)
	emit_signal("state_changed", "Tipe pemain dikunci ke default.")


func current_character_name() -> String:
	return character_system.current_character_name()


func current_character_color() -> Color:
	return character_system.current_character_color()


func character_passive_text() -> String:
	return character_system.current_passive_text()


func tick(delta: float) -> void:
	tick_loop.process_frame(delta)


func tick_growth() -> void:
	tick(1.0 / 60.0)


func _on_tick(_tick_id: int) -> void:
	if farming_system.tick_growth(world):
		emit_signal("state_changed", "Ada tanaman yang tumbuh.")
		_mark_dirty()
	entity_registry.tick_all(world)
	_mark_dirty()
	_pickup_near_player()
	world_system.save_world_if_dirty(save_system, world, false)
	if _state_dirty:
		_sync_public_state()
		_state_dirty = false


func _pickup_near_player() -> void:
	var picked: Dictionary = entity_registry.pickup_near(player_system.player_pos, inventory_system.inventory)
	if not picked.is_empty():
		emit_signal("state_changed", "Pickup: %s." % str(picked))
		_mark_dirty()


func _run_action(action_type: int, target: Vector2i, payload: Dictionary = {}) -> void:
	var action := GameAction.new(action_type, player_id, target, payload, tick_loop.tick_id)
	var result: ActionResult = adapter.execute(action)
	if result.reason != "":
		emit_signal("state_changed", result.reason)
	_mark_dirty()


func _can_interact(target: Vector2i) -> bool:
	if not world.is_inside(target):
		return false
	return _manhattan_distance(player_system.player_pos, target) <= ActionDispatcher.TILE_INTERACT_RANGE


func _manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func _begin_action(action_type: int) -> bool:
	var now := Time.get_ticks_msec()
	var last_action_at: int = int(_last_action_at_ms.get(action_type, 0))
	var cooldown: int = int(_action_cooldown_ms.get(action_type, ACTION_COOLDOWN_MS))
	var diff := now - last_action_at
	if diff < cooldown:
		var remaining: int = cooldown - diff
		emit_signal("state_changed", "Action cooldown: tunggu %d ms." % remaining)
		return false
	_last_action_at_ms[action_type] = now
	return true


func consume_action_window(action_type: int) -> bool:
	return _begin_action(action_type)


func cooldown_remaining_ms(action_type: int = GameAction.ActionType.BREAK) -> int:
	var now := Time.get_ticks_msec()
	var cooldown: int = int(_action_cooldown_ms.get(action_type, ACTION_COOLDOWN_MS))
	var last_action_at: int = int(_last_action_at_ms.get(action_type, 0))
	return max(0, cooldown - (now - last_action_at))


func save_game() -> bool:
	_save_player_profile()
	var ok := world_system.save_world_if_dirty(save_system, world, true)
	emit_signal("state_changed", "Save %s." % ("berhasil" if ok else "gagal"))
	return ok


func load_game() -> bool:
	if not _load_player_profile():
		emit_signal("state_changed", "Data player belum ada.")
		return false
	join_world(current_world_name)
	emit_signal("state_changed", "Load berhasil.")
	return true


func lock_summary() -> String:
	return world_system.lock_summary(world, player_id, player_name)


func _owner_text() -> String:
	if world.owner_id == "":
		return "none"
	if world.owner_id == player_id:
		return "%s (you)" % player_name
	return world.owner_id


func _sync_public_state() -> void:
	_public_state["player_pos"] = player_system.player_pos
	_public_state["facing"] = player_system.facing
	_public_state["hotbar"] = inventory_system.hotbar.duplicate()
	_public_state["selected_hotbar_index"] = inventory_system.selected_hotbar_index
	_public_state["inventory"] = inventory_system.inventory
	_public_state["dropped_items"] = entity_registry.to_render_array()


func _mark_dirty() -> void:
	_state_dirty = true


func get_player_pos() -> Vector2i:
	return player_system.player_pos


func get_facing() -> Vector2i:
	return player_system.facing


func get_hotbar() -> Array[int]:
	var cached: Array = inventory_system.hotbar
	var out: Array[int] = []
	for item in cached:
		out.append(int(item))
	return out


func get_selected_hotbar_index() -> int:
	return inventory_system.selected_hotbar_index


func get_inventory() -> Inventory:
	return inventory_system.inventory


func get_dropped_items() -> Array[Dictionary]:
	return entity_registry.to_render_array()


func _item_label(item_id: int) -> String:
	var item_data: Dictionary = ItemDB.get_item(item_id)
	return str(item_data.get("name", str(item_id)))
