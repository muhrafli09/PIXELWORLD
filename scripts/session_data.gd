extends Node

const DEFAULT_CHARACTER := "farmer"
const DEFAULT_WORLD := "START"

var username := "Player"
var character_id := DEFAULT_CHARACTER
var world_name := DEFAULT_WORLD
var remember_me := false


func set_profile(p_username: String, p_character_id: String, p_world_name: String, p_remember_me: bool) -> void:
	username = p_username.strip_edges()
	if username == "":
		username = "Player"
	character_id = p_character_id.strip_edges().to_lower()
	if character_id == "":
		character_id = DEFAULT_CHARACTER
	world_name = p_world_name.strip_edges().to_upper()
	if world_name == "":
		world_name = DEFAULT_WORLD
	remember_me = p_remember_me
