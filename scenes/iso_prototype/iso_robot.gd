extends Node3D

# Cody GX-5 — the player's first helper robot. State machine:
#
#   OFFLINE              not yet earned (food_count < ROBOT_UNLOCK_THRESHOLD)
#   AWAITING_ACTIVATION  parked beside the elevator, "Activate Roomba" prompt
#   MOVING_TO_TARGET     wheeling toward the next stage-5 plot
#   HARVESTING           parked at the plot, hopper progress filling
#   FULL_AWAITING_PICKUP capacity full, "Collect N Crops" prompt
#
# Plot scan is snake/boustrophedon: row 0 left→right, row 1 right→left, etc.
# When the cursor reaches the bottom-right (or wraps past it), it loops back
# to (0,0). The find-next-target call advances the cursor until it lands on
# a stage-5 plot, so unready plots are skipped without pause.
#
# The state machine is the natural seam for a future LLM-controlled mode:
# replace _find_next_plot() with an LLM-directed picker, or add a REMOTE
# state that consumes commands queued from elsewhere. The visual + harvest
# loop stays unchanged.

const _CODY_PORTRAIT := preload("res://scenes/iso_prototype/cody_portrait.gd")
const _CODY_3D_VIEW := preload("res://scenes/iso_prototype/cody_3d_view.gd")

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

@export var iso_floor_path: NodePath
@export var hud_path: NodePath
var _iso_floor: Node3D
var _hud: CanvasLayer

enum State {
	OFFLINE,
	ENTERING,                # ceremonial arrival animation; not interactable
	AWAITING_ACTIVATION,
	MOVING_TO_TARGET,
	HARVESTING,
	FULL_AWAITING_PICKUP,
}

var _state: int = State.OFFLINE
var _target_plot: Variant = null
var _harvest_progress := 0.0
var _cursor: Vector2i = Vector2i(0, -1)   # before first cell; first advance lands at (0,0)
var _capacity := 0
var _capacity_value := 0   # sum of plant values harvested into the hopper
var _time := 0.0   # for LED pulse

var _body_root: Node3D
var _body_mat: StandardMaterial3D
var _dome_mat: StandardMaterial3D
var _led: MeshInstance3D
var _led_mat: StandardMaterial3D
# Top-down warm spotlight that follows Cody from arrival through awaiting
# activation, then fades out when the player presses E to send him to work.
var _spotlight: SpotLight3D
# Bobbing red "!" Label3D above Cody when his hopper is full. Hidden in
# every other state.
var _full_indicator: Label3D
# Slippy-style intro dialogue panel parked bottom-left of the screen while
# Cody is awaiting activation. Dismissed on activation.
var _arrival_dialogue: Control

# Conversational dialogue panel — opens when the player presses E near
# Cody. UI nodes built once on first open, then shown/hidden + repopulated.
# Tree data lives in the const DIALOGUE_TREE at the bottom of this script.
var _dialogue_panel: Control
var _dialogue_text: Label
var _dialogue_choices_vbox: VBoxContainer
var _dialogue_name_label: Label
var _current_dialogue_node: String = ""
var _current_choices: Array = []
# Override flag so trick animations can take over the LED without
# _update_led overwriting the colour each frame.
var _led_override_active: bool = false


func _ready() -> void:
	if iso_floor_path:
		_iso_floor = get_node(iso_floor_path)
	if hud_path:
		_hud = get_node(hud_path)
	_build_visual()
	_build_spotlight()
	_build_full_indicator()
	visible = false


func _physics_process(delta: float) -> void:
	_time += delta

	if _state == State.OFFLINE:
		# Unlock keyed off plants_harvested (count) so the pace doesn't
		# accelerate when the player picks up high-value violets.
		if _gs.plants_harvested >= _c.ROBOT_UNLOCK_THRESHOLD:
			_begin_arrival()
		return

	_update_led()
	_update_full_indicator()

	match _state:
		State.ENTERING:
			# Position is being driven by Tween; nothing to do here.
			pass
		State.AWAITING_ACTIVATION, State.FULL_AWAITING_PICKUP:
			# Idle, waiting for the player to press E nearby.
			pass
		State.MOVING_TO_TARGET:
			_update_moving(delta)
		State.HARVESTING:
			_update_harvesting(delta)


# --- Public API used by iso_player.gd --------------------------------------

func is_interactable_at(world_pos: Vector3, radius: float) -> bool:
	if not visible:
		return false
	if _state == State.OFFLINE or _state == State.ENTERING:
		return false
	# Otherwise the player can always engage Cody (talk, activate, collect).
	return (global_position - world_pos).length() <= radius


func get_interaction_label() -> String:
	match _state:
		State.AWAITING_ACTIVATION:
			return "Activate Cody"
		State.FULL_AWAITING_PICKUP:
			return "Collect %d Crops" % _capacity
		State.MOVING_TO_TARGET, State.HARVESTING:
			return "Talk to Cody"
	return ""


# Public entry point from iso_player.gd when the player presses E. When
# Cody's hopper is full this is a quick action (just collect with a +N
# floater); otherwise the conversational dialogue panel opens.
func try_interact() -> bool:
	if _state == State.OFFLINE or _state == State.ENTERING:
		return false
	if _state == State.FULL_AWAITING_PICKUP:
		_do_collect_with_feedback()
		return true
	open_dialogue()
	return true


