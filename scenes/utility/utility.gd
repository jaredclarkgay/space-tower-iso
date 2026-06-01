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
const VacuumTube = preload("res://scenes/shared/vacuum_tube.gd")

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

# Per-source state. Keyed by system id ("water", "power", ...). Each entry
# carries the runtime tweens (0..1 progress) and refs to the meshes that
# the per-frame updaters drive.
#   connect_t  — 0..1 progress of the lay-pipe animation
#   activate_t — 0..1 progress of the activate animation
#   connected  — has the lay-pipe animation completed
#   active     — has the activate animation completed
#   sys        — Constants.FLOOR_1_SYSTEMS entry (cached for quick access)
#   body_mat   — StandardMaterial3D on the source chassis (for state colour)
#   spine_cold_mat / spine_fill_mat — two materials on the elevator face
#   spine_fill — the "fill" mesh whose y-scale lerps 0..1 over PIPE_FILL_TIME
#   floor_pipe_segments — list of MeshInstance3D for the Manhattan route
#   floor_pipe_mat — shared material for all segments (drives bright lerp)
#   detail — Dictionary of per-mech-detail mesh refs (filled by _build_source_detail)
var _source_state: Dictionary = {}

# Single shared 3D prompt that hops to whichever source is nearest. Built
# once in _ready; position + text + visibility refresh each frame.
var _source_prompt_root: Node3D
var _source_prompt_e: Label3D
var _source_prompt_label: Label3D

# Continuous-motion mechanical details have a phase accumulator so
# wheel-spin / fan-spin / LED-blink doesn't snap on activate.
var _detail_phase := 0.0

# Geometry data returned by FloorChrome.build_elevator_core. _build_spine_pipes
# reads its `corners` to place pipes on the chamfered corner panels. (The
# ride-able car is elevator_platform.gd, not built from this data.)
var _elevator_data: Dictionary = {}

# Yellow pulsing floor halo around the breaker — visible while master is
# off so the player can see the target across the dark room.
var _master_halo: MeshInstance3D
var _master_halo_mat: StandardMaterial3D

# Screen-flash + camera-shake state. Both kick on master-pull and decay.
@export var screen_flash_path: NodePath
@export var camera_pivot_path: NodePath
var _screen_flash: ColorRect
var _camera_pivot: Node3D
var _flash_t := 0.0
var _shake_t := 0.0
var _shake_base_pos: Vector3
var _shake_base_captured: bool = false
# Always-on overhead emergency light at room centre. Low energy; gives the
# room enough fill to be readable when the master is off.
var _emergency_omni: OmniLight3D


func _ready() -> void:
	# Slab + walls + extension grid — same construction the Garden uses, so
	# Floor 1 reads as the same building viewed one story down.
	FloorChrome.build_slab(self, _c)
	FloorChrome.build_walls(self, _c)
	FloorChrome.build_extension_grid(self, _c)
	_elevator_data = FloorChrome.build_elevator_core(self, _c)
	# Corner vacuum tubes — Floor 1 is the bottom of the served stack; its tubes
	# tile up into the Garden's. Bottom port feeds "out into the world".
	VacuumTube.build_corner_tubes(self, _c, false)
	_build_sources()
	_build_spine_pipes()
	_build_floor_pipes()
	_build_source_prompt()
	_build_emergency_omni()
	_build_master_breaker()
	_build_breaker_spot()
	_build_master_halo()

	if player_path:
		_player = get_node(player_path)
	if directional_light_path:
		_directional_light = get_node(directional_light_path)
	if world_environment_path:
		_world_environment = get_node(world_environment_path)
	if screen_flash_path:
		_screen_flash = get_node(screen_flash_path)
	if camera_pivot_path:
		_camera_pivot = get_node(camera_pivot_path)

	# Persist master_on across re-entry — GameState.utility is the source of
	# truth, declared as a typed dict on the autoload.
	if _gs.utility.master_on:
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
	_update_master_halo()
	_update_screen_flash(delta)
	_update_camera_shake(delta)

	if not _master_on:
		_check_master_breaker_interact()
	elif _master_anim_t < 1.0:
		_master_anim_t = min(1.0, _master_anim_t + delta / _c.MASTER_BREAKER_PULL_DURATION)
		_apply_breaker_visual_state(false)

	# Sources only become interactable once the master is on.
	if _master_on:
		_detail_phase += delta
		_advance_source_tweens(delta)
		_update_source_visuals(delta)
		_check_source_interact()
		_update_source_prompt()
	elif _source_prompt_root:
		_source_prompt_root.visible = false


