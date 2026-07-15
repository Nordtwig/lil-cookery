class_name InspectPanel
extends Control

## Per-player screen-corner tooltip. While that player holds their inspect
## action, shows live info about whatever they're carrying and/or currently
## targeting — held item state (prep/quality/seasoning) or a station's
## storage/charge counts. Hidden whenever there's nothing to say.

@export_range(1, 2) var player_id := 1

@onready var _panel: Panel = $Panel
@onready var _label: Label = $Panel/Label

var _player: Player


func _ready() -> void:
	_panel.visible = false
	_player = get_tree().current_scene.find_child("Player%d" % player_id, true, false) as Player


func _process(_delta: float) -> void:
	if _player == null or not Input.is_action_pressed("p%d_inspect" % player_id):
		_panel.visible = false
		return

	var lines: Array[String] = []
	if _player.held_item != null:
		var held_text := _player.held_item.get_inspect_text()
		if held_text != "":
			lines.append(held_text)
	var target := _player.get_target()
	if target != null:
		var target_text := target.get_inspect_text()
		if target_text != "":
			lines.append(target_text)

	if lines.is_empty():
		_panel.visible = false
		return

	_label.text = "\n\n".join(lines)
	_panel.visible = true
