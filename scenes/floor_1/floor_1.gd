extends Node3D

# Floor 1 — utility / infrastructure floor under the Garden. The first
# thing the player does on entering the basement is bring this floor
# online: pull the master breaker, then walk to each of 6 utility
# sources (water, power, atmosphere, data, waste, cargo) and connect +
# activate them.
#
# Source-of-truth design lives in:
#   ~/Downloads/files 10/b1-utility-floor-godot-brief.md
#   ~/Downloads/files 10/utility-floor-prototype.html
#
# This is M1 of the Floor 1 build: scene scaffold + master breaker only.
# No spine yet, no sources, no attention arrows, no audio. The breaker
# is functional — tap E nearby to pull it, room ramps from dark to lit.
# Subsequent milestones layer in the spine, the 6 sources, mechanical
# details, attention arrows, and audio.

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

# Lighting state machine. `room_brightness` lerps toward `target_brightness`
# at the rate dictated by ROOM_LIGHT_FADE_DURATION. Drives the directional
# light's `light_energy` and the WorldEnvironment's ambient energy.
var _room_brightness := 0.0
var _target_brightness := 0.0
var _master_on := false
var _master_anim_t := 0.0   # 0..1 progress of the breaker pull animation

# Player ref for proximity checks. Resolved in _ready from a NodePath.
@export var player_path: NodePath
var _player: Node3D

# Scene refs to drive lighting + visuals each frame.
@export var directional_light_path: NodePath
@export var world_environment_path: NodePath
var _directional_light: DirectionalLight3D
var _world_environment: WorldEnvironment

# Master breaker visual handles. Built procedurally in _build_master_breaker.
var _breaker_chassis: MeshInstance3D
var _breaker_lever: Node3D            # pivot — child mesh hangs forward; pivot rotates
var _breaker_status_light: MeshInstance3D
var _breaker_status_mat: StandardMaterial3D


func _ready() -> void:
	_build_slab()
	_build_walls()
	_build_master_breaker()

	if player_path:
		_player = get_node(player_path)
	if directional_light_path:
		_directional_light = get_node(directional_light_path)
	if world_environment_path:
		_world_environment = get_node(world_environment_path)

	# Persist master_on across re-entry — GameState.floor_1 is the source of
	# truth, declared as a typed dict on the autoload.
	if _gs.floor_1.master_on:
		_master_on = true
		_target_brightness = 1.0
		_room_brightness = 1.0
	_apply_brightness_to_lighting()
	_apply_breaker_visual_state(true)


func _process(delta: float) -> void:
	# Smooth lerp toward target brightness — critical-damped feel rather
	# than a linear ramp so the room "comes alive" with a soft surge.
	if _room_brightness != _target_brightness:
		var k: float = 1.0 - exp(-(1.0 / _c.ROOM_LIGHT_FADE_DURATION) * 4.0 * delta)
		_room_brightness = lerpf(_room_brightness, _target_brightness, k)
		if absf(_room_brightness - _target_brightness) < 0.005:
			_room_brightness = _target_brightness
		_apply_brightness_to_lighting()

	# Status light pulse when off — rapid red blink to draw attention from
	# across the dark room. Steady green when on.
	_update_status_light(delta)

	# Master breaker interaction: tap E within range when room is dark.
	if not _master_on:
		_check_master_breaker_interact()
	elif _master_anim_t < 1.0:
		_master_anim_t = min(1.0, _master_anim_t + delta / _c.MASTER_BREAKER_PULL_DURATION)
		_apply_breaker_visual_state(false)


# --- Geometry --------------------------------------------------------------

func _build_slab() -> void:
	# Floor body — collision so the player walks on it; mesh for visual.
	var body := StaticBody3D.new()
	body.name = "Slab"
	add_child(body)

	var col := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(_c.FLOOR_1_SIZE, 0.4, _c.FLOOR_1_SIZE)
	col.shape = col_shape
	col.position = Vector3(0, -0.2, 0)
	body.add_child(col)

	var mesh := MeshInstance3D.new()
	mesh.name = "SlabMesh"
	var box := BoxMesh.new()
	box.size = Vector3(_c.FLOOR_1_SIZE, 0.2, _c.FLOOR_1_SIZE)
	mesh.mesh = box
	mesh.material_override = _make_material(Color(0.18, 0.16, 0.13))
	mesh.position = Vector3(0, -0.1, 0)
	body.add_child(mesh)


