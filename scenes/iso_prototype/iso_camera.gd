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
var _pivot: Node3D
var _rotating := false
var _panning := false


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	rotation_degrees = Vector3(_c.CAMERA_TILT_DEG, 0, 0)
	# Pull camera back along its local -Z so the orthographic view frames the
	# scene without near-plane clipping. Distance is mostly cosmetic in ortho.
	position = Vector3(0, 0, 20)
	near = 0.1
	far = 200.0
	size = _c.CAMERA_ORTHO_SIZE_DEFAULT
	if pivot_path:
		_pivot = get_node(pivot_path)
		_pivot.rotation_degrees.y = _c.CAMERA_YAW_DEG_INITIAL
	_sync_to_state()


func _process(_delta: float) -> void:
	# Mirror our state into GameState every frame as the single source of truth.
	if _pivot:
		_gs.camera.target = _pivot.global_position
		_gs.camera.angle_step = _angle_step_from_pivot()
	_gs.camera.ortho_size = size


func _unhandled_input(event: InputEvent) -> void:
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
	var basis := _pivot.global_transform.basis
	var world_delta := basis.x * screen_dx + basis.z * screen_dy
	# Lock to XZ plane (we don't want middle-click drag to fly the camera up).
	world_delta.y = 0.0
	_pivot.global_position += world_delta


func _sync_to_state() -> void:
	_gs.camera.target = _pivot.global_position if _pivot else Vector3.ZERO
	_gs.camera.ortho_size = size
	_gs.camera.angle_step = 0