# --- Geometry --------------------------------------------------------------

func _build_spine_pipes() -> void:
	# Six vertical pipes — one per system — running up the four chamfered
	# corner panels of the elevator. Distributed 1-2-1-2 (NW: water, NE:
	# power+waste, SE: atmosphere, SW: data+cargo). When a corner has 2
	# pipes they sit on opposite tangent offsets along the chamfer face.
	# Each pipe is a "cold" cylinder (always-present dim base) plus a
	# "fill" cylinder bottom-anchored so y-scale 0→1 lerps upward fill
	# on activate. Wavefront band sits at the fill's leading edge.
	var pipe_height: float = _c.FLOOR_1_SPINE_PIPE_TOP_Y - _c.FLOOR_1_SPINE_PIPE_BASE_Y
	var pipe_mid_y: float = (_c.FLOOR_1_SPINE_PIPE_BASE_Y + _c.FLOOR_1_SPINE_PIPE_TOP_Y) * 0.5
	# Two-pipe corners: side-offset so each pipe sits half-way between the
	# centre and its end of the chamfer face. Chamfer width = chamfer*sqrt(2).
	var chamfer_width: float = _c.ELEVATOR_CHAMFER * sqrt(2.0)
	var slot_offset: float = chamfer_width * 0.22  # ±slot_offset from centre

	var corners: Dictionary = _elevator_data.get("corners", {})

	for sys in _c.FLOOR_1_SYSTEMS:
		var corner_spec: Array = _c.FLOOR_1_PIPE_CORNERS[sys.id]
		var corner_name: String = corner_spec[0]
		var slot: int = corner_spec[1]
		var corner: Dictionary = corners.get(corner_name, {})
		if corner.is_empty():
			continue
		var centre: Vector3 = corner.centre
		var tangent: Vector3 = corner.tangent
		var normal: Vector3 = corner.normal
		# Push the pipe slightly outboard from the chamfer face so it doesn't
		# z-fight with the panel.
		var outboard: float = _c.FLOOR_1_SPINE_PIPE_RADIUS + 0.06
		var count: int = int(_c.FLOOR_1_CORNER_COUNTS.get(corner_name, 1))
		var slot_pos: float = 0.0 if count == 1 else (slot_offset if slot == 1 else -slot_offset)
		var pipe_pos: Vector3 = (
			centre
			+ tangent * slot_pos
			+ normal * outboard
		)

		var base_col: Color = sys.base_color

		# Cold pipe.
		var cold := MeshInstance3D.new()
		cold.name = "SpinePipe_" + sys.id
		var cold_mesh := CylinderMesh.new()
		cold_mesh.top_radius = _c.FLOOR_1_SPINE_PIPE_RADIUS
		cold_mesh.bottom_radius = _c.FLOOR_1_SPINE_PIPE_RADIUS
		cold_mesh.height = pipe_height
		cold.mesh = cold_mesh
		var cold_mat := StandardMaterial3D.new()
		cold_mat.albedo_color = base_col * _c.FLOOR_1_SOURCE_COLD_MULT
		cold_mat.roughness = 0.5
		cold_mat.metallic = 0.4
		cold.material_override = cold_mat
		cold.position = pipe_pos + Vector3(0, pipe_mid_y, 0)
		add_child(cold)

		# Fill pivot at the pipe's base.
		var fill_pivot := Node3D.new()
		fill_pivot.name = "SpineFillPivot_" + sys.id
		fill_pivot.position = pipe_pos + Vector3(0, _c.FLOOR_1_SPINE_PIPE_BASE_Y, 0) + normal * 0.005
		fill_pivot.scale = Vector3(1, 0.001, 1)
		add_child(fill_pivot)
		var fill := MeshInstance3D.new()
		fill.name = "Fill"
		var fill_mesh := CylinderMesh.new()
		fill_mesh.top_radius = _c.FLOOR_1_SPINE_PIPE_RADIUS * 1.05
		fill_mesh.bottom_radius = _c.FLOOR_1_SPINE_PIPE_RADIUS * 1.05
		fill_mesh.height = pipe_height
		fill.mesh = fill_mesh
		var fill_mat := StandardMaterial3D.new()
		fill_mat.albedo_color = base_col
		fill_mat.emission_enabled = true
		fill_mat.emission = sys.glow_color
		fill_mat.emission_energy_multiplier = 1.6
		fill.material_override = fill_mat
		fill.position = Vector3(0, pipe_height * 0.5, 0)
		fill_pivot.add_child(fill)

		# Wavefront at top edge.
		var wave := MeshInstance3D.new()
		wave.name = "Wavefront"
		var wave_mesh := CylinderMesh.new()
		wave_mesh.top_radius = _c.FLOOR_1_SPINE_PIPE_RADIUS * 1.18
		wave_mesh.bottom_radius = _c.FLOOR_1_SPINE_PIPE_RADIUS * 1.18
		wave_mesh.height = 0.06
		wave.mesh = wave_mesh
		var wave_mat := StandardMaterial3D.new()
		wave_mat.albedo_color = sys.glow_color
		wave_mat.emission_enabled = true
		wave_mat.emission = sys.glow_color
		wave_mat.emission_energy_multiplier = 3.6
		wave.material_override = wave_mat
		wave.position = Vector3(0, pipe_height - 0.03, 0)
		fill_pivot.add_child(wave)
		wave.visible = false

		var st: Dictionary = _source_state.get(sys.id, {})
		st["spine_cold_mat"] = cold_mat
		st["spine_fill_pivot"] = fill_pivot
		st["spine_fill_mat"] = fill_mat
		st["spine_wave"] = wave
		_source_state[sys.id] = st


