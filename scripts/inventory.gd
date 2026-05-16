class_name Inventory
extends RefCounted

var items: Dictionary = {}


func add_item(item_id: int, amount: int = 1) -> void:
	if amount <= 0:
		return
	var current: int = int(items.get(item_id, 0))
	var max_stack: int = stack_limit_for(item_id)
	if max_stack <= 0:
		return
	var next_amount: int = min(max_stack, current + amount)
	if next_amount <= 0:
		items.erase(item_id)
		return
	items[item_id] = next_amount


func has_item(item_id: int, amount: int = 1) -> bool:
	return int(items.get(item_id, 0)) >= amount


func get_count(item_id: int) -> int:
	return int(items.get(item_id, 0))


func remove_item(item_id: int, amount: int = 1) -> bool:
	if not has_item(item_id, amount):
		return false
	items[item_id] = int(items[item_id]) - amount
	if int(items[item_id]) <= 0:
		items.erase(item_id)
	return true


func to_dict() -> Dictionary:
	return {"items": items.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	items = {}
	var raw_items: Dictionary = data.get("items", {})
	for item_id in raw_items.keys():
		var normalized_id: int = int(item_id)
		var amount: int = int(raw_items.get(item_id, 0))
		if amount <= 0:
			continue
		if not ItemDB.is_known(normalized_id):
			continue
		items[normalized_id] = min(stack_limit_for(normalized_id), amount)


func stack_limit_for(item_id: int) -> int:
	return ItemDB.stack_limit(item_id)
