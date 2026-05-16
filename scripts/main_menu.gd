extends Control

const GAME_SCENE_PATH := "res://scenes/Main.tscn"
const SPLASH_DURATION := 2.2
const LOADING_DURATION := 0.9
const WORLD_NAME_MAX := 24

enum FlowState {
	SPLASH,
	LOGIN,
	MAIN_MENU,
	WORLD_INPUT,
	LOADING
}

var state := FlowState.SPLASH
var state_elapsed := 0.0
var pending_world_name := "START"

var root_box: VBoxContainer
var title_label: Label
var subtitle_label: Label
var body_box: VBoxContainer
var footer_label: Label

var username_input: LineEdit
var password_input: LineEdit
var remember_check: CheckBox
var world_input: LineEdit
var volume_label: Label
var fullscreen_check: CheckBox


func _ready() -> void:
	UIFonts.apply_menu_theme(self)
	_set_fullscreen_anchors(self)
	_build_shell()
	_enter_state(FlowState.SPLASH)
	set_process(true)


func _process(delta: float) -> void:
	state_elapsed += delta
	match state:
		FlowState.SPLASH:
			if state_elapsed >= SPLASH_DURATION:
				_enter_state(FlowState.LOGIN)
		FlowState.LOADING:
			if state_elapsed >= LOADING_DURATION:
				_start_game()


func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = Color(0.08, 0.09, 0.14, 1.0)
	_set_fullscreen_anchors(background)
	add_child(background)

	var center := CenterContainer.new()
	_set_fullscreen_anchors(center)
	add_child(center)

	root_box = VBoxContainer.new()
	root_box.custom_minimum_size = Vector2(520, 0)
	root_box.alignment = BoxContainer.ALIGNMENT_CENTER
	root_box.add_theme_constant_override("separation", 12)
	center.add_child(root_box)

	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 42)
	root_box.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 18)
	root_box.add_child(subtitle_label)

	root_box.add_child(HSeparator.new())

	body_box = VBoxContainer.new()
	body_box.add_theme_constant_override("separation", 10)
	root_box.add_child(body_box)

	footer_label = Label.new()
	footer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer_label.add_theme_font_size_override("font_size", 14)
	footer_label.modulate = Color(0.8, 0.85, 0.95, 0.9)
	root_box.add_child(footer_label)


func _enter_state(next_state: int) -> void:
	state = next_state
	state_elapsed = 0.0
	_clear_body()
	match state:
		FlowState.SPLASH:
			_render_splash()
		FlowState.LOGIN:
			_render_login()
		FlowState.MAIN_MENU:
			_render_main_menu()
		FlowState.WORLD_INPUT:
			_render_world_input()
		FlowState.LOADING:
			_render_loading()


func _render_splash() -> void:
	title_label.text = "PIXEL FARM OFFLINE"
	subtitle_label.text = "v0.1 Prototype"
	var loading := Label.new()
	loading.text = "Loading..."
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.add_theme_font_size_override("font_size", 24)
	body_box.add_child(loading)
	footer_label.text = "Initializing systems"


func _render_login() -> void:
	title_label.text = "Login"
	subtitle_label.text = "Fast sandbox access"
	username_input = LineEdit.new()
	username_input.placeholder_text = "Username"
	username_input.text = "Player"
	body_box.add_child(username_input)
	password_input = LineEdit.new()
	password_input.placeholder_text = "Password"
	password_input.secret = true
	body_box.add_child(password_input)
	remember_check = CheckBox.new()
	remember_check.text = "Remember me"
	body_box.add_child(remember_check)
	body_box.add_child(_make_button("LOGIN", Callable(self, "_on_login_confirmed")))
	body_box.add_child(_make_button("REGISTER", Callable(self, "_on_login_confirmed")))
	footer_label.text = "Tip: username dipakai jadi display name."


