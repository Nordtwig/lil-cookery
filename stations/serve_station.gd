class_name ServeStation
extends Station

## The pass. A customer waits here wanting the day's dish. Hand over a plate
## and it's scored, paid out, and a floating result shows how it went. Only
## plates are accepted; anything else is ignored.

const _BAND_TEXT := {
	"perfect": "PERFECT!",
	"good": "Good",
	"poor": "Poor",
}
const _BAND_COLOR := {
	"perfect": Color(0.30, 0.85, 0.35),
	"good": Color(0.85, 0.80, 0.20),
	"poor": Color(0.90, 0.50, 0.20),
}

@onready var _result: Label3D = $Result
var _result_home: Vector3


func _ready() -> void:
	_result_home = _result.position
	_result.visible = false


func interact(player: Player) -> void:
	var plate := player.held_item as Plate
	if plate == null:
		return
	player.drop_item()
	var res := plate.evaluate()
	plate.queue_free()
	GameState.add_money(res.value)
	_show_result(res)


func _show_result(res: Dictionary) -> void:
	_result.text = "%s  +$%d" % [_BAND_TEXT[res.band], res.value]
	_result.modulate = _BAND_COLOR[res.band]
	_result.position = _result_home
	_result.visible = true

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_result, "position:y", _result_home.y + 0.6, 1.2)
	tween.tween_property(_result, "modulate:a", 0.0, 1.2).set_delay(0.4)
	tween.chain().tween_callback(func() -> void: _result.visible = false)
