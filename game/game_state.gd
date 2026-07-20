extends Node

## Session-wide shared state. Autoloaded as `GameState`. For now it just
## holds the money total the serving loop feeds; the night bookkeeping phase
## will read/extend this later.

signal money_changed(total: int)

## Small starting cushion so an early bad-luck run (a crate empties before
## the first dish is served) never hard-locks a session on an emergency
## restock nobody can afford yet.
var money := 15

enum Phase { MORNING, SERVICE, NIGHT }

## Which part of the day it is. MORNING = planning/prep (build mode is only
## ever available here); SERVICE = the dining room is open, tables seat
## customers; NIGHT = service has fully wound down, waiting on Bed.
signal phase_changed(phase: Phase)

var phase: Phase = Phase.MORNING

## How many days have passed — increments each time Bed sends NIGHT -> MORNING.
var day := 1

## Placeholder tuning number ("let's say 4 for now") — real pacing is
## backlog item 26's job, not this skeleton's. Total guests across all
## tables for the whole day, not per-table.
var guests_per_day := 4

## Drawn down by consume_guest() as tables seat customers; only meaningful
## during SERVICE. Read by the HUD.
var guests_remaining := 0

## True from the instant the guest pool runs dry until every table has
## actually gone empty (unserved WAITING customers leave immediately,
## EATING/PAID tables are left to finish/be collected normally) — Table
## watches this to stop seating new customers; this autoload watches every
## Table's own is_empty() to know when it's safe to actually flip to NIGHT.
var closing_out := false

## Per-unit cost for planned (OrderDesk) ordering — deliberately cheaper
## than paying a Crate's flat emergency-restock fee for the same need, since
## you're buying ahead instead of paying a "need it right now" premium.
## Placeholder tuning number like everything else economy-shaped here;
## backlog item 26 owns the real pass.
var order_unit_cost := 1

## item_type -> quantity, paid for at OrderDesk confirm time but not applied
## to any Crate's stock until _deliver_orders() runs at the next MORNING.
var pending_deliveries: Dictionary = {}


func _process(_delta: float) -> void:
	if phase != Phase.SERVICE or not closing_out:
		return
	for table in get_tree().get_nodes_in_group("tables"):
		if not table.is_empty():
			return
	closing_out = false
	set_phase(Phase.NIGHT)


func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)


func set_phase(new_phase: Phase) -> void:
	if new_phase == phase:
		return
	phase = new_phase
	phase_changed.emit(phase)


## Called by OpenSign — MORNING -> SERVICE, refills the guest pool. No-op
## outside MORNING (can't re-open an already-running or already-wound-down
## day).
func start_service() -> void:
	if phase != Phase.MORNING:
		return
	guests_remaining = guests_per_day
	closing_out = false
	set_phase(Phase.SERVICE)


## Called by a Table right before it seats a new customer. Returns false (and
## the table shouldn't seat anyone) once the day's pool is exhausted — the
## pool-based replacement for a time-based clock. Triggers closing_out the
## instant the last guest is drawn, same shape a clock hitting zero would.
##
## Order matters here: this runs and returns BEFORE the calling Table's own
## _seat_customer() ever executes (see Table._process's EMPTY branch), so
## _start_closing_out()'s sweep below can never catch the very table that's
## mid-draw — it's still EMPTY at sweep time, not WAITING yet. Getting this
## backwards once already kicked a customer the instant they sat down,
## because they were literally the guest whose arrival emptied the pool.
func consume_guest() -> bool:
	if phase != Phase.SERVICE or closing_out or guests_remaining <= 0:
		return false
	guests_remaining -= 1
	if guests_remaining <= 0:
		_start_closing_out()
	return true


## Called by OpenSign when flipped again mid-SERVICE — forces closing_out
## early, before the guest pool naturally runs dry, exact same wind-down as
## the pool hitting zero (no new seatings; existing customers unaffected).
## Mainly a debug/QoL convenience for now (skip a slow day without waiting
## out the pool) — a plausible future lever for a reputation cost (closing
## early on seated customers), not built.
func close_early() -> void:
	if phase != Phase.SERVICE or closing_out:
		return
	_start_closing_out()


## The actual wind-down moment, shared by both triggers above: no more new
## seatings from here (guaranteed separately by guests_remaining <= 0 /
## closing_out itself once set), plus a one-time sweep — anyone ALREADY
## WAITING right now leaves immediately, no penalty. Deliberately a single
## sweep, not an ongoing per-frame check: no table can newly become WAITING
## after this point anyway (consume_guest() refuses once closing_out is
## true), so there's nothing left to keep watching for.
func _start_closing_out() -> void:
	closing_out = true
	for table in get_tree().get_nodes_in_group("tables"):
		table.leave_if_waiting()


## Called by OrderDesk on confirm. Pays immediately (fails, returns false, if
## short on cash — the whole order is refused rather than silently placing a
## partial one); the actual crate refill is deferred to _deliver_orders().
func place_order(item_type: String, quantity: int) -> bool:
	if quantity <= 0:
		return true
	var cost := quantity * order_unit_cost
	if money < cost:
		return false
	add_money(-cost)
	pending_deliveries[item_type] = pending_deliveries.get(item_type, 0) + quantity
	return true


## Called by Bed — NIGHT -> MORNING, advances the day counter. No-op outside
## NIGHT (can't go to bed mid-service).
func end_night() -> void:
	if phase != Phase.NIGHT:
		return
	_deliver_orders()
	day += 1
	set_phase(Phase.MORNING)


func _deliver_orders() -> void:
	if pending_deliveries.is_empty():
		return
	for crate in get_tree().get_nodes_in_group("crates"):
		var qty: int = pending_deliveries.get(crate.item_type, 0)
		if qty > 0:
			crate.receive_delivery(qty)
	pending_deliveries.clear()
