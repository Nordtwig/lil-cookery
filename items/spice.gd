class_name Spice
extends Item

## An infinite-use seasoning tool: never chopped, never cooked, never plated
## as a dish component. Carry it to a station holding a food item and
## interact there to season that item.
##
## No longer limited-use / no longer dispensed by a SpiceRack (both deleted
## 2026-08-14) — the finite-charge-pool economy this fed was left over from
## before Crate.max_stock was removed; once the finite-ingredients pressure
## moved entirely into money, a per-charge shaker was pure Overcooked-style
## friction with no remaining purpose. Lose the shaker (bin it, misplace it)
## and it's orderable again at OrderDesk like any other supply — see
## Equipment.

@export var spice_type := "spice"
@export var bonus := 0.15


func get_inspect_text() -> String:
	return "%s SHAKER\n(+%d%% quality)" % [spice_type.to_upper(), int(round(bonus * 100))]
