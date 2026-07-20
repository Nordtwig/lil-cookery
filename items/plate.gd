class_name Plate
extends Item

## A carryable plate that holds components. It flows through the normal carry
## / slot machinery (it's an Item) but is never cookable. Components added to
## it are reparented onto the plate at fixed mount points. Which recipe it's
## scored against is always decided by whoever evaluates it (the Table it's
## delivered to, based on that table's live order) — an optional order tag (see
## tag_order below) is purely a player-facing display aid and never overrides that.

# Components arrange themselves by layout (see _relayout), not fixed mounts.
# A tagged plate uses its recipe's authored layout and re-sorts components
# into the dish's canonical order (so a burger built out of order still snaps
# into a proper stack); an untagged plate falls back to a plain stack in
# plating order.
const MAX_COMPONENTS := 6
const _STACK_BASE_Y := 0.09
const _STACK_DY := 0.05
const _FAN_SPACING := 0.13
const _FAN_Y := 0.09

var components: Array[Item] = []
var _tagged_dish := ""
var _tagged_table_number := 0  # 0 = untagged-to-a-table (e.g. a hand-tagged plate)

@onready var _checklist: Label3D = $Checklist
@onready var _checklist_bg: MeshInstance3D = $ChecklistBG


## Only real ingredients (item_type != "") count as platable components —
## this naturally excludes both another Plate and a Spice shaker, which is
## what stops a carried shaker from getting glued onto a plate as clutter
## instead of falling through to the seasoning branch in SlotStation. A
## dispenser (a whole loaf/head) is excluded too — you plate its peeled
## portions, never the batch itself.
func can_add(item: Item) -> bool:
	return item.item_type != "" and not item.is_dispenser() and components.size() < MAX_COMPONENTS


## True if an order tag is currently attached (see tag_order/clear_tag).
func is_tagged() -> bool:
	return _tagged_dish != ""


## The tagged dish/table, for reconstructing a physical OrderTicket when a tag
## is stripped back off (see SlotStation's untag path). "" / 0 if untagged.
func tagged_dish() -> String:
	return _tagged_dish


func tagged_table_number() -> int:
	return _tagged_table_number


## Overrides Item's chop/cook/season-based definition — a plate's own
## "nothing's happened to it yet" is just "no components on it". A tag is
## purely cosmetic and never costs anything, so a tagged-but-empty plate still
## counts as unmodified and can be returned to the PlateStack.
func is_unmodified() -> bool:
	return components.is_empty()


func add_component(item: Item) -> void:
	item.attach_to(self)
	item.scale = Vector3.ONE * 0.7
	components.append(item)
	_relayout()
	_update_checklist()


## Tag this plate with an order (from a carried OrderTicket). Purely a
## display aid — shows a live checklist of the dish's required components as
## they're added, but never affects scoring; evaluate() always scores
## against whatever's explicitly passed to it. `table_number` (e.g. 2) is an
## optional table this order came from, so a plate reads as belonging to it;
## kept as a raw number (not a pre-formatted "T2" string) so an untag can
## reconstruct a real OrderTicket from it.
func tag_order(dish: String, table_number: int = 0) -> void:
	_tagged_dish = dish
	_tagged_table_number = table_number
	_relayout()
	_update_checklist()


## Clears the order tag — either once a plate has been served (the live
## checklist was only useful while building the dish), or when a player
## deliberately strips it back off a plate sitting at a station (see
## SlotStation's untag path, which reads tagged_dish/tagged_table_number
## first to hand back a real ticket). Leaves the plated arrangement exactly
## as it was; only the checklist display goes away.
func clear_tag() -> void:
	_tagged_dish = ""
	_tagged_table_number = 0
	_checklist.visible = false
	_checklist_bg.visible = false


## Re-position every component for the current layout. Tagged: the recipe's
## authored layout (stack/fan), with components re-sorted into the dish's
## canonical order so out-of-order plating still presents correctly. Untagged:
## a plain stack in plating order. Components slide to their targets rather
## than snapping, so a late tag visibly re-arranges the plate.
func _relayout() -> void:
	var ordered := _arranged_components()
	var style := Recipes.layout_for(_tagged_dish) if _tagged_dish != "" else "stack"
	var n := ordered.size()
	if style == "fan":
		for i in n:
			var offset := i - (n - 1) / 2.0
			_move_component(ordered[i], Vector3(offset * _FAN_SPACING, _FAN_Y, 0.0), offset * 0.2)
	else:
		for i in n:
			_move_component(ordered[i], Vector3(0.0, _STACK_BASE_Y + i * _STACK_DY, 0.0), 0.0)


