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
var _saved_pivot_yaw: float
var _saved_size: float
var _focus_tween: Tween
# True after the entry tween finishes — gates the orbit-rotation in _process.
var _focus_settled := false

# Camera-mode state. Mode is the operator's pick from the HUD ("iso" /
# "profile" / "ots"); when it changes we save the iso state, tween the
# camera's local pose to the new preset, and start tracking the player.
var _mode: String = "iso"
var _mode_tween: Tween
# Iso-mode pose preserved while the operator is in profile / OTS so we can
# restore their pan + rotation + zoom on return.
var _iso_saved_pivot_pos: Vector3
var _iso_saved_pivot_yaw: float
var _iso_saved_size: float
var _iso_state_saved: bool = false

# --- Free-look orbit -----------------------------------------------------
# Middle-drag orbits the camera around the pivot in 360° (any mode); the offset
# eases back to the mode's standard orientation once the player moves again.
const ORBIT_YAW_SENS := 0.006
const ORBIT_PITCH_SENS := 0.006
const ORBIT_PITCH_MAX := 1.0          # rad (~57°) up/down from the base tilt
const ORBIT_RETURN_RATE := 6.0
var _orbiting := false
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
# The active mode's base tilt + distance, so orbit composes on top of them.
var _base_tilt_deg := 0.0
var _base_distance := 0.0


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
	_base_tilt_deg = _c.CAMERA_TILT_DEG
	_base_distance = d
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


func _process(delta: float) -> void:
	# Detect dialogue open/close transitions and trigger the close-up
	# tween in or out.
	var dialogue_open: bool = bool(_gs.get("dialogue_open"))
	if dialogue_open != _was_dialogue_open:
		_was_dialogue_open = dialogue_open
		if dialogue_open:
			_enter_dialogue_focus()
		else:
			_exit_dialogue_focus()

	# Slow steady orbit while the chat is up and the entry tween has
	# settled. Pauses while the player is actively drag-rotating; on
	# release the orbit picks back up from the new heading.
	if dialogue_open and _focus_settled and _pivot and not _panning:
		_pivot.rotation.y += _c.CAMERA_DIALOGUE_ORBIT_RATE * delta

	# Camera-mode state machine. Dialogue takes priority — the close-up
	# tween owns the camera while a chat is open, regardless of mode.
	if not dialogue_open:
		var requested_mode: String = String(_gs.get("camera_mode"))
		if requested_mode != _mode:
			_apply_mode_change(requested_mode)
		_update_follow_mode(delta)

	# Mirror our state into GameState every frame as the single source of truth.
	if _pivot:
		_gs.camera.target = _pivot.global_position
		_gs.camera.angle_step = _angle_step_from_pivot()
	_gs.camera.ortho_size = size

	# Free-look orbit: ease back to the mode's standard orientation as the player
	# moves, then apply the offset. Skipped during dialogue (the focus tween owns
	# the camera there).
	if not dialogue_open:
		if not _orbiting and (absf(_orbit_yaw) > 0.0001 or absf(_orbit_pitch) > 0.0001):
			var mv := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
			if mv.length() > 0.1:
				var k: float = clampf(ORBIT_RETURN_RATE * delta, 0.0, 1.0)
				_orbit_yaw = lerpf(_orbit_yaw, 0.0, k)
				_orbit_pitch = lerpf(_orbit_pitch, 0.0, k)
		_apply_orbit()


# Orbits the camera around the pivot by the free-look offsets, always looking
# back at the pivot origin. At zero offset this reproduces the mode's base pose
# (tilt + distance), so it composes cleanly on top of every mode. Skipped while
# a mode transition tween is animating the camera.
func _apply_orbit() -> void:
	if _mode_tween and _mode_tween.is_running():
		return
	var d: float = _base_distance
	var tilt: float = deg_to_rad(_base_tilt_deg)
	var base_pos := Vector3(0.0, -d * sin(tilt), d * cos(tilt))
	var yawed := base_pos.rotated(Vector3.UP, _orbit_yaw)
	var right := Vector3.UP.cross(yawed)
	right = right.normalized() if right.length() > 0.001 else Vector3.RIGHT
	var pos := yawed.rotated(right, _orbit_pitch)
	# Look-at-origin basis: camera +Z points away from the pivot (it looks -Z).
	var z := pos.normalized()
	var x := Vector3.UP.cross(z)
	x = x.normalized() if x.length() > 0.001 else Vector3.RIGHT
	var y := z.cross(x).normalized()
	transform = Transform3D(Basis(x, y, z), pos)


