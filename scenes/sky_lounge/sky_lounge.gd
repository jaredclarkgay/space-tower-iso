extends Node3D

# Floor 5 — SKY LOUNGE (sky-bar observation lounge). Blank for now, but it has
# its signature feature: floor-to-ceiling glass ringing the floor with the sky
# beyond, and a "look out the window" camera move. Walk up to the glass and an
# [E] LOOK OUT prompt appears; press it and the camera detaches to an exterior
# vantage you drive (Q/R orbit, arrows pan, wheel zoom, Esc/E back inside). The
# placeholder cityscape (scenes/shared/cityscape.gd) is what you look out at.
#
# Built with the shared chrome (slab + shaft + elevator/spine core + lit risers
# + corner vacuum tubes); only the perimeter walls differ — full-height glass
# instead of the standard low-base + glass.
#
# Built in LOCAL space (slab top at local y=0); the tower offsets the node up.

const FloorChrome = preload("res://scenes/shared/floor_chrome.gd")
const VacuumTube = preload("res://scenes/shared/vacuum_tube.gd")
const FloorConstruction = preload("res://scenes/shared/floor_construction.gd")

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

@export var player_path: NodePath

const FLOOR_COLOR := Color(0.40, 0.42, 0.47)   # pale, airy lounge floor

var _player: Node3D
var _elevator_data: Dictionary = {}

# Per-component structural assembly (shared chrome, but bespoke full-height glass
# walls supplied as the "walls" step's builder).
var _construction: FloorConstruction = null

# Look-out prompt (billboarded, scales with zoom). Child of this floor node, so
# the tower's floor-visibility gating hides it when the player isn't up here.
var _prompt_root: Node3D
var _prompt_key: Label3D
var _prompt_label: Label3D
var _offered: bool = false        # a window is in reach this frame
var _reenter_cd: float = 0.0      # brief lockout after exiting, so E can't re-arm instantly
# "drag to look" hint slides off + fades once the player actually starts looking.
var _entry_yaw: float = 0.0
var _look_engaged: bool = false
var _hint_anim: float = 0.0       # 0 = hint shown, 1 = fully slid off + faded


func _ready() -> void:
	_player = get_node_or_null(player_path)
	var shaft_half: float = float(_c.ELEVATOR_RADIUS) * float(_c.GARDEN_PLOT_SIZE)
	# Structural chrome via the per-component assembly module; the "walls" step uses
	# the Sky Lounge's signature full-height glass instead of the standard walls.
	_construction = FloorConstruction.new(self, _c, _gs, get_node_or_null("/root/Telemetry"), {
		"floor_color": FLOOR_COLOR,
		"shaft_half": shaft_half,
		"walls_build": func(g: Node3D) -> void: _build_glass_walls(g),
	})
	_construction.build_all_instant()
	_elevator_data = _construction.elevator_data()
	_build_prompt()


func _process(delta: float) -> void:
	if _player == null:
		return
	if _reenter_cd > 0.0:
		_reenter_cd -= delta
	var looking: bool = bool(_gs.get("looking_out"))
	# Only relevant while the player is actually up here on the Sky Lounge.
	var on_floor: bool = absf(_player.global_position.y - global_position.y) < 3.0
	if not on_floor:
		_set_prompt(false)
		return

	if looking:
		# Once the player actually starts looking around, retire the "drag to look"
		# hint — slide it off + fade (handled in _position_prompt via _hint_anim).
		var dyaw: float = absf(wrapf(float(_gs.get("look_view_yaw")) - _entry_yaw, -PI, PI))
		var dpitch: float = absf(float(_gs.get("look_view_pitch")) + 0.12)
		if dyaw > 0.05 or dpitch > 0.05:
			_look_engaged = true
		if _look_engaged:
			_hint_anim = minf(1.0, _hint_anim + delta * 3.0)
		# The prompt becomes "back inside"; E or Esc exits.
		_show_back_prompt()
		if Input.is_action_just_pressed(&"interact") or Input.is_action_just_pressed(&"ui_cancel"):
			_gs.set("looking_out", false)
			_reenter_cd = float(_c.LOOKOUT_REENTER_COOLDOWN)
		return

	# Brief lockout right after exiting so the same tap can't re-arm the look-out.
	if _reenter_cd > 0.0:
		_set_prompt(false)
		return

	# Find the nearest perimeter wall and whether the player is within reach.
	var n: Vector3 = _nearest_wall_normal()
	_offered = n != Vector3.ZERO
	_set_prompt(_offered)
	if not _offered:
		return
	if Input.is_action_just_pressed(&"interact"):
		_enter_look_out(n)


