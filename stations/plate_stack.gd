class_name PlateStack
extends Station

## An infinite source of empty plates. Carrying an unmodified (still empty)
## plate and interacting instead puts it back, same "undo, no cost" shape as
## returning an ingredient to its Crate — a tag on that plate survives the
## return as a real ticket handed back to the player, never destroyed with it.
##
## Carrying an OrderTicket instead grabs a plate already tagged with that
## order — the common case (grab a ticket, then immediately want a plate for
## it) used to be ticket-down, plate-up, combine as three separate steps;
## now it's one pickup. The ticket is consumed exactly as tag_order() already
## consumes it elsewhere.

const PLATE_SCENE := preload("res://items/plate.tscn")
const _ORDER_TICKET_SCENE := preload("res://items/order_ticket.tscn")


func hints(player: Player) -> Array[Dictionary]:
	var carried := player.held_item
	if carried == null:
		return [hint("interact", "Take a plate")]
	if carried is Plate and (carried as Plate).is_unmodified():
		return [hint("interact", "Put the plate back")]
	if carried is OrderTicket:
		return [hint("interact", "Take a plate for this order")]
	return []


func interact(player: Player) -> void:
	var carried := player.held_item
	if carried == null:
		player.take_item(PLATE_SCENE.instantiate())
	elif carried is Plate and (carried as Plate).is_unmodified():
		# A still-empty plate returns to the (infinite) stack and is freed —
		# but if it was tagged, that tag comes back as a real ticket in hand
		# instead of being destroyed along with the plate. Same "swap, never
		# silently lose it" rule as the tag branches in SlotStation.
		var plate := carried as Plate
		if plate.is_tagged():
			var ticket: OrderTicket = _ORDER_TICKET_SCENE.instantiate()
			ticket.dish = plate.tagged_dish()
			ticket.table_number = plate.tagged_table_number()
			player.drop_item()
			player.take_item(ticket)
		else:
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