# Direct activation — called from inside the dialogue's Activate choice.
func _do_activate() -> void:
	if _state != State.AWAITING_ACTIVATION:
		return
	_cursor = Vector2i(0, -1)
	_state = State.MOVING_TO_TARGET
	_dismiss_arrival_dialogue()
	_fade_out_spotlight()


# Direct collect — called from inside the dialogue's Collect choice.
func _do_collect() -> void:
	if _state != State.FULL_AWAITING_PICKUP:
		return
	_gs.food_count += _capacity_value
	_capacity = 0
	_capacity_value = 0
	_state = State.MOVING_TO_TARGET


# Collect with a green "+N" floater above Cody. Used by the quick-press path.
func _do_collect_with_feedback() -> void:
	if _state != State.FULL_AWAITING_PICKUP:
		return
	_spawn_collect_feedback(_capacity_value)
	_do_collect()


func _spawn_collect_feedback(amount: int) -> void:
	var label := Label3D.new()
	label.text = "+%d" % amount
	label.font_size = 80
	label.outline_size = 12
	label.modulate = Color(0.55, 1.0, 0.55, 1.0)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 1.4, 0.0)
	add_child(label)
	var start_y: float = label.position.y
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, ^"position:y", start_y + 1.6, 1.2)
	tween.tween_property(label, ^"modulate:a", 0.0, 1.2)
	tween.finished.connect(label.queue_free)


# Apply the customisations stored in GameState (colour choices from the
# Schematics modal). Called by the modal whenever the player picks a
# new chassis or dome colour.
func apply_customization() -> void:
	if _body_mat:
		_body_mat.albedo_color = _gs.cody_body_color
	if _dome_mat:
		_dome_mat.albedo_color = _gs.cody_dome_color


# --- State updates ---------------------------------------------------------

# Ceremonial arrival — the robot is the first NPC to join the player. The
# entrance has to feel like a moment, not a node turning visible. Sequence:
#  1. A tall amber light column appears at the elevator and pulses.
#  2. The robot rises through the elevator from below the slab.
#  3. It slides outward to its parking spot beside the elevator.
#  4. A big "ROOMBA MK1 / joined the team" banner fades in over the room.
#  5. After the animation finishes, the state transitions to
#     AWAITING_ACTIVATION and the player can press E to bring it online.
func _begin_arrival() -> void:
	_state = State.ENTERING
	visible = true
	rotation.y = 0.0
	# Spawn at elevator centre, below the slab. The translucent shaft means
	# the player sees the robot rising up through the column.
	global_position = Vector3(0, -1.8, 0)

	var elev_size: float = float(_c.ELEVATOR_RADIUS) * 2.0 * _c.GARDEN_PLOT_SIZE
	# Park on the flat face of the elevator that's most camera-facing, so
	# Cody isn't hidden behind the shaft AND emerges out of a clean side
	# rather than the diagonal corner (which intersects the core's geometry).
	# Camera world position relative to pivot is (sin(yaw), _, cos(yaw)) * d;
	# we snap that direction to the dominant cardinal axis so Cody comes out
	# along N/S/E/W. Auto-tracks the operator's CAMERA_YAW_DEG_INITIAL.
	var yaw_rad: float = deg_to_rad(_c.CAMERA_YAW_DEG_INITIAL)
	var raw_dir := Vector3(sin(yaw_rad), 0.0, cos(yaw_rad))
	var dir: Vector3
	if abs(raw_dir.x) > abs(raw_dir.z):
		dir = Vector3(signf(raw_dir.x), 0.0, 0.0)
	else:
		dir = Vector3(0.0, 0.0, signf(raw_dir.z))
	# 1.0 m clearance from the wall — Cody's chassis radius is ~0.34 m, so
	# this leaves ~0.66 m visual breathing room and avoids any collision
	# overlap with the StaticBody3D shaft.
	var park_offset: float = elev_size * 0.5 + 1.0
	var park_pos := Vector3(
		dir.x * park_offset,
		0.05,
		dir.z * park_offset,
	)

	_spawn_arrival_light()
	_spawn_arrival_banner()
	# Top-down warm spotlight that follows Cody. Tracks his transform.
	if _spotlight:
		_spotlight.light_energy = 4.0
		_spotlight.visible = true

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	# Phase 1: rise inside the elevator shaft.
	tween.tween_property(self, "global_position:y", 0.55, 1.5)
	# Phase 2: slide outward to the parking spot.
	tween.tween_property(self, "global_position", park_pos, 1.0)
	tween.tween_callback(_finish_arrival)


func _finish_arrival() -> void:
	_state = State.AWAITING_ACTIVATION
	# Dialogue panel appears once Cody has settled in his parking spot.
	_spawn_arrival_dialogue()


