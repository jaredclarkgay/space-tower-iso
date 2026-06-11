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
@onready var _tel: Node = get_node_or_null("/root/Telemetry")

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
# Dev "chapter jump" list — the single source of truth for the always-clickable
# overlay (chapter_jump.gd reads this). Each entry maps a stable id to a label;
# jump_to_chapter(id) sets the matching state. Floor ids below resolve to a level
# in jump_to_chapter (utility=0 … roof=top), so adding a floor only needs a row.
const CHAPTERS := [
	{"id": "empty_lot",    "label": "Empty Lot (survey)"},
	{"id": "hire",         "label": "Hire a Partner"},
	{"id": "build",        "label": "Build the Tower"},
	{"id": "garden_intro", "label": "Garden — Intro Cinematic"},
	{"id": "garden",       "label": "Garden (Floor 1)"},
	{"id": "utility",      "label": "Utility (Floor 0)"},
	{"id": "arboretum",    "label": "Arboretum (Floor 2)"},
	{"id": "canopy",       "label": "Canopy (Floor 3)"},
	{"id": "residential",  "label": "Residential (Floor 4)"},
	{"id": "sky_lounge",   "label": "Sky Lounge (Floor 5)"},
	{"id": "roof",         "label": "Roof / Vista"},
]
# Chapter id -> floor level for the plain "teleport onto a floor" jumps.
const _CHAPTER_FLOOR := {
	"utility": 0, "arboretum": 2, "canopy": 3, "residential": 4, "sky_lounge": 5,
}
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
# Arrival cinematic (FIRST Garden entry, Beats 0-2): spawn at the south doorway,
# auto-walk inward behind a lowering follow camera, stop at a mark, then hand off
# to Cody's in-place arrival. _arrival_played is the one-shot gate; _arrival_cine is
# active; _arrival_beat is the beat index (1=walk, 2=stop-hold); _arrival_t times
# the camera lower-in and the stop hold.
var _arrival_played: bool = false
var _arrival_cine: bool = false
var _arrival_beat: int = 0
var _arrival_t: float = 0.0
var _arrival_walk_started: bool = false   # first-tick guard for begin_scripted_walk
# Beat-3 elevator-emergence sub-phasing (Step 3). The conductor puppets the
# elevator car + Cody up the shaft, concurrently with the orbit sweep.
var _emerge_started: bool = false         # one-shot Beat-3 entry guard
var _emerge_rollout_started: bool = false # one-shot: roll-out fired
var _emerge_basement_y: float = 0.0       # car_y at the basement (level 0)
var _emerge_garden_y: float = 0.0         # car_y at the Garden (level 1)
# Beat-3 focus point (JOB 1): the camera look-at target eases from the player toward
# lerp(player, elevator-center, FOCUS_BIAS) during the emergence so the car/Cody
# roll-out is hero-framed. The eased look-at is now the persistent _cam_focus member
# (see _drive_arrival_camera); each beat sets _cam_focus_tgt and the member glides.
# Beat-4 resume ease (JOB 2): before releasing, ease the conductor-owned camera
# to iso's RESTING pose so iso_camera continues without a jump-cut. Captured at
# Beat-4 entry; the ease runs over ARRIVAL_CINE_RESUME_DUR then clears the flag.
# Beat-5 conversation orbit (ASK 3): after the emergence completes, the dialogue
# auto-opens and a slow close orbit circles the player↔Cody pair until the player
# ends the conversation; only then does Beat 4 (resume ease) run. _convo_opened is
# the one-shot auto-open guard; _convo_yaw is the continuously-advancing orbit yaw.
var _convo_opened: bool = false
var _convo_yaw: float = 0.0
# Smoothed camera-state members that PERSIST across beats. Each beat sets only the
# TARGET (the `*_tgt` locals fed to _drive_arrival_camera); these members ease toward
# those targets every frame with frame-rate-aware exponential smoothing, then the pose
# is applied ONCE. Because every parameter eases continuously, every beat boundary
# glides — the shoulder eases to 0 entering the orbit (no lateral pop), the OTS look-at
# bias eases out (no look-direction snap), and the conversation-orbit seed becomes a
# smooth glide rather than a 30° jump. Seeded at cinematic start to the OTS pose.
var _cam_init: bool = false       # false until _begin_arrival_cinematic seeds the members
var _cam_focus: Vector3 = Vector3.ZERO  # world look-at anchor (pivot position)
var _cam_size: float = 0.0        # ortho size
var _cam_yaw: float = 0.0         # pivot Y rotation, radians
var _cam_back: float = 0.0        # camera distance behind the pivot (-Z local)
var _cam_lift: float = 0.0        # camera height above the pivot
var _cam_shoulder: float = 0.0    # lateral OTS offset (eases to 0 for the orbit)
var _cam_lookahead: float = 0.0   # how far ahead (+Z local) the look-at sits
var _cam_looklift: float = 0.0    # height of the look-at target
# Per-beat TARGETS each beat writes; _drive_arrival_camera eases the _cam_* members
# toward these every frame, then applies the pose once.
var _cam_focus_tgt: Vector3 = Vector3.ZERO
var _cam_size_tgt: float = 0.0
var _cam_yaw_tgt: float = 0.0
var _cam_back_tgt: float = 0.0
var _cam_lift_tgt: float = 0.0
var _cam_shoulder_tgt: float = 0.0
var _cam_lookahead_tgt: float = 0.0
var _cam_looklift_tgt: float = 0.0
var _resume_t: float = 0.0
var _resume_started: bool = false
var _resume_from_pivot: Vector3 = Vector3.ZERO
var _resume_from_yaw: float = 0.0
var _resume_from_cam_pos: Vector3 = Vector3.ZERO
var _resume_from_cam_basis: Basis = Basis.IDENTITY
var _resume_from_size: float = 0.0
# Decays 1→0 after the player bonks their head on the ceiling; drives the
# localized glass ping on the floor directly above them, placed at _bonk_pos.
var _ceiling_pulse: float = 0.0
var _bonk_pos: Vector3 = Vector3.ZERO
# Same idea for walls: a feathered glow flashes on the wall surface where the
# player bumps it (the invisible seal you hit jumping at the perimeter).
var _wall_pulse: float = 0.0
var _wall_bump_pos: Vector3 = Vector3.ZERO
var _wall_bump_normal: Vector3 = Vector3.FORWARD
var _wall_glow: MeshInstance3D
var _wall_glow_mat: ShaderMaterial
# Radial feather, like the ceiling ping — a soft halo on the wall, zero by the edge.
const _WALL_BUMP_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec3 glow_color : source_color = vec3(0.80, 0.86, 0.92);
uniform float intensity = 0.0;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = exp(-d * d * 3.5);
	a *= 1.0 - smoothstep(0.7, 1.0, d);
	ALBEDO = glow_color;
	EMISSION = glow_color * mix(0.4, 2.0, clamp(intensity, 0.0, 1.0));
	ALPHA = clamp(a, 0.0, 1.0) * clamp(intensity, 0.0, 1.0);
}
"""
# Half a story — how far below a floor's surface still reveals it (set in _ready).
var _reveal_margin: float = 3.0
# Cache key for the extension-grid fade so it only recomputes when the current
# floor (or world mode) changes, not every frame.
var _grid_key: int = -999


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
		var base_y: float = float(int(f.level) - int(_c.GROUND_LEVEL)) * story
		node.position.y = base_y          # geometry (built local) rides up with the node
		# Regular floors build their slab as a StaticBody3D named "SlabBody"
		# (FloorChrome.build_slab). We toggle its collision per current floor so
		# a jump passes UP through the ceiling and falls back to the same floor
		# (never lands above). The Canopy's slab is "TiledSlabBody" and is NOT
		# found here, so its collision is left permanently on — the one glass
		# ceiling you can bonk (3 → 4).
		var slab: StaticBody3D = _find_slab_body(node)
		var ext_grid: Array = []
		_collect_ext_grid(node, ext_grid)
		_floors.append({"node": node, "level": int(f.level), "name": String(f.name), "base_y": base_y, "slab": slab, "ext_grid": ext_grid})
	_top_level = int(_floors[_floors.size() - 1].level) if not _floors.is_empty() else 0
	# The tower owns the player spawn (derived from the floor heights), not the
	# .tscn — keeps it correct if the story height changes. Boot picks the start
	# STATE within this one scene (decision D-002): the real opening drops onto
	# the exterior empty lot; the dev fallback boots straight to the Garden.
	if _player and not _floors.is_empty():
		var gd: Node = get_node_or_null("/root/GameDirector")
		# EmptyLot is retired: the survey, the build, and the walk all happen on the
		# one persistent SiteGround at x=0, so nothing teleports or swaps the ground.
		# Keep the legacy node hidden if it's still wired into the scene.
		if _empty_lot:
			_empty_lot.visible = false
		var to_exterior: bool = bool(_c.BOOT_TO_EXTERIOR) and gd != null and int(gd.current_phase) == 0 and _site_ground != null
		if to_exterior:
			enter_exterior()
		else:
			_spawn_in_garden()
	_update(true)


# Today's Garden spawn (derived from the floor heights). Shared by the dev boot
# and the exterior->tower handoff so both land in the exact same spot.
func _spawn_in_garden() -> void:
	var spawn_y: float = _base_y_for_level(_SPAWN_LEVEL) + float(_c.FLOOR_3D_TOP_Y)
	_player.global_position = Vector3(0.0, spawn_y, -6.0)
	if _player.has_method("set_spawn_here"):
		_player.set_spawn_here()


# Garden arrival gate. The FIRST time the player enters the Garden (and the
# cinematic is enabled) it plays the scripted walk-in; every later entry is the
# plain spawn. Called from both enter_tower() and _enter_building() in place of the
# bare _spawn_in_garden().
func _arrive_in_garden() -> void:
	if bool(_c.ARRIVAL_CINE_ENABLED) and not _arrival_played:
		_begin_arrival_cinematic()
	else:
		_spawn_in_garden()


# Beat 0-1 entry: place the player just inside the south doorway, snap the camera to
# the behind-the-back framing, flip on the cinematic and kick off Beat 1 (the walk).
func _begin_arrival_cinematic() -> void:
	_arrival_played = true
	_arrival_cine = true
	_arrival_beat = 1
	_arrival_t = 0.0
	_arrival_walk_started = false
	_emerge_started = false
	_emerge_rollout_started = false
	_convo_opened = false
	_convo_yaw = 0.0
	_resume_started = false
	_resume_t = 0.0
	_gs.set("arrival_cinematic", true)
	var spawn_y: float = _base_y_for_level(_SPAWN_LEVEL) + float(_c.FLOOR_3D_TOP_Y)
	_player.global_position = Vector3(0.0, spawn_y, float(_c.ARRIVAL_CINE_DOOR_Z))
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO
	if _player.has_method("set_spawn_here"):
		_player.set_spawn_here()
	# Seed the persistent _cam_* members to the OTS STARTING pose (what the old
	# _apply_arrival_camera(1.0) produced: lower_t=1 → higher/farther back+lift, half
	# shoulder, OTS size, look-at ahead). Beat 1 then eases these toward the settled OTS
	# targets, so the cinematic opens from a stable pose with no pop from a stale value.
	_cam_init = true
	_cam_focus = _player.global_position
	_cam_yaw = 0.0
	_cam_back = float(_c.ARRIVAL_CINE_OTS_BACK) * 1.6
	_cam_lift = float(_c.ARRIVAL_CINE_OTS_LIFT) * 1.8
	_cam_shoulder = float(_c.ARRIVAL_CINE_OTS_SHOULDER) * 0.5
	_cam_size = float(_c.ARRIVAL_CINE_OTS_SIZE)
	_cam_lookahead = float(_c.ARRIVAL_CINE_OTS_LOOK_AHEAD)
	_cam_looklift = float(_c.ARRIVAL_CINE_OTS_LOOK_LIFT)
	# Targets start equal to the seed so the first frames hold the opening pose.
	_cam_focus_tgt = _cam_focus
	_cam_yaw_tgt = _cam_yaw
	_cam_back_tgt = _cam_back
	_cam_lift_tgt = _cam_lift
	_cam_shoulder_tgt = _cam_shoulder
	_cam_size_tgt = _cam_size
	_cam_lookahead_tgt = _cam_lookahead
	_cam_looklift_tgt = _cam_looklift
	# Snap the pivot + apply the seeded pose immediately (no jump-in from wherever the
	# iso pivot last was). _drive_arrival_camera with delta=0 just applies the seed.
	if _pivot:
		_pivot.global_position = _cam_focus
	_drive_arrival_camera(0.0)
	_hud_level = -1   # refresh the floor header
	_update(true)


# The builder's spot on the site: stood back beyond the -Z doorway at grade,
# facing the build area. Shared by the empty-lot survey, the hire, and the
# construction stand-back so none of those beats teleport the player — it stays
# the same patch of ground the whole time (the continuity anchor).
func _site_stand_position() -> Vector3:
	var half: float = float(_c.FLOOR_3D_SIZE) * 0.5
	return Vector3(0.0, float(_c.FLOOR_3D_TOP_Y), -(half + float(_c.CONSTRUCT_VIEW_BACK)))


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
	_arrive_in_garden()
	_hud_level = -1   # force the HUD to re-push the floor header
	_update(true)


# Enter (or return to) the exterior empty lot: spawn the player on the lot and
# flip on exterior mode. Used by the boot branch and by the debug phase walk
# when it wraps back to EMPTY_LOT.
func enter_exterior() -> void:
	_exterior = true
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO
	# Survey the actual build site (x=0) — the ground you stand on now is the
	# ground the tower rises on. Same spot the hire/construction uses, so advancing
	# the arc never jumps you to a different place.
	_player.global_position = _site_stand_position()
	if _player.has_method("set_facing_yaw"):
		_player.call("set_facing_yaw", 0.0)   # face +Z, across the lot
	if _player.has_method("set_spawn_here"):
		_player.set_spawn_here()
	if _site_ground:
		_site_ground.visible = true
		if _site_ground.has_method("set_paths_visible"):
			_site_ground.set_paths_visible(false)   # no doorway paths until the tower exists
	if _empty_lot:
		_empty_lot.visible = false
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
	if _site_ground:
		_site_ground.visible = true       # the one persistent ground — survey the real site
	if _empty_lot:
		_empty_lot.visible = false
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


# Enter construction: the builder stands back on the site at grade and watches
# the tower rise floor-by-floor (the build action), then walks in. The camera is
# controller-owned (iso_camera bows out); the builder is frozen until top-out.
func enter_construction() -> void:
	_constructing = true
	_exterior_walk = false
	_exterior = false
	_gs.set("constructing", true)             # freezes the builder; iso_camera bows out
	_gs.set("exterior_walk", false)
	_gs.built_level = 0                        # the basement/foundation (below grade) is the ground to build on
	if _empty_lot:
		_empty_lot.visible = false
	if _site_ground:
		_site_ground.visible = true           # the builder stands on the site
		if _site_ground.has_method("set_paths_visible"):
			_site_ground.set_paths_visible(true)
	if _player:
		_player.visible = true                # the builder is present, watching it go up
		if _player is CharacterBody3D:
			(_player as CharacterBody3D).velocity = Vector3.ZERO
		# The exact spot they surveyed from — no teleport into the build (continuity).
		_player.global_position = _site_stand_position()
		if _player.has_method("set_spawn_here"):
			_player.set_spawn_here()
		if _player.has_method("set_facing_yaw"):
			_player.call("set_facing_yaw", 0.0)   # face +Z, toward the rising tower
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


# Grounded exterior framing: pivot on the tower centre, lifted toward the middle
# of the VISIBLE (above-grade) stack and widened as it grows, so the builder at
# the base and the rising floors both stay in frame.
func _frame_construction(snap: bool) -> void:
	if _pivot == null:
		return
	# Visible stack runs from grade (the Garden, GROUND_LEVEL) up to the built top.
	var top_built: int = maxi(int(_gs.built_level), int(_c.GROUND_LEVEL))
	var top_y: float = _base_y_for_level(top_built)        # world y of the highest built floor
	var center_y: float = top_y * 0.5 + float(_c.CONSTRUCT_CAM_CENTER_LIFT)
	var target := Vector3(0.0, center_y, 0.0)
	_pivot.global_position = target if snap else _pivot.global_position.lerp(target, 0.10)
	if _camera:
		var raised: int = maxi(int(_gs.built_level) - int(_c.GROUND_LEVEL) + 1, 1)
		var base_size: float = float(_c.CONSTRUCT_CAM_SIZE_MIN) + float(raised) * float(_c.CONSTRUCT_CAM_SIZE_PER_FLOOR)
		var size: float = _aspect_fit(base_size)
		_camera.size = size if snap else lerpf(_camera.size, size, 0.10)


# Grow an orthographic size so a window narrower than the design aspect never
# clips the framed subject horizontally (KEEP_HEIGHT ortho frames vertically, so
# a tall/narrow window otherwise crops the sides). Recomputed live → resize-safe.
func _aspect_fit(base_size: float) -> float:
	var vp := get_viewport()
	if vp == null:
		return base_size
	var sz: Vector2 = vp.get_visible_rect().size
	if sz.y <= 0.0:
		return base_size
	var aspect: float = sz.x / sz.y
	var design: float = float(_c.CONSTRUCT_DESIGN_ASPECT)
	if aspect > 0.0 and aspect < design:
		return base_size * (design / aspect)
	return base_size


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
	var base_y: float = _base_y_for_level(lvl)
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
	_gs.set("exterior_walk", true)            # camera owned by the controller for the whole walk
	_gs.set("constructing", true)             # hold the player for the hand-off ease only
	_gs.built_level = _top_level
	if _player:
		_player.visible = true                # already standing on the site — keep them put, just release
		if _player is CharacterBody3D:
			(_player as CharacterBody3D).velocity = Vector3.ZERO
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
			slab.collision_layer = 0   # the player walks on the site ground (y=0); the Garden is at grade, basement below
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
	_current_level = -1                       # daylight preset; the controller drives the camera
	if _hud and _hud.has_method("set_explore") and _hud_level != -6:
		_hud_level = -6
		_hud.set_explore()
	_drive_environment(snap)
	# Once the ease-down is done, crossing the footprint edge (only reachable
	# through a doorway gap) enters the building. Trigger right AT the edge so you
	# spawn inside the instant you cross the threshold — the site ground has a hole
	# over the footprint (so the basement isn't ceilinged), and any band between the
	# edge and the trigger would be floorless: stop there and you'd drop through.
	# Corners stay safe — outside a doorway at least one axis is still ≥ half.
	if _cam_tween_t >= 1.0 and _player:
		var half: float = float(_c.FLOOR_3D_SIZE) * 0.5
		var p: Vector3 = _player.global_position
		if absf(p.x) < half and absf(p.z) < half:
			_enter_building()


# Walk-in: enter the finished tower. Drop into the Garden, advance the arc to
# BUILD_INTERIORS, and resume normal interior play.
func _enter_building() -> void:
	_exterior_walk = false
	_gs.set("exterior_walk", false)
	_gs.set("constructing", false)
	_gs.built_level = _top_level
	# Keep the site ground: it's at grade with the Garden, so it reads straight out
	# through the doorways from inside (no void) and is the ground you walk back onto.
	if _site_ground:
		_site_ground.visible = true
		if _site_ground.has_method("set_paths_visible"):
			_site_ground.set_paths_visible(true)
	if _player:
		_player.visible = true
	var gd: Node = get_node_or_null("/root/GameDirector")
	if gd and gd.has_method("set_phase"):
		gd.set_phase(gd.Phase.BUILD_INTERIORS)
	_arrive_in_garden()
	_hud_level = -1                           # force the floor header to push (iso_camera resumes)
	_update(true)


# Walk back out: step off the Garden (grade) onto the site. The mirror of
# _enter_building — re-enter the exterior walk (whole tower visible, grounded
# follow camera easing from wherever the iso camera was). The player keeps
# control the whole time; only the camera eases. Makes the doorway two-way so the
# building is a place you enter and leave, not a one-way trap.
func _exit_building() -> void:
	_exterior_walk = true
	_gs.set("exterior_walk", true)            # iso_camera bows out; the controller follows
	_gs.set("constructing", false)            # the player is never frozen on the way out
	_gs.built_level = _top_level
	if _site_ground:
		_site_ground.visible = true
		if _site_ground.has_method("set_paths_visible"):
			_site_ground.set_paths_visible(true)
	if _player and _player.has_method("set_spawn_here"):
		_player.set_spawn_here()
	_cam_from_pos = _pivot.global_position if _pivot else Vector3.ZERO
	_cam_from_size = _camera.size if _camera else 14.0
	_cam_tween_t = 0.0
	_hud_level = -5                           # force the explore header
	_update(true)


# Arrival cinematic driver (Beats 1-3). Beat 1: scripted walk in from the doorway to
# the mark while the camera lowers in behind the player. Beat 2: a short stop-hold.
# Beat 3: fire Cody's arrival, then orbit the camera around the player; on completion
# end the cinematic so iso_camera resumes.
func _update_arrival_cinematic(delta: float) -> void:
	_arrival_t += delta
	if _arrival_beat == 1:
		# Kick off the scripted walk once (target = the mark at the same floor height).
		if not _arrival_walk_started:
			_arrival_walk_started = true
			if _player and _player.has_method("begin_scripted_walk"):
				var spawn_y: float = _base_y_for_level(_SPAWN_LEVEL) + float(_c.FLOOR_3D_TOP_Y)
				var mark := Vector3(0.0, spawn_y, float(_c.ARRIVAL_CINE_MARK_Z))
				_player.call("begin_scripted_walk", mark, float(_c.ARRIVAL_CINE_WALK_SPEED))
		# OTS walk-in TARGET: settled over-the-shoulder framing (back/lift/shoulder/size
		# at their tight values, look-at ahead + up). The _cam_* members were seeded to
		# the higher/farther opening pose, so they EASE down into this over Beat 1 — the
		# old per-frame lower_t lerp becomes the continuous member ease, no extra logic.
		_set_ots_walk_targets()
		_drive_arrival_camera(delta)
		if _player and _player.has_method("is_scripted_walk_done") and _player.call("is_scripted_walk_done"):
			_arrival_beat = 2
			_arrival_t = 0.0
	elif _arrival_beat == 2:
		# Hold at the mark — same settled OTS targets; the members continue easing in.
		_set_ots_walk_targets()
		_drive_arrival_camera(delta)
		if _arrival_t >= float(_c.ARRIVAL_CINE_STOP_HOLD):
			_arrival_beat = 3
			_arrival_t = 0.0
	elif _arrival_beat == 3:
		# Orbit the camera (eased accel/decel) while Cody EMERGES from the elevator
		# (car rises from the basement, doors open, Cody rolls out). The orbit +
		# emergence run concurrently; Beat 3 ends only once BOTH finish so Cody always
		# settles first. JOB 1: the camera focus eases off the player toward the
		# player↔elevator-center midpoint during the emergence so the car/Cody roll-out
		# is HERO-framed instead of shoved to the frame edge — and the ortho size widens
		# so both the player and the emerging car fit. Only TARGETS are set here; the
		# shoulder target goes to 0 and the look-at bias targets go to the orbit values,
		# so the _cam_* ease carries the lateral offset + look-direction out smoothly
		# (no lateral pop / look-direction snap at the Beat 2→3 boundary).
		_update_emergence(delta)
		var orbit_p: float = clampf(_arrival_t / float(_c.ARRIVAL_CINE_ORBIT_DUR), 0.0, 1.0)
		var orbit_deg: float = smoothstep(0.0, 1.0, orbit_p) * float(_c.ARRIVAL_CINE_ORBIT_DEG) * float(_c.ARRIVAL_CINE_ORBIT_DIR)
		# Bias the look-at toward the elevator center (floor center == world (0,y,0)).
		var pp: Vector3 = _player.global_position
		var elev_center := Vector3(0.0, pp.y, 0.0)
		var bias_full: Vector3 = pp.lerp(elev_center, float(_c.ARRIVAL_CINE_EMERGE_FOCUS_BIAS))
		# Ease the bias in over EMERGE_FOCUS_DUR so the focus glides (no jump on entry).
		var fe: float = smoothstep(0.0, 1.0, clampf(_arrival_t / float(_c.ARRIVAL_CINE_EMERGE_FOCUS_DUR), 0.0, 1.0))
		# ASK 2: pull the orbit in CLOSE — ease toward the tight pair size so the car/
		# Cody (and the nearby player) read big as they emerge, not survey-distant.
		var size_target: float = lerpf(float(_c.ARRIVAL_CINE_OTS_SIZE), float(_c.ARRIVAL_CINE_PAIR_SIZE), fe)
		# Orbit TARGETS: yaw sweeps with the orbit, focus biases toward the elevator,
		# shoulder→0, look-at dead-centre (lookahead 0, looklift the orbit value). The
		# camera ortho size widens to fit the pair.
		_cam_focus_tgt = pp.lerp(bias_full, fe)
		_cam_yaw_tgt = deg_to_rad(orbit_deg)
		_cam_back_tgt = float(_c.ARRIVAL_CINE_CAM_BACK)
		_cam_lift_tgt = float(_c.ARRIVAL_CINE_CAM_LIFT)
		_cam_shoulder_tgt = 0.0
		_cam_size_tgt = size_target
		_cam_lookahead_tgt = 0.0
		_cam_looklift_tgt = 0.8
		_drive_arrival_camera(delta)
		var robot: Node = get_node_or_null("Floors/Garden/IsoRobot")
		var emerge_done: bool = robot == null or not robot.has_method("is_emergence_done") or bool(robot.call("is_emergence_done"))
		if orbit_p >= 1.0 and emerge_done:
			# ASK 3: the intro animation is complete — go STRAIGHT into the conversation.
			# Auto-open Cody's dialogue (once) and hand to Beat 5, a slow close orbit
			# around the pair that runs for as long as the player stays in the chat.
			if robot and not _convo_opened and robot.has_method("open_dialogue"):
				_convo_opened = true
				robot.call("open_dialogue")
			_convo_yaw = 0.0   # time accumulator for the conversation-orbit ping-pong (starts at the settle yaw)
			_arrival_beat = 5
			_arrival_t = 0.0
	elif _arrival_beat == 5:
		_update_conversation_orbit(delta)
	elif _arrival_beat == 4:
		_update_resume_ease(delta)


# Beat 5 (ASK 3) — conversation orbit: the dialogue auto-opened at the end of Beat 3;
# keep arrival_cinematic TRUE (player frozen, iso_camera bowed out, the robot's own
# _input still drives the choices) and slowly circle the player↔Cody PAIR at the close
# pair size for as long as the player stays in the chat. When they end it
# (GameState.dialogue_open goes false), hand to Beat 4 (the existing resume ease).
func _update_conversation_orbit(delta: float) -> void:
	# Slow leisurely orbit around the pair midpoint. Bounded to the SOUTH hemisphere
	# (where both characters sit IN FRONT of the elevator core) as a gentle ping-pong,
	# so a long chat keeps circling the two of them without the core ever swinging
	# between camera and the pair. _convo_yaw accumulates time; yaw is a sine of it.
	_convo_yaw += delta
	# Settle yaw the emergence landed on (where the pair is well framed in front of the
	# core); swing a bounded arc OFF it toward the front (0°, more south = pair stays in
	# front of the core), as a smooth (1−cos) ping-pong so a long chat keeps circling.
	var settle: float = float(_c.ARRIVAL_CINE_ORBIT_DEG) * float(_c.ARRIVAL_CINE_ORBIT_DIR)
	var amp: float = float(_c.ARRIVAL_CINE_CONVO_ORBIT_AMP) * (-float(_c.ARRIVAL_CINE_ORBIT_DIR))
	# One-time seed off the settle yaw so the FIRST frame is already a clean two-shot
	# (at the bare settle yaw Cody sits directly behind the player). Sign follows the
	# orbit direction. The (1−cos) term is 0 at phase 0, so the orbit still starts with
	# zero velocity — the seed just shifts the starting angle (no jump, smooth start).
	var seed: float = float(_c.ARRIVAL_CINE_CONVO_SEED_DEG) * (-float(_c.ARRIVAL_CINE_ORBIT_DIR))
	var phase: float = _convo_yaw * deg_to_rad(float(_c.ARRIVAL_CINE_CONVO_ORBIT_RATE))
	var yaw: float = settle + seed + amp * (1.0 - cos(phase)) * 0.5
	var mid: Vector3 = _pair_midpoint()
	# Conversation TARGETS. The seed (+30°) is now applied to the yaw TARGET, not the
	# live yaw — Beat 3 ended on _cam_yaw≈settle, and the eased member GLIDES into
	# (settle + seed) over a few frames instead of snapping by 30°. Focus eases to the
	# pair midpoint; the close pair size + dead-centre look-at give the two-shot.
	_cam_focus_tgt = mid
	_cam_yaw_tgt = deg_to_rad(yaw)
	_cam_back_tgt = float(_c.ARRIVAL_CINE_CAM_BACK)
	_cam_lift_tgt = float(_c.ARRIVAL_CINE_CAM_LIFT)
	_cam_shoulder_tgt = 0.0
	_cam_size_tgt = float(_c.ARRIVAL_CINE_PAIR_SIZE)
	_cam_lookahead_tgt = 0.0
	_cam_looklift_tgt = 0.8
	_drive_arrival_camera(delta)
	# Exit once the conversation that auto-opened has been closed by the player.
	if _convo_opened and not bool(_gs.get("dialogue_open")):
		_arrival_beat = 4
		_arrival_t = 0.0
		_resume_started = false


# World focus for the conversation orbit — the player↔Cody midpoint, lifted to torso
# height so both bodies sit in the upper frame (clear of the bottom-left dialogue
# panel). Falls back to the player if Cody isn't reachable.
func _pair_midpoint() -> Vector3:
	var pp: Vector3 = _player.global_position
	var robot: Node3D = get_node_or_null("Floors/Garden/IsoRobot")
	if robot == null:
		return pp + Vector3(0.0, float(_c.ARRIVAL_CINE_PAIR_LIFT), 0.0)
	var cp: Vector3 = robot.global_position
	var mid := Vector3((pp.x + cp.x) * 0.5, pp.y, (pp.z + cp.z) * 0.5)
	return mid + Vector3(0.0, float(_c.ARRIVAL_CINE_PAIR_LIFT), 0.0)


# Beat-3 emergence: puppet the elevator car + Cody up the shaft, then roll Cody out.
# Sub-phased off the beat timer _arrival_t (reset to 0 on Beat-3 entry), running
# CONCURRENTLY with the orbit sweep. Lead → rise → doors → roll-out.
func _update_emergence(_delta: float) -> void:
	var elevator: Node = get_node_or_null("ElevatorPlatform")
	var robot: Node = get_node_or_null("Floors/Garden/IsoRobot")
	if elevator == null:
		return
	# One-shot entry: car to the basement (doors shut), Cody boards on top of it.
	if not _emerge_started:
		_emerge_started = true
		_emerge_basement_y = float(elevator.call("cinematic_floor_y", 0))
		_emerge_garden_y = float(elevator.call("cinematic_floor_y", 1))
		elevator.call("cinematic_begin")
		if robot and robot.has_method("cinematic_board"):
			robot.call("cinematic_board", _emerge_basement_y)

	var lead: float = float(_c.ARRIVAL_CINE_EMERGE_LEAD)
	var rise_dur: float = float(_c.ARRIVAL_CINE_CAR_RISE_DUR)
	var door_dur: float = float(_c.ARRIVAL_CINE_DOOR_DUR)
	var t: float = _arrival_t

	if t < lead:
		# Lead: orbit begins; car waits at the basement, doors shut.
		return
	var rt: float = t - lead
	if rt < rise_dur:
		# Rise: lerp the car basement→garden; Cody rides up at the shaft center.
		var p: float = clampf(rt / rise_dur, 0.0, 1.0)
		var car_y: float = lerpf(_emerge_basement_y, _emerge_garden_y, smoothstep(0.0, 1.0, p))
		elevator.call("cinematic_set_car_y", car_y)
		if robot and robot.has_method("cinematic_set_ride_y"):
			robot.call("cinematic_set_ride_y", car_y)
		return
	# Car has arrived at the Garden — pin it there.
	elevator.call("cinematic_set_car_y", _emerge_garden_y)
	var dt: float = rt - rise_dur
	if dt < door_dur:
		# Doors: lower them open; keep Cody riding at the (now stationary) car top.
		elevator.call("cinematic_set_doors", clampf(dt / door_dur, 0.0, 1.0))
		if robot and robot.has_method("cinematic_set_ride_y"):
			robot.call("cinematic_set_ride_y", _emerge_garden_y)
		return
	# Doors fully open — roll Cody out (once). He owns his tween from here.
	elevator.call("cinematic_set_doors", 1.0)
	if not _emerge_rollout_started:
		_emerge_rollout_started = true
		if robot and robot.has_method("cinematic_roll_out"):
			robot.call("cinematic_roll_out")


# Beat 4 (JOB 2) — resume ease: the conductor still owns the camera here. Capture
# the cinematic pose once, derive iso's RESTING pose (the exact pivot pose +
# Camera3D local transform iso_camera will adopt the frame after we clear the
# flag), then smoothstep the live camera from cinematic→iso over RESUME_DUR. Only
# when the ease COMPLETES do we clear arrival_cinematic, so iso_camera picks up
# from the identical transform — no jump-cut. The player stays frozen until then.
func _update_resume_ease(delta: float) -> void:
	if _pivot == null or _camera == null:
		return
	if not _resume_started:
		_resume_started = true
		_resume_t = 0.0
		_resume_from_pivot = _pivot.global_position
		_resume_from_yaw = _pivot.rotation.y
		_resume_from_cam_pos = _camera.position
		_resume_from_cam_basis = _camera.transform.basis
		_resume_from_size = _camera.size

	# --- iso RESTING-pose target (mirrors iso_camera._ready/_apply_orbit + the
	#     tower's per-floor pivot.y) so the hand-off lands on the EXACT pose
	#     iso_camera will hold (zero free-look offset) the next frame. ---
	# pivot.global_position: iso anchors XZ at the player and Y at the floor chest.
	var pp: Vector3 = _player.global_position
	var iso_pivot_y: float = _base_y_for_level(_current_level) + _PIVOT_CHEST
	var iso_pivot := Vector3(pp.x, iso_pivot_y, pp.z)
	# pivot yaw: iso's initial heading.
	var iso_yaw: float = deg_to_rad(float(_c.CAMERA_YAW_DEG_INITIAL))
	# Camera3D local transform: iso places it at (0, d·sin|θ|, d·cos|θ|) with a -θ X
	# tilt (replicating _ready / _apply_orbit at zero free-look offset).
	var tilt_rad: float = deg_to_rad(abs(float(_c.CAMERA_TILT_DEG)))
	var d: float = float(_c.CAMERA_DISTANCE)
	var iso_cam_pos := Vector3(0.0, d * sin(tilt_rad), d * cos(tilt_rad))
	var iso_cam_basis := Basis.from_euler(Vector3(deg_to_rad(float(_c.CAMERA_TILT_DEG)), 0.0, 0.0))
	var iso_size: float = float(_c.CAMERA_ORTHO_SIZE_DEFAULT)

	_resume_t += delta
	var e: float = smoothstep(0.0, 1.0, clampf(_resume_t / float(_c.ARRIVAL_CINE_RESUME_DUR), 0.0, 1.0))

	# Ease the live camera cinematic→iso. Pivot global pos + yaw, Camera3D local
	# position + orientation (slerp the basis), and ortho size.
	_pivot.global_position = _resume_from_pivot.lerp(iso_pivot, e)
	var yaw_diff: float = wrapf(iso_yaw - _resume_from_yaw + PI, 0.0, TAU) - PI
	_pivot.rotation = Vector3(0.0, _resume_from_yaw + yaw_diff * e, 0.0)
	_camera.position = _resume_from_cam_pos.lerp(iso_cam_pos, e)
	_camera.transform.basis = _resume_from_cam_basis.slerp(iso_cam_basis, e)
	_camera.size = lerpf(_resume_from_size, iso_size, e)
	_gs.camera.ortho_size = _camera.size

	if _resume_t >= float(_c.ARRIVAL_CINE_RESUME_DUR):
		# Snap to the exact iso pose (kill any residual ease error), then release.
		_pivot.global_position = iso_pivot
		_pivot.rotation = Vector3(0.0, iso_yaw, 0.0)
		_camera.position = iso_cam_pos
		_camera.transform.basis = iso_cam_basis
		_camera.size = iso_size
		_gs.camera.ortho_size = iso_size
		_arrival_cine = false
		_arrival_beat = 0
		_gs.set("arrival_cinematic", false)
		var elevator: Node = get_node_or_null("ElevatorPlatform")
		if elevator and elevator.has_method("cinematic_end"):
			elevator.call("cinematic_end")
		if _player and _player.has_method("clear_scripted_walk"):
			_player.call("clear_scripted_walk")
		_hud_level = -1
		_update(true)   # clears arrival_cinematic for iso_camera; pivot resumes seamlessly


# Per-beat TARGET helper — the settled over-the-shoulder WALK-IN framing (Beats 1/2).
# Sets ONLY the _cam_*_tgt members; the persistent _cam_* members ease toward these
# in _drive_arrival_camera. The members were seeded to the higher/farther OPENING pose
# at cinematic start, so easing toward these tight values IS the old camera-lower-in
# (the per-frame lower_t lerp is now the continuous member ease — same motion, no pop).
func _set_ots_walk_targets() -> void:
	_cam_focus_tgt = _player.global_position
	_cam_yaw_tgt = 0.0
	_cam_back_tgt = float(_c.ARRIVAL_CINE_OTS_BACK)
	_cam_lift_tgt = float(_c.ARRIVAL_CINE_OTS_LIFT)
	_cam_shoulder_tgt = float(_c.ARRIVAL_CINE_OTS_SHOULDER)
	_cam_size_tgt = float(_c.ARRIVAL_CINE_OTS_SIZE)
	_cam_lookahead_tgt = float(_c.ARRIVAL_CINE_OTS_LOOK_AHEAD)
	_cam_looklift_tgt = float(_c.ARRIVAL_CINE_OTS_LOOK_LIFT)


# Single TARGET+CONTINUOUS-EASE camera driver. Eases each persistent _cam_* member
# toward its per-beat TARGET (set by the active beat) with frame-rate-aware exponential
# smoothing (f = 1 − exp(−rate·delta)), THEN applies the pose ONCE: pivot at _cam_focus,
# pivot yaw = _cam_yaw, the Camera3D at pivot-local (_cam_shoulder, _cam_lift, −_cam_back)
# looking at a point derived from _cam_lookahead/_cam_looklift, ortho size = _cam_size.
# Because every parameter eases continuously, every beat boundary GLIDES: the shoulder
# eases to 0 entering the orbit (no lateral pop), the OTS look-at bias eases out (no
# look-direction snap), and the convo seed becomes a smooth yaw glide (no 30° jump).
# delta=0 just applies the current members (used to render the seeded opening pose).
# iso_camera bows out while arrival_cinematic is set, so this owns BOTH the pivot and
# the Camera3D's local transform each frame.
func _drive_arrival_camera(delta: float) -> void:
	if _pivot == null or _player == null:
		return
	if not _cam_init:
		return
	var f: float = 1.0 - exp(-float(_c.ARRIVAL_CINE_CAM_EASE_RATE) * delta) if delta > 0.0 else 0.0
	# Ease each member toward its target. Yaw is eased the SHORT way (wrap-aware) so a
	# target across the ±PI seam never sends the camera the long way around.
	_cam_focus = _cam_focus.lerp(_cam_focus_tgt, f)
	_cam_size = lerpf(_cam_size, _cam_size_tgt, f)
	_cam_back = lerpf(_cam_back, _cam_back_tgt, f)
	_cam_lift = lerpf(_cam_lift, _cam_lift_tgt, f)
	_cam_shoulder = lerpf(_cam_shoulder, _cam_shoulder_tgt, f)
	_cam_lookahead = lerpf(_cam_lookahead, _cam_lookahead_tgt, f)
	_cam_looklift = lerpf(_cam_looklift, _cam_looklift_tgt, f)
	var yaw_diff: float = wrapf(_cam_yaw_tgt - _cam_yaw + PI, 0.0, TAU) - PI
	_cam_yaw += yaw_diff * f
	# Apply the pose ONCE from the eased members.
	_pivot.global_position = _cam_focus
	_pivot.rotation = Vector3(0.0, _cam_yaw, 0.0)
	if _camera:
		# Camera south (-Z) of and above the pivot, offset _cam_shoulder to one side; look
		# back at the focus from behind/above. He walks +Z (north), so south = behind.
		_camera.position = Vector3(_cam_shoulder, _cam_lift, -_cam_back)
		# Look-at: a touch toward the shoulder side + ahead (+Z) + up. With shoulder→0 and
		# lookahead→0 (the orbit/convo targets) this is the dead-centre clean-circle aim;
		# with the OTS values it's the over-the-shoulder, look-ahead framing — and because
		# both ease continuously the transition between them never snaps.
		var look_local := Vector3(_cam_shoulder * 0.45, _cam_looklift, _cam_lookahead)
		_camera.look_at(_pivot.global_transform * look_local, Vector3.UP)
		_camera.size = _cam_size
		_gs.camera.ortho_size = _camera.size


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
	# Exterior walk: the controller owns a wide, pulled-back follow so the whole tower
	# reads as the player circles it. The ease-down interpolates from the dollhouse
	# framing; afterward it tracks the player at a fixed lift + size.
	if _exterior_walk and _player:
		var target_pos := Vector3(_player.global_position.x, float(_c.EXTERIOR_WALK_CAM_LIFT), _player.global_position.z)
		var target_size := _aspect_fit(float(_c.EXTERIOR_WALK_CAM_SIZE))
		if _cam_tween_t < 1.0:
			_cam_tween_t = minf(_cam_tween_t + delta / float(_c.EXTERIOR_WALK_CAM_TWEEN_DUR), 1.0)
			var e: float = smoothstep(0.0, 1.0, _cam_tween_t)
			if _pivot:
				_pivot.global_position = _cam_from_pos.lerp(target_pos, e)
			if _camera:
				_camera.size = lerpf(_cam_from_size, target_size, e)
			if _cam_tween_t >= 1.0:
				_gs.set("constructing", false)   # unfreeze the player (camera stays controller-owned)
		else:
			if _pivot:
				_pivot.global_position = _pivot.global_position.lerp(target_pos, 0.12)
			if _camera:
				_camera.size = lerpf(_camera.size, target_size, 0.12)
	# Arrival cinematic: the controller drives the behind-the-back follow camera and
	# the scripted walk while iso_camera bows out (gated on arrival_cinematic).
	if _arrival_cine:
		_update_arrival_cinematic(delta)
	# Ceiling bonk → a localized glass glow at the hit point on the floor above.
	if _player and _player.has_method("is_on_ceiling") and _player.is_on_ceiling():
		_ceiling_pulse = 1.0
		_bonk_pos = _player.global_position
	else:
		_ceiling_pulse = maxf(_ceiling_pulse - delta * float(_c.FLOOR_4_CEILING_PULSE_DECAY), 0.0)
	# Wall bump: flash a glow ONLY when the player jumps ABOVE the visible wall and
	# shoves into the invisible seal trying to leave — not for ordinary wall
	# contact down at floor level. Gate on the player's height above their floor.
	var above_wall: bool = false
	if _player:
		var floor_surface: float = _base_y_for_level(_current_level) + float(_c.FLOOR_3D_TOP_Y)
		above_wall = (_player.global_position.y - floor_surface) >= float(_c.WALL_HEIGHT) - 1.8
	if above_wall and _player is CharacterBody3D and (_player as CharacterBody3D).is_on_wall():
		_wall_pulse = 1.0
		_wall_bump_pos = _player.global_position
		_wall_bump_normal = (_player as CharacterBody3D).get_wall_normal()
	else:
		_wall_pulse = maxf(_wall_pulse - delta * float(_c.FLOOR_4_CEILING_PULSE_DECAY), 0.0)
	_update(false)
	_update_extension_grids()
	_update_wall_bump()


func _update(snap: bool) -> void:
	if _player == null or _floors.is_empty():
		return
	# Plunging off the roof: show the whole tower + ground and chase the player down.
	if bool(_gs.get("roof_falling")):
		_update_roof_fall(snap)
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
	# (Cody's first-Garden greeting now belongs to the arrival cinematic, which calls
	# greet_on_entry() at its hand-off — see _update_arrival_cinematic Beat 2.)
	# Two-way threshold: on the Garden (grade), stepping back out through a doorway
	# returns you to the site on foot. Hysteresis (1.05× the footprint, wider than
	# _enter_building's 0.9× test) keeps the boundary from flickering.
	if not _exterior_walk and int(_gs.built_level) >= _top_level and _current_level == _SPAWN_LEVEL:
		var half_out: float = float(_c.FLOOR_3D_SIZE) * 0.5 * 1.05
		var pp: Vector3 = _player.global_position
		if absf(pp.x) > half_out or absf(pp.z) > half_out:
			_exit_building()
			return
	# FIX 2 — during the arrival cinematic the camera drops to a LOW over-the-shoulder
	# angle that can see past the Garden floor edge / down the shaft. The normal
	# at-or-below rule renders the basement (level 0) UNDER the Garden, so you'd see
	# THROUGH the ground into the basement. While the cinematic plays, gate interior
	# floor visibility to ONLY the current floor (hide everything strictly below) so the
	# shaft shows empty void below the Garden, never the basement. The elevator car is a
	# separate ElevatorPlatform node (not in this loop), so it still rises into view from
	# below — the intended effect. Normal play keeps the at-or-below rule unchanged.
	var cine_gate: bool = bool(_gs.get("arrival_cinematic"))
	for f in _floors:
		var node: Node3D = f.node
		# Construct-from-empty: a floor only exists once built. Unbuilt floors are
		# fully absent (invisible + no collision). With built_level=99 (default)
		# every floor is built, so this reduces to the original at_or_below rule.
		var built: bool = int(f.level) <= int(_gs.built_level)
		var at_or_below: bool = built and (int(f.level) <= _current_level)
		# During the cinematic: show ONLY the current floor (no basement showing through).
		if cine_gate:
			at_or_below = built and (int(f.level) == _current_level)
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
		if _tel:
			_tel.record("floor_reached", {"level": _current_level, "name": _name_for_level(_current_level)})
	# Camera pivot rises/lowers with the current floor — only in iso mode and
	# outside dialogue, where the camera owns the pivot pose itself. The arrival
	# cinematic owns the pivot directly (behind-the-back follow), so skip it then.
	if _pivot and String(_gs.get("camera_mode")) == "iso" and not bool(_gs.get("dialogue_open")) and not bool(_gs.get("looking_out")) and not _arrival_cine:
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
	# The site ground reads as the world's ground only at grade (the Garden); on
	# floors above/below it would float in the tight iso framing, so hide it there.
	# The exterior / construct / walk branches manage their own visibility.
	if _site_ground:
		_site_ground.visible = (_current_level == _SPAWN_LEVEL)
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
		1: return {"amb": Color(0.68, 0.68, 0.66), "energy": 0.92, "bg": Color(0.40, 0.50, 0.64), "sun": 1.00, "sky_exposure": 0.45}   # Garden interior identity at grade — blended toward open sky near the doorways (see _drive_environment)
		2: return {"amb": Color(0.78, 0.84, 0.72), "energy": 1.50, "bg": Color(0.08, 0.13, 0.10), "sun": 1.25, "sky_exposure": 0.40}   # Arboretum (ground)
		3: return {"amb": Color(0.82, 0.88, 0.78), "energy": 1.70, "bg": Color(0.10, 0.16, 0.13), "sun": 1.35, "sky_exposure": 0.60}   # Canopy (glassy upper)
		4: return {"amb": Color(0.74, 0.72, 0.70), "energy": 1.05, "bg": Color(0.12, 0.12, 0.14), "sun": 1.05, "sky_exposure": 0.50}   # Residential (windows)
		5: return {"amb": Color(0.84, 0.88, 0.96), "energy": 1.60, "bg": Color(0.46, 0.60, 0.78), "sun": 1.45, "sky_exposure": 1.0}    # Sky Lounge (floor-to-ceiling glass)
		# Roof / Vista (top): open to the sky — full day/night swing.
		_: return {"amb": Color(0.80, 0.86, 0.95), "energy": 1.95, "bg": Color(0.42, 0.55, 0.70), "sun": 1.55, "sky_exposure": 1.0}


# Linear interpolation between two environment presets (t: 0 = a, 1 = b). Used to
# fade a floor's interior identity toward the open-sky exterior by position.
func _blend_preset(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	return {
		"amb": (a.amb as Color).lerp(b.amb as Color, t),
		"energy": lerpf(float(a.energy), float(b.energy), t),
		"bg": (a.bg as Color).lerp(b.bg as Color, t),
		"sun": lerpf(float(a.sun), float(b.sun), t),
		"sky_exposure": lerpf(float(a.get("sky_exposure", 0.0)), float(b.get("sky_exposure", 0.0)), t),
	}


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
	# Natural daylight near the at-grade openings: on the ground floor, blend the
	# Garden's interior identity toward the open-sky exterior the closer the player
	# is to a perimeter doorway, so light floods in as you near the doors and fades
	# as you go deep inside — stepping in/out is a gradient, not a hard switch.
	if _current_level == _SPAWN_LEVEL and _player:
		var half: float = float(_c.FLOOR_3D_SIZE) * 0.5
		var pos: Vector3 = _player.global_position
		var edge_dist: float = maxf(absf(pos.x), absf(pos.z))   # Chebyshev: distance to the nearest wall plane
		var b: float = smoothstep(half * 0.5, half, edge_dist)  # 0 deep interior → 1 at the wall/threshold
		if b > 0.0:
			p = _blend_preset(p, _preset_for(-1), b)
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


# The player is plummeting down the outside of the tower after stepping off the
# roof: reveal the whole stack + the ground (so the fall reads against the
# building), light it as daylight exterior, and lock the camera to the falling
# body so it stays in frame all the way down.
func _update_roof_fall(snap: bool) -> void:
	for f in _floors:
		var node: Node3D = f.node
		var slab: StaticBody3D = f.get("slab")
		if slab:
			slab.collision_layer = 0
		if node.has_method("set_structure_visible"):
			node.set_structure_visible(true)
			node.set_slab_alpha(float(_c.FLOOR_4_SLAB_ON_ALPHA))
			if node.has_method("set_apertures_visible"):
				node.set_apertures_visible(true)
		else:
			node.visible = true
	if _site_ground:
		_site_ground.visible = true
		if _site_ground.has_method("set_paths_visible"):
			_site_ground.set_paths_visible(true)
	if _cityscape:
		_cityscape.visible = true
	_current_level = -1
	if _pivot:
		var ty: float = _player.global_position.y + _PIVOT_CHEST
		_pivot.position.y = ty if snap else lerpf(_pivot.position.y, ty, 0.5)
	_drive_environment(snap)
	_update_extension_grids()


# Positions + fades the wall-bump glow on the wall surface the player hit. The
# quad lies flat against the wall (oriented to its normal) and feathers out like
# the ceiling ping, so a bump reads as a soft impact rather than a hard line.
func _update_wall_bump() -> void:
	if _wall_pulse <= 0.01:
		if _wall_glow:
			_wall_glow.visible = false
		return
	if _wall_glow == null:
		_build_wall_glow()
	# Slide the player's position onto the wall plane, just off the surface.
	var n: Vector3 = _wall_bump_normal
	if n.length_squared() < 0.01:
		n = Vector3.FORWARD
	n = n.normalized()
	var surface: Vector3 = _wall_bump_pos - n * 0.06
	_wall_glow.global_position = surface
	# Orient the quad so it lies in the wall plane (its face along the normal).
	_wall_glow.look_at(surface + n, Vector3.UP)
	_wall_glow.visible = true
	_wall_glow_mat.set_shader_parameter("intensity", clampf(_wall_pulse, 0.0, 1.0))


func _build_wall_glow() -> void:
	_wall_glow = MeshInstance3D.new()
	_wall_glow.name = "WallBumpGlow"
	var r: float = float(_c.FLOOR_4_CEILING_PING_RADIUS)
	var quad := QuadMesh.new()
	quad.size = Vector2(r * 2.0, r * 2.0)
	_wall_glow.mesh = quad
	var sh := Shader.new()
	sh.code = _WALL_BUMP_SHADER
	_wall_glow_mat = ShaderMaterial.new()
	_wall_glow_mat.shader = sh
	var g: Color = _c.FLOOR_4_GLASS_COLOR
	_wall_glow_mat.set_shader_parameter("glow_color", Vector3(g.r, g.g, g.b))
	_wall_glow_mat.set_shader_parameter("intensity", 0.0)
	_wall_glow.material_override = _wall_glow_mat
	_wall_glow.visible = false
	add_child(_wall_glow)


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


# --- Dev chapter jump ----------------------------------------------------
# The chapter list for the dev overlay. A method (not a bare const) so the
# overlay can read it via the group — Object.get() can't fetch a `const`.
func chapter_list() -> Array:
	return CHAPTERS


# Cleanly exit ANY active world-presentation / scripted mode so a jump is safe
# from ANYWHERE (mid-cinematic, in dialogue, on the lot, mid-build). Clears every
# flag a mode sets — both the local member and its GameState mirror — so the jump
# target never inherits a half-state. Idempotent: safe to call when already idle.
func _teardown_transient_state() -> void:
	# Arrival cinematic + all its beat bookkeeping.
	_arrival_cine = false
	_gs.set("arrival_cinematic", false)
	_arrival_beat = 0
	_arrival_t = 0.0
	_arrival_walk_started = false
	_emerge_started = false
	_emerge_rollout_started = false
	_convo_opened = false
	_convo_yaw = 0.0
	_resume_started = false
	_resume_t = 0.0
	# Exterior / construction modes.
	_exterior = false
	_constructing = false
	_gs.set("constructing", false)
	_exterior_walk = false
	_gs.set("exterior_walk", false)
	_cam_tween_t = 1.0
	# Roof plunge.
	_gs.set("roof_falling", false)
	# Dialogue: drop the flag AND tell Cody to hide his panel (both sides).
	_gs.set("dialogue_open", false)
	var robot: Node = get_node_or_null("Floors/Garden/IsoRobot")
	if robot and robot.has_method("close_dialogue"):
		robot.close_dialogue()
	# Scripted walk + any carried momentum on the player.
	if _player:
		if _player.has_method("clear_scripted_walk"):
			_player.call("clear_scripted_walk")
		if _player is CharacterBody3D:
			(_player as CharacterBody3D).velocity = Vector3.ZERO
		_player.visible = true


# Jump straight to a narrative beat / floor from any state. Tears down whatever's
# active, then sets up the target (GameDirector phase + world mode + spawn), and
# forces a HUD/camera refresh. Defensive throughout — a jump must never leave the
# game half-in-two-modes. `id` is one of CHAPTERS[*].id.
func jump_to_chapter(id: String) -> void:
	if _player == null or _floors.is_empty():
		return
	_teardown_transient_state()
	var gd: Node = get_node_or_null("/root/GameDirector")
	match id:
		"empty_lot":
			if gd and gd.has_method("set_phase"):
				gd.set_phase(gd.Phase.EMPTY_LOT)
			enter_exterior()
		"hire":
			if gd and gd.has_method("set_phase"):
				gd.set_phase(gd.Phase.HIRE_PARTNER)
			enter_exterior()   # the hire happens on the lot
		"build":
			if gd and gd.has_method("set_phase"):
				gd.set_phase(gd.Phase.BUILD_STRUCTURE)
			enter_construction()   # the dollhouse "raise the tower" view
		"garden_intro":
			# Replay the intro cinematic from the top.
			_arrival_played = false
			_gs.built_level = _top_level
			if gd and gd.has_method("set_phase"):
				gd.set_phase(gd.Phase.BUILD_INTERIORS)
			_begin_arrival_cinematic()
		"garden":
			# Normal Garden play — skip the cinematic.
			_arrival_played = true
			_gs.built_level = _top_level
			if gd and gd.has_method("set_phase"):
				gd.set_phase(gd.Phase.BUILD_INTERIORS)
			_spawn_in_garden()
		_:
			# Floor teleports (utility / arboretum / canopy / residential /
			# sky_lounge), plus roof (which resolves to _top_level).
			var level: int = int(_CHAPTER_FLOOR.get(id, -999))
			if id == "roof":
				level = _top_level
			if level == -999:
				push_warning("jump_to_chapter: unknown id '%s'" % id)
				return
			_arrival_played = true
			_gs.built_level = _top_level
			if gd and gd.has_method("set_phase"):
				gd.set_phase(gd.Phase.BUILD_INTERIORS)
			_player.global_position = Vector3(0.0, _base_y_for_level(level) + float(_c.FLOOR_3D_TOP_Y) + 0.1, -6.0)
			if _player is CharacterBody3D:
				(_player as CharacterBody3D).velocity = Vector3.ZERO
			if _player.has_method("set_spawn_here"):
				_player.set_spawn_here()
			_current_level = level   # resolve immediately so camera + gating are right pre-grounding
	# Force a full HUD + camera + floor-visibility refresh after any jump.
	_hud_level = -1
	_grid_key = -999
	_pulse_level = 0
	_update(true)


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


# Gathers every extension-grid mesh (the blueprint lines + crossbars that radiate
# from the walls) under a floor node, so their opacity can be driven per floor.
func _collect_ext_grid(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("GridExt"):
			out.append(child)
		_collect_ext_grid(child, out)


# Fades each floor's extension grid by its distance from the current floor: the
# floor you're on is fully lit, fading sequentially to 10% by the 4th floor away
# (symmetric up and down), invisible beyond. Outside the tower (exterior / build /
# walk) every grid reads at full so the blueprint frames the whole site.
func _update_extension_grids() -> void:
	var interior: bool = not _exterior and not _exterior_walk and not _constructing
	var key: int = _current_level if interior else 9999
	if key == _grid_key:
		return
	_grid_key = key
	for f in _floors:
		var factor: float = 1.0
		if interior:
			var d: int = absi(int(f.level) - _current_level)
			factor = 0.0 if d > 4 else lerpf(1.0, 0.10, float(d) / 4.0)
		var transp: float = 1.0 - factor
		for inst in f.get("ext_grid", []):
			(inst as GeometryInstance3D).transparency = transp


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
