class_name SpiceRack
extends Station

## Dispenses limited-use seasoning shakers. The rack itself holds a finite
## charge pool: spawning a fresh shaker or topping off a depleted one both
## draw from that pool. When the rack itself runs dry, interacting with free
## hands triggers the same costed emergency restock as ingredient storage
## (Crate) — same pressure valve, same pattern, so players only learn it once.

const SHAKER_SCENE := preload("res://items/spice.tscn")

@export var spice_type := "pepper"
@export var shaker_color := Color(0.32, 0.27, 0.22, 1)
@export var bonus := 0.15
@export var charges_per_shaker := 4
@export var max_rack_charges := 24
@export var restock_cost := 8
@export var restock_delay := 4.0

var rack_charges := 0
var _restocking := false


func _ready() -> void:
	rack_charges = max_rack_charges


func interact(player: Player) -> void:
	var carried := player.held_item
	if carried == null:
		_dispense(player)
	elif carried is Spice and (carried as Spice).spice_type == spice_type:
		_refill(carried as Spice)


func _dispense(player: Player) -> void:
	if rack_charges <= 0:
		_try_restock()
		return
	var amount := mini(charges_per_shaker, rack_charges)
	var shaker: Spice = SHAKER_SCENE.instantiate()
	shaker.spice_type = spice_type
	shaker.color = shaker_color
	shaker.bonus = bonus
	shaker.max_uses = charges_per_shaker
	shaker.uses_remaining = amount
	rack_charges -= amount
	player.take_item(shaker)


func _refill(shaker: Spice) -> void:
	var needed := shaker.max_uses - shaker.uses_remaining
	if needed <= 0:
		return
	if rack_charges <= 0:
		_try_restock()
		return
	var given := mini(needed, rack_charges)
	shaker.add_uses(given)
	rack_charges -= given


func _try_restock() -> void:
	if _restocking or GameState.money < restock_cost:
		return
	_restocking = true
	GameState.add_money(-restock_cost)
	await get_tree().create_timer(restock_delay).timeout
	rack_charges = max_rack_charges
	_restocking = false


func get_inspect_text() -> String:
	if _restocking:
		return "%s RACK\nRestocking..." % spice_type.to_upper()
	return "%s RACK\nCharges: %d/%d\nRestock cost: $%d" % [
		spice_type.to_upper(), rack_charges, max_rack_charges, restock_cost
	]
