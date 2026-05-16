extends Node2D

const BASE_CELL_SIZE := 32.0
const VIEW_HALF_WIDTH := 15
const VIEW_HALF_HEIGHT := 8
const PLAYER_HALF_SIZE := Vector2(0.36, 0.42)
const MAX_RUN_SPEED := 6.2
const GROUND_ACCEL := 52.0
const AIR_ACCEL := 24.0
const GROUND_FRICTION := 44.0
const JUMP_VELOCITY := -11.4
const GRAVITY := 28.0
const MAX_FALL_SPEED := 16.0
const COYOTE_TIME := 0.10
const JUMP_BUFFER_TIME := 0.12
const HOTBAR_COLUMNS := 8
const HOTBAR_VISIBLE_SLOTS := 8
const HOTBAR_SLOT_SIZE := Vector2(108, 44)
const HOTBAR_SLOT_GAP := 6.0
const ZOOM_STEP := 0.1
const MIN_ZOOM := 0.6
const MAX_ZOOM := 1.8
const ZOOM_LERP_SPEED := 8.0
const CAMERA_FOLLOW_SPEED := 10.0
const POPUP_LIFETIME := 2.2
const POPUP_MAX := 6
const CHAT_MAX := 200
const CHAT_VISIBLE_LINES := 8
const COLLISION_SKIN := 0.02
const DRAWER_ANIM_SPEED := 9.0
const CHAT_DRAWER_HEIGHT := 200.0
const BACKPACK_DRAWER_HEIGHT := 240.0
const DRAWER_HANDLE_HEIGHT := 20.0
const CHAT_INPUT_MAX_CHARS := 120
const CHAT_COOLDOWN_MS := 700
const REMOTE_BUBBLE_CULL_DISTANCE := 22.0

var logic: GameLogic = GameLogic.new()
var status_text := "Ready"
var player_world_pos := Vector2.ZERO
var player_velocity := Vector2.ZERO
var is_on_ground := false
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var zoom_target := 1.0
var zoom_current := 1.0
var camera_world_pos := Vector2.ZERO
var popup_messages: Array[Dictionary] = []
var chat_messages: Array[Dictionary] = []
var chat_drawer_open := 0.0
var chat_drawer_target := 0.0
var backpack_drawer_open := 0.0
var backpack_drawer_target := 0.0
var dragging_chat_drawer := false
var dragging_backpack_drawer := false
var chat_scroll_offset := 0
var backpack_scroll_offset := 0
var show_pause_menu := false
var show_debug_overlay := false
var chat_input_active := false
var chat_input_text := ""
var last_chat_sent_ms := 0
var player_chat_bubble := ""
var player_chat_timer := 0.0
var server_state: Node
var remote_players_cache: Array[Dictionary] = []


func _ready() -> void:
	logic.state_changed.connect(_on_state_changed)
	logic.bootstrap_demo_world()
	var session: Node = get_node_or_null("/root/SessionData")
	if session != null:
		logic.apply_session_override(
			str(session.get("username")),
			str(session.get("character_id")),
			str(session.get("world_name"))
		)
	var initial_pos: Vector2i = logic.get_player_pos()
	player_world_pos = Vector2(initial_pos.x, initial_pos.y)
	camera_world_pos = player_world_pos
	server_state = get_node_or_null("/root/ServerState")
	if server_state != null:
		server_state.update_local_presence(logic.player_name, logic.current_world_name)
	set_process(true)
	set_physics_process(true)


func _process(delta: float) -> void:
	logic.tick(delta)
	_apply_zoom_limits()
	zoom_current = lerpf(zoom_current, zoom_target, clampf(delta * ZOOM_LERP_SPEED, 0.0, 1.0))
	camera_world_pos = camera_world_pos.lerp(player_world_pos, clampf(delta * CAMERA_FOLLOW_SPEED, 0.0, 1.0))
	chat_drawer_open = move_toward(chat_drawer_open, chat_drawer_target, delta * DRAWER_ANIM_SPEED)
	backpack_drawer_open = move_toward(backpack_drawer_open, backpack_drawer_target, delta * DRAWER_ANIM_SPEED)
	if server_state != null:
		server_state.tick_simulation(delta)
		server_state.update_local_presence(logic.player_name, logic.current_world_name)
		remote_players_cache = server_state.remote_players_for_world(logic.current_world_name)
	_tick_popups(delta)
	if player_chat_timer > 0.0:
		player_chat_timer = max(0.0, player_chat_timer - delta)
		if player_chat_timer <= 0.0:
			player_chat_bubble = ""
	logic.set_manual_target(_screen_to_world_tile(get_viewport().get_mouse_position()))
	queue_redraw()


func _physics_process(delta: float) -> void:
	var move_axis := Input.get_axis("move_left", "move_right")
	if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_accept"):
		jump_buffer_timer = JUMP_BUFFER_TIME

	if move_axis > 0.0:
		logic.set_facing(Vector2i.RIGHT)
	elif move_axis < 0.0:
		logic.set_facing(Vector2i.LEFT)

	var accel := GROUND_ACCEL if is_on_ground else AIR_ACCEL
	if move_axis != 0.0:
		player_velocity.x = move_toward(player_velocity.x, move_axis * MAX_RUN_SPEED, accel * delta)
	elif is_on_ground:
		player_velocity.x = move_toward(player_velocity.x, 0.0, GROUND_FRICTION * delta)

	if is_on_ground:
		coyote_timer = COYOTE_TIME
	else:
		coyote_timer = max(0.0, coyote_timer - delta)

	if jump_buffer_timer > 0.0:
		jump_buffer_timer = max(0.0, jump_buffer_timer - delta)

	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		player_velocity.y = JUMP_VELOCITY
		is_on_ground = false
		coyote_timer = 0.0
		jump_buffer_timer = 0.0

	if not is_on_ground:
		player_velocity.y = min(player_velocity.y + (GRAVITY * delta), MAX_FALL_SPEED)

	_move_with_collision(player_velocity * delta)
	_snap_to_ground_if_needed()
	_sync_player_to_logic()
	logic.update_player_motion_state(player_velocity, is_on_ground)


