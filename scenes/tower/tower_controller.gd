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

# Floors present in the tower. `node` is relative to this controller, `level`
# is 1=bottom, `name` is the HUD header text. Append Floors 1 & 2 in Phase 2.
const _FLOORS := [
	{"node": "Floors/Floor3", "level": 3, "name": "FLOOR 3 / ARBORETUM"},
	{"node": "Floors/Floor4", "level": 4, "name": "FLOOR 4 / CANOPY"},
]
const _PIVOT_CHEST := 1.0      # camera look-at height above a floor's surface

var _player: Node3D
var _pivot: Node3D
var _header: Label
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
	var story: float = float(_c.FLOOR_3D_STORY_HEIGHT)
	_reveal_margin = story * 0.5
	for f in _FLOORS:
		var node: Node3D = get_node_or_null(NodePath(f.node))
		if node == null:
			continue
		var base_y: float = float(int(f.level) - 1) * story
		node.position.y = base_y          # geometry (built local) rides up with the node
		_floors.append({"node": node, "level": int(f.level), "name": String(f.name), "base_y": base_y})
	# The tower owns the player spawn (derived from the floor heights), not the
	# .tscn — keeps it correct if the story height changes.
	if _player and not _floors.is_empty():
		var spawn_y: float = float(_floors[0].base_y) + float(_c.FLOOR_3D_TOP_Y)
		_player.global_position = Vector3(0.0, spawn_y, -6.0)
		if _player.has_method("set_spawn_here"):
			_player.set_spawn_here()
	_update(true)


func _process(delta: float) -> void:
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
	# never reveals the floor above or moves the camera off your floor. You
	# change floors by landing (walk up the stairs, or jump up through a ring).
	var grounded: bool = _player.has_method("is_on_floor") and _player.is_on_floor()
	if snap or grounded:
		_current_level = _level_for_y(_player.global_position.y)
	for f in _floors:
		var node: Node3D = f.node
		var at_or_below: bool = (int(f.level) <= _current_level)
		if node.has_method("set_structure_visible"):
			# Glass-ceiling floor (Canopy): walls/elevator gated; the slab is an
			# invisible glass ceiling from below and a frosted-glass floor when
			# you stand on it. Its aperture rings stay faintly visible as
			# jump-through aim targets, and a bonk lights a localized glow.
			node.set_structure_visible(at_or_below)
			node.set_slab_alpha(float(_c.FLOOR_4_SLAB_ON_ALPHA) if at_or_below else 0.0)
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


# Highest floor whose surface is at or just below the player. The reveal margin
# lets the floor above appear while the player is still climbing toward it.
func _level_for_y(py: float) -> int:
	var top_y: float = float(_c.FLOOR_3D_TOP_Y)
	var level: int = int(_floors[0].level)
	for f in _floors:
		if py + _reveal_margin >= f.base_y + top_y:
			level = maxi(level, int(f.level))
	return level


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
