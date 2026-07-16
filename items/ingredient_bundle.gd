class_name IngredientBundle
extends Item

## A portable batch of leftover pieces from a yield ingredient's split (see
## SlotStation._split_if_yield) — e.g. the 3 leftover lettuce scraps after
## the first is handed over at a cutting board, or the leftover bread slices
## after baking a loaf on a stove. A normal carryable Item otherwise — no
## item_type of its own (matching Plate/Spice), so it's never itself a
## platable component and can't be seasoned. Set it down on any station and
## pick it back up as a whole batch, peel one piece at a time, or merge a
## carried matching piece back in — all of that lives on every SlotStation
## (see _peel_one/_take_whole_bundle/_merge_one there), not just wherever the
## bundle was created.
##
## Visually this borrows the contained ingredient's own *whole, uncut* look
## (a real instance of its scene, left in its default un-chopped state) —
## it's still recognizably "the loaf" / "the head", just missing however
## many pieces have been taken out of it, not a stray pile shaped like a
## single portion.

@export var contained_type := ""
@export var count := 0
## The whole batch was prepped together, so every piece peeled off replays
## this same recorded quality/tint rather than being scored individually.
var piece_doneness := 0.0
var piece_score := 0.0


func _ready() -> void:
	super._ready()
	_mesh.visible = false  # replaced by the borrowed visual below
	if contained_type == "":
		return
	var visual: Item = Ingredients.scene_for(contained_type).instantiate()
	visual.item_type = contained_type
	add_child(visual)
	visual.doneness = piece_doneness  # tint matches how well the batch turned out
	visual.refresh_visual()


func get_inspect_text() -> String:
	return "%s ×%d" % [contained_type.capitalize(), count]
