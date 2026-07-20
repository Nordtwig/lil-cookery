class_name Crate
extends Station

## Ingredient storage (fridge/cupboard) — a finite stock, not an Overcooked-
## style infinite crate. Interact with free hands to take an item, depleting
## stock by one. Once empty, interacting again triggers an emergency restock:
## a short delay, a money cost, then the bin refills to max_stock. This is
## the design doc's "express delivery" pressure valve (§6b), standing in for
## the real day/night ordering system until that exists. Carrying a matching,
## still-unmodified ingredient and interacting instead puts it back — undoes
## the dispense, no cost, no delay, since nothing was actually spent on it.
##
## Carrying a container that accepts this crate's type (a Tray with room)
## instead swipes a fresh item straight onto it, skipping the hand — repeated
## taps batch-fill a tray without a hand-then-merge round trip each time.

@export var item_type := "tomato"
@export var max_stock := 8
@export var restock_cost := 6
@export var restock_delay := 3.0

var stock := 0
var _restocking := false

@onready var _content_mesh: MeshInstance3D = $ContentMesh


func _ready() -> void:
	super._ready()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Ingredients.color_for(item_type)
	_content_mesh.material_override = mat
	stock = max_stock


func interact(player: Player) -> void:
	var carried := player.held_item
	if carried == null:
		if stock <= 0:
			_try_restock()
			return
		var item: Item = Ingredients.scene_for(item_type).instantiate()
		item.item_type = item_type
		player.take_item(item)
		stock -= 1
	elif carried.item_type == item_type and carried.is_unmodified() and stock < max_stock:
		player.drop_item()
		carried.queue_free()
		stock += 1
	elif carried.can_absorb_type(item_type):
		if stock <= 0:
			# Same empty-handed dead-end otherwise: an empty crate should
			# still offer a restock, not silently do nothing just because a
			# tray happens to be in the way of the take.
			_try_restock()
			return
		var item: Item = Ingredients.scene_for(item_type).instantiate()
		item.item_type = item_type
		add_child(item)  # scratch-parented so _ready fires; absorb reparents it
		carried.absorb(item)
		stock -= 1


func _try_restock() -> void:
	if _restocking or GameState.money < restock_cost:
		return
	_restocking = true
	GameState.add_money(-restock_cost)
	await get_tree().create_timer(restock_delay).timeout
	# clear_contents() (a grid-based relocation, mid-restock) sets _restocking
	# back to false to signal "this is stale now" — known rough edge, not
	# actively cancelled, since moving a crate mid-restock is a rare,
	# self-inflicted timing case, not a normal flow.
	if not _restocking:
		return
	stock = max_stock
	_restocking = false


## The per-instance identity a respawned Crate needs back — which ingredient
## it dispenses. max_stock/restock_cost/restock_delay aren't included: no
## instance in the kitchen overrides them today, so there's nothing to carry.
func get_config() -> Dictionary:
	return {"item_type": item_type}


func apply_config(config: Dictionary) -> void:
	item_type = config.get("item_type", item_type)


func is_empty() -> bool:
	return stock <= 0 and not _restocking


func clear_contents() -> void:
	stock = 0
	_restocking = false


func get_inspect_text() -> String:
	if _restocking:
		return "%s\nRestocking..." % item_type.to_upper()
	return "%s\nStock: %d/%d\nRestock cost: $%d" % [item_type.to_upper(), stock, max_stock, restock_cost]
