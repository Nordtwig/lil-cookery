class_name ReceiptStation
extends LedgerAccumulator

## Merges two things Noah wanted on one physical spike, matching a real
## kitchen: a **live order printer** during SERVICE (pull one pending chit at
## a time — what the kitchen still owes) and the existing **night bookkeeping
## pile** (LedgerAccumulator's "receipts" category — a record of what was
## actually sold, tallied after close). Noah's own framing: "the Receipt
## Station has both a printer, which you can pull receipts from during
## service, and has the spike of receipts you empty at the night phase."
##
## Table.reveal_order() calls print_tickets() here instead of handing a
## physical ticket to the player directly at the table (the old single-guest
## design) — with a whole party's worth of dishes now, walking back and
## forth to grab one ticket per guest would have multiplied the trip for no
## real decision. One table interact reveals the whole order AND prints it
## here; receipts get pulled one at a time from the kitchen instead.
##
## Two physically distinct fixtures on one station (2026-08-14, Noah: "we
## cant just have the receipt spike... let's make the spike off center
## towards the bottom, and add a new box that changes light from red to
## green if theres an order waiting"): the spike (Rod/Pile) is offset toward
## the front of the tile; a separate small `Light` box reads red/green for
## whether _pending_tickets has anything in it — a glance-only "something's
## waiting to be picked up and tagged" cue, distinct from actually walking
## up and inspecting/pulling.

var _pending_tickets: Array[Dictionary] = []
const _TICKET_SCENE := preload("res://items/order_ticket.tscn")

const _COLOR_IDLE := Color(0.85, 0.20, 0.15, 1)
const _COLOR_WAITING := Color(0.20, 0.80, 0.25, 1)

@onready var _light: MeshInstance3D = $Light
var _light_mat: StandardMaterial3D


func _ready() -> void:
	super._ready()
	add_to_group("receipt_stations")
	_light_mat = StandardMaterial3D.new()
	_light_mat.emission_enabled = true
	_light_mat.emission_energy_multiplier = 0.8
	_light.material_override = _light_mat
	_update_light()


func _process(delta: float) -> void:
	super._process(delta)
	_update_light()


func _update_light() -> void:
	var color := _COLOR_WAITING if not _pending_tickets.is_empty() else _COLOR_IDLE
	_light_mat.albedo_color = color
	_light_mat.emission = color


## Queues one printed ticket per dish — called by Table, not the player.
func print_tickets(dishes: Array[String], table_number: int) -> void:
	for dish in dishes:
		_pending_tickets.append({"dish": dish, "table_number": table_number})


## During SERVICE, empty-handed interact pulls the oldest pending order
## ticket. Outside SERVICE (i.e. NIGHT), this is the same station it's
## always been — falls through to LedgerAccumulator's bookkeeping-slip pickup
## unchanged.
func interact(player: Player) -> void:
	if GameState.phase == GameState.Phase.SERVICE:
		if player.held_item == null and not _pending_tickets.is_empty():
			var order: Dictionary = _pending_tickets.pop_front()
			var ticket: OrderTicket = _TICKET_SCENE.instantiate()
			ticket.dish = order.dish
			ticket.table_number = order.table_number
			player.take_item(ticket)
		return
	super.interact(player)


func get_inspect_text() -> String:
	if GameState.phase == GameState.Phase.SERVICE:
		if _pending_tickets.is_empty():
			return "%s\n(no pending orders)" % display_name
		return "%s\n%d pending order%s" % [
			display_name, _pending_tickets.size(), "" if _pending_tickets.size() == 1 else "s"
		]
	return super.get_inspect_text()
