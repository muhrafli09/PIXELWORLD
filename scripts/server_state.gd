extends Node

var _online_players: Dictionary = {}
var _server_started_at_ms := 0
var _simulated_global_online := 1280
var _simulated_ping_ms := 42
var _remote_players: Dictionary = {}


func _ready() -> void:
	_server_started_at_ms = Time.get_ticks_msec()
	randomize()


func tick_simulation(delta: float) -> void:
	# Small drift so HUD feels alive in offline mode.
	if randi_range(0, 100) < int(6.0 * delta * 60.0):
		_simulated_global_online = clampi(_simulated_global_online + randi_range(-3, 4), 900, 3200)
	if randi_range(0, 100) < int(10.0 * delta * 60.0):
		_simulated_ping_ms = clampi(_simulated_ping_ms + randi_range(-2, 3), 18, 95)
	for key in _remote_players.keys():
		var p: Dictionary = _remote_players[key]
		var timer: float = max(0.0, float(p.get("bubble_timer", 0.0)) - delta)
		p["bubble_timer"] = timer
		if timer <= 0.0:
			p["bubble_text"] = ""
		if randi_range(0, 1000) < 4:
			p["bubble_text"] = _random_chat_line()
			p["bubble_timer"] = 4.0
		_remote_players[key] = p


func update_local_presence(player_name: String, world_name: String) -> void:
	_online_players["local"] = {
		"name": player_name,
		"world": world_name.to_upper()
	}
	_ensure_world_population(world_name)


func total_online() -> int:
	# Prototype mode: simulated global + local client.
	return _simulated_global_online + _online_players.size()


func world_online(world_name: String) -> int:
	var normalized := world_name.to_upper()
	var seed_val := int(abs(hash(normalized)))
	var simulated := 4 + (seed_val % 41)
	var local_here := 0
	for player in _online_players.values():
		if str((player as Dictionary).get("world", "")).to_upper() == normalized:
			local_here += 1
	return simulated + local_here


func current_ping_ms() -> int:
	return _simulated_ping_ms


func uptime_text() -> String:
	var elapsed_sec := int((Time.get_ticks_msec() - _server_started_at_ms) / 1000)
	var hours := int(elapsed_sec / 3600)
	var minutes := int((elapsed_sec % 3600) / 60)
	var seconds := int(elapsed_sec % 60)
	if hours > 0:
		return "%dh %02dm" % [hours, minutes]
	if minutes > 0:
		return "%dm %02ds" % [minutes, seconds]
	return "%ds" % seconds


func remote_players_for_world(world_name: String) -> Array[Dictionary]:
	_ensure_world_population(world_name)
	var normalized := world_name.to_upper()
	var out: Array[Dictionary] = []
	for p in _remote_players.values():
		var player: Dictionary = p as Dictionary
		if str(player.get("world", "")).to_upper() != normalized:
			continue
		out.append(player.duplicate(true))
	return out


func _ensure_world_population(world_name: String) -> void:
	var normalized := world_name.to_upper()
	var existing := 0
	for p in _remote_players.values():
		if str((p as Dictionary).get("world", "")).to_upper() == normalized:
			existing += 1
	if existing >= 6:
		return
	var base_seed := int(abs(hash(normalized)))
	var rng := RandomNumberGenerator.new()
	rng.seed = base_seed
	for i in range(existing, 6):
		var id := "%s_%d" % [normalized, i]
		if _remote_players.has(id):
			continue
		var x := rng.randi_range(8, WorldData.WORLD_WIDTH - 8)
		var y := rng.randi_range(20, 36)
		_remote_players[id] = {
			"id": id,
			"name": "Player%d" % (i + 1),
			"world": normalized,
			"pos": Vector2(x, y),
			"bubble_text": "",
			"bubble_timer": 0.0
		}


func _random_chat_line() -> String:
	var lines := [
		"halo semua",
		"jual seed murah",
		"siapa di START?",
		"farm dulu bro",
		"need trade gem",
		"world ini rame"
	]
	return lines[randi_range(0, lines.size() - 1)]
