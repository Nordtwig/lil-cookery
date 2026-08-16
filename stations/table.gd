class_name Table
extends Station

## A dining table — the pass, the order, and the till all in one, now
## supporting a whole party at once (2026-08-14, backlog item 30 — see
## completed.md's entry for the full design discussion).
##
## Ebb and flow: a table sits EMPTY, a party arrives after a random wait
## (WAITING) — a weighted draw picks party size (GameState.draw_party_size(),
## clamped to capacity and to whatever's left in the day's guest pool via
## GameState.consume_party()), and each guest gets a dish
## (Recipes.random_party_order(), with a slight duplicate-dish weight). The
## whole order stays hidden until a single empty-handed interact reveals it —
## no per-guest ticket to grab: revealing also prints one OrderTicket per
## dish at the nearest ReceiptStation (see that station's own doc), so
## walking a party's worth of individual pickups was never necessary. A
## delivered plate is matched against one still-pending dish (by tag if it
## matches something still owed, else FIFO) and scored against THAT dish —
## same forgiving evaluate() as always. Each served dish sits visibly on its
## own plate spot while that guest "eats" on an independent timer; the whole
## party is billed as one group total once every dish has both been served
## AND finished being eaten, plus a tightness bonus if the first and last
## serve landed within tightness_window of each other (the payoff for
## batching/prepping ahead rather than cooking one guest at a time). No
## impatience timer, no angry-leave — a still-pending dish at closing_out is
## just dropped (no penalty, no reward); whatever's already served/eating
## keeps going and gets paid normally, since punishing an already-served
## guest for a tablemate's order never arriving would blame the wrong thing.

enum State { EMPTY, WAITING, PAID }

const _BAND_TEXT := {
	"perfect": "PERFECT!",
	"good": "Good",
	"poor": "Poor",
}
const _BAND_COLOR := {
	"perfect": Color(0.30, 0.85, 0.35),
	"good": Color(0.85, 0.80, 0.20),
	"poor": Color(0.90, 0.50, 0.20),
}

## Which table this is — shown on its order tickets so several live orders stay
## tellable apart. Set per-instance in the kitchen scene.
@export var table_number := 1

## Max party size this table can seat — fixed per table for now (backlog item
## 30, Noah's call: "let's say these normal, 1x1 tables have a capacity of up
## to 4. We might offer bigger parties later.").
@export var capacity := 4

## Random gap between a table freeing up (cash collected) and its next party
## arriving. The spread is what gives service its ebb and flow.
@export var spawn_delay_min := 5.0
@export var spawn_delay_max := 14.0

## First party arrives somewhere in [0, this] after load, so the tables
## don't all seat at the exact same instant.
@export var initial_delay_max := 7.0

## How long a served plate sits on its spot (that guest "eating") before it's
## cleared — per guest, independently, not synchronized across the party.
@export var eat_duration_min := 4.0
@export var eat_duration_max := 7.0

## If every dish in the party gets served within this many seconds of the
## first one (measured first serve -> last serve, not from seating — arriving
## late because of a *different* table shouldn't cost this one anything),
## the whole party's bill gets tightness_bonus_pct on top. Placeholder tuning
## numbers, like every other economy figure here — real tuning is item 26's.
@export var tightness_window := 25.0
@export var tightness_bonus_pct := 0.20

## The floating want label pops up (on reveal, or on a refresh — see action()
## below) and fades back out on its own rather than staying up the whole
## time (2026-08-14, Noah: "the order text above a table needs to go away...
## pop it up when you take their order, but it should fade out"). How long
## it stays fully visible before fading, and how long the fade itself takes.
@export var want_label_visible_duration := 3.0
@export var want_label_fade_duration := 1.5

var _state: State = State.EMPTY
var _party_size := 0
var _pending_dishes: Array[String] = []
var _order_revealed := false
var _pending_value := 0
var _timer := 0.0

## Elapsed seconds since this party sat down — the clock the tightness
## bonus's first/last-serve timestamps are measured against. Simpler than
## wall-clock time (Time.get_ticks_msec()): only ever compared to itself.
var _elapsed := 0.0
var _first_serve_at := -1.0
var _last_serve_at := -1.0

