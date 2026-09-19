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
## One flat layer, 8 slots (2026-08-14 — down from the old two-course
## 8+4=12 pyramid). Capacity is now **slot cost**, not a flat item count: a
## plain portion costs 1 slot; a whole dispenser (a raw or baked loaf, a raw
## or chopped head) costs 2, so at most 4 fit — "bigger" items claim more of
## the tray, Noah's own framing for why this reads as fair rather than
## arbitrary ("they contain X amount of ingredients, so could be logically
## considered bigger... we could see it as them taking up more slots on the
## tray itself"), and explicitly meant to extend per-type later (a
## hypothetical future ingredient could cost more than 2). Whole dispensers
## were previously excluded from trays entirely ("slice the loaf, tray the
## slices") — that restriction is gone; a tray now holds either portions or
## whole dispensers (never mixed, same-type-only rule unchanged), and taking
## one off a tray of dispensers hands over the whole thing — dispense() only
## ever returns whatever Item is actually stored, so this needed no special
## casing once can_absorb_type stopped excluding dispenser types.

## A 4×2 grid across the tray floor — the only layer now.
const _SLOTS: Array[Vector3] = [
	Vector3(-0.30, 0.06, -0.16), Vector3(-0.10, 0.06, -0.16), Vector3(0.10, 0.06, -0.16), Vector3(0.30, 0.06, -0.16),
	Vector3(-0.30, 0.06, 0.16), Vector3(-0.10, 0.06, 0.16), Vector3(0.10, 0.06, 0.16), Vector3(0.30, 0.06, 0.16),
]
## Full size — items on a tray are meant to read as real portions, not
## shrunk tokens (only the plate shrinks its components, for its own
## presentation reasons).
const _CONTENT_SCALE := 1.0
## Total slot budget the 8 floor positions represent — not an item count.
const _SLOT_CAPACITY := 8

var contents: Array[Item] = []


func can_dispense() -> bool:
	return not contents.is_empty()


## Real ingredients only, matching whatever's already in here (anything goes
## into an empty tray), while there's slot room. Excludes other trays/
## plates/spices/tickets (no item_type); whole dispensers are allowed now,
## just at double the slot cost of a portion (see _slot_cost).
func can_absorb(item: Item) -> bool:
	return item != null and can_absorb_type(item.item_type)


## Type-only variant — lets a Crate (dispensing straight onto a carried tray)
## or a carried dispenser (peeling straight onto a tray sitting on a station,
## see SlotStation) check the destination before an item exists to check.
func can_absorb_type(type: String) -> bool:
	if type == "":
		return false
	if not (contents.is_empty() or contents[0].item_type == type):
		return false
	return _used_slots() + _slot_cost(type) <= _SLOT_CAPACITY


func absorb(item: Item) -> void:
	item.attach_to(self)
	contents.append(item)
	_arrange()


## Hands back the most recently added item, full-sized again, with all its
## state intact — it was never anything but itself while it sat here. For a
## tray of whole dispensers this hands over the entire dispenser, same as
## for a tray of portions — there's no partial-item concept here at all,
## peeling a portion off something the tray holds only ever happens once
## it's out of the tray and sitting somewhere else.
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


func _used_slots() -> int:
	var used := 0
	for c in contents:
		used += _slot_cost(c.item_type)
	return used


## A whole dispenser (a loaf, a head) costs 2 slots; a plain portion costs 1.
## The one place this ever needs to change if a future ingredient wants a
## different cost.
func _slot_cost(type: String) -> int:
	return 2 if Ingredients.dispenses_for(type) != "" else 1


func _arrange() -> void:
	var slot := 0
	for item in contents:
		item.scale = Vector3.ONE * _CONTENT_SCALE
		item.position = _SLOTS[slot]
		item.rotation = Vector3.ZERO
		slot += _slot_cost(item.item_type)


func get_inspect_text() -> String:
	if contents.is_empty():
		return "TRAY (empty)"
	var lines := ["TRAY (%d/%d slots) - %s" % [_used_slots(), _SLOT_CAPACITY, contents[0].item_type.capitalize()]]
	for c in contents:
		lines.append("- %s: %d%%" % [c.item_type.capitalize(), int(round(c.quality_value() * 100))])
	return "\n".join(lines)


func hint_name() -> String:
	return "Tray" if contents.is_empty() else "Tray of %s" % contents[0].hint_name()
