extends Node3D

# Stacked-tower world controller. Owns the single player + camera and drives the
# multi-floor experience:
#   - positions each floor node at its real height,
#   - tracks which floor the player is on,
#   - hides floors ABOVE the player so the top-down iso view isn't ceilinged
#     (you see your floor + everything below; climbing reveals the next floor),
#   - raises/lowers the camera pivot with the player's level,
#   - keeps the HUD header in sync with the current floor.
#
# Each floor is a child Node3D whose controller builds geometry in LOCAL space
# (slab top at local y=0); the vertical offset is purely the node transform set
# here, so floor_chrome.gd / the floor controllers need no base_y awareness.

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

@export var player_path: NodePath
@export var camera_pivot_path: NodePath
@export var header_label_path: NodePath
@export var world_environment_path: NodePath
@export var env_light_path: NodePath

# Floors present in the tower. `node` is relative to this controller, `level`
# is 1=bottom, `name` is the HUD header text. Append Floors 1 & 2 in Phase 2.
const _FLOORS := [
	{"node": "Floors/Floor1", "level": 1, "name": "FLOOR 1 / UTILITY"},
	{"node": "Floors/Floor2", "level": 2, "name": "FLOOR 2 / GARDEN"},
	{"node": "Floors/Floor3", "level": 3, "name": "FLOOR 3 / ARBORETUM"},
	{"node": "Floors/Floor4", "level": 4, "name": "FLOOR 4 / CANOPY"},
]
const _SPAWN_LEVEL := 2   # the player starts on the Garden (home floor)
const _PIVOT_CHEST := 1.0      # camera look-at height above a floor's surface

var _player: Node3D
var _pivot: Node3D
var _header: Label
var _world_env: WorldEnvironment
var _env_light: DirectionalLight3D
var _floors: Array = []        # [{node, level, name, base_y}]
var _current_level: int = 0
# Decays 1→0 after the player bonks their head on the ceiling; drives the
# localized glass ping on the floor directly above them, placed at _bonk_pos.
var _ceiling_pulse: float = 0.0
var _bonk_pos: Vector3 = Vector3.ZERO
# Half a story — how far below a floor's surface still reveals it (set in _ready).
var _reveal_margin: float = 3.0


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_pivot = get_node_or_null(camera_pivot_path)
	_header = get_node_or_null(header_label_path)
	_world_env = get_node_or_null(world_environment_path)
	_env_light = get_node_or_null(env_light_path)
	var story: float = float(_c.FLOOR_3D_STORY_HEIGHT)
	_reveal_margin = story * 0.5
	for f in _FLOORS:
		var node: Node3D = get_node_or_null(NodePath(f.node))
		if node == null:
			continue
		var base_y: float = float(int(f.level) - 1) * story
		node.position.y = base_y          # geometry (built local) rides up with the node
		# Regular floors build their slab as a StaticBody3D named "SlabBody"
		# (FloorChrome.build_slab). We toggle its collision per current floor so
		# a jump passes UP through the ceiling and falls back to the same floor
		# (never lands above). The Canopy's slab is "TiledSlabBody" and is NOT
		# found here, so its collision is left permanently on — the one glass
		# ceiling you can bonk (3 → 4).
		var slab: StaticBody3D = _find_slab_body(node)
		_floors.append({"node": node, "level": int(f.level), "name": String(f.name), "base_y": base_y, "slab": slab})
	# The tower owns the player spawn (derived from the floor heights), not the
	# .tscn — keeps it correct if the story height changes.
	if _player and not _floors.is_empty():
		var spawn_y: float = _base_y_for_level(_SPAWN_LEVEL) + float(_c.FLOOR_3D_TOP_Y)
		_player.global_position = Vector3(0.0, spawn_y, -6.0)
		if _player.has_method("set_spawn_here"):
			_player.set_spawn_here()
	_update(true)


func _process(delta: float) -> void:
	# Debug: backslash cycles the player up through the floors (wraps at the
	# top). Temporary traversal aid until the elevator platform lands (2b).
	if Input.is_action_just_pressed(&"debug_floor_switch"):
		_debug_cycle_floor()
	# Ceiling bonk → a localized glass glow at the hit point on the floor above.
	if _player and _player.has_method("is_on_ceiling") and _player.is_on_ceiling():
		_ceiling_pulse = 1.0
		_bonk_pos = _player.global_position
	else:
		_ceiling_pulse = maxf(_ceiling_pulse - delta * float(_c.FLOOR_4_CEILING_PULSE_DECAY), 0.0)
	_update(false)


