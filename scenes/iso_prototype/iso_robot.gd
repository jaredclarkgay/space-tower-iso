extends Node3D

# Roomba MK1 — the player's first helper robot. State machine:
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

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

@export var iso_floor_path: NodePath
var _iso_floor: Node3D

enum State {
	OFFLINE,
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


func _ready() -> void:
	if iso_floor_path:
		_iso_floor = get_node(iso_floor_path)
	_build_visual()
	visible = false


func _physics_process(delta: float) -> void:
	_time += delta

	if _state == State.OFFLINE:
		if _gs.food_count >= _c.ROBOT_UNLOCK_THRESHOLD:
			_enter_awaiting_activation()
		return

	_update_led()

	match _state:
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
			return "Activate Roomba"
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
			return true
		State.FULL_AWAITING_PICKUP:
			_gs.food_count += _capacity
			_capacity = 0
			_state = State.MOVING_TO_TARGET
			return true
	return false


# --- State updates ---------------------------------------------------------

func _enter_awaiting_activation() -> void:
	_state = State.AWAITING_ACTIVATION
	# Spawn just outside the elevator on its +Z edge so the player can read
	# "the robot came up the elevator". Y sits the robot's wheels on the slab.
	var elev_size: float = float(_c.ELEVATOR_RADIUS) * 2.0 * _c.GARDEN_PLOT_SIZE
	global_position = Vector3(0, 0.05, elev_size * 0.5 + 0.7)
	rotation.y = 0.0
	visible = true


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
		_iso_floor.harvest_plot(_target_plot, false)
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

	# Flat orange disc body — Roomba silhouette.
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := CylinderMesh.new()
	bm.top_radius = 0.32
	bm.bottom_radius = 0.34
	bm.height = 0.18
	body.mesh = bm
	body.material_override = _make_material(Color(0.85, 0.55, 0.25))
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
	rim.material_override = _make_material(Color(0.18, 0.18, 0.20))
	rim.position.y = 0.04
	_body_root.add_child(rim)

	# Tapered dome on top — slightly back-tilted shoulder where the LED sits.
	var dome := MeshInstance3D.new()
	dome.name = "Dome"
	var dm := CylinderMesh.new()
	dm.top_radius = 0.18
	dm.bottom_radius = 0.26
	dm.height = 0.10
	dome.mesh = dm
	dome.material_override = _make_material(Color(0.30, 0.30, 0.32))
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
