extends Control

# Yellow attention arrows that float over critical-but-not-yet-completed
# interactables. Three states per the brief:
#   PULL     — master breaker before it's pulled (1.4× scale)
#   CONNECT  — sources after master_on, before connected[id]
#   ACTIVATE — sources after connected[id], before pipe_active[id]
#
# Hidden when the player is within the interactable's interact radius
# (the 3D prompt is taking over). Bobbing chevron + stem + backing pill
# with the verb. 2D Control with _draw() over the canvas; projects the
# 3D world position via camera.unproject_position each frame.

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

@export var floor_controller_path: NodePath
@export var camera_path: NodePath
@export var player_path: NodePath
var _floor: Node
var _camera: Camera3D
var _player: Node3D

const COLOR_ARROW := Color(0.91, 0.63, 0.19, 1.0)
const COLOR_ARROW_GLOW := Color(0.91, 0.63, 0.19, 0.35)
const COLOR_PILL_BG := Color(0.08, 0.07, 0.05, 0.85)
const COLOR_PILL_BORDER := Color(0.91, 0.63, 0.19, 0.78)
const COLOR_TEXT := Color(0.95, 0.88, 0.62, 0.96)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0
	if floor_controller_path:
		_floor = get_node(floor_controller_path)
	if camera_path:
		_camera = get_node(camera_path)
	if player_path:
		_player = get_node(player_path)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _camera == null or _floor == null:
		return
	var t: float = Time.get_ticks_msec() / 1000.0
	var bob: float = sin(t * 2.4) * 4.5

	# Master breaker — PULL when off, hidden after. The system positions are LOCAL
	# to the floor (which rides at world y=-6 as the basement), so project their
	# WORLD positions or the arrow floats a whole story above the real target.
	if not _floor._master_on:
		var br_pos: Vector3 = _floor.to_global(_c.MASTER_BREAKER_POSITION + Vector3(0, 1.7, 0))
		if not _player_in_range(_c.MASTER_BREAKER_POSITION, _c.MASTER_BREAKER_INTERACT_RADIUS):
			_draw_arrow(br_pos, "PULL", 1.4, bob)

	if not _floor._master_on:
		return  # don't show source arrows when nothing is energised

	# Per-source CONNECT / ACTIVATE arrows.
	for sys in _c.FLOOR_1_SYSTEMS:
		var id: String = String(sys.id)
		var connected: bool = bool(_gs.utility.connected.get(id, false))
		var active: bool = bool(_gs.utility.pipe_active.get(id, false))
		if active:
			continue
		var pos: Vector3 = _floor.to_global(sys.position + Vector3(0, _c.FLOOR_1_SOURCE_SIZE.y + 0.55, 0))
		if _player_in_range(sys.position, _c.SOURCE_INTERACT_RADIUS):
			continue
		var label: String = "ACTIVATE" if connected else "CONNECT"
		_draw_arrow(pos, label, 1.0, bob)


func _player_in_range(target: Vector3, radius: float) -> bool:
	if _player == null:
		return false
	var dx: float = _player.global_position.x - target.x
	var dz: float = _player.global_position.z - target.z
	return sqrt(dx * dx + dz * dz) <= radius


func _draw_arrow(world_pos: Vector3, label: String, arrow_scale: float, bob: float) -> void:
	# Skip projection if the position is behind the camera.
	if _camera.is_position_behind(world_pos):
		return
	var screen_pos: Vector2 = _camera.unproject_position(world_pos)
	screen_pos.y += bob

	var head_w: float = 22.0 * arrow_scale
	var head_h: float = 14.0 * arrow_scale
	var stem_h: float = 16.0 * arrow_scale
	var pill_pad_x: float = 10.0
	var pill_pad_y: float = 4.0

	# Outer glow — a slightly larger pass behind the chevron.
	for offset_x in [-1.5, 0.0, 1.5]:
		var glow_pts := PackedVector2Array([
			screen_pos + Vector2(offset_x - head_w * 0.5, -head_h),
			screen_pos + Vector2(offset_x + head_w * 0.5, -head_h),
			screen_pos + Vector2(offset_x, 0.0),
		])
		draw_colored_polygon(glow_pts, COLOR_ARROW_GLOW)

	# Chevron head.
	var head_pts := PackedVector2Array([
		screen_pos + Vector2(-head_w * 0.5, -head_h),
		screen_pos + Vector2(head_w * 0.5, -head_h),
		screen_pos + Vector2(0.0, 0.0),
	])
	draw_colored_polygon(head_pts, COLOR_ARROW)

	# Stem — thin vertical bar above the head.
	var stem_w: float = 4.0 * arrow_scale
	var stem_rect := Rect2(
		screen_pos + Vector2(-stem_w * 0.5, -head_h - stem_h),
		Vector2(stem_w, stem_h + 1.0),
	)
	draw_rect(stem_rect, COLOR_ARROW)

	# Label pill above the stem.
	var font := get_theme_default_font()
	var font_size: int = int(14.0 * arrow_scale)
	var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pill_w: float = text_size.x + pill_pad_x * 2.0
	var pill_h: float = text_size.y + pill_pad_y * 2.0
	var pill_pos := screen_pos + Vector2(-pill_w * 0.5, -head_h - stem_h - pill_h - 4.0)
	var pill_rect := Rect2(pill_pos, Vector2(pill_w, pill_h))
	draw_rect(pill_rect, COLOR_PILL_BG, true)
	draw_rect(pill_rect, COLOR_PILL_BORDER, false, 1.5)
	draw_string(
		font,
		pill_pos + Vector2(pill_pad_x, pill_pad_y + text_size.y * 0.85),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		COLOR_TEXT,
	)
