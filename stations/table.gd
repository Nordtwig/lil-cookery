class_name Table
extends Station

## A dining table — the pass, the order, and the till all in one. Replaces the
## single central ServeStation with several independent tables you deliver to.
##
## Ebb and flow: a table sits EMPTY, a customer arrives after a random wait
## with an order (WAITING) — the order itself stays hidden until a ticket is
## grabbed for it, so knowing what a table wants costs a trip over. Deliver a
## plate and it's scored against THIS table's live order (forgiving as ever);
## the plate stays sitting on the table while the customer eats (EATING), then
## they leave and the payment appears where the plate sat, as a physical
## pickup (PAID). Collecting the cash (a separate empty-handed interact) adds
## it to the total and frees the table, which starts the wait for its next
## customer.
##
## No impatience timer, no angry-leave — an unserved or uncollected table just
## sits there earning nothing, a systemic nudge, never a punishment. The
## uncollected cash blocks the next customer, so busing your tables is what
## keeps them turning over.

enum State { EMPTY, WAITING, EATING, PAID }

const TICKET_SCENE := preload("res://items/order_ticket.tscn")

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

## Random gap between a table freeing up (cash collected) and its next customer
## arriving. The spread is what gives service its ebb and flow.
@export var spawn_delay_min := 5.0
@export var spawn_delay_max := 14.0

## First customer arrives somewhere in [0, this] after load, so the tables
## don't all seat at the exact same instant.
@export var initial_delay_max := 7.0

## How long a served plate sits on the table (customer "eating") before they
## leave and the cash appears. Random within the range for a bit of variety.
@export var eat_duration_min := 4.0
@export var eat_duration_max := 7.0

var _state: State = State.EMPTY
var _dish := ""
var _order_revealed := false
var _pending_value := 0
var _pending_band := ""
var _timer := 0.0
var _eat_timer := 0.0
var _plate: Plate = null

## A ticket currently sitting physically on the table (set down by a player),
## or null. Once the order's revealed, the want label stays up regardless of
## whether a ticket is out being carried or resting here — see interact().
var _ticket: OrderTicket = null

@onready var _customer: Node3D = $Customer
@onready var _want_label: Label3D = $Customer/Want
@onready var _plate_spot: Marker3D = $PlateSpot
@onready var _ticket_spot: Marker3D = $TicketSpot
@onready var _cash: Node3D = $Cash
@onready var _result: Label3D = $Result
var _result_home: Vector3


func _ready() -> void:
	super._ready()
	add_to_group("tables")
	_result_home = _result.position
	_result.visible = false
	_customer.visible = false
	_want_label.visible = false
	_cash.visible = false
	_state = State.EMPTY
	_timer = randf() * initial_delay_max
	GameState.phase_changed.connect(_on_phase_changed)


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
				if _timer <= 0.0 and GameState.consume_guest():
					_seat_customer()
		State.EATING:
			_eat_timer -= delta
			if _eat_timer <= 0.0:
				_finish_eating()


func interact(player: Player) -> void:
	match _state:
		State.WAITING:
			if player.held_item == null:
				if _ticket != null:
					# A ticket is already sitting on the table — pick it back
					# up, same as taking anything off any other station's slot.
					var t := _ticket
					_ticket = null
					player.take_item(t)
				else:
					_reveal_order()
					var ticket: OrderTicket = TICKET_SCENE.instantiate()
					ticket.dish = _dish
					ticket.table_number = table_number
					player.take_item(ticket)
			elif player.held_item is Plate:
				_serve(player)
			elif player.held_item is OrderTicket and (player.held_item as OrderTicket).table_number == table_number and _ticket == null:
				# Set this table's own ticket down — it just sits there
				# physically, like an item on any other station's slot, until
				# picked back up. The want label reflects "order revealed," not
				# "ticket currently out," so it's untouched by this — a ticket
				# for a different table is silently refused.
				var t := player.drop_item() as OrderTicket
				t.attach_to(_ticket_spot)
				_ticket = t
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
## customer, a ticket out, a plate being eaten, cash waiting) can still be
## relocated — frees anything real (ticket/plate), hides the rest, and rearms
## the next-customer timer exactly like a freshly freed-up table would.
func clear_contents() -> void:
	if _ticket != null:
		_ticket.queue_free()
		_ticket = null
	if _plate != null:
		_plate.queue_free()
		_plate = null
	_customer.visible = false
	_want_label.visible = false
	_cash.visible = false
	_result.visible = false
	_pending_value = 0
	_state = State.EMPTY
	_timer = randf_range(spawn_delay_min, spawn_delay_max)


