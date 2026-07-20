extends Node

## Session-wide shared state. Autoloaded as `GameState`. For now it just
## holds the money total the serving loop feeds; the night bookkeeping phase
## will read/extend this later.

signal money_changed(total: int)

## Small starting cushion so an early bad-luck run (a crate empties before
## the first dish is served) never hard-locks a session on an emergency
## restock nobody can afford yet.
var money := 15

enum Phase { MORNING, SERVICE }

## Which part of the day it is. Starts MORNING (planning/prep) so a fresh
## session opens with build mode available before anyone's seated. This is
## the minimal slice of the eventual day-phase skeleton (backlog item 24) —
## just the flag build-mode gating needs now. The real skeleton (service
## clock, OpenSign/Bed stations) will come later and drive this same signal
## instead of AppShortcuts' debug toggle.
signal phase_changed(phase: Phase)

var phase: Phase = Phase.MORNING


func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)


func set_phase(new_phase: Phase) -> void:
	if new_phase == phase:
		return
	phase = new_phase
	phase_changed.emit(phase)
