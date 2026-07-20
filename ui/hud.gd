extends CanvasLayer

@onready var _money_label: Label = $Money
@onready var _phase_label: Label = $Phase

const _PHASE_TEXT := {
	GameState.Phase.MORNING: "MORNING",
	GameState.Phase.SERVICE: "SERVICE",
	GameState.Phase.NIGHT: "NIGHT",
}


func _ready() -> void:
	GameState.money_changed.connect(_on_money_changed)
	_on_money_changed(GameState.money)


func _process(_delta: float) -> void:
	var text := "Day %d - %s" % [GameState.day, _PHASE_TEXT[GameState.phase]]
	if GameState.phase == GameState.Phase.SERVICE:
		text += "  %d guests left" % GameState.guests_remaining
		if GameState.closing_out:
			text += " (closing)"
	_phase_label.text = text


func _on_money_changed(total: int) -> void:
	_money_label.text = "$%d" % total
