extends Node3D

# Vacuum-lift traversal + item transit for the stacked tower. The corner tube
# GEOMETRY is rendered per-floor (shared/vacuum_tube.gd); this top-level node
# adds the behaviour that spans floors, mirroring how elevator_platform.gd sits
# above the floors and owns the rider during a ride:
#
#   1. THE HOP — when the player stands grounded in a corner tube mouth, their
#      jump becomes a vacuum hop: a quick suction snap UP one floor (or DOWN,
#      if they hold the down key). A third vertical-traversal method alongside
#      the elevator (multi-floor ride) and the 3<->4 stairs, scoped to ±1 floor.
#      While hopping, this node OWNS the player's transform (GameState.tube_hopping
#      → iso_player skips its own physics) and the tower keeps tracking the
#      current floor so the destination slab is solid on arrival (the same class
#      of fix as the elevator ride — commit 79021ff / F-022).
#
#   2. ITEM TRANSIT — small produce capsules visibly rise through a corner tube
#      on the player's current floor: the cross-floor conduit made literal.
#      Purely cosmetic.

const VacuumTube = preload("res://scenes/shared/vacuum_tube.gd")

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

@export var player_path: NodePath

const PROMPT_ANCHOR_Y := 2.7      # prompt-stack height above the player's feet

enum State { IDLE, HOPPING }

var _player: Node3D
var _anchors: Array = []          # 4 corner anchors (world XZ, y=0), from VacuumTube

var _state: int = State.IDLE
var _hop_t := 0.0                 # 0..1 progress of the current hop
var _hop_from_y := 0.0
var _hop_to_y := 0.0
var _hop_xz := Vector2.ZERO       # tube centre the hop rides up/down
var _hop_glow_mat: StandardMaterial3D = null

# Prompt stack (JUMP cap + direction sublabel), same grammar as the elevator's.
var _prompt_root: Node3D
var _prompt_key: Label3D
var _prompt_label: Label3D

# Item-transit capsules currently in flight: [{node, top_y}].
var _capsules: Array = []
var _transit_timer := 0.0


func _story() -> float:
	return float(_c.FLOOR_3D_STORY_HEIGHT)

# Player-feet (slab-top) world Y for a floor level — matches the tower's spawn math.
func _surface_y(level: int) -> float:
	return float(level - 1) * _story() + float(_c.FLOOR_3D_TOP_Y)


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_anchors = VacuumTube.corner_anchors(_c)
	_build_prompt()
	_transit_timer = _next_transit_gap()


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	# The prompt floats a fixed height above the player whenever it's shown.
	if _prompt_root and _prompt_root.visible:
		_prompt_root.position = Vector3(_player.global_position.x, _player.global_position.y + PROMPT_ANCHOR_Y, _player.global_position.z)
	match _state:
		State.IDLE:
			_update_idle(delta)
		State.HOPPING:
			_update_hopping(delta)
	_update_transit(delta)


func _process(_delta: float) -> void:
	_update_prompt_scale()


# --- IDLE: detect the mouth, show the prompt, start a hop on jump ----------

func _update_idle(_delta: float) -> void:
	# Other vertical-travel / modal states own the player — no hop offered.
	var busy: bool = (
		bool(_gs.get("riding_elevator"))
		or bool(_gs.get("dialogue_open"))
		or bool(_gs.get("schematic_open"))
	)
	var grounded: bool = _player.has_method("is_on_floor") and _player.is_on_floor()
	var idx: int = _nearest_mouth_index() if (grounded and not busy) else -1
	var level: int = _player_level()
	var up_ok: bool = idx >= 0 and level < int(_c.VACUUM_HOP_TOP_LEVEL)
	var down_ok: bool = idx >= 0 and level > int(_c.VACUUM_HOP_BOTTOM_LEVEL)
	var offered: bool = up_ok or down_ok

	# iso_player reads this to swap its normal jump/charge for the hop AND to stop
	# the down key from walking the player off the mouth.
	_gs.set("in_tube_mouth", offered)
	_show_prompt(offered, up_ok, down_ok)

	if not offered:
		return
	# Jump = hop up (the headline "jump through the tube" verb). The down key =
	# hop down — its own trigger, not a jump+down combo, so the player never has
	# to fight their own footing. On the top floor, where up isn't available,
	# jump falls back to down so the verb still does something.
	if Input.is_action_just_pressed(&"jump"):
		_begin_hop(idx, level + (1 if up_ok else -1))
	elif down_ok and Input.is_action_just_pressed(&"move_down"):
		_begin_hop(idx, level - 1)