## Components in presentation order. Untagged: plating order as-is. Tagged: the
## dish's canonical component order (each canonical slot consumes one matching
## component by type), with any extra/wrong components appended last so they
## sit on top rather than disturbing the recognizable stack.
func _arranged_components() -> Array:
	if _tagged_dish == "":
		return components.duplicate()
	var pool := components.duplicate()
	var arranged := []
	for type in Recipes.required_for(_tagged_dish):
		for i in pool.size():
			if pool[i].item_type == type:
				arranged.append(pool[i])
				pool.remove_at(i)
				break
	for leftover in pool:
		arranged.append(leftover)
	return arranged


func _move_component(item: Item, target_pos: Vector3, target_rot_y: float) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(item, "position", target_pos, 0.18).set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "rotation:y", target_rot_y, 0.18)


func _update_checklist() -> void:
	if _tagged_dish == "":
		_checklist.visible = false
		_checklist_bg.visible = false
		return
	var have := {}
	for c in components:
		have[c.item_type] = have.get(c.item_type, 0) + 1
	var need := {}
	for type in Recipes.required_for(_tagged_dish):
		need[type] = need.get(type, 0) + 1
	var header := _tagged_dish.to_upper()
	if _tagged_table_number > 0:
		header = "T%d · %s" % [_tagged_table_number, header]
	var lines := [header]
	var listed := {}
	for type in Recipes.required_for(_tagged_dish):
		if listed.has(type):
			continue
		listed[type] = true
		var h: int = have.get(type, 0)
		var n: int = need[type]
		var mark := "[ ]"
		if h >= n:
			mark = "[x]"
		elif h > 0:
			mark = "[/]"  # partially there (e.g. one of a burger's two buns)
		var label: String = type.capitalize()
		if n > 1:
			label += " (%d/%d)" % [h, n]
		lines.append("%s %s" % [mark, label])
	_checklist.text = "\n".join(lines)
	_checklist.visible = true
	_checklist_bg.visible = true


## Season the first not-yet-seasoned component on the plate. Returns true if
## one was found and seasoned (so the caller only spends a shaker charge on
## a real hit, never on an empty or fully-seasoned plate).
func season_component(bonus: float, spice_color: Color) -> bool:
	for c in components:
		if c.can_be_seasoned():
			c.season(bonus, spice_color)
			return true
	return false


## Score the plated dish against `required` (the current order's component
## types, from Recipes). Component-quality average over the required items
## that are present, scaled by completeness, plus a small clean-plate bonus
## (no wrong/extra components) or a mild penalty for clutter. Forgiving:
## missing or wrong items lower the score, they never hard-fail. `base_type`
## is an optional component that should have been plated before the others
## (e.g. a burger's bun) — plating out of order costs a small penalty, same
## forgiving shape as a wrong ingredient, never a hard block.
func evaluate(required: Array, base_type: String = "") -> Dictionary:
	# Count-based matching so a legitimately-repeated required component (a
	# burger's two bread slices) is accepted up to the count the recipe asks
	# for; a third bread would still count as clutter.
	var needed := {}
	for r in required:
		needed[r] = needed.get(r, 0) + 1
	var sum := 0.0
	var matched := 0
	var wrong := 0
	var base_index := -1
	var first_required_index := -1
	for i in components.size():
		var c := components[i]
		if needed.get(c.item_type, 0) > 0:
			needed[c.item_type] -= 1
			sum += c.quality_value()
			matched += 1
			if first_required_index == -1:
				first_required_index = i
			if c.item_type == base_type and base_index == -1:
				base_index = i
		else:
			wrong += 1

	var comp_avg := sum / matched if matched > 0 else 0.0
	var completeness := float(matched) / required.size()
	var quality := comp_avg * completeness
	if wrong == 0 and completeness >= 1.0:
		quality = minf(1.0, quality + 0.05)
	else:
		quality = maxf(0.0, quality - 0.1 * wrong)

	if base_type != "" and base_index != -1 and base_index != first_required_index:
		quality = maxf(0.0, quality - 0.1)

	quality = clampf(quality, 0.0, 1.0)

	return {
		"band": _band_for(quality),
		"quality": quality,
		"value": int(round(quality * 15.0)),
	}


func get_inspect_text() -> String:
	var header := "PLATE"
	if _tagged_dish != "":
		header += " - "
		if _tagged_table_number > 0:
			header += "T%d · " % _tagged_table_number
		header += _tagged_dish.to_upper()
	if components.is_empty():
		return header + " (empty)"
	var lines := [header]
	for c in components:
		lines.append("- %s: %d%%" % [c.item_type.capitalize(), int(round(c.quality_value() * 100))])
	return "\n".join(lines)


func _band_for(quality: float) -> String:
	if quality >= 0.85:
		return "perfect"
	elif quality >= 0.62:
		return "good"
	return "poor"
