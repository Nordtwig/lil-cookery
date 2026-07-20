class_name OpenSign
extends Station

## Flips the day from MORNING (planning) to SERVICE (dining room open) — and
## flipped again mid-SERVICE, closes early instead (see GameState.close_early
## for why this is worth keeping even once the guest pool alone decides a
## normal day's end). Either player can do it — "open when ready, co-op
## friendly," no confirmation or two-player requirement.


func interact(_player: Player) -> void:
	match GameState.phase:
		GameState.Phase.MORNING:
			GameState.start_service()
		GameState.Phase.SERVICE:
			GameState.close_early()
		_:
			pass


func get_inspect_text() -> String:
	match GameState.phase:
		GameState.Phase.MORNING:
			return "OPEN SIGN\nFlip to start service"
		GameState.Phase.SERVICE:
			if GameState.closing_out:
				return "OPEN SIGN\nClosing up..."
			return "OPEN SIGN\nFlip to close early"
		GameState.Phase.NIGHT:
			return "OPEN SIGN\nClosed for the night"
	return "OPEN SIGN"
