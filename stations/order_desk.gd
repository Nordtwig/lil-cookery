class_name OrderDesk
extends Station

## Night-only ordering panel — pay up front for tomorrow's ingredient
## delivery, one Crate refill per unit ordered (see GameState.place_order/
## _deliver_orders). Only usable during GameState.Phase.NIGHT.
##
## The player who opens it drives the panel: their move input is captured
## (see Player.ui_capture) — up/down cycles rows, left/right adjusts the
## selected ingredient row's order quantity, action cancels. Interact only
## confirms-and-pays when the row currently selected is the dedicated
## "CONFIRM ORDER" row at the bottom of the list — a plain ingredient row
## doesn't respond to interact at all. This is deliberate, not a missing
## zero-amount check: interact opening the desk and interact confirming it
## used to be the exact same button-in-the-same-context, so a reflexive
## second tap (E is "do the thing" everywhere else in this game) silently
## confirmed a $0 order and closed the desk before anyone meant it to.
## Requiring a real navigation to a real row fixes that structurally. The
## other player is completely unaffected — their own Player instance never
## touches this station's input handling at all.
##
## The ingredient row list is read live from whatever Crates actually exist
## in the "crates" group, not a hardcoded list — stays in sync automatically
## if ingredients are ever added/removed. Crates have no stock ceiling, so
## quantity here isn't capped either — the only real constraint is what you
## can afford at confirm time.

## Debounce for held up/down/left/right — a deliberate hold-to-repeat feel
## (common menu-navigation shape) without flying through rows/amounts at
## 60fps.
const _MOVE_REPEAT_DELAY := 0.25

var _open_player: Player = null
var _item_types: Array[String] = []
var _row := 0
var _amounts: Array[int] = []
var _move_cooldown := 0.0

@onready var _panel: Label3D = $Panel


func _ready() -> void:
	super._ready()
	_panel.visible = false


func interact(player: Player) -> void:
	if GameState.phase != GameState.Phase.NIGHT:
		return
	if _open_player == null:
		_open_desk(player)


func get_inspect_text() -> String:
	if GameState.phase != GameState.Phase.NIGHT:
		return "ORDER DESK\n(night only)"
	if _open_player != null:
		return "ORDER DESK\n(in use)"
	return "ORDER DESK\nInteract to order tomorrow's delivery"


## Row index of the dedicated "CONFIRM ORDER" row — always one past the
## last ingredient row.
func _confirm_row() -> int:
	return _item_types.size()


func _row_count() -> int:
	return _item_types.size() + 1


func _open_desk(player: Player) -> void:
	_item_types = []
	for crate in get_tree().get_nodes_in_group("crates"):
		if crate.item_type not in _item_types:
			_item_types.append(crate.item_type)
	_item_types.sort()
	if _item_types.is_empty():
		return
	_amounts = []
	_amounts.resize(_item_types.size())
	_amounts.fill(0)
	_row = 0
	_open_player = player
	player.start_ui_capture(self)
	_update_panel()


## Called every physics frame by the capturing Player while this desk has
## them — see Player.ui_capture. Polls input directly by player_id, same
## convention SlotStation already uses for its own tap/hold timing.
func handle_input(player: Player, delta: float) -> void:
	var prefix := "p%d" % player.player_id
	if Input.is_action_just_pressed(prefix + "_action"):
		_cancel(player)
		return
	if Input.is_action_just_pressed(prefix + "_interact"):
		if _row == _confirm_row():
			_confirm(player)
		return

	_move_cooldown -= delta
	if _move_cooldown > 0.0:
		return
	if Input.is_action_pressed(prefix + "_move_up"):
		_row = (_row - 1 + _row_count()) % _row_count()
		_move_cooldown = _MOVE_REPEAT_DELAY
	elif Input.is_action_pressed(prefix + "_move_down"):
		_row = (_row + 1) % _row_count()
		_move_cooldown = _MOVE_REPEAT_DELAY
	elif Input.is_action_pressed(prefix + "_move_left"):
		_adjust(-1)
		_move_cooldown = _MOVE_REPEAT_DELAY
	elif Input.is_action_pressed(prefix + "_move_right"):
		_adjust(1)
		_move_cooldown = _MOVE_REPEAT_DELAY
	else:
		return
	_update_panel()


## No-op on the CONFIRM ORDER row — nothing to adjust there. No upper bound —
## crates have no stock ceiling, so the only thing that can stop an order is
## money, checked once at confirm time, not per-adjustment here.
func _adjust(delta_qty: int) -> void:
	if _row == _confirm_row():
		return
	_amounts[_row] = maxi(_amounts[_row] + delta_qty, 0)


func _confirm(player: Player) -> void:
	var total_cost := 0
	for i in _item_types.size():
		total_cost += _amounts[i] * GameState.order_unit_cost
	if GameState.money < total_cost:
		# Can't afford the order as configured — refuse the whole thing
		# rather than silently placing a partial order; adjust amounts down
		# and confirm again.
		return
	for i in _item_types.size():
		if _amounts[i] > 0:
			GameState.place_order(_item_types[i], _amounts[i])
	_close(player)


func _cancel(player: Player) -> void:
	_close(player)


func _close(player: Player) -> void:
	player.end_ui_capture()
	_open_player = null
	_panel.visible = false


func _update_panel() -> void:
	_panel.visible = true
	var lines := ["ORDER DESK"]
	var total := 0
	for i in _item_types.size():
		var marker := ">" if i == _row else " "
		var qty := _amounts[i]
		total += qty * GameState.order_unit_cost
		lines.append("%s %s: %d" % [marker, _item_types[i].capitalize(), qty])
	var confirm_marker := ">" if _row == _confirm_row() else " "
	lines.append("%s CONFIRM ORDER" % confirm_marker)
	lines.append("Total: $%d" % total)
	_panel.text = "\n".join(lines)
