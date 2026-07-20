class_name Player
extends CharacterBody3D

## Which local player this body reads input for. Actions are prefixed
## "p1_"/"p2_" and bound per-device in the Input Map, so no device
## filtering is needed here.
@export_range(1, 2) var player_id: int = 1
@export var player_color: Color = Color("4f9dff")

const SPEED := 4.5
const ACCELERATION := 22.0
const TURN_SPEED := 12.0
const GRAVITY := 20.0

## Grid-based station relocation ("build mode"), only allowed in
## GameState.Phase.MORNING (see AppShortcuts' F6 debug toggle until the real
## day-phase skeleton exists). A held station is never the live node — it's
## despawned into {scene, config}. What follows the player is a real (but
## inert and shrunk) copy of that same station, so you can see exactly what
## you're carrying; a separate floor-level square is the green/red
## can-I-place-it-here signal, kept apart from the carried model itself.
const _BUILD_GHOST_SCALE := 0.7
const _BUILD_INDICATOR_SIZE := Vector2(0.9, 0.9)
const _BUILD_INDICATOR_Y := 0.02
const _BUILD_GHOST_FREE_COLOR := Color(0.25, 0.85, 0.35, 0.6)
const _BUILD_GHOST_BLOCKED_COLOR := Color(0.85, 0.25, 0.2, 0.6)
const _CLEARING_TINT := Color(0.95, 0.65, 0.15, 0.45)
## Deliberate hold to confirm lifting a non-empty station (it clears first) —
## long enough that a quick tap can never trigger it by accident.
const _CLEAR_HOLD_DURATION := 0.4

var held_item: Item = null

var _target: Station = null

var _carrying_scene: PackedScene = null
var _carrying_config: Dictionary = {}
var _carrying_y := 0.45
## The carried preview itself — a real, inert copy of the station scene (see
## _show_build_ghost). Separate from _build_indicator, the floor-level
## validity square.
var _build_ghost: Station = null
var _build_indicator: MeshInstance3D = null

var _pending_clear_station: Station = null
var _clear_press_elapsed := 0.0

## Set by a station (currently only OrderDesk) to fully take over this
## player's input for a UI panel. While non-null, movement/targeting/normal
## station dispatch/build mode all pause; the capturing node owns 100% of
## interaction semantics and reads this player's input directly (same
## poll-by-player_id convention SlotStation already uses for its own
## tap/hold timing), via handle_input(self, delta) each physics frame.
var ui_capture: Node = null

@onready var _body_mesh: MeshInstance3D = $BodyMesh
@onready var _hold_point: Marker3D = $HoldPoint
@onready var _reach: Area3D = $Reach


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = player_color
	_body_mesh.material_override = mat


func _physics_process(delta: float) -> void:
	if ui_capture != null:
		# Stay grounded and stationary rather than freezing entirely — no
		# horizontal drift, but gravity still applies so a capture started
		# mid-air (shouldn't happen on this flat kitchen floor, but just in
		# case) doesn't leave the player floating.
		velocity.x = 0.0
		velocity.z = 0.0
		if is_on_floor():
			velocity.y = 0.0
		else:
			velocity.y -= GRAVITY * delta
		move_and_slide()
		ui_capture.handle_input(self, delta)
		return

	var prefix := "p%d" % player_id
	var input := Input.get_vector(
		prefix + "_move_left", prefix + "_move_right",
		prefix + "_move_up", prefix + "_move_down"
	)
	# Camera looks toward -Z, so stick-up maps straight to world -Z.
	var direction := Vector3(input.x, 0.0, input.y)

	velocity.x = move_toward(velocity.x, direction.x * SPEED, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, direction.z * SPEED, ACCELERATION * delta)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta

	if direction.length_squared() > 0.001:
		# Face -Z along the move direction (Godot's forward convention),
		# so interaction targeting can use -global_basis.z as "in front".
		var target_yaw := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, TURN_SPEED * delta)

	move_and_slide()

	_update_target()
	if _target != null:
		# interact = pickup/place (tap take/place/peel, hold take-whole-dispenser);
		# action = operate a tool (tap trigger e.g. flip, hold e.g. chop).
		#
		# _target is re-checked before each call below, not just once up
		# front: interact(self) can itself clear _target mid-frame (e.g.
		# OrderDesk.interact() -> start_ui_capture() nulls it out to drop
		# the stale highlight) — and since is_action_pressed is still true
		# on the very same frame is_action_just_pressed fired, the next
		# line would otherwise call a method on a freshly-nulled _target.
		if Input.is_action_just_pressed(prefix + "_interact"):
			_target.interact(self)
		if _target != null and Input.is_action_pressed(prefix + "_interact"):
			_target.interact_hold(self, delta)
		if _target != null and Input.is_action_just_pressed(prefix + "_action"):
			_target.action(self)
		if _target != null and Input.is_action_pressed(prefix + "_action"):
			_target.action_hold(self, delta)
	_handle_build_input(prefix, delta)


func take_item(item: Item) -> void:
	held_item = item
	item.attach_to(_hold_point)


func drop_item() -> Item:
	var item := held_item
	held_item = null
	return item


## The station currently targeted (highlighted), or null. Read-only outside
## Player — InspectPanel uses this to show info about what you're facing.
func get_target() -> Station:
	return _target


## Hands this player's input over to a UI panel (currently only OrderDesk).
## Clears the current target/highlight first — the player isn't "browsing"
## stations anymore while captured, so a stale highlighted target shouldn't
## linger.
func start_ui_capture(capture: Node) -> void:
	if _target != null:
		_target.remove_highlight()
		_target = null
	ui_capture = capture


