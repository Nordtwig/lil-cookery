class_name Ingredients

## Index of every Ingredient under res://data/ingredients/, keyed by file name. Loaded
## on first use and validated once: every type a def names must exist, and derivation
## (a loaf dispensing slices, a slice toasting into another type) must not loop. A bad
## data edit fails loudly here instead of somewhere downstream.

enum Verb { CHOP, COOK }

const DIR := "res://data/ingredients"
const _FALLBACK_SCENE := "res://items/item.tscn"

static var _defs: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_defs = DataDir.load_all(DIR, Ingredient)
	for problem in validate(_defs):
		push_error("Ingredients: " + problem)


## Every problem in a {type: Ingredient} set, as messages. Empty means valid.
static func validate(defs: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var edges := {}
	for type in defs:
		edges[type] = []
	for type in defs:
		var def: Ingredient = defs[type]
		if def.scene == null:
			problems.append("%s has no scene" % type)
		if def.remainder != "" and def.dispenses == "":
			problems.append("%s has a remainder but dispenses nothing" % type)
		if def.dispenses_raw and def.dispenses == "":
			problems.append("%s dispenses raw but dispenses nothing" % type)
		for field in ["dispenses", "toasts_into", "remainder"]:
			var target: String = def.get(field)
			if target == "":
				continue
			if target not in defs:
				problems.append("%s.%s names unknown type '%s'" % [type, field, target])
			edges[type].append(target)
		if def.dispenses != "" and def.uses <= 0:
			problems.append("%s dispenses but has no uses" % type)
		if not def.made_from.is_empty():
			if def.yields <= 0:
				problems.append("%s is made in a pot but yields nothing" % type)
			for input in def.made_from:
				if input not in defs:
					problems.append("%s.made_from names unknown type '%s'" % [type, input])
				else:
					edges[input].append(type)
	for type in DataDir.find_cycles(edges):
		problems.append("%s derives from itself" % type)
	return problems


static func _def(type: String) -> Ingredient:
	_load()
	return _defs.get(type)


static func has(type: String) -> bool:
	return _def(type) != null


static func types() -> Array[String]:
	_load()
	var out: Array[String] = []
	out.assign(_defs.keys())
	return out


static func steps_for(type: String) -> Array:
	var def := _def(type)
	return def.steps if def != null else []


## Types a Crate can be stocked with: anything with a prep chain of its own that no
## other type produces. A slice, a toasted slice, a chicken piece, bones - all reached
## only through another ingredient, never ordered.
static func stockable_types() -> Array[String]:
	var out: Array[String] = []
	for type in types():
		if not steps_for(type).is_empty() and type not in derived_types():
			out.append(type)
	return out


## Every type some other type turns into, hands out, or is cooked into.
static func derived_types() -> Array[String]:
	_load()
	var out: Array[String] = []
	for type in _defs:
		var def: Ingredient = _defs[type]
		for target in [def.dispenses, def.toasts_into, def.remainder]:
			if target != "" and target not in out:
				out.append(target)
		if not def.made_from.is_empty() and type not in out:
			out.append(type)
	return out


## Types made in a pot.
static func combined_types() -> Array[String]:
	_load()
	var out: Array[String] = []
	for type in _defs:
		if not (_defs[type] as Ingredient).made_from.is_empty():
			out.append(type)
	return out


static func made_from_for(type: String) -> Array[String]:
	var def := _def(type)
	return def.made_from if def != null else []


static func yields_for(type: String) -> int:
	var def := _def(type)
	return def.yields if def != null else 0


## Seconds to cook this type to the top of Perfect, or 0 for the stove's default.
static func cook_time_for(type: String) -> float:
	var def := _def(type)
	return def.cook_time if def != null else 0.0


static func color_for(type: String) -> Color:
	var def := _def(type)
	return def.color if def != null else Color.WHITE


static func scene_for(type: String) -> PackedScene:
	var def := _def(type)
	if def != null and def.scene != null:
		return def.scene
	return load(_FALLBACK_SCENE)


## The portion type this ingredient peels once prepped, or "" for a plain item.
static func dispenses_for(type: String) -> String:
	var def := _def(type)
	return def.dispenses if def != null else ""


static func uses_for(type: String) -> int:
	var def := _def(type)
	return def.uses if def != null else 0


## The type a second cook pass turns this one into, or "" if re-cooking only rescores.
static func toasts_into(type: String) -> String:
	var def := _def(type)
	return def.toasts_into if def != null else ""


## Whether this dispenser can be picked before its own prep step is done.
static func dispenses_raw(type: String) -> bool:
	var def := _def(type)
	return def.dispenses_raw if def != null else false


## What this dispenser turns into once picked clean, or "" if it is simply gone.
static func remainder_for(type: String) -> String:
	var def := _def(type)
	return def.remainder if def != null else ""
