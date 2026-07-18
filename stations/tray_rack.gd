class_name TrayRack
extends Station

## An infinite source of empty trays, mirroring PlateStack (trays aren't part
## of the finite-ingredients economy either). Carrying an empty tray and
## interacting puts it back — same "undo, no cost" shape as returning an
## empty plate; a tray with anything still in it is refused.

const TRAY_SCENE := preload("res://items/tray.tscn")


func interact(player: Player) -> void:
	var carried := player.held_item
	if carried == null:
		player.take_item(TRAY_SCENE.instantiate())
	elif carried is Tray and (carried as Tray).is_unmodified():
		player.drop_item()
		carried.queue_free()