func _build_walls() -> void:
	# Four perimeter walls. StaticBody3D with a box collider + mesh.
	var half: float = _c.FLOOR_1_SIZE * 0.5
	var t: float = _c.FLOOR_1_WALL_THICKNESS
	var h: float = _c.FLOOR_1_WALL_HEIGHT
	# Sides: (axis, sign) pairs. axis 0 = X (left/right walls), 1 = Z (back/front).
	var sides := [
		[Vector3(-half - t * 0.5, h * 0.5, 0), Vector3(t, h, _c.FLOOR_1_SIZE)],
		[Vector3(half + t * 0.5, h * 0.5, 0), Vector3(t, h, _c.FLOOR_1_SIZE)],
		[Vector3(0, h * 0.5, -half - t * 0.5), Vector3(_c.FLOOR_1_SIZE + t * 2, h, t)],
		[Vector3(0, h * 0.5, half + t * 0.5), Vector3(_c.FLOOR_1_SIZE + t * 2, h, t)],
	]
	for s in sides:
		var pos: Vector3 = s[0]
		var size: Vector3 = s[1]
		var body := StaticBody3D.new()
		body.name = "Wall"
		body.position = pos
		add_child(body)
		var col := CollisionShape3D.new()
		var col_shape := BoxShape3D.new()
		col_shape.size = size
		col.shape = col_shape
		body.add_child(col)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.material_override = _make_material(Color(0.22, 0.20, 0.18))
		body.add_child(mesh)


func _build_master_breaker() -> void:
	# Industrial breaker box: chassis + lever + status light. The lever is
	# a child of a pivot Node3D so we can rotate it on pull without moving
	# the chassis or the light. Brief says ~0.6 × 0.4 × 1.4 units; we use
	# (0.7, 1.4, 0.4) since x and z are the floor plane in Godot.
	var root := Node3D.new()
	root.name = "MasterBreaker"
	root.position = _c.MASTER_BREAKER_POSITION
	# Face the breaker toward the room interior. With Floor 1 centred on the
	# origin and the breaker on the south wall (positive Z), it should look
	# back toward -Z.
	root.rotation.y = 0.0
	add_child(root)

	# Chassis box — sits on the floor, sticks out from the wall.
	_breaker_chassis = MeshInstance3D.new()
	_breaker_chassis.name = "Chassis"
	var chassis_mesh := BoxMesh.new()
	chassis_mesh.size = Vector3(0.7, 1.4, 0.4)
	_breaker_chassis.mesh = chassis_mesh
	_breaker_chassis.material_override = _make_material(Color(0.16, 0.18, 0.22))
	_breaker_chassis.position = Vector3(0, 0.7, 0)
	root.add_child(_breaker_chassis)

	# Lever pivot — sits at lever-base height on the front face of the chassis.
	# When master is OFF the lever points up (+Y); when ON it swings down.
	# We tween rotation.x of this pivot from a negative angle (up) to a
	# positive angle (down) over the pull animation.
	_breaker_lever = Node3D.new()
	_breaker_lever.name = "LeverPivot"
	_breaker_lever.position = Vector3(0, 0.95, -0.22)
	_breaker_lever.rotation.x = -PI * 0.3   # initial: pointing up-and-forward
	root.add_child(_breaker_lever)

	var lever_mesh_node := MeshInstance3D.new()
	lever_mesh_node.name = "Lever"
	var lever_mesh := BoxMesh.new()
	lever_mesh.size = Vector3(0.08, 0.55, 0.08)
	lever_mesh_node.mesh = lever_mesh
	lever_mesh_node.material_override = _make_material(Color(0.78, 0.55, 0.30))
	# Mesh's local origin sits at its centre — offset down by half-height so
	# the pivot is at the lever's base, not its centre.
	lever_mesh_node.position = Vector3(0, 0.275, 0)
	_breaker_lever.add_child(lever_mesh_node)

	# Lever knob — small ball at the tip.
	var knob := MeshInstance3D.new()
	knob.name = "LeverKnob"
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.07
	knob_mesh.height = 0.14
	knob.mesh = knob_mesh
	knob.material_override = _make_material(Color(0.92, 0.78, 0.45))
	knob.position = Vector3(0, 0.55, 0)
	_breaker_lever.add_child(knob)

	# Status light — small emissive disc on top of the chassis.
	_breaker_status_light = MeshInstance3D.new()
	_breaker_status_light.name = "StatusLight"
	var light_mesh := SphereMesh.new()
	light_mesh.radius = 0.07
	light_mesh.height = 0.14
	_breaker_status_light.mesh = light_mesh
	_breaker_status_mat = StandardMaterial3D.new()
	_breaker_status_mat.albedo_color = Color(0.91, 0.31, 0.25)
	_breaker_status_mat.emission_enabled = true
	_breaker_status_mat.emission = Color(0.91, 0.31, 0.25)
	_breaker_status_mat.emission_energy_multiplier = 1.4
	_breaker_status_light.material_override = _breaker_status_mat
	_breaker_status_light.position = Vector3(0, 1.46, 0)
	root.add_child(_breaker_status_light)