func _unhandled_input(event: InputEvent) -> void:
	if chat_input_active and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER:
			_send_chat_message(chat_input_text)
			chat_input_text = ""
			chat_input_active = false
			return
		if event.keycode == KEY_ESCAPE:
			chat_input_active = false
			return
		if event.keycode == KEY_BACKSPACE:
			if chat_input_text.length() > 0:
				chat_input_text = chat_input_text.substr(0, chat_input_text.length() - 1)
			return
		if event.unicode > 0 and chat_input_text.length() < CHAT_INPUT_MAX_CHARS:
			chat_input_text += char(event.unicode)
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_I, KEY_B:
				backpack_drawer_target = 0.0 if backpack_drawer_target > 0.5 else 1.0
				return
			KEY_ENTER:
				chat_drawer_target = 1.0
				chat_input_active = true
				return
			KEY_F3:
				show_debug_overlay = not show_debug_overlay
				return
			KEY_6:
				logic.select_hotbar(5)
				return
			KEY_7:
				logic.select_hotbar(6)
				return
			KEY_8:
				logic.select_hotbar(7)
				return

	if event.is_action_pressed("ui_cancel"):
		show_pause_menu = not show_pause_menu
		return

	if event is InputEventMouseMotion:
		if dragging_chat_drawer:
			var max_h: float = CHAT_DRAWER_HEIGHT
			chat_drawer_open = clampf((event.position.y - DRAWER_HANDLE_HEIGHT) / max_h, 0.0, 1.0)
			chat_drawer_target = chat_drawer_open
			return
		if dragging_backpack_drawer:
			var viewport_h: float = get_viewport_rect().size.y
			var pull: float = viewport_h - event.position.y - DRAWER_HANDLE_HEIGHT
			backpack_drawer_open = clampf(pull / BACKPACK_DRAWER_HEIGHT, 0.0, 1.0)
			backpack_drawer_target = backpack_drawer_open
			return

	if show_pause_menu:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _chat_handle_rect().has_point(event.position):
				dragging_chat_drawer = true
				return
			if _backpack_handle_rect().has_point(event.position):
				dragging_backpack_drawer = true
				return
			if _chat_panel_rect().has_point(event.position):
				chat_drawer_target = 1.0
				chat_input_active = true
				return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _chat_panel_rect().has_point(event.position):
				chat_scroll_offset = max(0, chat_scroll_offset - 1)
				return
			if _backpack_panel_rect().has_point(event.position):
				backpack_scroll_offset = max(0, backpack_scroll_offset - 1)
				return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _chat_panel_rect().has_point(event.position):
				chat_scroll_offset += 1
				return
			if _backpack_panel_rect().has_point(event.position):
				backpack_scroll_offset += 1
				return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if event.ctrl_pressed:
				_adjust_zoom(-ZOOM_STEP)
				return
			logic.cycle_hotbar(-1)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.ctrl_pressed:
				_adjust_zoom(ZOOM_STEP)
				return
			logic.cycle_hotbar(1)
			return
		elif event.button_index == MOUSE_BUTTON_LEFT:
			logic.primary_action(_screen_to_world_tile(event.position))
			return
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		dragging_chat_drawer = false
		dragging_backpack_drawer = false
	if event.is_action_pressed("break_block"):
		logic.break_target()
	elif event.is_action_pressed("place_block"):
		logic.use_active_item()
	elif event.is_action_pressed("plant_seed"):
		logic.use_active_item()
	elif event.is_action_pressed("save_game"):
		logic.save_game()
	elif event.is_action_pressed("load_game"):
		logic.load_game()
		_snap_physics_to_logic()
	elif event.is_action_pressed("trade_action"):
		logic.try_trade()
	elif event.is_action_pressed("slot_1"):
		logic.select_hotbar(0)
	elif event.is_action_pressed("slot_2"):
		logic.select_hotbar(1)
	elif event.is_action_pressed("slot_3"):
		logic.select_hotbar(2)
	elif event.is_action_pressed("slot_4"):
		logic.select_hotbar(3)
	elif event.is_action_pressed("slot_5"):
		logic.select_hotbar(4)


func _draw() -> void:
	var center: Vector2 = get_viewport_rect().size * 0.5
	var player: Vector2 = player_world_pos
	var cell_size: float = _cell_size()
	var half_width: int = _view_half_width(cell_size)
	var half_height: int = _view_half_height(cell_size)
	var camera_world: Vector2 = _camera_world_pos(cell_size)

	for y in range(-half_height, half_height + 1):
		for x in range(-half_width, half_width + 1):
			var world_pos := Vector2i(roundi(camera_world.x) + x, roundi(camera_world.y) + y)
			var screen_pos := center + (Vector2(world_pos.x, world_pos.y) - camera_world) * cell_size
			_draw_cell(world_pos, screen_pos, cell_size)

			if logic.world.is_inside(world_pos):
				draw_rect(
					Rect2(screen_pos - Vector2(cell_size * 0.5, cell_size * 0.5), Vector2(cell_size, cell_size)),
					Color(0.2, 0.2, 0.2, 0.3),
					false,
					1.0
				)

	_draw_trade_station(center, camera_world, cell_size)
	_draw_dropped_items(center, camera_world, cell_size)
	_draw_remote_players(center, camera_world, cell_size)

	var player_screen: Vector2 = center + (player - camera_world) * cell_size
	var player_size: Vector2 = Vector2(PLAYER_HALF_SIZE.x * 2.0 * cell_size, PLAYER_HALF_SIZE.y * 2.0 * cell_size)
	var player_pos: Vector2 = player_screen - (player_size * 0.5)
	draw_rect(Rect2(player_pos, player_size), logic.current_character_color(), true)
	_draw_player_nametag(player_screen, cell_size)

	var target: Vector2i = logic.target_pos()
	var target_screen: Vector2 = center + (Vector2(target.x, target.y) - camera_world) * cell_size
	var target_color: Color = logic.target_preview_color(target)
	draw_rect(
		Rect2(target_screen - Vector2(cell_size * 0.5, cell_size * 0.5), Vector2(cell_size, cell_size)),
		target_color,
		false,
		2.0
	)

	if show_debug_overlay:
		var font: Font = _gameplay_font()
		var debug_lines := [
			"DEBUG (F3): Pos %s | Vel (%.2f, %.2f) | Ground %s" % [str(logic.get_player_pos()), player_velocity.x, player_velocity.y, str(is_on_ground)],
			"Facing: %s | Target: %s | State: %s | Zoom %.2fx" % [str(logic.get_facing()), str(logic.target_pos()), logic.player_state_name(), zoom_target],
			"Character: %s | Passive: %s" % [logic.current_character_name(), logic.character_passive_text()],
			"Trade station: %s | Cooldown: %d ms" % [str(GameLogic.TRADE_POS), logic.cooldown_remaining_ms()],
			"Drops: %d | Status: %s" % [logic.get_dropped_items().size(), status_text],
			"Inventory: %s" % str(logic.get_inventory().items),
			"Hotbar: %s" % _hotbar_text()
		]
		var y_start: float = 84.0
		for line in debug_lines:
			draw_string(
				font,
				Vector2(20, y_start),
				line,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				15,
				Color(0.92, 0.95, 1.0, 0.95)
			)
			y_start += 20.0

	_draw_top_bar()
	_draw_hotbar()
	_draw_popup_feed()
	_draw_chat_panel()
	_draw_backpack_panel()
	if show_pause_menu:
		_draw_pause_menu()


