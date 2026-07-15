class_name Plate
extends Item

## A carryable plate that holds components. It flows through the normal carry
## / slot machinery (it's an Item) but is never cookable. Components added to
## it are reparented onto the plate at fixed mount points. Which recipe it's
## scored against is decided by whoever evaluates it (the ServeStation, based
## on the current order) — the plate itself doesn't know or care what dish
## it's supposed to be.

const _MOUNTS := [
	Vector3(-0.10, 0.05, 0.02),
	Vector3(0.10, 0.05, -0.02),
	Vector3(0.0, 0.05, 0.12),
	Vector3(0.0, 0.05, -0.12),
]

var components: Array[Item] = []


## Only real ingredients (item_type != "") count as platable components —
## this naturally excludes both another Plate and a Spice shaker, which is
## what stops a carried shaker from getting glued onto a plate as clutter
## instead of falling through to the seasoning branch in SlotStation.
func can_add(item: Item) -> bool:
	return item.item_type != "" and components.size() < _MOUNTS.size()


func add_component(item: Item) -> void:
	var idx := components.size()
	item.attach_to(self)
	item.position = _MOUNTS[idx]
	item.scale = Vector3.ONE * 0.7
	components.append(item)


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
## missing or wrong items lower the score, they never hard-fail.
func evaluate(required: Array) -> Dictionary:
	var seen := {}
	var sum := 0.0
	var matched := 0
	var wrong := 0
	for c in components:
		if c.item_type in required and not seen.has(c.item_type):
			seen[c.item_type] = true
			sum += c.quality_value()
			matched += 1
		else:
			wrong += 1

	var comp_avg := sum / matched if matched > 0 else 0.0
	var completeness := float(seen.size()) / required.size()
	var quality := comp_avg * completeness
	if wrong == 0 and completeness >= 1.0:
		quality = minf(1.0, quality + 0.05)
	else:
		quality = maxf(0.0, quality - 0.1 * wrong)
	quality = clampf(quality, 0.0, 1.0)

	return {
		"band": _band_for(quality),
		"quality": quality,
		"value": int(round(quality * 15.0)),
	}


func get_inspect_text() -> String:
	if components.is_empty():
		return "PLATE (empty)"
	var lines := ["PLATE"]
	for c in components:
		lines.append("- %s: %d%%" % [c.item_type.capitalize(), int(round(c.quality_value() * 100))])
	return "\n".join(lines)


func _band_for(quality: float) -> String:
	if quality >= 0.85:
		return "perfect"
	elif quality >= 0.62:
		return "good"
	return "poor"
