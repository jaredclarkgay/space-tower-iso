extends Node3D

# Drivable construction crane on the Vista deck. Walk up and press E to climb in;
# WASD then drives + turns the whole crane around the deck (camera-relative, like
# the player), and E gets you back out. While you're driving, GameState.driving_crane
# is set so the player skips its own physics and rides the cab.
#
# Built procedurally by roof.gd, which hands it the player + camera-pivot refs.

var _c: Node
var _gs: Node
var _player: Node3D
var _camera_pivot: Node3D
var _roof: Node                # the roof floor — owns the knockable beams

enum State { IDLE, DRIVING, FALLING }
var _state: int = State.IDLE

const SPEED := 5.5             # m/s drive speed
const TURN_RATE := 5.0         # rad/s the rig swings toward its heading
const INTERACT_RADIUS := 3.0   # m — how close to climb in
const EXIT_OFFSET := 2.6       # m to the side where you step out

# --- Drive-off-the-edge plunge gag ---------------------------------------
const FALL_GRAVITY := 32.0     # m/s² — matches the player roof plunge
const EDGE_MARGIN := 1.0       # m past the deck half-extent before it tips over
const BEAM_KNOCK_RADIUS := 6.0 # m — beams within this of the crane go down with it
const PLUNGE_TUMBLE := Vector3(2.6, 0.4, 1.4)   # rad/s the rig tumbles as it falls

var _yaw := 0.0
var _t := 0.0
var _cab_seat: Node3D          # where the player rides
var _hook_pivot: Node3D        # cable + hook, swings while driving
var _prompt_root: Node3D
var _prompt_e: Label3D
var _prompt_label: Label3D

# Plunge bookkeeping.
var _fall_vel: Vector3 = Vector3.ZERO    # current plunge velocity (local space)
var _last_drive_dir: Vector3 = Vector3.ZERO  # heading at the instant it tips over
var _enter_pos: Vector3 = Vector3.ZERO   # crane spot when the player climbed in
var _enter_yaw := 0.0                     # crane heading when they climbed in
var _knocked := false                     # beams already knocked this plunge
var _bottom_y := -100.0                    # world y at which the plunge bottoms out

const YELLOW := Color(0.92, 0.74, 0.18)
const STEEL := Color(0.36, 0.38, 0.42)
const DARK := Color(0.16, 0.17, 0.20)


func setup(player: Node3D, camera_pivot: Node3D, roof: Node = null) -> void:
	_player = player
	_camera_pivot = camera_pivot
	_roof = roof


func _ready() -> void:
	_c = get_node("/root/Constants")
	_gs = get_node("/root/GameState")
	# One story below the basement (level 0) in world space — the same floor the
	# player roof-plunge bottoms out on, so the crane disappears past the tower.
	_bottom_y = -float(int(_c.GROUND_LEVEL) + 1) * float(_c.FLOOR_3D_STORY_HEIGHT)
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
		State.FALLING:
			_update_falling(delta)


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
	# Remember exactly where they climbed in — the plunge gag flashes back to here.
	_enter_pos = position
	_enter_yaw = rotation.y


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
		# The Roof has no rotation, so local XZ == world XZ; move in local space.
		position += world_dir.normalized() * SPEED * delta
		_yaw = atan2(world_dir.x, world_dir.z)
		_last_drive_dir = world_dir.normalized()
	rotation.y = lerp_angle(rotation.y, _yaw, TURN_RATE * delta)

	# Drive off the deck → the crane tips over the edge and plunges (no clamp).
	var edge: float = float(_c.FLOOR_3D_SIZE) * 0.5 + EDGE_MARGIN
	if absf(position.x) > edge or absf(position.z) > edge:
		_begin_plunge()
		return

	# The player rides the cab.
	_player.global_position = _cab_seat.global_position
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO

	_prompt_root.visible = true
	_prompt_e.text = "E"
	_prompt_label.text = "Exit crane"
	if Input.is_action_just_pressed(&"interact"):
		_exit()


# The crane has driven past the deck edge: knock the nearby beams off, kick off
# the shared roof-plunge presentation (whole tower + ground revealed, camera
# chases the falling body), and start the rig falling with the player aboard.
func _begin_plunge() -> void:
	_state = State.FALLING
	_prompt_root.visible = false
	# Carry the drive momentum off the edge, then gravity takes over.
	_fall_vel = _last_drive_dir * SPEED + Vector3(0.0, 1.0, 0.0)
	# Reuse the player roof-plunge presentation; the player rides the cab, so the
	# chase camera (which follows the player) tracks the crane all the way down.
	_gs.set("roof_falling", true)
	if _roof and _roof.has_method("knock_beams_near") and not _knocked:
		_knocked = true
		_roof.call("knock_beams_near", global_position, BEAM_KNOCK_RADIUS, _fall_vel)


func _update_falling(delta: float) -> void:
	# Plunge under gravity, tumbling, carrying the player in the cab.
	_fall_vel.y -= FALL_GRAVITY * delta
	position += _fall_vel * delta
	rotation += PLUNGE_TUMBLE * delta
	_player.global_position = _cab_seat.global_position
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO
	if _roof and _roof.has_method("tick_falling_beams"):
		_roof.call("tick_falling_beams", delta)
	# Hit the bottom → flash back to the roof.
	if global_position.y <= _bottom_y:
		_land_plunge()


# Bottomed out: snap the rig back to the spot the player climbed in, restore the
# knocked beams to their parked positions, end the plunge presentation, and drop
# the player back into the driver's seat (still driving).
func _land_plunge() -> void:
	position = _enter_pos
	rotation = Vector3(0.0, _enter_yaw, 0.0)
	_yaw = _enter_yaw
	_fall_vel = Vector3.ZERO
	_last_drive_dir = Vector3.ZERO
	_knocked = false
	if _roof and _roof.has_method("restore_beams"):
		_roof.call("restore_beams")
	_state = State.DRIVING
	# Seat the player back in the cab FIRST, so when the controller snaps the view
	# below it reads the player at the roof (not still at the fall's bottom) and
	# there's no one-frame wrong-floor flash.
	_player.global_position = _cab_seat.global_position
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO
	_gs.set("roof_falling", false)
	# The player rode the cab (physics skipped), so the tower never re-grounded the
	# current floor — tell it to snap the view back to the roof.
	var tower: Node = _tower_controller()
	if tower and tower.has_method("recover_from_crane_plunge"):
		tower.call("recover_from_crane_plunge")


func _tower_controller() -> Node:
	var nodes: Array = get_tree().get_nodes_in_group("tower_controller")
	return nodes[0] if not nodes.is_empty() else null


# Called by tower_controller._teardown_transient_state so a dev chapter jump from
# ANY state can't leave the crane owning the player — driving/falling both write
# the player's transform every frame and would yank them back to the cab. Drops
# cleanly to IDLE; if it was mid-plunge, restores the knocked beams + the parked
# crane pose and ends the plunge presentation.
func force_release() -> void:
	if _state == State.FALLING:
		if _roof and _roof.has_method("restore_beams"):
			_roof.call("restore_beams")
		_gs.set("roof_falling", false)
		position = _enter_pos
		rotation = Vector3(0.0, _enter_yaw, 0.0)
		_yaw = _enter_yaw
	_state = State.IDLE
	_fall_vel = Vector3.ZERO
	_knocked = false
	_gs.set("driving_crane", false)
	if _prompt_root:
		_prompt_root.visible = false


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
