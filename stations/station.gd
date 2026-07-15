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


## Called every frame while a targeting player holds interact. Stations that
## need continuous input (e.g. the cutting board) override this.
func interact_hold(_player: Player, _delta: float) -> void:
	pass


## Tap-triggered "skill move" — the opt-in timing mechanic a station offers,
## if any (currently just the stove's flip catch). Kept on a separate button
## from interact so a normal pick-up/put-down action never gets silently
## reinterpreted as a timing attempt. Does nothing where there's no such
## mechanic.
func action(_player: Player) -> void:
	pass


## Multi-line summary for the inspect panel. "" (the default) means nothing
## extra to show beyond what's already visible in the world.
func get_inspect_text() -> String:
	return ""