func _build_sources() -> void:
	# One source object per system. Cold visual + collision; per-source
	# state (chassis mat, mechanical detail refs) cached into
	# _source_state for the connect / activate flows to mutate.
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

		var detail := _build_source_detail(root, sys, size)

		var st: Dictionary = _source_state.get(sys.id, {})
		st["sys"] = sys
		st["root"] = root
		st["body_mat"] = mat
		st["detail"] = detail
		st["connect_t"] = 0.0
		st["activate_t"] = 0.0
		st["fill_t"] = 0.0
		st["connected"] = bool(_gs.utility.connected.get(sys.id, false))
		st["active"] = bool(_gs.utility.pipe_active.get(sys.id, false))
		_source_state[sys.id] = st


func _build_source_detail(root: Node3D, sys: Dictionary, size: Vector3) -> Dictionary:
	# Distinct top/front mechanical detail per source. Returns a dict of
	# named refs so the activate flow + per-frame anim can drive them.
	var refs: Dictionary = {}
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
			refs["wheel"] = wheel
		"knife_switches":
			var switches: Array = []
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
				switches.append(sw)
			refs["switches"] = switches
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
			# Fan blade behind the grille (lower y so it sits below the
			# grille mesh and reads as spinning behind the slats).
			var fan := MeshInstance3D.new()
			fan.name = "FanBlade"
			var fan_mesh := BoxMesh.new()
			fan_mesh.size = Vector3(0.42, 0.005, 0.06)
			fan.mesh = fan_mesh
			fan.material_override = _make_material(Color(0.85, 0.85, 0.85) * 0.4)
			fan.position = Vector3(0, detail_y + 0.015, 0)
			root.add_child(fan)
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
			refs["fan"] = fan
			refs["button"] = btn
			refs["button_mat"] = btn_mat
		"led_grid":
			# 4×4 LED matrix on the front face (-Z direction). Each LED
			# gets its own material so per-frame blinking can drive
			# emission_energy_multiplier independently.
			var spacing: float = 0.08
			var leds: Array = []
			for r in range(4):
				for col2 in range(4):
					var led := MeshInstance3D.new()
					led.name = "LED_%d_%d" % [r, col2]
					var led_mesh := BoxMesh.new()
					led_mesh.size = Vector3(0.04, 0.04, 0.02)
					led.mesh = led_mesh
					var led_mat := StandardMaterial3D.new()
					led_mat.albedo_color = base_col * 0.45
					led_mat.emission_enabled = true
					led_mat.emission = base_col
					led_mat.emission_energy_multiplier = 0.4
					led.material_override = led_mat
					led.position = Vector3(
						-1.5 * spacing + spacing * float(col2),
						0.25 + spacing * float(r),
						-size.z * 0.5 - 0.012,
					)
					root.add_child(led)
					leds.append({"node": led, "mat": led_mat, "phase": randf() * TAU, "rate": 0.7 + randf() * 1.6})
			refs["leds"] = leds
		"sluice_lever":
			var grate := MeshInstance3D.new()
			grate.name = "Grate"
			var grate_mesh := BoxMesh.new()
			grate_mesh.size = Vector3(size.x, 0.04, size.z)
			grate.mesh = grate_mesh
			grate.material_override = _make_material(base_col * 0.5)
			grate.position = Vector3(0, detail_y + 0.02, 0)
			root.add_child(grate)
			# Lever pivot at base of lever so rotation swings down cleanly.
			var lever_pivot := Node3D.new()
			lever_pivot.name = "SluicePivot"
			lever_pivot.position = Vector3(size.x * 0.5 + 0.08, detail_y, 0)
			root.add_child(lever_pivot)
			var lever := MeshInstance3D.new()
			lever.name = "SluiceLever"
			var lever_mesh := BoxMesh.new()
			lever_mesh.size = Vector3(0.06, 0.4, 0.06)
			lever.mesh = lever_mesh
			lever.material_override = _make_material(Color(0.78, 0.55, 0.30) * 0.7)
			lever.position = Vector3(0, 0.20, 0)
			lever_pivot.add_child(lever)
			refs["lever_pivot"] = lever_pivot
		"dispatcher_panel":
			var console := MeshInstance3D.new()
			console.name = "DispatcherConsole"
			var console_mesh := BoxMesh.new()
			console_mesh.size = Vector3(size.x * 0.85, 0.20, size.z * 0.45)
			console.mesh = console_mesh
			console.material_override = _make_material(base_col * 0.6)
			console.position = Vector3(0, detail_y + 0.10, -size.z * 0.18)
			console.rotation.x = -PI * 0.18
			root.add_child(console)
			var lamps: Array = []
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
				lamp_mat.emission = glow_col
				lamp_mat.emission_energy_multiplier = 0.5
				lamp.material_override = lamp_mat
				lamp.position = Vector3(-0.10 + 0.20 * float(k), detail_y + 0.16, -size.z * 0.18)
				root.add_child(lamp)
				lamps.append({"node": lamp, "mat": lamp_mat})
			refs["lamps"] = lamps
	return refs


