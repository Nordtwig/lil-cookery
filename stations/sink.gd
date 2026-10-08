class_name Sink
extends SlotStation

## A counter with a tap. Carrying a pot that still wants water, interact fills it
## straight from the tap - water is never a standalone item, the pot is the only way
## to carry it. Anything else is set down on / taken off the sink like a counter.


func interact(player: Player) -> void:
	var carried := player.held_item
	if carried is Pot and (carried as Pot).can_fill_water():
		(carried as Pot).fill_water()
		return
	super.interact(player)


func hints(player: Player) -> Array[Dictionary]:
	var carried := player.held_item
	if carried is Pot and (carried as Pot).can_fill_water():
		return [hint("interact", "Fill %s" % carried.hint_name())]
	return super.hints(player)


func get_inspect_text() -> String:
	var rest := super.get_inspect_text()
	return "SINK" if rest == "" else "SINK\n" + rest
