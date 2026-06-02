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
@export var hud_manager_path: NodePath
@export var world_environment_path: NodePath
@export var env_light_path: NodePath
@export var cityscape_path: NodePath
@export var empty_lot_path: NodePath

# Floors present in the tower. `node` is relative to this controller, `level`
# is 0=basement (Utility) and counts UP; `name` is the HUD header text (the part
# before "/" is the eyebrow). The Roof has no floor number — it shows "ROOF".
const _FLOORS := [
	{"node": "Floors/Utility", "level": 0, "name": "FLOOR 0 / UTILITY"},
	{"node": "Floors/Garden", "level": 1, "name": "FLOOR 1 / GARDEN"},
	{"node": "Floors/ArboretumGround", "level": 2, "name": "FLOOR 2 / ARBORETUM"},
	{"node": "Floors/ArboretumCanopy", "level": 3, "name": "FLOOR 3 / CANOPY"},
	{"node": "Floors/Residential", "level": 4, "name": "FLOOR 4 / RESIDENTIAL"},
	{"node": "Floors/SkyLounge", "level": 5, "name": "FLOOR 5 / SKY LOUNGE"},
	{"node": "Floors/Roof", "level": 6, "name": "ROOF / VISTA — UNDER CONSTRUCTION"},
]
const _SPAWN_LEVEL := 1   # the player starts on the Garden (home floor)
const _PIVOT_CHEST := 1.0      # camera look-at height above a floor's surface
# Fraction of the player's height-above-floor the pivot follows on a jump, so a
# big jump stays in frame without the camera feeling glued to the body.
const _JUMP_FOLLOW_FRACTION := 0.55

var _player: Node3D
var _pivot: Node3D
var _hud: Node
var _world_env: WorldEnvironment
var _env_light: DirectionalLight3D
var _cityscape: Node3D
var _empty_lot: Node3D
# True while the game is on the exterior empty lot (GameDirector EMPTY_LOT): the
# tower is hidden and the normal per-floor gating is bypassed. Cleared by
# enter_tower() when the player heads inside (the continuous-world handoff).
var _exterior: bool = false
var _floors: Array = []        # [{node, level, name, base_y}]
var _current_level: int = 0
var _hud_level: int = -1        # last level pushed to the HUD (force first push)
var _pulse_level: int = 0       # last level the camera-arrival pulse saw
# Decays 1→0 after the player bonks their head on the ceiling; drives the
# localized glass ping on the floor directly above them, placed at _bonk_pos.
var _ceiling_pulse: float = 0.0
var _bonk_pos: Vector3 = Vector3.ZERO
# Half a story — how far below a floor's surface still reveals it (set in _ready).
var _reveal_margin: float = 3.0


func _ready() -> void:
	_player = get_node_or_null(player_path)
	_pivot = get_node_or_null(camera_pivot_path)
	_hud = get_node_or_null(hud_manager_path)
	_world_env = get_node_or_null(world_environment_path)
	_env_light = get_node_or_null(env_light_path)
	_cityscape = get_node_or_null(cityscape_path)
	_empty_lot = get_node_or_null(empty_lot_path)
	add_to_group("tower_controller")   # so the hire panel can reach enter_tower()
	var story: float = float(_c.FLOOR_3D_STORY_HEIGHT)
	_reveal_margin = story * 0.5
	for f in _FLOORS:
		var node: Node3D = get_node_or_null(NodePath(f.node))
		if node == null:
			continue
		var base_y: float = float(int(f.level)) * story
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
	# .tscn — keeps it correct if the story height changes. Boot picks the start
	# STATE within this one scene (decision D-002): the real opening drops onto
	# the exterior empty lot; the dev fallback boots straight to the Garden.
	if _player and not _floors.is_empty():
		var gd: Node = get_node_or_null("/root/GameDirector")
		var to_exterior: bool = bool(_c.BOOT_TO_EXTERIOR) and gd != null and int(gd.current_phase) == 0 and _empty_lot != null
		if to_exterior:
			enter_exterior()
		else:
			_spawn_in_garden()
			if _empty_lot:
				_empty_lot.visible = false
	_update(true)


# Today's Garden spawn (derived from the floor heights). Shared by the dev boot
# and the exterior->tower handoff so both land in the exact same spot.
func _spawn_in_garden() -> void:
	var spawn_y: float = _base_y_for_level(_SPAWN_LEVEL) + float(_c.FLOOR_3D_TOP_Y)
	_player.global_position = Vector3(0.0, spawn_y, -6.0)
	if _player.has_method("set_spawn_here"):
		_player.set_spawn_here()


