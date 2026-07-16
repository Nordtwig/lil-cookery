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

@onready var _customer: Node3D = $Customer
@onready var _want_label: Label3D = $Customer/Want
@onready var _plate_spot: Marker3D = $PlateSpot
@onready var _cash: Node3D = $Cash
@onready var _result: Label3D = $Result
var _result_home: Vector3


func _ready() -> void:
	_result_home = _result.position
	_result.visible = false
	_customer.visible = false
	_want_label.visible = false
	_cash.visible = false
	_state = State.EMPTY
	_timer = randf() * initial_delay_max


func _process(delta: float) -> void:
	match _state:
		State.EMPTY:
			_timer -= delta
			if _timer <= 0.0:
				_seat_customer()
		State.EATING:
			_eat_timer -= delta
			if _eat_timer <= 0.0:
				_finish_eating()


func interact(player: Player) -> void:
	match _state:
		State.WAITING:
			if player.held_item == null:
				_reveal_order()
				var ticket: OrderTicket = TICKET_SCENE.instantiate()
				ticket.dish = _dish
				ticket.table_number = table_number
				player.take_item(ticket)
			elif player.held_item is Plate:
				_serve(player)
		State.PAID:
			if player.held_item == null:
				_collect()
		_:
			pass


func get_inspect_text() -> String:
	match _state:
		State.WAITING:
			if _order_revealed:
				return "TABLE %d\nWants: %s" % [table_number, _dish.to_upper()]
			return "TABLE %d\n(seated — grab a ticket to see their order)" % table_number
		State.EATING:
			return "TABLE %d\nEnjoying their %s" % [table_number, _dish.to_upper()]
		State.PAID:
			return "TABLE %d\nPaid $%d — collect it" % [table_number, _pending_value]
	return "TABLE %d\n(empty)" % table_number


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


func _show_result(res: Dictionary) -> void:
	_pop_label("%s  +$%d" % [_BAND_TEXT[res.band], res.value], _BAND_COLOR[res.band])


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
