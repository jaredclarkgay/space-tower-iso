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
var _time := 0.0   # for LED pulse

var _body_root: Node3D
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
		if _gs.food_count >= _c.ROBOT_UNLOCK_THRESHOLD:
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
	if _state != State.AWAITING_ACTIVATION and _state != State.FULL_AWAITING_PICKUP:
		return false
	return (global_position - world_pos).length() <= radius


func get_interaction_label() -> String:
	match _state:
		State.AWAITING_ACTIVATION:
			return "Activate Cody"
		State.FULL_AWAITING_PICKUP:
			return "Collect %d Crops" % _capacity
	return ""


# Returns true if the press fired an action (used for UX/sound hooks later).
func try_interact() -> bool:
	match _state:
		State.AWAITING_ACTIVATION:
			# Cursor reset so the activated robot starts at the top-left
			# corner of the snake, not wherever it left off pre-activation.
			_cursor = Vector2i(0, -1)
			_state = State.MOVING_TO_TARGET
			# End-of-introduction beat: dismiss the dialogue and fade the
			# spotlight away — Cody is "going to work" now.
			_dismiss_arrival_dialogue()
			_fade_out_spotlight()
			return true
		State.FULL_AWAITING_PICKUP:
			_gs.food_count += _capacity
			_capacity = 0
			_state = State.MOVING_TO_TARGET
			return true
	return false


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
	var park_pos := Vector3(0, 0.05, elev_size * 0.5 + 0.7)

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
		_iso_floor.harvest_plot(_target_plot, false)
		_spawn_robot_harvest_feedback(plant_name)
		_capacity += 1
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
	# garden than the previous hardhat-orange chassis.
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := CylinderMesh.new()
	bm.top_radius = 0.32
	bm.bottom_radius = 0.34
	bm.height = 0.18
	body.mesh = bm
	body.material_override = _make_material(Color(0.25, 0.68, 0.80))
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
	dome.material_override = _make_material(Color(0.46, 0.50, 0.56))
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
func _spawn_robot_harvest_feedback(plant_name: String) -> void:
	var label := Label3D.new()
	label.text = "+1 %s" % plant_name
	label.font_size = 36
	label.outline_size = 6
	label.modulate = Color(0.55, 1.0, 0.50, 1.0)
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

	# Programmatic portrait Control — drawn via cody_portrait.gd's _draw.
	var portrait := Control.new()
	portrait.set_script(_CODY_PORTRAIT)
	portrait.custom_minimum_size = Vector2(120, 120)
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
