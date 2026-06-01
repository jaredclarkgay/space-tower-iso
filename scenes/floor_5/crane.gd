extends Node3D

# Drivable construction crane on the Vista deck. Walk up and press E to climb in;
# WASD then drives + turns the whole crane around the deck (camera-relative, like
# the player), and E gets you back out. While you're driving, GameState.driving_crane
# is set so the player skips its own physics and rides the cab.
#
# Built procedurally by floor_5.gd, which hands it the player + camera-pivot refs.

var _c: Node
var _gs: Node
var _player: Node3D
var _camera_pivot: Node3D

enum State { IDLE, DRIVING }
var _state: int = State.IDLE

const SPEED := 5.5             # m/s drive speed
const TURN_RATE := 5.0         # rad/s the rig swings toward its heading
const INTERACT_RADIUS := 3.0   # m — how close to climb in
const EXIT_OFFSET := 2.6       # m to the side where you step out

var _yaw := 0.0
var _t := 0.0
var _cab_seat: Node3D          # where the player rides
var _hook_pivot: Node3D        # cable + hook, swings while driving
var _prompt_root: Node3D
var _prompt_e: Label3D
var _prompt_label: Label3D

const YELLOW := Color(0.92, 0.74, 0.18)
const STEEL := Color(0.36, 0.38, 0.42)
const DARK := Color(0.16, 0.17, 0.20)


func setup(player: Node3D, camera_pivot: Node3D) -> void:
	_player = player
	_camera_pivot = camera_pivot


func _ready() -> void:
	_c = get_node("/root/Constants")
	_gs = get_node("/root/GameState")
	_build_crane()
	_build_prompt()


func _physics_process(delta: float) -> void:
	_t += delta
	if _player == null:
		return
	_swing_hook(delta)
	match _state:
		State.IDLE:
			_update_idle()
		State.DRIVING:
			_update_driving(delta)


func _update_idle() -> void:
	var near: bool = _player_near()
	_prompt_root.visible = near
	if near:
		_prompt_e.text = "E"
		_prompt_label.text = "Operate crane"
		if Input.is_action_just_pressed(&"interact"):
			_enter()


func _enter() -> void:
	_state = State.DRIVING
	_gs.set("driving_crane", true)


func _update_driving(delta: float) -> void:
	# Camera-relative WASD, same mapping as the player so it feels consistent.
	var input := Vector2(
		Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		Input.get_action_strength(&"move_down") - Input.get_action_strength(&"move_up"),
	)
	var yaw: float = _camera_pivot.rotation.y if _camera_pivot else 0.0
	var world_dir := Vector3(
		input.x * cos(yaw) + input.y * sin(yaw),
		0.0,
		-input.x * sin(yaw) + input.y * cos(yaw),
	)
	if world_dir.length() > 0.05:
		# Floor 5 has no rotation, so local XZ == world XZ; move in local space.
		position += world_dir.normalized() * SPEED * delta
		_yaw = atan2(world_dir.x, world_dir.z)
	rotation.y = lerp_angle(rotation.y, _yaw, TURN_RATE * delta)

	# Keep the crawler on the deck.
	var clamp_xz: float = float(_c.FLOOR_3D_SIZE) * 0.5 - 2.8
	position.x = clampf(position.x, -clamp_xz, clamp_xz)
	position.z = clampf(position.z, -clamp_xz, clamp_xz)

	# The player rides the cab.
	_player.global_position = _cab_seat.global_position
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO

	_prompt_root.visible = true
	_prompt_e.text = "E"
	_prompt_label.text = "Exit crane"
	if Input.is_action_just_pressed(&"interact"):
		_exit()


func _exit() -> void:
	_state = State.IDLE
	_gs.set("driving_crane", false)
	# Step the player out beside the cab, onto the deck.
	var side: Vector3 = global_transform.basis.x.normalized()
	_player.global_position = _cab_seat.global_position + side * EXIT_OFFSET + Vector3(0.0, -1.2, 0.0)
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO


func _player_near() -> bool:
	var p: Vector3 = _player.global_position
	var c: Vector3 = global_position
	# XZ proximity + same-floor Y gate.
	return absf(p.y - c.y) < 3.0 and Vector2(p.x - c.x, p.z - c.z).length() <= INTERACT_RADIUS


# --- Geometry -------------------------------------------------------------

