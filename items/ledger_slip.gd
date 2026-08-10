class_name LedgerSlip
extends Item

## A physical document carried from a LedgerAccumulator fixture (Till/
## ReceiptSpike/InvoiceFolder) to LedgerDesk. One script, three distinct
## scenes (ledger_slip_cash.tscn/ledger_slip_receipts.tscn/
## ledger_slip_invoices.tscn — a coin stack, a paper-receipt stack, a folder
## stack, matching each fixture's own pile shape at hand scale) — same
## pattern as Ingredients' per-type item scenes (tomato.tscn vs bread.tscn,
## one shared item.gd). Deliberately shows only its category label while
## carried, never the amount — the number is what the desk reveals, not the
## slip itself, so grabbing one doesn't quietly defeat the whole "carry it
## to find out" point of the chore.

## "cash" | "receipts" | "invoices" — matches GameState.ledger_value().
var category := ""

## Snapshot at pickup time, for BookkeepingDesk.file_slip() to read once
## filed — not shown on the slip itself (see above).
var amount := 0

## Shown on the slip so a carried slip is identifiable before it's ever
## filed, e.g. "TILL".
var display_name := ""

@onready var _label: Label3D = $Label


func _ready() -> void:
	super._ready()
	_label.text = display_name


func get_inspect_text() -> String:
	return "%s\n(carry to the bookkeeping desk to file it)" % display_name
