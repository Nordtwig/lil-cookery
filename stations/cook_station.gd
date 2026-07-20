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
## no penalty. Pulling the item off always works immediately, even mid-flip-
## window (the flip is a pure bonus chance, never a hijack of a normal pull).
## Pulling a partially-cooked item off doesn't lock it out of cooking further
## — set it aside and put it back on any stove later to resume right where
## doneness left off.
##
## A finished dispenser (a baked loaf) is inert here — it's done, and its job
## is now to be sliced, not re-cooked — so it just sits without the gauge
## running, never burning down from being set on a stove. Peeling slices off
## it (empty-handed tap/hold) works here too, via the shared SlotStation logic.
##
## A bread slice can be *toasted* on a stove — a fresh cook on its own clock
## (its doneness starts from 0, unrelated to how the loaf was baked), darkening
## it toward the toasted color. Pull it once it's toasted and it becomes
## toasted_bread (what bruschetta wants), its quality the average of the loaf's
## bake and how well you timed the toast. Pull too early and it's just a warm
## slice — put it back to keep toasting.

## Seconds for doneness to travel from raw (0) to the top of the Perfect
## window (1.0). The Perfect band is ~1.5s of this at the default.
@export var cook_duration := 6.0
## Doneness (same 0..1-ish scale as Item.doneness) at which the flip window
## opens — a bit before the Poor/Good boundary, so it reads as "partway".
@export var flip_window_start := 0.45
@export var flip_window_duration := 1.0
@export var flip_bonus := 0.1

## Doneness a slice must reach before pulling it actually counts as toasted
## (and transforms it). Below this it's just a warm slice — no harm, put it
## back to keep going. Matches the Good-band boundary, so light heat isn't
## "toast" yet.
const _TOAST_MIN := 0.5

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
	super._ready()
	_fill_mat = StandardMaterial3D.new()
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mat.no_depth_test = true
	# Highest of the three gauge materials (BG=0, PerfectZone=1) — without an
	# explicit order, several no-depth-test layers draw in whatever order
	# Godot's render sort picks, not their actual spatial stacking, so the
	# fill (the actual progress meter) could end up hidden behind the BG.
	_fill_mat.render_priority = 2
	_fill_mesh.material_override = _fill_mat
	_gauge.visible = false
	_flip_cue.visible = false


func _process(delta: float) -> void:
	if _is_heating():
		held_item.cook(delta, 1.0 / cook_duration)
		_update_gauge()
		_update_flip_window(delta)
		return
	super._process(delta)  # let SlotStation resolve a pending dispense-take


func action(_player: Player) -> void:
	if _flip_open:
		_catch_flip()


func _catch_flip() -> void:
	_flipped_well = true
	held_item.flip_visual()
	_close_flip_window()


func _on_item_placed(item: Item) -> void:
	_gauge.visible = _can_cook(item) or _can_toast(item)
	if _gauge.visible:
		_update_gauge()
	_flip_triggered = false
	_flipped_well = false
	_close_flip_window()


func _on_item_removed(item: Item) -> Item:
	if _can_toast(item):
		_gauge.visible = false
		_close_flip_window()
		if item.doneness >= _TOAST_MIN:
			_toast_transform(item)
		return item
	if _can_cook(item):
		_score_and_lock(item)
		return item
	_gauge.visible = false
	_close_flip_window()
	return item


## Turn a sufficiently-toasted slice into toasted_bread. Its final quality is
## the average of the loaf's inherited bake quality and how well the toast was
## timed (plus any flip bonus) — both baking and toasting matter for a good
## bruschetta. transform_into re-tints to the toasted base color, so doneness
## no longer drives its look afterward.
func _toast_transform(item: Item) -> void:
	var toast_score := item.cook_score()
	if _flipped_well:
		toast_score = minf(1.0, toast_score + flip_bonus)
	var bake_q := item.inherited_quality if item.inherited_quality >= 0.0 else item.quality_value()
	var final_q := clampf((bake_q + toast_score) / 2.0, 0.0, 1.0)
	item.transform_into("toasted_bread")
	item.inherited_quality = final_q


func _score_and_lock(item: Item) -> float:
	_gauge.visible = false
	_close_flip_window()
	var score := item.cook_score()
	if _flipped_well:
		score = minf(1.0, score + flip_bonus)
	item.lock_in_cook_score(score)
	return score


func _is_heating() -> bool:
	return held_item != null and (_can_cook(held_item) or _can_toast(held_item))


## True both the first time (COOK is the pending step) and for a resumed item
## that's already been cooked once (COOK recorded, but doneness carries forward
## so more heat keeps having an effect). A finished dispenser (a baked loaf)
## is excluded — it's done and meant to be sliced, not re-cooked to charcoal.
func _can_cook(item: Item) -> bool:
	if item.can_dispense():
		return false
	return item.has_step(Ingredients.Verb.COOK) and (
		item.next_verb() == Ingredients.Verb.COOK
		or item.step_done(Ingredients.Verb.COOK)
	)


## True for a finished portion that toasting turns into something else — a
## bread slice → toasted_bread. This is how a slice (which has no COOK step of
## its own) still cooks on a stove: a fresh heat on its own clock.
func _can_toast(item: Item) -> bool:
	return item != null and Ingredients.toasts_into(item.item_type) != ""


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