func _unhandled_input(event: InputEvent) -> void:
	# During dialogue, only the pan action is active — and it's repurposed
	# to drag-rotate the camera around the focused midpoint instead of
	# panning the world. While the player is actively dragging, the
	# auto-orbit pauses (see _process); on release the orbit resumes.
	if bool(_gs.get("dialogue_open")):
		if event.is_action_pressed(&"camera_pan"):
			_panning = true
		elif event.is_action_released(&"camera_pan"):
			_panning = false
		elif event is InputEventMouseMotion and _panning:
			_apply_dialogue_drag_rotate(event.relative)
		return
	# Zoom is allowed in every mode (helps the operator tune the framing).
	# Pan + 90° rotation only make sense in iso; the follow modes own the
	# pivot pose and would otherwise fight the input.
	if event.is_action_pressed(&"camera_zoom_in"):
		_apply_zoom(_c.CAMERA_ZOOM_FACTOR)
		return
	elif event.is_action_pressed(&"camera_zoom_out"):
		_apply_zoom(1.0 / _c.CAMERA_ZOOM_FACTOR)
		return
	# Free-look orbit — middle-drag in ANY mode to swing the camera around in
	# 360°; it eases back to the mode's standard orientation once the player
	# starts moving again (see _process).
	if event.is_action_pressed(&"camera_pan"):
		_orbiting = true
		return
	elif event.is_action_released(&"camera_pan"):
		_orbiting = false
		return
	elif event is InputEventMouseMotion and _orbiting:
		_orbit_yaw += -event.relative.x * ORBIT_YAW_SENS
		_orbit_pitch = clampf(_orbit_pitch + event.relative.y * ORBIT_PITCH_SENS, -ORBIT_PITCH_MAX, ORBIT_PITCH_MAX)
		return
	# 90° snap rotation is iso-only.
	if _mode != _c.CAMERA_MODE_ISO:
		return
	if event.is_action_pressed(&"camera_rotate_left"):
		_rotate_pivot_by(-90.0)
	elif event.is_action_pressed(&"camera_rotate_right"):
		_rotate_pivot_by(90.0)


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
	_saved_pivot_yaw = _pivot.rotation.y
	_saved_size = size
	_focus_settled = false

	# Look at the midpoint between player and Cody at chest height. If
	# either is missing, fall back to the saved pivot position.
	var target: Vector3 = _saved_pivot_pos
	var target_yaw: float = _saved_pivot_yaw
	if _iso_player and _iso_robot and _iso_robot.visible:
		var p1: Vector3 = _iso_player.global_position
		var p2: Vector3 = _iso_robot.global_position
		target = (p1 + p2) * 0.5
		target.y = 1.0
		# Aim the camera so its right axis aligns with the player→Cody
		# vector — both characters land side-by-side in frame, neither
		# occluded by the other or by the elevator. Camera-right (after a
		# Y rotation θ) is (cos θ, 0, -sin θ); solving for the segment
		# direction (dx, 0, dz) gives θ = atan2(-dz, dx).
		var seg: Vector3 = p2 - p1
		if Vector2(seg.x, seg.z).length_squared() > 0.0001:
			target_yaw = atan2(-seg.z, seg.x)
			# Take the short path from current yaw to target_yaw.
			var diff: float = wrapf(target_yaw - _saved_pivot_yaw + PI, 0.0, TAU) - PI
			target_yaw = _saved_pivot_yaw + diff

	if _focus_tween:
		_focus_tween.kill()
	_focus_tween = create_tween().set_parallel(true)
	_focus_tween.set_trans(Tween.TRANS_QUAD)
	_focus_tween.set_ease(Tween.EASE_OUT)
	_focus_tween.tween_property(_pivot, "global_position", target, _c.CAMERA_DIALOGUE_FOCUS_DURATION)
	_focus_tween.tween_property(_pivot, "rotation:y", target_yaw, _c.CAMERA_DIALOGUE_FOCUS_DURATION)
	_focus_tween.tween_property(self, "size", _c.CAMERA_DIALOGUE_FOCUS_SIZE, _c.CAMERA_DIALOGUE_FOCUS_DURATION)
	_focus_tween.finished.connect(_on_focus_settled, CONNECT_ONE_SHOT)


