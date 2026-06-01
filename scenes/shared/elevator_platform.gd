extends Node3D

# Physical ride-able elevator for the stacked tower. A single car travels the
# open shaft; the player walks onto the platform, presses E to open a floor
# chooser, picks a floor, and physically rides there — no scene swap. Serves
# Floors 0,1,2,4,5 (Canopy 3 is stairs-only, the Roof tube-only). While travelling, the car owns the
# rider's transform (GameState.riding_elevator), so the tower's visibility +
# camera follow naturally as the floors pass.

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

@export var player_path: NodePath

const SERVED := [0, 1, 2, 4, 5]    # served floors (Canopy 3 stairs-only, Roof 6 tube-only)
const NAMES := {0: "Utility", 1: "Garden", 2: "Arboretum", 4: "Residential", 5: "Sky Lounge"}
const CAR_HALF := 1.7              # platform half-extent (fits inside the ±2 shaft)
const DOOR_HEIGHT := 2.8
const PROMPT_ANCHOR_Y := 2.7       # prompt-stack height above the player's feet
const SPEED := 6.0                 # m/s vertical travel
const INTERACT_RADIUS := 2.4

enum State { IDLE, MOVING, CHOOSING }

var _player: Node3D
var _car: Node3D
var _glow_mat: StandardMaterial3D
var _doors: Array = []             # [{pivot, base_y}]
var _door_open_t := 1.0            # 1 open, 0 closed
var _glow_t := 0.0

var _state: int = State.IDLE
var _car_y := 0.0                  # world y of the platform top
var _target_y := 0.0
var _rider_aboard := false
var _rider_offset := Vector3.ZERO  # rider XZ offset on the platform

var _prompt_root: Node3D
var _prompt_e: Label3D
var _prompt_label: Label3D
# Chooser is a framed 2D overlay (not floating 3D text).
var _chooser_layer: CanvasLayer
var _chooser_text: Label


func _story() -> float:
	return float(_c.FLOOR_3D_STORY_HEIGHT)

func _floor_y(level: int) -> float:
	return float(level) * _story()


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_build_car()
	_build_prompt()
	_car_y = _floor_y(1)           # start at the Garden (the spawn floor)
	_apply_car_y()
	_apply_doors()
	_apply_glow()


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	# Float the prompt stack a fixed height above the player (works whether the
	# car is at their floor or being called from another). The "E" + label are
	# small offsets around this anchor and the whole group scales as one (see
	# _update_label_scale), so they never overlap regardless of zoom.
	if _prompt_root:
		_prompt_root.position.y = _player.global_position.y + PROMPT_ANCHOR_Y
	match _state:
		State.IDLE:
			_update_idle(delta)
		State.MOVING:
			_update_moving(delta)
		State.CHOOSING:
			_update_choosing(delta)
	_apply_car_y()
	_apply_doors()
	_apply_glow()


func _process(_delta: float) -> void:
	_update_label_scale()


# --- State updates --------------------------------------------------------

func _update_idle(delta: float) -> void:
	var near_car: bool = _player_on_car()
	var near_shaft: bool = _player_near_shaft()
	_door_open_t = move_toward(_door_open_t, 1.0 if (near_car or near_shaft) else 0.0, delta * 3.0)
	_glow_t = move_toward(_glow_t, 0.0, delta * 2.0)
	# Prompt.
	_prompt_root.visible = near_shaft
	_prompt_e.visible = near_shaft
	_prompt_label.visible = near_shaft
	_show_chooser(false)
	if near_shaft:
		_prompt_label.text = "Ride elevator" if near_car else "Call elevator"
	if near_shaft and Input.is_action_just_pressed(&"interact"):
		if near_car:
			_set_chooser_text()
			_state = State.CHOOSING
		else:
			# Call the empty car to the player's floor.
			_rider_aboard = false
			_target_y = _floor_y(_player_floor_level())
			_state = State.MOVING


func _update_choosing(delta: float) -> void:
	if not _player_on_car():
		_show_chooser(false)
		_state = State.IDLE
		return
	_door_open_t = move_toward(_door_open_t, 1.0, delta * 3.0)
	_glow_t = move_toward(_glow_t, 0.0, delta * 2.0)
	_prompt_root.visible = false
	_show_chooser(true)
	var here: int = _car_floor_level()
	for lvl in SERVED:
		if lvl == here:
			continue
		if Input.is_action_just_pressed(StringName("seed_select_%d" % lvl)):
			_show_chooser(false)
			_begin_ride(lvl)
			return
	if Input.is_action_just_pressed(&"ui_cancel"):
		_show_chooser(false)
		_state = State.IDLE


