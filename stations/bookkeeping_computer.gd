class_name BookkeepingComputer
extends Station

## Sits next to a LedgerDesk (wired via desk_path, set per-instance in the
## scene). Filing the books is real, sustained work, not a single tap — hold
## the **work** button (action_hold, same button CuttingBoard's chop uses)
## once the desk holds every document that actually has something to report
## today (LedgerDesk.missing()) to fill a plain progress gauge over
## _WORK_DURATION; crossing 1.0 files the books immediately (there's no
## finished item to separately pull off, unlike a cutting board, so
## completing the hold *is* the trigger). A quick action tap short of a full
## hold gives immediate "NEED: X"/"ALREADY CLOSED" feedback without
## committing to the hold. Releasing early resets progress to zero — there's
## no item here to carry resumable state the way a cutting board's
## chop_progress does, so a half-finished session doesn't persist.
##
## Skipping this and going straight to Bed instead still closes the books
## somehow — see GameState.end_night()/_auto_close_books() — just silently
## and worse, since someone always has to do the accounting.

const _WORK_DURATION := 2.5

@export var desk_path: NodePath

var _desk: LedgerDesk
var _progress := 0.0

## Set by action_hold whenever real work happens this frame; the gauge is
## only ever visible while that's true, same "_chopped_this_frame" shape
## CuttingBoard already uses — release the button and the gauge (and
## progress) both disappear next frame.
var _worked_this_frame := false

@onready var _result: Label3D = $Result
var _result_home: Vector3

@onready var _gauge: Node3D = $Gauge
@onready var _fill_pivot: Node3D = $Gauge/FillPivot
@onready var _fill_mesh: MeshInstance3D = $Gauge/FillPivot/Fill

var _fill_mat: StandardMaterial3D


func _ready() -> void:
	super._ready()
	_desk = get_node(desk_path)
	_result_home = _result.position
	_result.visible = false

	_fill_mat = StandardMaterial3D.new()
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mat.no_depth_test = true
	_fill_mat.render_priority = 1  # above the gauge BG's 0
	_fill_mat.albedo_color = Color(0.35, 0.65, 0.85, 1)
	_fill_mesh.material_override = _fill_mat
	_gauge.visible = false


func _process(_delta: float) -> void:
	# Physics (where action_hold runs) always finishes before this frame
	# callback — same ordering CuttingBoard relies on for its own
	# _chopped_this_frame flag.
	_gauge.visible = _worked_this_frame
	if not _worked_this_frame:
		_progress = 0.0
		_fill_pivot.scale.x = 0.001
	_worked_this_frame = false


## A quick tap short of a full hold — doesn't advance any work, just tells
## the player what's still missing (or that it's already done tonight)
## without committing to the hold.
func hints(_player: Player) -> Array[Dictionary]:
	if _ready_to_work():
		return [hint("action_hold", "Do the books")]
	if GameState.phase == GameState.Phase.NIGHT and not GameState.books_closed:
		return [hint("action", "What's still needed?")]
	return []


func action(_player: Player) -> void:
	if GameState.phase != GameState.Phase.NIGHT:
		return
	if GameState.books_closed:
		_pop("ALREADY CLOSED", Color(0.7, 0.7, 0.7, 1))
		return
	var missing := _desk.missing()
	if not missing.is_empty():
		var labels := missing.map(func(c: String) -> String: return c.capitalize())
		_pop("NEED:\n%s" % "\n".join(labels), Color(0.9, 0.5, 0.2, 1))


func action_hold(_player: Player, delta: float) -> void:
	if not _ready_to_work():
		return
	_worked_this_frame = true
	_progress = clampf(_progress + delta / _WORK_DURATION, 0.0, 1.0)
	_fill_pivot.scale.x = maxf(_progress, 0.001)
	if _progress >= 1.0:
		_finish_work()


func _ready_to_work() -> bool:
	return GameState.phase == GameState.Phase.NIGHT \
		and not GameState.books_closed \
		and _desk.missing().is_empty()


func _finish_work() -> void:
	_progress = 0.0
	_worked_this_frame = false
	_gauge.visible = false
	var result := GameState.file_books()
	_desk.clear()
	var lines := ["Cash: $%d" % result.cash]
	if result.receipts > 0:
		lines.append("Receipts: $%d sold" % result.receipts)
	if result.invoices > 0:
		lines.append("Invoices: -$%d" % result.invoices)
	lines.append("Rent: -$%d" % result.rent)
	if result.waste > 0:
		lines.append("Wasted ~$%d in stock" % result.waste)
	lines.append("Net: $%d" % result.net)
	_pop("\n".join(lines), Color(0.85, 0.85, 0.90, 1))


func get_inspect_text() -> String:
	if GameState.phase != GameState.Phase.NIGHT:
		return "COMPUTER\n(night only)"
	if GameState.books_closed:
		return "COMPUTER\n(books closed for the night)"
	var missing := _desk.missing()
	if missing.is_empty():
		return "COMPUTER\nHold action to close the books"
	var labels := missing.map(func(c: String) -> String: return c.capitalize())
	return "COMPUTER\nNeed: %s" % ", ".join(labels)


func _pop(text: String, color: Color) -> void:
	_result.text = text
	_result.modulate = color
	_result.position = _result_home
	_result.visible = true

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_result, "position:y", _result_home.y + 0.6, 1.2)
	tween.tween_property(_result, "modulate:a", 0.0, 1.2).set_delay(2.5)
	tween.chain().tween_callback(func() -> void: _result.visible = false)
