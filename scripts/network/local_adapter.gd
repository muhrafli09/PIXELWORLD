class_name LocalAdapter
extends RefCounted

var dispatcher: ActionDispatcher


func _init(p_dispatcher: ActionDispatcher) -> void:
	dispatcher = p_dispatcher


func execute(action: GameAction) -> ActionResult:
	return dispatcher.dispatch(action)