func _update(snap: bool) -> void:
	if _player == null or _floors.is_empty():
		return
	# Only change floors when GROUNDED — so jumping (or bonking the ceiling)
	# never reveals the floor above or moves the camera off your floor. It also
	# keeps the floor-above slab gating (below) frozen mid-jump, so a jump arcs
	# up through the ceiling and falls back to the SAME floor. You change floors
	# by riding the elevator or walking the stairs, never by jumping.
	var grounded: bool = _player.has_method("is_on_floor") and _player.is_on_floor()
	if snap or grounded:
		_current_level = _level_for_y(_player.global_position.y)
	for f in _floors:
		var node: Node3D = f.node
		var at_or_below: bool = (int(f.level) <= _current_level)
		# Slab collision: solid for your floor + everything below, OFF for floors
		# above so a jump passes straight up through the ceiling and falls back
		# to the same floor. Canopy has no "SlabBody" (slab = null) → its glass
		# ceiling collision is never touched here, so Floor 3 jumps still bonk it.
		var slab: StaticBody3D = f.get("slab")
		if slab:
			slab.collision_layer = 2 if at_or_below else 0
		if node.has_method("set_structure_visible"):
			# Glass-ceiling floor (Canopy): walls/elevator gated; the slab is an
			# invisible glass ceiling from below and a frosted-glass floor when
			# you stand on it. Its tree-hole aperture rings stay faintly visible
			# from the floor below, and bonking the glass ceiling (you can't jump
			# through it — it's the one solid ceiling) lights a localized glow.
			node.set_structure_visible(at_or_below)
			node.set_slab_alpha(float(_c.FLOOR_4_SLAB_ON_ALPHA) if at_or_below else 0.0)
			# Aperture rings only from the floor directly below or on it.
			if node.has_method("set_apertures_visible"):
				node.set_apertures_visible(_current_level >= int(f.level) - 1)
			if node.has_method("set_ceiling_ping"):
				var ping: float = _ceiling_pulse if int(f.level) == _current_level + 1 else 0.0
				node.set_ceiling_ping(_bonk_pos, ping)
		else:
			# Plain floor: show the current floor + everything below, hide above.
			node.visible = at_or_below
	# HUD header reflects the current floor.
	if _header:
		_header.text = _name_for_level(_current_level)
	# Camera pivot rises/lowers with the current floor — only in iso mode and
	# outside dialogue, where the camera owns the pivot pose itself.
	if _pivot and String(_gs.get("camera_mode")) == "iso" and not bool(_gs.get("dialogue_open")):
		var target_y: float = _base_y_for_level(_current_level) + _PIVOT_CHEST
		_pivot.position.y = target_y if snap else lerpf(_pivot.position.y, target_y, 0.12)
	# Ambience eases to the current floor's mood (Utility dark, Garden warm,
	# Arboretum/Canopy bright green).
	_drive_environment(snap)


# Per-floor environment preset: ambient colour/energy, background, sun energy.
func _preset_for(level: int) -> Dictionary:
	match level:
		1: return {"amb": Color(0.55, 0.60, 0.72), "energy": 0.55, "bg": Color(0.05, 0.05, 0.07), "sun": 0.45}
		2: return {"amb": Color(0.66, 0.64, 0.62), "energy": 0.80, "bg": Color(0.07, 0.07, 0.08), "sun": 0.95}
		3: return {"amb": Color(0.78, 0.84, 0.72), "energy": 1.50, "bg": Color(0.08, 0.13, 0.10), "sun": 1.25}
		_: return {"amb": Color(0.82, 0.88, 0.78), "energy": 1.70, "bg": Color(0.10, 0.16, 0.13), "sun": 1.35}


func _drive_environment(snap: bool) -> void:
	if _world_env == null or _world_env.environment == null:
		return
	var p := _preset_for(_current_level)
	var env := _world_env.environment
	var k: float = 1.0 if snap else 0.06
	env.ambient_light_color = env.ambient_light_color.lerp(p.amb, k)
	env.ambient_light_energy = lerpf(env.ambient_light_energy, float(p.energy), k)
	env.background_color = env.background_color.lerp(p.bg, k)
	if _env_light:
		_env_light.light_energy = lerpf(_env_light.light_energy, float(p.sun), k)


# Highest floor whose surface is at or just below the player. The reveal margin
# lets the floor above appear while the player is still climbing toward it.
func _debug_cycle_floor() -> void:
	if _player == null or _floors.is_empty():
		return
	var top_level: int = int(_floors[_floors.size() - 1].level)
	var next: int = _current_level + 1
	if next > top_level:
		next = int(_floors[0].level)
	_player.global_position = Vector3(0.0, _base_y_for_level(next) + float(_c.FLOOR_3D_TOP_Y) + 0.1, -6.0)
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO


func _level_for_y(py: float) -> int:
	var top_y: float = float(_c.FLOOR_3D_TOP_Y)
	var level: int = int(_floors[0].level)
	for f in _floors:
		if py + _reveal_margin >= f.base_y + top_y:
			level = maxi(level, int(f.level))
	return level


# First descendant StaticBody3D named "SlabBody" (FloorChrome.build_slab's
# slab). Returns null for the Canopy, whose slab is "TiledSlabBody" — that's
# intentional: the Canopy slab stays permanently solid as the glass ceiling.
func _find_slab_body(node: Node) -> StaticBody3D:
	for child in node.get_children():
		if child is StaticBody3D and child.name == "SlabBody":
			return child
		var found: StaticBody3D = _find_slab_body(child)
		if found != null:
			return found
	return null


func _base_y_for_level(level: int) -> float:
	for f in _floors:
		if int(f.level) == level:
			return float(f.base_y)
	return 0.0


func _name_for_level(level: int) -> String:
	for f in _floors:
		if int(f.level) == level:
			return String(f.name)
	return ""