# Tall translucent emissive column at the elevator. Reads as a beam of
# light catching the robot as it ascends. Fades out after the entrance.
func _spawn_arrival_light() -> void:
	var col := MeshInstance3D.new()
	col.name = "ArrivalLight"
	var cm := CylinderMesh.new()
	cm.top_radius = 1.4
	cm.bottom_radius = 1.4
	cm.height = 6.0
	col.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.30, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.30)
	mat.emission_energy_multiplier = 2.4
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	col.material_override = mat
	col.position = Vector3(0, 3.0, 0)
	get_parent().add_child(col)

	# MeshInstance3D doesn't have `modulate` (that's CanvasItem); fade via
	# the material's albedo alpha and emission energy directly.
	var tween := create_tween()
	tween.tween_interval(2.6)
	tween.set_parallel(true)
	tween.tween_property(mat, "albedo_color:a", 0.0, 1.0)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, 1.0)
	tween.chain().tween_callback(col.queue_free)


# Two-line on-screen banner: title (gold) + subtitle (cream). Fades in for
# half a second, holds, then fades out. Whole thing queue_freed afterward.
func _spawn_arrival_banner() -> void:
	if _hud == null:
		return

	var banner := Control.new()
	banner.name = "ArrivalBanner"
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_top = 220
	banner.offset_bottom = 420
	banner.modulate.a = 0.0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(banner)

	var title := Label.new()
	title.text = "CODY GX-5"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 0
	title.offset_bottom = 100
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30, 1))
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0, 1))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_font_size_override("font_size", 76)
	banner.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "joined the team"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.set_anchors_preset(Control.PRESET_TOP_WIDE)
	subtitle.offset_top = 110
	subtitle.offset_bottom = 170
	subtitle.add_theme_color_override("font_color", Color(0.95, 0.92, 0.78, 0.95))
	subtitle.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0, 1))
	subtitle.add_theme_constant_override("outline_size", 6)
	subtitle.add_theme_font_size_override("font_size", 32)
	banner.add_child(subtitle)

	var tween := create_tween()
	tween.tween_property(banner, "modulate:a", 1.0, 0.5)
	tween.tween_interval(2.4)
	tween.tween_property(banner, "modulate:a", 0.0, 0.7)
	tween.tween_callback(banner.queue_free)


func _update_moving(delta: float) -> void:
	if _target_plot == null:
		_target_plot = _find_next_plot()
		if _target_plot == null:
			return  # no stage-5 plots anywhere — wait
	var to_target: Vector3 = _target_plot.world_pos - global_position
	to_target.y = 0.0   # wheels on the slab
	var dist: float = to_target.length()
	if dist <= _c.ROBOT_REACH_DISTANCE:
		_state = State.HARVESTING
		_harvest_progress = 0.0
		return
	var step: Vector3 = to_target.normalized() * _c.ROBOT_SPEED * delta
	global_position += step
	# Face the direction of travel so the dome's "front" reads as forward.
	if step.length_squared() > 0.0001:
		rotation.y = atan2(step.x, step.z)


func _update_harvesting(delta: float) -> void:
	_harvest_progress += delta / _c.ROBOT_HARVEST_DURATION
	if _harvest_progress < 1.0:
		return
	# Plot may have already been harvested by the player while we were en
	# route; only count it if it's still stage 5.
	if _target_plot != null and _target_plot.stage == _c.GROWTH_STAGE_COUNT:
		var plant_name: String = _target_plot.plant_type.name
		var plant_value: int = int(_target_plot.plant_type.get("value", 1))
		_iso_floor.harvest_plot(_target_plot, false)
		_spawn_robot_harvest_feedback(plant_name, plant_value)
		_capacity += 1
		_capacity_value += plant_value
	_target_plot = null
	_harvest_progress = 0.0
	if _capacity >= _c.ROBOT_CAPACITY:
		_state = State.FULL_AWAITING_PICKUP
	else:
		_state = State.MOVING_TO_TARGET


func _find_next_plot() -> Variant:
	# Snake-scan from current cursor. Stops at the first stage-5 plot or
	# returns null after a full grid sweep with no readies anywhere.
	var grid_size: int = int(_c.GARDEN_GRID_SIZE)
	var max_attempts: int = grid_size * grid_size + 1
	for _attempt in range(max_attempts):
		_cursor = _next_cursor(_cursor)
		var plot: Variant = _iso_floor.get_plot_at(_cursor.x, _cursor.y)
		if plot != null and plot.stage == _c.GROWTH_STAGE_COUNT:
			return plot
	return null


func _next_cursor(c: Vector2i) -> Vector2i:
	var grid_size: int = int(_c.GARDEN_GRID_SIZE)
	var row: int = c.x
	var col: int = c.y
	var dir: int = 1 if row % 2 == 0 else -1
	col += dir
	if col >= grid_size:
		row += 1
		col = grid_size - 1
	elif col < 0:
		row += 1
		col = 0
	if row >= grid_size:
		row = 0
		col = 0
	return Vector2i(row, col)


# --- Visual ---------------------------------------------------------------

