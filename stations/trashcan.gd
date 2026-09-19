class_name Trashcan
extends Station

## Throws away whatever you're carrying — no limit, no restriction, no cost.
## A release valve for mistakes (overcooked, wrong ingredient, a plate you
## don't want anymore) so nothing ever has to sit around cluttering the
## kitchen or stuck in a player's hands with no way to let go of it.


func hints(player: Player) -> Array[Dictionary]:
	if player.held_item == null:
		return []
	return [hint("interact", "Throw away %s" % player.held_item.hint_name())]


func interact(player: Player) -> void:
	if player.held_item == null:
		return
	var item := player.drop_item()
	# Only real ingredients count as waste (item_type == "" covers plates,
	# spices, tickets, trays — nothing the ledger's waste line is about).
	# Valued at what replacing it would cost to order, the closest thing to
	# an honest price any ingredient has right now.
	if item.item_type != "":
		GameState.record_waste(GameState.order_unit_cost)
	item.queue_free()
