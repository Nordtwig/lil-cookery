class_name CookStation
extends SlotStation

## A stove: heat plus a surface. The surface takes only vessels (a Pot, a Pan -
## `Item.is_vessel()`), never bare food; what actually cooks is the vessel's
## `cook_subject()` - the pot itself, or whatever sits in the pan. Everything
## below that reads "the item" means that subject. A flat gauge in front shows
## its band (Poor → Good → Perfect → Burnt). Pull it at the right moment.
## Leaving it too long burns it to a low-value item — the cost is systemic
## (lost quality), never a hard fail. Taking the food out of the pan by a tap
## scores it the same as lifting the pan does (_on_portion_dispensed) - the
## flip bonus counts either way. A looping frying sound plays
## for exactly as long as _is_heating() is true (started/stopped in _process,
## not tied to any specific placement/removal branch, so it can never be left
## running after an item's pulled or forgotten silent while one's cooking).
##
## The burner has a switch. Hold **action** to toggle it; a cold stove is just a
## counter - whatever sits on it keeps its doneness but doesn't cook. That makes
## fire-and-forget a choice rather than a property of the food: light a pot in the
## morning and come back to kill the heat, or forget and let it burn. Tap-action stays
## the flip catch, so a mistimed flip can never switch the burner off. Every stove
## starts cold each morning.
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
## A stove also runs STOVE transforms (`Ingredients.stove_output_for`): a
## bread slice toasts into toasted_bread, a chopped potato fries into
## fried_potato. A fresh cook on its own clock (doneness starts from 0,
## unrelated to any earlier cook), tinting toward the output's color. Pull it
## past _TRANSFORM_MIN and it becomes the output, its quality the average of
## what came in and how well you timed this heat. Pull too early and it's
## just warm - put it back to keep going.

## Seconds for doneness to travel from raw (0) to the top of the Perfect
## window (1.0). The Perfect band is ~1.5s of this at the default.
@export var cook_duration := 6.0
## Doneness (same 0..1-ish scale as Item.doneness) at which the flip window
## opens — a bit before the Poor/Good boundary, so it reads as "partway".
@export var flip_window_start := 0.45
@export var flip_window_duration := 1.0
@export var flip_bonus := 0.1
## How long action must be held to flip the switch. Longer than any flip-catch tap.
@export var toggle_hold_time := 0.35

const _BURNER_COLD := Color(0.12, 0.12, 0.13)
const _BURNER_LIT := Color(0.95, 0.35, 0.12)

## Doneness a transform input must reach before pulling it converts it.
## Below this it's just warm - no harm, put it back to keep going. Matches
## the Good-band boundary, so light heat isn't "toast" yet.
const _TRANSFORM_MIN := 0.5

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
@onready var _fry_sound: AudioStreamPlayer3D = $FrySound
@onready var _burner: MeshInstance3D = find_mesh_instance($Burner)

var burner_on := false
var _burner_mat: StandardMaterial3D
## Who is holding action on the switch, and for how long. One toggle per press.
var _toggle_player: Player = null
var _toggle_held := 0.0
var _toggled_this_press := false

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
	_burner_mat = StandardMaterial3D.new()
	_burner.material_override = _burner_mat
	_update_burner()
	GameState.phase_changed.connect(_on_phase_changed)


func _on_phase_changed(phase: int) -> void:
	if phase == GameState.Phase.MORNING:
		set_burner(false)


func set_burner(on: bool) -> void:
	burner_on = on
	if not on:
		_close_flip_window()
	_update_burner()


func _update_burner() -> void:
	_burner_mat.albedo_color = _BURNER_LIT if burner_on else _BURNER_COLD
	_burner_mat.emission_enabled = burner_on
	_burner_mat.emission = _BURNER_LIT
	_burner_mat.emission_energy_multiplier = 1.5


func _process(delta: float) -> void:
	if _toggle_player != null and not Input.is_action_pressed("p%d_action" % _toggle_player.player_id):
		_toggle_player = null
		_toggle_held = 0.0
		_toggled_this_press = false
	# Resolve a pending tap/hold first - a patty tapped out of a heating pan has
	# to leave before this frame's heat lands on it.
	super._process(delta)
	var heating := _is_heating()
	if heating and not _fry_sound.playing:
		_fry_sound.play()
	elif not heating and _fry_sound.playing:
		_fry_sound.stop()
	if heating:
		var subject := _subject()
		var t := subject.cook_time()
		subject.cook(delta, 1.0 / (t if t > 0.0 else cook_duration))
		_update_gauge()
		_update_flip_window(delta)


func action(_player: Player) -> void:
	if _flip_open:
		_catch_flip()