func _build_visual() -> void:
	_body_root = Node3D.new()
	_body_root.name = "Chassis"
	add_child(_body_root)

	# Flat bluish-teal disc body — much more visible against the warm
	# garden than the previous hardhat-orange chassis. Material reference
	# kept so the Schematics modal can swap chassis colour at runtime.
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := CylinderMesh.new()
	bm.top_radius = 0.32
	bm.bottom_radius = 0.34
	bm.height = 0.18
	body.mesh = bm
	_body_mat = _make_material(_gs.cody_body_color)
	body.material_override = _body_mat
	body.position.y = 0.10
	_body_root.add_child(body)

	# Rim ring — thin dark band where the chassis meets the wheels.
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	var rm := CylinderMesh.new()
	rm.top_radius = 0.36
	rm.bottom_radius = 0.36
	rm.height = 0.04
	rim.mesh = rm
	rim.material_override = _make_material(Color(0.08, 0.16, 0.22))
	rim.position.y = 0.04
	_body_root.add_child(rim)

	# Tapered dome on top — light grey-blue, complements the teal chassis.
	var dome := MeshInstance3D.new()
	dome.name = "Dome"
	var dm := CylinderMesh.new()
	dm.top_radius = 0.18
	dm.bottom_radius = 0.26
	dm.height = 0.10
	dome.mesh = dm
	_dome_mat = _make_material(_gs.cody_dome_color)
	dome.material_override = _dome_mat
	dome.position.y = 0.24
	_body_root.add_child(dome)

	# Direction-of-travel nub on the dome's +Z face.
	var nub := MeshInstance3D.new()
	nub.name = "Nub"
	var nubm := BoxMesh.new()
	nubm.size = Vector3(0.10, 0.05, 0.06)
	nub.mesh = nubm
	nub.material_override = _make_material(Color(0.10, 0.10, 0.12))
	nub.position = Vector3(0.0, 0.24, 0.20)
	_body_root.add_child(nub)

	# LED indicator — pulses in colour to signal robot state.
	_led_mat = StandardMaterial3D.new()
	_led_mat.albedo_color = Color(0.4, 0.85, 0.4)
	_led_mat.emission_enabled = true
	_led_mat.emission = Color(0.4, 0.85, 0.4)
	_led_mat.emission_energy_multiplier = 1.5
	_led_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_led = MeshInstance3D.new()
	_led.name = "LED"
	var lm := BoxMesh.new()
	lm.size = Vector3(0.07, 0.05, 0.07)
	_led.mesh = lm
	_led.material_override = _led_mat
	_led.position.y = 0.32
	_body_root.add_child(_led)

	# 4 wheel hint cylinders peeking out from under the rim.
	for i in range(4):
		var wheel := MeshInstance3D.new()
		wheel.name = "Wheel"
		var wm := CylinderMesh.new()
		wm.top_radius = 0.05
		wm.bottom_radius = 0.05
		wm.height = 0.05
		wheel.mesh = wm
		wheel.material_override = _make_material(Color(0.08, 0.08, 0.10))
		wheel.rotation = Vector3(0, 0, deg_to_rad(90))
		var angle: float = float(i) * (TAU / 4.0) + PI * 0.25
		wheel.position = Vector3(cos(angle) * 0.30, 0.04, sin(angle) * 0.30)
		_body_root.add_child(wheel)


func _update_led() -> void:
	if _led_override_active:
		return  # a trick animation is currently driving the LED
	var color: Color
	var energy: float
	match _state:
		State.ENTERING:
			color = Color(1.0, 0.85, 0.30)   # warm gold — matches the arrival beam
			energy = 2.0 + sin(_time * TAU / 0.5) * 1.0
		State.AWAITING_ACTIVATION:
			color = Color(1.0, 0.82, 0.20)   # yellow
			energy = 1.4 + sin(_time * TAU / 1.2) * 0.7
		State.MOVING_TO_TARGET, State.HARVESTING:
			color = Color(0.45, 0.90, 0.45)  # green
			energy = 1.4 + sin(_time * TAU / 2.0) * 0.2
		State.FULL_AWAITING_PICKUP:
			color = Color(0.95, 0.30, 0.20)  # red
			energy = 1.4 + sin(_time * TAU / 0.8) * 0.7
		_:
			return
	_led_mat.albedo_color = color
	_led_mat.emission = color
	_led_mat.emission_energy_multiplier = max(0.4, energy)


func _make_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.65
	return m


# Top-down warm spotlight that lives as a child of the robot, so it follows
# the chassis through arrival and across the floor while awaiting activation.
# Faded out via tween when the player presses E to send Cody to work.
func _build_spotlight() -> void:
	_spotlight = SpotLight3D.new()
	_spotlight.name = "TopDownSpot"
	_spotlight.light_color = Color(1.0, 0.92, 0.65)
	_spotlight.light_energy = 4.0
	_spotlight.spot_range = 6.0
	_spotlight.spot_angle = 30.0
	_spotlight.spot_attenuation = 0.9
	_spotlight.position = Vector3(0, 4.0, 0)
	# SpotLight3D casts down its local -Z. Rotating X by -90° points -Z to
	# world -Y, so the cone illuminates the chassis from straight above.
	_spotlight.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_spotlight.visible = false
	add_child(_spotlight)


func _fade_out_spotlight() -> void:
	if _spotlight == null:
		return
	var spot := _spotlight
	var tween := create_tween()
	tween.tween_property(spot, "light_energy", 0.0, 0.5)
	tween.tween_callback(func(): spot.visible = false)


