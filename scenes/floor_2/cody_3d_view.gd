extends SubViewportContainer

# Shared 3D-Cody preview component. Used by:
#   - cody_schematic.gd (rotatable: true, auto_spin: false) for the
#     full Schematics modal preview
#   - iso_robot.gd's dialogue panel (rotatable: false, auto_spin: true)
#     so the same chassis appears in the Slippy-style chat pop-up
#
# Builds its own SubViewport with own_world_3d, key+fill DirectionalLights,
# an orthographic-ish Camera3D, and a standalone Cody chassis on a pivot.
# Material refs are kept so colour customisation in GameState can be
# mirrored live via sync_colors_from_state().

@onready var _gs: Node = get_node("/root/GameState")

@export var rotatable: bool = false
@export var auto_spin: bool = false
@export var auto_spin_rate: float = 0.6   # rad/s yaw

var _viewport: SubViewport
var _model_pivot: Node3D
var _is_dragging: bool = false
var _drag_yaw: float = 0.6
var _drag_pitch: float = -0.4
var _model_body_mat: StandardMaterial3D
var _model_dome_mat: StandardMaterial3D


func _ready() -> void:
	stretch = true
	if rotatable:
		mouse_filter = Control.MOUSE_FILTER_STOP
		gui_input.connect(_on_gui_input)
	else:
		# Click-through so the parent dialogue can keep its hover/cursor logic.
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_viewport()
	set_process(auto_spin)


func _process(delta: float) -> void:
	if not auto_spin:
		return
	if _is_dragging:
		return
	_drag_yaw += auto_spin_rate * delta
	_apply_drag_to_pivot()


func sync_colors_from_state() -> void:
	if _model_body_mat:
		_model_body_mat.albedo_color = _gs.cody_body_color
	if _model_dome_mat:
		_model_dome_mat.albedo_color = _gs.cody_dome_color


func reset_pose(yaw: float = 0.6, pitch: float = -0.4) -> void:
	_drag_yaw = yaw
	_drag_pitch = pitch
	_apply_drag_to_pivot()


# --- Viewport + lighting + chassis -----------------------------------------

func _build_viewport() -> void:
	_viewport = SubViewport.new()
	var sz_x: int = max(64, int(custom_minimum_size.x))
	var sz_y: int = max(64, int(custom_minimum_size.y))
	_viewport.size = Vector2i(sz_x, sz_y)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	add_child(_viewport)

	# Camera — pulled back enough to frame the whole chassis with a slight
	# upward tilt. add_child first; look_at requires the node to be in tree.
	var cam := Camera3D.new()
	cam.fov = 35
	_viewport.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0.5, 1.7), Vector3(0, 0.25, 0), Vector3.UP)

	# Key + fill lights for a clean studio look.
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-50, 30, 0)
	key_light.light_color = Color(1.0, 0.94, 0.85)
	key_light.light_energy = 1.4
	_viewport.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-25, -45, 0)
	fill_light.light_color = Color(0.6, 0.75, 1.0)
	fill_light.light_energy = 0.4
	_viewport.add_child(fill_light)

	_model_pivot = Node3D.new()
	_viewport.add_child(_model_pivot)
	_build_chassis_into(_model_pivot)
	_apply_drag_to_pivot()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging = event.pressed
	elif event is InputEventMouseMotion and _is_dragging:
		_drag_yaw -= event.relative.x * 0.01
		_drag_pitch -= event.relative.y * 0.008
		_drag_pitch = clamp(_drag_pitch, -1.2, 0.6)
		_apply_drag_to_pivot()


func _apply_drag_to_pivot() -> void:
	if _model_pivot:
		_model_pivot.rotation = Vector3(_drag_pitch, _drag_yaw, 0.0)


func _build_chassis_into(parent: Node3D) -> void:
	# Body
	_model_body_mat = _make_material(_gs.cody_body_color)
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.32
	bm.bottom_radius = 0.34
	bm.height = 0.18
	body.mesh = bm
	body.material_override = _model_body_mat
	body.position.y = 0.10
	parent.add_child(body)

	# Rim
	var rim := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.36
	rm.bottom_radius = 0.36
	rm.height = 0.04
	rim.mesh = rm
	rim.material_override = _make_material(Color(0.08, 0.16, 0.22))
	rim.position.y = 0.04
	parent.add_child(rim)

	# Dome
	_model_dome_mat = _make_material(_gs.cody_dome_color)
	var dome := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.18
	dm.bottom_radius = 0.26
	dm.height = 0.10
	dome.mesh = dm
	dome.material_override = _model_dome_mat
	dome.position.y = 0.24
	parent.add_child(dome)

	# Direction nub on the dome's +Z face.
	var nub := MeshInstance3D.new()
	var nubm := BoxMesh.new()
	nubm.size = Vector3(0.10, 0.05, 0.06)
	nub.mesh = nubm
	nub.material_override = _make_material(Color(0.10, 0.10, 0.12))
	nub.position = Vector3(0.0, 0.24, 0.20)
	parent.add_child(nub)

	# LED — solid green emissive (no state pulse in the preview).
	var led := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.07, 0.05, 0.07)
	led.mesh = lm
	var led_mat := StandardMaterial3D.new()
	led_mat.albedo_color = Color(0.45, 0.90, 0.45)
	led_mat.emission_enabled = true
	led_mat.emission = Color(0.45, 0.90, 0.45)
	led_mat.emission_energy_multiplier = 1.6
	led_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	led.material_override = led_mat
	led.position.y = 0.32
	parent.add_child(led)

	# Wheels
	for i in range(4):
		var wheel := MeshInstance3D.new()
		var wm := CylinderMesh.new()
		wm.top_radius = 0.05
		wm.bottom_radius = 0.05
		wm.height = 0.05
		wheel.mesh = wm
		wheel.material_override = _make_material(Color(0.08, 0.08, 0.10))
		wheel.rotation = Vector3(0.0, 0.0, deg_to_rad(90.0))
		var angle: float = float(i) * (TAU / 4.0) + PI * 0.25
		wheel.position = Vector3(cos(angle) * 0.30, 0.04, sin(angle) * 0.30)
		parent.add_child(wheel)


func _make_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.65
	return m
