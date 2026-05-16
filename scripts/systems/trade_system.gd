class_name TradeSystem
extends RefCounted


func try_trade(inventory: Inventory, trade_rate_bonus: int = 0) -> Dictionary:
	var fruit_count: int = inventory.get_count(ItemDB.ID.FRUIT)
	if fruit_count > 0:
		inventory.remove_item(ItemDB.ID.FRUIT, fruit_count)
		var rate: int = 5 + max(0, trade_rate_bonus)
		var gained: int = fruit_count * rate
		inventory.add_item(ItemDB.ID.GEM, gained)
		return {"ok": true, "message": "Trade sukses: jual %d fruit -> %d gem." % [fruit_count, gained]}

	if inventory.has_item(ItemDB.ID.GEM, 2):
		inventory.remove_item(ItemDB.ID.GEM, 2)
		inventory.add_item(ItemDB.ID.SEED, 1)
		return {"ok": true, "message": "Trade sukses: beli 1 seed dengan 2 gem."}

	return {"ok": false, "message": "Trade gagal. Butuh fruit untuk jual, atau minimal 2 gem untuk beli seed."}
