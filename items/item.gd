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

## A finished portion (a peeled slice/scrap) carries the quality it inherited
## from the whole it was cut from, rather than earning it through its own prep
## chain. -1 means unset (this item earns quality normally). See can_dispense.
var inherited_quality := -1.0

## For a dispenser ingredient (a loaf, a head — Ingredients.dispenses_for),
## how many portions are still in it. -1 means "not a dispenser". Initialized
## in _ready; decremented by a station each time a portion is peeled off.
var uses_left := -1

var _steps: Array = []
var _step_index := 0
var _prep_scores := {}  # Ingredients.Verb -> float (0..1)

## Node3D, not MeshInstance3D — a simple ingredient's Mesh is one MeshInstance3D
## directly, but one built from an imported model (see mozzarella.tscn) is a
## whole instanced scene wrapping its own MeshInstance3D. Everything below only
## ever needs Node3D's API (visible, tree walking), so either shape works.
@onready var _mesh: Node3D = $Mesh
@onready var _pieces: Node3D = $Pieces
@onready var _season_marks: Node3D = $SeasonMarks

var _mat: StandardMaterial3D


func _ready() -> void:
	_steps = Ingredients.steps_for(item_type)
	if item_type != "":
		color = Ingredients.color_for(item_type)
	if Ingredients.dispenses_for(item_type) != "":
		uses_left = Ingredients.uses_for(item_type)
	_mat = StandardMaterial3D.new()
	# Tint the whole visual subtree, so a representation built from several
	# meshes (a portion modeled as a little clump of shreds, not one box) all
	# takes the food color. SeasonMarks live outside Mesh/Pieces and keep their
	# own spice-colored material.
	_tint_tree(_mesh)
	_tint_tree(_pieces)
	_update_visual_state()
	_update_tint()


## A vessel is what a stove holds - a Pot, a Pan. Nothing else goes on a burner.
func is_vessel() -> bool:
	return false


## What a stove actually cooks when this sits on it: the item itself, or for a pan
## its content (null when empty). A pot is its own subject - it cooks as one thing.
func cook_subject() -> Item:
	return self


## Whether heat would do anything to this right now: a COOK step (pending or done -
## more heat keeps having an effect), or a STOVE recipe whose prep rule it meets. A
## finished dispenser (a baked loaf) is inert - its job is to be sliced.
func heatable() -> bool:
	if is_dispenser() and is_fully_prepped():
		return false
	if has_step(Ingredients.Verb.COOK):
		return true
	var out := Ingredients.stove_output_for(item_type)
	return out != "" and (is_fully_prepped() or Ingredients.input_any(Ingredients.made_from_for(out)[0]))


## What a hint calls this - "Potato", "Chicken Piece". Things without an
## item_type (a plate, a tray) say what they are.
func hint_name() -> String:
	return item_type.capitalize() if item_type != "" else "Item"


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

## Seconds to cook this to the top of Perfect, or 0 to use the stove's default.
func cook_time() -> float:
	return Ingredients.cook_time_for(item_type)


## Advance cooking by `delta` at the given rate (doneness/sec), re-tinting.
## Caps at Burnt so an abandoned item settles at low value, never vanishes.
func cook(delta: float, rate: float) -> void:
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


## Changes this item's ingredient type in place (a STOVE transform's output, a
## dispenser's remainder — see Ingredients.stove_output_for) — updates its base
## color and re-tints immediately using the current doneness, so a
## well-toasted vs. burnt slice still reads differently. Doesn't touch
## prep-chain state; only meant for an item that's already fully prepped
## under its old type.
func transform_into(new_type: String) -> void:
	item_type = new_type
	color = Ingredients.color_for(new_type)
	# Re-derive the prep chain: a step already scored stays done if the new type
	# has it too (a roasted bird's bones stay "cooked"); anything else is fresh.
	_steps = Ingredients.steps_for(new_type)
	_step_index = 0
	for verb in _steps:
		if not _prep_scores.has(verb):
			break
		_step_index += 1
	uses_left = Ingredients.uses_for(new_type) if Ingredients.dispenses_for(new_type) != "" else -1
	_update_visual_state()
	_update_tint()


# --- dispensing ---
#
# One shared grammar for anything that holds portions (tap peels one, hold
# takes the whole thing; carrying a matching item, tap merges it back in,
# hold absorbs + takes everything). The base implementations cover the
# data-driven ingredient dispensers (a baked loaf, a chopped head — driven
# by Ingredients' dispenses/uses fields); Tray overrides all of them to be a
# player-filled container of real items instead. SlotStation only ever talks
# to these five methods, so it needs no per-type knowledge.

## True if this is a dispenser type at all (a loaf, a head) — regardless of
## whether it's been prepped yet.
func is_dispenser() -> bool:
	return Ingredients.dispenses_for(item_type) != ""


## True if a portion can be peeled off right now: it's a dispenser with portions
## left, and either its own prep step (baking a loaf, chopping a head) is done or
## it's the kind that can be picked raw (a chicken, jointed before roasting).
func can_dispense() -> bool:
	return is_dispenser() and uses_left > 0 and _ready_to_dispense()


func _ready_to_dispense() -> bool:
	return is_fully_prepped() or Ingredients.dispenses_raw(item_type)


## True if `item` can be merged back in — a portion of the type this whole
## dispenses, with room for it. A full dispenser refuses (the item stays in
## the player's hand) rather than silently eating the merge.
func can_absorb(item: Item) -> bool:
	# A raw piece goes back into a raw bird, a roasted one into a roasted bird - never
	# across. Always equal for a finished portion of a finished whole (a slice, a loaf).
	return (
		item != null
		and can_absorb_type(item.item_type)
		and item.is_fully_prepped() == is_fully_prepped()
	)


