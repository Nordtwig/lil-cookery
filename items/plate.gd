class_name Plate
extends Item

## A carryable plate that holds components. It flows through the normal carry
## / slot machinery (it's an Item) but is never cookable. Components added to
## it are reparented onto the plate at fixed mount points.

## The single hardcoded recipe for the first slice: a caprese needs a tomato
## and a cheese, any order. Real data-driven recipes come later.
const REQUIRED := ["tomato", "cheese"]

const _MOUNTS := [
	Vector3(-0.10, 0.05, 0.02),
	Vector3(0.10, 0.05, -0.02),
	Vector3(0.0, 0.05, 0.12),
	Vector3(0.0, 0.05, -0.12),
]

var components: Array[Item] = []


func can_add(item: Item) -> bool:
	return not (item is Plate) and components.size() < _MOUNTS.size()


func add_component(item: Item) -> void:
	var idx := components.size()
	item.attach_to(self)
	item.position = _MOUNTS[idx]
	item.scale = Vector3.ONE * 0.7
	components.append(item)


## Score the plated dish. Component-quality average over the required items
## that are present, scaled by completeness, plus a small clean-plate bonus
## (no wrong/extra components) or a mild penalty for clutter. Forgiving:
## missing or wrong items lower the score, they never hard-fail.
func evaluate() -> Dictionary:
	var seen := {}
	var sum := 0.0
	var matched := 0
	var wrong := 0
	for c in components:
		if c.item_type in REQUIRED and not seen.has(c.item_type):
			seen[c.item_type] = true
			sum += c.quality_value()
			matched += 1
		else:
			wrong += 1

	var comp_avg := sum / matched if matched > 0 else 0.0
	var completeness := float(seen.size()) / REQUIRED.size()
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


func _band_for(quality: float) -> String:
	if quality >= 0.85:
		return "perfect"
	elif quality >= 0.62:
		return "good"
	return "poor"
