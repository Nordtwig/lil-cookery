extends CanvasLayer

@onready var _money_label: Label = $Money


func _ready() -> void:
	GameState.money_changed.connect(_on_money_changed)
	_on_money_changed(GameState.money)


func _on_money_changed(total: int) -> void:
	_money_label.text = "$%d" % total
