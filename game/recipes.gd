class_name Recipes

## Central list of servable dishes: each maps to its required component types
## (order-free by default, same forgiving scoring as before — missing/wrong
## components lower the score, never reject the plate). A dish may also name
## a `base` component — one that should be plated before the others (the
## design doc's shallow "garnish needs base plated first" dependency). This
## is scored, not enforced: plating out of order never blocks anything, it
## just costs a small penalty, same forgiving shape as a wrong ingredient.
## `components` may repeat a type (a burger's two bread slices — bottom and
## top bun); evaluate() matches by count. `layout` drives how a tagged plate
## arranges its components visually, never scoring. Adding a dish is a
## one-line edit, same pattern as Ingredients.

const DEFS := {
	"caprese": {"components": ["tomato", "mozzarella"], "layout": "fan"},
	"bruschetta": {"components": ["toasted_bread", "tomato"], "layout": "stack"},
	"burger": {"components": ["bread", "meat", "lettuce", "bread"], "base": "bread", "layout": "stack"},
}


static func required_for(dish: String) -> Array:
	return DEFS.get(dish, {}).get("components", [])


static func base_for(dish: String) -> String:
	return DEFS.get(dish, {}).get("base", "")


## How a tagged plate arranges this dish's components. Display only — never
## read by scoring. "stack" (default, bottom-to-top) or "fan" (side-by-side).
static func layout_for(dish: String) -> String:
	return DEFS.get(dish, {}).get("layout", "stack")


static func random_name() -> String:
	return DEFS.keys().pick_random()


## The dish `item_types` exactly matches (same types, same counts, nothing
## extra or missing), or "" if none. Deliberately exact-only, not a "closest
## fit while still building" guess — an in-progress plate (e.g. just a slice
## of bread) is genuinely ambiguous between recipes that share a component
## (bread's in both burger and bruschetta), which is exactly the shape of
## fuzzy inference already rejected for plate layout (see Plate._relayout).
## Exact match sidesteps that: a partial plate matches nothing, so there's
## nothing ambiguous to report.
static func matching_dish(item_types: Array) -> String:
	for dish in DEFS.keys():
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
