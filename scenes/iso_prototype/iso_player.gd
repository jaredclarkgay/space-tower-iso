extends CharacterBody3D

# Programmatic placeholder character for the iso slice. Walks on the floor
# plane via WASD / arrow keys.
#
# Movement design: 4-direction, but expressed as a normalized Vector2 (so the
# implementer can flip to 8-direction with one comment if it feels stiff).
# 4-direction matches the iso cardinal axes after camera rotation, keeps
# depth-sort intuitions clean, and is honest about the slice's scope — we are
# testing whether iso *feels right*, not whether 8-way movement feels right.
#
# Movement is camera-relative: WASD maps to screen up/down/left/right, which
# means the world-space direction depends on the camera's current yaw. This
# is what makes WASD feel correct when the camera has been rotated.

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

# Camera the player should be relative to. Set by iso_prototype.tscn.
@export var camera_pivot_path: NodePath
var _camera_pivot: Node3D


func _ready() -> void:
	_build_visual()
	if camera_pivot_path:
		_camera_pivot = get_node(camera_pivot_path)


func _physics_process(delta: float) -> void:
	var input := Vector2(
		Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		Input.get_action_strength(&"move_down") - Input.get_action_strength(&"move_up"),
	)
	# Normalize so diagonal movement isn't faster than cardinal. Even with
	# 4-direction input the user can press two keys for an instant; clamp it.
	if input.length() > 1.0:
		input = input.normalized()
	# Camera-relative: rotate the input by the camera pivot's yaw so "up" on
	# screen always means "forward into the scene", regardless of rotation.
	var yaw := 0.0
	if _camera_pivot:
		yaw = _camera_pivot.rotation.y
	var world_dir := Vector3(
		input.x * cos(yaw) + input.y * sin(yaw),
		0.0,
		-input.x * sin(yaw) + input.y * cos(yaw),
	)
	velocity = world_dir * _c.PLAYER_MOVE_SPEED
	move_and_slide()
	# Mirror to GameState as the single source of truth.
	_gs.player.iso_pos = global_position
	if input.length_squared() > 0.01:
		_gs.player.facing = _facing_from_input(input)


# --- Visual: programmatic capsule body, box head, single accent ------------

func _build_visual() -> void:
	# Body
	var body := MeshInstance3D.new()
	body.name = "Body"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.25
	capsule.height = 1.0
	body.mesh = capsule
	body.material_override = _make_material(Color(0.85, 0.55, 0.25))  # hardhat orange
	body.position = Vector3(0, 0.6, 0)
	add_child(body)
	# Head
	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.32, 0.32, 0.32)
	head.mesh = head_mesh
	head.material_override = _make_material(Color(0.95, 0.78, 0.65))
	head.position = Vector3(0, 1.32, 0)
	add_child(head)
	# Hardhat
	var hat := MeshInstance3D.new()
	hat.name = "Hardhat"
	var hat_mesh := SphereMesh.new()
	hat_mesh.radius = 0.22
	hat_mesh.height = 0.22
	hat.mesh = hat_mesh
	hat.material_override = _make_material(Color(1.0, 0.85, 0.2))
	hat.position = Vector3(0, 1.55, 0)
	add_child(hat)
	# Facing-indicator nub on the front (Z+) so iso direction is readable.
	var nub := MeshInstance3D.new()
	nub.name = "FacingNub"
	var nub_mesh := BoxMesh.new()
	nub_mesh.size = Vector3(0.1, 0.1, 0.18)
	nub.mesh = nub_mesh
	nub.material_override = _make_material(Color(0.2, 0.2, 0.2))
	nub.position = Vector3(0, 1.32, 0.22)
	add_child(nub)
	# Collision: a single capsule at body height.
	var col := CollisionShape3D.new()
	var col_shape := CapsuleShape3D.new()
	col_shape.radius = 0.3
	col_shape.height = 1.6
	col.shape = col_shape
	col.position = Vector3(0, 0.8, 0)
	add_child(col)


func _facing_from_input(input: Vector2) -> int:
	# Map input vector to cardinal index 0..3 (N, E, S, W). Used for future
	# anim/sprite selection; not visually meaningful with a placeholder mesh.
	if abs(input.x) > abs(input.y):
		return 1 if input.x > 0 else 3
	return 2 if input.y > 0 else 0


func _make_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	return m
