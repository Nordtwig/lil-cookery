class_name Bed
extends Station

## Ends the day — NIGHT -> MORNING, advances GameState.day. No-op outside
## NIGHT (can't turn in mid-service or mid-morning).


func interact(_player: Player) -> void:
	GameState.end_night()


func get_inspect_text() -> String:
	if GameState.phase == GameState.Phase.NIGHT:
		return "BED\nTurn in for the night"
	return "BED\nNot tired yet"