# Hand off from the exterior empty lot into the tower (called by the Step 3
# hire). The continuous-world transition: clear exterior mode, hide the lot,
# drop the player at the Garden spawn. No scene swap.
func enter_tower() -> void:
	if not _exterior:
		return
	_exterior = false
	if _empty_lot:
		_empty_lot.visible = false
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO
	_spawn_in_garden()
	_hud_level = -1   # force the HUD to re-push the floor header
	_update(true)


# Enter (or return to) the exterior empty lot: spawn the player on the lot and
# flip on exterior mode. Used by the boot branch and by the debug phase walk
# when it wraps back to EMPTY_LOT.
func enter_exterior() -> void:
	_exterior = true
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO
	if _empty_lot:
		_player.global_position = _empty_lot.spawn_position()
	if _player.has_method("set_spawn_here"):
		_player.set_spawn_here()
	_hud_level = -3   # force the exterior header to re-push (distinct from -2/-1)
	_update(true)


# The empty-lot world: hide the tower + cityscape, keep the lot solid, frame the
# camera on the dirt, neutral exterior header (no floor panels). XZ follow is the
# camera's own job (iso_camera); we only set pivot.Y + the outdoor environment.
func _update_exterior(snap: bool) -> void:
	_current_level = -1   # exterior daylight preset; recomputed on enter_tower
	for f in _floors:
		var node: Node3D = f.node
		if node.has_method("set_structure_visible"):
			node.set_structure_visible(false)
		else:
			node.visible = false
	if _cityscape:
		_cityscape.visible = false
	if _empty_lot:
		_empty_lot.visible = true
	if _pivot and String(_gs.get("camera_mode")) == "iso" and not bool(_gs.get("dialogue_open")) and not bool(_gs.get("looking_out")):
		var target_y: float = float(_c.LOT_GROUND_Y) + _PIVOT_CHEST
		_pivot.position.y = target_y if snap else lerpf(_pivot.position.y, target_y, 0.12)
	if _hud and _hud.has_method("set_floor") and _hud_level != -2:
		_hud_level = -2   # exterior-header marker (distinct from -1 force-repush + real levels)
		_hud.set_floor(-1, "EXTERIOR / EMPTY LOT")
	_drive_environment(snap)


func _process(delta: float) -> void:
	# Debug: backslash cycles the player up through the floors (wraps at the
	# top). Temporary traversal aid until the elevator platform lands (2b).
	if Input.is_action_just_pressed(&"debug_floor_switch"):
		_debug_cycle_floor()
	# Debug: ] walks the GameDirector phase, keeping the world coherent (the
	# exterior beats stay on the lot; advancing inward enters the tower; wrapping
	# back to EMPTY_LOT returns to the lot).
	if Input.is_action_just_pressed(&"debug_advance_phase"):
		_debug_advance_phase()
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
	# Exterior empty lot owns the world: tower hidden, no per-floor gating.
	if _exterior:
		_update_exterior(snap)
		return
	# Change floors when GROUNDED or while RIDING the elevator — never mid-jump.
	# Freezing it mid-jump is what lets a jump arc up through the ceiling and
	# fall back to the SAME floor (the floor-above slab gating below stays
	# frozen). Tracking it during an elevator ride is what keeps it correct on
	# arrival: is_on_floor() is stale while the car owns the player's transform,
	# so without this the destination slab could still be gated OFF when you
	# step off the car and you'd fall straight through it (the fall-through bug).
	var grounded: bool = _player.has_method("is_on_floor") and _player.is_on_floor()
	var riding: bool = bool(_gs.get("riding_elevator"))
	# A vacuum-lift hop owns the player's transform mid-flight (is_on_floor() is
	# stale), so track the level during it exactly like the elevator ride — the
	# destination floor's slab must be solid when the hop lands or the player
	# falls straight through it (same fall-through class as F-022).
	var hopping: bool = bool(_gs.get("tube_hopping"))
	if snap or grounded or riding or hopping:
		_current_level = _level_for_y(_player.global_position.y)
	# Tell the camera to pulse a brief survey of the new floor on arrival (not on
	# the initial spawn snap).
	if not snap and _current_level != _pulse_level and _pulse_level != 0:
		_gs.set("camera_arrival_pulse", true)
	_pulse_level = _current_level
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
	# HUD reflects the current floor — title, wayfinding, and which floor's
	# gameplay panels are shown. Only push on change (set_floor relays out).
	if _hud and _hud.has_method("set_floor") and _current_level != _hud_level:
		_hud_level = _current_level
		_hud.set_floor(_current_level, _name_for_level(_current_level))
	# Camera pivot rises/lowers with the current floor — only in iso mode and
	# outside dialogue, where the camera owns the pivot pose itself.
	if _pivot and String(_gs.get("camera_mode")) == "iso" and not bool(_gs.get("dialogue_open")) and not bool(_gs.get("looking_out")):
		var floor_anchor: float = _base_y_for_level(_current_level) + _PIVOT_CHEST
		# Jump-follow: now that a charged jump clears ~9 m, anchoring the pivot to
		# the floor lets the player launch clean out of the top of frame. Let the
		# pivot chase a FRACTION of how far they've risen above the floor so they
		# stay in shot, then ease back down on landing. Partial (not 1:1) keeps a
		# stable ground reference instead of gluing the camera to the body.
		var floor_surface: float = _base_y_for_level(_current_level) + float(_c.FLOOR_3D_TOP_Y)
		var rise: float = maxf(0.0, _player.global_position.y - floor_surface)
		var target_y: float = floor_anchor + rise * _JUMP_FOLLOW_FRACTION
		_pivot.position.y = target_y if snap else lerpf(_pivot.position.y, target_y, 0.12)
	# The placeholder cityscape shows only from the upper floors (so it doesn't
	# clutter the tight iso framing down on the Garden / Utility).
	if _cityscape:
		_cityscape.visible = _current_level >= int(_c.CITY_REVEAL_LEVEL)
	# Light the passive spine-pipe risers on the floors above Utility to match
	# whatever's online down on Floor 1 — so an activated utility glows
	# continuously all the way up the shaft, not just on its own floor.
	_update_spine_pipe_fills()
	# Ambience eases to the current floor's mood (Utility dark, Garden warm,
	# Arboretum/Canopy bright green).
	_drive_environment(snap)


