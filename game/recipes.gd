class_name Recipes

## Central list of servable dishes: each maps to its required component types
## (order-free by default, same forgiving scoring as before — missing/wrong
## components lower the score, never reject the plate). A dish may also name
## a `base` component — one that should be plated before the others (the
## design doc's shallow "garnish needs base plated first" dependency). This
## is scored, not enforced: plating out of order never blocks anything, it
## just costs a small penalty, same forgiving shape as a wrong ingredient.
## Adding a dish is a one-line edit, same pattern as Ingredients.

const DEFS := {
	"caprese": {"components": ["tomato", "cheese"]},
	"bruschetta": {"components": ["bread", "tomato"]},
	"burger": {"components": ["bread", "meat", "lettuce"], "base": "bread"},
}


static func required_for(dish: String) -> Array:
	return DEFS.get(dish, {}).get("components", [])


static func base_for(dish: String) -> String:
	return DEFS.get(dish, {}).get("base", "")


static func random_name() -> String:
	return DEFS.keys().pick_random()
