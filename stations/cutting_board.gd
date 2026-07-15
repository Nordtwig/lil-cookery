class_name CuttingBoard
extends SlotStation

## Chops the item in its slot. Hold interact to advance chop_progress — a
## continuous meter with the same Undercut/Good/Perfect/Overcut shape as the
## stove's cook bands. Watching the gauge and pulling (a plain interact tap,
## never overridden here) at the right moment is the whole skill; go too far
## and it overcuts, mirroring burnt. Progress only advances while a player
## actively holds interact — unlike the stove, nothing chops itself with no
## hand on the knife, so an unattended board never goes bad on its own.
## Pulling a partially-chopped item off doesn't lock it out — set it aside
## and put it back on any board later to keep refining the chop right where
## chop_progress left off.
##
## Tap vs. hold is ambiguous at the instant of a fresh press — Godot can't
## know yet whether this is a quick tap (take it) or the start of a longer
## hold (keep chopping). A take is deferred for `_TAP_GRACE`, and — to avoid
## a quick tap nudging chop_progress before we know it's just a tap —
## progress itself doesn't start accumulating until that same window has
## elapsed either. If the button is released before then, it was a genuine
## tap and the item is taken, untouched; if the hold continues past it, the
## take is cancelled and chopping starts for real from that point on — so
## pressing-and-holding always resumes cutting cleanly, and a quick tap never
## leaves so much as a trace of progress behind.

@export var chop_duration := 2.0  # seconds for chop_progress to reach 1.0 (top of Perfect)
const _TAP_GRACE := 0.15

var _pending_take_player: Player = null
var _press_elapsed := 0.0

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


func interact(player: Player) -> void:
	if _is_chopping() and player.held_item == null:
		# Empty-handed tap on a choppable item: don't take it immediately —
		# wait to see if this turns into a hold instead.
		_pending_take_player = player
		_press_elapsed = 0.0
		return
	super.interact(player)


func interact_hold(player: Player, delta: float) -> void:
	if not _is_chopping():
		return
	if _pending_take_player == player:
		_press_elapsed += delta
		if _press_elapsed < _TAP_GRACE:
			return  # still uncertain whether this is a tap or a hold — no progress yet
		# Held long enough to be a genuine hold, not a tap — cancel the pending
		# take (releasing later won't also take the item) and start chopping
		# for real from this point on.
		_pending_take_player = null
	held_item.chop(delta, 1.0 / chop_duration)
	_update_gauge()


func _process(_delta: float) -> void:
	if _pending_take_player == null:
		return
	var p := _pending_take_player
	if not Input.is_action_pressed("p%d_interact" % p.player_id):
		# Released before the grace window elapsed — a genuine quick tap.
		_pending_take_player = null
		super.interact(p)


func _on_item_placed(item: Item) -> void:
	_gauge.visible = _can_chop(item)
	if _gauge.visible:
		_update_gauge()


func _on_item_removed(item: Item) -> void:
	_gauge.visible = false
	if _can_chop(item):
		item.lock_in_chop_score(item.chop_score())


func _is_chopping() -> bool:
	return held_item != null and _can_chop(held_item)


## True both the first time (CHOP is the pending step) and for a resumed
## item that's already been chopped once (CHOP already recorded, but
## chop_progress carries forward so more cutting keeps having an effect).
func _can_chop(item: Item) -> bool:
	return item.has_step(Ingredients.Verb.CHOP) and (
		item.next_verb() == Ingredients.Verb.CHOP
		or item.step_done(Ingredients.Verb.CHOP)
	)


func _update_gauge() -> void:
	var normalized := clampf(held_item.chop_progress / Item.CHOP_OVERCUT_CAP, 0.0, 1.0)
	_fill_pivot.scale.x = maxf(normalized, 0.001)
	_fill_mat.albedo_color = _BAND_COLORS[held_item.current_chop_band()]