# Outward normal (world) of the nearest wall the player is within reach of, or
# Vector3.ZERO if none. Walls sit at x = ±half and z = ±half (no floor rotation,
# so local axes == world axes).
func _nearest_wall_normal() -> Vector3:
	var half: float = float(_c.FLOOR_3D_SIZE) * 0.5
	var lp: Vector3 = to_local(_player.global_position)
	var r: float = float(_c.LOOKOUT_WINDOW_RADIUS)
	var best := Vector3.ZERO
	var best_gap: float = r
	for n in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var coord: float = lp.x * n.x + lp.z * n.z   # player's position along the outward axis
		var gap: float = half - coord                # distance from player to that wall
		if gap >= -0.5 and gap < best_gap:
			best_gap = gap
			best = n
	return best


func _enter_look_out(n: Vector3) -> void:
	# Face outward through the window the player walked up to: forward = the wall's
	# outward normal, so the body turns to look out and the camera sits behind it.
	var yaw: float = atan2(n.x, n.z)
	_entry_yaw = yaw
	_look_engaged = false
	_hint_anim = 0.0
	_gs.set("look_out_yaw", yaw)
	_gs.set("look_view_yaw", yaw)
	_gs.set("look_view_pitch", -0.12)
	_gs.set("looking_out", true)


# --- Full-height glass walls ------------------------------------------------

func _build_glass_walls(parent: Node3D = self) -> void:
	var half: float = float(_c.FLOOR_3D_SIZE) * 0.5
	for n in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		_build_one_glass_wall(parent, n, half)


func _build_one_glass_wall(parent: Node3D, n: Vector3, half: float) -> void:
	var height: float = float(_c.WALL_HEIGHT)
	var length: float = float(_c.FLOOR_3D_SIZE)
	var along_x: bool = absf(n.z) > 0.5        # wall runs along x when facing ±z
	var body := StaticBody3D.new()
	body.name = "GlassWall"
	parent.add_child(body)
	var perp: float = (n.x + n.z) * half        # signed offset to the wall plane

	# Full-height collision (thin) so you can't walk through the glass.
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = Vector3(length, height, 0.1) if along_x else Vector3(0.1, height, length)
	col.shape = cs
	col.position = Vector3(0 if along_x else perp, height * 0.5, perp if along_x else 0)
	body.add_child(col)

	# Floor-to-ceiling glass pane.
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	var gm := BoxMesh.new()
	gm.size = Vector3(length - 0.2, height - 0.1, 0.06) if along_x else Vector3(0.06, height - 0.1, length - 0.2)
	glass.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.74, 0.86, 0.98, 0.16)   # clearer than the standard panes
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.roughness = 0.03
	gmat.metallic = 0.5
	glass.material_override = gmat
	glass.position = Vector3(0 if along_x else perp, height * 0.5, perp if along_x else 0)
	body.add_child(glass)

	# Thin frame: top + bottom rails + mullions every ~3 m.
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.30, 0.32, 0.37)
	frame_mat.metallic = 0.6
	frame_mat.roughness = 0.4
	for ry in [0.06, height - 0.06]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(length, 0.12, 0.12) if along_x else Vector3(0.12, 0.12, length)
		rail.mesh = rm
		rail.material_override = frame_mat
		rail.position = Vector3(0 if along_x else perp, ry, perp if along_x else 0)
		body.add_child(rail)
	var mullions: int = int(length / 3.0)
	for k in range(mullions + 1):
		var t: float = -length * 0.5 + float(k) * (length / float(mullions))
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.1, height, 0.1)
		post.mesh = pm
		post.material_override = frame_mat
		post.position = Vector3(t if along_x else perp, height * 0.5, perp if along_x else t)
		body.add_child(post)


