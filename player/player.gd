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

var held_item: Item = null

var _target: Station = null

@onready var _body_mesh: MeshInstance3D = $BodyMesh
@onready var _hold_point: Marker3D = $HoldPoint
@onready var _reach: Area3D = $Reach


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = player_color
	_body_mesh.material_override = mat


func _physics_process(delta: float) -> void:
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
	if _target != null and Input.is_action_just_pressed(prefix + "_interact"):
		_target.interact(self)


func take_item(item: Item) -> void:
	held_item = item
	item.attach_to(_hold_point)


func drop_item() -> Item:
	var item := held_item
	held_item = null
	return item


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