func _begin_hop(mouth_idx: int, dest_level: int) -> void:
	var anchor: Vector3 = _anchors[mouth_idx]
	_hop_xz = Vector2(anchor.x, anchor.z)
	_hop_from_y = _player.global_position.y
	_hop_to_y = _surface_y(dest_level)
	_hop_t = 0.0
	_hop_glow_mat = _glow_mat_for_corner_on_floor(mouth_idx, _player_level())
	_pulse_glow(_hop_glow_mat)
	_state = State.HOPPING
	_gs.set("tube_hopping", true)
	_gs.set("in_tube_mouth", false)
	_show_prompt(false, false, false)


func _update_hopping(delta: float) -> void:
	_hop_t = minf(_hop_t + delta / float(_c.VACUUM_HOP_DURATION), 1.0)
	# Ease-in-out for a suction-snap feel: quick middle, soft ends.
	var e: float = _hop_t * _hop_t * (3.0 - 2.0 * _hop_t)
	var y: float = lerpf(_hop_from_y, _hop_to_y, e)
	_player.global_position = Vector3(_hop_xz.x, y, _hop_xz.y)
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO
	if _hop_t >= 1.0:
		# Settle a hair above the slab so the player's snap re-grounds them.
		_player.global_position = Vector3(_hop_xz.x, _hop_to_y + 0.02, _hop_xz.y)
		if _player is CharacterBody3D:
			(_player as CharacterBody3D).velocity = Vector3.ZERO
		_gs.set("tube_hopping", false)
		_state = State.IDLE


# --- Queries --------------------------------------------------------------

# Nearest corner whose mouth the player is standing in (XZ), or -1.
func _nearest_mouth_index() -> int:
	var p: Vector3 = _player.global_position
	var r: float = float(_c.VACUUM_HOP_MOUTH_RADIUS)
	var best := -1
	var best_d: float = r
	for i in range(_anchors.size()):
		var a: Vector3 = _anchors[i]
		var d: float = Vector2(a.x - p.x, a.z - p.z).length()
		if d <= best_d:
			best_d = d
			best = i
	return best


# Nearest served floor level to the player's current height.
func _player_level() -> int:
	var py: float = _player.global_position.y
	var best: int = int(_c.VACUUM_HOP_BOTTOM_LEVEL)
	var bd: float = 1.0e9
	for lvl in range(int(_c.VACUUM_HOP_BOTTOM_LEVEL), int(_c.VACUUM_HOP_TOP_LEVEL) + 1):
		var d: float = absf(py - _surface_y(lvl))
		if d < bd:
			bd = d
			best = lvl
	return best


# Finds the glow material of the tube at corner `idx` on the given floor so the
# hop can pulse it. Tube nodes live under the floor node; we match by XZ anchor.
func _glow_mat_for_corner_on_floor(idx: int, level: int) -> StandardMaterial3D:
	var floor_node: Node = get_node_or_null(NodePath("../Floors/Floor%d" % level))
	if floor_node == null:
		return null
	var anchor: Vector3 = _anchors[idx]
	return _find_tube_glow(floor_node, anchor)


func _find_tube_glow(node: Node, anchor: Vector3) -> StandardMaterial3D:
	for child in node.get_children():
		if child is Node3D and child.name == "VacuumTube":
			var c3 := child as Node3D
			if Vector2(c3.position.x - anchor.x, c3.position.z - anchor.z).length() < 0.2:
				var m = c3.get_meta("glow_mat", null)
				if m is StandardMaterial3D:
					return m
		var found: StandardMaterial3D = _find_tube_glow(child, anchor)
		if found != null:
			return found
	return null


func _pulse_glow(mat: StandardMaterial3D) -> void:
	if mat == null:
		return
	var tween := create_tween()
	tween.tween_property(mat, "emission_energy_multiplier", 5.0, 0.06)
	tween.tween_property(mat, "emission_energy_multiplier", 1.4, 0.5)


# --- Item transit ---------------------------------------------------------

