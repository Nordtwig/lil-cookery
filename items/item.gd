class_name Item
extends Node3D

## A carryable ingredient. Items have no physics — they are always parented to
## a station slot, a player's hold point, or a plate. Prep is an ordered list
## of steps (from Ingredients); each completed step records a 0..1 skill score
## that feeds the component's contribution to dish quality.

@export var item_type := ""
## Base albedo. Derived from Ingredients for real ingredients; set directly in
## the scene for type-less items like the plate.
@export var color := Color.WHITE

# Cooking runs on a 0..BURNT_CAP "doneness" scale (the COOK step). Bands, plus
# Burnt as the overcook consequence. The Perfect window is generous.
const POOR_MAX := 0.5
const GOOD_MAX := 0.8
const PERFECT_MAX := 1.05
const BURNT_CAP := 1.25

# Chopping runs on the same shape of scale as cooking (the CHOP step): a
# continuous 0..CHOP_OVERCUT_CAP meter with a real downside for going past
# Perfect, mirroring doneness/burnt. Only advances while a player actively
# holds interact — unlike cooking, nothing chops itself unattended.
const CHOP_UNDER_MAX := 0.5
const CHOP_GOOD_MAX := 0.8
const CHOP_PERFECT_MAX := 1.05
const CHOP_OVERCUT_CAP := 1.25

## The whole mesh swaps to diced pieces partway through cutting, not the instant
## the knife touches it — otherwise placing an item on a board while still
## holding interact pops it straight to pieces. Roughly halfway (the
## undercut/good boundary), about when the stove's flip window opens.
const CHOP_PIECES_AT := 0.5

## How far the COOK step has progressed. Also drives the cooked tint.
var doneness := 0.0
## How far the CHOP step has progressed.
var chop_progress := 0.0

## Set by a Spice applied at a station. One-shot bonus — never stacks, never
## required, only ever raises quality_value().
var seasoned := false
var seasoning_bonus := 0.0

var _steps: Array = []
var _step_index := 0
var _prep_scores := {}  # Ingredients.Verb -> float (0..1)

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _pieces: Node3D = $Pieces
@onready var _season_marks: Node3D = $SeasonMarks

var _mat: StandardMaterial3D


func _ready() -> void:
	_steps = Ingredients.steps_for(item_type)
	if item_type != "":
		color = Ingredients.color_for(item_type)
	_mat = StandardMaterial3D.new()
	_mesh.material_override = _mat
	for piece in _pieces.get_children():
		(piece as MeshInstance3D).material_override = _mat
	_update_visual_state()
	_update_tint()


## The next unfinished prep verb, or -1 if fully prepped.
func next_verb() -> int:
	return _steps[_step_index] if _step_index < _steps.size() else -1


func has_step(verb: int) -> bool:
	return verb in _steps


func step_done(verb: int) -> bool:
	return _prep_scores.has(verb)


func is_fully_prepped() -> bool:
	return _step_index >= _steps.size()


## Record the current step as complete with a 0..1 skill score and advance.
func complete_step(score: float) -> void:
	var verb := next_verb()
	if verb == -1:
		return
	_prep_scores[verb] = score
	_step_index += 1
	_update_visual_state()
	_update_tint()
	if verb == Ingredients.Verb.CHOP:
		_punch(_active_visual())


# --- COOK step ---

## True once this specific Item instance has actually been through cook()
## itself, at least once — as opposed to `doneness` merely being pre-stamped
## on it (a yield ingredient's split-off piece inherits a visual doneness
## matching how well the batch baked, so it doesn't look freshly-raw, but it
## has never personally been cooked). Lets the very first real cook() call
## on such a piece start its own live doneness fresh — e.g. toasting an
## already-baked bread slice plays out as a genuine cook, not an instant
## burn from picking up wherever the loaf's bake left off — while a normal
## resumed cook (same instance, pulled and placed again) is unaffected,
## since by then this is already true and doneness legitimately continues.
var _cook_started := false

## Advance cooking by `delta` at the given rate (doneness/sec), re-tinting.
## Caps at Burnt so an abandoned item settles at low value, never vanishes.
func cook(delta: float, rate: float) -> void:
	if not _cook_started:
		_cook_started = true
		doneness = 0.0
	doneness = minf(doneness + rate * delta, BURNT_CAP)
	_update_tint()