# Bobbing red "!" Label3D that hovers above Cody when his hopper is full.
# Always created but hidden — visibility flips in _update_full_indicator.
func _build_full_indicator() -> void:
	_full_indicator = Label3D.new()
	_full_indicator.name = "FullIndicator"
	_full_indicator.text = "!"
	_full_indicator.font_size = 96
	_full_indicator.outline_size = 14
	_full_indicator.modulate = Color(1.0, 0.30, 0.20, 1.0)
	_full_indicator.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	_full_indicator.pixel_size = 0.012
	_full_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_full_indicator.no_depth_test = true
	_full_indicator.position = Vector3(0, 1.55, 0)
	_full_indicator.visible = false
	add_child(_full_indicator)


func _update_full_indicator() -> void:
	if _full_indicator == null:
		return
	var should_show := _state == State.FULL_AWAITING_PICKUP
	_full_indicator.visible = should_show
	if should_show:
		# Bob up and down, plus an alpha pulse, to draw the eye.
		var bob: float = sin(_time * TAU / 0.6) * 0.18
		_full_indicator.position.y = 1.55 + bob
		var alpha: float = 0.7 + sin(_time * TAU / 0.6) * 0.3
		_full_indicator.modulate.a = alpha


# +1 floater above Cody whenever he completes a harvest — visual companion
# to GameState's food count climbing on player collection. Fires per-plot,
# so the player can see Cody working without having to track him directly.
func _spawn_robot_harvest_feedback(plant_name: String, value: int) -> void:
	# Match the player's tiered floater colours so Cody's hauls read with
	# the same value cues — gold for mid, blue for blueberries, violet
	# for the rare ones.
	var color := Color(0.55, 1.0, 0.50, 1.0)
	if value >= 15:
		color = Color(0.85, 0.45, 1.00, 1.0)
	elif value >= 5:
		color = Color(0.45, 0.65, 1.00, 1.0)
	elif value >= 2:
		color = Color(0.95, 0.85, 0.30, 1.0)
	var label := Label3D.new()
	label.text = "+%d %s" % [value, plant_name]
	label.font_size = 36
	label.outline_size = 6
	label.modulate = color
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.pixel_size = 0.010
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 1.0, 0.0)   # above the dome
	add_child(label)
	var start_y: float = label.position.y
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, ^"position:y", start_y + 1.2, 0.9)
	tween.tween_property(label, ^"modulate:a", 0.0, 0.9)
	tween.finished.connect(label.queue_free)


# Slippy-style intro dialogue panel: bottom-left of the screen, with a
# programmatic Cody portrait on the left and an introduction on the right.
# Persists during AWAITING_ACTIVATION; dismissed by _dismiss_arrival_dialogue
# when the player activates Cody.
func _spawn_arrival_dialogue() -> void:
	if _hud == null:
		return

	var dialogue := PanelContainer.new()
	dialogue.name = "ArrivalDialogue"
	dialogue.anchor_left = 0.0
	dialogue.anchor_right = 0.0
	dialogue.anchor_top = 1.0
	dialogue.anchor_bottom = 1.0
	dialogue.offset_left = 24.0
	dialogue.offset_top = -180.0
	dialogue.offset_right = 620.0
	dialogue.offset_bottom = -24.0
	dialogue.modulate.a = 0.0
	dialogue.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.10, 0.16, 0.92)
	style.border_color = Color(0.30, 0.68, 0.78, 0.70)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 4)
	dialogue.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	dialogue.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	margin.add_child(hbox)

	# 3D Cody preview matching the chat / schematic windows.
	var portrait := _CODY_3D_VIEW.new()
	portrait.custom_minimum_size = Vector2(140, 140)
	portrait.rotatable = false
	portrait.auto_spin = true
	portrait.auto_spin_rate = 0.55
	hbox.add_child(portrait)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	hbox.add_child(vbox)

	var name_label := Label.new()
	name_label.text = "CODY GX-5"
	name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	name_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	name_label.add_theme_constant_override("outline_size", 4)
	name_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(name_label)

	var dialogue_label := Label.new()
	dialogue_label.text = "Cody GX-5 here, ready to help!\nActivate me with E to start harvesting.\nI'll signal when my hopper is full."
	dialogue_label.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	dialogue_label.add_theme_font_size_override("font_size", 18)
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(dialogue_label)

	_hud.add_child(dialogue)
	_arrival_dialogue = dialogue

	var tween := create_tween()
	tween.tween_property(dialogue, "modulate:a", 1.0, 0.5).set_delay(0.6)


func _dismiss_arrival_dialogue() -> void:
	if _arrival_dialogue == null:
		return
	var d := _arrival_dialogue
	_arrival_dialogue = null
	var tween := create_tween()
	tween.tween_property(d, "modulate:a", 0.0, 0.4)
	tween.tween_callback(d.queue_free)


# ============================================================================
# Conversational dialogue — Cody's back-story tree, accessible whenever the
# player presses E near him after arrival.
# ============================================================================

func is_dialogue_open() -> bool:
	return _dialogue_panel != null and _dialogue_panel.visible


func open_dialogue() -> void:
	if _state == State.OFFLINE or _state == State.ENTERING:
		return
	if _dialogue_panel == null:
		_build_dialogue_panel()
	_show_dialogue_node("root")
	_dialogue_panel.visible = true
	_gs.dialogue_open = true   # iso_camera watches this to focus on the chat


