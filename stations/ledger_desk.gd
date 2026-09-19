class_name LedgerDesk
extends Station

## A physical staging surface — carry a LedgerSlip here and set it down,
## like plating a dish onto a Plate. Holds up to one slip per category
## (cash/receipts/invoices) simultaneously. BookkeepingComputer (placed next
## to this) reads missing()/is_complete() to decide whether it's ready to
## process, and calls clear() once it has.
##
## Only categories with real activity today are ever required — a category
## GameState.ledger_value() reports as 0 has no document to begin with
## (LedgerAccumulator refuses to hand one out), so it's simply never counted
## against completeness. On a day with no ingredient purchases at all,
## "invoices" is never asked for.

const _CATEGORIES := ["cash", "receipts", "invoices"]

var _slips: Dictionary = {}  # category -> LedgerSlip


func hints(player: Player) -> Array[Dictionary]:
	if player.held_item is LedgerSlip and not _slips.has((player.held_item as LedgerSlip).category):
		return [hint("interact", "Put down the %s" % player.held_item.hint_name().to_lower())]
	return []


func interact(player: Player) -> void:
	if not (player.held_item is LedgerSlip):
		return
	var slip := player.held_item as LedgerSlip
	if _slips.has(slip.category):
		# Already have this document — a second trip for the same one is a
		# harmless no-op, the slip stays in hand rather than doubling up.
		return
	player.drop_item()
	slip.attach_to(_spot(slip.category))
	_slips[slip.category] = slip


## Categories with real activity today that aren't sitting here yet — what
## BookkeepingComputer is still waiting on. A category with nothing to
## report is never included, whether or not it's physically present.
func missing() -> Array[String]:
	var out: Array[String] = []
	for category in _CATEGORIES:
		if GameState.ledger_value(category) > 0 and not _slips.has(category):
			out.append(category)
	return out


func is_complete() -> bool:
	return missing().is_empty()


## Called by BookkeepingComputer once it's actually processed everything —
## the slips' only job was to sit here and prove each document was fetched.
func clear() -> void:
	for slip in _slips.values():
		slip.queue_free()
	_slips.clear()


func is_empty() -> bool:
	return _slips.is_empty()


func clear_contents() -> void:
	clear()


func get_inspect_text() -> String:
	var lines := ["LEDGER DESK"]
	for category in _CATEGORIES:
		if GameState.ledger_value(category) <= 0:
			lines.append("  %s: (none today)" % category.capitalize())
		else:
			var mark := "x" if _slips.has(category) else " "
			lines.append("[%s] %s" % [mark, category.capitalize()])
	return "\n".join(lines)


func _spot(category: String) -> Marker3D:
	return get_node(category.capitalize() + "Spot")
