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
