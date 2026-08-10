class_name CrateStack
extends SlotStation

## A stack of crates in fixed physical slots — the shared mechanism behind
## both `Shelf` (this class, used directly — a mounted shelf has no physical
## deviation from the base behavior) and `BayStack` (a subclass overriding
## the handful of things that differ because a floor stack has to obey
## gravity and a wall shelf doesn't — see bay_stack.gd).
##
## The TOP slot is always the interactable one — SlotStation's _get_held/
## _set_held/_slot_marker point at _slots[capacity - 1], permanently, exactly
## TrayFridge's own precedent. Tap **action** to cycle: the crate on top
## teleports to the bottom, every other crate physically slides up one
## position into the spot that just opened above it — the same "reality-
## warping" shuffle TrayFridge already does, and for the same reason: with a
## fixed active slot, whatever's currently in focus is always the thing
## visibly sitting on top, not a marker buried wherever an index happens to
## point.
##
## The **work** button also carries a sustained `action_hold` — resolved
## with the same _TAP_GRACE deferred-decision shape SlotStation's own
## dispenser logic already uses (so a press can't be told apart from a hold
## until it's actually held past the grace window) — express-restocks the
## active crate if it's empty. Noah's own framing for this: "it's kind of
## like doing a job at a station, hold R to do work, and the work for an
## empty crate is to express restock."
##
## Everything that DOES differ between a shelf and a bay stack is pulled out
## into small overridable hooks (_fill_order, _should_cycle,
## _on_occupancy_changed, _label) rather than branched on a flag in here —
## a first pass shared one script with an `is_bay_slot` toggle threading
## through several methods, which kept needing new special cases (a bay
## stack's collision has to disappear when empty; cycling has to no-op below
## 2 crates there but never on a shelf) and, worse, got a real bug from the
## two being physically different in a way one shared rule couldn't express:
## a shelf's slots are independent boards, so filling nearest the active
## slot (top-down) makes sense, but a bay stack's crates are gravity-stacked
## on bare ground and a crate spawned into a higher slot with nothing under
## it would render floating in mid-air. That's not an edge case to patch
## around, it's two different physical objects — hence the subclass split.

const _CYCLE_GRACE := 0.15
const _MOVE_DURATION := 0.25

@export var capacity := 3

## If set, this shelf spawns one starting Crate of this type into its first
## slot at game start — how the initial handful of ingredient shelves get
## stocked, without needing a pre-placed item as a scene child (no existing
## station in this project pre-places an item that way, so this follows the
## established "config lives as @export, per-instance" pattern instead —
## same shape Crate's own contained_type/starting_stock already use). Empty
## for every shelf/bay slot that should just start bare.
@export var starting_crate_type := ""
@export var starting_crate_stock := 8

var _slots: Array[Crate] = []
var _pending_cycle_player: Player = null
var _cycle_press_elapsed := 0.0

var _anchors: Array[Marker3D] = []


func _ready() -> void:
	_slots.resize(capacity)
	for i in capacity:
		_anchors.append(get_node("Slot%d" % i))
	super._ready()
	if starting_crate_type != "":
		var crate: Crate = load("res://items/crate.tscn").instantiate()
		crate.contained_type = starting_crate_type
		crate.starting_stock = starting_crate_stock
		add_crate(crate)
	_on_occupancy_changed()


func _get_held() -> Item:
	return _slots[capacity - 1]


func _set_held(value: Item) -> void:
	_slots[capacity - 1] = value as Crate
	_on_occupancy_changed()


func _slot_marker() -> Marker3D:
	return _anchors[capacity - 1]


## Carrying a crate onto a stack whose active (top) slot is already taken
## normally does nothing — two Crates never combine (no shared item_type,
## never "unmodified"), so none of SlotStation's interact() branches fire,
## and the crate you're carrying would otherwise be stuck until you cycle to
## an empty slot first. Skip straight to placing it in the next slot
## _fill_order() offers instead. Falls through to the inherited behavior for
## every other case (taking, dispensing, restocking-adjacent interactions on
## the active slot) — this only ever intercepts "carrying a crate, top slot
## occupied."
func interact(player: Player) -> void:
	var carried := player.held_item
	if carried is Crate and held_item != null:
		for i in _fill_order():
			if _slots[i] == null:
				var crate := player.drop_item()
				crate.attach_to(_anchors[i])
				_slots[i] = crate
				_on_occupancy_changed()
				return
	super.interact(player)


