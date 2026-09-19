class_name Recipes

## Index of every Dish under res://data/dishes/, keyed by file name. Scoring stays
## forgiving - missing or wrong components lower the score, never reject the plate.
## Validated once on load: every component must be a real ingredient type.

const DIR := "res://data/dishes"
const _DUPLICATE_CHANCE := 0.35

static var _defs: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_defs = DataDir.load_all(DIR, Dish)
	for problem in validate(_defs):
		push_error("Recipes: " + problem)


## Every problem in a {name: Dish} set, as messages. Empty means valid.
static func validate(defs: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	for dish in defs:
		var def: Dish = defs[dish]
		if def.components.is_empty():
			problems.append("%s has no components" % dish)
		for component in def.components:
			if not Ingredients.has(component):
				problems.append("%s uses unknown ingredient '%s'" % [dish, component])
		if def.base != "" and def.base not in def.components:
			problems.append("%s's base '%s' is not one of its components" % [dish, def.base])
	return problems


static func _def(dish: String) -> Dish:
	_load()
	return _defs.get(dish)


static func names() -> Array[String]:
	_load()
	var out: Array[String] = []
	out.assign(_defs.keys())
	return out


static func required_for(dish: String) -> Array:
	var def := _def(dish)
	return def.components if def != null else []


static func base_for(dish: String) -> String:
	var def := _def(dish)
	return def.base if def != null else ""


## "stack" (bottom-to-top) or "fan" (side-by-side). Display only.
static func layout_for(dish: String) -> String:
	var def := _def(dish)
	return def.layout if def != null else "stack"


static func random_name() -> String:
	return names().pick_random()


## What a seated party of `size` orders - a slight weight toward repeating a dish
## already in the order. The one seam a demand forecast reads from, so it stays a
## single function rather than scattered random_name() calls.
static func random_party_order(size: int) -> Array[String]:
	var dishes: Array[String] = []
	for i in size:
		if i > 0 and randf() < _DUPLICATE_CHANCE:
			dishes.append(dishes[randi() % dishes.size()])
		else:
			dishes.append(random_name())
	return dishes


## The dish `item_types` exactly matches (same types, same counts), or "". Exact only:
## a partial plate is ambiguous between dishes sharing a component, so it matches none.
static func matching_dish(item_types: Array) -> String:
	for dish in names():
		if _same_multiset(item_types, required_for(dish)):
			return dish
	return ""


static func _same_multiset(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var counts := {}
	for x in a:
		counts[x] = counts.get(x, 0) + 1
	for y in b:
		counts[y] = counts.get(y, 0) - 1
	for v in counts.values():
		if v != 0:
			return false
	return true
