extends Node

## Session-wide shared state. Autoloaded as `GameState`. For now it just
## holds the money total the serving loop feeds; the night bookkeeping phase
## will read/extend this later.

## Fired once the day's books are actually closed — either at
## BookkeepingComputer (silent = false, a real net the HUD can reveal) or
## silently by end_night() (silent = true — the HUD still needs to catch its
## displayed account total up to the real GameState.money, just without the
## reveal ceremony, since finding out was the whole point of visiting the
## office). `net` is the day's cash - invoices - rent (- the auto-close cut,
## if silent) — see file_books()/_auto_close_books().
signal books_filed(net: int, silent: bool)

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

## Placeholder tuning number, bumped 2026-08-14 (was 4) now that a table
## seats a whole weighted-size party at once rather than one guest at a
## time — at draw_party_size()'s current weights (~1.95 guests/party on
## average), the old value was only ever two parties a day. Real pacing is
## still backlog item 26's job, not this skeleton's. Total guests across all
## tables for the whole day, not per-table.
var guests_per_day := 16

## Drawn down by consume_party() as tables seat parties; only meaningful
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

## Flat cost of running the place for one day, charged when the books close
## (see file_books()/_auto_close_books()) — the ledger's one guaranteed
## line, known up front rather than discovered, unlike the three
## earned/spent figures below.
var rent := 5

## The day's figures, each fed by a record_*() call from wherever that
## category actually happens. Reset at start_service() — bookkeeping is a
## per-day accounting, not cumulative. None of this duplicates `money` (the
## real, spendable total, updated the instant cash actually moves) — it's a
## second, slower-revealed ledger of related but distinct facts a player
## can't otherwise reconstruct once the day's a blur of individual pickups.
##
## Three real-restaurant categories (Noah's framing): `ledger_cash` is what
## you've actually collected (Table._collect() — tells you how much you
## earned, nothing about what was sold); `ledger_receipts` is a record of
## every order actually fulfilled (Table._serve(), at the moment of
## delivery — not collection, so it exists independently of whether anyone's
## walked over to pick up the cash yet; this is the "what did we sell today"
## side money alone can't answer, and the hook for a future tip-gauging
## pass); `ledger_invoices` is every ingredient purchase, whether it's an
## emergency restock mid-service or a planned order at night — the same
## category either way, since both are "money paid to get more stock," just
## at different urgency/cost.
var ledger_cash := 0
var ledger_receipts := 0
var ledger_invoices := 0
var ledger_waste := 0

## True once this NIGHT's books have been closed (either at
## BookkeepingComputer or silently by end_night() — see below). Walking
## straight to Bed without ever visiting the office still gets the books
## filed, just silently and worse, since someone still has to do it.
var books_closed := false


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
	ledger_cash = 0
	ledger_receipts = 0
	ledger_invoices = 0
	ledger_waste = 0
	books_closed = false
	set_phase(Phase.SERVICE)


func record_cash(amount: int) -> void:
	ledger_cash += amount


## Called by Table._serve() the instant an order is delivered — deliberately
## not at collect time, so this tracks what was actually sold, independent
## of whether the cash has physically been picked up yet.
func record_receipt(amount: int) -> void:
	ledger_receipts += amount


## Called for any purchase — a Crate's emergency restock or a planned
## OrderDesk order alike (ingredient or Equipment). Same category either way.
func record_invoice_spend(amount: int) -> void:
	ledger_invoices += amount


## Waste has no fetchable document — unlike the four figures above, it never
## costs fresh money (the ingredient was already paid for), it's purely an
## efficiency stat, so there's nothing to gate behind a physical fetch. It's
## always visible at the desk once book-closing time comes.
func record_waste(amount: int) -> void:
	ledger_waste += amount


## The current value of a ledger category, by name — read by LedgerAccumulator
## so one script can drive all three fixtures generically instead of one
## script per category.
func ledger_value(category: String) -> int:
	match category:
		"cash": return ledger_cash
		"receipts": return ledger_receipts
		"invoices": return ledger_invoices
	return 0


## Called by BookkeepingComputer once every category with real activity today
## is present on LedgerDesk (see LedgerDesk.missing() — a category with
## nothing to report is never required). Caller is expected to have already
## checked that (the computer refuses to activate otherwise); this just does
## the math and the deduction. Returns the exact figures for display.
func file_books() -> Dictionary:
	# Receipts is a record of what was sold, not a cost or a second income
	# stream — cash already captures the real money, so it's shown but not
	# part of the net math (kept for a future tip-gauging pass — comparing
	# receipts against cash collected is what that'd need).
	var net := ledger_cash - ledger_invoices - rent
	add_money(-rent)
	books_closed = true
	books_filed.emit(net, false)
	return {
		"cash": ledger_cash,
		"receipts": ledger_receipts,
		"invoices": ledger_invoices,
		"waste": ledger_waste,
		"rent": rent,
		"net": net,
	}


## The books get filed one way or another — if a player never visits the
## office at all this NIGHT, end_night() calls this instead: rent plus a
## flat automatic cut (someone still has to do the accounting), silently,
## with nothing shown. This is what makes visiting the office at all worth
## it — not a menu choice, just the difference between doing it yourself
## (free, file_books()) and not (this).
func _auto_close_books() -> void:
	var cut := maxi(1, ceili(0.10 * ledger_cash))
	var net := ledger_cash - ledger_invoices - rent - cut
	add_money(-rent)
	add_money(-cut)
	books_closed = true
	books_filed.emit(net, true)


