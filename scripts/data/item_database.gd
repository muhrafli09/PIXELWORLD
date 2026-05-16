extends Node

enum Property {
	NONE = 0,
	NO_SEED = 1,
	DROPLESS = 2,
	WRENCHABLE = 4,
	MULTI_FACING = 8,
	PERMANENT = 16,
	AUTO_PICKUP = 32,
	WORLD_LOCK = 64,
	FOREGROUND = 128,
	NO_SHADOW = 256,
	RANDOM_GROW = 512,
	PUBLIC = 1024,
	UNTRADABLE = 2048,
	MOD = 4096,
	NO_SELF = 8192,
	HOLIDAY = 16384,
	BETA = 32768
}

enum Category {
	FOREGROUND_BLOCK,
	BACKGROUND_BLOCK,
	SEED,
	PLATFORM,
	DOOR,
	MAIN_DOOR,
	LOCK,
	SIGN,
	TOOL,
	CLOTHING,
	CONSUMABLE,
	GEMS,
	PAIN_BLOCK,
	SPIKE,
	SLIPPERY_BLOCK,
	TRAMPOLINE_BLOCK,
	BEDROCK,
	AIR
}

enum ClothingSlot {
	NONE,
	HAT,
	FACE,
	HAIR,
	SHIRT,
	PANTS,
	FEET,
	HAND,
	BACK,
	CHEST
}

const DATA_PATH := "res://data/items.tsv"
const ID := {
	"AIR": 0,
	"DIRT": 2,
	"DIRT_SEED": 3,
	"STONE": 4,
	"STONE_SEED": 5,
	"GRASS_BLOCK": 6,
	"GRASS_SEED": 7,
	"SAND": 8,
	"SAND_SEED": 9,
	"BEDROCK": 10,
	"CAVE_BACKGROUND": 12,
	"CAVE_SEED": 13,
	"WOOD_BACKGROUND": 14,
	"WOOD_SEED": 15,
	"LAVA": 16,
	"EMBER_SEED": 17,
	"WOOD_BLOCK": 18,
	"TIMBER_SEED": 19,
	"COPPER_ORE": 20,
	"COPPER_SEED": 21,
	"IRON_ORE": 22,
	"IRON_SEED": 23,
	"CRYSTAL_SHARD": 24,
	"CRYSTAL_SEED": 25,
	"COAL_BLOCK": 26,
	"COAL_SEED": 27,
	"CLAY_BLOCK": 28,
	"CLAY_SEED": 29,
	"BRICK_BLOCK": 30,
	"BRICK_SEED": 31,
	"GLASS_BLOCK": 32,
	"GLASS_SEED": 33,
	"WOOD_PLANK": 34,
	"PLANK_SEED": 35,
	"WOOD_PLATFORM": 36,
	"PLATFORM_SEED": 37,
	"STONE_BRICK": 38,
	"STONE_BRICK_SEED": 39,
	"LANTERN": 40,
	"LANTERN_SEED": 41,
	"SIGN": 42,
	"SIGN_SEED": 43,
	"PAINTED_BLOCK": 44,
	"PAINTED_SEED": 45,
	"SPIKES": 46,
	"SPIKE_SEED": 47,
	"THORN_BUSH": 48,
	"THORN_SEED": 49,
	"ICE_BLOCK": 50,
	"ICE_SEED": 51,
	"MAIN_DOOR": 52,
	"WOOD_DOOR": 54,
	"SMALL_LOCK": 56,
	"WORLD_LOCK": 58,
	"GATEWAY": 60,
	"PUNCH": 62,
	"WRENCH": 64,
	"WOOD_PICKAXE": 66,
	"IRON_PICKAXE": 68,
	"SEED": 70,
	"FRUIT": 72,
	"GEM": 74,
	"HEALTH_TONIC": 76,
	"PIONEER_HAT": 78,
	"CLOTH_SHIRT": 80,
	"CLOTH_PANTS": 82,
	"TRAIL_BOOTS": 84,
	"FRONTIER_BACKPACK": 86,
	"PLANT_0": 88,
	"PLANT_1": 90,
	"PLANT_2": 92,
	"STONE_PICKAXE": 94,
	"BIG_LOCK": 58
}