# --- State + behaviour -----------------------------------------------------

func _check_master_breaker_interact() -> void:
	if _player == null:
		return
	var pos: Vector3 = _player.global_position
	var d: float = (pos - _c.MASTER_BREAKER_POSITION).length()
	if d > _c.MASTER_BREAKER_INTERACT_RADIUS:
		return
	if Input.is_action_just_pressed(&"interact"):
		_pull_master_breaker()


func _pull_master_breaker() -> void:
	_master_on = true
	_master_anim_t = 0.0
	_target_brightness = 1.0
	_gs.floor_1.master_on = true


func _apply_breaker_visual_state(initial: bool) -> void:
	# Lever rotation interpolates from up-forward (-PI*0.3) to down-forward
	# (+PI*0.4) over the pull animation. When initial=true (re-entry into a
	# room that's already on, or just after _ready), snap to the end state.
	var t: float = _master_anim_t if not initial else (1.0 if _master_on else 0.0)
	if _breaker_lever:
		var start_angle := -PI * 0.3
		var end_angle := PI * 0.4
		_breaker_lever.rotation.x = lerpf(start_angle, end_angle, t)


func _update_status_light(_delta: float) -> void:
	if _breaker_status_mat == null:
		return
	if _master_on:
		# Steady green when on.
		var c := Color(0.36, 0.79, 0.65)
		_breaker_status_mat.albedo_color = c
		_breaker_status_mat.emission = c
		_breaker_status_mat.emission_energy_multiplier = 1.6
	else:
		# Rapid red pulse when off — attention beacon across the dark room.
		var t: float = Time.get_ticks_msec() / 1000.0
		var pulse: float = 0.7 + sin(t * 6.28 * 1.4) * 0.3
		var c := Color(0.91, 0.31, 0.25)
		_breaker_status_mat.albedo_color = c
		_breaker_status_mat.emission = c
		_breaker_status_mat.emission_energy_multiplier = 1.0 + pulse * 1.4


func _apply_brightness_to_lighting() -> void:
	# Map room_brightness (0..1) to a multiplier between dark and lit ambient
	# levels. Both the directional light and the WorldEnvironment ambient
	# energy ride this scalar so the room reads as one cohesive lighting
	# state rather than two independent dimmers.
	var mult: float = lerpf(
		_c.FLOOR_1_DARK_AMBIENT_MULT,
		_c.FLOOR_1_LIT_AMBIENT_MULT,
		_room_brightness,
	)
	if _directional_light:
		_directional_light.light_energy = 0.7 * mult
	if _world_environment and _world_environment.environment:
		_world_environment.environment.ambient_light_energy = 0.6 * mult


func _make_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	return m