func _build_floor_pipes() -> void:
	# Manhattan-routed pipe from each source to its spot on the elevator
	# perimeter. One BoxMesh per axis-aligned segment, with corner overlap
	# (each segment extended by w/2 at both ends so adjacent boxes meet
	# cleanly without visible joint blocks).
	# All segments start invisible (visible = false) and a shared material
	# starts at FLOOR_PIPE_COLD_MULT alpha. Connect tween reveals segments
	# in order; activate tween brightens the material.
	for sys in _c.FLOOR_1_SYSTEMS:
		var route: Array = sys.route
		if route.size() < 2:
			continue
		var w: float = float(sys.pipe_width)
		var pipe_root := Node3D.new()
		pipe_root.name = "FloorPipe_" + sys.id
		add_child(pipe_root)

		var mat := StandardMaterial3D.new()
		var base_col: Color = sys.base_color
		mat.albedo_color = base_col * _c.FLOOR_PIPE_COLD_MULT
		mat.roughness = 0.55
		mat.metallic = 0.3
		mat.emission_enabled = true
		mat.emission = sys.glow_color
		mat.emission_energy_multiplier = 0.0   # cold

		var segments: Array = []
		for i in range(route.size() - 1):
			var a: Vector2 = route[i]
			var b: Vector2 = route[i + 1]
			var horizontal: bool = absf(a.y - b.y) < 0.0001
			var seg_len: float = (b - a).length() + w
			var mid: Vector2 = (a + b) * 0.5
			var seg := MeshInstance3D.new()
			seg.name = "Segment_%d" % i
			var box := BoxMesh.new()
			if horizontal:
				box.size = Vector3(seg_len, _c.FLOOR_PIPE_HEIGHT, w)
			else:
				box.size = Vector3(w, _c.FLOOR_PIPE_HEIGHT, seg_len)
			seg.mesh = box
			seg.material_override = mat
			seg.position = Vector3(
				mid.x,
				_c.FLOOR_PIPE_BASE_Y + _c.FLOOR_PIPE_HEIGHT * 0.5,
				mid.y,
			)
			seg.visible = false
			pipe_root.add_child(seg)
			segments.append(seg)

		var st: Dictionary = _source_state.get(sys.id, {})
		st["floor_pipe_root"] = pipe_root
		st["floor_pipe_mat"] = mat
		st["floor_pipe_segments"] = segments
		# If state was persisted as already connected/active, snap visuals
		# to that state right now (no tween).
		if st.get("connected", false):
			for seg in segments:
				seg.visible = true
			st["connect_t"] = 1.0
		if st.get("active", false):
			st["activate_t"] = 1.0
			st["fill_t"] = 1.0
			mat.albedo_color = base_col * _c.FLOOR_PIPE_BRIGHT_MULT
			mat.emission_energy_multiplier = 1.4
			# Spine fill snap to full.
			var pivot: Node3D = st.get("spine_fill_pivot")
			if pivot:
				pivot.scale = Vector3(1, 1, 1)
		_source_state[sys.id] = st