## One entry per dish currently "being eaten": {plate: Plate, spot: Marker3D,
## remaining: float}. Never longer than capacity, since _pending_dishes +
## _eating together can never exceed _party_size <= capacity.
var _eating: Array[Dictionary] = []

var _plate_spots: Array[Marker3D] = []

## One figure per possible guest (capacity 4) — Customer0..3 in the scene,
## positioned around the table's four edges. Showing the first _party_size of
## them and hiding the rest is the actual guest-count readout (2026-08-14,
## Noah: "let's ad the actual number of guests around the table, not just the
## orders") — previously there was only ever one generic figure regardless of
## party size.
var _customers: Array[Node3D] = []
@onready var _want_label: Label3D = $Want
var _want_fade_tween: Tween = null
@onready var _cash: Node3D = $Cash
@onready var _result: Label3D = $Result
var _result_home: Vector3


func _ready() -> void:
	super._ready()
	add_to_group("tables")
	for i in capacity:
		_plate_spots.append(get_node("PlateSpot%d" % i))
		_customers.append(get_node("Customers/Customer%d" % i))
	_result_home = _result.position
	_result.visible = false
	_hide_customers()
	_hide_want_label()
	_cash.visible = false
	_state = State.EMPTY
	_timer = randf() * initial_delay_max
	GameState.phase_changed.connect(_on_phase_changed)


func _show_customers(count: int) -> void:
	for i in _customers.size():
		_customers[i].visible = i < count


func _hide_customers() -> void:
	for c in _customers:
		c.visible = false


## Pops the want label fully visible, refreshed with whatever's currently
## still pending, then lets it fade out on its own — never stays up
## permanently. Safe to call repeatedly (interrupts/replaces any fade
## already in progress rather than layering a second tween on top).
func _flash_want_label() -> void:
	if _pending_dishes.is_empty():
		return
	_update_want_label()
	if _want_fade_tween != null:
		_want_fade_tween.kill()
	_want_label.visible = true
	_want_label.modulate.a = 1.0
	_want_fade_tween = create_tween()
	_want_fade_tween.tween_interval(want_label_visible_duration)
	_want_fade_tween.tween_property(_want_label, "modulate:a", 0.0, want_label_fade_duration)
	_want_fade_tween.tween_callback(func() -> void: _want_label.visible = false)


## Hides the label immediately and kills any in-flight fade — used whenever
## the party's state changes out from under a possibly-mid-fade label (a new
## party seated, closing_out, the party's fully done), so a stale tween can
## never fire later and touch a label that's moved on to a different party.
func _hide_want_label() -> void:
	if _want_fade_tween != null:
		_want_fade_tween.kill()
		_want_fade_tween = null
	_want_label.visible = false


## Re-stagger an already-empty table's wait at the start of each service, so
## a table that happened to hit zero (or go negative) while SERVICE was
## closed doesn't seat someone the instant the sign flips — keeps the same
## ebb-and-flow spread every day, not just the first.
func _on_phase_changed(phase: GameState.Phase) -> void:
	if phase == GameState.Phase.SERVICE and _state == State.EMPTY:
		_timer = randf() * initial_delay_max


func _process(delta: float) -> void:
	match _state:
		State.EMPTY:
			if GameState.phase == GameState.Phase.SERVICE and not GameState.closing_out:
				_timer -= delta
				if _timer <= 0.0:
					_try_seat()
		State.WAITING:
			_elapsed += delta
			var i := _eating.size() - 1
			while i >= 0:
				_eating[i].remaining -= delta
				if _eating[i].remaining <= 0.0:
					(_eating[i].plate as Plate).queue_free()
					_eating.remove_at(i)
				i -= 1
			if _pending_dishes.is_empty() and _eating.is_empty():
				_finish_party()


func interact(player: Player) -> void:
	match _state:
		State.WAITING:
			if player.held_item is Plate:
				if not _pending_dishes.is_empty():
					_serve(player)
			elif player.held_item == null and not _order_revealed:
				_reveal_order()
		State.PAID:
			if player.held_item == null:
				_collect()
		_:
			pass


