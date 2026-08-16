class_name Equipment

## Non-ingredient orderable supplies — durable tools you'd normally never
## run out of unless you lose or destroy one (a spice shaker, say), priced
## at their own fixed cost rather than Ingredients' per-unit
## GameState.order_unit_cost. OrderDesk reads types() alongside
## Ingredients.stockable_types() for its row list; GameState._deliver_orders()
## reads is_equipment() to know a delivered type needs a loose BayStack
## landing (see BayStack.place_loose_item) instead of a crate. The one place
## to add a new orderable piece of equipment.
##
## Deliberately no "unpacking" step — an ordered shaker arrives as a real,
## ready shaker, not a crate you dispense one from.

const DEFS := {
	"spice_shaker": {
		"display_name": "Spice Shaker",
		"cost": 10,
		"scene": "res://items/spice.tscn",
	},
}


static func types() -> Array[String]:
	var out: Array[String] = []
	for type in DEFS:
		out.append(type)
	return out


static func is_equipment(type: String) -> bool:
	return DEFS.has(type)


static func display_name_for(type: String) -> String:
	return DEFS.get(type, {}).get("display_name", type.capitalize())


static func cost_for(type: String) -> int:
	return DEFS.get(type, {}).get("cost", 0)


static func scene_for(type: String) -> PackedScene:
	return load(DEFS.get(type, {}).get("scene", ""))
