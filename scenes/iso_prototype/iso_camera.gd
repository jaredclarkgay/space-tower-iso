extends Camera3D

# Iso camera for the slice. Designed to attach as a child of a "CameraPivot"
# Node3D placed at the camera's target point. The pivot is rotated for the
# 90° camera_rotate_left / camera_rotate_right snaps; the camera itself only
# manages tilt (-30° X, fixed) and zoom (the orthographic `size` property).
#
# Pan is implemented here rather than on the pivot so middle-click drag moves
# the target on the world XZ plane, basis-relative to the current camera yaw.
#
# Why this composition (one pivot rotates yaw, camera holds tilt + zoom):
#   - Rotating the pivot keeps the tilt fixed during 90° snaps.
#   - Camera-relative pan stays correct after rotation because we read the
#     pivot's basis on every drag delta.
#   - Future renderer-swap (Path B) would share GameState.camera but not this
#     scene; the GameState fields stay renderer-agnostic.

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

@export var pivot_path: NodePath
@export var iso_player_path: NodePath
@export var iso_robot_path: NodePath
var _pivot: Node3D
var _iso_player: Node3D
var _iso_robot: Node3D
var _rotating := false
var _panning := false

# Dialogue close-up state. Camera saves its current pivot+size when the
# player opens a Cody chat, tweens in to the player↔Cody midpoint, then
# tweens back out when the dialogue closes.
var _was_dialogue_open := false
var _saved_pivot_pos: Vector3
var _saved_size: float
var _focus_tween: Tween


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	rotation_degrees = Vector3(_c.CAMERA_TILT_DEG, 0, 0)
	# Position the camera so that, with the -30° X tilt applied, its look
	# direction passes through the pivot's origin. For a tilt of θ below
	# horizontal at distance d, the local offset is (0, d·sin|θ|, d·cos|θ|).
	# That math is what wires "rotate the camera and look at the pivot" into
	# a single transform — getting it wrong makes the framing drift off-target
	# (caught in F-003).
	var tilt_rad: float = deg_to_rad(abs(_c.CAMERA_TILT_DEG))
	var d: float = _c.CAMERA_DISTANCE
	position = Vector3(0.0, d * sin(tilt_rad), d * cos(tilt_rad))
	near = 0.1
	far = 200.0
	size = _c.CAMERA_ORTHO_SIZE_DEFAULT
	if pivot_path:
		_pivot = get_node(pivot_path)
		_pivot.rotation_degrees.y = _c.CAMERA_YAW_DEG_INITIAL
	if iso_player_path:
		_iso_player = get_node(iso_player_path)
	if iso_robot_path:
		_iso_robot = get_node(iso_robot_path)
	_sync_to_state()


func _process(_delta: float) -> void:
	# Detect dialogue open/close transitions and trigger the close-up
	# tween in or out.
	var dialogue_open: bool = bool(_gs.get("dialogue_open"))
	if dialogue_open != _was_dialogue_open:
		_was_dialogue_open = dialogue_open
		if dialogue_open:
			_enter_dialogue_focus()
		else:
			_exit_dialogue_focus()

	# Mirror our state into GameState every frame as the single source of truth.
	if _pivot:
		_gs.camera.target = _pivot.global_position
		_gs.camera.angle_step = _angle_step_from_pivot()
	_gs.camera.ortho_size = size


func _unhandled_input(event: InputEvent) -> void:
	# Disable camera input while dialogue is open — let the focus tween
	# do its thing without the player accidentally panning/rotating mid-chat.
	if bool(_gs.get("dialogue_open")):
		return
	if event.is_action_pressed(&"camera_rotate_left"):
		_rotate_pivot_by(-90.0)
	elif event.is_action_pressed(&"camera_rotate_right"):
		_rotate_pivot_by(90.0)
	elif event.is_action_pressed(&"camera_zoom_in"):
		_apply_zoom(_c.CAMERA_ZOOM_FACTOR)
	elif event.is_action_pressed(&"camera_zoom_out"):
		_apply_zoom(1.0 / _c.CAMERA_ZOOM_FACTOR)
	elif event.is_action_pressed(&"camera_pan"):
		_panning = true
	elif event.is_action_released(&"camera_pan"):
		_panning = false
	elif event is InputEventMouseMotion and _panning:
		_apply_pan(event.relative)