func action(player: Player) -> void:
	_pending_cycle_player = player
	_cycle_press_elapsed = 0.0


func action_hold(player: Player, delta: float) -> void:
	if _pending_cycle_player != player:
		return
	_cycle_press_elapsed += delta
	if _cycle_press_elapsed < _CYCLE_GRACE:
		return
	# Held long enough — this was a deliberate hold, not a tap: cancel the
	# pending cycle and, if the active slot holds an empty crate, restock it.
	_pending_cycle_player = null
	var active := held_item
	if active != null:
		(active as Crate).try_restock()


func _process(delta: float) -> void:
	if _pending_cycle_player != null:
		var p := _pending_cycle_player
		if not Input.is_action_pressed("p%d_action" % p.player_id):
			# Released before the grace window elapsed — a genuine quick
			# tap: cycle the stack.
			_pending_cycle_player = null
			_cycle()
	super._process(delta)


## The crate on top teleports to the bottom (no physical path exists for
## that jump, same as TrayFridge's top→bottom case); every other crate
## slides up one position into the anchor that just freed up above it.
func _cycle() -> void:
	if not _should_cycle():
		return
	var rotated: Array[Crate] = [_slots[capacity - 1]]
	for i in range(capacity - 1):
		rotated.append(_slots[i])
	_slots = rotated
	if _slots[0] != null:
		_slots[0].attach_to(_anchors[0])
	for i in range(1, capacity):
		if _slots[i] != null:
			_slide_to_anchor(_slots[i], i)


## Reparents immediately (so game logic is correct right away), then plays
## the visual slide up from wherever the item actually was to its new slot.
func _slide_to_anchor(item: Item, anchor_index: int) -> void:
	var target := _anchors[anchor_index]
	var start_global := item.global_position
	item.attach_to(target)
	item.position = target.to_local(start_global)
	var tween := create_tween()
	tween.tween_property(item, "position", Vector3.ZERO, _MOVE_DURATION).set_ease(Tween.EASE_OUT)


## SlotStation's is_empty/clear_contents only ever see the top slot (via
## held_item) — this station actually needs every slot checked/cleared.
func is_empty() -> bool:
	return _slots.all(func(c: Crate) -> bool: return c == null)


func clear_contents() -> void:
	for i in _slots.size():
		if _slots[i] != null:
			_slots[i].queue_free()
			_slots[i] = null
	_on_occupancy_changed()


## Whether there's a free slot at all — used by GameState._deliver_orders()
## to find somewhere for a fresh delivery to land.
func has_room() -> bool:
	return _slots.any(func(c: Crate) -> bool: return c == null)


## Places a freshly-spawned crate (not yet in the tree) into the first empty
## slot _fill_order() offers — the delivery path, distinct from the
## player-driven interact() flow above. Returns false (does nothing) if
## there's no room.
func add_crate(crate: Crate) -> bool:
	for i in _fill_order():
		if _slots[i] == null:
			crate.attach_to(_anchors[i])
			_slots[i] = crate
			_on_occupancy_changed()
			return true
	return false


## Which slot index to fill next, in priority order — a shelf fills top-down
## (nearest the active slot, so a newly-stocked crate needs no cycling to
## reach), used by both add_crate() and interact()'s smart-place. BayStack
## overrides this bottom-up (gravity: a crate can't float above an empty
## slot).
func _fill_order() -> Array[int]:
	var order: Array[int] = []
	for i in range(capacity - 1, -1, -1):
		order.append(i)
	return order


## Whether a resolved tap-cycle should actually rotate. Always true on a
## shelf — cycling with only one crate present is how you reach an empty
## slot to stock a second one. BayStack overrides this to no-op below 2
## crates, where there's nothing else to rotate into place.
func _should_cycle() -> bool:
	return true


## Called whenever a slot's occupancy actually changes. No-op on a shelf —
## its collision is a permanent fixture regardless of contents. BayStack
## overrides this to toggle walkability.
func _on_occupancy_changed() -> void:
	pass


func get_config() -> Dictionary:
	return {"capacity": capacity}


func apply_config(config: Dictionary) -> void:
	capacity = config.get("capacity", capacity)


func _label() -> String:
	return "SHELF"


func get_inspect_text() -> String:
	var filled := _slots.filter(func(c: Crate) -> bool: return c != null).size()
	var lines := ["%s (%d/%d)" % [_label(), filled, capacity]]
	var active := held_item
	lines.append(active.get_inspect_text() if active != null else "(empty slot, active)")
	return "\n".join(lines)