## Which table number this is — the one bit of identity a respawned Table
## needs back.
func get_config() -> Dictionary:
	return {"table_number": table_number}


func apply_config(config: Dictionary) -> void:
	table_number = config.get("table_number", table_number)


func is_empty() -> bool:
	return _state == State.EMPTY


## Force-resets the whole state machine so a table mid-service (a seated
## party, dishes being eaten, cash waiting) can still be relocated — frees
## anything real (every plate still being eaten), hides the rest, and rearms
## the next-party timer exactly like a freshly freed-up table would.
func clear_contents() -> void:
	for e in _eating:
		(e.plate as Plate).queue_free()
	_eating.clear()
	_pending_dishes.clear()
	_hide_customers()
	_hide_want_label()
	_cash.visible = false
	_result.visible = false
	_pending_value = 0
	_party_size = 0
	_state = State.EMPTY
	_timer = randf_range(spawn_delay_min, spawn_delay_max)


func get_inspect_text() -> String:
	match _state:
		State.WAITING:
			if not _order_revealed:
				return "TABLE %d\n(seated - interact to see their order)" % table_number
			if _pending_dishes.is_empty():
				return "TABLE %d\nEnjoying their meal" % table_number
			return "TABLE %d\nWants: %s" % [table_number, ", ".join(_pending_dishes).to_upper()]
		State.PAID:
			return "TABLE %d\nPaid $%d - collect it" % [table_number, _pending_value]
	return "TABLE %d\n(empty)" % table_number


## Called once by GameState._start_closing_out()'s sweep, the instant the
## guest pool empties (or the sign closes early). Any dish this party hasn't
## been served yet is simply dropped — no penalty, no reward, matching the
## "an unserved dish just earns nothing" rule that's always applied here.
## Whatever's already served and being eaten keeps going untouched and gets
## paid normally once it finishes — an already-served guest never loses their
## meal because a tablemate's order never arrived, which would be blaming the
## wrong thing. If nothing was ever served at all, the party leaves outright
## (mirrors the old single-guest _leave_unserved() exactly). Deliberately
## doesn't rearm _timer either way — no new seatings happen once closing_out
## is true (consume_party() refuses them), so there's nothing left to time.
func leave_if_waiting() -> void:
	if _state != State.WAITING:
		return
	_pending_dishes.clear()
	if _eating.is_empty():
		_hide_customers()
		_hide_want_label()
		_state = State.EMPTY


func _try_seat() -> void:
	var size := GameState.consume_party(mini(GameState.draw_party_size(), capacity))
	if size > 0:
		_seat_party(size)


func _seat_party(size: int) -> void:
	_party_size = size
	_pending_dishes = Recipes.random_party_order(size)
	_order_revealed = false
	_eating.clear()
	_pending_value = 0
	_elapsed = 0.0
	_first_serve_at = -1.0
	_last_serve_at = -1.0
	_state = State.WAITING
	_show_customers(size)
	_hide_want_label()


## Grabbing the order is what tells you (and anyone glancing at the table)
## what's wanted — before that, a waiting table is deliberately a mystery.
## Also prints one order ticket per dish at the nearest ReceiptStation
## (2026-08-14) — the table itself no longer hands over a physical ticket at
## all, since walking a party's worth of individual pickups defeated the
## point of taking the whole order in one interact. The want label pops up
## and fades on its own (see _flash_want_label) rather than staying lit —
## walk back and tap **action** (see action() below) to check again.
func _reveal_order() -> void:
	if _order_revealed:
		return
	_order_revealed = true
	_flash_want_label()
	var station := _find_receipt_station()
	if station != null:
		station.print_tickets(_pending_dishes.duplicate(), table_number)


## Re-pops the want label on demand — the only way to see it again once it's
## faded, short of waiting for the next serve to briefly update its text
## while still hidden. A no-op before the order's ever been revealed, or
## once nothing's left pending (matches get_inspect_text()'s own
## "enjoying their meal" read for that state — nothing to remind anyone of).
func action(_player: Player) -> void:
	if _state == State.WAITING and _order_revealed:
		_flash_want_label()