func _update_transit(delta: float) -> void:
	# Advance live capsules; free them at the ceiling.
	var still_alive: Array = []
	for cap in _capsules:
		var node: Node3D = cap.node
		if not is_instance_valid(node):
			continue
		node.position.y += float(_c.VACUUM_TRANSIT_RISE_SPEED) * delta
		if node.position.y >= cap.top_y:
			node.queue_free()
		else:
			still_alive.append(cap)
	_capsules = still_alive

	# Spawn the next capsule on a randomised cadence, rising through a corner on
	# the player's current floor so it's always in the visible band.
	_transit_timer -= delta
	if _transit_timer <= 0.0:
		_transit_timer = _next_transit_gap()
		_spawn_transit_capsule()


func _next_transit_gap() -> float:
	return randf_range(float(_c.VACUUM_TRANSIT_INTERVAL_MIN), float(_c.VACUUM_TRANSIT_INTERVAL_MAX))


func _spawn_transit_capsule() -> void:
	if _state == State.HOPPING or _anchors.is_empty():
		return
	var level: int = _player_level()
	var idx: int = randi() % _anchors.size()
	var anchor: Vector3 = _anchors[idx]
	var base_y: float = _surface_y(level)

	var cap := MeshInstance3D.new()
	cap.name = "TransitItem"
	var mesh := SphereMesh.new()
	mesh.radius = float(_c.VACUUM_TUBE_RADIUS) * 0.5
	mesh.height = mesh.radius * 2.0
	cap.mesh = mesh
	var mat := StandardMaterial3D.new()
	var tint: Color = _random_produce_color()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 0.9
	cap.material_override = mat
	cap.position = Vector3(anchor.x, base_y + 0.4, anchor.z)
	add_child(cap)
	_capsules.append({"node": cap, "top_y": base_y + _story() - 0.2})


func _random_produce_color() -> Color:
	var types: Array = _c.PLANT_TYPES
	if types.is_empty():
		return Color(0.8, 0.5, 0.3)
	var t: Dictionary = types[randi() % types.size()]
	return t.get("fruit_color", Color(0.8, 0.5, 0.3))


# --- Prompt ---------------------------------------------------------------

func _build_prompt() -> void:
	_prompt_root = Node3D.new()
	_prompt_root.name = "VacuumPrompt"
	_prompt_root.visible = false
	add_child(_prompt_root)

	_prompt_key = Label3D.new()
	_prompt_key.text = "JUMP"
	_prompt_key.font_size = 72
	_prompt_key.outline_size = 12
	_prompt_key.modulate = Color(0.72, 0.92, 1.0, 1.0)
	_prompt_key.outline_modulate = Color(0, 0, 0, 0.92)
	_prompt_key.pixel_size = 0.0075
	_prompt_key.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_key.no_depth_test = true
	_prompt_key.position = Vector3(0, 0.45, 0)
	_prompt_root.add_child(_prompt_key)

	_prompt_label = Label3D.new()
	_prompt_label.text = "Vacuum up"
	_prompt_label.font_size = 48
	_prompt_label.outline_size = 8
	_prompt_label.modulate = Color(0.95, 0.98, 1.0, 1.0)
	_prompt_label.outline_modulate = Color(0, 0, 0, 0.92)
	_prompt_label.pixel_size = 0.0075
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.position = Vector3(0, -0.28, 0)
	_prompt_root.add_child(_prompt_label)


func _show_prompt(visible_now: bool, up_ok: bool, down_ok: bool) -> void:
	if _prompt_root == null:
		return
	_prompt_root.visible = visible_now
	if not visible_now:
		return
	if up_ok and down_ok:
		_prompt_key.text = "JUMP ▲   ↓ DOWN ▼"
		_prompt_label.text = "Vacuum lift"
	elif up_ok:
		_prompt_key.text = "JUMP"
		_prompt_label.text = "Vacuum up ▲"
	else:
		_prompt_key.text = "JUMP"
		_prompt_label.text = "Vacuum down ▼"


func _update_prompt_scale() -> void:
	if _prompt_root == null or not _prompt_root.visible:
		return
	# Match the player/elevator prompt: scale the whole group by the camera's
	# ortho size so it stays a constant on-screen height across zoom + modes.
	var ortho: float = float(_gs.camera.get("ortho_size", _c.CAMERA_ORTHO_SIZE_DEFAULT)) if _gs else _c.CAMERA_ORTHO_SIZE_DEFAULT
	var k: float = clampf(ortho / float(_c.CAMERA_ORTHO_SIZE_DEFAULT), 0.18, 1.0)
	_prompt_root.scale = Vector3.ONE * k
