class_name CuttingBoard
extends SlotStation

## Chops the item in its slot. Hold the **work** button to advance chop_progress
## — a continuous meter with the same Undercut/Good/Perfect/Overcut shape as the
## stove's cook bands. Watching the gauge and pulling (a **pickup** tap, plain
## take) at the right moment is the whole skill; go too far and it overcuts,
## mirroring burnt. Progress only advances while a player actively holds work —
## unlike the stove, nothing chops itself with no hand on the knife, so an
## unattended board never goes bad on its own. Pulling a partially-chopped item
## off doesn't lock it out — set it aside and put it back on any board later to
## keep refining the chop right where chop_progress left off.
##
## Because take (pickup) and chop (work) are now different buttons, there's no
## tap/hold ambiguity to resolve — a pull can never be mistaken for a chop, and
## a chop can never snatch the item away. (Take/place and a dispenser's
## peel/take-whole live on the shared SlotStation, inherited unchanged; a chopped
## `lettuce_head` becomes a dispenser you peel scraps off of, see Item.can_dispense.)

@export var chop_duration := 2.0  # seconds for chop_progress to reach 1.0 (top of Perfect)

## Set by action_hold whenever a real chop happens this frame; the gauge is only
## ever visible while that's true — an item just sitting there between cuts shows
## no gauge, only actively cutting does.
var _chopped_this_frame := false

const _BAND_COLORS := {
	"undercut": Color(0.90, 0.50, 0.20),
	"good": Color(0.85, 0.80, 0.20),
	"perfect": Color(0.30, 0.85, 0.35),
	"overcut": Color(0.15, 0.13, 0.12),
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


func action_hold(_player: Player, delta: float) -> void:
	if _is_chopping():
		held_item.chop(delta, 1.0 / chop_duration)
		_chopped_this_frame = true
		_update_gauge()


func _process(_delta: float) -> void:
	# Physics (where action_hold runs) always finishes before this frame
	# callback, so the flag reliably reflects whether a real chop happened this
	# frame — visible only while actually cutting, not just resting.
	_gauge.visible = _chopped_this_frame
	_chopped_this_frame = false
	super._process(_delta)  # let SlotStation resolve a pending dispense-take, if any


func _on_item_removed(item: Item) -> Item:
	_gauge.visible = false
	if _can_chop(item):
		item.lock_in_chop_score(item.chop_score())
	return item


func _is_chopping() -> bool:
	return held_item != null and _can_chop(held_item)


## True both the first time (CHOP is the pending step) and for a resumed item
## that's already been chopped once (CHOP already recorded, but chop_progress
## carries forward so more cutting keeps having an effect). A finished dispenser
## (a chopped head) is excluded — it's done and meant to be sliced into scraps,
## not re-chopped; that frees the board to peel from it.
func _can_chop(item: Item) -> bool:
	if item.can_dispense():
		return false
	return item.has_step(Ingredients.Verb.CHOP) and (
		item.next_verb() == Ingredients.Verb.CHOP
		or item.step_done(Ingredients.Verb.CHOP)
	)


func _update_gauge() -> void:
	var normalized := clampf(held_item.chop_progress / Item.CHOP_OVERCUT_CAP, 0.0, 1.0)
	_fill_pivot.scale.x = maxf(normalized, 0.001)
	_fill_mat.albedo_color = _BAND_COLORS[held_item.current_chop_band()]
