class_name OrderTicket
extends Item

## A physical, carryable order slip. Grabbed empty-handed from a Table (matches
## that table's current order), then tagged onto a plate — carry the ticket to
## a station holding a plate, or vice versa — to attach a live checklist showing
## the dish and which required components are already there. The ticket is
## consumed the instant it's tagged; the tag is purely an aid for the player,
## never binding — a plate still scores against whatever table it's actually
## delivered to.
##
## `table_number` identifies which table the slip is for, so several live orders
## stay tellable apart once there's more than one going at once. No floating
## label of its own — you already see the order the moment you pick the ticket
## up (the table reveals it) and again once it's tagged onto a plate; the
## ticket's own dish/table is inspect-only (see get_inspect_text below).

@export var dish := ""
@export var table_number := 0


## "T2 · BURGER" when it came from a numbered table, else just the dish.
func table_label() -> String:
	return "T%d" % table_number if table_number > 0 else ""


func _header() -> String:
	var tl := table_label()
	return "%s · %s" % [tl, dish.to_upper()] if tl != "" else dish.to_upper()


func get_inspect_text() -> String:
	return "ORDER TICKET\n%s" % _header()
