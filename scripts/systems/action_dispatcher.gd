class_name ActionDispatcher
extends RefCounted

const TILE_INTERACT_RANGE := 4
const TRADE_RANGE := 1.5

var game: GameLogic


func _init(p_game: GameLogic) -> void:
	game = p_game


func dispatch(action: GameAction) -> ActionResult:
	if action.actor_id != game.player_id:
		return ActionResult.new(false, "Actor tidak valid.")
	if not _validate_common(action):
		return ActionResult.new(false, "Aksi ditolak oleh validator.")

	match action.type:
		GameAction.ActionType.BREAK:
			return _break_action(action)
		GameAction.ActionType.PLACE_DIRT:
			return _place_dirt_action(action)
		GameAction.ActionType.PLANT_SEED:
			return _plant_seed_action(action)
		GameAction.ActionType.LOCK_SMALL:
			return _small_lock_action(action)
		GameAction.ActionType.LOCK_BIG:
			return _big_lock_action(action)
		GameAction.ActionType.TRADE:
			return _trade_action(action)
		_:
			return ActionResult.new(false, "Jenis action belum didukung.")


func _validate_common(action: GameAction) -> bool:
	if not game.consume_action_window(action.type):
		return false
	if action.type == GameAction.ActionType.TRADE:
		return game.player_system.player_pos.distance_to(GameLogic.TRADE_POS) <= TRADE_RANGE
	if action.type == GameAction.ActionType.MOVE:
		return true
	if not game.world.is_inside(action.target):
		return false
	var dist: int = abs(game.player_system.player_pos.x - action.target.x) + abs(game.player_system.player_pos.y - action.target.y)
	if dist > TILE_INTERACT_RANGE:
		return false
	if not game.world.can_modify(game.player_id, action.target):
		if action.type == GameAction.ActionType.BREAK or action.type == GameAction.ActionType.PLACE_DIRT or action.type == GameAction.ActionType.PLANT_SEED:
			return false
	return true


func _break_action(action: GameAction) -> ActionResult:
	var result: Dictionary = game.combat_system.break_target(
		game.world,
		game.inventory_system,
		game.entity_registry,
		game.player_id,
		game.player_system.player_pos,
		action.target,
		Callable(game, "_can_interact"),
		game.character_system.miner_bonus_dirt_chance(),
		game.rng
	)
	if bool(result.get("ok", false)):
		game.player_system.mark_punch()
		game._pickup_near_player()
	return ActionResult.new(
		bool(result.get("ok", false)),
		str(result.get("message", "")),
		[{"type": "break", "target": action.target, "destroyed": bool(result.get("destroyed", false))}]
	)


func _place_dirt_action(action: GameAction) -> ActionResult:
	var result := game.combat_system.place_dirt(game.world, game.inventory_system.inventory, game.player_id, action.target, Callable(game, "_can_interact"))
	return ActionResult.new(bool(result.get("ok", false)), str(result.get("message", "")), [{"type": "place_dirt", "target": action.target}])


func _plant_seed_action(action: GameAction) -> ActionResult:
	var result := game.farming_system.plant_seed(
		game.world,
		game.inventory_system.inventory,
		game.player_id,
		action.target,
		Callable(game, "_can_interact"),
		game.character_system.seed_refund_chance(),
		game.rng
	)
	return ActionResult.new(bool(result.get("ok", false)), str(result.get("message", "")), [{"type": "plant_seed", "target": action.target}])


func _small_lock_action(action: GameAction) -> ActionResult:
	var result := game.combat_system.place_small_lock(game.world, game.inventory_system.inventory, game.player_id, action.target, Callable(game, "_can_interact"))
	return ActionResult.new(bool(result.get("ok", false)), str(result.get("message", "")), [{"type": "lock_small", "target": action.target}])


func _big_lock_action(action: GameAction) -> ActionResult:
	var result := game.combat_system.place_big_lock(game.world, game.inventory_system.inventory, game.player_id, game.player_name, action.target, Callable(game, "_can_interact"))
	return ActionResult.new(bool(result.get("ok", false)), str(result.get("message", "")), [{"type": "lock_big", "target": action.target}])


func _trade_action(_action: GameAction) -> ActionResult:
	var result := game.trade_system.try_trade(game.inventory_system.inventory, game.character_system.trade_rate_bonus())
	return ActionResult.new(bool(result.get("ok", false)), str(result.get("message", "")), [{"type": "trade"}])