func _update_moving(delta: float) -> void:
	_prompt_root.visible = false
	_door_open_t = move_toward(_door_open_t, 0.0, delta * 4.0)
	_glow_t = move_toward(_glow_t, 1.0, delta * 4.0)
	# Only travel once the doors are essentially shut.
	if _door_open_t > 0.15:
		_hold_rider()
		return
	_car_y = move_toward(_car_y, _target_y, SPEED * delta)
	_hold_rider()
	if absf(_car_y - _target_y) < 0.001:
		_car_y = _target_y
		if _rider_aboard:
			_rider_aboard = false
			_gs.set("riding_elevator", false)
		_state = State.IDLE


func _begin_ride(level: int) -> void:
	_rider_aboard = true
	_gs.set("riding_elevator", true)
	var p: Vector3 = _player.global_position
	_rider_offset = Vector3(p.x, 0.0, p.z)
	_target_y = _floor_y(level)
	_state = State.MOVING


func _hold_rider() -> void:
	if not _rider_aboard:
		return
	_player.global_position = Vector3(_rider_offset.x, _car_y, _rider_offset.z)
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO


# --- Queries --------------------------------------------------------------

func _player_on_car() -> bool:
	var p: Vector3 = _player.global_position
	return absf(p.y - _car_y) < 0.7 and absf(p.x) <= CAR_HALF + 0.25 and absf(p.z) <= CAR_HALF + 0.25

func _player_near_shaft() -> bool:
	var p: Vector3 = _player.global_position
	return Vector2(p.x, p.z).length() <= INTERACT_RADIUS

func _player_floor_level() -> int:
	return _nearest_served(_player.global_position.y)

func _car_floor_level() -> int:
	return _nearest_served(_car_y)

func _nearest_served(y: float) -> int:
	var best: int = SERVED[0]
	var bd: float = 1.0e9
	for lvl in SERVED:
		var d: float = absf(y - _floor_y(lvl))
		if d < bd:
			bd = d
			best = lvl
	return best


# --- Apply visuals --------------------------------------------------------

func _apply_car_y() -> void:
	if _car:
		_car.position.y = _car_y

func _apply_doors() -> void:
	var solid: bool = _door_open_t < 0.85   # impenetrable until fully lowered
	for d in _doors:
		d.pivot.position.y = float(d.base_y) - _door_open_t * DOOR_HEIGHT
		d.col.disabled = not solid

func _apply_glow() -> void:
	if _glow_mat == null:
		return
	var base := Color(0.30, 0.55, 0.85)
	var hot := Color(1.0, 0.78, 0.20)
	_glow_mat.emission = base.lerp(hot, _glow_t)
	_glow_mat.emission_energy_multiplier = lerpf(0.5, 4.0, _glow_t)


# --- Build ----------------------------------------------------------------

func _build_car() -> void:
	_car = Node3D.new()
	_car.name = "Car"
	add_child(_car)

	# Platform (collision floor + mesh) — top at the car origin.
	var body := StaticBody3D.new()
	body.name = "Platform"
	_car.add_child(body)
	var plat_mat := StandardMaterial3D.new()
	plat_mat.albedo_color = Color(0.30, 0.33, 0.38)
	plat_mat.metallic = 0.4
	plat_mat.roughness = 0.5
	var pm := MeshInstance3D.new()
	var pbox := BoxMesh.new()
	pbox.size = Vector3(CAR_HALF * 2.0, 0.2, CAR_HALF * 2.0)
	pm.mesh = pbox
	pm.material_override = plat_mat
	pm.position.y = -0.1
	body.add_child(pm)
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = Vector3(CAR_HALF * 2.0, 0.2, CAR_HALF * 2.0)
	col.shape = cs
	col.position.y = -0.1
	body.add_child(col)

	# Glowing inlay on the platform — leaks through the door seams in travel.
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = Color(0.10, 0.12, 0.15)
	_glow_mat.emission_enabled = true
	var glow := MeshInstance3D.new()
	var gbox := BoxMesh.new()
	gbox.size = Vector3(CAR_HALF * 1.8, 0.06, CAR_HALF * 1.8)
	glow.mesh = gbox
	glow.material_override = _glow_mat
	glow.position.y = 0.02
	_car.add_child(glow)

	_build_doors()

