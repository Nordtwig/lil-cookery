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

# A few ingredients are dispensers: a whole item (a loaf, a head) you prep once
# — its own quality/doneness/chop state, on its own model — and then peel usable
# portions off of. Baking a loaf, or chopping a head, unlocks it; each peel spawns
# a distinct portion item (`dispenses`) that inherits the whole's earned quality.
# The loaf/head is never itself plated; only its portions are. This keeps every
# item's state honest to a single physical object — no shared mesh or doneness
# doing double duty for both a batch and its pieces.
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
	"bread_loaf": {
		"color": Color(0.82, 0.62, 0.36),  # bakes pale tan -> golden -> charred
		"steps": [Verb.COOK],  # baked whole on the stove — no chopping
		"scene": "res://items/bread_loaf.tscn",
		"dispenses": "bread",  # a baked loaf peels into slices
		"uses": 4,
	},
	"bread": {
		"color": Color(0.82, 0.62, 0.36),  # a baked slice; ready to plate as-is
		"steps": [],  # finished portion — its quality is inherited from the loaf
		"scene": "res://items/bread.tscn",
		"toasts_into": "toasted_bread",  # a cook pass toasts a slice, for bruschetta
	},
	"toasted_bread": {
		"color": Color(0.62, 0.40, 0.20),  # a deeper golden-brown than plain baked bread
		"steps": [],  # never dispensed fresh — only reached via transform_into
		"scene": "res://items/bread.tscn",  # same slice geometry, only the tint differs
	},
	"meat": {
		"color": Color(0.72, 0.34, 0.33),  # raw pink -> seared brown -> charred
		"steps": [Verb.COOK],  # a pre-formed patty; only needs the stove
		"scene": "res://items/meat.tscn",
	},
	"lettuce_head": {
		"color": Color(0.48, 0.72, 0.32),
		"steps": [Verb.CHOP],  # chopped whole on a board — no cooking
		"scene": "res://items/lettuce_head.tscn",
		"dispenses": "lettuce",  # a chopped head peels into scraps
		"uses": 4,
	},
	"lettuce": {
		"color": Color(0.48, 0.72, 0.32),
		"steps": [],  # finished portion — quality inherited from the head
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


## The portion type this ingredient dispenses once prepped (a baked loaf peels
## `bread` slices, a chopped head peels `lettuce` scraps), or "" if it's a
## plain single item that's plated directly. See Item.can_dispense.
static func dispenses_for(type: String) -> String:
	return DEFS.get(type, {}).get("dispenses", "")


## How many portions a dispenser ingredient yields before it's used up.
static func uses_for(type: String) -> int:
	return DEFS.get(type, {}).get("uses", 0)


## The ingredient type a *second* cook pass transforms this one into (e.g.
## plain baked bread -> toasted_bread), or "" if re-cooking this type never
## changes what it is — just its score, as usual. See CookStation and
## Item.transform_into.
static func toasts_into(type: String) -> String:
	return DEFS.get(type, {}).get("toasts_into", "")
