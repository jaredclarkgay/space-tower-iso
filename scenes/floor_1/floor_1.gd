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
# This commit (M1.1): footprint matches the Garden (30×30 with the same
# wall style + extension grid), emergency lighting is on by default so the
# room reads, and the master breaker has a fixed spotlight on it. The
# player gets a soft top-down follow-spotlight set up in the .tscn.
# M2 layers in the spine pipes + 6 source objects.

const FloorChrome = preload("res://scenes/shared/floor_chrome.gd")

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

var _room_brightness := 0.0
var _target_brightness := 0.0
var _master_on := false
var _master_anim_t := 0.0

@export var player_path: NodePath
var _player: Node3D

@export var directional_light_path: NodePath
@export var world_environment_path: NodePath
var _directional_light: DirectionalLight3D
var _world_environment: WorldEnvironment

var _breaker_chassis: MeshInstance3D
var _breaker_lever: Node3D
var _breaker_status_light: MeshInstance3D
var _breaker_status_mat: StandardMaterial3D
# Spotlight that pools warm light on the breaker even when the master is
# off, so it reads as the obvious target across the dark room.
var _breaker_spot: SpotLight3D
# 3D "E" prompt + label above the breaker. Fades in on approach so the
# player knows it's interactable; hidden once the breaker is on.
var _breaker_prompt_root: Node3D
var _breaker_prompt_e: Label3D
var _breaker_prompt_label: Label3D
# Always-on overhead emergency light at room centre. Low energy; gives the
# room enough fill to be readable when the master is off.
var _emergency_omni: OmniLight3D


func _ready() -> void:
	# Slab + walls + extension grid — same construction the Garden uses, so
	# Floor 1 reads as the same building viewed one story down.
	FloorChrome.build_slab(self, _c)
	FloorChrome.build_walls(self, _c)
	FloorChrome.build_extension_grid(self, _c)
	FloorChrome.build_elevator_core(self, _c)
	_build_spine_pipes()
	_build_sources()
	_build_emergency_omni()
	_build_master_breaker()
	_build_breaker_spot()

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
	if _room_brightness != _target_brightness:
		var k: float = 1.0 - exp(-(1.0 / _c.ROOM_LIGHT_FADE_DURATION) * 4.0 * delta)
		_room_brightness = lerpf(_room_brightness, _target_brightness, k)
		if absf(_room_brightness - _target_brightness) < 0.005:
			_room_brightness = _target_brightness
		_apply_brightness_to_lighting()

	_update_status_light(delta)
	_update_breaker_prompt()

	if not _master_on:
		_check_master_breaker_interact()
	elif _master_anim_t < 1.0:
		_master_anim_t = min(1.0, _master_anim_t + delta / _c.MASTER_BREAKER_PULL_DURATION)
		_apply_breaker_visual_state(false)


# --- Geometry --------------------------------------------------------------

func _build_spine_pipes() -> void:
	# Six vertical pipes attached to the south face (+Z) of the elevator
	# core. Cold (pre-activate) = base_color × COLD_MULT. Pipe order left to
	# right matches FLOOR_1_SYSTEMS pipe_index. The elevator core has a 4×4
	# footprint, so the south face spans x ∈ [-2, +2]; six pipes evenly
	# spaced fit at x = -1.67, -1.0, -0.33, 0.33, 1.0, 1.67.
	var elev_size: float = float(_c.ELEVATOR_RADIUS) * 2.0 * _c.GARDEN_PLOT_SIZE
	var face_z: float = elev_size * 0.5 + _c.FLOOR_1_SPINE_PIPE_RADIUS + 0.02
	var pipe_count: int = _c.FLOOR_1_SYSTEMS.size()
	var pipe_step: float = elev_size / float(pipe_count)
	for sys in _c.FLOOR_1_SYSTEMS:
		var idx: int = int(sys.pipe_index)
		var pipe := MeshInstance3D.new()
		pipe.name = "SpinePipe_" + sys.id
		var pipe_mesh := CylinderMesh.new()
		pipe_mesh.top_radius = _c.FLOOR_1_SPINE_PIPE_RADIUS
		pipe_mesh.bottom_radius = _c.FLOOR_1_SPINE_PIPE_RADIUS
		pipe_mesh.height = _c.FLOOR_1_SPINE_PIPE_TOP_Y - _c.FLOOR_1_SPINE_PIPE_BASE_Y
		pipe.mesh = pipe_mesh
		var mat := StandardMaterial3D.new()
		var base_col: Color = sys.base_color
		mat.albedo_color = base_col * _c.FLOOR_1_SOURCE_COLD_MULT
		mat.roughness = 0.5
		mat.metallic = 0.4
		pipe.material_override = mat
		var cx: float = -elev_size * 0.5 + (float(idx) + 0.5) * pipe_step
		var cy: float = (_c.FLOOR_1_SPINE_PIPE_BASE_Y + _c.FLOOR_1_SPINE_PIPE_TOP_Y) * 0.5
		pipe.position = Vector3(cx, cy, face_z)
		add_child(pipe)