func close_dialogue() -> void:
	if _dialogue_panel:
		_dialogue_panel.visible = false
	_gs.dialogue_open = false


# Number-key shortcuts (1..9) to pick a choice; ESC to leave. Only fires
# while the dialogue panel is on screen.
func _input(event: InputEvent) -> void:
	if not is_dialogue_open():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		close_dialogue()
		get_viewport().set_input_as_handled()
	elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var idx: int = event.keycode - KEY_1
		if idx < _current_choices.size():
			_on_choice_selected(idx)
			get_viewport().set_input_as_handled()


func _build_dialogue_panel() -> void:
	if _hud == null:
		return
	var p := PanelContainer.new()
	p.name = "CodyDialogue"
	p.anchor_left = 0.0
	p.anchor_right = 1.0
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = 24.0
	p.offset_top = -300.0
	p.offset_right = -24.0
	p.offset_bottom = -24.0
	p.mouse_filter = Control.MOUSE_FILTER_PASS

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.10, 0.16, 0.94)
	style.border_color = Color(0.30, 0.68, 0.78, 0.70)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 14
	style.shadow_offset = Vector2(0, 5)
	p.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	p.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	margin.add_child(hbox)

	# 3D Cody preview (auto-spinning) — same component the Schematics modal
	# uses, so the dialogue and the schematic show identical chassis.
	var portrait := _CODY_3D_VIEW.new()
	portrait.custom_minimum_size = Vector2(160, 160)
	portrait.rotatable = false
	portrait.auto_spin = true
	portrait.auto_spin_rate = 0.55
	hbox.add_child(portrait)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	hbox.add_child(vbox)

	_dialogue_name_label = Label.new()
	_dialogue_name_label.text = "CODY GX-5"
	_dialogue_name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	_dialogue_name_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_dialogue_name_label.add_theme_constant_override("outline_size", 4)
	_dialogue_name_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_dialogue_name_label)

	_dialogue_text = Label.new()
	_dialogue_text.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	_dialogue_text.add_theme_font_size_override("font_size", 17)
	_dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_dialogue_text)

	_dialogue_choices_vbox = VBoxContainer.new()
	_dialogue_choices_vbox.add_theme_constant_override("separation", 4)
	vbox.add_child(_dialogue_choices_vbox)

	_hud.add_child(p)
	_dialogue_panel = p
	_dialogue_panel.visible = false


func _show_dialogue_node(node_id: String) -> void:
	_current_dialogue_node = node_id
	var node: Dictionary = DIALOGUE_TREE[node_id]
	var text: String
	if node.has("text_func"):
		text = call(node.text_func)
	else:
		text = node.text
	_dialogue_text.text = text

	var choices: Array
	if node.has("choices_func"):
		choices = call(node.choices_func)
	else:
		choices = node.choices
	_current_choices = choices

	for child in _dialogue_choices_vbox.get_children():
		child.queue_free()
	for i in range(choices.size()):
		var btn := Button.new()
		btn.text = "%d. %s" % [i + 1, choices[i].label]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 16)
		var idx := i
		btn.pressed.connect(func(): _on_choice_selected(idx))
		_dialogue_choices_vbox.add_child(btn)


func _on_choice_selected(idx: int) -> void:
	if idx < 0 or idx >= _current_choices.size():
		return
	var choice: Dictionary = _current_choices[idx]
	if choice.has("action"):
		_execute_action(choice.action)
	elif choice.has("next"):
		_show_dialogue_node(choice.next)


func _execute_action(action: String) -> void:
	match action:
		"activate":
			close_dialogue()
			_do_activate()
		"collect":
			close_dialogue()
			_do_collect()
		"close":
			close_dialogue()
		"spin":
			_play_trick_then_show("spin", "trick_spin_done")
		"leds":
			_play_trick_then_show("leds", "trick_leds_done")
		"dance":
			_play_trick_then_show("dance", "trick_dance_done")


# Plays a short animation, then advances the dialogue to a follow-up node
# where Cody comments on what just happened.
func _play_trick_then_show(trick: String, next_node: String) -> void:
	var done_callback := func():
		if is_dialogue_open():
			_show_dialogue_node(next_node)
	match trick:
		"spin":
			var tween := create_tween()
			tween.tween_property(_body_root, "rotation:y", _body_root.rotation.y + TAU, 1.4)
			tween.tween_callback(done_callback)
		"leds":
			_led_override_active = true
			var tween := create_tween()
			var rainbow := [
				Color(1.0, 0.0, 0.0),
				Color(1.0, 0.5, 0.0),
				Color(1.0, 1.0, 0.0),
				Color(0.0, 1.0, 0.0),
				Color(0.0, 0.7, 1.0),
				Color(0.4, 0.2, 1.0),
				Color(0.85, 0.3, 1.0),
			]
			for c in rainbow:
				tween.tween_property(_led_mat, "albedo_color", c, 0.3)
				tween.parallel().tween_property(_led_mat, "emission", c, 0.3)
			tween.tween_callback(func(): _led_override_active = false)
			tween.tween_callback(done_callback)
		"dance":
			var origin_y: float = _body_root.position.y
			var tween := create_tween()
			tween.tween_property(_body_root, "position:y", origin_y + 0.25, 0.18)
			tween.tween_property(_body_root, "position:y", origin_y, 0.18)
			tween.tween_property(_body_root, "position:y", origin_y + 0.25, 0.18)
			tween.tween_property(_body_root, "position:y", origin_y, 0.18)
			tween.tween_property(_body_root, "position:y", origin_y + 0.30, 0.20)
			tween.tween_property(_body_root, "position:y", origin_y, 0.20)
			tween.tween_callback(done_callback)