func _draw_cell(world_pos: Vector2i, screen_pos: Vector2, cell_size: float) -> void:
	var block: int = logic.world.get_block(world_pos)
	if block == ItemDB.ID.AIR:
		return
	var color: Color = ItemDB.get_base_color(block)
	draw_rect(
		Rect2(screen_pos - Vector2(cell_size * 0.5, cell_size * 0.5), Vector2(cell_size, cell_size)),
		color,
		true
	)
	var overlay: Color = ItemDB.get_overlay_color(block)
	if overlay.a > 0.0:
		draw_rect(
			Rect2(screen_pos - Vector2(cell_size * 0.42, cell_size * 0.42), Vector2(cell_size * 0.84, cell_size * 0.84)),
			Color(overlay.r, overlay.g, overlay.b, 0.35),
			true
		)
	var crack_progress: float = logic.world.get_break_progress(world_pos)
	if crack_progress > 0.0:
		var crack_color := Color(1.0, 1.0, 1.0, 0.25 + (0.65 * crack_progress))
		var half := cell_size * 0.5
		draw_line(screen_pos + Vector2(-half * 0.7, -half * 0.75), screen_pos + Vector2(half * 0.7, half * 0.75), crack_color, 2.0)
		draw_line(screen_pos + Vector2(-half * 0.1, -half * 0.8), screen_pos + Vector2(-half * 0.3, half * 0.6), crack_color, 1.8)
		draw_line(screen_pos + Vector2(half * 0.2, -half * 0.2), screen_pos + Vector2(half * 0.8, -half * 0.55), crack_color, 1.6)


func _draw_dropped_items(center: Vector2, camera_world: Vector2, cell_size: float) -> void:
	var font: Font = _gameplay_font()
	for drop in logic.get_dropped_items():
		var drop_pos: Vector2i = drop.get("pos", Vector2i.ZERO)
		var amount: int = int(drop.get("amount", 0))
		var screen_pos: Vector2 = center + (Vector2(drop_pos.x, drop_pos.y) - camera_world) * cell_size
		var size: Vector2 = Vector2(cell_size * 0.4, cell_size * 0.4)
		draw_rect(
			Rect2(screen_pos - size * 0.5, size),
			Color.GOLD,
			true
		)
		draw_string(
			font,
			screen_pos + Vector2(-8, -10),
			str(amount),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			14,
			Color.WHITE
		)


func _draw_trade_station(center: Vector2, camera_world: Vector2, cell_size: float) -> void:
	var font: Font = _gameplay_font()
	var screen_pos: Vector2 = center + (Vector2(GameLogic.TRADE_POS.x, GameLogic.TRADE_POS.y) - camera_world) * cell_size
	var rect: Rect2 = Rect2(
		screen_pos - Vector2(cell_size * 0.5, cell_size * 0.5),
		Vector2(cell_size, cell_size)
	)
	draw_rect(rect, Color(0.5, 0.2, 0.9, 0.95), true)
	draw_string(
		font,
		screen_pos + Vector2(-10, 5),
		"$",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		18,
		Color.WHITE
	)


func _on_state_changed(message: String) -> void:
	status_text = message
	_push_popup(message)
	_push_chat("SYSTEM", message)


func _sync_player_to_logic() -> void:
	var snapped := Vector2i(int(round(player_world_pos.x)), int(floor(player_world_pos.y)))
	if logic.world.is_inside(snapped):
		logic.set_player_position(snapped)
	else:
		var clamped: Vector2i = logic.world.clamp_inside(snapped)
		logic.set_player_position(clamped)
		player_world_pos = Vector2(clamped.x, clamped.y)


func _snap_physics_to_logic() -> void:
	var synced_pos: Vector2i = logic.get_player_pos()
	player_world_pos = Vector2(synced_pos.x, synced_pos.y)
	camera_world_pos = player_world_pos
	player_velocity = Vector2.ZERO
	is_on_ground = false
	coyote_timer = 0.0
	jump_buffer_timer = 0.0


func _move_with_collision(total_motion: Vector2) -> void:
	var max_component: float = max(abs(total_motion.x), abs(total_motion.y))
	var steps: int = max(1, int(ceil(max_component / 0.08)))
	var step_motion := total_motion / float(steps)
	is_on_ground = false

	for _i in range(steps):
		if step_motion.x != 0.0:
			var resolved_x: float = _resolve_axis_motion(step_motion.x, true)
			player_world_pos.x += resolved_x
			if absf(resolved_x - step_motion.x) > 0.0001:
				player_velocity.x = 0.0

		if step_motion.y != 0.0:
			var resolved_y: float = _resolve_axis_motion(step_motion.y, false)
			player_world_pos.y += resolved_y
			if absf(resolved_y - step_motion.y) > 0.0001:
				if step_motion.y > 0.0:
					is_on_ground = true
				player_velocity.y = 0.0

	if _collides_at(player_world_pos + Vector2(0.0, 0.05)):
		is_on_ground = true


