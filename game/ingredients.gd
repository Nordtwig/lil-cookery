class_name Ingredients

## Central definition of ingredients and their prep chains. Each ingredient
## is an ordered list of prep steps (verbs); a station performs a step only
## if it matches the item's *next* unfinished step. Kept as plain data here so
## adding an ingredient or dish is a one-line edit; can move to Resources later.

enum Verb { CHOP, COOK }

const DEFS := {
	"tomato": {
		"color": Color(0.85, 0.20, 0.15),
		"steps": [Verb.CHOP],  # eaten raw — diced, never cooked
	},
	"cheese": {
		"color": Color(0.95, 0.80, 0.25),
		"steps": [Verb.CHOP],  # "chop" == slice; no cooking
	},
	"bread": {
		"color": Color(0.85, 0.65, 0.35),  # toasts pale tan -> golden -> charred
		"steps": [Verb.CHOP, Verb.COOK],  # sliced, then toasted
	},
	"meat": {
		"color": Color(0.65, 0.30, 0.28),  # raw pink -> seared brown -> charred
		"steps": [Verb.COOK],  # a pre-formed patty; only needs the stove
	},
	"lettuce": {
		"color": Color(0.45, 0.70, 0.30),
		"steps": [Verb.CHOP],
	},
}


static func steps_for(type: String) -> Array:
	return DEFS.get(type, {}).get("steps", [])


static func color_for(type: String) -> Color:
	return DEFS.get(type, {}).get("color", Color.WHITE)