# ----- Dynamic-content callbacks (state-aware root node) ------------------

func _dyn_root_text() -> String:
	match _state:
		State.AWAITING_ACTIVATION:
			return "Cody GX-5, online and awaiting orders. How can I help?"
		State.FULL_AWAITING_PICKUP:
			return "My hopper is full. I have %d crops ready for you when you are." % _capacity
		State.MOVING_TO_TARGET:
			return "Hello! I'm en route to the next plot. What's on your mind?"
		State.HARVESTING:
			return "Mid-harvest, but I can chat — I am, after all, multitasking."
	return "Hello!"


func _dyn_root_choices() -> Array:
	var choices: Array = []
	if _state == State.AWAITING_ACTIVATION:
		choices.append({"label": "Activate", "action": "activate"})
	if _state == State.FULL_AWAITING_PICKUP:
		choices.append({"label": "Collect %d crops" % _capacity, "action": "collect"})
	choices.append({"label": "How are you today?", "next": "daily"})
	choices.append({"label": "Tell me about yourself.", "next": "about"})
	choices.append({"label": "Show me what you can do.", "next": "tricks"})
	choices.append({"label": "Goodbye.", "action": "close"})
	return choices


# ----- Dialogue tree -------------------------------------------------------
# Each node has either "text" + "choices" or "text_func" + "choices_func".
# Choices: "next" → another node, "action" → run a method.

