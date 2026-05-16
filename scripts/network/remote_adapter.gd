class_name RemoteAdapter
extends RefCounted

var base_url := ""


func _init(p_base_url: String = "http://localhost:8080") -> void:
	base_url = p_base_url


func execute(_action: GameAction) -> ActionResult:
	return ActionResult.new(false, "RemoteAdapter belum aktif. Saat ini mode offline/local.")
