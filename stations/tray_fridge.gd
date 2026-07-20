class_name TrayFridge
extends SlotStation

## A vertical rack of four shelves. The TOP shelf is always the interactable
## one — SlotStation's _get_held/_set_held/_slot_marker just point at
## _slots[3]/_anchors[3], permanently. Tap **action** to cycle: the tray
## currently on top jumps straight to the bottom shelf (a teleport — there's
## no physical path for "top to bottom" the way there is for the others, and
## that's fine), while every other shelf's tray slides up one position into
## the spot that just opened above it, like an elevator where the result
## that reaches the top immediately recycles to the bottom. Every tap/hold
## dispensing behavior (peel/take-whole/merge/absorb) is inherited from
## SlotStation completely unchanged — this station only ever redirects where
## "the slot" points.
##
## An empty top after cycling is a normal state, not something to skip past —
## you cycle onto it on purpose to set a new tray down there.

const _MOVE_DURATION := 0.25

## Indexed bottom (0) to top (3) — matches _anchors.
var _slots: Array[Item] = [null, null, null, null]

@onready var _anchors: Array[Marker3D] = [$Shelf0, $Shelf1, $Shelf2, $Shelf3]


func _get_held() -> Item:
	return _slots[3]


func _set_held(value: Item) -> void:
	_slots[3] = value


func _slot_marker() -> Marker3D:
	return _anchors[3]


func action(_player: Player) -> void:
	var rotated: Array[Item] = [_slots[3], _slots[0], _slots[1], _slots[2]]
	_slots = rotated
	if _slots[0] != null:
		# The old top, teleporting to the bottom — no adjacent path exists
		# for this one, so it just jumps.
		_slots[0].attach_to(_anchors[0])
	for i in [1, 2, 3]:
		if _slots[i] != null:
			_slide_to_anchor(_slots[i], i)


## SlotStation's is_empty/clear_contents only ever see _slots[3] (the top,
## via held_item) — this station actually needs all four checked/cleared.
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
