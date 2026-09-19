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
##
## Noah's framing, 2026-08-14: "the bay is essentially a desk, but at ground
## level... I don't see why you shouldn't be allowed to put items down on it,
## without stacking." So a BayStack with no crates also accepts exactly one
## loose, non-Crate item straight onto the ground marker (_anchors[0]) —
## completely separate from the crate-stacking machinery above, no elevator,
## no cycling. The two are mutually exclusive: a loose item can't be set down
## while any crate occupies this stack, and a crate can't be placed while a
## loose item sits here. This is how a delivered piece of Equipment (a spice
## shaker) lands — see GameState._deliver_orders() / place_loose_item below.

var _loose_item: Item = null


func _ready() -> void:
	super._ready()
	add_to_group("bay_stacks")


func interact(player: Player) -> void:
	var carried := player.held_item
	if carried is Crate and _loose_item != null:
		# The ground slot's taken by a loose item — no starting a crate
		# stack underneath it until that's cleared.
		return
	if carried != null and not (carried is Crate) and _loose_item == null and super.is_empty():
		_loose_item = player.drop_item()
		_loose_item.attach_to(_anchors[0])
		_on_occupancy_changed()
		return
	if carried == null and _loose_item != null:
		player.take_item(_loose_item)
		_loose_item = null
		_on_occupancy_changed()
		return
	super.interact(player)


## The delivery path for a non-Crate orderable (Equipment) — mirrors
## CrateStack.add_crate()'s shape but for the ground slot instead. Refuses
## (returns false) if a crate stack or another loose item already occupies
## this stack.
func place_loose_item(item: Item) -> bool:
	if not super.is_empty() or _loose_item != null:
		return false
	_loose_item = item
	item.attach_to(_anchors[0])
	_on_occupancy_changed()
	return true


func is_empty() -> bool:
	return super.is_empty() and _loose_item == null


func has_room() -> bool:
	return super.has_room() and _loose_item == null


func clear_contents() -> void:
	super.clear_contents()
	if _loose_item != null:
		_loose_item.queue_free()
		_loose_item = null
		_on_occupancy_changed()


func get_inspect_text() -> String:
	if _loose_item != null:
		return "%s\n%s" % [_label(), _loose_item.get_inspect_text()]
	return super.get_inspect_text()


## The programmatic delivery path (GameState._deliver_orders()) bypasses
## interact() entirely, so it needs its own guard against landing a crate on
## top of a resting loose item.
func add_crate(crate: Crate) -> bool:
	if _loose_item != null:
		return false
	return super.add_crate(crate)


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
func hints(player: Player) -> Array[Dictionary]:
	var carried := player.held_item
	if carried is Crate and _loose_item != null:
		return []
	if carried != null and not (carried is Crate) and _loose_item == null and super.is_empty():
		return [hint("interact", "Put down %s" % carried.hint_name())]
	if carried == null and _loose_item != null:
		return [hint("interact", "Pick up %s" % _loose_item.hint_name())]
	return super.hints(player)


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
