extends RefCounted
class_name UIFonts

static var GAMEPLAY_FONT_CANDIDATES: PackedStringArray = PackedStringArray([
	"res://assets/fonts/PixelOperator.ttf",
	"res://assets/fonts/pixel_operator.ttf",
	"res://assets/fonts/m6x11.ttf",
	"res://assets/fonts/Dogica.ttf"
])

static var MENU_FONT_CANDIDATES: PackedStringArray = PackedStringArray([
	"res://assets/fonts/Nunito-Regular.ttf",
	"res://assets/fonts/Nunito.ttf"
])

static var _cached_gameplay_font: Font
static var _cached_menu_font: Font


static func gameplay_font() -> Font:
	if _cached_gameplay_font == null:
		_cached_gameplay_font = _load_first_font(GAMEPLAY_FONT_CANDIDATES)
	return _cached_gameplay_font


static func menu_font() -> Font:
	if _cached_menu_font == null:
		_cached_menu_font = _load_first_font(MENU_FONT_CANDIDATES)
	return _cached_menu_font


static func apply_menu_theme(target: Control) -> void:
	var theme := Theme.new()
	theme.default_font = menu_font()
	theme.default_font_size = 18
	target.theme = theme


static func _load_first_font(candidates: PackedStringArray) -> Font:
	for path in candidates:
		if ResourceLoader.exists(path):
			var loaded: Resource = load(path)
			if loaded is Font:
				return loaded
	return ThemeDB.fallback_font
