class_name InventorySystem
extends RefCounted

const HOTBAR_SIZE := 16

var inventory := Inventory.new()
var hotbar: Array[int] = []
var selected_hotbar_index := 0


func seed_new_player() -> void:
	inventory = Inventory.new()
	inventory.add_item(ItemDB.ID.DIRT, 64)
	inventory.add_item(ItemDB.ID.SEED, 20)
	inventory.add_item(ItemDB.ID.SMALL_LOCK, 2)
	inventory.add_item(ItemDB.ID.WORLD_LOCK, 1)
	hotbar = build_default_hotbar()
	selected_hotbar_index = 0


func from_profile(payload: Dictionary) -> void:
	inventory.from_dict(payload.get("inventory", {}))
	hotbar = normalize_hotbar(payload.get("hotbar", build_default_hotbar()))
	selected_hotbar_index = int(payload.get("selected_hotbar_index", 0))
	selected_hotbar_index = clamp(selected_hotbar_index, 0, hotbar.size() - 1)
	ensure_break_tool_access()


func to_profile() -> Dictionary:
	return {
		"inventory": inventory.to_dict(),
		"hotbar": hotbar,
		"selected_hotbar_index": selected_hotbar_index
	}


func select_hotbar(index: int) -> int:
	if index < 0 or index >= hotbar.size():
		return -1
	selected_hotbar_index = index
	return active_item_id()


func cycle_hotbar(step: int) -> int:
	if hotbar.is_empty():
		return -1
	var normalized_step: int = step if step != 0 else 1
	selected_hotbar_index = posmod(selected_hotbar_index + normalized_step, hotbar.size())
	return active_item_id()


func active_item_id() -> int:
	if selected_hotbar_index < 0 or selected_hotbar_index >= hotbar.size():
		return -1
	return hotbar[selected_hotbar_index]


func is_active_break_tool() -> bool:
	var item_id: int = active_item_id()
	if not ItemDB.is_tool_item(item_id):
		return false
	if item_id == ItemDB.ID.PUNCH:
		return true
	return inventory.has_item(item_id, 1)


func active_tool_power() -> int:
	var item_id: int = active_item_id()
	if not is_active_break_tool():
		return 0
	return ItemDB.tool_power(item_id)


func normalize_hotbar(raw_hotbar: Array) -> Array[int]:
	var output: Array[int] = []
	for slot in raw_hotbar:
		output.append(int(slot))
	while output.size() < HOTBAR_SIZE:
		output.append(-1)
	if output.size() > HOTBAR_SIZE:
		output = output.slice(0, HOTBAR_SIZE)
	output[0] = ItemDB.ID.PUNCH
	return output


func build_default_hotbar() -> Array[int]:
	var defaults: Array[int] = [ItemDB.ID.PUNCH, ItemDB.ID.DIRT, ItemDB.ID.SEED, ItemDB.ID.SMALL_LOCK, ItemDB.ID.WORLD_LOCK]
	while defaults.size() < HOTBAR_SIZE:
		defaults.append(-1)
	return defaults


func ensure_break_tool_access() -> void:
	if hotbar.is_empty():
		hotbar = build_default_hotbar()
	if hotbar[0] != ItemDB.ID.PUNCH:
		hotbar[0] = ItemDB.ID.PUNCH