func _snap_to_ground_if_needed() -> void:
	if not is_on_ground:
		return
	if player_velocity.y < 0.0:
		return
	var left := _world_to_tile_index(player_world_pos.x - PLAYER_HALF_SIZE.x + 0.02)
	var right := _world_to_tile_index(player_world_pos.x + PLAYER_HALF_SIZE.x - 0.02)
	var foot_row := _world_to_tile_index(player_world_pos.y + PLAYER_HALF_SIZE.y + 0.01)
	var best_y := INF
	for x in range(left, right + 1):
		var tile := Vector2i(x, foot_row)
		if not logic.world.is_inside(tile):
			continue
		if not logic.world.is_solid(tile):
			continue
		var top_surface_y: float = float(tile.y) - 0.5
		var corrected_center_y: float = top_surface_y - PLAYER_HALF_SIZE.y
		best_y = min(best_y, corrected_center_y)
	if best_y < INF:
		player_world_pos.y = best_y


func _collides_at(pos: Vector2) -> bool:
	var left := _world_to_tile_index(pos.x - PLAYER_HALF_SIZE.x + COLLISION_SKIN)
	var right := _world_to_tile_index(pos.x + PLAYER_HALF_SIZE.x - COLLISION_SKIN)
	var top := _world_to_tile_index(pos.y - PLAYER_HALF_SIZE.y + COLLISION_SKIN)
	var bottom := _world_to_tile_index(pos.y + PLAYER_HALF_SIZE.y - COLLISION_SKIN)

	for y in range(top, bottom + 1):
		for x in range(left, right + 1):
			var tile := Vector2i(x, y)
			if not logic.world.is_inside(tile):
				return true
			if _is_solid_tile(tile):
				return true
	return false


func _is_solid_tile(tile: Vector2i) -> bool:
	return logic.world.is_solid(tile)


func _resolve_axis_motion(delta: float, horizontal: bool) -> float:
	if delta == 0.0:
		return 0.0
	var test_pos := player_world_pos
	if horizontal:
		test_pos.x += delta
	else:
		test_pos.y += delta
	if not _collides_at(test_pos):
		return delta

	var low := 0.0
	var high := delta
	if delta < 0.0:
		low = delta
		high = 0.0
	for _i in range(10):
		var mid := (low + high) * 0.5
		var mid_pos := player_world_pos
		if horizontal:
			mid_pos.x += mid
		else:
			mid_pos.y += mid
		if _collides_at(mid_pos):
			if delta > 0.0:
				high = mid
			else:
				low = mid
		else:
			if delta > 0.0:
				low = mid
			else:
				high = mid
	return low if delta > 0.0 else high


func _world_to_tile_index(value: float) -> int:
	return int(floor(value + 0.5))


func _screen_to_world_tile(screen_pos: Vector2) -> Vector2i:
	var center: Vector2 = get_viewport_rect().size * 0.5
	var cell_size: float = _cell_size()
	var relative: Vector2 = (screen_pos - center) / cell_size
	var world_pos: Vector2 = _camera_world_pos(cell_size) + relative
	return Vector2i(int(round(world_pos.x)), int(round(world_pos.y)))


func _adjust_zoom(amount: float) -> void:
	zoom_target = clampf(zoom_target + amount, MIN_ZOOM, _max_zoom_without_bounds())


func _cell_size() -> float:
	return BASE_CELL_SIZE / max(zoom_current, 0.01)


func _max_zoom_without_bounds() -> float:
	var viewport_size: Vector2 = get_viewport_rect().size
	var min_cell_w: float = viewport_size.x / float(WorldData.WORLD_WIDTH)
	var min_cell_h: float = viewport_size.y / float(WorldData.WORLD_HEIGHT)
	var min_cell: float = max(min_cell_w, min_cell_h)
	var max_zoom_by_world: float = BASE_CELL_SIZE / max(min_cell, 0.01)
	return min(MAX_ZOOM, max(MIN_ZOOM, max_zoom_by_world))


func _apply_zoom_limits() -> void:
	var max_zoom := _max_zoom_without_bounds()
	zoom_target = clampf(zoom_target, MIN_ZOOM, max_zoom)
	zoom_current = clampf(zoom_current, MIN_ZOOM, max_zoom)


func _gameplay_font() -> Font:
	return UIFonts.gameplay_font()


func _camera_world_pos(cell_size: float) -> Vector2:
	var target := camera_world_pos
	var half_visible_x: float = (get_viewport_rect().size.x * 0.5) / max(cell_size, 1.0)
	var half_visible_y: float = (get_viewport_rect().size.y * 0.5) / max(cell_size, 1.0)
	var min_x: float = half_visible_x - 0.5
	var max_x: float = float(WorldData.WORLD_WIDTH) - 0.5 - half_visible_x
	var min_y: float = half_visible_y - 0.5
	var max_y: float = float(WorldData.WORLD_HEIGHT) - 0.5 - half_visible_y
	if max_x < min_x:
		target.x = float(WorldData.WORLD_WIDTH - 1) * 0.5
	else:
		target.x = clampf(target.x, min_x, max_x)
	if max_y < min_y:
		target.y = float(WorldData.WORLD_HEIGHT - 1) * 0.5
	else:
		target.y = clampf(target.y, min_y, max_y)
	return target


func _view_half_width(cell_size: float) -> int:
	var viewport_half_px: float = get_viewport_rect().size.x * 0.5
	return max(VIEW_HALF_WIDTH, int(ceil(viewport_half_px / max(cell_size, 1.0))) + 1)


func _view_half_height(cell_size: float) -> int:
	var viewport_half_px: float = get_viewport_rect().size.y * 0.5
	return max(VIEW_HALF_HEIGHT, int(ceil(viewport_half_px / max(cell_size, 1.0))) + 1)


