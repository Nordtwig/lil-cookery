class_name SlotStation
extends Station

## A station with a single item slot: interact takes the item if your hands
## are free, or puts down what you're carrying if the slot is free.
## Subclasses hook the placed/removed events to add behavior (e.g. cooking).

var held_item: Item = null

@onready var _slot: Marker3D = $Slot


func interact(player: Player) -> void:
	var carried := player.held_item
	if carried == null and held_item != null:
		# Take the item off the station.
		var item := held_item
		held_item = null
		player.take_item(item)
		_on_item_removed(item)
	elif carried != null and held_item == null:
		# Place the carried item onto the empty slot.
		var item := player.drop_item()
		item.attach_to(_slot)
		held_item = item
		_on_item_placed(item)
	elif carried is Plate and (carried as Plate).can_add(held_item):
		# Carrying a plate, station holds a component: add it to the plate.
		var comp := held_item
		held_item = null
		_on_item_removed(comp)
		(carried as Plate).add_component(comp)
	elif held_item is Plate and (held_item as Plate).can_add(carried):
		# Station holds a plate, carrying a component: add it to the plate.
		player.drop_item()
		(held_item as Plate).add_component(carried)
	elif carried is Spice and (carried as Spice).can_use() and held_item != null and held_item.can_be_seasoned():
		# Carrying a shaker with charges left: season the item on the
		# station and spend one charge. The shaker itself is never placed
		# down here — bring it back to its rack to refill once it's empty.
		var spice := carried as Spice
		held_item.season(spice.bonus, spice.color)
		spice.consume_use()
	elif carried is Spice and (carried as Spice).can_use() and held_item is Plate:
		# Station holds a plate: season the first seasonable component on it
		# rather than gluing the shaker onto the plate as clutter.
		var spice := carried as Spice
		if (held_item as Plate).season_component(spice.bonus, spice.color):
			spice.consume_use()


func _on_item_placed(_item: Item) -> void:
	pass


func _on_item_removed(_item: Item) -> void:
	pass


## A plate on a counter, an ingredient on the cutting board, a patty on the
## stove — whatever's sitting in the slot is what's worth inspecting here,
## not the station itself. Empty slot -> nothing to add.
func get_inspect_text() -> String:
	if held_item != null:
		return held_item.get_inspect_text()
	return ""