# --- Rotation (pivot yaw) ---------------------------------------------------

func _rotate_pivot_by(degrees: float) -> void:
	if _rotating or _pivot == null:
		return
	_rotating = true
	var target := _pivot.rotation_degrees.y + degrees
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_pivot, "rotation_degrees:y", target, _c.CAMERA_ROTATE_DURATION)
	tween.tween_callback(func(): _rotating = false)


func _angle_step_from_pivot() -> int:
	# Normalize yaw to the canonical 0..3 step index.
	var yaw_deg := fposmod(_pivot.rotation_degrees.y - _c.CAMERA_YAW_DEG_INITIAL, 360.0)
	return int(round(yaw_deg / 90.0)) % 4


# --- Zoom -------------------------------------------------------------------

func _apply_zoom(factor: float) -> void:
	size = clamp(size * factor, _c.CAMERA_ORTHO_SIZE_MIN, _c.CAMERA_ORTHO_SIZE_MAX)


# --- Pan (target on XZ plane, basis-relative to pivot yaw) ------------------

func _apply_pan(mouse_delta: Vector2) -> void:
	if _pivot == null:
		return
	# Convert pixel delta to world units. Empirically tuned so a comfortable
	# hand drag moves the camera a comparable distance on screen at default
	# zoom; scales with `size` so pan stays consistent at all zoom levels.
	var per_pixel := size * 0.0025
	var screen_dx := -mouse_delta.x * per_pixel
	var screen_dy := mouse_delta.y * per_pixel
	# Pivot basis: forward = -Z in pivot space, right = +X.
	# Don't name this `basis` — that shadows Node3D's own basis property.
	var pivot_basis := _pivot.global_transform.basis
	var world_delta := pivot_basis.x * screen_dx + pivot_basis.z * screen_dy
	# Lock to XZ plane (we don't want middle-click drag to fly the camera up).
	world_delta.y = 0.0
	_pivot.global_position += world_delta


func _sync_to_state() -> void:
	_gs.camera.target = _pivot.global_position if _pivot else Vector3.ZERO
	_gs.camera.ortho_size = size
	_gs.camera.angle_step = 0


# --- Dialogue close-up ---------------------------------------------------

func _enter_dialogue_focus() -> void:
	if _pivot == null:
		return
	# Save the pre-dialogue pose so we can restore it when chat closes.
	_saved_pivot_pos = _pivot.global_position
	_saved_size = size

	# Look at the midpoint between player and Cody at chest height. If
	# either is missing, fall back to the saved pivot position.
	var target: Vector3 = _saved_pivot_pos
	if _iso_player and _iso_robot and _iso_robot.visible:
		var p1: Vector3 = _iso_player.global_position
		var p2: Vector3 = _iso_robot.global_position
		target = (p1 + p2) * 0.5
		target.y = 1.0

	if _focus_tween:
		_focus_tween.kill()
	_focus_tween = create_tween().set_parallel(true)
	_focus_tween.set_trans(Tween.TRANS_QUAD)
	_focus_tween.set_ease(Tween.EASE_OUT)
	_focus_tween.tween_property(_pivot, "global_position", target, _c.CAMERA_DIALOGUE_FOCUS_DURATION)
	_focus_tween.tween_property(self, "size", _c.CAMERA_DIALOGUE_FOCUS_SIZE, _c.CAMERA_DIALOGUE_FOCUS_DURATION)


func _exit_dialogue_focus() -> void:
	if _pivot == null:
		return
	if _focus_tween:
		_focus_tween.kill()
	_focus_tween = create_tween().set_parallel(true)
	_focus_tween.set_trans(Tween.TRANS_QUAD)
	_focus_tween.set_ease(Tween.EASE_OUT)
	_focus_tween.tween_property(_pivot, "global_position", _saved_pivot_pos, _c.CAMERA_DIALOGUE_FOCUS_DURATION)
	_focus_tween.tween_property(self, "size", _saved_size, _c.CAMERA_DIALOGUE_FOCUS_DURATION)