func _build_source_prompt() -> void:
	_source_prompt_root = Node3D.new()
	_source_prompt_root.name = "SourcePromptGroup"
	_source_prompt_root.visible = false
	add_child(_source_prompt_root)

	_source_prompt_e = Label3D.new()
	_source_prompt_e.text = "E"
	_source_prompt_e.font_size = 96
	_source_prompt_e.outline_size = 12
	_source_prompt_e.modulate = Color(1.0, 0.92, 0.55, 1.0)
	_source_prompt_e.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	_source_prompt_e.pixel_size = 0.005
	_source_prompt_e.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_source_prompt_e.no_depth_test = true
	_source_prompt_e.position = Vector3(0, 0.32, 0)
	_source_prompt_root.add_child(_source_prompt_e)

	_source_prompt_label = Label3D.new()
	_source_prompt_label.text = ""
	_source_prompt_label.font_size = 56
	_source_prompt_label.outline_size = 8
	_source_prompt_label.modulate = Color(1.0, 0.96, 0.85, 1.0)
	_source_prompt_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	_source_prompt_label.pixel_size = 0.005
	_source_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_source_prompt_label.no_depth_test = true
	_source_prompt_label.position = Vector3(0, 0.0, 0)
	_source_prompt_root.add_child(_source_prompt_label)


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
	# Rotate so the lever side faces the default camera (NW). With Y-rotation
	# of +45°, the chassis's local -Z (where the lever pivot sits) aligns
	# with world (-X, -Z) — the direction from the breaker toward the camera.
	# If the operator changes CAMERA_YAW_DEG_INITIAL later this won't auto-
	# track, but the chassis still reads as "facing into the room" from
	# every iso angle.
	root.rotation.y = PI * 0.25
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


func _build_master_halo() -> void:
	# Flat emissive disc on the floor around the breaker. Radial-fade
	# alpha is faked with two stacked discs (inner brighter, outer dim
	# fades out). Pulses while master is off, hides when master comes on.
	var halo_root := Node3D.new()
	halo_root.name = "MasterHalo"
	halo_root.position = _c.MASTER_BREAKER_POSITION + Vector3(0, 0.02, 0)
	add_child(halo_root)

	# Inner disc — strong centre.
	_master_halo = MeshInstance3D.new()
	_master_halo.name = "Inner"
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 1.6
	disc_mesh.bottom_radius = 1.6
	disc_mesh.height = 0.01
	_master_halo.mesh = disc_mesh
	_master_halo_mat = StandardMaterial3D.new()
	_master_halo_mat.albedo_color = Color(0.95, 0.62, 0.20, 0.45)
	_master_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_master_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_master_halo_mat.emission_enabled = true
	_master_halo_mat.emission = Color(0.95, 0.62, 0.20)
	_master_halo_mat.emission_energy_multiplier = 1.4
	_master_halo.material_override = _master_halo_mat
	halo_root.add_child(_master_halo)

	# Outer disc — wider, dimmer, softens the edge.
	var outer := MeshInstance3D.new()
	outer.name = "Outer"
	var outer_mesh := CylinderMesh.new()
	outer_mesh.top_radius = 2.6
	outer_mesh.bottom_radius = 2.6
	outer_mesh.height = 0.005
	outer.mesh = outer_mesh
	var outer_mat := StandardMaterial3D.new()
	outer_mat.albedo_color = Color(0.95, 0.62, 0.20, 0.20)
	outer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outer_mat.emission_enabled = true
	outer_mat.emission = Color(0.95, 0.62, 0.20)
	outer_mat.emission_energy_multiplier = 0.6
	outer.material_override = outer_mat
	outer.position.y = -0.005
	halo_root.add_child(outer)

	# Hide if master already on (re-entry into a lit room).
	if _master_on:
		halo_root.visible = false


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


