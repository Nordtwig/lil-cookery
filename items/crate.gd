class_name Crate
extends Item

## A carryable crate of one fixed ingredient type — the storage room's
## shelf/stack unit, replacing the old fixed-Station Crate. Speaks the same
## dispenser grammar as a baked loaf or a Tray (SlotStation only ever talks
## to these six methods), so every existing tap/hold/merge/take-whole
## interaction on any SlotStation (a Shelf, a bay CrateStack, even a plain
## Counter) works on a Crate with zero new interaction code — hold E takes
## the whole crate, a tap takes one item out or puts one back.
##
## No item_type of its own (like Plate/Spice/Tray) — contained_type is a
## separate field, so a Crate never looks like a real plateable ingredient
## itself (Plate.can_add already excludes anything with item_type == "").
##
## Restocking (an empty crate topped up for a fee, mid-service) lives here
## now rather than on a fixed station, since a crate might be sitting on a
## shelf, a bay stack, or in a player's hands when it runs dry — the station
## holding it just forwards the trigger (see CrateStack.action_hold).

@export var contained_type := "tomato"
@export var starting_stock := 8
@export var restock_amount := 4
@export var restock_cost := 6
@export var restock_delay := 3.0

var stock := 0
var _restocking := false

@onready var _content_mesh: MeshInstance3D = $ContentMesh


func _ready() -> void:
	super._ready()
	stock = starting_stock
	# The crate body (wood-brown) and the visible content peek are both
	# plain siblings of Mesh/Pieces, not routed through Item's food-tint
	# system (which those stay empty stubs for, like Plate/Spice/Tray) —
	# a crate isn't a food item itself, so it manages its own materials
	# directly instead.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Ingredients.color_for(contained_type)
	_content_mesh.material_override = mat


func can_dispense() -> bool:
	return stock > 0


## Only a still-unmodified matching ingredient can go back in — undoes a
## take with no cost, same as the old station-based Crate, since nothing
## was actually spent on an item that was never touched.
func can_absorb(item: Item) -> bool:
	return item != null and can_absorb_type(item.item_type) and item.is_unmodified()


func can_absorb_type(type: String) -> bool:
	return type == contained_type


func absorb(item: Item) -> void:
	item.queue_free()
	stock += 1


## Overridden because contained_type — not item_type, which a Crate never
## has — is what actually names the portion this crate hands out. This is
## the one method a Crate has to override for the generic "station holds a
## dispenser, carried container swipes a portion straight onto it" path
## (SlotStation.interact()) to work at all — the base Item implementation
## infers this from item_type, which is always "" here on purpose.
func dispensed_portion_type() -> String:
	return contained_type


func dispense(host: Node) -> Item:
	var portion: Item = Ingredients.scene_for(contained_type).instantiate()
	portion.item_type = contained_type
	host.add_child(portion)
	stock -= 1
	return portion


## A crate persists once emptied — it's still a crate, just waiting on a
## restock, not consumed the way a spent loaf/head is.
func frees_when_empty() -> bool:
	return false


func is_unmodified() -> bool:
	return false


## Called by whatever station is currently holding this crate, once it's
## resolved a held work-button press past the tap/hold grace window (see
## CrateStack.action_hold) — "the work for an empty crate is to express
## restock it," Noah's framing. No-op if already restocking, not actually
## empty, or unaffordable.
func try_restock() -> void:
	if _restocking or stock > 0 or GameState.money < restock_cost:
		return
	_restocking = true
	GameState.add_money(-restock_cost)
	GameState.record_invoice_spend(restock_cost)
	await get_tree().create_timer(restock_delay).timeout
	if not is_inside_tree():
		return  # freed mid-restock (trashed, e.g.) — nothing left to update
	stock += restock_amount
	_restocking = false


func get_inspect_text() -> String:
	if _restocking:
		return "%s CRATE\nRestocking..." % contained_type.to_upper()
	if stock <= 0:
		return "%s CRATE\n(empty)\nHold action to express-restock: +%d for $%d" % [
			contained_type.to_upper(), restock_amount, restock_cost]
	return "%s CRATE\nStock: %d" % [contained_type.to_upper(), stock]


func hint_name() -> String:
	return "Crate of %s" % contained_type.capitalize()
