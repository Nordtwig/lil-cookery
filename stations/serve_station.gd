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
@onready var _want_label: Label3D = $Customer/Want
var _result_home: Vector3
var _current_dish := ""


func _ready() -> void:
	_result_home = _result.position
	_result.visible = false
	_next_order()


func interact(player: Player) -> void:
	var plate := player.held_item as Plate
	if plate == null:
		return
	player.drop_item()
	var res := plate.evaluate(Recipes.required_for(_current_dish))
	plate.queue_free()
	GameState.add_money(res.value)
	_show_result(res)
	_next_order()


func _next_order() -> void:
	_current_dish = Recipes.random_name()
	_want_label.text = "Wants: %s" % _current_dish.to_upper()


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
