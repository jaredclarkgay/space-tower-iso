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
@export var site_ground_path: NodePath

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
var _site_ground: Node3D        # walkable exterior ground around the tower base (construct + walk)
var _camera: Camera3D            # the iso Camera3D under the pivot (driven during construction)
var _top_level: int = 0          # highest floor level (Roof) — the build target
# True during the external dollhouse CONSTRUCTION view (BUILD_STRUCTURE). Like
# _exterior, it's a world-presentation mode that bypasses the normal per-floor gating.
var _constructing: bool = false
# True while exploring the finished tower's exterior on foot (after the build,
# before walking in). All built floors stay visible; the player walks the site.
var _exterior_walk: bool = false
var _cam_tween_t: float = 1.0    # 0..1 dollhouse->ground camera ease at the start of the walk
var _cam_from_pos: Vector3 = Vector3.ZERO
var _cam_from_size: float = 14.0
# True while the game is on the exterior empty lot (GameDirector EMPTY_LOT): the
# tower is hidden and the normal per-floor gating is bypassed. Cleared by
# enter_tower() when the player heads inside (the continuous-world handoff).
var _exterior: bool = false
var _floors: Array = []        # [{node, level, name, base_y}]
var _current_level: int = 0
var _hud_level: int = -1        # last level pushed to the HUD (force first push)
var _ext_hud_phase: int = -99   # last arc phase the exterior header showed (-99 = none)
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
	_site_ground = get_node_or_null(site_ground_path)
	_camera = _pivot.get_node_or_null("Camera3D") if _pivot else null
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
	_top_level = int(_floors[_floors.size() - 1].level) if not _floors.is_empty() else 0
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
	_ext_hud_phase = -99   # force the exterior header to re-push on (re-)entry
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
	# Phase-aware exterior header (re-pushed when the exterior phase changes, e.g.
	# EMPTY_LOT -> HIRE_PARTNER). set_floor(-1, ...) also hides every floor panel.
	if _hud and _hud.has_method("set_floor"):
		var gd: Node = get_node_or_null("/root/GameDirector")
		var ph: int = int(gd.current_phase) if gd else 0
		if ph != _ext_hud_phase:
			_ext_hud_phase = ph
			_hud_level = -2   # mark non-real so the floor path re-pushes on enter_tower
			_hud.set_floor(-1, "EXTERIOR / CHOOSE A PARTNER" if ph == 1 else "EXTERIOR / EMPTY LOT")
	_drive_environment(snap)


# --- Construct-from-empty (BUILD_STRUCTURE) -------------------------------

# Entry from the hire: CONSTRUCT_FROM_EMPTY -> raise the tower in the dollhouse
# view; else drop straight into the finished Garden (today's dev path).
func begin_build_structure() -> void:
	if bool(_c.CONSTRUCT_FROM_EMPTY):
		enter_construction()
	else:
		enter_tower()


# Enter the external dollhouse: foundation only, player hidden, camera owns the
# framing. The player raises the tower from here with the build action.
func enter_construction() -> void:
	_constructing = true
	_exterior = false
	_gs.set("constructing", true)
	_gs.built_level = 0                       # the basement/foundation is the ground to build on
	if _empty_lot:
		_empty_lot.visible = false
	if _player:
		_player.visible = false
		if _player is CharacterBody3D:
			(_player as CharacterBody3D).velocity = Vector3.ZERO
		_player.global_position = Vector3(0.0, float(_c.FLOOR_3D_TOP_Y), 0.0)
	_hud_level = -99                          # force the construction header to push
	_update(true)


# The dollhouse world: show every BUILT floor (no ceiling-hide), unbuilt absent,
# player hidden, camera framing the rising stack from outside. No physics needed.
func _update_constructing(snap: bool) -> void:
	_current_level = -1                       # exterior daylight preset for _drive_environment
	for f in _floors:
		var node: Node3D = f.node
		var built: bool = int(f.level) <= int(_gs.built_level)
		var slab: StaticBody3D = f.get("slab")
		if slab:
			slab.collision_layer = 0          # external view — no walking, no collision
		if node.has_method("set_structure_visible"):
			node.set_structure_visible(built)
			node.set_slab_alpha(float(_c.FLOOR_4_SLAB_ON_ALPHA) if built else 0.0)
			if node.has_method("set_apertures_visible"):
				node.set_apertures_visible(built)
		else:
			node.visible = built
	if _cityscape:
		_cityscape.visible = false
	if _empty_lot:
		_empty_lot.visible = false
	if _site_ground:
		_site_ground.visible = true       # the tower sits on the build site ground
	_frame_construction(snap)
	if _hud and _hud.has_method("set_construction") and _hud_level != -4:
		_hud_level = -4                       # construction-header marker
		_hud.set_construction(int(_gs.built_level), _top_level)
	_drive_environment(snap)


