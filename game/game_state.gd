extends Node

## Session-wide shared state. Autoloaded as `GameState`. For now it just
## holds the money total the serving loop feeds; the night bookkeeping phase
## will read/extend this later.

signal money_changed(total: int)

var money := 0


func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)