func action_hold(player: Player, delta: float) -> void:
	if _toggle_player != player:
		_toggle_player = player
		_toggle_held = 0.0
		_toggled_this_press = false
	_toggle_held += delta
	if _toggle_held >= toggle_hold_time and not _toggled_this_press:
		_toggled_this_press = true
		set_burner(not burner_on)


func _catch_flip() -> void:
	_flipped_well = true
	_subject().flip_visual()
	_close_flip_window()


## Only vessels go on a burner.
func accepts(item: Item) -> bool:
	return item.is_vessel()


## What is actually cooking: the held vessel's subject, or null.
func _subject() -> Item:
	return held_item.cook_subject() if held_item != null else null


func _on_item_placed(item: Item) -> void:
	var subject := item.cook_subject()
	_gauge.visible = subject != null and (_can_cook(subject) or _can_transform(subject))
	if _gauge.visible:
		_update_gauge()
	_flip_triggered = false
	_flipped_well = false
	_close_flip_window()


func _on_item_removed(item: Item) -> Item:
	var subject := item.cook_subject()
	if subject != null:
		_settle(subject)
	_gauge.visible = false
	_close_flip_window()
	return item


## Food taken out of the pan by a tap leaves the heat the same as the pan lifting.
func _on_portion_dispensed(portion: Item) -> Item:
	_settle(portion)
	return portion


## The pan was filled or emptied in place: start or stop gauging its new content.
func _on_held_contents_changed() -> void:
	_on_item_placed(held_item)


## An item is leaving the heat: lock in its cook score, or convert a transform
## input that got far enough. Nothing happens to something the stove wasn't
## acting on (a stock cup ladled from the pot).
func _settle(subject: Item) -> void:
	if _can_transform(subject):
		_close_flip_window()
		if subject.doneness >= _TRANSFORM_MIN:
			_transform(subject)
	elif _can_cook(subject):
		_score_and_lock(subject)


## Turn a sufficiently-heated input into its STOVE output. Its final quality
## is the average of what came in (a slice's inherited bake, a potato's chop)
## and how well this heat was timed (plus any flip bonus) - both stages matter.
## transform_into re-tints to the output's base color, so doneness no longer
## drives its look afterward.
func _transform(item: Item) -> void:
	var heat_score := item.cook_score()
	if _flipped_well:
		heat_score = minf(1.0, heat_score + flip_bonus)
	var in_q := item.inherited_quality if item.inherited_quality >= 0.0 else item.quality_value()
	var final_q := clampf((in_q + heat_score) / 2.0, 0.0, 1.0)
	item.transform_into(Ingredients.stove_output_for(item.item_type))
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
	var subject := _subject()
	return burner_on and subject != null and (_can_cook(subject) or _can_transform(subject))


## True both the first time (COOK is the pending step) and for a resumed item
## that's already been cooked once (COOK recorded, but doneness carries forward
## so more heat keeps having an effect). A finished dispenser (a baked loaf, a
## roasted bird) is excluded — it's done and meant to be sliced, not re-cooked
## to charcoal. A raw bird can be jointed but still needs roasting, so the
## test is "finished", not "can dispense".
func _can_cook(item: Item) -> bool:
	if item.is_dispenser() and item.is_fully_prepped():
		return false
	return item.has_step(Ingredients.Verb.COOK) and (
		item.next_verb() == Ingredients.Verb.COOK
		or item.step_done(Ingredients.Verb.COOK)
	)


## True for an item some STOVE recipe turns into something else - a bread
## slice into toasted_bread, a chopped potato into fried_potato. This is how
## an item with no COOK step of its own still cooks on a stove: a fresh heat
## on its own clock. The recipe's entry decides whether prep comes first - a
## plain "potato" wants the board done, "any potato" takes it whole.
func _can_transform(item: Item) -> bool:
	if item == null:
		return false
	var out := Ingredients.stove_output_for(item.item_type)
	if out == "":
		return false
	return item.is_fully_prepped() or Ingredients.input_any(Ingredients.made_from_for(out)[0])


func hints(player: Player) -> Array[Dictionary]:
	var out := super.hints(player)
	if _flip_open:
		out.append(hint("action", "Flip!"))
	out.append(hint("action_hold", "Turn the stove off" if burner_on else "Light the stove"))
	return out


func get_inspect_text() -> String:
	var header := "STOVE: %s" % ("ON" if burner_on else "OFF")
	var rest := super.get_inspect_text()
	return header if rest == "" else header + "\n" + rest


func _update_gauge() -> void:
	var subject := _subject()
	var normalized := clampf(subject.doneness / Item.BURNT_CAP, 0.0, 1.0)
	_fill_pivot.scale.x = maxf(normalized, 0.001)
	_fill_mat.albedo_color = _BAND_COLORS[subject.current_cook_band()]


func _update_flip_window(delta: float) -> void:
	if not _flip_triggered and _subject().doneness >= flip_window_start:
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