func _bottom_panel_width() -> float:
	return (HOTBAR_COLUMNS * HOTBAR_SLOT_SIZE.x) + ((HOTBAR_COLUMNS - 1) * HOTBAR_SLOT_GAP) + 20.0


func _chat_panel_rect() -> Rect2:
	var width := _bottom_panel_width()
	var x := 12.0
	var y := -CHAT_DRAWER_HEIGHT + (CHAT_DRAWER_HEIGHT * chat_drawer_open) + DRAWER_HANDLE_HEIGHT
	return Rect2(Vector2(x, y), Vector2(width, CHAT_DRAWER_HEIGHT))


func _chat_handle_rect() -> Rect2:
	var width := 160.0
	var x := 12.0 + ((_chat_panel_rect().size.x - width) * 0.5)
	var y := (_chat_panel_rect().position.y + _chat_panel_rect().size.y) - DRAWER_HANDLE_HEIGHT
	return Rect2(Vector2(x, y), Vector2(width, DRAWER_HANDLE_HEIGHT))


func _backpack_panel_rect() -> Rect2:
	var width := _bottom_panel_width()
	var x := 12.0
	var viewport_h := get_viewport_rect().size.y
	var y := viewport_h - (BACKPACK_DRAWER_HEIGHT * backpack_drawer_open)
	return Rect2(Vector2(x, y), Vector2(width, BACKPACK_DRAWER_HEIGHT))


func _backpack_handle_rect() -> Rect2:
	var width := 170.0
	var x := _backpack_panel_rect().position.x + ((_backpack_panel_rect().size.x - width) * 0.5)
	var y := _backpack_panel_rect().position.y - DRAWER_HANDLE_HEIGHT
	return Rect2(Vector2(x, y), Vector2(width, DRAWER_HANDLE_HEIGHT))


func _draw_hotbar() -> void:
	var hotbar: Array[int] = logic.get_hotbar()
	var inventory: Inventory = logic.get_inventory()
	var selected_hotbar_index: int = logic.get_selected_hotbar_index()
	var visible_slots: int = min(HOTBAR_VISIBLE_SLOTS, hotbar.size())
	if visible_slots <= 0:
		return
	var font: Font = _gameplay_font()
	var width: float = (visible_slots * HOTBAR_SLOT_SIZE.x) + ((visible_slots - 1) * HOTBAR_SLOT_GAP) + 20.0
	var panel_size := Vector2(width, HOTBAR_SLOT_SIZE.y + 28.0)
	var viewport_size := get_viewport_rect().size
	var panel_pos := Vector2((viewport_size.x - panel_size.x) * 0.5, viewport_size.y - panel_size.y - 10.0)
	draw_rect(Rect2(panel_pos, panel_size), Color(0.06, 0.08, 0.11, 0.86), true)
	draw_rect(Rect2(panel_pos, panel_size), Color(0.72, 0.8, 0.95, 0.72), false, 2.0)
	for i in range(visible_slots):
		var slot_pos := panel_pos + Vector2(10.0 + (i * (HOTBAR_SLOT_SIZE.x + HOTBAR_SLOT_GAP)), 20.0)
		var slot_rect := Rect2(slot_pos, HOTBAR_SLOT_SIZE)
		var is_selected := i == selected_hotbar_index
		draw_rect(slot_rect, Color(0.27, 0.35, 0.48, 0.98) if is_selected else Color(0.16, 0.2, 0.26, 0.92), true)
		draw_rect(slot_rect, Color(0.78, 0.87, 1.0, 0.9) if is_selected else Color(0.4, 0.5, 0.64, 0.65), false, 2.0)
		var item_id: int = hotbar[i]
		var display_name := "empty"
		var amount_text := "-"
		if item_id >= 0:
			display_name = _item_name(item_id)
			if item_id == ItemDB.ID.PUNCH:
				amount_text = "INF"
			else:
				amount_text = str(inventory.get_count(item_id))
		draw_string(font, slot_pos + Vector2(6.0, 16.0), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.72, 0.79, 0.92, 0.95))
		draw_string(font, slot_pos + Vector2(6.0, 31.0), display_name, HORIZONTAL_ALIGNMENT_LEFT, HOTBAR_SLOT_SIZE.x - 10.0, 14, Color(1, 1, 1, 0.95))
		draw_string(font, slot_pos + Vector2(HOTBAR_SLOT_SIZE.x - 48.0, 16.0), "x%s" % amount_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.96, 0.92, 0.54, 0.98))