func _build_sources() -> void:
	# One source object per system. Cold visual only — no interaction yet
	# (M3 wires connect, M4 wires activate). Body sits on the floor with a
	# distinct mechanical detail on top so the player reads each source's
	# function at a glance even before approaching it.
	for sys in _c.FLOOR_1_SYSTEMS:
		var root := Node3D.new()
		root.name = "Source_" + sys.id
		root.position = sys.position
		add_child(root)

		var size: Vector3 = _c.FLOOR_1_SOURCE_SIZE
		var body := StaticBody3D.new()
		body.name = "Body"
		root.add_child(body)

		var mesh := MeshInstance3D.new()
		mesh.name = "Chassis"
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		var base_col: Color = sys.base_color
		mat.albedo_color = base_col * _c.FLOOR_1_SOURCE_COLD_MULT
		mat.roughness = 0.7
		mesh.material_override = mat
		mesh.position = Vector3(0, size.y * 0.5, 0)
		body.add_child(mesh)

		var col := CollisionShape3D.new()
		var col_shape := BoxShape3D.new()
		col_shape.size = size
		col.shape = col_shape
		col.position = Vector3(0, size.y * 0.5, 0)
		body.add_child(col)

		_build_source_detail(root, sys, size)


func _build_source_detail(root: Node3D, sys: Dictionary, size: Vector3) -> void:
	# Distinct top/front mechanical detail per source. Cold = inert pose;
	# active animations land in M4. The geometry only — no animation here.
	var detail_y: float = size.y + 0.04
	var base_col: Color = sys.base_color
	var glow_col: Color = sys.glow_color
	match sys.mechanical_detail:
		"wheel_valve":
			var wheel := MeshInstance3D.new()
			wheel.name = "WheelValve"
			var wheel_mesh := TorusMesh.new()
			wheel_mesh.inner_radius = 0.13
			wheel_mesh.outer_radius = 0.22
			wheel.mesh = wheel_mesh
			wheel.material_override = _make_material(base_col * 0.7)
			wheel.position = Vector3(0, detail_y + 0.05, 0)
			root.add_child(wheel)
		"knife_switches":
			for k in range(3):
				var sw := MeshInstance3D.new()
				sw.name = "KnifeSwitch_%d" % k
				var sw_mesh := BoxMesh.new()
				sw_mesh.size = Vector3(0.06, 0.32, 0.04)
				sw.mesh = sw_mesh
				sw.material_override = _make_material(base_col * 0.7)
				sw.position = Vector3(-0.18 + 0.18 * float(k), detail_y + 0.18, 0)
				sw.rotation.x = -PI * 0.18  # leaning back = "off"
				root.add_child(sw)
		"fan_button":
			var grille := MeshInstance3D.new()
			grille.name = "FanGrille"
			var grille_mesh := CylinderMesh.new()
			grille_mesh.top_radius = 0.22
			grille_mesh.bottom_radius = 0.22
			grille_mesh.height = 0.05
			grille.mesh = grille_mesh
			grille.material_override = _make_material(base_col * 0.5)
			grille.position = Vector3(0, detail_y + 0.04, 0)
			root.add_child(grille)
			var btn := MeshInstance3D.new()
			btn.name = "FanButton"
			var btn_mesh := CylinderMesh.new()
			btn_mesh.top_radius = 0.06
			btn_mesh.bottom_radius = 0.06
			btn_mesh.height = 0.06
			btn.mesh = btn_mesh
			var btn_mat := StandardMaterial3D.new()
			btn_mat.albedo_color = Color(0.85, 0.22, 0.18) * 0.55
			btn.material_override = btn_mat
			btn.position = Vector3(0.13, detail_y + 0.06, 0)
			root.add_child(btn)
		"led_grid":
			# 4×4 LED matrix on the front face (-Z direction). Cold = dim.
			var spacing: float = 0.08
			var mat := StandardMaterial3D.new()
			mat.albedo_color = base_col * 0.45
			mat.emission_enabled = true
			mat.emission = base_col * 0.3
			mat.emission_energy_multiplier = 0.4
			for r in range(4):
				for col2 in range(4):
					var led := MeshInstance3D.new()
					led.name = "LED_%d_%d" % [r, col2]
					var led_mesh := BoxMesh.new()
					led_mesh.size = Vector3(0.04, 0.04, 0.02)
					led.mesh = led_mesh
					led.material_override = mat
					led.position = Vector3(
						-1.5 * spacing + spacing * float(col2),
						0.25 + spacing * float(r),
						-size.z * 0.5 - 0.012,
					)
					root.add_child(led)
		"sluice_lever":
			var grate := MeshInstance3D.new()
			grate.name = "Grate"
			var grate_mesh := BoxMesh.new()
			grate_mesh.size = Vector3(size.x, 0.04, size.z)
			grate.mesh = grate_mesh
			grate.material_override = _make_material(base_col * 0.5)
			grate.position = Vector3(0, detail_y + 0.02, 0)
			root.add_child(grate)
			var lever := MeshInstance3D.new()
			lever.name = "SluiceLever"
			var lever_mesh := BoxMesh.new()
			lever_mesh.size = Vector3(0.06, 0.4, 0.06)
			lever.mesh = lever_mesh
			lever.material_override = _make_material(Color(0.78, 0.55, 0.30) * 0.7)
			lever.position = Vector3(size.x * 0.5 + 0.08, detail_y + 0.20, 0)
			root.add_child(lever)
		"dispatcher_panel":
			# A small angled control console + a couple of status LEDs.
			var console := MeshInstance3D.new()
			console.name = "DispatcherConsole"
			var console_mesh := BoxMesh.new()
			console_mesh.size = Vector3(size.x * 0.85, 0.20, size.z * 0.45)
			console.mesh = console_mesh
			console.material_override = _make_material(base_col * 0.6)
			console.position = Vector3(0, detail_y + 0.10, -size.z * 0.18)
			console.rotation.x = -PI * 0.18
			root.add_child(console)
			# Two small dim lamps.
			for k in range(2):
				var lamp := MeshInstance3D.new()
				lamp.name = "Lamp_%d" % k
				var lamp_mesh := SphereMesh.new()
				lamp_mesh.radius = 0.04
				lamp_mesh.height = 0.08
				lamp.mesh = lamp_mesh
				var lamp_mat := StandardMaterial3D.new()
				lamp_mat.albedo_color = glow_col * 0.5
				lamp_mat.emission_enabled = true
				lamp_mat.emission = glow_col * 0.4
				lamp_mat.emission_energy_multiplier = 0.5
				lamp.material_override = lamp_mat
				lamp.position = Vector3(-0.10 + 0.20 * float(k), detail_y + 0.16, -size.z * 0.18)
				root.add_child(lamp)


