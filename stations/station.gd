class_name Station
extends StaticBody3D

## Base for anything a player can target and interact with. Both players can
## target the same station at once, so the highlight is refcounted rather
## than a plain bool.

@onready var _highlight: MeshInstance3D = $Highlight

var _highlight_count := 0


func add_highlight() -> void:
	_highlight_count += 1
	_highlight.visible = true


func remove_highlight() -> void:
	_highlight_count = maxi(0, _highlight_count - 1)
	_highlight.visible = _highlight_count > 0


func interact(_player: Player) -> void:
	pass


## Called every frame while a targeting player holds interact. Pickup-side
## continuous input — currently a dispenser's hold-to-take-the-whole-batch
## (handled in SlotStation).
func interact_hold(_player: Player, _delta: float) -> void:
	pass


## Tap on the work button — a tool trigger: the stove's flip catch now, an
## oven door or similar later. Separate from interact so a normal pickup is
## never reinterpreted as a timing attempt. No-op where there's no trigger.
func action(_player: Player) -> void:
	pass


## Held work button — operating a tool over time, currently the cutting
## board's chop. Separate from interact_hold so "keep cutting" can never
## collide with "pick this up". No-op where there's no such tool.
func action_hold(_player: Player, _delta: float) -> void:
	pass


## Multi-line summary for the inspect panel. "" (the default) means nothing
## extra to show beyond what's already visible in the world.
func get_inspect_text() -> String:
	return ""
