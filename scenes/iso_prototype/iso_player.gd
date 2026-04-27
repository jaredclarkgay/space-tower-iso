extends CharacterBody3D

# Programmatic placeholder character for the iso slice. Walks on the floor
# plane via WASD / arrow keys, jumps with Space.
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
#
# Body: programmatic primitives — legs, torso, arms, head, hardhat with brim,
# tool belt, facing nub. No animation in the slice; static geometry that
# reads as a person rather than a single capsule.

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

# Camera the player should be relative to. Set by iso_prototype.tscn.
@export var camera_pivot_path: NodePath
var _camera_pivot: Node3D
# Visual root — rotates with movement direction. Separate from the
# CharacterBody3D so the collision capsule doesn't spin with the body.
var _visual: Node3D
var _facing_yaw := 0.0     # smoothed yaw the visual is interpolating toward
const FACING_TURN_SPEED := 14.0   # rad/s — snappy but not jittery


func _ready() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_build_visual()
	_build_collision()
	if camera_pivot_path:
		_camera_pivot = get_node(camera_pivot_path)


func _physics_process(delta: float) -> void:
	# Horizontal input — camera-relative.
	var input := Vector2(
		Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		Input.get_action_strength(&"move_down") - Input.get_action_strength(&"move_up"),
	)
	if input.length() > 1.0:
		input = input.normalized()
	var yaw := 0.0
	if _camera_pivot:
		yaw = _camera_pivot.rotation.y
	var world_dir := Vector3(
		input.x * cos(yaw) + input.y * sin(yaw),
		0.0,
		-input.x * sin(yaw) + input.y * cos(yaw),
	)
	velocity.x = world_dir.x * _c.PLAYER_MOVE_SPEED
	velocity.z = world_dir.z * _c.PLAYER_MOVE_SPEED

	# Vertical: gravity + jump.
	if is_on_floor():
		if Input.is_action_just_pressed(&"jump"):
			velocity.y = _c.PLAYER_JUMP_VELOCITY
		# Don't zero velocity.y on every grounded frame — let move_and_slide
		# settle it. Light gravity nudge keeps us seated on the slab.
		else:
			velocity.y = -1.0
	else:
		velocity.y -= _c.PLAYER_GRAVITY * delta

	move_and_slide()

	# Visual facing: rotate the visual root toward the world-space movement
	# direction. atan2(x, z) gives the angle around Y. Smooth via lerp_angle
	# so the body doesn't jitter when input changes mid-step.
	if Vector2(world_dir.x, world_dir.z).length_squared() > 0.01:
		_facing_yaw = atan2(world_dir.x, world_dir.z)
	if _visual:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, _facing_yaw, FACING_TURN_SPEED * delta)

	# Mirror to GameState as the single source of truth.
	_gs.player.iso_pos = global_position
	if input.length_squared() > 0.01:
		_gs.player.facing = _facing_from_input(input)

	# Fall fail-safe (F-005). Walls should keep us in, but if we ever escape,
	# snap back to spawn rather than drop forever.
	if global_position.y < _c.PLAYER_FALL_RESPAWN_Y:
		global_position = Vector3(0, 1.0, 0)
		velocity = Vector3.ZERO


# --- Visual: legs + torso + arms + head + hardhat -----------------------