func _build_emergency_omni() -> void:
	_emergency_omni = OmniLight3D.new()
	_emergency_omni.name = "EmergencyOmni"
	_emergency_omni.light_color = Color(1.0, 0.78, 0.45)   # warm amber
	_emergency_omni.light_energy = _c.FLOOR_1_EMERGENCY_OMNI_ENERGY
	_emergency_omni.omni_range = _c.FLOOR_1_EMERGENCY_OMNI_RANGE
	_emergency_omni.omni_attenuation = 1.5
	_emergency_omni.position = Vector3(0, _c.WALL_HEIGHT - 0.4, 0)
	add_child(_emergency_omni)


func _build_master_breaker() -> void:
	var root := Node3D.new()
	root.name = "MasterBreaker"
	root.position = _c.MASTER_BREAKER_POSITION
	root.rotation.y = 0.0
	add_child(root)

	# Chassis is a StaticBody3D so the player physically collides with it
	# instead of walking through (operator: "my player is walking through
	# the breaker box"). Mesh is a child of the body.
	var body := StaticBody3D.new()
	body.name = "ChassisBody"
	root.add_child(body)
	var chassis_size := Vector3(0.7, 1.4, 0.4)
	_breaker_chassis = MeshInstance3D.new()
	_breaker_chassis.name = "Chassis"
	var chassis_mesh := BoxMesh.new()
	chassis_mesh.size = chassis_size
	_breaker_chassis.mesh = chassis_mesh
	_breaker_chassis.material_override = _make_material(Color(0.16, 0.18, 0.22))
	_breaker_chassis.position = Vector3(0, 0.7, 0)
	body.add_child(_breaker_chassis)
	var col := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	col_shape.size = chassis_size
	col.shape = col_shape
	col.position = Vector3(0, 0.7, 0)
	body.add_child(col)

	_breaker_lever = Node3D.new()
	_breaker_lever.name = "LeverPivot"
	_breaker_lever.position = Vector3(0, 0.95, -0.22)
	_breaker_lever.rotation.x = -PI * 0.3
	root.add_child(_breaker_lever)

	var lever_mesh_node := MeshInstance3D.new()
	lever_mesh_node.name = "Lever"
	var lever_mesh := BoxMesh.new()
	lever_mesh.size = Vector3(0.08, 0.55, 0.08)
	lever_mesh_node.mesh = lever_mesh
	lever_mesh_node.material_override = _make_material(Color(0.78, 0.55, 0.30))
	lever_mesh_node.position = Vector3(0, 0.275, 0)
	_breaker_lever.add_child(lever_mesh_node)

	var knob := MeshInstance3D.new()
	knob.name = "LeverKnob"
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.07
	knob_mesh.height = 0.14
	knob.mesh = knob_mesh
	knob.material_override = _make_material(Color(0.92, 0.78, 0.45))
	knob.position = Vector3(0, 0.55, 0)
	_breaker_lever.add_child(knob)

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

	# 3D interaction prompt — "[E]" + "Pull breaker" subtext above the box.
	# Hidden by default; fades in when the player is in interaction range.
	# Style mirrors the iso slice's plot/dispenser prompt language so the
	# verb-grammar is consistent across floors.
	_breaker_prompt_root = Node3D.new()
	_breaker_prompt_root.name = "BreakerPromptGroup"
	_breaker_prompt_root.position = Vector3(0, 1.85, 0)
	_breaker_prompt_root.visible = false
	root.add_child(_breaker_prompt_root)

	_breaker_prompt_e = Label3D.new()
	_breaker_prompt_e.text = "E"
	_breaker_prompt_e.font_size = 96
	_breaker_prompt_e.outline_size = 12
	_breaker_prompt_e.modulate = Color(1.0, 0.92, 0.55, 1.0)
	_breaker_prompt_e.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	_breaker_prompt_e.pixel_size = 0.005
	_breaker_prompt_e.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_breaker_prompt_e.no_depth_test = true
	_breaker_prompt_e.position = Vector3(0, 0.32, 0)
	_breaker_prompt_root.add_child(_breaker_prompt_e)

	_breaker_prompt_label = Label3D.new()
	_breaker_prompt_label.text = "Pull breaker"
	_breaker_prompt_label.font_size = 56
	_breaker_prompt_label.outline_size = 8
	_breaker_prompt_label.modulate = Color(1.0, 0.96, 0.85, 1.0)
	_breaker_prompt_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	_breaker_prompt_label.pixel_size = 0.005
	_breaker_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_breaker_prompt_label.no_depth_test = true
	_breaker_prompt_label.position = Vector3(0, 0.0, 0)
	_breaker_prompt_root.add_child(_breaker_prompt_label)


