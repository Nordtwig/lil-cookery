extends CanvasLayer

## Two-tier money display, replacing a single live-updating total. `Account`
## is deliberately stale — it only ever catches up to GameState.money at the
## moment the books are actually filed (GameState.books_filed), never live
## during the day — so it can't spoil the same "find out how you did"
## payoff the bookkeeping chore itself is built around. `Today` shows "?"
## until then, then the day's net, then slides up and merges into Account
## while it ticks toward the new total — the reveal moment Noah asked for.

const _REVEAL_DURATION := 0.7

@onready var _account_label: Label = $Account
@onready var _today_label: Label = $Today
@onready var _phase_label: Label = $Phase

const _PHASE_TEXT := {
	GameState.Phase.MORNING: "MORNING",
	GameState.Phase.SERVICE: "SERVICE",
	GameState.Phase.NIGHT: "NIGHT",
}

var _account_display := 0.0
var _today_home: Vector2
var _account_home: Vector2


func _ready() -> void:
	_account_display = GameState.money
	_account_label.text = "$%d" % GameState.money
	_today_home = _today_label.position
	_account_home = _account_label.position
	GameState.books_filed.connect(_on_books_filed)


func _process(_delta: float) -> void:
	var text := "Day %d - %s" % [GameState.day, _PHASE_TEXT[GameState.phase]]
	if GameState.phase == GameState.Phase.SERVICE:
		text += "  %d guests left" % GameState.guests_remaining
		if GameState.closing_out:
			text += " (closing)"
	_phase_label.text = text


func _on_books_filed(net: int, silent: bool) -> void:
	if silent:
		# No reveal, no ceremony — the account still ends up correct, it
		# just never gets the satisfying moment, since skipping the office
		# is what forfeits that in the first place.
		_account_display = GameState.money
		_account_label.text = "$%d" % GameState.money
		return

	_today_label.position = _today_home
	_today_label.modulate = Color(0.35, 0.85, 0.4, 1) if net >= 0 else Color(0.9, 0.4, 0.3, 1)
	_today_label.text = "+$%d" % net if net >= 0 else "-$%d" % -net

	var start_value := _account_display
	var end_value := float(GameState.money)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_today_label, "position", _account_home, _REVEAL_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(_today_label, "modulate:a", 0.0, _REVEAL_DURATION * 0.5) \
		.set_delay(_REVEAL_DURATION * 0.5)
	tween.tween_method(_set_account_display, start_value, end_value, _REVEAL_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(_finish_reveal)


func _set_account_display(value: float) -> void:
	_account_display = value
	_account_label.text = "$%d" % roundi(value)


func _finish_reveal() -> void:
	# A small landing punch once the total lands — same "punch" juice
	# vocabulary as Item's chop/season completion elsewhere in this project.
	var tween := create_tween()
	tween.tween_property(_account_label, "scale", Vector2(1.15, 1.15), 0.08)
	tween.tween_property(_account_label, "scale", Vector2.ONE, 0.12)

	_today_label.position = _today_home
	_today_label.modulate = Color(0.7, 0.7, 0.7, 1)
	_today_label.text = "?"
