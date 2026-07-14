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

@onready var _body_mesh: MeshInstance3D = $BodyMesh


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
		# so later interaction raycasts can use -global_basis.z.
		var target_yaw := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, TURN_SPEED * delta)

	move_and_slide()
