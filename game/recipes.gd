class_name Recipes

## Central list of servable dishes: each maps to its required component types
## (order-free, same forgiving scoring as before — missing/wrong components
## lower the score, never reject the plate). Adding a dish is a one-line edit,
## same pattern as Ingredients.

const DEFS := {
	"caprese": ["tomato", "cheese"],
	"bruschetta": ["bread", "tomato"],
}


static func required_for(dish: String) -> Array:
	return DEFS.get(dish, [])


static func random_name() -> String:
	return DEFS.keys().pick_random()