## Locks in the cook step's score. The first time (step not yet done), this
## advances the prep chain normally via complete_step(). If it's already been
## cooked once and is being re-cooked (pulled, set aside, put back on a
## stove, pulled again), this just updates the recorded score in place —
## `doneness` was never reset, so cooking genuinely resumes rather than being
## locked out the moment the item first left the stove.
func lock_in_cook_score(score: float) -> void:
	if step_done(Ingredients.Verb.COOK):
		_prep_scores[Ingredients.Verb.COOK] = score
	else:
		complete_step(score)


func current_cook_band() -> String:
	if doneness < POOR_MAX:
		return "poor"
	elif doneness < GOOD_MAX:
		return "good"
	elif doneness < PERFECT_MAX:
		return "perfect"
	return "burnt"


func cook_score() -> float:
	match current_cook_band():
		"perfect": return 1.0
		"good": return 0.7
		"poor": return 0.4
	return 0.2  # burnt


# --- CHOP step ---

## Advance chopping by `delta` at the given rate (chop_progress/sec). Caps at
## CHOP_OVERCUT_CAP so leaving it under the knife too long settles at a low
## value, never vanishes — same shape as an abandoned item on the stove.
func chop(delta: float, rate: float) -> void:
	chop_progress = minf(chop_progress + rate * delta, CHOP_OVERCUT_CAP)
	_update_visual_state()


func current_chop_band() -> String:
	if chop_progress < CHOP_UNDER_MAX:
		return "undercut"
	elif chop_progress < CHOP_GOOD_MAX:
		return "good"
	elif chop_progress < CHOP_PERFECT_MAX:
		return "perfect"
	return "overcut"


## Locks in the chop step's score — same resume pattern as
## lock_in_cook_score(): first time advances the prep chain normally via
## complete_step(); already chopped once (a resumed item, put back on a
## board to refine further) just updates the recorded score in place.
## chop_progress is never reset, so it genuinely resumes rather than
## restarting.
func lock_in_chop_score(score: float) -> void:
	if step_done(Ingredients.Verb.CHOP):
		_prep_scores[Ingredients.Verb.CHOP] = score
	else:
		complete_step(score)


func chop_score() -> float:
	match current_chop_band():
		"perfect": return 1.0
		"good": return 0.7
		"undercut": return 0.4
	return 0.2  # overcut


# --- seasoning (optional, from a Spice) ---

## Real ingredients only (not a Plate or Spice, which have no item_type), and
## only once — a second shake of the same or another spice does nothing more.
func can_be_seasoned() -> bool:
	return item_type != "" and not seasoned


func season(bonus: float, spice_color: Color) -> void:
	if not can_be_seasoned():
		return
	seasoned = true
	seasoning_bonus = bonus
	_flash_seasoned(spice_color)


## True if nothing has happened to this item since it was dispensed — no
## prep, no cooking, no chopping, no seasoning. What a Crate checks before
## accepting an ingredient back (undoing the dispense); Plate overrides this
## with its own meaning ("no components added yet").
func is_unmodified() -> bool:
	return _prep_scores.is_empty() and chop_progress == 0.0 and doneness == 0.0 and not seasoned


## Changes this item's ingredient type in place (e.g. a re-cooked bread slice
## becoming toasted bread — see Ingredients.toasts_into) — updates its base
## color and re-tints immediately using the current doneness, so a
## well-toasted vs. burnt slice still reads differently. Doesn't touch
## prep-chain state; only meant for an item that's already fully prepped
## under its old type.
func transform_into(new_type: String) -> void:
	item_type = new_type
	color = Ingredients.color_for(new_type)
	_update_tint()


# --- scoring ---

## 0..1 contribution to a dish: low if under-prepped (steps left undone),
## otherwise the average of the skill scores earned across its prep steps.
## Seasoning always adds on top, capped at 1.0 — it only ever helps.
func quality_value() -> float:
	var base := 0.3
	if is_fully_prepped():
		if _prep_scores.is_empty():
			base = 0.8
		else:
			var total := 0.0
			for score in _prep_scores.values():
				total += score
			base = total / _prep_scores.size()
	return clampf(base + seasoning_bonus, 0.0, 1.0)


