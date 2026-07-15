extends Node

## Session-wide shared state. Autoloaded as `GameState`. For now it just
## holds the money total the serving loop feeds; the night bookkeeping phase
## will read/extend this later.

signal money_changed(total: int)

## Small starting cushion so an early bad-luck run (a crate empties before
## the first dish is served) never hard-locks a session on an emergency
## restock nobody can afford yet.
var money := 15


func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)