# Pulled-back iso framing centred on the tower, raised + widened as the stack grows.
func _frame_construction(snap: bool) -> void:
	if _pivot == null:
		return
	var story: float = float(_c.FLOOR_3D_STORY_HEIGHT)
	var center_y: float = float(_gs.built_level) * story * 0.5 + float(_c.CONSTRUCT_CAM_CENTER_LIFT)
	var target := Vector3(0.0, center_y, 0.0)
	_pivot.global_position = target if snap else _pivot.global_position.lerp(target, 0.10)
	if _camera:
		var size: float = float(_c.CONSTRUCT_CAM_SIZE_MIN) + float(_gs.built_level) * float(_c.CONSTRUCT_CAM_SIZE_PER_FLOOR)
		_camera.size = size if snap else lerpf(_camera.size, size, 0.10)


# Raise the next floor with a rise-from-below ceremony; reframe to the taller stack.
func _build_next_floor() -> void:
	if int(_gs.built_level) >= _top_level:
		return                                 # already topped out
	_gs.built_level = int(_gs.built_level) + 1
	var lvl: int = int(_gs.built_level)
	var node: Node3D = null
	for f in _floors:
		if int(f.level) == lvl:
			node = f.node
			break
	if node == null:
		return
	var base_y: float = float(lvl) * float(_c.FLOOR_3D_STORY_HEIGHT)
	node.position.y = base_y - float(_c.CONSTRUCT_RISE_DROP)
	var tw := create_tween()
	tw.tween_property(node, "position:y", base_y, float(_c.CONSTRUCT_RISE_DUR)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Topped out: once the last floor settles, step out to explore the exterior.
	if int(_gs.built_level) >= _top_level:
		tw.finished.connect(_begin_exterior_walk)
	_hud_level = -99                          # force the construction header to re-push (N changed)
	_update(true)


# Leave the dollhouse and put the player on the ground outside the tower to explore.
# The camera eases from the dollhouse framing down to a ground follow (the tween),
# during which the player is held (constructing lock); then control hands back.
func _begin_exterior_walk() -> void:
	_constructing = false
	_exterior_walk = true
	_gs.set("constructing", true)             # hold camera + player for the ease-down
	_gs.built_level = _top_level
	var half: float = float(_c.FLOOR_3D_SIZE) * 0.5
	if _player:
		_player.visible = true
		if _player is CharacterBody3D:
			(_player as CharacterBody3D).velocity = Vector3.ZERO
		_player.global_position = Vector3(0.0, float(_c.FLOOR_3D_TOP_Y), -(half + 6.0))  # on the -Z path
		if _player.has_method("set_spawn_here"):
			_player.set_spawn_here()
	if _site_ground:
		_site_ground.visible = true
	_cam_from_pos = _pivot.global_position if _pivot else Vector3.ZERO
	_cam_from_size = _camera.size if _camera else 14.0
	_cam_tween_t = 0.0
	_hud_level = -5                           # force the explore header
	_update(true)


# The exterior walk: the finished tower stands on its site, the player walks the
# ground (iso_camera follows once the ease-down completes), and crossing into the
# footprint through any doorway enters the building.
func _update_exterior_walk(snap: bool) -> void:
	for f in _floors:
		var node: Node3D = f.node
		var built: bool = int(f.level) <= int(_gs.built_level)
		var slab: StaticBody3D = f.get("slab")
		if slab:
			slab.collision_layer = 2 if (built and int(f.level) == 0) else 0   # only the ground floor is solid
		if node.has_method("set_structure_visible"):
			node.set_structure_visible(built)
			node.set_slab_alpha(float(_c.FLOOR_4_SLAB_ON_ALPHA) if built else 0.0)
			if node.has_method("set_apertures_visible"):
				node.set_apertures_visible(built)
		else:
			node.visible = built
	if _site_ground:
		_site_ground.visible = true
	if _cityscape:
		_cityscape.visible = false
	if _empty_lot:
		_empty_lot.visible = false
	_current_level = -1                       # daylight preset (iso_camera tracks the player itself)
	if _hud and _hud.has_method("set_explore") and _hud_level != -6:
		_hud_level = -6
		_hud.set_explore()
	_drive_environment(snap)
	# Once the ease-down is done (control handed back), crossing into the footprint
	# through a doorway enters the building.
	if not bool(_gs.get("constructing")) and _player:
		var half: float = float(_c.FLOOR_3D_SIZE) * 0.5
		var p: Vector3 = _player.global_position
		if absf(p.x) < half * 0.9 and absf(p.z) < half * 0.9:
			_enter_building()


# Walk-in: enter the finished tower. Drop into the Garden, advance the arc to
# BUILD_INTERIORS, and resume normal interior play.
func _enter_building() -> void:
	_exterior_walk = false
	_gs.set("constructing", false)
	_gs.built_level = _top_level
	if _site_ground:
		_site_ground.visible = false
	if _player:
		_player.visible = true
	var gd: Node = get_node_or_null("/root/GameDirector")
	if gd and gd.has_method("set_phase"):
		gd.set_phase(gd.Phase.BUILD_INTERIORS)
	_spawn_in_garden()
	_hud_level = -1                           # force the floor header to push (iso_camera resumes)
	_update(true)


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
	# Debug: [ starts the day/night clock now (it normally only latches at the
	# TEMPORAL phase), so the lighting swing is testable without walking the arc.
	if Input.is_action_just_pressed(&"debug_start_clock"):
		var tod: Node = get_node_or_null("/root/TimeOfDay")
		if tod and tod.has_method("start"):
			tod.start()
	# Construct-from-empty: raise the next floor (topping out auto-starts the walk).
	if _constructing and Input.is_action_just_pressed(&"build_floor") and int(_gs.built_level) < _top_level:
		_build_next_floor()
	# Ease the camera from the dollhouse down to the ground when the walk begins.
	if _exterior_walk and _cam_tween_t < 1.0:
		_cam_tween_t = minf(_cam_tween_t + delta / float(_c.EXTERIOR_WALK_CAM_TWEEN_DUR), 1.0)
		var e: float = smoothstep(0.0, 1.0, _cam_tween_t)
		if _pivot and _player:
			var ground := Vector3(_player.global_position.x, float(_c.LOT_GROUND_Y) + _PIVOT_CHEST, _player.global_position.z)
			_pivot.global_position = _cam_from_pos.lerp(ground, e)
		if _camera:
			_camera.size = lerpf(_cam_from_size, 16.0, e)
		if _cam_tween_t >= 1.0:
			_gs.set("constructing", false)   # hand the camera + player back (iso_camera follows)
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
	# Construction dollhouse owns the world: external framing, all built floors shown.
	if _constructing:
		_update_constructing(snap)
		return
	# Exterior walk: the finished tower stands on its site; the player walks in.
	if _exterior_walk:
		_update_exterior_walk(snap)
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
		# Construct-from-empty: a floor only exists once built. Unbuilt floors are
		# fully absent (invisible + no collision). With built_level=99 (default)
		# every floor is built, so this reduces to the original at_or_below rule.
		var built: bool = int(f.level) <= int(_gs.built_level)
		var at_or_below: bool = built and (int(f.level) <= _current_level)
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
			# Aperture rings only from the floor directly below or on it (and built).
			if node.has_method("set_apertures_visible"):
				node.set_apertures_visible(built and _current_level >= int(f.level) - 1)
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


# Per-floor environment preset: the floor's lighting IDENTITY (ambient colour/
# energy, background, sun energy) plus `sky_exposure` (0..1) — how much this floor
# reads the day/night sky. Time-of-day modulates ON TOP of the identity, scaled by
# exposure: windowless interiors barely shift; glass/open floors swing the full day.
func _preset_for(level: int) -> Dictionary:
	match level:
		-1: return {"amb": Color(0.86, 0.88, 0.92), "energy": 1.40, "bg": Color(0.50, 0.62, 0.80), "sun": 1.60, "sky_exposure": 1.0}   # Exterior empty lot (open sky)
		0: return {"amb": Color(0.55, 0.60, 0.72), "energy": 0.55, "bg": Color(0.05, 0.05, 0.07), "sun": 0.45, "sky_exposure": 0.0}    # Utility (basement — windowless)
		1: return {"amb": Color(0.66, 0.64, 0.62), "energy": 0.80, "bg": Color(0.07, 0.07, 0.08), "sun": 0.95, "sky_exposure": 0.18}   # Garden (mostly interior)
		2: return {"amb": Color(0.78, 0.84, 0.72), "energy": 1.50, "bg": Color(0.08, 0.13, 0.10), "sun": 1.25, "sky_exposure": 0.40}   # Arboretum (ground)
		3: return {"amb": Color(0.82, 0.88, 0.78), "energy": 1.70, "bg": Color(0.10, 0.16, 0.13), "sun": 1.35, "sky_exposure": 0.60}   # Canopy (glassy upper)
		4: return {"amb": Color(0.74, 0.72, 0.70), "energy": 1.05, "bg": Color(0.12, 0.12, 0.14), "sun": 1.05, "sky_exposure": 0.50}   # Residential (windows)
		5: return {"amb": Color(0.84, 0.88, 0.96), "energy": 1.60, "bg": Color(0.46, 0.60, 0.78), "sun": 1.45, "sky_exposure": 1.0}    # Sky Lounge (floor-to-ceiling glass)
		# Roof / Vista (top): open to the sky — full day/night swing.
		_: return {"amb": Color(0.80, 0.86, 0.95), "energy": 1.95, "bg": Color(0.42, 0.55, 0.70), "sun": 1.55, "sky_exposure": 1.0}


# Drives the visibility of every passive spine-pipe fill (floors 2-4) from the
# live Floor 1 utility state, so lit risers continue up the whole shaft instead
# of stopping at the floor they were built on. Floor 1 builds its own animated
# pipes separately; these are the cross-floor copies.
func _update_spine_pipe_fills() -> void:
	var active: Dictionary = _gs.utility.get("pipe_active", {})
	for fill in get_tree().get_nodes_in_group("passive_spine_fill"):
		var id: String = String(fill.get_meta("sys_id", ""))
		fill.visible = bool(active.get(id, false))


# Global day/night modulation derived from normalized time-of-day (0..1). Pure
# function of the hour — no per-location logic (floors apply it scaled by their
# sky_exposure). Smooth curves throughout (gradients, not switches).
func _sky_state(t: float) -> Dictionary:
	var elev: float = -cos(TAU * t)                      # -1 midnight, 0 dawn/dusk, +1 noon
	var day: float = smoothstep(-0.15, 0.5, elev)        # 0 deep night -> 1 daylight
	var high: float = clampf(elev, 0.0, 1.0)             # 0 at the horizon -> 1 at noon
	# Night floor -> identity by daybreak, plus a midday GAIN that peaks at noon so
	# daylight reads brighter than the neutral identity (and night dimmer).
	var intensity: float = lerpf(float(_c.TOD_NIGHT_INTENSITY), 1.0, day) + (float(_c.TOD_DAY_INTENSITY) - 1.0) * high
	# Warmth: cool moonlight at night, golden near the horizon, white at noon.
	var golden := Color(1.00, 0.72, 0.45)
	var moon := Color(0.55, 0.64, 0.92)
	var warmth: Color = moon.lerp(golden.lerp(Color.WHITE, high), day)
	# Sky bg: dark night -> warm horizon -> bright day blue.
	var night_sky := Color(0.04, 0.05, 0.10)
	var horizon_sky := Color(0.76, 0.46, 0.28)
	var day_sky := Color(0.58, 0.73, 0.95)
	var sky_tint: Color = night_sky.lerp(horizon_sky.lerp(day_sky, high), day)
	# Sun rotation: elevation tracks the curve; azimuth sweeps east->west by day.
	var pitch: float = lerpf(float(_c.TOD_SUN_PITCH_MIN), float(_c.TOD_SUN_PITCH_MAX), elev * 0.5 + 0.5)
	var yaw: float = lerpf(-float(_c.TOD_SUN_YAW_SWEEP), float(_c.TOD_SUN_YAW_SWEEP), clampf((t - 0.25) / 0.5, 0.0, 1.0))
	return {"intensity": intensity, "warmth": warmth, "sky_tint": sky_tint, "sun_pitch": pitch, "sun_yaw": yaw}


func _drive_environment(snap: bool) -> void:
	if _world_env == null or _world_env.environment == null:
		return
	var p := _preset_for(_current_level)
	var env := _world_env.environment
	var k: float = 1.0 if snap else 0.06
	# Targets start at the floor's IDENTITY; time-of-day modulates on top, scaled by
	# this floor's sky exposure. Clock dormant (pre-TEMPORAL) or exposure 0 -> no-op,
	# so the look is exactly today's.
	var amb: Color = p.amb
	var energy: float = float(p.energy)
	var bg: Color = p.bg
	var sun: float = float(p.sun)
	var exposure: float = float(p.get("sky_exposure", 0.0))
	var tod: Node = get_node_or_null("/root/TimeOfDay")
	var running: bool = tod != null and bool(tod.running)
	var s: Dictionary = _sky_state(float(_gs.time_of_day)) if running else {}
	if running and exposure > 0.0:
		var lvl: float = lerpf(1.0, float(s.intensity), exposure)
		var warmth: Color = s.warmth
		amb = (p.amb as Color).lerp((p.amb as Color) * warmth, exposure)
		energy = float(p.energy) * lvl
		sun = float(p.sun) * lvl
		bg = (p.bg as Color).lerp(s.sky_tint, exposure)
	env.ambient_light_color = env.ambient_light_color.lerp(amb, k)
	env.ambient_light_energy = lerpf(env.ambient_light_energy, energy, k)
	env.background_color = env.background_color.lerp(bg, k)
	if _env_light:
		_env_light.light_energy = lerpf(_env_light.light_energy, sun, k)
		# Sun DIRECTION is global + time-driven (only once the clock runs); harmless on
		# low-exposure floors because their sun energy stays low.
		if running:
			var target_rot := Vector3(-float(s.sun_pitch), float(s.sun_yaw), 0.0)
			_env_light.rotation_degrees = target_rot if snap else _env_light.rotation_degrees.lerp(target_rot, k)


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
