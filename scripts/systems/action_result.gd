class_name ActionResult
extends RefCounted

var ok := false
var reason := ""
var effects: Array[Dictionary] = []


func _init(p_ok: bool = false, p_reason: String = "", p_effects: Array[Dictionary] = []) -> void:
	ok = p_ok
	reason = p_reason
	effects = p_effects.duplicate(true)
