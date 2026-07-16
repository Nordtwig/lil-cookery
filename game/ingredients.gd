class_name Ingredients

## Central definition of ingredients and their prep chains. Each ingredient
## is an ordered list of prep steps (verbs); a station performs a step only
## if it matches the item's *next* unfinished step. Kept as plain data here so
## adding an ingredient or dish is a one-line edit; can move to Resources later.

enum Verb { CHOP, COOK }

## Each ingredient names its own scene, so its whole/prepped meshes can differ
## (a bread loaf slices, a tomato dices, a meat patty never chops). Loaded on
## demand by whoever spawns an ingredient (Crate); load() caches after the
## first call. Keeps DEFS the single place an ingredient is defined — add an
## entry here plus its scene file. Unknown types fall back to the generic item.
const _FALLBACK_SCENE := "res://items/item.tscn"

const DEFS := {
	"tomato": {
		"color": Color(0.86, 0.19, 0.14),
		"steps": [Verb.CHOP],  # eaten raw — diced, never cooked
		"scene": "res://items/tomato.tscn",
	},
	"cheese": {
		"color": Color(0.96, 0.78, 0.30),
		"steps": [Verb.CHOP],  # "chop" == slice; no cooking
		"scene": "res://items/cheese.tscn",
	},
	"bread": {
		"color": Color(0.82, 0.62, 0.36),  # toasts pale tan -> golden -> charred
		"steps": [Verb.CHOP, Verb.COOK],  # sliced, then toasted
		"scene": "res://items/bread.tscn",
	},
	"meat": {
		"color": Color(0.72, 0.34, 0.33),  # raw pink -> seared brown -> charred
		"steps": [Verb.COOK],  # a pre-formed patty; only needs the stove
		"scene": "res://items/meat.tscn",
	},
	"lettuce": {
		"color": Color(0.48, 0.72, 0.32),
		"steps": [Verb.CHOP],
		"scene": "res://items/lettuce.tscn",
	},
}


static func steps_for(type: String) -> Array:
	return DEFS.get(type, {}).get("steps", [])


static func color_for(type: String) -> Color:
	return DEFS.get(type, {}).get("color", Color.WHITE)


## The scene to instantiate for an ingredient of this type.
static func scene_for(type: String) -> PackedScene:
	return load(DEFS.get(type, {}).get("scene", _FALLBACK_SCENE))
