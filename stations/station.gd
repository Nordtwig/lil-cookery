class_name Station
extends StaticBody3D

## Base for anything a player can target and interact with. Both players can
## target the same station at once, so the highlight is refcounted rather
## than a plain bool.

@onready var _highlight: MeshInstance3D = $Highlight

var _highlight_count := 0

## The cell this station currently occupies in StationGrid, set by
## StationGrid.register() at _ready(). Subclasses that override _ready()
## must call super._ready() first so registration still happens.
var grid_cell: Vector2i

## Set before entering the tree to instantiate a pure-display copy of a
## station scene (build mode's carried preview) — skips grid registration
## (its position changes every frame following the player, so it must never
## occupy a cell) and highlight/collision entirely. Callers are expected to
## also zero collision_layer/collision_mask and call set_process(false)/
## set_physics_process(false) themselves; this flag only handles the grid.
var _is_ghost := false


func _ready() -> void:
	if not _is_ghost:
		StationGrid.register(self)


func _exit_tree() -> void:
	if not _is_ghost:
		StationGrid.unregister(self)


func add_highlight() -> void:
	_highlight_count += 1
	_highlight.visible = true


func remove_highlight() -> void:
	_highlight_count = maxi(0, _highlight_count - 1)
	_highlight.visible = _highlight_count > 0


var _highlight_tint_mat: StandardMaterial3D = null


## Tints the highlight box a specific color, for a state the default yellow
## "targeted" tint doesn't cover (build mode's "hold to clear and lift" cue).
## Uses material_override rather than touching the highlight mesh's own
## material resource, since that's shared across every instance of this
## station's scene — mutating it in place would tint every instance's
## highlight, not just this one.
func set_highlight_tint(color: Color) -> void:
	if _highlight_tint_mat == null:
		_highlight_tint_mat = StandardMaterial3D.new()
		_highlight_tint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_highlight_tint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_highlight.material_override = _highlight_tint_mat
	_highlight_tint_mat.albedo_color = color


func clear_highlight_tint() -> void:
	_highlight.material_override = null
	_highlight_tint_mat = null


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


## Per-instance identity that must survive a despawn/respawn round trip (grid-
## based relocation) — the differing @export values that make this instance
## not just any station of its scene (a Crate's item_type, a Table's
## table_number). Scene identity itself is separate (scene_file_path), so this
## is only ever the extra bit of config on top. Base: none — most stations
## (Counter, CookStation, CuttingBoard, PlateStack, TrayRack, Trashcan) are
## fully defined by their scene alone.
func get_config() -> Dictionary:
	return {}


## Re-applies a config captured by get_config(). Must be called before this
## station enters the tree (i.e. before add_child), since most stations read
## their exported config in _ready(). Base: no-op.
func apply_config(_config: Dictionary) -> void:
	pass


## True if this station holds nothing that would be lost by relocating it —
## the gate grid-based movement checks before allowing a lift without a
## warning. Base: true (nothing to lose by default).
func is_empty() -> bool:
	return true


## Destroys whatever this station currently holds so it can be safely
## relocated — the "clear it" half of "clear it, with a warning." Base:
## no-op (nothing to clear).
func clear_contents() -> void:
	pass