func _build_crane() -> void:
	# Start parked off to one side, clear of the central shaft.
	position = Vector3(-6.0, 0.0, 5.5)

	# Crawler treads (two long dark boxes) + body.
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.7, 0.5, 3.4), Vector3(sx * 0.95, 0.25, 0.0), DARK, 0.7, self)
	_box(Vector3(2.6, 0.5, 2.6), Vector3(0.0, 0.7, 0.0), STEEL, 0.5, self)   # slew deck

	# Superstructure root (cab + counterweight + boom) sits on the slew deck.
	var sup := Node3D.new()
	sup.name = "Superstructure"
	sup.position = Vector3(0, 0.95, 0)
	add_child(sup)

	# Operator cab — body + a glass window front.
	_box(Vector3(1.5, 1.5, 1.4), Vector3(0.0, 0.75, -0.55), YELLOW, 0.5, sup)
	var glass := _box(Vector3(1.2, 0.9, 0.06), Vector3(0.0, 0.95, -1.27), Color(0.55, 0.75, 0.9, 0.5), 0.1, sup)
	(glass.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Counterweight slab at the back.
	_box(Vector3(1.8, 0.9, 0.7), Vector3(0.0, 0.7, 1.2), DARK, 0.6, sup)

	# Seat anchor inside the cab (where the player rides).
	_cab_seat = Node3D.new()
	_cab_seat.name = "CabSeat"
	_cab_seat.position = Vector3(0.0, 0.2, -0.55)
	sup.add_child(_cab_seat)

	# Boom — a lattice arm angled up-and-forward (out the cab's -Z front).
	var boom := Node3D.new()
	boom.name = "Boom"
	boom.position = Vector3(0.0, 0.8, -0.9)
	boom.rotation = Vector3(deg_to_rad(52.0), 0.0, 0.0)   # tilt up
	sup.add_child(boom)
	var boom_len := 9.0
	_box(Vector3(0.34, 0.34, boom_len), Vector3(0.0, 0.0, -boom_len * 0.5), STEEL, 0.5, boom)
	# A few lattice rungs so it reads as a truss, not a stick.
	for i in range(1, 6):
		var z: float = -boom_len * (float(i) / 6.0)
		_box(Vector3(0.42, 0.06, 0.06), Vector3(0.0, 0.20, z), YELLOW, 0.5, boom)
		_box(Vector3(0.06, 0.42, 0.06), Vector3(0.20, 0.0, z), YELLOW, 0.5, boom)

	# Hook + cable hang straight DOWN from the boom tip (world-vertical), so put
	# the pivot at the tip in superstructure space and don't inherit boom tilt.
	var tip: Vector3 = boom.position + Vector3(0, sin(deg_to_rad(52.0)), -cos(deg_to_rad(52.0))) * boom_len
	_hook_pivot = Node3D.new()
	_hook_pivot.name = "HookPivot"
	_hook_pivot.position = tip
	sup.add_child(_hook_pivot)
	_box(Vector3(0.04, 3.0, 0.04), Vector3(0.0, -1.5, 0.0), DARK, 0.4, _hook_pivot)   # cable
	_box(Vector3(0.22, 0.34, 0.22), Vector3(0.0, -3.1, 0.0), STEEL, 0.6, _hook_pivot)  # hook block


func _swing_hook(delta: float) -> void:
	if _hook_pivot == null:
		return
	# Gentle pendulum; a bit livelier while driving.
	var amp: float = 0.10 if _state == State.DRIVING else 0.04
	_hook_pivot.rotation.x = sin(_t * 1.6) * amp
	_hook_pivot.rotation.z = sin(_t * 1.2 + 0.7) * amp


func _box(size: Vector3, pos: Vector3, color: Color, metallic: float, parent: Node3D) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = 0.55
	m.material_override = mat
	m.position = pos
	parent.add_child(m)
	return m


func _build_prompt() -> void:
	_prompt_root = Node3D.new()
	_prompt_root.name = "CranePrompt"
	_prompt_root.visible = false
	# Rides above the cab on the crane itself; the labels billboard so the rig's
	# spin never affects their readability.
	_prompt_root.position = Vector3(0.0, 3.4, -0.55)
	add_child(_prompt_root)

	_prompt_e = Label3D.new()
	_prompt_e.text = "E"
	_prompt_e.font_size = 84
	_prompt_e.outline_size = 12
	_prompt_e.modulate = Color(1.0, 0.92, 0.55)
	_prompt_e.outline_modulate = Color(0, 0, 0, 0.92)
	_prompt_e.pixel_size = 0.01
	_prompt_e.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_e.no_depth_test = true
	_prompt_e.position = Vector3(0, 0.5, 0)
	_prompt_root.add_child(_prompt_e)

	_prompt_label = Label3D.new()
	_prompt_label.text = "Operate crane"
	_prompt_label.font_size = 52
	_prompt_label.outline_size = 8
	_prompt_label.modulate = Color(1.0, 0.96, 0.85)
	_prompt_label.outline_modulate = Color(0, 0, 0, 0.92)
	_prompt_label.pixel_size = 0.01
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.position = Vector3(0, -0.1, 0)
	_prompt_root.add_child(_prompt_label)