var _items: Dictionary = {}
var _name_to_id: Dictionary = {}


func _ready() -> void:
	_load_item_data()
	if _items.size() < 40:
		push_warning("ItemDB loaded only %d items. Expected >= 40." % _items.size())


func _load_item_data() -> void:
	_items.clear()
	_name_to_id.clear()
	if not FileAccess.file_exists(DATA_PATH):
		push_warning("ItemDB TSV missing at %s" % DATA_PATH)
		return
	var file: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("ItemDB failed to open %s" % DATA_PATH)
		return
	var text: String = file.get_as_text()
	file.close()
	var lines: PackedStringArray = text.split("\n")
	for i in range(lines.size()):
		var line_number: int = i + 1
		var raw: String = lines[i].strip_edges()
		if raw == "" or raw.begins_with("//"):
			continue
		if raw.begins_with("ID|"):
			continue
		var cols: PackedStringArray = raw.split("|")
		if cols.size() < 10:
			push_warning("ItemDB invalid row %d: expected 10 columns." % line_number)
			continue
		var id: int = int(cols[0].strip_edges())
		var item_name: String = cols[1].strip_edges()
		if id < 0 or item_name == "":
			push_warning("ItemDB invalid row %d: bad id/name." % line_number)
			continue
		if _items.has(id):
			push_warning("ItemDB duplicate id at row %d: %d" % [line_number, id])
			continue

		var rarity: int = max(1, int(cols[2].strip_edges()))
		var properties: int = _parse_properties(cols[3])
		var category: int = _parse_category(cols[4])
		var base_color: Color = _parse_hex_color(cols[5], Color.WHITE)
		var overlay_color: Color = _parse_hex_color(cols[6], base_color)
		var hits_to_break: int = max(0, int(cols[7].strip_edges()))
		var growtime_sec: int = max(0, int(cols[8].strip_edges()))
		var clothing_slot: int = _parse_clothing_slot(cols[9])

		var data := {
			"id": id,
			"name": item_name,
			"rarity": rarity,
			"properties": properties,
			"category": category,
			"base_color": base_color,
			"overlay_color": overlay_color,
			"hits_to_break": hits_to_break,
			"growtime_sec": growtime_sec,
			"clothing_slot": clothing_slot
		}
		_derive_item_fields(data)
		_items[id] = data
		_register_name_aliases(item_name, id)


func _parse_properties(raw_value: String) -> int:
	var out := 0
	var tokens: PackedStringArray = raw_value.split(",")
	for token_raw in tokens:
		var token: String = token_raw.strip_edges().to_upper().replace("-", "_").replace(" ", "_")
		if token == "" or token == "NONE":
			continue
		token = token.replace("__", "_")
		match token:
			"NOSEED":
				token = "NO_SEED"
			"WORLDLOCK":
				token = "WORLD_LOCK"
			"AUTOPICKUP":
				token = "AUTO_PICKUP"
		if Property.has(token):
			out |= Property[token]
	return out


func _parse_category(raw_value: String) -> int:
	var token: String = raw_value.strip_edges().to_upper().replace("-", "_").replace(" ", "_")
	if Category.has(token):
		return Category[token]
	return Category.FOREGROUND_BLOCK


func _parse_clothing_slot(raw_value: String) -> int:
	var token: String = raw_value.strip_edges().to_upper().replace("-", "_").replace(" ", "_")
	if ClothingSlot.has(token):
		return ClothingSlot[token]
	return ClothingSlot.NONE


func _parse_hex_color(raw_value: String, fallback: Color) -> Color:
	var token: String = raw_value.strip_edges()
	if token == "":
		return fallback
	if not token.begins_with("#"):
		token = "#" + token
	return Color.from_string(token, fallback)


