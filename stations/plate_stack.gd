class_name PlateStack
extends Station

## An infinite source of empty plates. Carrying an unmodified (still empty)
## plate and interacting instead puts it back, same "undo, no cost" shape as
## returning an ingredient to its Crate.

const PLATE_SCENE := preload("res://items/plate.tscn")


func interact(player: Player) -> void:
	var carried := player.held_item
	if carried == null:
		player.take_item(PLATE_SCENE.instantiate())
	elif carried is Plate and (carried as Plate).is_unmodified():
		player.drop_item()
		carried.queue_free()
