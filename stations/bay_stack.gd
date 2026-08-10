class_name BayStack
extends CrateStack

## The loading-bay floor version of CrateStack — crates piled directly on
## bare ground rather than sitting on independent shelf boards. Every
## override here traces back to that one physical difference: gravity.
##
## Base CrateStack fixes the active/interactable slot at _slots[capacity-1]
## (the top), which is right for a shelf — its boards are independent, order
## never matters. It's wrong here: a bay stack fills bottom-up, so the top
## slot sits empty for most of a stack's life. Placing a crate at a fixed
## "active" slot that reads as empty while a lower slot is actually occupied
## is exactly how a crate ends up floating with a gap underneath it. So the
## active slot here is whichever slot is **currently the top of the real
## stack** — the highest occupied index, recomputed every access, falling
## back to the floor (0) only once the stack is genuinely empty.

func _ready() -> void:
	super._ready()
	add_to_group("bay_stacks")


func _active_index() -> int:
	for i in range(capacity - 1, -1, -1):
		if _slots[i] != null:
			return i
	return 0


func _get_held() -> Item:
	return _slots[_active_index()]


func _set_held(value: Item) -> void:
	_slots[_active_index()] = value as Crate
	_on_occupancy_changed()


func _slot_marker() -> Marker3D:
	return _anchors[_active_index()]


## Gravity: a crate can't float above an empty slot, so a bay stack has to
## fill bottom-up — the opposite of a shelf's top-down "nearest the active
## slot" order. Filling top-down here would spawn a crate floating in
## mid-air with nothing supporting it.
func _fill_order() -> Array[int]:
	var order: Array[int] = []
	for i in capacity:
		order.append(i)
	return order


## Cycling never applies here, at any crate count — with the active slot now
## always the real top of the stack, there's nothing a rotation could reveal
## that removing the top crate wouldn't already reveal on its own. Unlike a
## shelf, nobody manually plans out which bay slot to fill.
func _should_cycle() -> bool:
	return false


## A bay slot with nothing stacked on it is just bare floor — walkable, not
## an obstacle — so the loading bay's inner tiles stay reachable instead of
## every cell (empty or not) permanently blocking movement like a solid
## station. Only once a crate actually lands there does it become a real
## physical obstacle.
func _on_occupancy_changed() -> void:
	collision_layer = 5 if not is_empty() else 4


func _label() -> String:
	return "BAY STACK"
