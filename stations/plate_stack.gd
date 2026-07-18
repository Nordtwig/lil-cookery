class_name PlateStack
extends Station

## An infinite source of empty plates. Carrying an unmodified (still empty)
## plate and interacting instead puts it back, same "undo, no cost" shape as
## returning an ingredient to its Crate.
##
## Carrying an OrderTicket instead grabs a plate already tagged with that
## order — the common case (grab a ticket, then immediately want a plate for
## it) used to be ticket-down, plate-up, combine as three separate steps;
## now it's one pickup. The ticket is consumed exactly as tag_order() already
## consumes it elsewhere.

const PLATE_SCENE := preload("res://items/plate.tscn")


func interact(player: Player) -> void:
	var carried := player.held_item
	if carried == null:
		player.take_item(PLATE_SCENE.instantiate())
	elif carried is Plate and (carried as Plate).is_unmodified():
		player.drop_item()
		carried.queue_free()
	elif carried is OrderTicket:
		# tag_order() touches @onready node refs, so the plate needs to already
		# be in the tree (take_item attaches it) before it's tagged.
		var ticket := carried as OrderTicket
		var plate: Plate = PLATE_SCENE.instantiate()
		player.drop_item()
		player.take_item(plate)
		plate.tag_order(ticket.dish, ticket.table_number)
		ticket.queue_free()
