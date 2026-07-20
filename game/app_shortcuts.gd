extends Node

## Always-on quality-of-life shortcuts, independent of whatever scene is
## active — lets whoever's running a build quit or restart the round without
## alt-tabbing or relaunching the exe. Autoloaded so it survives once there's
## more than one scene (the eventual day-cycle work).

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F5:
		get_tree().reload_current_scene()