func _on_focus_settled() -> void:
	_focus_settled = true


# Drag-rotate during chat: horizontal mouse motion rotates the camera
# pivot's yaw. Vertical motion ignored — the tilt stays at -30° so the
# iso framing isn't broken mid-conversation.
func _apply_dialogue_drag_rotate(mouse_delta: Vector2) -> void:
	if _pivot == null:
		return
	_pivot.rotation.y += -mouse_delta.x * 0.01


# --- Camera modes -----------------------------------------------------------

# Mode change pipeline. Saves iso state on the way out, computes the new
# preset (tilt, distance, size, pivot pose), and tweens the camera's local
# transform + the orthographic size + the pivot to the new pose.
func _apply_mode_change(new_mode: String) -> void:
	if _pivot == null:
		return
	# If we're leaving iso, snapshot the operator's pan/rotation/zoom so we
	# can restore them on return.
	if _mode == _c.CAMERA_MODE_ISO and new_mode != _c.CAMERA_MODE_ISO:
		_iso_saved_pivot_pos = _pivot.global_position
		_iso_saved_pivot_yaw = _pivot.rotation.y
		_iso_saved_size = size
		_iso_state_saved = true

	# Cancel any in-flight mode tween before starting a new one.
	if _mode_tween and _mode_tween.is_running():
		_mode_tween.kill()

	# Per-mode preset: tilt, distance from pivot, ortho size, pivot pose.
	var tilt_deg: float
	var distance: float
	var target_size: float
	var target_pivot_pos: Vector3
	var target_pivot_yaw: float
	match new_mode:
		_c.CAMERA_MODE_PROFILE:
			tilt_deg = _c.CAMERA_PROFILE_TILT_DEG
			distance = _c.CAMERA_PROFILE_DISTANCE
			target_size = _c.CAMERA_PROFILE_SIZE
			target_pivot_pos = _player_anchor(_c.CAMERA_PROFILE_HEIGHT_OFFSET)
			# Lock yaw at mode-entry to perpendicular-of-current-facing so
			# the player walks through the frame instead of rotating it.
			target_pivot_yaw = _player_yaw_or(_pivot.rotation.y) - PI * 0.5
		_c.CAMERA_MODE_OTS:
			tilt_deg = _c.CAMERA_OTS_TILT_DEG
			distance = _c.CAMERA_OTS_DISTANCE
			target_size = _c.CAMERA_OTS_SIZE
			target_pivot_pos = _player_anchor(_c.CAMERA_OTS_HEIGHT_OFFSET)
			# Behind the player — pivot.yaw + π places the camera offset on
			# the opposite side of the pivot from where the player is looking.
			target_pivot_yaw = _player_yaw_or(_pivot.rotation.y) + PI
		_:
			# Default → restore saved iso pose if we have one, otherwise
			# fall back to the constants-default starting pose.
			tilt_deg = _c.CAMERA_TILT_DEG
			distance = _c.CAMERA_DISTANCE
			if _iso_state_saved:
				target_size = _iso_saved_size
				target_pivot_pos = _iso_saved_pivot_pos
				target_pivot_yaw = _iso_saved_pivot_yaw
			else:
				target_size = _c.CAMERA_ORTHO_SIZE_DEFAULT
				target_pivot_pos = Vector3.ZERO
				target_pivot_yaw = deg_to_rad(_c.CAMERA_YAW_DEG_INITIAL)

	# Remember the mode's base pose so free-look orbit composes on top of it.
	_base_tilt_deg = tilt_deg
	_base_distance = distance

	# Camera local position derived from tilt + distance (same math as
	# _ready, kept consistent so the pivot origin stays the look-at).
	var tilt_rad: float = deg_to_rad(abs(tilt_deg))
	var target_pos := Vector3(0.0, distance * sin(tilt_rad), distance * cos(tilt_rad))
	var target_rot_deg := Vector3(tilt_deg, 0.0, 0.0)

	# Take the short angular path so the rotation tween doesn't unwind a
	# full turn when leaving a long-running follow mode.
	var current_yaw: float = _pivot.rotation.y
	var yaw_diff: float = wrapf(target_pivot_yaw - current_yaw + PI, 0.0, TAU) - PI
	var resolved_pivot_yaw: float = current_yaw + yaw_diff

	_mode_tween = create_tween().set_parallel(true)
	_mode_tween.set_trans(Tween.TRANS_QUAD)
	_mode_tween.set_ease(Tween.EASE_OUT)
	_mode_tween.tween_property(self, ^"position", target_pos, _c.CAMERA_MODE_TWEEN_DURATION)
	_mode_tween.tween_property(self, ^"rotation_degrees", target_rot_deg, _c.CAMERA_MODE_TWEEN_DURATION)
	_mode_tween.tween_property(self, ^"size", target_size, _c.CAMERA_MODE_TWEEN_DURATION)
	_mode_tween.tween_property(_pivot, ^"global_position", target_pivot_pos, _c.CAMERA_MODE_TWEEN_DURATION)
	_mode_tween.tween_property(_pivot, ^"rotation:y", resolved_pivot_yaw, _c.CAMERA_MODE_TWEEN_DURATION)

	_mode = new_mode
	# Returning to iso clears the saved state so the next entry into a
	# follow mode captures fresh pan/rotation/zoom.
	if new_mode == _c.CAMERA_MODE_ISO:
		_iso_state_saved = false