## Multi-line summary for the inspect panel. "" means nothing to show.
## Plate/Spice override this with their own shape.
func get_inspect_text() -> String:
	if item_type == "":
		return ""
	var lines := [item_type.capitalize().to_upper()]  # "toasted_bread" -> "TOASTED BREAD"
	if not _steps.is_empty():
		lines.append("Prep: %d/%d steps done" % [_step_index, _steps.size()])
	if has_step(Ingredients.Verb.CHOP):
		lines.append("Chop: %s" % current_chop_band().capitalize())
	if has_step(Ingredients.Verb.COOK):
		lines.append("Cook: %s" % current_cook_band().capitalize())
	if seasoned:
		lines.append("Seasoned +%d%%" % int(round(seasoning_bonus * 100)))
	lines.append("Quality: %d%%" % int(round(quality_value() * 100)))
	return "\n".join(lines)


## Whichever representation is currently on screen — the whole mesh, or the
## diced pieces once chopped. Punch/flip animations act on this.
func _active_visual() -> Node3D:
	return _pieces if _pieces.visible else _mesh


func _update_visual_state() -> void:
	# Whole vs diced tells prep state at a glance; swaps once cutting is roughly
	# halfway (CHOP_PIECES_AT), not the instant the knife touches it, so an item
	# placed on a board while interact is still held doesn't pop to pieces
	# immediately. chop_progress persists, so a resumed/pulled item stays diced.
	# The cook tint layers on top (shared material, applies to both).
	var chopped := chop_progress >= CHOP_PIECES_AT
	_mesh.visible = not chopped
	_pieces.visible = chopped


## Re-applies mesh/tint from the current chop_progress/doneness — for when
## something external sets those fields directly rather than through
## chop()/cook() (e.g. IngredientBundle borrowing this item's "already cut"
## look for its own decorative display, see IngredientBundle._ready).
func refresh_visual() -> void:
	_update_visual_state()
	_update_tint()


## Quick squash-and-settle, used whenever a step completes with a visible
## change (chopping into pieces) or a shaker lands a seasoning hit.
func _punch(node: Node3D) -> void:
	var base_scale := node.scale
	var tween := create_tween()
	tween.tween_property(node, "scale", base_scale * 1.25, 0.08)
	tween.tween_property(node, "scale", base_scale, 0.12)


func _flash_seasoned(spice_color: Color) -> void:
	# Physical flecks in the spice's own color read as "seasoned" at a
	# glance, no abstract glow needed. A punch-scale reads as the shake itself.
	var mark_mat := StandardMaterial3D.new()
	mark_mat.albedo_color = spice_color
	for mark in _season_marks.get_children():
		(mark as MeshInstance3D).material_override = mark_mat
	_season_marks.visible = true
	_punch(_active_visual())


## A quick rotate-and-hop, used by CookStation when the flip window is caught.
func flip_visual() -> void:
	var visual := _active_visual()
	var start_y := visual.position.y
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(visual, "rotation:x", visual.rotation.x + TAU, 0.35)
	tween.tween_property(visual, "position:y", start_y + 0.1, 0.17).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(visual, "position:y", start_y, 0.18).set_ease(Tween.EASE_IN)


func _update_tint() -> void:
	# Cookable items show the cook tint (pale raw → rich at done → charcoal
	# burnt) once any prior CHOP step is out of the way — or immediately, for
	# an ingredient like meat that skips chopping and goes straight to the
	# stove. Everything else shows its base color.
	var chop_clear := not has_step(Ingredients.Verb.CHOP) or step_done(Ingredients.Verb.CHOP)
	if has_step(Ingredients.Verb.COOK) and chop_clear:
		var pale := color.lerp(Color(0.90, 0.85, 0.80), 0.55)
		var cooked: Color
		if doneness <= 1.0:
			cooked = pale.lerp(color, clampf(doneness, 0.0, 1.0))
		else:
			var char_t := clampf((doneness - 1.0) / (BURNT_CAP - 1.0), 0.0, 1.0)
			cooked = color.lerp(Color(0.08, 0.07, 0.06), char_t)
		_mat.albedo_color = cooked
	else:
		_mat.albedo_color = color


func attach_to(new_parent: Node3D) -> void:
	if get_parent() != null:
		get_parent().remove_child(self)
	new_parent.add_child(self)
	position = Vector3.ZERO
	rotation = Vector3.ZERO