func _build_breaker_spot() -> void:
	# Soft top-down spotlight pooled on the breaker — gives the player a
	# clear "this is what to walk toward" cue across the dim room.
	# add_child first, then look_at (F-006 lesson — look_at requires the
	# node to be in the tree).
	_breaker_spot = SpotLight3D.new()
	_breaker_spot.name = "BreakerSpot"
	_breaker_spot.light_color = Color(1.0, 0.92, 0.78)
	_breaker_spot.light_energy = _c.FLOOR_1_BREAKER_SPOT_ENERGY
	_breaker_spot.spot_range = 4.5
	_breaker_spot.spot_angle = 32.0
	_breaker_spot.spot_attenuation = 0.7
	_breaker_spot.position = _c.MASTER_BREAKER_POSITION + Vector3(0, 3.5, 0)
	add_child(_breaker_spot)
	_breaker_spot.look_at(_c.MASTER_BREAKER_POSITION + Vector3(0, 0.7, 0), Vector3(0, 0, -1))


# --- State + behaviour -----------------------------------------------------

func _update_breaker_prompt() -> void:
	if _breaker_prompt_root == null:
		return
	# Once the breaker is on, the prompt stays hidden — there's no reason
	# to re-pull. Before that, show only when the player is in range.
	if _master_on:
		_breaker_prompt_root.visible = false
		return
	if _player == null:
		_breaker_prompt_root.visible = false
		return
	var d: float = (_player.global_position - _c.MASTER_BREAKER_POSITION).length()
	_breaker_prompt_root.visible = d <= _c.MASTER_BREAKER_INTERACT_RADIUS


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
	var t: float = _master_anim_t if not initial else (1.0 if _master_on else 0.0)
	if _breaker_lever:
		var start_angle := -PI * 0.3
		var end_angle := PI * 0.4
		_breaker_lever.rotation.x = lerpf(start_angle, end_angle, t)