func _update_master_halo() -> void:
	if _master_halo_mat == null:
		return
	if _master_on:
		return
	var t: float = Time.get_ticks_msec() / 1000.0
	var pulse: float = 0.7 + sin(t * 1.5) * 0.3
	_master_halo_mat.emission_energy_multiplier = 1.4 * pulse


func _update_screen_flash(delta: float) -> void:
	if _screen_flash == null:
		return
	if _flash_t > 0.0:
		_flash_t = max(0.0, _flash_t - delta * 2.2)   # decay rate from brief
	var alpha: float = clampf(_flash_t * 0.35, 0.0, 0.35)
	var c := _screen_flash.color
	c.a = alpha
	_screen_flash.color = c
	_screen_flash.visible = alpha > 0.001


func _update_camera_shake(delta: float) -> void:
	if _camera_pivot == null:
		return
	if not _shake_base_captured:
		_shake_base_pos = _camera_pivot.position
		_shake_base_captured = true
	if _shake_t > 0.0:
		_shake_t = max(0.0, _shake_t - delta * 12.0 / 4.0)   # 4-unit shake decaying at 12/s normalised
		var amp: float = _shake_t * 0.18   # world-space metres at full strength
		_camera_pivot.position = _shake_base_pos + Vector3(
			(randf() - 0.5) * 2.0 * amp,
			(randf() - 0.5) * 2.0 * amp,
			(randf() - 0.5) * 2.0 * amp,
		)
	else:
		_camera_pivot.position = _shake_base_pos


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
	_gs.utility.master_on = true
	# Kick off the screen flash + camera shake — they decay each frame
	# in _process and self-clear when t reaches zero.
	_flash_t = 1.0
	_shake_t = 1.0
	if _master_halo:
		_master_halo.visible = false


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


# --- Source interaction loop ---------------------------------------------

# True only while the player is physically standing on this floor (Floor 1 sits
# at y=0 in the tower; global_position.y is its surface). Stops cross-floor
# interactions in the stacked world.
func _player_on_this_floor() -> bool:
	if _player == null:
		return false
	return absf(_player.global_position.y - global_position.y) < 1.5


func _check_source_interact() -> void:
	if _player == null:
		return
	var nearest_id: String = _nearest_source_in_range(_player.global_position)
	if nearest_id == "":
		return
	if not Input.is_action_just_pressed(&"interact"):
		return
	var st: Dictionary = _source_state[nearest_id]
	if not bool(st.get("connected", false)):
		_do_connect(nearest_id)
	elif not bool(st.get("active", false)):
		_do_activate(nearest_id)


func _nearest_source_in_range(player_pos: Vector3) -> String:
	# Y-gate: the per-source range test below is XZ-only (it ignores height so
	# the player's slightly-raised feet don't skew it). In the stacked tower
	# that would otherwise let a player standing on the floor directly above —
	# same XZ as a source — connect/activate it. Require them to be on this
	# floor first. (The master breaker uses a full-3D distance, so it's already
	# height-gated and needs no extra check.)
	if not _player_on_this_floor():
		return ""
	var best := ""
	var best_d: float = _c.SOURCE_INTERACT_RADIUS
	for id in _source_state.keys():
		var st: Dictionary = _source_state[id]
		var sys: Dictionary = st.sys
		var pos: Vector3 = sys.position
		var dx := player_pos.x - pos.x
		var dz := player_pos.z - pos.z
		var d: float = sqrt(dx * dx + dz * dz)
		if d <= best_d:
			best_d = d
			best = id
	return best