func end_ui_capture() -> void:
	ui_capture = null


## Build mode: not yet carrying a station -> tap picks up an empty one under
## the target, or arms a deliberate hold to clear-then-lift a non-empty one.
## Carrying one -> the ghost follows the cell ahead; tap places it there if
## free. Only available during GameState.Phase.MORNING (the day-phase
## skeleton isn't built yet — this reads whatever AppShortcuts' debug toggle
## currently has it set to).
func _handle_build_input(prefix: String, delta: float) -> void:
	if _carrying_scene != null:
		_update_build_ghost()
		if Input.is_action_just_pressed(prefix + "_build"):
			_try_place_station()
		return

	if _target == null or GameState.phase != GameState.Phase.MORNING or held_item != null:
		_cancel_pending_clear()
		return

	if Input.is_action_just_pressed(prefix + "_build"):
		if _target.is_empty():
			_pickup_station(_target)
			return
		_pending_clear_station = _target
		_clear_press_elapsed = 0.0
		_target.set_highlight_tint(_CLEARING_TINT)

	if _pending_clear_station != null:
		if _pending_clear_station != _target or not Input.is_action_pressed(prefix + "_build"):
			_cancel_pending_clear()
		else:
			_clear_press_elapsed += delta
			if _clear_press_elapsed >= _CLEAR_HOLD_DURATION:
				var station := _pending_clear_station
				_cancel_pending_clear()
				station.clear_contents()
				_pickup_station(station)


func _cancel_pending_clear() -> void:
	if _pending_clear_station != null:
		_pending_clear_station.clear_highlight_tint()
		_pending_clear_station = null
		_clear_press_elapsed = 0.0


## Despawns a station into {scene, config} and hands the player a ghost to
## carry instead — the station is never carried live, so nothing about its
## collision/targeting/slot state has to survive a "held" limbo.
func _pickup_station(station: Station) -> void:
	_cancel_pending_clear()
	_carrying_scene = load(station.scene_file_path)
	_carrying_config = station.get_config()
	_carrying_y = station.global_position.y
	_target = null
	station.remove_highlight()
	station.queue_free()
	_show_build_ghost()


func _try_place_station() -> void:
	var cell := _build_target_cell()
	if StationGrid.is_occupied(cell):
		return
	var station: Station = _carrying_scene.instantiate()
	station.apply_config(_carrying_config)
	station.position = StationGrid.cell_to_world(cell, _carrying_y)
	get_tree().current_scene.add_child(station)
	_carrying_scene = null
	_carrying_config = {}
	_hide_build_ghost()


## One cell in front of the player, matching the "-Z is forward" convention
## used for targeting elsewhere.
func _build_target_cell() -> Vector2i:
	return StationGrid.world_to_cell(global_position - global_basis.z * 1.0)


## Builds a real, inert copy of the station scene being carried — same
## model, shrunk a bit, so it's obvious what you're holding. _is_ghost skips
## grid registration (its position changes every frame), zeroed collision
## keeps it untargetable, and freezing process/physics_process stops any
## per-type background behavior (a Table's customer-seating timer, a gauge's
## visibility tick) from running on what's meant to be frozen scenery.
func _show_build_ghost() -> void:
	var ghost: Station = _carrying_scene.instantiate()
	ghost._is_ghost = true
	ghost.collision_layer = 0
	ghost.collision_mask = 0
	ghost.apply_config(_carrying_config)
	add_child(ghost)
	ghost.set_process(false)
	ghost.set_physics_process(false)
	ghost.scale = Vector3.ONE * _BUILD_GHOST_SCALE
	ghost.top_level = true
	_build_ghost = ghost

	var indicator := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = _BUILD_INDICATOR_SIZE
	indicator.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	indicator.material_override = mat
	indicator.top_level = true
	add_child(indicator)
	_build_indicator = indicator


## The ghost is scene-specific (a Crate looks nothing like a Table), so
## there's no "reuse" case — every pickup gets a fresh one, freed here.
func _hide_build_ghost() -> void:
	if _build_ghost != null:
		_build_ghost.queue_free()
		_build_ghost = null
	if _build_indicator != null:
		_build_indicator.queue_free()
		_build_indicator = null


func _update_build_ghost() -> void:
	if _build_ghost == null:
		return
	var cell := _build_target_cell()
	var occupied := StationGrid.is_occupied(cell)
	_build_ghost.global_position = StationGrid.cell_to_world(cell, _carrying_y)
	_build_indicator.global_position = StationGrid.cell_to_world(cell, _BUILD_INDICATOR_Y)
	_build_indicator.material_override.albedo_color = (
		_BUILD_GHOST_BLOCKED_COLOR if occupied else _BUILD_GHOST_FREE_COLOR
	)


func _update_target() -> void:
	var facing := -global_basis.z
	var best: Station = null
	var best_score := INF
	for body in _reach.get_overlapping_bodies():
		var station := body as Station
		if station == null:
			continue
		var to := station.global_position - global_position
		to.y = 0.0
		# Distance discounted by facing alignment, so the station you're
		# looking at wins over one that's merely a bit closer.
		var score := to.length() - 0.75 * facing.dot(to.normalized())
		if score < best_score:
			best_score = score
			best = station
	if best == _target:
		return
	if _target != null:
		_target.remove_highlight()
	_target = best
	if _target != null:
		_target.add_highlight()
