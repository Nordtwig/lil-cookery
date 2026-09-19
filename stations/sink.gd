class_name Sink
extends Station

## An infinite source of water, like PlateStack is of plates. Empty-handed, take a
## cup; carrying anything that takes water (a pot), fill it straight from the tap;
## carrying an untouched cup, pour it back.

const _WATER_SCENE := preload("res://items/water.tscn")


func interact(player: Player) -> void:
	var carried := player.held_item
	if carried == null:
		player.take_item(_spawn())
	elif carried.item_type == "water" and carried.is_unmodified():
		player.drop_item()
		carried.queue_free()
	elif carried.can_absorb_type("water"):
		carried.absorb(_spawn())


func hints(player: Player) -> Array[Dictionary]:
	var carried := player.held_item
	if carried == null:
		return [hint("interact", "Take some water")]
	if carried.item_type == "water" and carried.is_unmodified():
		return [hint("interact", "Pour it back")]
	if carried.can_absorb_type("water"):
		return [hint("interact", "Fill %s" % carried.hint_name())]
	return []


func _spawn() -> Item:
	var water: Item = _WATER_SCENE.instantiate()
	water.item_type = "water"
	return water


func get_inspect_text() -> String:
	return "SINK"
