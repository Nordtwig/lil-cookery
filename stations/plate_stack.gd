class_name PlateStack
extends Station

## An infinite source of empty plates.

const PLATE_SCENE := preload("res://items/plate.tscn")


func interact(player: Player) -> void:
	if player.held_item != null:
		return
	player.take_item(PLATE_SCENE.instantiate())