func _build_visual() -> void:
	# All visual primitives parent to _visual (not self) so the visual rotates
	# with movement direction without spinning the collision capsule.
	var v: Node3D = _visual
	var jumpsuit := Color(0.85, 0.55, 0.25)   # hardhat-orange
	var skin := Color(0.95, 0.78, 0.65)
	var hat_color := Color(1.0, 0.85, 0.2)
	var leather := Color(0.32, 0.22, 0.14)

	# Legs (two capsules, slightly apart on X).
	for sign_x in [-1, 1]:
		var leg := MeshInstance3D.new()
		leg.name = "Leg"
		var leg_mesh := CapsuleMesh.new()
		leg_mesh.radius = 0.11
		leg_mesh.height = 0.6
		leg.mesh = leg_mesh
		leg.material_override = _make_material(jumpsuit)
		leg.position = Vector3(0.13 * sign_x, 0.32, 0)
		v.add_child(leg)
		# Boot — small dark box at the foot.
		var boot := MeshInstance3D.new()
		boot.name = "Boot"
		var boot_mesh := BoxMesh.new()
		boot_mesh.size = Vector3(0.18, 0.08, 0.28)
		boot.mesh = boot_mesh
		boot.material_override = _make_material(leather)
		boot.position = Vector3(0.13 * sign_x, 0.05, 0.04)
		v.add_child(boot)

	# Torso.
	var torso := MeshInstance3D.new()
	torso.name = "Torso"
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.5, 0.55, 0.3)
	torso.mesh = torso_mesh
	torso.material_override = _make_material(jumpsuit)
	torso.position = Vector3(0, 0.95, 0)
	v.add_child(torso)

	# Tool belt — thin dark band around the waist.
	var belt := MeshInstance3D.new()
	belt.name = "Belt"
	var belt_mesh := BoxMesh.new()
	belt_mesh.size = Vector3(0.54, 0.08, 0.34)
	belt.mesh = belt_mesh
	belt.material_override = _make_material(leather)
	belt.position = Vector3(0, 0.7, 0)
	v.add_child(belt)

	# Arms (two capsules at the shoulders).
	for sign_x in [-1, 1]:
		var arm := MeshInstance3D.new()
		arm.name = "Arm"
		var arm_mesh := CapsuleMesh.new()
		arm_mesh.radius = 0.09
		arm_mesh.height = 0.55
		arm.mesh = arm_mesh
		arm.material_override = _make_material(jumpsuit)
		arm.position = Vector3(0.32 * sign_x, 0.95, 0)
		v.add_child(arm)
		# Hand — tiny skin-colored cube.
		var hand := MeshInstance3D.new()
		hand.name = "Hand"
		var hand_mesh := BoxMesh.new()
		hand_mesh.size = Vector3(0.12, 0.12, 0.14)
		hand.mesh = hand_mesh
		hand.material_override = _make_material(skin)
		hand.position = Vector3(0.32 * sign_x, 0.62, 0)
		v.add_child(hand)

	# Head.
	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.3, 0.32, 0.3)
	head.mesh = head_mesh
	head.material_override = _make_material(skin)
	head.position = Vector3(0, 1.4, 0)
	v.add_child(head)

	# Eyes — two tiny dark boxes on the front of the head.
	for sign_x in [-1, 1]:
		var eye := MeshInstance3D.new()
		eye.name = "Eye"
		var eye_mesh := BoxMesh.new()
		eye_mesh.size = Vector3(0.04, 0.04, 0.02)
		eye.mesh = eye_mesh
		eye.material_override = _make_material(Color(0.1, 0.1, 0.12))
		eye.position = Vector3(0.07 * sign_x, 1.42, 0.16)
		v.add_child(eye)

	# Hardhat brim — flat cylinder slightly wider than the head.
	var brim := MeshInstance3D.new()
	brim.name = "HardhatBrim"
	var brim_mesh := CylinderMesh.new()
	brim_mesh.top_radius = 0.26
	brim_mesh.bottom_radius = 0.26
	brim_mesh.height = 0.04
	brim.mesh = brim_mesh
	brim.material_override = _make_material(hat_color)
	brim.position = Vector3(0, 1.59, 0.04)  # slightly forward = visor feel
	v.add_child(brim)

	# Hardhat dome — slightly squashed sphere on top.
	var hat := MeshInstance3D.new()
	hat.name = "HardhatDome"
	var hat_mesh := SphereMesh.new()
	hat_mesh.radius = 0.2
	hat_mesh.height = 0.28
	hat.mesh = hat_mesh
	hat.material_override = _make_material(hat_color)
	hat.position = Vector3(0, 1.66, 0)
	v.add_child(hat)

	# Facing-direction nub on the brim front so iso direction stays readable.
	var nub := MeshInstance3D.new()
	nub.name = "FacingNub"
	var nub_mesh := BoxMesh.new()
	nub_mesh.size = Vector3(0.08, 0.06, 0.06)
	nub.mesh = nub_mesh
	nub.material_override = _make_material(Color(0.2, 0.2, 0.22))
	nub.position = Vector3(0, 1.59, 0.28)
	v.add_child(nub)


func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var col_shape := CapsuleShape3D.new()
	col_shape.radius = 0.3
	col_shape.height = 1.7
	col.shape = col_shape
	col.position = Vector3(0, 0.85, 0)
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
