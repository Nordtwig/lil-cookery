class_name Pan
extends Item

## A frying pan: the vessel for one thing on a stove. Nothing goes on a burner bare
## any more - a stove holds a Pot or a Pan, and the pan holds the food. Capacity one,
## so two things frying is two pans; the constraint is equipment, not a clock.
##
## The stove never looks inside: `cook_subject()` hands it the content, and it cooks,
## gauges, flips and scores that as if it sat on the burner directly. The pan itself is
## inert - it keeps its own gray, never browns, never scores.
##
## Grammar mirrors the pot: tap acts on the content (take it out, put something in,
## plate it, scoop it onto a tray), hold lifts the pan with whatever is in it. Speaks
## the dispenser grammar for that: `can_dispense()` while it holds something,
## `can_absorb()` an empty pan and something a stove would act on - a raw patty, a
## jointed chicken piece, a bread slice to toast; a tomato is refused, the stove does
## nothing with one. A whole bird has no COOK step (it is jointed raw, not roasted), so
## it is refused by the same rule. Equipment, orderable, never freed.

const _CONTENT_SCALE := 0.85

var content: Item = null

@onready var _seat: Marker3D = $Seat


func is_vessel() -> bool:
	return true


func cook_subject() -> Item:
	return content


# --- dispenser grammar ---

func can_dispense() -> bool:
	return content != null


func dispensed_portion_type() -> String:
	return content.item_type if content != null else ""


## Only something heat would act on right now - a raw patty yes, a whole potato no
## (the board first), a baked loaf no (it's for slicing).
func can_absorb(item: Item) -> bool:
	return item != null and content == null and item.item_type != "" and item.heatable()


## The type-only form for deposit-before-the-item-exists (a raw bird peeling a piece
## straight into the pan): a COOK step of its own, or a STOVE recipe that turns it
## into another type.
func can_absorb_type(type: String) -> bool:
	if content != null or type == "":
		return false
	return Ingredients.Verb.COOK in Ingredients.steps_for(type) or Ingredients.stove_output_for(type) != ""


func absorb(item: Item) -> void:
	content = item
	item.attach_to(_seat)
	item.scale = Vector3.ONE * _CONTENT_SCALE


func dispense(_host: Node) -> Item:
	var out := content
	content = null
	out.scale = Vector3.ONE
	return out


func frees_when_empty() -> bool:
	return false


func is_unmodified() -> bool:
	return content == null


func _update_tint() -> void:
	_mat.albedo_color = color


func hint_name() -> String:
	return "Pan of %s" % content.hint_name() if content != null else "Pan"


func get_inspect_text() -> String:
	if content == null:
		return "PAN (empty)"
	return "PAN\n" + content.get_inspect_text()