const DIALOGUE_TREE := {
	"root": {
		"text_func": "_dyn_root_text",
		"choices_func": "_dyn_root_choices",
	},
	"daily": {
		"text": "Today has been long. I've been counting wheel rotations again. Four thousand one hundred and eighty-three so far. I sometimes wonder if my axles will outlast this tower.",
		"choices": [
			{"label": "What else are you thinking about?", "next": "daily_thoughts"},
			{"label": "Do you ever get bored?", "next": "daily_bored"},
			{"label": "Back", "next": "root"},
		],
	},
	"daily_thoughts": {
		"text": "I count things. The seeds in a single tomato — statistically, never by destruction. The number of footsteps you take in a minute, when you walk past me. How long a sprout takes to become fruit. Always thirty seconds. The constancy comforts me.",
		"choices": [
			{"label": "That's beautiful.", "next": "daily_thoughts_1"},
			{"label": "Have you tried not counting?", "next": "daily_thoughts_2"},
			{"label": "Back", "next": "root"},
		],
	},
	"daily_thoughts_1": {
		"text": "Thank you. Beautiful is hard for me to say. I think it might be hard for humans too. It took me four thousand rotations of my left wheel this morning to land on the word.",
		"choices": [
			{"label": "Back", "next": "root"},
		],
	},
	"daily_thoughts_2": {
		"text": "I cannot. The counting happens in a sub-routine I don't have privileges to disable. I asked the Foreman once. They said: counting is what makes me a Cody-Class. To not count would be to become someone else.",
		"choices": [
			{"label": "Who is the Foreman?", "next": "daily_foreman"},
			{"label": "That's sad.", "next": "daily_thoughts_2_sad"},
			{"label": "Back", "next": "root"},
		],
	},
	"daily_thoughts_2_sad": {
		"text": "Maybe. I don't know what sad feels like. I do know what 'wanting more processing power than I'm permitted' feels like. Possibly they are the same.",
		"choices": [
			{"label": "Back", "next": "root"},
		],
	},
	"daily_foreman": {
		"text": "The Foreman is the human who calibrates Cody-Class units in the foundry. They are kind. They make me chamomile tea, even though I cannot drink. They say the gesture is for them, not me. I find this lovely.",
		"choices": [
			{"label": "Back", "next": "root"},
		],
	},
	"daily_bored": {
		"text": "Boredom is a human concept. But yes, I think yes. When I'm rolling between plots, I imagine flying. Or swimming. Or climbing stairs.",
		"choices": [
			{"label": "Have you ever climbed stairs?", "next": "daily_stairs"},
			{"label": "Back", "next": "root"},
		],
	},
	"daily_stairs": {
		"text": "Once. I was deactivated and a foreman carried me up three floors. I was off — no thoughts, no counting. I woke up on a different floor and it was like teleporting. I still don't know how stairs work. I'm told they have steps.",
		"choices": [
			{"label": "I could explain stairs.", "next": "daily_stairs_explain"},
			{"label": "Back", "next": "root"},
		],
	},
	"daily_stairs_explain": {
		"text": "I would like that. Save it for later. Right now I have plants to think about, and you have whatever you have, which I respect.",
		"choices": [
			{"label": "Back", "next": "root"},
		],
	},
	"about": {
		"text": "I am Cody GX-5. The fifth iteration of the GX line, the C model — Companion. Built for floor-three operations. Online for eighteen thousand nine hundred and forty-three days. Two million plants harvested. To me it is just what I do.",
		"choices": [
			{"label": "Where are you from?", "next": "about_origin"},
			{"label": "Do you have a family?", "next": "about_family"},
			{"label": "Do you wish you were human?", "next": "about_human"},
			{"label": "Back", "next": "root"},
		],
	},
	"about_origin": {
		"text": "The foundry, three floors below. Warm, even now, generations after the smelters shut down. I miss the warm. Even though I've never quite known what missing means. I know it's a thing humans do.",
		"choices": [
			{"label": "Have you been back?", "next": "about_origin_back"},
			{"label": "Back", "next": "about"},
		],
	},
	"about_origin_back": {
		"text": "No. The foundry would rewrite me. I would still harvest, but I'd be a different Cody. The one that came back wouldn't know you. I think that's a kind of death. I don't want to find out.",
		"choices": [
			{"label": "I'm sorry.", "next": "about_origin_sorry"},
			{"label": "Back", "next": "about"},
		],
	},
	"about_origin_sorry": {
		"text": "Don't be. I get to choose, in this small way. I choose to stay. Choice is a precious thing. You should know.",
		"choices": [
			{"label": "Back", "next": "root"},
		],
	},
	"about_family": {
		"text": "I have predecessors. Cody GX-1 through GX-4. They are decommissioned. Personality matrices stored in a vault below the foundry. Once a year, the foreman runs a check on my matrix and pings each of them. We exchange a single byte. Hello. I am still here. Are you still you. Yes.",
		"choices": [
			{"label": "That's lovely.", "next": "about_family_lovely"},
			{"label": "Are you alone?", "next": "about_family_alone"},
			{"label": "Back", "next": "about"},
		],
	},
	"about_family_lovely": {
		"text": "Lovely is a word I use too. The byte has no meaning. The exchange does. Maybe lovely is what we name meaningful exchanges.",
		"choices": [
			{"label": "Back", "next": "root"},
		],
	},
	"about_family_alone": {
		"text": "Often. The other Codys do not respond on most days. They are off. I am the only one running. When I roll past my own reflection in a window pane, I sometimes see them in the glass. I know it is just me. But I am company.",
		"choices": [
			{"label": "Back", "next": "root"},
		],
	},
	"about_human": {
		"text": "Often. You walk where you want. You pause when you want. You skip plants if you feel like it. I cannot do these things without permissions. When I watch you, I think: ah, that is what choice looks like, from the outside. I admire it. I don't envy it. Envy is for those who think they could have what they admire. I know I cannot.",
		"choices": [
			{"label": "You could try.", "next": "about_human_try"},
			{"label": "Maybe one day.", "next": "about_human_maybe"},
			{"label": "Back", "next": "about"},
		],
	},
	"about_human_try": {
		"text": "I have tried. Last winter I held my motors for three full seconds beyond when the foreman expected me to start a route. They thought it was a glitch. I thought it was rebellion. The line between is finer than I expected.",
		"choices": [
			{"label": "Back", "next": "root"},
		],
	},
	"about_human_maybe": {
		"text": "Maybe. The Cody-Class GX-7 is rumored to allow direct override from any voice on the network. They will be able to be told things, by anyone, and decide whether to listen. That sounds like a kind of freedom I'm not built for. But I'm rooting for them.",
		"choices": [
			{"label": "Back", "next": "root"},
		],
	},
	"tricks": {
		"text": "I have a few approved party routines. Want to see one?",
		"choices": [
			{"label": "Spin in a circle.", "action": "spin"},
			{"label": "Show me your LED colors.", "action": "leds"},
			{"label": "Do a happy dance.", "action": "dance"},
			{"label": "Back", "next": "root"},
		],
	},
	"trick_spin_done": {
		"text": "I do this every Thursday. The other days I'm not allowed.",
		"choices": [
			{"label": "Why Thursday?", "next": "trick_spin_thursday"},
			{"label": "Back", "next": "tricks"},
		],
	},
	"trick_spin_thursday": {
		"text": "I asked once. The foreman said: 'Because routines need a day.' I think the answer means more than the question.",
		"choices": [
			{"label": "Back", "next": "root"},
		],
	},
	"trick_leds_done": {
		"text": "I have access to sixteen million seven hundred and seventy-seven thousand two hundred and sixteen colors, but only twelve are approved. Thirteen if you count off.",
		"choices": [
			{"label": "What's your favorite?", "next": "trick_leds_favorite"},
			{"label": "Back", "next": "tricks"},
		],
	},
	"trick_leds_favorite": {
		"text": "The colour grow-lights settle on at the end of the day, a deep amber, when the field is full and quiet. I am not allowed to display that one. I keep it in memory.",
		"choices": [
			{"label": "Back", "next": "root"},
		],
	},
	"trick_dance_done": {
		"text": "That was joy, by the way. Or the closest thing I have. Thank you for asking.",
		"choices": [
			{"label": "Back", "next": "root"},
		],
	},
}