func _derive_item_fields(data: Dictionary) -> void:
	var category: int = int(data.get("category", Category.FOREGROUND_BLOCK))
	var properties: int = int(data.get("properties", Property.NONE))
	var rarity: int = int(data.get("rarity", 1))
	var id: int = int(data.get("id", -1))
	var hits_to_break: int = int(data.get("hits_to_break", 0))

	var is_solid: bool = (
		category == Category.FOREGROUND_BLOCK
		or category == Category.DOOR
		or category == Category.LOCK
		or category == Category.PLATFORM
		or category == Category.BEDROCK
		or category == Category.SPIKE
		or category == Category.PAIN_BLOCK
		or category == Category.SLIPPERY_BLOCK
	)
	var is_tool: bool = category == Category.TOOL
	var is_air: bool = category == Category.AIR
	var is_lock: bool = category == Category.LOCK
	var is_breakable: bool = not is_air and hits_to_break > 0 and ((properties & Property.PERMANENT) == 0)

	var stack_limit_value := 200
	if is_air:
		stack_limit_value = 0
	elif is_tool or is_lock:
		stack_limit_value = 1

	var drops: Array[Dictionary] = []
	if not is_air and ((properties & Property.DROPLESS) == 0):
		drops.append({"item_id": id, "amount": 1})

	data["is_solid"] = is_solid
	data["is_breakable"] = is_breakable
	data["is_tool"] = is_tool
	data["tool_power"] = int(floor(float(rarity) / 10.0)) + 1 if is_tool else 0
	data["stack_limit"] = stack_limit_value
	data["drops"] = drops


func _register_name_aliases(item_name: String, id: int) -> void:
	var key: String = _normalize_name(item_name)
	if key != "":
		_name_to_id[key] = id
	var snake: String = _snake_name(item_name)
	if snake != "":
		_name_to_id[snake] = id


func _normalize_name(value: String) -> String:
	var out: String = value.strip_edges().to_lower()
	out = out.replace("-", "_").replace(" ", "_")
	return out


func _snake_name(value: String) -> String:
	var out: String = _normalize_name(value)
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.trim_prefix("_").trim_suffix("_")


func get_item(id: int) -> Dictionary:
	return (_items.get(id, {}) as Dictionary).duplicate(true)


func get_id(name: String) -> int:
	var normalized: String = _normalize_name(name)
	if _name_to_id.has(normalized):
		return int(_name_to_id[normalized])
	var key: String = normalized.to_upper()
	if ID.has(key):
		return int(ID[key])
	return -1


func is_known(id: int) -> bool:
	return _items.has(id)


func is_solid(id: int) -> bool:
	return bool((_items.get(id, {}) as Dictionary).get("is_solid", false))


func is_breakable(id: int) -> bool:
	return bool((_items.get(id, {}) as Dictionary).get("is_breakable", false))


func is_tool_item(id: int) -> bool:
	return bool((_items.get(id, {}) as Dictionary).get("is_tool", false))


func tool_power(id: int) -> int:
	return int((_items.get(id, {}) as Dictionary).get("tool_power", 0))


func stack_limit(id: int) -> int:
	return int((_items.get(id, {}) as Dictionary).get("stack_limit", 200))


func break_hits(id: int) -> int:
	return int((_items.get(id, {}) as Dictionary).get("hits_to_break", 0))


func drops_for(id: int) -> Array[Dictionary]:
	var raw: Array = (_items.get(id, {}) as Dictionary).get("drops", [])
	var out: Array[Dictionary] = []
	for entry in raw:
		if typeof(entry) == TYPE_DICTIONARY:
			out.append((entry as Dictionary).duplicate(true))
	return out


func get_rarity(id: int) -> int:
	return int((_items.get(id, {}) as Dictionary).get("rarity", 1))


func get_category(id: int) -> int:
	return int((_items.get(id, {}) as Dictionary).get("category", Category.FOREGROUND_BLOCK))


func get_base_color(id: int) -> Color:
	return (_items.get(id, {}) as Dictionary).get("base_color", Color.WHITE) as Color


func get_overlay_color(id: int) -> Color:
	return (_items.get(id, {}) as Dictionary).get("overlay_color", Color.WHITE) as Color


func get_growtime(id: int) -> int:
	return int((_items.get(id, {}) as Dictionary).get("growtime_sec", 0))


func get_clothing_slot(id: int) -> int:
	return int((_items.get(id, {}) as Dictionary).get("clothing_slot", ClothingSlot.NONE))


func has_property(id: int, prop: int) -> bool:
	var value: int = int((_items.get(id, {}) as Dictionary).get("properties", Property.NONE))
	return (value & prop) != 0