func _update_status_light(_delta: float) -> void:
	if _breaker_status_mat == null:
		return
	if _master_on:
		var c := Color(0.36, 0.79, 0.65)
		_breaker_status_mat.albedo_color = c
		_breaker_status_mat.emission = c
		_breaker_status_mat.emission_energy_multiplier = 1.6
	else:
		var t: float = Time.get_ticks_msec() / 1000.0
		var pulse: float = 0.7 + sin(t * 6.28 * 1.4) * 0.3
		var c := Color(0.91, 0.31, 0.25)
		_breaker_status_mat.albedo_color = c
		_breaker_status_mat.emission = c
		_breaker_status_mat.emission_energy_multiplier = 1.0 + pulse * 1.4


func _apply_brightness_to_lighting() -> void:
	# Map room_brightness (0..1) to a multiplier between dark and lit ambient
	# levels. Both the directional light and the WorldEnvironment ambient
	# energy ride this scalar.
	var mult: float = lerpf(
		_c.FLOOR_1_DARK_AMBIENT_MULT,
		_c.FLOOR_1_LIT_AMBIENT_MULT,
		_room_brightness,
	)
	if _directional_light:
		_directional_light.light_energy = 0.7 * mult
	if _world_environment and _world_environment.environment:
		_world_environment.environment.ambient_light_energy = 0.6 * mult
	# When the room comes on, dim the breaker's spotlight so it doesn't
	# stay overbright after the room is lit. Stays at 30% energy when on
	# rather than fully off — keeps the breaker subtly highlighted as a
	# returnable interactable.
	if _breaker_spot:
		_breaker_spot.light_energy = lerpf(
			_c.FLOOR_1_BREAKER_SPOT_ENERGY,
			_c.FLOOR_1_BREAKER_SPOT_ENERGY * 0.3,
			_room_brightness,
		)


func _make_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	return m