## Weighted party-size draw for a table about to seat (2026-08-14, backlog
## item 30) — Noah's own placeholder numbers, a real balance pass is item
## 26's job: 2 guests most common, then 1, then 3, then 4 (rare). Independent
## of guests_remaining — consume_party() below clamps against the pool.
func draw_party_size() -> int:
	var roll := randf()
	if roll < 0.30:
		return 1
	elif roll < 0.80:
		return 2
	elif roll < 0.95:
		return 3
	return 4


## Called by a Table right before it seats a party. The multi-guest
## generalization of the old single-guest consume_guest() (deleted — this
## replaces it) — draws up to `requested_size` from the day's pool, returning
## the actual number seated, which can be smaller than requested if the pool's
## nearly dry (never negative, never seats nobody unless the pool was already
## empty). Triggers closing_out the instant the pool empties, same shape a
## clock hitting zero would.
##
## Order matters here: this runs and returns BEFORE the calling Table's own
## _seat_customer() ever executes (see Table._process's EMPTY branch), so
## _start_closing_out()'s sweep below can never catch the very table that's
## mid-draw — it's still EMPTY at sweep time, not WAITING yet. Getting this
## backwards once already kicked a customer the instant they sat down,
## because they were literally the guest whose arrival emptied the pool.
func consume_party(requested_size: int) -> int:
	if phase != Phase.SERVICE or closing_out or guests_remaining <= 0:
		return 0
	var actual := mini(requested_size, guests_remaining)
	guests_remaining -= actual
	if guests_remaining <= 0:
		_start_closing_out()
	return actual


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
## after this point anyway (consume_party() refuses once closing_out is
## true), so there's nothing left to keep watching for.
func _start_closing_out() -> void:
	closing_out = true
	for table in get_tree().get_nodes_in_group("tables"):
		table.leave_if_waiting()


## Per-unit price for a given orderable type — Equipment (a spice shaker) is
## priced at its own fixed cost, everything else (a real ingredient) at the
## flat order_unit_cost. What OrderDesk shows per row and what place_order
## actually charges.
func unit_cost_for(item_type: String) -> int:
	if Equipment.is_equipment(item_type):
		return Equipment.cost_for(item_type)
	return order_unit_cost


## Called by OrderDesk on confirm. Pays immediately (fails, returns false, if
## short on cash — the whole order is refused rather than silently placing a
## partial one); the actual delivery is deferred to _deliver_orders().
func place_order(item_type: String, quantity: int) -> bool:
	if quantity <= 0:
		return true
	var cost := quantity * unit_cost_for(item_type)
	if money < cost:
		return false
	add_money(-cost)
	record_invoice_spend(cost)
	pending_deliveries[item_type] = pending_deliveries.get(item_type, 0) + quantity
	return true


## Called by Bed — NIGHT -> MORNING, advances the day counter. No-op outside
## NIGHT (can't go to bed mid-service). If the books were never closed at
## BookkeepingComputer this NIGHT, they still get closed here — silently,
## and at the worse (auto-cut) rate, since rent and the day's accounting
## don't wait on a player actually walking over to the office.
func end_night() -> void:
	if phase != Phase.NIGHT:
		return
	if not books_closed:
		_auto_close_books()
	_deliver_orders()
	day += 1
	set_phase(Phase.MORNING)


const _CRATE_SCENE := preload("res://items/crate.tscn")

## How much stock one delivered crate holds — matches Crate's own
## starting_stock default, so "qty" here still means the same thing it
## always did (an ingredient count, what OrderDesk prices and displays),
## just packaged into physical crates now instead of silently topping up an
## existing bin.
const _DELIVERY_CRATE_SIZE := 8


## Spawns real Crate items into whatever loading-bay CrateStacks have room
## (2026-08-11 — crates became carryable Items rather than fixed stations,
## so a delivery can no longer just top up an existing bin in place; it has
## to physically land somewhere). Large orders split across multiple
## crates, each up to _DELIVERY_CRATE_SIZE. Equipment types (a spice shaker)
## aren't crated at all — they arrive as the real item, landing loose on
## whichever BayStack's ground slot is free (2026-08-14 — see
## BayStack.place_loose_item; "no unpacking," Noah's call). If the bay is
## full either way, whatever doesn't fit is simply lost — the loading-bay
## overflow system (an indicator + a way to reclaim it once space clears) is
## parked, see backlog.md; Noah's own call that this is fine to defer.
func _deliver_orders() -> void:
	if pending_deliveries.is_empty():
		return
	for item_type in pending_deliveries:
		var remaining: int = pending_deliveries[item_type]
		if Equipment.is_equipment(item_type):
			while remaining > 0:
				if not _place_delivery_equipment(item_type):
					break
				remaining -= 1
		else:
			while remaining > 0:
				var crate_stock := mini(remaining, _DELIVERY_CRATE_SIZE)
				if not _place_delivery_crate(item_type, crate_stock):
					break
				remaining -= crate_stock
	pending_deliveries.clear()


func _place_delivery_crate(item_type: String, stock_amount: int) -> bool:
	for stack in get_tree().get_nodes_in_group("bay_stacks"):
		if stack.has_room():
			var crate: Crate = _CRATE_SCENE.instantiate()
			crate.contained_type = item_type
			crate.starting_stock = stock_amount
			stack.add_crate(crate)
			return true
	return false


func _place_delivery_equipment(item_type: String) -> bool:
	var item: Item = Equipment.scene_for(item_type).instantiate()
	for stack in get_tree().get_nodes_in_group("bay_stacks"):
		if stack.place_loose_item(item):
			return true
	item.queue_free()
	return false