func _update_source_prompt() -> void:
	if _source_prompt_root == null:
		return
	if _player == null:
		_source_prompt_root.visible = false
		return
	var nearest_id: String = _nearest_source_in_range(_player.global_position)
	if nearest_id == "":
		_source_prompt_root.visible = false
		return
	var st: Dictionary = _source_state[nearest_id]
	if bool(st.get("active", false)):
		# Already online — no further action; hide the prompt.
		_source_prompt_root.visible = false
		return
	if float(st.get("connect_t", 0.0)) > 0.0 and not bool(st.get("connected", false)):
		# Mid-connect tween — hide so the world animation owns the moment.
		_source_prompt_root.visible = false
		return
	if float(st.get("activate_t", 0.0)) > 0.0 and not bool(st.get("active", false)):
		_source_prompt_root.visible = false
		return
	var sys: Dictionary = st.sys
	var verb: String = sys.connect_verb if not st.get("connected", false) else sys.activate_verb
	var label_text: String = "%s — %s" % [String(sys.name), verb.capitalize()]
	_source_prompt_label.text = label_text
	_source_prompt_root.position = sys.position + Vector3(0, _c.FLOOR_1_SOURCE_SIZE.y + 0.85, 0)
	_source_prompt_root.visible = true


# --- Connect + activate flows --------------------------------------------

func _do_connect(id: String) -> void:
	var st: Dictionary = _source_state[id]
	if bool(st.get("connected", false)) or float(st.get("connect_t", 0.0)) > 0.0:
		return
	st["connect_t"] = 0.0001  # any non-zero kicks _advance_source_tweens
	_source_state[id] = st


func _do_activate(id: String) -> void:
	var st: Dictionary = _source_state[id]
	if bool(st.get("active", false)) or float(st.get("activate_t", 0.0)) > 0.0:
		return
	if not bool(st.get("connected", false)):
		return
	st["activate_t"] = 0.0001
	# Reveal wavefront for the duration of the fill.
	var wave: Node3D = st.get("spine_wave")
	if wave:
		wave.visible = true
	_source_state[id] = st


func _advance_source_tweens(delta: float) -> void:
	# Drives connect_t (0..1 over CONNECT_DURATION) and activate_t (0..1
	# over ACTIVATE_DURATION). When activate_t completes, fill_t starts
	# rising over SPINE_PIPE_FILL_DURATION; when fill_t completes, wave
	# hides and the system is fully active.
	for id in _source_state.keys():
		var st: Dictionary = _source_state[id]
		var ct: float = float(st.get("connect_t", 0.0))
		if ct > 0.0 and ct < 1.0:
			ct = min(1.0, ct + delta / _c.SOURCE_CONNECT_DURATION)
			st["connect_t"] = ct
			if ct >= 1.0:
				st["connected"] = true
				_gs.utility.connected[id] = true
		var at: float = float(st.get("activate_t", 0.0))
		if at > 0.0 and at < 1.0:
			at = min(1.0, at + delta / _c.SOURCE_ACTIVATE_DURATION)
			st["activate_t"] = at
		# Fill begins as activate completes — compute proportional progress
		# combining the activate portion and the spine-fill portion.
		var ft: float = float(st.get("fill_t", 0.0))
		if at >= 1.0 and ft < 1.0:
			ft = min(1.0, ft + delta / _c.SPINE_PIPE_FILL_DURATION)
			st["fill_t"] = ft
			if ft >= 1.0:
				st["active"] = true
				_gs.utility.pipe_active[id] = true
				var wave: Node3D = st.get("spine_wave")
				if wave:
					wave.visible = false
		_source_state[id] = st