func _draw_backpack_panel() -> void:
	var font: Font = _gameplay_font()
	var panel_size := Vector2(
		_bottom_panel_width(),
		BACKPACK_DRAWER_HEIGHT
	)
	var panel_rect := _backpack_panel_rect()
	var panel_pos := panel_rect.position
	draw_rect(Rect2(panel_pos, panel_size), Color(0.06, 0.08, 0.11, 0.84), true)
	draw_rect(Rect2(panel_pos, panel_size), Color(0.7, 0.78, 0.95, 0.7), false, 2.0)
	draw_string(
		font,
		panel_pos + Vector2(8.0, 16.0),
		"Backpack / Hotbar (pull from bottom)",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color(0.9, 0.95, 1.0, 0.95)
	)
	var handle := _backpack_handle_rect()
	draw_rect(handle, Color(0.2, 0.28, 0.38, 0.95), true)
	draw_string(font, handle.position + Vector2(16.0, 14.0), "Backpack", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

	var hotbar: Array[int] = logic.get_hotbar()
	var inventory: Inventory = logic.get_inventory()
	var selected_hotbar_index: int = logic.get_selected_hotbar_index()
	var start_index: int = min(HOTBAR_VISIBLE_SLOTS, hotbar.size())
	var backpack_total: int = max(0, hotbar.size() - start_index)
	var start := panel_pos + Vector2(10.0, 24.0)
	for j in range(backpack_total):
		var i: int = start_index + j
		var col: int = j % HOTBAR_COLUMNS
		var row: int = int(j / HOTBAR_COLUMNS)
		var hidden_rows := int(backpack_scroll_offset)
		var slot_pos := start + Vector2(
			col * (HOTBAR_SLOT_SIZE.x + HOTBAR_SLOT_GAP),
			(row - hidden_rows) * (HOTBAR_SLOT_SIZE.y + HOTBAR_SLOT_GAP)
		)
		if slot_pos.y + HOTBAR_SLOT_SIZE.y < panel_pos.y + 22.0 or slot_pos.y > panel_pos.y + panel_size.y - 6.0:
			continue
		var slot_rect := Rect2(slot_pos, HOTBAR_SLOT_SIZE)
		var is_selected := i == selected_hotbar_index
		var fill_color := Color(0.16, 0.2, 0.26, 0.92)
		if is_selected:
			fill_color = Color(0.27, 0.35, 0.48, 0.98)
		draw_rect(slot_rect, fill_color, true)
		draw_rect(slot_rect, Color(0.78, 0.87, 1.0, 0.9) if is_selected else Color(0.4, 0.5, 0.64, 0.65), false, 2.0)

		var item_id: int = hotbar[i]
		var display_name := "empty"
		var amount_text := "-"
		if item_id >= 0:
			display_name = _item_name(item_id)
			if item_id == ItemDB.ID.PUNCH:
				amount_text = "INF"
			else:
				amount_text = str(inventory.get_count(item_id))

		draw_string(
			font,
			slot_pos + Vector2(6.0, 16.0),
			"%02d" % (i + 1),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			Color(0.72, 0.79, 0.92, 0.95)
		)
		draw_string(
			font,
			slot_pos + Vector2(6.0, 31.0),
			display_name,
			HORIZONTAL_ALIGNMENT_LEFT,
			HOTBAR_SLOT_SIZE.x - 10.0,
			14,
			Color(1, 1, 1, 0.95)
		)
		draw_string(
			font,
			slot_pos + Vector2(HOTBAR_SLOT_SIZE.x - 48.0, 16.0),
			"x%s" % amount_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			Color(0.96, 0.92, 0.54, 0.98)
		)


func _draw_top_bar() -> void:
	var font: Font = _gameplay_font()
	var viewport := get_viewport_rect().size
	var bar_size := Vector2(860.0, 52.0)
	var bar_pos := Vector2((viewport.x - bar_size.x) * 0.5, 10.0)
	draw_rect(Rect2(bar_pos, bar_size), Color(0.06, 0.08, 0.11, 0.86), true)
	draw_rect(Rect2(bar_pos, bar_size), Color(0.72, 0.8, 0.95, 0.72), false, 2.0)
	var world_label := "WORLD: %s" % logic.current_world_name
	var gem_label := "Gems: %d" % logic.get_inventory().get_count(ItemDB.ID.GEM)
	var lock_label: String = logic.lock_summary()
	var online_total := 1
	var world_online := 1
	var ping_ms := 0
	var uptime_text := "0s"
	if server_state != null:
		online_total = int(server_state.total_online())
		world_online = int(server_state.world_online(logic.current_world_name))
		ping_ms = int(server_state.current_ping_ms())
		uptime_text = str(server_state.uptime_text())
	var net_label := "ONLINE: %d  HERE: %d  PING: %dms  UP: %s  FPS: %d" % [online_total, world_online, ping_ms, uptime_text, Engine.get_frames_per_second()]
	var pause_label := "Pause: ESC"
	draw_string(font, bar_pos + Vector2(14.0, 20.0), world_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	draw_string(font, bar_pos + Vector2(210.0, 20.0), gem_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.95, 0.9, 0.35, 1.0))
	draw_string(font, bar_pos + Vector2(330.0, 20.0), lock_label, HORIZONTAL_ALIGNMENT_LEFT, 180.0, 14, Color(0.82, 0.9, 1.0, 1.0))
	draw_string(font, bar_pos + Vector2(14.0, 40.0), net_label, HORIZONTAL_ALIGNMENT_LEFT, bar_size.x - 160.0, 13, Color(0.87, 0.94, 1.0, 0.95))
	draw_string(font, bar_pos + Vector2(bar_size.x - 110.0, 20.0), pause_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.92, 0.95, 1.0, 0.85))


func _draw_remote_players(center: Vector2, camera_world: Vector2, cell_size: float) -> void:
	for player_data in remote_players_cache:
		var pos: Vector2 = player_data.get("pos", Vector2.ZERO)
		var dist: float = pos.distance_to(player_world_pos)
		if dist > REMOTE_BUBBLE_CULL_DISTANCE:
			continue
		var player_screen: Vector2 = center + (pos - camera_world) * cell_size
		var player_size: Vector2 = Vector2(PLAYER_HALF_SIZE.x * 2.0 * cell_size, PLAYER_HALF_SIZE.y * 2.0 * cell_size)
		var player_pos: Vector2 = player_screen - (player_size * 0.5)
		draw_rect(Rect2(player_pos, player_size), Color(0.76, 0.86, 1.0, 0.9), true)
		_draw_entity_nametag_and_bubble(
			player_screen,
			cell_size,
			str(player_data.get("name", "Remote")),
			str(player_data.get("bubble_text", "")),
			float(player_data.get("bubble_timer", 0.0))
		)


func _draw_player_nametag(player_screen: Vector2, cell_size: float) -> void:
	_draw_entity_nametag_and_bubble(
		player_screen,
		cell_size,
		logic.player_name,
		player_chat_bubble,
		player_chat_timer
	)


func _draw_entity_nametag_and_bubble(
	player_screen: Vector2,
	cell_size: float,
	player_name: String,
	bubble_text: String,
	bubble_timer: float
) -> void:
	var font: Font = _gameplay_font()
	var tag := "[%s]" % player_name
	var tag_pos := player_screen + Vector2(-46.0, -cell_size * 0.95)
	draw_rect(Rect2(tag_pos + Vector2(-6.0, -16.0), Vector2(104.0, 24.0)), Color(0.08, 0.1, 0.14, 0.78), true)
	draw_string(font, tag_pos, tag, HORIZONTAL_ALIGNMENT_LEFT, 96.0, 14, Color(0.95, 0.97, 1.0, 1.0))
	if bubble_timer > 0.0 and bubble_text != "":
		_draw_player_bubble(player_screen, cell_size, bubble_text, bubble_timer)


