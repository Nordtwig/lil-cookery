class_name TrayFridge
extends SlotStation

## A vertical rack of three shelves (2026-08-14, down from four — "the normal
## desk racks should also have three shelves instead of 4, so can be a
## little shorter," matching CrateStack/Shelf's own capacity of 3). The TOP
## shelf is always the interactable one — SlotStation's _get_held/_set_held/
## _slot_marker just point at _slots[2]/_anchors[2], permanently. Tap
## **action** to cycle: the tray currently on top jumps straight to the
## bottom shelf (a teleport — there's no physical path for "top to bottom"
## the way there is for the others, and that's fine), while the other
## shelf's tray slides up one position into the spot that just opened above
## it, like an elevator where the result that reaches the top immediately
## recycles to the bottom. Every tap/hold dispensing behavior (peel/
## take-whole/merge/absorb) is inherited from SlotStation completely
## unchanged — this station only ever redirects where "the slot" points.
##
## **Smart-place** (2026-08-14, matching the fix CrateStack already got
## during the storage-room build): carrying a Tray onto a rack whose top
## shelf already holds a *different* Tray used to do nothing at all — two
## Trays never merge via the inherited dispenser grammar (no shared
## item_type), so none of SlotStation.interact()'s branches ever fired.
## interact() now overrides to smart-place into the next empty shelf instead
## of requiring a manual cycle-to-empty-shelf first.
##
## An empty top after cycling is a normal state, not something to skip past —
## you cycle onto it on purpose to set a new tray down there.

const _MOVE_DURATION := 0.25

## Indexed bottom (0) to top (2) — matches _anchors.
var _slots: Array[Item] = [null, null, null]

@onready var _anchors: Array[Marker3D] = [$Shelf0, $Shelf1, $Shelf2]


func _get_held() -> Item:
	return _slots[2]


func _set_held(value: Item) -> void:
	_slots[2] = value


func _slot_marker() -> Marker3D:
	return _anchors[2]


## Carrying a Tray onto a rack whose top shelf is already taken by a
## different Tray: skip straight to the next empty shelf (nearest the top,
## same "why cycle first when there's an obvious empty spot" reasoning
## CrateStack's own smart-place uses) instead of doing nothing.
func interact(player: Player) -> void:
	var carried := player.held_item
	if carried is Tray and held_item != null:
		for i in range(2, -1, -1):
			if _slots[i] == null:
				var tray := player.drop_item()
				tray.attach_to(_anchors[i])
				_slots[i] = tray
				return
	super.interact(player)


func hints(player: Player) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if player.held_item is Tray and held_item != null:
		for i in range(2, -1, -1):
			if _slots[i] == null:
				out.append(hint("interact", "Put %s on a shelf" % player.held_item.hint_name()))
				break
	if out.is_empty():
		out = super.hints(player)
	out.append(hint("action", "Next shelf"))
	return out


func action(_player: Player) -> void:
	var rotated: Array[Item] = [_slots[2], _slots[0], _slots[1]]
	_slots = rotated
	if _slots[0] != null:
		# The old top, teleporting to the bottom — no adjacent path exists
		# for this one, so it just jumps.
		_slots[0].attach_to(_anchors[0])
	for i in [1, 2]:
		if _slots[i] != null:
			_slide_to_anchor(_slots[i], i)


## SlotStation's is_empty/clear_contents only ever see _slots[2] (the top,
## via held_item) — this station actually needs all three checked/cleared.
func is_empty() -> bool:
	return _slots.all(func(item: Item) -> bool: return item == null)


func clear_contents() -> void:
	for i in _slots.size():
		if _slots[i] != null:
			_slots[i].queue_free()
			_slots[i] = null


## Reparents immediately (so game logic — can_absorb, inspect, the next
## interact — is correct right away), then plays the visual slide up from
## wherever the item actually was to its new shelf, rather than snapping.
func _slide_to_anchor(item: Item, anchor_index: int) -> void:
	var target := _anchors[anchor_index]
	var start_global := item.global_position
	item.attach_to(target)
	item.position = target.to_local(start_global)
	var tween := create_tween()
	tween.tween_property(item, "position", Vector3.ZERO, _MOVE_DURATION).set_ease(Tween.EASE_OUT)