# Per-frame update for the follow modes. Iso doesn't need this (operator
# controls pan + yaw directly).
func _update_follow_mode(delta: float) -> void:
	if _pivot == null or _iso_player == null:
		return
	if _mode == _c.CAMERA_MODE_ISO:
		return
	# A tween into the new pose is still running — let it finish before
	# we start chasing the player, otherwise the two fight each other.
	if _mode_tween and _mode_tween.is_running():
		return
	if _mode == _c.CAMERA_MODE_PROFILE:
		_pivot.global_position = _player_anchor(_c.CAMERA_PROFILE_HEIGHT_OFFSET)
		# Yaw stays fixed for profile — set at mode-entry, doesn't track turns.
	elif _mode == _c.CAMERA_MODE_OTS:
		_pivot.global_position = _player_anchor(_c.CAMERA_OTS_HEIGHT_OFFSET)
		# Freeze the yaw chase when the player is in a held pose (mid-plant,
		# mid-harvest, charging a jump). The camera keeps tracking position
		# but stops rotating, so the moment doesn't get spun around.
		if _iso_player and _iso_player.has_method("is_holding_pose") \
				and _iso_player.is_holding_pose():
			return
		var target_yaw: float = _player_yaw_or(_pivot.rotation.y) + PI
		var diff: float = wrapf(target_yaw - _pivot.rotation.y + PI, 0.0, TAU) - PI
		var step: float = clamp(_c.CAMERA_OTS_YAW_LERP_RATE * delta, 0.0, abs(diff))
		_pivot.rotation.y += sign(diff) * step


func _player_anchor(height_offset: float) -> Vector3:
	if _iso_player == null:
		return Vector3.ZERO
	var p: Vector3 = _iso_player.global_position
	return Vector3(p.x, p.y + height_offset, p.z)


func _player_yaw_or(fallback: float) -> float:
	# Pull the player's smoothed body yaw if available, falling back to the
	# given value if the player hasn't been resolved yet.
	if _iso_player and _iso_player.has_method("get_facing_yaw"):
		return _iso_player.get_facing_yaw()
	return fallback


func _exit_dialogue_focus() -> void:
	if _pivot == null:
		return
	_focus_settled = false
	if _focus_tween:
		_focus_tween.kill()
	# Normalize the current yaw to ±π around the saved value so the tween
	# back is the short way around — orbit might have advanced past one or
	# more full turns during a long chat.
	var current_yaw: float = _pivot.rotation.y
	var yaw_diff: float = wrapf(current_yaw - _saved_pivot_yaw + PI, 0.0, TAU) - PI
	_pivot.rotation.y = _saved_pivot_yaw + yaw_diff

	_focus_tween = create_tween().set_parallel(true)
	_focus_tween.set_trans(Tween.TRANS_QUAD)
	_focus_tween.set_ease(Tween.EASE_OUT)
	_focus_tween.tween_property(_pivot, "global_position", _saved_pivot_pos, _c.CAMERA_DIALOGUE_FOCUS_DURATION)
	_focus_tween.tween_property(_pivot, "rotation:y", _saved_pivot_yaw, _c.CAMERA_DIALOGUE_FOCUS_DURATION)
	_focus_tween.tween_property(self, "size", _saved_size, _c.CAMERA_DIALOGUE_FOCUS_DURATION)