## Type-only variant of can_absorb — whether a portion of `type` could be
## merged in, without an actual item existing yet to check. Lets a Crate (or
## a carried dispenser peeling straight onto a container, see SlotStation)
## decide the destination before spawning anything.
func can_absorb_type(type: String) -> bool:
	return (
		is_dispenser()
		and _ready_to_dispense()
		and type == dispensed_portion_type()
		and uses_left < Ingredients.uses_for(item_type)
	)


## Merge `item` back in. For an ingredient dispenser the portion is consumed
## outright — it becomes part of the whole again, not a stored object.
func absorb(item: Item) -> void:
	item.queue_free()
	uses_left = mini(uses_left + 1, Ingredients.uses_for(item_type))


## What type of portion this dispenser hands out — a separate virtual (not
## just inlining Ingredients.dispenses_for(item_type) at every call site)
## because Crate needs to answer this from its own contained_type instead:
## a Crate deliberately carries no item_type of its own (so Plate.can_add
## can exclude it without special-casing), so Ingredients.dispenses_for
## would only ever see "" for one. This is what lets SlotStation ask any
## dispenser — a Crate, a baked loaf, a chopped head — "what do you hand
## out" generically, without per-type knowledge (e.g. to swipe straight onto
## a carried Tray, see SlotStation.interact()).
func dispensed_portion_type() -> String:
	return Ingredients.dispenses_for(item_type)


## Peel one portion off, returning it. `host` is a scratch parent so a
## freshly spawned portion's _ready fires; the caller reparents it right
## after (to a hand, a slot). The portion is a genuinely separate item with
## its own fresh state. A finished portion (a slice) carries the whole's
## earned quality; a portion with prep of its own (a chicken piece) instead
## carries whichever of its steps the whole has already done, with the
## whole's scores - a piece off a roasted bird is roasted, off a raw one raw.
## The last portion may leave a remainder behind (a picked-clean chicken is
## bones), in which case this item turns into it right here.
func dispense(host: Node) -> Item:
	var ptype := dispensed_portion_type()
	var portion: Item = Ingredients.scene_for(ptype).instantiate()
	portion.item_type = ptype
	host.add_child(portion)
	if Ingredients.steps_for(ptype).is_empty():
		portion.inherited_quality = quality_value()
	else:
		for verb in Ingredients.steps_for(ptype):
			if step_done(verb):
				portion.complete_step(_prep_scores[verb])
				continue
			# A step in progress but not yet scored (a bird still roasting): the
			# piece is exactly as far along as the whole, and keeps going from there.
			if verb == Ingredients.Verb.COOK:
				portion.doneness = doneness
			elif verb == Ingredients.Verb.CHOP:
				portion.chop_progress = chop_progress
			portion._update_visual_state()
			portion._update_tint()
			break
	uses_left -= 1
	var remainder := Ingredients.remainder_for(item_type)
	if uses_left == 0 and remainder != "":
		transform_into(remainder)
	return portion


## Whether running out consumes this item. A loaf peeled to its last slice
## is gone; an emptied container (Tray) persists to be refilled. A dispenser
## with a remainder never reaches this - it has already become something else.
func frees_when_empty() -> bool:
	return true


## True once a dispenser has been used up and should be discarded by whoever
## holds it. False for anything that was never a dispenser (a remainder, a
## plain item), still has portions, or persists when empty (a Tray, a Crate).
func spent() -> bool:
	return is_dispenser() and not can_dispense() and frees_when_empty()


# --- scoring ---

## 0..1 contribution to a dish. A peeled portion returns the quality it
## inherited from its whole; otherwise it's low if under-prepped (steps left
## undone), else the average of the skill scores earned across its prep steps.
## Seasoning always adds on top, capped at 1.0 — it only ever helps.
func quality_value() -> float:
	var base: float
	if inherited_quality >= 0.0:
		base = inherited_quality
	elif not is_fully_prepped():
		base = 0.3
	elif _prep_scores.is_empty():
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


## Assign the food material to every MeshInstance3D in `root`'s subtree (the
## node itself if it's one, plus any children), so multi-mesh representations
## tint uniformly.
func _tint_tree(root: Node) -> void:
	if root is MeshInstance3D:
		(root as MeshInstance3D).material_override = _mat
	for child in root.get_children():
		_tint_tree(child)


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
## chop()/cook().
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
	# stove. A STOVE-transform input (a bread slice) instead shades from its own
	# base toward the output's color as it cooks - a fresh cook on its own
	# clock, base-colored at rest. Everything else shows its base color.
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
	elif Ingredients.stove_output_for(item_type) != "" and doneness > 0.0:
		var target := Ingredients.color_for(Ingredients.stove_output_for(item_type))
		var shade: Color
		if doneness <= 1.0:
			shade = color.lerp(target, clampf(doneness, 0.0, 1.0))
		else:
			var char_t := clampf((doneness - 1.0) / (BURNT_CAP - 1.0), 0.0, 1.0)
			shade = target.lerp(Color(0.08, 0.07, 0.06), char_t)
		_mat.albedo_color = shade
	else:
		_mat.albedo_color = color


func attach_to(new_parent: Node3D) -> void:
	if get_parent() != null:
		get_parent().remove_child(self)
	new_parent.add_child(self)
	position = Vector3.ZERO
	rotation = Vector3.ZERO
