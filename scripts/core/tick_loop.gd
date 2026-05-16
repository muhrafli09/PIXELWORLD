class_name TickLoop
extends RefCounted

const DEFAULT_TPS := 20.0

signal tick_emitted(tick_id: int)

var tps := DEFAULT_TPS
var accumulator := 0.0
var tick_id := 0


func process_frame(delta: float) -> void:
	accumulator += delta
	var interval: float = 1.0 / tps
	while accumulator >= interval:
		accumulator -= interval
		tick_id += 1
		emit_signal("tick_emitted", tick_id)


func reset() -> void:
	accumulator = 0.0
	tick_id = 0
