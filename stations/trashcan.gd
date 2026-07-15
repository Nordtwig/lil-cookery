class_name Trashcan
extends Station

## Throws away whatever you're carrying — no limit, no restriction, no cost.
## A release valve for mistakes (overcooked, wrong ingredient, a plate you
## don't want anymore) so nothing ever has to sit around cluttering the
## kitchen or stuck in a player's hands with no way to let go of it.


func interact(player: Player) -> void:
	if player.held_item == null:
		return
	player.drop_item().queue_free()
