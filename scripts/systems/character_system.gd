class_name CharacterSystem
extends RefCounted

const DEFAULT_CHARACTER_ID := "farmer"

var current_character_id := DEFAULT_CHARACTER_ID

var _definitions := {
	"farmer": {
		"display_name": "Farmer",
		"color": Color(0.2, 0.85, 0.35, 1.0),
		"passive_text": "20% chance seed refund saat tanam",
		"seed_refund_chance": 0.2,
		"miner_bonus_dirt_chance": 0.0,
		"trade_rate_bonus": 0
	},
	"miner": {
		"display_name": "Miner",
		"color": Color(0.55, 0.75, 0.95, 1.0),
		"passive_text": "35% chance bonus +1 dirt saat break dirt",
		"seed_refund_chance": 0.0,
		"miner_bonus_dirt_chance": 0.35,
		"trade_rate_bonus": 0
	},
	"trader": {
		"display_name": "Trader",
		"color": Color(0.95, 0.8, 0.22, 1.0),
		"passive_text": "Rate jual fruit lebih tinggi",
		"seed_refund_chance": 0.0,
		"miner_bonus_dirt_chance": 0.0,
		"trade_rate_bonus": 1
	}
}


func set_current_character(character_id: String) -> void:
	var normalized: String = character_id.strip_edges().to_lower()
	if not _definitions.has(normalized):
		current_character_id = DEFAULT_CHARACTER_ID
		return
	current_character_id = normalized


func current_character_name() -> String:
	return str(_active_def().get("display_name", "Unknown"))


func current_character_color() -> Color:
	return _active_def().get("color", Color.CORNFLOWER_BLUE) as Color


func current_passive_text() -> String:
	return str(_active_def().get("passive_text", "-"))


func seed_refund_chance() -> float:
	return float(_active_def().get("seed_refund_chance", 0.0))


func miner_bonus_dirt_chance() -> float:
	return float(_active_def().get("miner_bonus_dirt_chance", 0.0))


func trade_rate_bonus() -> int:
	return int(_active_def().get("trade_rate_bonus", 0))


func _active_def() -> Dictionary:
	return _definitions.get(current_character_id, _definitions[DEFAULT_CHARACTER_ID]) as Dictionary
