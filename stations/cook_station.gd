class_name CookStation
extends SlotStation

## A stove. Place a raw cookable item and it cooks on its own; a flat gauge
## in front shows the band (Poor → Good → Perfect → Burnt). Pull it at the
## right moment. Leaving it too long burns it to a low-value item — the cost
## is systemic (lost quality), never a hard fail.
##
## Partway through, a "FLIP!" window opens once per cook: catching it with a
## tap on **action** adds a quality bonus on top of whatever band you
## eventually pull at. Same shape as the cutting board's opt-in timing —
## ignore it entirely and the item still finishes exactly as it always has,
## no penalty. Interact itself is never overridden here, so pulling the item
## off the stove always works immediately, even mid-flip-window — the flip is
## a pure bonus chance, never a hijack of a normal pull. Pulling a
## partially-cooked item off doesn't lock it out of cooking further — set it
## aside and put it back on any stove later to resume right where doneness
## left off.

## Seconds for doneness to travel from raw (0) to the top of the Perfect
## window (1.0). The Perfect band is ~1.5s of this at the default.
@export var cook_duration := 6.0
## Doneness (same 0..1-ish scale as Item.doneness) at which the flip window
## opens — a bit before the Poor/Good boundary, so it reads as "partway".
@export var flip_window_start := 0.45
@export var flip_window_duration := 1.0
@export var flip_bonus := 0.1

const _BAND_COLORS := {
	"poor": Color(0.90, 0.50, 0.20),
	"good": Color(0.85, 0.80, 0.20),
	"perfect": Color(0.30, 0.85, 0.35),
	"burnt": Color(0.15, 0.13, 0.12),
}

@onready var _gauge: Node3D = $Gauge
@onready var _fill_pivot: Node3D = $Gauge/FillPivot
@onready var _fill_mesh: MeshInstance3D = $Gauge/FillPivot/Fill
@onready var _flip_cue: Label3D = $FlipCue

var _fill_mat: StandardMaterial3D

var _flip_triggered := false
var _flip_open := false
var _flip_timer := 0.0
var _flipped_well := false
var _flip_tween: Tween


func _ready() -> void:
	_fill_mat = StandardMaterial3D.new()
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mesh.material_override = _fill_mat
	_gauge.visible = false
	_flip_cue.visible = false


func _process(delta: float) -> void:
	if not _is_cooking():
		return
	held_item.cook(delta, 1.0 / cook_duration)
	_update_gauge()
	_update_flip_window(delta)


func action(_player: Player) -> void:
	if _flip_open:
		_catch_flip()


func _catch_flip() -> void:
	_flipped_well = true
	held_item.flip_visual()
	_close_flip_window()


func _on_item_placed(item: Item) -> void:
	_gauge.visible = _can_cook(item)
	if _gauge.visible:
		_update_gauge()
	_flip_triggered = false
	_flipped_well = false
	_close_flip_window()


func _on_item_removed(item: Item) -> void:
	_gauge.visible = false
	_close_flip_window()
	if _can_cook(item):
		var score := item.cook_score()
		if _flipped_well:
			score = minf(1.0, score + flip_bonus)
		item.lock_in_cook_score(score)


func _is_cooking() -> bool:
	return held_item != null and _can_cook(held_item)


## True both the first time (COOK is the pending step) and for a resumed
## item that's already been cooked once (COOK already recorded, but
## doneness carries forward so more heat keeps having an effect).
func _can_cook(item: Item) -> bool:
	return item.has_step(Ingredients.Verb.COOK) and (
		item.next_verb() == Ingredients.Verb.COOK
		or item.step_done(Ingredients.Verb.COOK)
	)


func _update_gauge() -> void:
	var normalized := clampf(held_item.doneness / Item.BURNT_CAP, 0.0, 1.0)
	_fill_pivot.scale.x = maxf(normalized, 0.001)
	_fill_mat.albedo_color = _BAND_COLORS[held_item.current_cook_band()]


func _update_flip_window(delta: float) -> void:
	if not _flip_triggered and held_item.doneness >= flip_window_start:
		_open_flip_window()
	if _flip_open:
		_flip_timer -= delta
		if _flip_timer <= 0.0:
			_close_flip_window()


func _open_flip_window() -> void:
	_flip_triggered = true
	_flip_open = true
	_flip_timer = flip_window_duration
	_flip_cue.visible = true
	_flip_cue.scale = Vector3.ONE
	_flip_tween = create_tween().set_loops()
	_flip_tween.tween_property(_flip_cue, "scale", Vector3.ONE * 1.3, 0.25)
	_flip_tween.tween_property(_flip_cue, "scale", Vector3.ONE, 0.25)


func _close_flip_window() -> void:
	_flip_open = false
	_flip_cue.visible = false
	if _flip_tween != null:
		_flip_tween.kill()
		_flip_tween = null
