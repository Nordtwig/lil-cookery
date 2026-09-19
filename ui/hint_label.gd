class_name HintLabel
extends Node3D

## Per-player floating hints, above the station that player is facing: what E and R
## (tap and hold) would do there with what they're carrying. Reads Station.hints()
## every frame and names the keys from the InputMap, so a rebinding shows up on its
## own. P1/P2 sit left/right of the station so two players facing the same thing don't
## overwrite each other. Hidden when there's
## nothing to do, while inspect is held, and while a UI has the player's input.

@export_range(1, 2) var player_id := 1
## World height above a station's origin.
@export var height := 1.35
## Sideways offset so two players' hints on one station don't overlap.
@export var side := 0.45

@onready var _label: Label3D = $Label

var _player: Player
var _keys := {}


func _ready() -> void:
	_label.visible = false
	_player = get_tree().current_scene.find_child("Player%d" % player_id, true, false) as Player
	_keys = {
		"interact": _key_name("p%d_interact" % player_id),
		"interact_hold": "Hold " + _key_name("p%d_interact" % player_id),
		"action": _key_name("p%d_action" % player_id),
		"action_hold": "Hold " + _key_name("p%d_action" % player_id),
	}


## The keyboard binding's label; a gamepad-only binding shows as its button index.
func _key_name(action: String) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var k := event as InputEventKey
			var code := k.keycode
			if k.physical_keycode != 0:
				# The physical->layout lookup is a real display server feature; headless has none.
				code = k.physical_keycode
				if DisplayServer.get_name() != "headless":
					var mapped := DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode)
					if mapped != 0:
						code = mapped
			return OS.get_keycode_string(code)
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			return "Button %d" % (event as InputEventJoypadButton).button_index
	return "?"


func _process(_delta: float) -> void:
	if _player == null or _player.ui_capture != null or Input.is_action_pressed("p%d_inspect" % player_id):
		_label.visible = false
		return
	var target := _player.get_target()
	if target == null:
		_label.visible = false
		return
	var lines: Array[String] = []
	for h in target.hints(_player):
		lines.append("%s: %s" % [_keys.get(h.button, "?"), h.text])
	if lines.is_empty():
		_label.visible = false
		return
	_label.text = "\n".join(lines)
	var x_side := -side if player_id == 1 else side
	global_position = target.global_position + Vector3(x_side, height, 0.0)
	_label.visible = true