func _build_doors() -> void:
	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.40, 0.46, 0.55)
	door_mat.metallic = 0.6
	door_mat.roughness = 0.35
	var faces := [Vector3(0, 0, -CAR_HALF), Vector3(0, 0, CAR_HALF), Vector3(-CAR_HALF, 0, 0), Vector3(CAR_HALF, 0, 0)]
	var yaws := [0.0, 0.0, PI * 0.5, PI * 0.5]
	for i in range(4):
		var pivot := Node3D.new()
		pivot.position = faces[i] + Vector3(0, DOOR_HEIGHT * 0.5, 0)
		pivot.rotation.y = yaws[i]
		_car.add_child(pivot)
		# The panel is a body with collision so you can't walk through it until
		# it's fully lowered (see _apply_doors).
		var sb := StaticBody3D.new()
		pivot.add_child(sb)
		var dsize := Vector3(CAR_HALF * 2.0 * 0.96, DOOR_HEIGHT, 0.08)
		var panel := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = dsize
		panel.mesh = pm
		panel.material_override = door_mat
		sb.add_child(panel)
		var col := CollisionShape3D.new()
		var cs := BoxShape3D.new()
		cs.size = dsize
		col.shape = cs
		sb.add_child(col)
		_doors.append({"pivot": pivot, "base_y": DOOR_HEIGHT * 0.5, "col": col})

func _build_prompt() -> void:
	_prompt_root = Node3D.new()
	_prompt_root.name = "ElevatorPrompt"
	_prompt_root.visible = false
	add_child(_prompt_root)

	# "E" + label are SMALL offsets around the prompt-stack origin and share a
	# fixed pixel_size; _update_label_scale scales the whole _prompt_root as one
	# group, so the gap between them is preserved at every zoom (no overlap).
	_prompt_e = Label3D.new()
	_prompt_e.text = "E"
	_prompt_e.font_size = 84
	_prompt_e.outline_size = 12
	_prompt_e.modulate = Color(1.0, 0.92, 0.55, 1.0)
	_prompt_e.outline_modulate = Color(0, 0, 0, 0.92)
	_prompt_e.pixel_size = 0.0075
	_prompt_e.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_e.no_depth_test = true
	_prompt_e.position = Vector3(0, 0.45, 0)
	_prompt_root.add_child(_prompt_e)

	_prompt_label = Label3D.new()
	_prompt_label.text = "Ride elevator"
	_prompt_label.font_size = 48
	_prompt_label.outline_size = 8
	_prompt_label.modulate = Color(1.0, 0.96, 0.85, 1.0)
	_prompt_label.outline_modulate = Color(0, 0, 0, 0.92)
	_prompt_label.pixel_size = 0.0075
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.position = Vector3(0, -0.28, 0)
	_prompt_root.add_child(_prompt_label)

	_build_chooser_ui()


# Framed, semi-transparent floor chooser shown centred on screen while aboard.
func _build_chooser_ui() -> void:
	_chooser_layer = CanvasLayer.new()
	_chooser_layer.layer = 50
	_chooser_layer.visible = false
	add_child(_chooser_layer)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chooser_layer.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.82)
	sb.border_color = Color(0.82, 0.58, 0.30, 0.7)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(24)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 14
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	_chooser_text = Label.new()
	_chooser_text.add_theme_font_size_override("font_size", 26)
	_chooser_text.add_theme_color_override("font_color", Color(0.96, 0.92, 0.78, 0.98))
	_chooser_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_chooser_text)


# Lists only the floors you can travel to (omits the one you're on).
func _set_chooser_text() -> void:
	if _chooser_text == null:
		return
	var here: int = _car_floor_level()
	var lines := PackedStringArray(["·  TRAVEL TO  ·", ""])
	for lvl in SERVED:
		if lvl == here:
			continue
		lines.append("[ %d ]   %s" % [lvl, NAMES[lvl]])
	lines.append("")
	lines.append("[ ESC ]  cancel")
	_chooser_text.text = "\n".join(lines)


func _show_chooser(b: bool) -> void:
	if _chooser_layer:
		_chooser_layer.visible = b

func _update_label_scale() -> void:
	if _prompt_root == null or not _prompt_root.visible:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	# Scale the whole prompt group (matches iso_player's prompt): keeps the "E"
	# and label locked in relative layout so they never overlap, and keeps the
	# prompt from dominating the frame in close camera modes.
	var def: float = float(_c.CAMERA_ORTHO_SIZE_DEFAULT)
	var k: float = clampf(cam.size / def, 0.18, 1.0)
	_prompt_root.scale = Vector3.ONE * k