func _update_source_visuals(_delta: float) -> void:
	for id in _source_state.keys():
		var st: Dictionary = _source_state[id]
		var sys: Dictionary = st.sys
		var base_col: Color = sys.base_color
		var ct: float = float(st.get("connect_t", 0.0))
		var at: float = float(st.get("activate_t", 0.0))
		var ft: float = float(st.get("fill_t", 0.0))
		var connected: bool = bool(st.get("connected", false))
		var active: bool = bool(st.get("active", false))

		# 1) Source body brightness — three states (cold / primed / active).
		var body_mat: StandardMaterial3D = st.get("body_mat")
		if body_mat:
			var body_mult: float
			if active:
				var pulse: float = 0.95 + sin(_detail_phase * 9.0) * 0.07
				body_mult = _c.SOURCE_ACTIVE_MULT * pulse
			elif connected:
				var breath: float = 0.86 + sin(_detail_phase * 5.7) * 0.12
				body_mult = _c.SOURCE_PRIMED_MULT * breath
			else:
				body_mult = _c.FLOOR_1_SOURCE_COLD_MULT
			body_mat.albedo_color = base_col * body_mult

		# 2) Floor pipe segment reveal — segments appear in route order as
		# connect_t advances. After connected, lerp brightness with at→1.
		var segs: Array = st.get("floor_pipe_segments", [])
		var pipe_mat: StandardMaterial3D = st.get("floor_pipe_mat")
		if segs.size() > 0:
			var visible_progress: float = ct if not connected else 1.0
			var n: int = segs.size()
			# Each segment occupies 1/n of the connect timeline; reveal once
			# its share of progress is reached.
			for i in range(n):
				var threshold: float = float(i) / float(n)
				segs[i].visible = visible_progress > threshold
			if pipe_mat:
				# Brightness mult lerps from cold to bright over fill_t.
				var bright_mult: float = lerpf(
					_c.FLOOR_PIPE_COLD_MULT,
					_c.FLOOR_PIPE_BRIGHT_MULT,
					ft if connected else 0.0,
				)
				pipe_mat.albedo_color = base_col * bright_mult
				pipe_mat.emission_energy_multiplier = lerpf(0.0, 1.4, ft)

		# 3) Spine fill — pivot y-scale tracks ft (with a tiny minimum so
		# the cylinder doesn't fully collapse and z-fight at scale 0).
		var fill_pivot: Node3D = st.get("spine_fill_pivot")
		if fill_pivot:
			fill_pivot.scale = Vector3(1, max(0.001, ft), 1)

		# 4) Mechanical detail anims — only animate continuous motions when
		# active. One-shot transitions ride the activate_t curve.
		_update_detail_anim(st, at, active)


func _update_detail_anim(st: Dictionary, at: float, active: bool) -> void:
	var sys: Dictionary = st.sys
	var detail: Dictionary = st.get("detail", {})
	match sys.mechanical_detail:
		"wheel_valve":
			# Continuous spin while active.
			var wheel: MeshInstance3D = detail.get("wheel")
			if wheel and active:
				wheel.rotation.y = _detail_phase * 0.85
		"knife_switches":
			# Switches flip from -PI*0.18 (off) to +PI*0.32 (down/on) over
			# activate_t, with stagger so they read as a sequence.
			var switches: Array = detail.get("switches", [])
			for i in range(switches.size()):
				var sw: MeshInstance3D = switches[i]
				if sw == null:
					continue
				var local_t: float = clampf(at * 1.6 - float(i) * 0.18, 0.0, 1.0)
				var start_a := -PI * 0.18
				var end_a := PI * 0.32
				sw.rotation.x = lerpf(start_a, end_a, local_t)
		"fan_button":
			var btn: MeshInstance3D = detail.get("button")
			if btn:
				# Button presses down by ~0.04 over activate_t.
				btn.position.y = lerpf(btn.position.y, btn.position.y, 0.0)  # noop placeholder so parser stays happy
				# We only need to set it once — drive from at directly:
				btn.position.y = (_c.FLOOR_1_SOURCE_SIZE.y + 0.04) + 0.06 - at * 0.04
			var fan: MeshInstance3D = detail.get("fan")
			if fan and active:
				fan.rotation.y = _detail_phase * 11.0
		"led_grid":
			var leds: Array = detail.get("leds", [])
			for entry in leds:
				var mat: StandardMaterial3D = entry.mat
				if mat == null:
					continue
				if active:
					var phase: float = entry.phase + _detail_phase * float(entry.rate)
					var blink: float = (sin(phase) + 1.0) * 0.5
					mat.emission_energy_multiplier = 0.4 + blink * 2.0
				else:
					mat.emission_energy_multiplier = 0.4
		"sluice_lever":
			var lever_pivot: Node3D = detail.get("lever_pivot")
			if lever_pivot:
				# Lever rotates from upright (0) to fully down (PI/2) over at.
				lever_pivot.rotation.x = at * (PI * 0.5)
		"dispatcher_panel":
			var lamps: Array = detail.get("lamps", [])
			for entry in lamps:
				var mat: StandardMaterial3D = entry.mat
				if mat == null:
					continue
				if active:
					var pulse: float = 0.7 + sin(_detail_phase * 3.2) * 0.3
					mat.emission_energy_multiplier = 0.5 + at * 1.5 + pulse * 0.6 * at
				else:
					mat.emission_energy_multiplier = 0.5 + at * 1.5