func get_inspect_text() -> String:
	match _state:
		State.WAITING:
			if _order_revealed:
				return "TABLE %d\nWants: %s" % [table_number, _dish.to_upper()]
			return "TABLE %d\n(seated - grab a ticket to see their order)" % table_number
		State.EATING:
			return "TABLE %d\nEnjoying their %s" % [table_number, _dish.to_upper()]
		State.PAID:
			return "TABLE %d\nPaid $%d - collect it" % [table_number, _pending_value]
	return "TABLE %d\n(empty)" % table_number


## Called once by GameState._start_closing_out()'s sweep, the instant the
## guest pool empties (or the sign closes early) — if this table happens to
## already be WAITING at that exact moment, the customer leaves with no
## penalty, same as any other unserved table. A no-op otherwise, including
## for a table that's mid-draw of the very guest that triggered the sweep —
## GameState calls this before that table's own _seat_customer() has run,
## so it's still EMPTY here, not WAITING (see consume_guest()'s ordering
## note — getting this backwards once kicked a customer the instant they
## sat down).
func leave_if_waiting() -> void:
	if _state == State.WAITING:
		_leave_unserved()


## Deliberately doesn't rearm _timer — no new seatings happen once
## closing_out is true (consume_guest() refuses them), so there's nothing
## left to time.
func _leave_unserved() -> void:
	if _ticket != null:
		_ticket.queue_free()
		_ticket = null
	_customer.visible = false
	_want_label.visible = false
	_state = State.EMPTY


func _seat_customer() -> void:
	_dish = Recipes.random_name()
	_order_revealed = false
	_state = State.WAITING
	_customer.visible = true
	_want_label.text = "T%d · %s" % [table_number, _dish.to_upper()]
	_want_label.visible = false


## Grabbing a ticket is what tells you (and anyone glancing at the table)
## what's wanted — before that, a waiting table is deliberately a mystery.
func _reveal_order() -> void:
	if _order_revealed:
		return
	_order_revealed = true
	_want_label.visible = true


func _serve(player: Player) -> void:
	var plate := player.held_item as Plate
	player.drop_item()
	var res := plate.evaluate(Recipes.required_for(_dish), Recipes.base_for(_dish))

	# A ticket left sitting on the table is stale the moment its order is
	# actually resolved — free it rather than leaving a dead object behind.
	if _ticket != null:
		_ticket.queue_free()
		_ticket = null

	# The plate stays put and visible while the customer "eats" it — no
	# instant vanish — rather than being freed immediately. The checklist
	# was only ever a build-time aid, so it goes away once served.
	plate.clear_tag()
	plate.attach_to(_plate_spot)
	_plate = plate
	_pending_value = res.value
	_pending_band = res.band
	_state = State.EATING
	_eat_timer = randf_range(eat_duration_min, eat_duration_max)
	_want_label.visible = false
	_show_result(res)


func _finish_eating() -> void:
	_plate.queue_free()
	_plate = null
	_customer.visible = false
	# Cash appears in the same spot the plate just sat — no amount printed on
	# it; the payoff is finding out when you pick it up (see _collect).
	_cash.visible = true
	_state = State.PAID


func _collect() -> void:
	GameState.add_money(_pending_value)
	_cash.visible = false
	_pop_label("+$%d" % _pending_value, Color(0.30, 0.85, 0.35, 1))
	_pending_value = 0
	_state = State.EMPTY
	_timer = randf_range(spawn_delay_min, spawn_delay_max)


## Just the band ("PERFECT!"/"Good"/"Poor") — no dollar amount here. The value
## is already revealed once at collect (see _collect's "+$N" pop); repeating it
## at serve time is redundant, and collect is where the payoff should land.
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
