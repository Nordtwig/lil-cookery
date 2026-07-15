class_name Spice
extends Item

## A limited-use seasoning tool: never chopped, never cooked, never plated as
## a dish component. Carry it to a station holding a food item and interact
## there to season that item (SlotStation.interact routes to Item.season()
## when the carried item is a Spice with charges left). A shaker is always
## spawned and configured by a SpiceRack (spice_type/color/bonus/uses set at
## spawn time), so there's no baked per-flavor scene — bring it back to its
## rack to refill once it runs dry.

@export var spice_type := "pepper"
@export var bonus := 0.15
@export var max_uses := 4
@export var uses_remaining := 4

func can_use() -> bool:
	return uses_remaining > 0


func consume_use() -> void:
	uses_remaining = maxi(0, uses_remaining - 1)


func add_uses(n: int) -> void:
	uses_remaining = mini(max_uses, uses_remaining + n)


func get_inspect_text() -> String:
	return "%s SHAKER\n%d/%d uses  (+%d%% quality)" % [
		spice_type.to_upper(), uses_remaining, max_uses, int(round(bonus * 100))
	]
