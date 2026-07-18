class_name Tray
extends Item

## A player-filled batch container — the carry-over medium that makes
## prepping ahead physically possible (one counter slot holds one item, so
## without a tray, "prep eight tomatoes for the rush" means eight occupied
## counters). Speaks the exact same dispenser grammar as a baked loaf or a
## chopped head (tap peels one out, hold takes the whole tray; carrying a
## matching item, tap merges it in, hold absorbs + takes) — one interaction
## language for everything that holds portions, all via the Item virtuals
## SlotStation already calls.
##
## Holds real Item nodes as children (the plate-components precedent), not
## serialized counts or an abstract stand-in mesh (both tried and rejected
## in earlier drafts, 2026-07-18 — Noah wanted the actual items visible, not
## a pile prop) — seasoning, resumable doneness/chop progress, and every
## other bit of state survives a round trip untouched. Same-type only, raw
## or prepped alike, so a tray works both as prep output (a batch of diced
## tomato) and as bulk transport (a dozen raw patties hauled crate → stove).
## No item_type of its own (like Plate/Spice), so it can never be plated,
## seasoned, cooked, or absorbed into anything else.
##
## Two physical layers, forming a pyramid: 8 slots on the tray floor, then 4
## more nested inward and sitting higher on top of those — a second course
## stacked on the first, not a bigger footprint. Capacity is exactly 12, the
## number the two layers can actually show; every slot always holds (or is
## ready to hold) one real, fully visible item — nothing is ever hidden.

## Bottom course — a 4×2 grid across the tray floor.
const _BOTTOM_SLOTS: Array[Vector3] = [
	Vector3(-0.30, 0.06, -0.16), Vector3(-0.10, 0.06, -0.16), Vector3(0.10, 0.06, -0.16), Vector3(0.30, 0.06, -0.16),
	Vector3(-0.30, 0.06, 0.16), Vector3(-0.10, 0.06, 0.16), Vector3(0.10, 0.06, 0.16), Vector3(0.30, 0.06, 0.16),
]
## Top course — a narrower 2×2 grid, nested inward and raised, resting on
## the bottom course like a second layer of a pyramid.
const _TOP_SLOTS: Array[Vector3] = [
	Vector3(-0.10, 0.16, -0.08), Vector3(0.10, 0.16, -0.08),
	Vector3(-0.10, 0.16, 0.08), Vector3(0.10, 0.16, 0.08),
]
const _SLOTS: Array[Vector3] = _BOTTOM_SLOTS + _TOP_SLOTS
## Full size — items on a tray are meant to read as real portions, not
## shrunk tokens (only the plate shrinks its components, for its own
## presentation reasons).
const _CONTENT_SCALE := 1.0
## Exactly what the two courses can show — every item is always real and
## visible, so capacity can't outrun the display.
const _MAX_CAPACITY := 12

var contents: Array[Item] = []


func can_dispense() -> bool:
	return not contents.is_empty()


## Real ingredients only, matching whatever's already in here (anything goes
## into an empty tray), while there's room. Excludes other trays/plates/
## spices/tickets (no item_type) and whole dispensers (slice the loaf, tray
## the slices).
func can_absorb(item: Item) -> bool:
	return item != null and can_absorb_type(item.item_type)


## Type-only variant — lets a Crate (dispensing straight onto a carried tray)
## or a carried dispenser (peeling straight onto a tray sitting on a station,
## see SlotStation) check the destination before an item exists to check.
func can_absorb_type(type: String) -> bool:
	if type == "" or Ingredients.dispenses_for(type) != "":
		return false
	if contents.size() >= _MAX_CAPACITY:
		return false
	return contents.is_empty() or contents[0].item_type == type


func absorb(item: Item) -> void:
	item.attach_to(self)
	contents.append(item)
	_arrange()


## Hands back the most recently added item, full-sized again, with all its
## state intact — it was never anything but itself while it sat here.
func dispense(_host: Node) -> Item:
	var item: Item = contents.pop_back()
	item.scale = Vector3.ONE
	return item


## An emptied tray is still a tray — set it down, refill it, or return it
## to the rack.
func frees_when_empty() -> bool:
	return false


## For TrayRack's return-to-source check: an empty tray can go back.
func is_unmodified() -> bool:
	return contents.is_empty()


func _arrange() -> void:
	for i in contents.size():
		contents[i].scale = Vector3.ONE * _CONTENT_SCALE
		contents[i].position = _SLOTS[i]
		contents[i].rotation = Vector3.ZERO


func get_inspect_text() -> String:
	if contents.is_empty():
		return "TRAY (empty)"
	var lines := ["TRAY (%d/%d) — %s" % [contents.size(), _MAX_CAPACITY, contents[0].item_type.capitalize()]]
	for c in contents:
		lines.append("- %s: %d%%" % [c.item_type.capitalize(), int(round(c.quality_value() * 100))])
	return "\n".join(lines)
