class_name Plate
extends Item

## A carryable plate that holds components. It flows through the normal carry
## / slot machinery (it's an Item) but is never cookable. Components added to
## it are reparented onto the plate at fixed mount points. Which recipe it's
## scored against is always decided by whoever evaluates it (the ServeStation,
## based on the current order) — an optional order tag (see tag_order below)
## is purely a player-facing display aid and never overrides that.

const _MOUNTS := [
	Vector3(-0.10, 0.05, 0.02),
	Vector3(0.10, 0.05, -0.02),
	Vector3(0.0, 0.05, 0.12),
	Vector3(0.0, 0.05, -0.12),
]

var components: Array[Item] = []
var _tagged_dish := ""

@onready var _checklist: Label3D = $Checklist
@onready var _checklist_bg: MeshInstance3D = $ChecklistBG


## Only real ingredients (item_type != "") count as platable components —
## this naturally excludes both another Plate and a Spice shaker, which is
## what stops a carried shaker from getting glued onto a plate as clutter
## instead of falling through to the seasoning branch in SlotStation.
func can_add(item: Item) -> bool:
	return item.item_type != "" and components.size() < _MOUNTS.size()


## Overrides Item's chop/cook/season-based definition — a plate's own
## "nothing's happened to it yet" is just "no components on it". A tag is
## purely cosmetic and never costs anything, so a tagged-but-empty plate still
## counts as unmodified and can be returned to the PlateStack.
func is_unmodified() -> bool:
	return components.is_empty()


func add_component(item: Item) -> void:
	var idx := components.size()
	item.attach_to(self)
	item.position = _MOUNTS[idx]
	item.scale = Vector3.ONE * 0.7
	components.append(item)
	_update_checklist()


## Tag this plate with an order (from a carried OrderTicket). Purely a
## display aid — shows a live checklist of the dish's required components as
## they're added, but never affects scoring; evaluate() always scores
## against whatever's explicitly passed to it.
func tag_order(dish: String) -> void:
	_tagged_dish = dish
	_update_checklist()


func _update_checklist() -> void:
	if _tagged_dish == "":
		_checklist.visible = false
		_checklist_bg.visible = false
		return
	var have := {}
	for c in components:
		have[c.item_type] = true
	var lines := [_tagged_dish.to_upper()]
	for type in Recipes.required_for(_tagged_dish):
		var mark := "[x]" if have.has(type) else "[ ]"
		lines.append("%s %s" % [mark, type.capitalize()])
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
	var seen := {}
	var sum := 0.0
	var matched := 0
	var wrong := 0
	var base_index := -1
	var first_required_index := -1
	for i in components.size():
		var c := components[i]
		if c.item_type in required and not seen.has(c.item_type):
			seen[c.item_type] = true
			sum += c.quality_value()
			matched += 1
			if first_required_index == -1:
				first_required_index = i
			if c.item_type == base_type:
				base_index = i
		else:
			wrong += 1

	var comp_avg := sum / matched if matched > 0 else 0.0
	var completeness := float(seen.size()) / required.size()
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
		header += " — %s" % _tagged_dish.to_upper()
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
