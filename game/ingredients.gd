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
		"color": Color(0.82, 0.62, 0.36),  # bakes pale tan -> golden -> charred
		"steps": [Verb.COOK],  # baked whole on the stove — no chopping at all
		"scene": "res://items/bread.tscn",
		"yield": 4,  # one loaf bakes into 4 usable slices
		"toasts_into": "toasted_bread",  # a second cook pass toasts a slice, for bruschetta
	},
	"toasted_bread": {
		"color": Color(0.62, 0.40, 0.20),  # a deeper golden-brown than plain baked bread
		"steps": [Verb.COOK],  # never dispensed fresh — only reached via transform_into
		"scene": "res://items/bread.tscn",  # same slice geometry, only the tint differs
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
		"yield": 4,  # one head chops into 4 scraps
	},
}


static func steps_for(type: String) -> Array:
	return DEFS.get(type, {}).get("steps", [])


static func color_for(type: String) -> Color:
	return DEFS.get(type, {}).get("color", Color.WHITE)


## The scene to instantiate for an ingredient of this type.
static func scene_for(type: String) -> PackedScene:
	return load(DEFS.get(type, {}).get("scene", _FALLBACK_SCENE))


## How many usable pieces one whole ingredient's relevant step (whichever
## verb splits it — see YieldStation) yields. Most ingredients are 1 (prep
## just refines the single item in place); a few (bread, lettuce) split into
## several independent pieces.
static func yield_for(type: String) -> int:
	return DEFS.get(type, {}).get("yield", 1)


## The ingredient type a *second* cook pass transforms this one into (e.g.
## plain baked bread -> toasted_bread), or "" if re-cooking this type never
## changes what it is — just its score, as usual. See CookStation and
## Item.transform_into.
static func toasts_into(type: String) -> String:
	return DEFS.get(type, {}).get("toasts_into", "")