func _draw_player_bubble(player_screen: Vector2, cell_size: float, bubble_text: String, bubble_timer: float) -> void:
	var font: Font = _gameplay_font()
	var max_width := 240.0
	var text_width := font.get_string_size(bubble_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var bubble_w: float = clampf(text_width + 16.0, 100.0, max_width)
	var alpha: float = clampf(bubble_timer / 4.0, 0.0, 1.0)
	var bubble_pos := player_screen + Vector2(-bubble_w * 0.5, -cell_size * 1.55)
	var bubble_rect := Rect2(bubble_pos, Vector2(bubble_w, 24.0))
	draw_rect(bubble_rect, Color(0.08, 0.1, 0.14, 0.35 + (0.51 * alpha)), true)
	draw_rect(bubble_rect, Color(0.72, 0.82, 0.98, 0.25 + (0.45 * alpha)), false, 1.5)
	draw_string(
		font,
		bubble_pos + Vector2(8.0, 16.0),
		bubble_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		bubble_rect.size.x - 12.0,
		13,
		Color(1.0, 1.0, 1.0, 0.35 + (0.63 * alpha))
	)


func _draw_popup_feed() -> void:
	if popup_messages.is_empty():
		return
	var font: Font = _gameplay_font()
	var panel_size := Vector2(_bottom_panel_width(), HOTBAR_SLOT_SIZE.y + 28.0)
	var base_y := get_viewport_rect().size.y - panel_size.y - 22.0
	var idx := 0
	for popup in popup_messages:
		var text: String = str(popup.get("text", ""))
		var ttl: float = float(popup.get("ttl", 0.0))
		var alpha: float = clampf(ttl / POPUP_LIFETIME, 0.2, 1.0)
		var y := base_y - (idx * 22.0)
		draw_string(
			font,
			Vector2(18.0, y),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Color(1.0, 1.0, 1.0, alpha)
		)
		idx += 1


func _draw_chat_panel() -> void:
	var font: Font = _gameplay_font()
	var panel_rect := _chat_panel_rect()
	var panel_size := panel_rect.size
	var panel_pos := panel_rect.position
	draw_rect(Rect2(panel_pos, panel_size), Color(0.05, 0.07, 0.1, 0.76), true)
	draw_rect(Rect2(panel_pos, panel_size), Color(0.55, 0.66, 0.84, 0.6), false, 2.0)
	var handle := _chat_handle_rect()
	draw_rect(handle, Color(0.2, 0.28, 0.38, 0.95), true)
	draw_string(font, panel_pos + Vector2(10.0, 36.0), "Chat / Notifications (pull from top)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.95, 1.0, 0.95))
	var visible_rows: int = max(1, min(CHAT_VISIBLE_LINES, int((panel_size.y - 84.0) / 19.0)))
	var max_scroll: int = max(0, chat_messages.size() - visible_rows)
	chat_scroll_offset = clampi(chat_scroll_offset, 0, max_scroll)
	var start_index: int = max(0, chat_messages.size() - visible_rows - chat_scroll_offset)
	var end_index: int = min(chat_messages.size(), start_index + visible_rows)
	var draw_row := 0
	for i in range(start_index, end_index):
		var entry: Dictionary = chat_messages[i]
		var text: String = str(entry.get("text", ""))
		var channel: String = str(entry.get("channel", "SYSTEM"))
		var color: Color = _chat_color_for_channel(channel)
		draw_string(
			font,
			panel_pos + Vector2(12.0, 58.0 + (draw_row * 19.0)),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			panel_size.x - 18.0,
			14,
			color
		)
		draw_row += 1

	var total: int = max(chat_messages.size(), 1)
	var visible_ratio: float = clampf(float(visible_rows) / float(total), 0.08, 1.0)
	var track_height := panel_size.y - 84.0
	var bar_height: float = track_height * visible_ratio
	var max_scroll_for_bar: int = max(1, total - visible_rows)
	var scroll_t: float = float(chat_scroll_offset) / float(max_scroll_for_bar)
	var scroll_y: float = panel_pos.y + 48.0 + ((track_height - bar_height) * scroll_t)
	draw_rect(
		Rect2(
			Vector2(panel_pos.x + panel_size.x - 8.0, scroll_y),
			Vector2(4.0, bar_height)
		),
		Color(0.8, 0.9, 1.0, 0.8),
		true
	)
	var input_rect := Rect2(
		Vector2(panel_pos.x + 8.0, panel_pos.y + panel_size.y - 30.0),
		Vector2(panel_size.x - 16.0, 22.0)
	)
	draw_rect(input_rect, Color(0.12, 0.15, 0.2, 0.95), true)
	draw_rect(input_rect, Color(0.7, 0.8, 1.0, 0.85) if chat_input_active else Color(0.5, 0.6, 0.76, 0.55), false, 1.5)
	var display: String = chat_input_text
	if chat_input_active:
		display += "_"
	draw_string(
		font,
		input_rect.position + Vector2(8.0, 16.0),
		display,
		HORIZONTAL_ALIGNMENT_LEFT,
		input_rect.size.x - 10.0,
		14,
		Color.WHITE
	)


func _draw_inventory_panel() -> void:
	var font: Font = _gameplay_font()
	var panel_size := Vector2(600.0, 390.0)
	var panel_pos := (get_viewport_rect().size - panel_size) * 0.5
	draw_rect(Rect2(panel_pos, panel_size), Color(0.05, 0.07, 0.1, 0.92), true)
	draw_rect(Rect2(panel_pos, panel_size), Color(0.72, 0.8, 0.95, 0.8), false, 2.0)
	draw_string(font, panel_pos + Vector2(14.0, 22.0), "Inventory (I/B to close)", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	var inventory: Inventory = logic.get_inventory()
	var keys: Array = inventory.items.keys()
	keys.sort()
	var cols := 6
	var slot_size := Vector2(92.0, 54.0)
	var start := panel_pos + Vector2(14.0, 38.0)
	for i in range(keys.size()):
		var col: int = i % cols
		var row: int = int(i / cols)
		if row > 5:
			break
		var slot_pos := start + Vector2(col * (slot_size.x + 8.0), row * (slot_size.y + 8.0))
		draw_rect(Rect2(slot_pos, slot_size), Color(0.13, 0.16, 0.22, 0.95), true)
		draw_rect(Rect2(slot_pos, slot_size), Color(0.45, 0.55, 0.72, 0.75), false, 2.0)
		var item_id: int = int(keys[i])
		var count: int = int(inventory.items[item_id])
		draw_string(font, slot_pos + Vector2(6.0, 20.0), _item_name(item_id), HORIZONTAL_ALIGNMENT_LEFT, slot_size.x - 8.0, 13, Color.WHITE)
		draw_string(font, slot_pos + Vector2(6.0, 40.0), "x%d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.9, 0.4, 1.0))


func _draw_pause_menu() -> void:
	var font: Font = _gameplay_font()
	var panel_size := Vector2(420.0, 220.0)
	var panel_pos := (get_viewport_rect().size - panel_size) * 0.5
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.0, 0.0, 0.0, 0.35), true)
	draw_rect(Rect2(panel_pos, panel_size), Color(0.06, 0.08, 0.12, 0.95), true)
	draw_rect(Rect2(panel_pos, panel_size), Color(0.72, 0.8, 0.95, 0.82), false, 2.0)
	draw_string(font, panel_pos + Vector2(16.0, 28.0), "PAUSED", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(font, panel_pos + Vector2(16.0, 62.0), "ESC: Resume", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.92, 0.95, 1.0, 0.95))
	draw_string(font, panel_pos + Vector2(16.0, 86.0), "I/B: Toggle Inventory", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.94, 1.0, 0.95))
	draw_string(font, panel_pos + Vector2(16.0, 110.0), "ENTER: Toggle Chat", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.94, 1.0, 0.95))
	draw_string(font, panel_pos + Vector2(16.0, 138.0), "CTRL + MouseWheel: Zoom", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.94, 1.0, 0.95))
	draw_string(font, panel_pos + Vector2(16.0, 170.0), "Settings menu placeholder", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.72, 0.8, 0.95, 0.9))