# Per-floor environment preset: ambient colour/energy, background, sun energy.
func _preset_for(level: int) -> Dictionary:
	match level:
		-1: return {"amb": Color(0.86, 0.88, 0.92), "energy": 1.40, "bg": Color(0.50, 0.62, 0.80), "sun": 1.60}  # Exterior empty lot (open daylight)
		0: return {"amb": Color(0.55, 0.60, 0.72), "energy": 0.55, "bg": Color(0.05, 0.05, 0.07), "sun": 0.45}  # Utility (basement)
		1: return {"amb": Color(0.66, 0.64, 0.62), "energy": 0.80, "bg": Color(0.07, 0.07, 0.08), "sun": 0.95}  # Garden
		2: return {"amb": Color(0.78, 0.84, 0.72), "energy": 1.50, "bg": Color(0.08, 0.13, 0.10), "sun": 1.25}  # Arboretum (ground)
		3: return {"amb": Color(0.82, 0.88, 0.78), "energy": 1.70, "bg": Color(0.10, 0.16, 0.13), "sun": 1.35}  # Canopy
		4: return {"amb": Color(0.74, 0.72, 0.70), "energy": 1.05, "bg": Color(0.12, 0.12, 0.14), "sun": 1.05}  # Residential (warm interior)
		5: return {"amb": Color(0.84, 0.88, 0.96), "energy": 1.60, "bg": Color(0.46, 0.60, 0.78), "sun": 1.45}  # Sky Lounge (glass, sky beyond)
		# Roof / Vista (top): open to the sky — bright, cool, airy, with a pale horizon.
		_: return {"amb": Color(0.80, 0.86, 0.95), "energy": 1.95, "bg": Color(0.42, 0.55, 0.70), "sun": 1.55}


# Drives the visibility of every passive spine-pipe fill (floors 2-4) from the
# live Floor 1 utility state, so lit risers continue up the whole shaft instead
# of stopping at the floor they were built on. Floor 1 builds its own animated
# pipes separately; these are the cross-floor copies.
func _update_spine_pipe_fills() -> void:
	var active: Dictionary = _gs.utility.get("pipe_active", {})
	for fill in get_tree().get_nodes_in_group("passive_spine_fill"):
		var id: String = String(fill.get_meta("sys_id", ""))
		fill.visible = bool(active.get(id, false))


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


func _debug_advance_phase() -> void:
	var gd: Node = get_node_or_null("/root/GameDirector")
	if gd == null:
		return
	gd.advance_phase()
	var phase: int = int(gd.current_phase)
	var on_exterior_beat: bool = phase == 0 or phase == 1   # EMPTY_LOT / HIRE_PARTNER
	if _exterior and not on_exterior_beat:
		enter_tower()
	elif not _exterior and on_exterior_beat:
		enter_exterior()


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