func _render_main_menu() -> void:
	title_label.text = "Main Menu"
	subtitle_label.text = "UI ringan, flow cepat"
	body_box.add_child(_make_button("PLAY", Callable(self, "_on_play_pressed")))
	body_box.add_child(_build_settings_panel())
	body_box.add_child(_make_button("EXIT", Callable(self, "_on_quit_pressed")))
	footer_label.text = "ESC untuk pause saat gameplay."


func _render_world_input() -> void:
	title_label.text = "Enter World"
	subtitle_label.text = "Join existing / generate new"
	world_input = LineEdit.new()
	world_input.placeholder_text = "World Name (A-Z0-9, max 24)"
	world_input.text = pending_world_name
	world_input.text_submitted.connect(_on_world_name_submitted)
	body_box.add_child(world_input)
	body_box.add_child(_make_button("ENTER WORLD", Callable(self, "_on_world_join_pressed")))
	body_box.add_child(_make_button("BACK", Callable(self, "_on_world_back_pressed")))
	footer_label.text = "World name otomatis uppercase."


func _render_loading() -> void:
	title_label.text = "Loading"
	subtitle_label.text = "Preparing world..."
	var label := Label.new()
	label.text = "Joining %s..." % pending_world_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	body_box.add_child(label)
	footer_label.text = "Generate/load/sync world state."


func _clear_body() -> void:
	for child in body_box.get_children():
		child.queue_free()


func _make_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 48)
	button.pressed.connect(action)
	return button


func _build_settings_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 170)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 20)
	root.add_child(title)

	fullscreen_check = CheckBox.new()
	fullscreen_check.text = "Fullscreen"
	fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	root.add_child(fullscreen_check)

	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = _current_volume_percent()
	slider.value_changed.connect(_on_volume_changed)
	root.add_child(slider)

	volume_label = Label.new()
	volume_label.text = "Volume: %d%%" % int(slider.value)
	root.add_child(volume_label)
	return panel


func _on_login_confirmed() -> void:
	var username := username_input.text.strip_edges()
	if username == "":
		footer_label.text = "Username wajib diisi."
		return
	var session := get_node_or_null("/root/SessionData")
	if session != null:
		session.set_profile(username, "farmer", pending_world_name, remember_check.button_pressed)
	_enter_state(FlowState.MAIN_MENU)


func _on_play_pressed() -> void:
	_enter_state(FlowState.WORLD_INPUT)
	if world_input != null:
		world_input.grab_focus()


func _on_world_back_pressed() -> void:
	_enter_state(FlowState.MAIN_MENU)


func _on_world_join_pressed() -> void:
	_on_world_name_submitted(world_input.text)


func _on_world_name_submitted(text: String) -> void:
	var normalized := _normalize_world_name(text)
	if normalized == "":
		footer_label.text = "Nama world invalid. Gunakan A-Z dan 0-9."
		return
	pending_world_name = normalized
	var session := get_node_or_null("/root/SessionData")
	if session != null:
		session.world_name = pending_world_name
	_enter_state(FlowState.LOADING)


func _normalize_world_name(raw: String) -> String:
	var input := raw.strip_edges().to_upper()
	if input.length() > WORLD_NAME_MAX:
		input = input.substr(0, WORLD_NAME_MAX)
	var out := ""
	for i in range(input.length()):
		var ch := input.substr(i, 1)
		var code := ch.unicode_at(0)
		var is_alpha := code >= 65 and code <= 90
		var is_num := code >= 48 and code <= 57
		if is_alpha or is_num:
			out += ch
	return out


func _start_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _set_fullscreen_anchors(control: Control) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0


func _on_fullscreen_toggled(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _on_volume_changed(value: float) -> void:
	var percent: int = int(value)
	AudioServer.set_bus_volume_db(0, linear_to_db(max(0.001, percent / 100.0)))
	if volume_label != null:
		volume_label.text = "Volume: %d%%" % percent


func _current_volume_percent() -> float:
	var db: float = AudioServer.get_bus_volume_db(0)
	var linear: float = db_to_linear(db)
	return clamp(linear * 100.0, 0.0, 100.0)