func _find_receipt_station() -> Node:
	var stations := get_tree().get_nodes_in_group("receipt_stations")
	return stations[0] if not stations.is_empty() else null


func _update_want_label() -> void:
	_want_label.text = "T%d · %s" % [table_number, ", ".join(_pending_dishes).to_upper()]


## Matches a delivered plate to one pending dish — by its tag if that tag
## names something this party still owes, otherwise the oldest pending dish
## (FIFO). Never refuses based on what's actually on the plate (that's what
## the forgiving evaluate() score is for) — only refuses (returns -1) once
## there's truly nothing left pending to deliver here.
func _match_pending_index(plate: Plate) -> int:
	if _pending_dishes.is_empty():
		return -1
	if plate.is_tagged():
		var idx := _pending_dishes.find(plate.tagged_dish())
		if idx != -1:
			return idx
	return 0


func _serve(player: Player) -> void:
	var plate := player.held_item as Plate
	var idx := _match_pending_index(plate)
	if idx == -1:
		return
	var dish: String = _pending_dishes[idx]
	_pending_dishes.remove_at(idx)
	player.drop_item()
	var res := plate.evaluate(Recipes.required_for(dish), Recipes.base_for(dish))
	plate.clear_tag()

	var spot := _free_spot()
	plate.attach_to(spot)
	_pending_value += res.value
	# Recorded at serve, not collect — a receipt marks the order as sold the
	# instant it's fulfilled, independent of when anyone actually walks over
	# to pick up the cash. Deliberately the pre-tightness-bonus value — the
	# bonus is a tip for speed, only ever reflected in the cash actually
	# collected, not in the sales record of what was cooked.
	GameState.record_receipt(res.value)
	if _first_serve_at < 0.0:
		_first_serve_at = _elapsed
	_last_serve_at = _elapsed
	_eating.append({
		"plate": plate,
		"spot": spot,
		"remaining": randf_range(eat_duration_min, eat_duration_max),
	})
	_update_want_label()
	_show_result(res)


func _free_spot() -> Marker3D:
	for spot in _plate_spots:
		var taken := false
		for e in _eating:
			if e.spot == spot:
				taken = true
				break
		if not taken:
			return spot
	return _plate_spots[0]


## The whole party's done — every dish served and finished being eaten.
## Applies the tightness bonus (measured first serve -> last serve, never
## from seating) to the group total, then reveals the cash pickup.
func _finish_party() -> void:
	if _first_serve_at >= 0.0 and _last_serve_at - _first_serve_at <= tightness_window:
		_pending_value = int(round(_pending_value * (1.0 + tightness_bonus_pct)))
	_hide_customers()
	_hide_want_label()
	# Cash appears in the same general spot the plates sat — no amount
	# printed on it; the payoff is finding out when you pick it up (see
	# _collect).
	_cash.visible = true
	_state = State.PAID


func _collect() -> void:
	GameState.add_money(_pending_value)
	GameState.record_cash(_pending_value)
	_cash.visible = false
	_pop_label("+$%d" % _pending_value, Color(0.30, 0.85, 0.35, 1))
	_pending_value = 0
	_party_size = 0
	_state = State.EMPTY
	_timer = randf_range(spawn_delay_min, spawn_delay_max)


## Just the band ("PERFECT!"/"Good"/"Poor") — no dollar amount here, per
## dish, at the moment it's served. The value is revealed once at collect
## (see _collect's "+$N" pop, the group total including any tightness bonus).
func _show_result(res: Dictionary) -> void:
	_pop_label(_BAND_TEXT[res.band], _BAND_COLOR[res.band])


func _pop_label(text: String, color: Color) -> void:
	_result.text = text
	_result.modulate = color
	_result.position = _result_home
	_result.visible = true

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_result, "position:y", _result_home.y + 0.6, 1.2)
	tween.tween_property(_result, "modulate:a", 0.0, 1.2).set_delay(0.4)
	tween.chain().tween_callback(func() -> void: _result.visible = false)
