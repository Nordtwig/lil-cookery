class_name Item
extends Node3D

## A carryable thing. Items have no physics — they are always parented to
## either a station slot or a player's hold point.

@export var item_type := ""
@export var color := Color.WHITE
## Whether a cook station can cook this item. Non-cookable items (cold
## components like cheese) just sit on a stove doing nothing.
@export var cookable := false

# Cooking runs on a 0..BURNT_CAP "doneness" scale. Bands (design doc §4,
# plus Burnt as the overcook consequence). The Perfect window is generous —
# reward good play, don't punish.
const POOR_MAX := 0.5
const GOOD_MAX := 0.8
const PERFECT_MAX := 1.05
const BURNT_CAP := 1.25

## True until the item is pulled from a cook station (or has burned). Stops
## it from re-cooking if placed back on a stove.
var is_raw := true
var doneness := 0.0
## Set when cooking finishes: "poor" / "good" / "perfect" / "burnt". Empty
## while raw or for never-cooked components. Read later for dish scoring.
var quality := ""

@onready var _mesh: MeshInstance3D = $Mesh

var _mat: StandardMaterial3D


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mesh.material_override = _mat
	_update_tint()


## Advance cooking by `delta` seconds at the given rate (doneness/sec),
## re-tinting toward cooked/charred. Caps at Burnt so an abandoned item
## settles at low value rather than vanishing.
func cook(delta: float, rate: float) -> void:
	doneness = minf(doneness + rate * delta, BURNT_CAP)
	_update_tint()


## 0..1 contribution of this component to a dish. Cooked items score by
## band; a raw-but-cookable item scored badly (undercooked); a non-cookable
## cold component (e.g. cheese) is fine as-is at a neutral-good value.
func quality_value() -> float:
	match quality:
		"perfect": return 1.0
		"good": return 0.7
		"poor": return 0.4
		"burnt": return 0.2
	if cookable:
		return 0.3
	return 0.8


func current_band() -> String:
	if doneness < POOR_MAX:
		return "poor"
	elif doneness < GOOD_MAX:
		return "good"
	elif doneness < PERFECT_MAX:
		return "perfect"
	return "burnt"


## Freeze the current cooking result into the item.
func finish_cook() -> void:
	is_raw = false
	quality = current_band()


func _update_tint() -> void:
	if not cookable:
		_mat.albedo_color = color
		return
	# Raw reads as a washed-out version of the item's color; it saturates to
	# the full color right as it hits done (doneness 1.0 = top of Perfect),
	# then darkens to charcoal as it burns. Peak appetising == peak score.
	var pale := color.lerp(Color(0.90, 0.85, 0.80), 0.55)
	var cooked: Color
	if doneness <= 1.0:
		cooked = pale.lerp(color, clampf(doneness, 0.0, 1.0))
	else:
		var char_t := clampf((doneness - 1.0) / (BURNT_CAP - 1.0), 0.0, 1.0)
		cooked = color.lerp(Color(0.08, 0.07, 0.06), char_t)
	_mat.albedo_color = cooked


func attach_to(new_parent: Node3D) -> void:
	if get_parent() != null:
		get_parent().remove_child(self)
	new_parent.add_child(self)
	position = Vector3.ZERO
	rotation = Vector3.ZERO