# --- Prompt -----------------------------------------------------------------

func _build_prompt() -> void:
	_prompt_root = Node3D.new()
	_prompt_root.name = "LookOutPrompt"
	_prompt_root.visible = false
	add_child(_prompt_root)

	_prompt_key = Label3D.new()
	_prompt_key.text = "E"
	_prompt_key.font_size = 84
	_prompt_key.outline_size = 12
	_prompt_key.modulate = Color(0.72, 0.92, 1.0, 1.0)
	_prompt_key.outline_modulate = Color(0, 0, 0, 0.92)
	_prompt_key.pixel_size = 0.0075
	_prompt_key.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_key.no_depth_test = true
	_prompt_key.position = Vector3(0, 0.45, 0)
	_prompt_root.add_child(_prompt_key)

	_prompt_label = Label3D.new()
	_prompt_label.text = "Look out the window"
	_prompt_label.font_size = 48
	_prompt_label.outline_size = 8
	_prompt_label.modulate = Color(0.95, 0.98, 1.0, 1.0)
	_prompt_label.outline_modulate = Color(0, 0, 0, 0.92)
	_prompt_label.pixel_size = 0.0075
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.position = Vector3(0, -0.28, 0)
	_prompt_root.add_child(_prompt_label)


func _set_prompt(show_it: bool) -> void:
	if _prompt_root == null:
		return
	_prompt_root.visible = show_it
	if not show_it or _player == null:
		return
	_prompt_key.text = "E"
	_prompt_label.text = "Look out the window"
	_position_prompt()


func _show_back_prompt() -> void:
	if _prompt_root == null:
		return
	_prompt_root.visible = true
	_prompt_key.text = "drag to look"
	_prompt_label.text = "E / Esc — back inside"
	_position_prompt()


func _position_prompt() -> void:
	var p: Vector3 = _player.global_position
	# While looking out the camera is a perspective POV right behind the head, so
	# the ortho-size scaling doesn't apply — use a fixed modest scale + a little
	# lift so the "back inside" hint reads without ballooning in frame.
	if bool(_gs.get("looking_out")):
		_prompt_root.global_position = Vector3(p.x, p.y + 2.3, p.z)
		_prompt_root.scale = Vector3.ONE * 0.5
		# The "drag to look" key line gently slides off (+x in the billboard plane)
		# and fades once the player starts looking; the "back inside" line stays.
		var e: float = smoothstep(0.0, 1.0, _hint_anim)
		_prompt_key.position = Vector3(2.6 * e, 0.45, 0.0)
		_prompt_key.modulate.a = 1.0 - e
		return
	# Reset the key line (a prior look-out may have faded/slid it).
	_prompt_key.position = Vector3(0, 0.45, 0)
	_prompt_key.modulate.a = 1.0
	# Otherwise float above the player; scale by ortho size so it stays a constant
	# on-screen height (matches the elevator / vacuum prompts).
	_prompt_root.global_position = Vector3(p.x, p.y + 2.7, p.z)
	var ortho: float = float(_gs.camera.get("ortho_size", _c.CAMERA_ORTHO_SIZE_DEFAULT)) if _gs else float(_c.CAMERA_ORTHO_SIZE_DEFAULT)
	var k: float = clampf(ortho / float(_c.CAMERA_ORTHO_SIZE_DEFAULT), 0.18, 1.0)
	_prompt_root.scale = Vector3.ONE * k
