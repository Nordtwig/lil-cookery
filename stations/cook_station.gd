class_name CookStation
extends SlotStation

## A stove. Place a raw cookable item and it cooks on its own; a flat gauge
## in front shows the band (Poor → Good → Perfect → Burnt). Pull it at the
## right moment. Leaving it too long burns it to a low-value item — the cost
## is systemic (lost quality), never a hard fail.

## Seconds for doneness to travel from raw (0) to the top of the Perfect
## window (1.0). The Perfect band is ~1.5s of this at the default.
@export var cook_duration := 6.0

const _BAND_COLORS := {
	"poor": Color(0.90, 0.50, 0.20),
	"good": Color(0.85, 0.80, 0.20),
	"perfect": Color(0.30, 0.85, 0.35),
	"burnt": Color(0.15, 0.13, 0.12),
}

@onready var _gauge: Node3D = $Gauge
@onready var _fill_pivot: Node3D = $Gauge/FillPivot
@onready var _fill_mesh: MeshInstance3D = $Gauge/FillPivot/Fill

var _fill_mat: StandardMaterial3D


func _ready() -> void:
	_fill_mat = StandardMaterial3D.new()
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mesh.material_override = _fill_mat
	_gauge.visible = false


func _process(delta: float) -> void:
	if not _is_cooking():
		return
	held_item.cook(delta, 1.0 / cook_duration)
	_update_gauge()


func _on_item_placed(item: Item) -> void:
	_gauge.visible = _is_cookable(item)
	if _gauge.visible:
		_update_gauge()


func _on_item_removed(item: Item) -> void:
	_gauge.visible = false
	if _is_cookable(item):
		item.finish_cook()


func _is_cooking() -> bool:
	return held_item != null and _is_cookable(held_item)


func _is_cookable(item: Item) -> bool:
	return item.cookable and item.is_raw


func _update_gauge() -> void:
	var normalized := clampf(held_item.doneness / Item.BURNT_CAP, 0.0, 1.0)
	_fill_pivot.scale.x = maxf(normalized, 0.001)
	_fill_mat.albedo_color = _BAND_COLORS[held_item.current_band()]