func _send_chat_message(raw_text: String) -> void:
	var text: String = raw_text.strip_edges()
	if text == "":
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - last_chat_sent_ms < CHAT_COOLDOWN_MS:
		_push_chat("ERROR", "Tunggu %.1f detik sebelum kirim pesan lagi." % (float(CHAT_COOLDOWN_MS) / 1000.0))
		return
	last_chat_sent_ms = now_ms
	if text.begins_with("/"):
		_process_chat_command(text)
		return
	_push_chat("GLOBAL", "%s: %s" % [logic.player_name, text])
	player_chat_bubble = text
	player_chat_timer = 4.0


func _process_chat_command(raw_cmd: String) -> void:
	var args: PackedStringArray = raw_cmd.split(" ", false)
	if args.is_empty():
		return
	var command: String = args[0].to_lower()
	match command:
		"/help":
			_push_chat("SYSTEM", "Commands: /help, /join <WORLD>, /spawn")
		"/join":
			if args.size() < 2:
				_push_chat("ERROR", "Usage: /join WORLDNAME")
				return
			var world_name: String = args[1].strip_edges().to_upper()
			if world_name == "":
				_push_chat("ERROR", "Nama world tidak valid.")
				return
			logic.join_world(world_name)
			_snap_physics_to_logic()
			_push_chat("SYSTEM", "Joining world %s..." % world_name)
		"/spawn":
			logic.set_player_position(logic.world.get_spawn_position())
			_snap_physics_to_logic()
			_push_chat("SYSTEM", "Kembali ke spawn.")
		_:
			_push_chat("ERROR", "Unknown command: %s" % command)


func _push_popup(text: String) -> void:
	if text.strip_edges() == "":
		return
	popup_messages.push_front({"text": text, "ttl": POPUP_LIFETIME})
	if popup_messages.size() > POPUP_MAX:
		popup_messages = popup_messages.slice(0, POPUP_MAX)


func _push_chat(channel: String, text: String) -> void:
	if text.strip_edges() == "":
		return
	var stamp := Time.get_datetime_string_from_system().split("T")[1].substr(0, 5)
	var channel_upper := channel.strip_edges().to_upper()
	chat_messages.append({
		"text": "[%s] %s: %s" % [stamp, channel_upper, text],
		"channel": channel_upper
	})
	chat_scroll_offset = 0
	if chat_messages.size() > CHAT_MAX:
		chat_messages = chat_messages.slice(chat_messages.size() - CHAT_MAX, chat_messages.size())


func _chat_color_for_channel(channel_upper: String) -> Color:
	if channel_upper == "SYSTEM":
		return Color(0.72, 0.86, 1.0, 0.98)
	if channel_upper == "TRADE":
		return Color(0.72, 1.0, 0.72, 0.98)
	if channel_upper == "ERROR":
		return Color(1.0, 0.65, 0.65, 0.98)
	return Color(0.95, 0.97, 1.0, 0.94)


func _tick_popups(delta: float) -> void:
	if popup_messages.is_empty():
		return
	var next: Array[Dictionary] = []
	for popup in popup_messages:
		var ttl: float = float(popup.get("ttl", 0.0)) - delta
		if ttl <= 0.0:
			continue
		popup["ttl"] = ttl
		next.append(popup)
	popup_messages = next


func _hotbar_text() -> String:
	var slots: Array[String] = []
	var hotbar: Array[int] = logic.get_hotbar()
	var selected_hotbar_index: int = logic.get_selected_hotbar_index()
	for i in range(hotbar.size()):
		var item: int = hotbar[i]
		var item_text: String = _item_name(item)
		if item < 0:
			item_text = "empty"
		if i == selected_hotbar_index:
			slots.append("[%d:%s]" % [i + 1, item_text])
		else:
			slots.append("%d:%s" % [i + 1, item_text])
	return " ".join(slots)


func _item_name(item_id: int) -> String:
	if item_id < 0:
		return "empty"
	var item_data: Dictionary = ItemDB.get_item(item_id)
	return str(item_data.get("name", str(item_id)))
