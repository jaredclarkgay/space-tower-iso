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
	{"node": "Floors/Utility", "level": 0, "name": "FLOOR 0 / CONTROL CENTER"},
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
	{"id": "utility",      "label": "Control Center (Floor 0)"},
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
# True while a crane-issued floor build is mid-assembly (opening redesign Chunk 7). The
# worksite animates (workers hammer) and the floor assembles, but the player stays FREE.
var _crane_building: bool = false
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
# Opening redesign Chunk 9 — the arrival is the ONE allowed lock, trimmed to its essence:
# Cody rises from the column, says ONE line, control returns. _arrival_played is the one-shot
# gate; _arrival_cine is active; _arrival_beat is the trimmed beat index (1=emerge, 2=one-line,
# 4=resume); _arrival_t times the current beat. (The old walk-in/stop-hold/rotate/orbit beats
# were the railroad that's now gone — see _update_arrival_cinematic.)
var _arrival_played: bool = false
var _arrival_cine: bool = false
var _arrival_beat: int = 0
var _arrival_t: float = 0.0
var _arrival_walk_started: bool = false   # first-tick guard for begin_scripted_walk
var _oneline_said: bool = false           # one-shot: Cody's single arrival line issued
# Beat-3 elevator-emergence sub-phasing (Step 3). The conductor puppets the
# elevator car + Cody up the shaft, concurrently with the orbit sweep.
var _emerge_started: bool = false         # one-shot Beat-3 entry guard
var _emerge_rollout_started: bool = false # one-shot: roll-out fired
var _rollout_elapsed: float = 0.0         # seconds since the roll-out tween fired (gates the rotation)
# ROTATE-DELAY: the yaw stays pinned at _walk_yaw() (0, over-the-shoulder) through the WHOLE
# emergence; only once Cody is (nearly) settled does the rotation to the profile begin. It's
# tracked with member state so it can keep advancing the SAME smoothstep across the Beat 3 →
# Beat 5 boundary (emergence done before the 2.2 s ease finishes) — no snap/restart.
var _rotate_started: bool = false         # true once the yaw→profile rotation has begun
var _rotate_t: float = 0.0                # rotation ease elapsed (0 → ARRIVAL_CINE_ROTATE_DUR)
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
# FIX 2 — intro ease (cinematic start). Capture the LIVE camera WORLD pose the moment the
# cinematic begins (wherever the prior mode left it) and smoothstep FROM it TO the OTS
# follow pose over ARRIVAL_CINE_INTRO_DUR while Beat 1 (the walk) already runs, so the
# camera GLIDES in behind the walking player instead of snapping. _intro_t times it. We
# blend in WORLD space (the pivot moves during the ease) then re-derive the local offset.
var _intro_t: float = 0.0
var _intro_active: bool = false
var _intro_from_cam_world: Vector3 = Vector3.ZERO
var _intro_from_cam_basis: Basis = Basis.IDENTITY
var _intro_from_size: float = 0.0
# FIX 3 — re-entry ease (walk back in through the doorway). Eases the camera from the
# exterior-walk follow pose to iso's resting pose without teleporting the player. The
# player keeps control; only the camera eases. _reentry_ease is the active flag.
var _reentry_ease: bool = false
var _reentry_t: float = 0.0
var _reentry_from_pivot: Vector3 = Vector3.ZERO
var _reentry_from_yaw: float = 0.0
var _reentry_from_cam_pos: Vector3 = Vector3.ZERO
var _reentry_from_cam_basis: Basis = Basis.IDENTITY
var _reentry_from_size: float = 0.0
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
	# First-entry greeter for the NON-cinematic path (dev boot / jump-to-Garden /
	# cinematic-disabled). greet_on_entry self-guards on Cody's OFFLINE state, so
	# re-spawns + later entries are no-ops; his arrival ends by issuing the
	# power_utilities beat through the Director channel — the same single greeting
	# the cinematic hand-off issues. (The cinematic path runs _begin_arrival_cinematic,
	# not this, so there's no double-greet.)
	var robot: Node = get_node_or_null("Floors/Garden/IsoRobot")
	if robot and robot.has_method("greet_on_entry"):
		robot.call("greet_on_entry")


# Garden arrival gate. The FIRST time the player enters the Garden (and the
# cinematic is enabled) it plays the scripted walk-in; every later entry is the
# plain spawn. Called from both enter_tower() and _enter_building() in place of the
# bare _spawn_in_garden().
func _arrive_in_garden(walked_in: bool = false) -> void:
	if bool(_c.ARRIVAL_CINE_ENABLED) and not _arrival_played:
		_begin_arrival_cinematic(walked_in)
	else:
		_spawn_in_garden()


# Beat 0-1 entry: place the player just inside the south doorway, snap the camera to
# the behind-the-back framing, flip on the cinematic and kick off Beat 1 (the walk).
# `walked_in` = the player physically crossed the threshold (vs. the hire/dev hand-off
# that drops them on the lot): when true, keep their exact pose instead of relocating.
func _begin_arrival_cinematic(walked_in: bool = false) -> void:
	_arrival_played = true
	_arrival_cine = true
	_arrival_beat = 1
	_arrival_t = 0.0
	_arrival_walk_started = false
	_emerge_started = false
	_emerge_rollout_started = false
	_rollout_elapsed = 0.0
	_rotate_started = false
	_rotate_t = 0.0
	_convo_opened = false
	_convo_yaw = 0.0
	_oneline_said = false
	_resume_started = false
	_resume_t = 0.0
	# FIX 3 — reset Cody + the elevator to their PRE-cinematic state so the emergence REPLAYS
	# in full (on a replay they're left parked/visible/at-rest-with-doors-open, which would
	# short-circuit is_emergence_done()). On the first boot play these are already at rest, so
	# the resets are safe no-ops.
	var robot0: Node = get_node_or_null("Floors/Garden/IsoRobot")
	if robot0 and robot0.has_method("cinematic_reset"):
		robot0.call("cinematic_reset")
	var elevator0: Node = get_node_or_null("ElevatorPlatform")
	if elevator0 and elevator0.has_method("cinematic_reset"):
		elevator0.call("cinematic_reset")
	_gs.set("arrival_cinematic", true)
	# Only RELOCATE to the south-door spawn when the player arrives from OUTSIDE the footprint
	# (the hire / debug hand-off drops them out on the lot). When they physically WALKED across
	# the threshold they're already just inside a doorway — keep their EXACT position AND heading
	# so there's no jump/turn at the door; the scripted walk below simply eases them on to the
	# mark from wherever they crossed (the walk direction ≈ their entry heading, so no snap).
	# Mirrors the re-entry no-teleport rule (FIX 3). The site ground is at grade with the Garden,
	# so a walk-in's Y already matches the floor — no vertical pop from keeping it.
	var spawn_y: float = _base_y_for_level(_SPAWN_LEVEL) + float(_c.FLOOR_3D_TOP_Y)
	if not walked_in:
		_player.global_position = Vector3(0.0, spawn_y, float(_c.ARRIVAL_CINE_DOOR_Z))
		if _player is CharacterBody3D:
			(_player as CharacterBody3D).velocity = Vector3.ZERO
	if _player.has_method("set_spawn_here"):
		_player.set_spawn_here()
	# CALM REDESIGN: seed the persistent _cam_* members DIRECTLY AT the settled
	# walk-follow OTS pose — NOT a higher/farther "opening" pose. The old seed eased a big
	# back/lift/shoulder drop over Beat 1 (a perceptible swoop) and started yaw at 0 (a 24°+
	# rotation into the walk yaw). Seeding at the final follow pose makes entry→walk ONE
	# motion: the only thing that moves at the start is the intro blend gliding the live
	# camera from the prior mode into the (already-correct) follow. The walk yaw sits a
	# small bias OFF the iso resting yaw, ONE direction; the emergence eases that bias to 0.
	_cam_init = true
	_cam_focus = _player.global_position
	_cam_yaw = _walk_yaw()
	_cam_back = float(_c.ARRIVAL_CINE_OTS_BACK)
	_cam_lift = float(_c.ARRIVAL_CINE_OTS_LIFT)
	_cam_shoulder = float(_c.ARRIVAL_CINE_OTS_SHOULDER)
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
	# FIX 2 (rework) — the entry is a slow ZOOM-IN from the LIVE prior camera pose to behind
	# the player. Capture the actual `_camera` world transform + ortho size the moment the
	# cinematic starts (wherever the exterior / prior mode left it), and ease FROM it INTO the
	# OTS-behind follow over ARRIVAL_CINE_INTRO_DUR (smoothstep, slerped basis). This is one
	# continuous gentle zoom-in that arrives behind the character — NO cut, NO overhead jump.
	# The old synthesized high-above start pose (which made frame 1 a cut to directly overhead)
	# is gone. The _cam_* members ease underneath, so at intro completion the live pose already
	# equals the driven OTS follow — no second pop at the hand-off.
	if _pivot and _camera:
		_intro_active = true
		_intro_t = 0.0
		_intro_from_cam_world = _camera.global_position
		_intro_from_cam_basis = _camera.global_transform.basis
		_intro_from_size = _camera.size
	else:
		_intro_active = false
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


# Floor-by-floor entry (opening redesign Chunk 10, Control-Center-first). After the player
# builds the Control Center from the crane they're already standing ON its floor (the worksite
# climbed them down onto it). This flips the cold-open EXTERIOR presentation to the interior
# per-floor world: the pit's cold-open staging retires (worksite hides, the real elevator car
# appears) as the arc advances, the Control Center renders as the current floor, and Cody rises
# from the column right here. No teleport — the player keeps their exact spot below grade.
func enter_control_center() -> void:
	if not _exterior:
		return
	_exterior = false
	if _empty_lot:
		_empty_lot.visible = false
	# Advance the arc past the cold-open build phases so ConstructionPit deactivates (it gates
	# active on phase <= BUILD_STRUCTURE) — the worksite + earthen staging clear and the built
	# tower's own elevator takes over.
	var gd: Node = get_node_or_null("/root/GameDirector")
	if gd and gd.has_method("set_phase"):
		gd.set_phase(gd.Phase.BUILD_INTERIORS)
	_current_level = int(_c.GROUND_LEVEL) - 1   # the Control Center / basement (level 0)
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).velocity = Vector3.ZERO
	if _player and _player.has_method("set_spawn_here"):
		_player.set_spawn_here()
	# (Stage 10b wires Cody's rise from the column here — the one allowed lock, restaged at the
	# Control Center. For now entry is just the presentation flip.)
	_hud_level = -1
	_update(true)


# Enter (or return to) the exterior empty lot: spawn the player on the lot and
# flip on exterior mode. Used by the boot branch and by the debug phase walk
# when it wraps back to EMPTY_LOT.
func enter_exterior() -> void:
	_exterior = true
	_gs.built_level = -1   # cold open: nothing built yet; floors raise one at a time from the crane
	_crane_building = false
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
	# Floors raise one at a time from the crane: a floor is present once it's been built
	# (level <= built_level). Initially nothing is built (built_level = -1) so the site is
	# bare — the construction pit is the only ground. As floors build, they appear in place.
	for f in _floors:
		var node: Node3D = f.node
		var built: bool = int(f.level) <= int(_gs.built_level)
		if node.has_method("set_structure_visible"):
			node.set_structure_visible(built)
		else:
			node.visible = built
		# Unbuilt floors must NOT collide (else the invisible Garden slab at grade ceilings
		# the pit). A built floor's slab IS solid so you can stand on the floor you raised.
		var slab: StaticBody3D = f.get("slab")
		if slab:
			slab.collision_layer = 2 if built else 0
		# The extension grid is for the in-tower extended-floor look; it reads as a big blue
		# plane in the open cold-open pit, so keep it off out here.
		var ext_grid = f.get("ext_grid")
		if ext_grid is Array:
			for g in ext_grid:
				if is_instance_valid(g):
					g.visible = false
		elif ext_grid != null and is_instance_valid(ext_grid):
			ext_grid.visible = false
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
	# Floor-by-floor entry (Chunk 10): once the Control Center is built and the player has
	# settled ONTO its floor (grounded, inside the footprint, below grade — only reachable by
	# being down in the built basement, not up on the crane), flip into the interior world.
	if int(_gs.built_level) >= int(_c.GROUND_LEVEL) - 1 and _player and not _crane_building \
			and not bool(_gs.get("driving_crane")):
		var half: float = float(_c.FLOOR_3D_SIZE) * 0.5
		var pp: Vector3 = _player.global_position
		var grounded: bool = _player is CharacterBody3D and (_player as CharacterBody3D).is_on_floor()
		# Below grade = below the at-grade floor (the Garden sits at y=0); the built Control
		# Center floor is a full story down, so this cleanly means "standing in the basement".
		var below_grade: bool = pp.y < _base_y_for_level(int(_c.GROUND_LEVEL)) - 1.0
		if grounded and below_grade and absf(pp.x) < half and absf(pp.z) < half:
			enter_control_center()
			return
	_drive_environment(snap)


# --- Crane-issued floor construction (opening redesign Chapter 2 / Chunk 7) -------
# Floors raise one at a time from the crane cab. The next buildable level is the one just
# above the highest built — gated to what's UNLOCKED. For now only the Control Center
# (level 0) is unlocked; later events unlock the floors above (Chunk 10 wires
# utilities-complete -> Garden).
const _CRANE_UNLOCKED_MAX := 0   # highest level the crane may raise so far (Control Center)

func next_buildable_level() -> int:
	# Nothing's buildable until you've signed on with a partner (the call that says "go build").
	if String(_gs.partner_name) == "":
		return -1
	var nxt: int = int(_gs.built_level) + 1
	if nxt <= _CRANE_UNLOCKED_MAX and _floor_node_for_level(nxt) != null:
		return nxt
	return -1

func next_buildable_label() -> String:
	var lvl: int = next_buildable_level()
	if lvl < 0:
		return ""
	if lvl == int(_c.GROUND_LEVEL) - 1:
		return "Control Center"
	return _name_for_level(lvl)

func is_crane_building() -> bool:
	return _crane_building

# Raise the next unlocked floor from the crane: prime it collapsed, reveal it, play the
# per-component assembly, and set the worksite hammering for the duration. The player stays
# FREE the whole time (no _constructing freeze, no camera seize).
func request_crane_build() -> void:
	if _crane_building:
		return
	var lvl: int = next_buildable_level()
	if lvl < 0:
		return
	_crane_building = true
	get_tree().call_group("worker_npc", "set_building", true)
	var node: Node3D = _floor_node_for_level(lvl)
	var asm: Object = _floor_assembler(node)
	if asm != null:
		asm.call("prime_collapsed")
	_gs.built_level = lvl                 # the floor is now present (revealed by _update_exterior)
	var tw: Tween = _assemble_floor(lvl)
	var dur: float = 1.0
	if asm != null and asm.has_method("approx_duration"):
		dur = float(asm.call("approx_duration"))
	elif tw != null:
		dur = float(_c.CONSTRUCT_STEP_DUR)
	get_tree().create_timer(dur + 0.3).timeout.connect(_finish_crane_build)
	_hud_level = -99
	_update(true)

func _finish_crane_build() -> void:
	_crane_building = false
	get_tree().call_group("worker_npc", "set_building", false)
	_update(true)


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
	# Per-component floors: collapse every piece so nothing flashes full when it's
	# revealed, then assemble the basement foundation in place (build starts from
	# the ground up; each B raises the next floor by assembling it).
	for f in _floors:
		var asm: Object = _floor_assembler(f.node)
		if asm != null:
			asm.call("prime_collapsed")
	_assemble_floor(0)
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
			node.set_slab_alpha(float(_c.CANOPY_SLAB_ON_ALPHA) if built else 0.0)
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


# This floor's construction ASSEMBLER — either its FloorConstruction module, or
# the floor node itself if it implements the assembler interface directly (the
# Canopy, whose glass-ceiling slab is too special for the manifest). Null = no
# assembler (uses the whole-floor grow-in fallback). The interface is:
# prime_collapsed() / play_sequence() / is_complete() / approx_duration().
func _floor_assembler(node: Node) -> Object:
	if node == null:
		return null
	var fc: Object = node.get("_construction")
	if fc != null:
		return fc
	if node.has_method("play_sequence"):
		return node
	return null


func _floor_node_for_level(level: int) -> Node3D:
	for f in _floors:
		if int(f.level) == level:
			return f.node
	return null


# Assemble a floor IN PLACE at its final height (no rise — the bounce-and-gap is
# gone). A converted floor plays its piece-by-piece sequence (slab → core →
# risers → walls → tubes → grid); an unconverted one does a clean whole-node
# grow-in. Returns the fallback Tween (or null for the per-component path).
func _assemble_floor(level: int) -> Tween:
	var node: Node3D = _floor_node_for_level(level)
	if node == null:
		return null
	node.position.y = _base_y_for_level(level)
	var asm: Object = _floor_assembler(node)
	if asm != null:
		node.scale.y = 1.0
		if not bool(asm.call("is_complete")):
			asm.call("play_sequence")         # coroutine — assembles over the next beats
		return null
	# Fallback: the floor materializes by growing up out of nothing (no bounce).
	node.scale.y = float(_c.CONSTRUCT_GROW_EPSILON)
	var tw := create_tween()
	tw.tween_property(node, "scale:y", 1.0, float(_c.CONSTRUCT_STEP_DUR)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw


# Raise the next floor by ASSEMBLING it in place; reframe to the taller stack.
func _build_next_floor() -> void:
	if int(_gs.built_level) >= _top_level:
		return                                 # already topped out
	_gs.built_level = int(_gs.built_level) + 1
	var lvl: int = int(_gs.built_level)
	var tw: Tween = _assemble_floor(lvl)
	# Topped out: once the last floor finishes assembling, step out to explore.
	if int(_gs.built_level) >= _top_level:
		if tw != null:
			tw.finished.connect(_begin_exterior_walk)
		else:
			var asm: Object = _floor_assembler(_floor_node_for_level(lvl))
			var d: float = float(asm.call("approx_duration")) if asm != null else 1.0
			get_tree().create_timer(d).timeout.connect(_begin_exterior_walk)
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
			node.set_slab_alpha(float(_c.CANOPY_SLAB_ON_ALPHA) if built else 0.0)
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
	# FIX 3 — RE-ENTRY is anything after the first-time cinematic already played. On
	# re-entry we must NOT teleport the player (they physically walked across the
	# threshold) and must NOT hard-cut the camera. Capture the exterior-walk pose first
	# so the re-entry ease can glide it to iso's resting pose.
	var reentry: bool = _arrival_played
	if reentry and _pivot and _camera:
		_reentry_ease = true
		_gs.set("reentry_ease", true)         # iso_camera bows out while the controller eases
		_reentry_t = 0.0
		_reentry_from_pivot = _pivot.global_position
		_reentry_from_yaw = _pivot.rotation.y
		_reentry_from_cam_pos = _camera.position
		_reentry_from_cam_basis = _camera.transform.basis
		_reentry_from_size = _camera.size
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
	# FIX 3 — on re-entry the player keeps their current (threshold) position: skip the
	# _arrive_in_garden() teleport entirely. Just re-anchor the spawn + zero momentum so
	# they walk in continuously. The first-time path still runs the cinematic.
	if reentry:
		_current_level = _level_for_y(_player.global_position.y) if _player else _SPAWN_LEVEL
		if _player is CharacterBody3D:
			(_player as CharacterBody3D).velocity = Vector3.ZERO
		if _player and _player.has_method("set_spawn_here"):
			_player.set_spawn_here()
	else:
		_arrive_in_garden(true)               # first-time, but they WALKED across the threshold: keep their pose
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
	# FIX 2 — advance the intro-ease timer first so the per-beat _drive_arrival_camera
	# (which still eases the _cam_* members toward the OTS targets) is OVERRIDDEN by a
	# smoothstep blend from the captured start pose for the first ARRIVAL_CINE_INTRO_DUR.
	if _intro_active:
		_intro_t += delta
		if _intro_t >= float(_c.ARRIVAL_CINE_INTRO_DUR):
			_intro_active = false   # hand to the normal member-ease cleanly (members already at OTS)
	if _arrival_beat == 1:
		# Beat 1 — EMERGE (the one allowed lock). The player stands where they entered,
		# frozen by arrival_cinematic; Cody rises from the column/elevator. The camera holds
		# ONE calm over-the-shoulder frame that widens to take in the rising bot — NO walk-in,
		# NO rotate-to-profile, NO orbit (those were the railroad; opening redesign Chunk 9).
		_update_emergence(delta)
		_set_emergence_frame_targets()
		_drive_arrival_camera(delta)
		var robot1: Node = get_node_or_null("Floors/Garden/IsoRobot")
		var emerge_done: bool = robot1 == null or not robot1.has_method("is_emergence_done") or bool(robot1.call("is_emergence_done"))
		if emerge_done:
			_arrival_beat = 2
			_arrival_t = 0.0
	elif _arrival_beat == 2:
		# Beat 2 — ONE line, then auto-return. Cody delivers a single non-interactive line and
		# the HUD objective carries the rest. The Director owns the words (vision.md §1): set the
		# directive's OBJECTIVE passively (HUD mirror, no interactive box) + speak its one-liner.
		if not _oneline_said:
			_oneline_said = true
			var robot2: Node = get_node_or_null("Floors/Garden/IsoRobot")
			var gd: Node = get_node_or_null("/root/GameDirector")
			var line: String = ""
			if gd and gd.has_method("issue_directive"):
				gd.call("issue_directive", "power_utilities", false)   # objective only
				if gd.has_method("oneline_for"):
					line = String(gd.call("oneline_for", "power_utilities"))
			if robot2 and robot2.has_method("say_oneline") and line != "":
				robot2.call("say_oneline", line, float(_c.ARRIVAL_CINE_LINE_HOLD))
		_set_emergence_frame_targets()
		_drive_arrival_camera(delta)
		if _arrival_t >= float(_c.ARRIVAL_CINE_LINE_HOLD):
			_arrival_beat = 4
			_arrival_t = 0.0
			_resume_started = false
	elif _arrival_beat == 4:
		_update_resume_ease(delta)


# The calm arrival frame (Chunk 9): a steady over-the-shoulder shot, yaw pinned at 0 (looking
# NORTH toward the rising Cody), widened a touch to a two-shot and nudged toward the pair so
# the emerging bot + the one line both read. NO rotation, NO orbit — the whole trimmed lock
# holds this single frame from the rise through the line, then the resume ease takes over.
func _set_emergence_frame_targets() -> void:
	var pp: Vector3 = _player.global_position
	_cam_focus_tgt = pp.lerp(_pair_midpoint(), 0.45)
	_cam_yaw_tgt = _walk_yaw()
	_cam_back_tgt = float(_c.ARRIVAL_CINE_OTS_BACK)
	_cam_lift_tgt = float(_c.ARRIVAL_CINE_OTS_LIFT)
	_cam_shoulder_tgt = float(_c.ARRIVAL_CINE_OTS_SHOULDER)
	_cam_size_tgt = float(_c.ARRIVAL_CINE_EMERGE_OTS_SIZE)
	_cam_lookahead_tgt = float(_c.ARRIVAL_CINE_OTS_LOOK_AHEAD)
	_cam_looklift_tgt = float(_c.ARRIVAL_CINE_OTS_LOOK_LIFT)


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
	# FIX 1 — nudge the focus NORTH (toward Cody, +Z) so the profile two-shot sits in the
	# upper frame, clear of the bottom-left dialogue panel.
	return mid + Vector3(0.0, float(_c.ARRIVAL_CINE_PAIR_LIFT), float(_c.ARRIVAL_CINE_PROFILE_FOCUS_Z))


# Beat-3 emergence: puppet the elevator car + Cody up the shaft, then roll Cody out.
# Sub-phased off the beat timer _arrival_t (reset to 0 on Beat-3 entry), running
# CONCURRENTLY with the orbit sweep. Lead → rise → doors → roll-out.
func _update_emergence(delta: float) -> void:
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
	else:
		# Track how long the roll-out tween has been running so Beat 3 can fire the
		# yaw→profile rotation a small lead (ARRIVAL_CINE_ROTATE_LEAD) before it ends.
		_rollout_elapsed += delta


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


# FIX 3 — re-entry ease: walking BACK in through the doorway. The player has CONTROL the
# whole time (not frozen); only the camera is controller-owned for this short ease. We
# smoothstep the camera FROM the captured exterior-walk follow pose TO iso's resting pose
# over ARRIVAL_CINE_REENTRY_DUR. The iso target is recomputed each frame because the
# player keeps moving (pivot XZ tracks them). On completion we release to iso, which picks
# up from the identical transform — no hard cut, no warp (the player was never teleported).
func _update_reentry_ease(delta: float) -> void:
	if _pivot == null or _camera == null or _player == null:
		_reentry_ease = false
		_gs.set("reentry_ease", false)
		return
	# iso RESTING-pose target (mirrors _update_resume_ease) — recomputed live so the pivot
	# follows the walking player's XZ while the rest of the framing eases in.
	var pp: Vector3 = _player.global_position
	var iso_pivot_y: float = _base_y_for_level(_current_level) + _PIVOT_CHEST
	var iso_pivot := Vector3(pp.x, iso_pivot_y, pp.z)
	var iso_yaw: float = deg_to_rad(float(_c.CAMERA_YAW_DEG_INITIAL))
	var tilt_rad: float = deg_to_rad(abs(float(_c.CAMERA_TILT_DEG)))
	var d: float = float(_c.CAMERA_DISTANCE)
	var iso_cam_pos := Vector3(0.0, d * sin(tilt_rad), d * cos(tilt_rad))
	var iso_cam_basis := Basis.from_euler(Vector3(deg_to_rad(float(_c.CAMERA_TILT_DEG)), 0.0, 0.0))
	var iso_size: float = float(_c.CAMERA_ORTHO_SIZE_DEFAULT)

	_reentry_t += delta
	var e: float = smoothstep(0.0, 1.0, clampf(_reentry_t / float(_c.ARRIVAL_CINE_REENTRY_DUR), 0.0, 1.0))

	# Ease the live camera exterior-walk → iso. Pivot global pos + yaw, Camera3D local pos +
	# orientation (slerp the basis), and ortho size — the same shape as the resume ease.
	_pivot.global_position = _reentry_from_pivot.lerp(iso_pivot, e)
	var yaw_diff: float = wrapf(iso_yaw - _reentry_from_yaw + PI, 0.0, TAU) - PI
	_pivot.rotation = Vector3(0.0, _reentry_from_yaw + yaw_diff * e, 0.0)
	_camera.position = _reentry_from_cam_pos.lerp(iso_cam_pos, e)
	_camera.transform.basis = _reentry_from_cam_basis.slerp(iso_cam_basis, e)
	_camera.size = lerpf(_reentry_from_size, iso_size, e)
	_gs.camera.ortho_size = _camera.size

	if _reentry_t >= float(_c.ARRIVAL_CINE_REENTRY_DUR):
		# Snap to the exact iso pose, then release — iso_camera resumes from here seamlessly.
		_pivot.global_position = iso_pivot
		_pivot.rotation = Vector3(0.0, iso_yaw, 0.0)
		_camera.position = iso_cam_pos
		_camera.transform.basis = iso_cam_basis
		_camera.size = iso_size
		_gs.camera.ortho_size = iso_size
		_reentry_ease = false
		_gs.set("reentry_ease", false)


# Per-beat TARGET helper — the settled over-the-shoulder WALK-IN framing (Beats 1/2).
# Sets ONLY the _cam_*_tgt members; the persistent _cam_* members ease toward these
# in _drive_arrival_camera. The members were seeded to the higher/farther OPENING pose
# at cinematic start, so easing toward these tight values IS the old camera-lower-in
# (the per-frame lower_t lerp is now the continuous member ease — same motion, no pop).
# The iso resting pivot yaw (radians) — what the cinematic must LAND on so the exit is
# a non-event (the resume yaw delta is ~0).
func _iso_yaw() -> float:
	return deg_to_rad(float(_c.CAMERA_YAW_DEG_INITIAL))


# FIX 1 — the PROFILE conversation yaw the cinematic settles to and holds. The pair lies
# along Z facing each other; a profile = camera along ±X. ARRIVAL_CINE_PROFILE_YAW_DEG is
# −90 (camera east, looking west across the pair), only 45° off iso (−135) so the resume
# stays gentle. The settle eases walk_yaw(0) → this; Beat 4 then eases this → iso(−135).
func _profile_yaw() -> float:
	return deg_to_rad(float(_c.ARRIVAL_CINE_PROFILE_YAW_DEG))


# The walk-follow pivot yaw (radians): iso resting yaw (-135) + WALK_YAW_BIAS (135) = 0 =
# directly BEHIND the player (camera due south, -Z), seeing his back as he walks NORTH (+Z)
# = true over-the-shoulder. The settle then sweeps this 0 -> iso (-135), one direction, after
# he settles (the single deliberate rotation; lerp_angle 0->-135 goes negative, framing Cody).
func _walk_yaw() -> float:
	return _iso_yaw() + deg_to_rad(float(_c.ARRIVAL_CINE_WALK_YAW_BIAS))


# Build the world-space basis of a camera at `from` looking at `to` (Y-up), matching
# Camera3D.look_at's convention (camera looks down its -Z). Used to synthesize the intro
# descend's high-behind START orientation (looking DOWN at the player) so the blend can
# slerp from it into the OTS follow without re-running look_at.
func _looking_at_basis(from: Vector3, to: Vector3) -> Basis:
	var fwd: Vector3 = to - from
	if fwd.length() < 0.0001:
		return Basis.IDENTITY
	return Transform3D().looking_at(fwd, Vector3.UP).basis


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
		# FIX 1 — clamp the camera's WORLD XZ to stay over the floor footprint. The
		# behind-the-back pose pushes the camera past the south edge at the doorway, where
		# it would look UNDER the slab (void / site-ground / basement). Clamping it inward
		# keeps the slab filling the lower frame at every point in the cinematic; the look-at
		# (below) still aims at the focus, so only the framing slides — never sees under the
		# edge. We convert the clamped world point back to a pivot-local offset.
		_clamp_cam_over_footprint()
		# Look-at: a touch toward the shoulder side + ahead (+Z) + up. With shoulder→0 and
		# lookahead→0 (the orbit/convo targets) this is the dead-centre clean-circle aim;
		# with the OTS values it's the over-the-shoulder, look-ahead framing — and because
		# both ease continuously the transition between them never snaps.
		var look_local := Vector3(_cam_shoulder * 0.45, _cam_looklift, _cam_lookahead)
		var look_world: Vector3 = _pivot.global_transform * look_local
		# The edge-pitch-drop "cutaway" hack was removed (operator disliked the way it
		# pitched the floor away near edges). With the site ground now visible at grade
		# (FIX 1) the area past the floor edge is solid ground, not void/basement, and the
		# higher angled-down OTS (raised ARRIVAL_CINE_OTS_LIFT) keeps the slab filling the
		# lower frame — together these kill the see-through without any per-edge pitching.
		_camera.look_at(look_world, Vector3.UP)
		_camera.size = _cam_size
		_gs.camera.ortho_size = _camera.size
		# FIX 2 — intro ease: for the first ARRIVAL_CINE_INTRO_DUR the OTS pose just
		# computed (and clamped + look_at-oriented above) is the END pose; smoothstep-blend
		# the APPLIED transform FROM the captured live start pose TO it, so the camera glides
		# in behind the walking player instead of snapping. We blend the basis directly (no
		# re-run of look_at) so e=0 holds the exact live orientation — no first-frame pop.
		# The _cam_* members keep easing underneath, so when the intro completes the live
		# pose already equals the driven pose — no second pop at the hand-off.
		if _intro_active:
			_blend_intro_pose()
			_gs.camera.ortho_size = _camera.size


# FIX 2 helper — blend the just-applied OTS pose toward the captured cinematic-start pose
# by the inverse intro progress, so e=0 → start pose, e=1 → full OTS follow. Mirrors the
# resume ease, reversed (start→OTS). Pivot global pos + yaw, Camera3D local pos + basis
# (slerped — no look_at re-run so the start orientation is held exactly at e=0), ortho size.
func _blend_intro_pose() -> void:
	if _pivot == null or _camera == null:
		return
	var e: float = smoothstep(0.0, 1.0, clampf(_intro_t / float(_c.ARRIVAL_CINE_INTRO_DUR), 0.0, 1.0))
	# The pivot already sits at the DRIVEN position/yaw (we keep it — the pivot tracks the
	# player). We blend only the Camera3D's WORLD pose from the captured start toward the
	# driven world pose, so the camera body glides in independent of the pivot motion.
	var to_cam_world: Vector3 = _camera.global_position
	var to_cam_basis: Basis = _camera.global_transform.basis
	var to_size: float = _camera.size
	var blended_world: Vector3 = _intro_from_cam_world.lerp(to_cam_world, e)
	# Ease the footprint clamp IN by intro progress. At e=0 hold the EXACT captured live pose
	# (the exterior-walk camera legitimately sits OUTSIDE the footprint and frames the at-grade
	# site ground, not void) — a hard clamp here yanked that far start pose inward on frame 1,
	# which was the entry "jump". By e=1 the pose is fully clamped so the close OTS end-framing
	# still never peers under the slab. (to_cam_world is already clamped, so the destination is
	# safe; only the START needed un-clamping.)
	var half: float = float(_c.FLOOR_3D_SIZE) * 0.5 - float(_c.ARRIVAL_CINE_CAM_FOOTPRINT_MARGIN)
	var clamped := Vector3(clampf(blended_world.x, -half, half), blended_world.y, clampf(blended_world.z, -half, half))
	blended_world = blended_world.lerp(clamped, e)
	var blended_basis: Basis = _intro_from_cam_basis.slerp(to_cam_basis, e)
	# Write the blended WORLD pose back (Godot derives the local transform under the pivot).
	_camera.global_transform = Transform3D(blended_basis, blended_world)
	_camera.size = lerpf(_intro_from_size, to_size, e)


# FIX 1 helper — keep the cinematic camera's WORLD XZ inside the Garden footprint (minus a
# margin) so the slab always reads solid and the camera never peers under the south/edge.
# The camera local pos is already set; we read its world XZ, clamp, and write back the
# pivot-local offset for the clamped world point (Y/local-Z framing preserved otherwise).
# (The former _edge_pitch_drop helper — a per-edge look-at pull-down "cutaway" — was
# removed; the operator disliked the floor-pitch look. The higher angled-down OTS plus the
# at-grade site ground now keep the floor solid to the edge without it.)
func _clamp_cam_over_footprint() -> void:
	if _camera == null or _pivot == null:
		return
	var world: Vector3 = _pivot.global_transform * _camera.position
	var half: float = float(_c.FLOOR_3D_SIZE) * 0.5 - float(_c.ARRIVAL_CINE_CAM_FOOTPRINT_MARGIN)
	var cx: float = clampf(world.x, -half, half)
	var cz: float = clampf(world.z, -half, half)
	if cx == world.x and cz == world.z:
		return
	world.x = cx
	world.z = cz
	_camera.position = _pivot.global_transform.affine_inverse() * world


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
	# (The old frozen press-B all-floors dollhouse build is retired — floors now raise one
	# at a time from the crane cab; see request_crane_build(). The _constructing path remains
	# only as dead fallback for the dev "build" chapter jump.)
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
	# FIX 3 — re-entry ease: after walking back in, the controller eases the camera from
	# the exterior-walk follow pose to iso's resting pose (the player keeps control). Runs
	# while iso_camera bows out (gated on reentry_ease), then releases to iso seamlessly.
	if _reentry_ease:
		_update_reentry_ease(delta)
	# Ceiling bonk → a localized glass glow at the hit point on the floor above.
	if _player and _player.has_method("is_on_ceiling") and _player.is_on_ceiling():
		_ceiling_pulse = 1.0
		_bonk_pos = _player.global_position
	else:
		_ceiling_pulse = maxf(_ceiling_pulse - delta * float(_c.CANOPY_CEILING_PULSE_DECAY), 0.0)
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
		_wall_pulse = maxf(_wall_pulse - delta * float(_c.CANOPY_CEILING_PULSE_DECAY), 0.0)
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
	# Basement occlusion is now handled by the unified below-grade rule in the loop
	# below (a below-grade floor shows only when _current_level is itself below grade).
	# That covers the arrival cinematic too — from the Garden the basement stays hidden —
	# so the old cinematic-only "current floor only" gate is gone.
	for f in _floors:
		var node: Node3D = f.node
		# Construct-from-empty: a floor only exists once built. Unbuilt floors are
		# fully absent (invisible + no collision). With built_level=99 (default)
		# every floor is built, so this reduces to the original at_or_below rule.
		var built: bool = int(f.level) <= int(_gs.built_level)
		# Unified visibility rule (operator's basement-occlusion fix). A floor shows
		# when it's built AND at-or-below the current floor — EXCEPT a below-grade
		# (basement) floor is shown ONLY when you are yourself at/below grade (on or
		# descending to it). So from the Garden+ the basement stays hidden under the
		# at-grade site ground; riding the elevator DOWN crosses _current_level to 0
		# and the basement reveals. Above-grade floors keep the plain at-or-below rule.
		# This subsumes the old cinematic-only gate: from the Garden (current=1) only the
		# Garden shows (basement is below-grade → hidden; floors above → > current), so
		# the separate cine_gate special-case is no longer needed.
		var at_or_below: bool = built and (int(f.level) <= _current_level) \
			and (int(f.level) >= int(_c.GROUND_LEVEL) or _current_level < int(_c.GROUND_LEVEL))
		# Slab COLLISION: solid for your floor + everything BELOW, OFF only for floors
		# ABOVE (so a jump passes straight up through the ceiling and falls back to the
		# same floor). This is deliberately decoupled from `at_or_below` — that var also
		# folds in the below-grade VISIBILITY trick (the basement hides under the site
		# ground from above grade). Collision must NOT follow that: the basement is the
		# bottom of the tower and has to stay SOLID even while hidden, or a fall down the
		# open shaft drops straight through it into the void ("fall beneath the lowest
		# floor"). Now anything that gets into the shaft lands in the basement instead.
		# Canopy has no "SlabBody" (slab = null) → its glass ceiling collision is never
		# touched here, so Floor 2 jumps still bonk it.
		var solid: bool = built and (int(f.level) <= _current_level)
		var slab: StaticBody3D = f.get("slab")
		if slab:
			slab.collision_layer = 2 if solid else 0
		if node.has_method("set_structure_visible"):
			# Glass-ceiling floor (Canopy): walls/elevator gated; the slab is an
			# invisible glass ceiling from below and a frosted-glass floor when
			# you stand on it. Its tree-hole aperture rings stay faintly visible
			# from the floor below, and bonking the glass ceiling (you can't jump
			# through it — it's the one solid ceiling) lights a localized glow.
			node.set_structure_visible(at_or_below)
			node.set_slab_alpha(float(_c.CANOPY_SLAB_ON_ALPHA) if at_or_below else 0.0)
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
	if _pivot and String(_gs.get("camera_mode")) == "iso" and not bool(_gs.get("dialogue_open")) and not bool(_gs.get("looking_out")) and not _arrival_cine and not _reentry_ease:
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
	# The exterior GROUND is the world the tower stands ON: keep it visible from grade
	# (the Garden) and EVERY floor above (Arboretum, Canopy, Residential, Sky Lounge,
	# Roof) so the tower never floats in void and — being a full 72 m plane at y=0 — it
	# OCCLUDES the below-grade basement from any above-grade view. It's hidden ONLY when
	# the player is themselves BELOW grade (in the basement), where you're under it. The
	# exterior / construct / walk branches manage their own visibility.
	if _site_ground:
		_site_ground.visible = (_current_level >= int(_c.GROUND_LEVEL))
		# Recenter the VISUAL ground mesh on the camera pivot XZ each frame so its edge is
		# NEVER visible from any view — including the pulled-back Roof survey (36 m up). The
		# flat plane just slides under wherever we're looking; collision (around the tower
		# footprint) is unaffected. Fall back to the player XZ if the pivot isn't ready.
		if _site_ground.visible and _site_ground.has_method("recenter_mesh"):
			var anchor: Vector3 = _pivot.global_position if _pivot else (_player.global_position if _player else Vector3.ZERO)
			_site_ground.recenter_mesh(anchor)
	# The placeholder cityscape shows only from the upper floors (so it doesn't
	# clutter the tight iso framing down on the Garden / Utility).
	if _cityscape:
		_cityscape.visible = _current_level >= int(_c.CITY_REVEAL_LEVEL)
	# Light the passive spine-pipe risers on the floors above Utility to match
	# whatever's online down on Floor 0 (Utility) — so an activated utility glows
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


# Drives the visibility of every passive spine-pipe fill (the floors above the
# Utility basement) from the live Floor 0 utility state, so lit risers continue up
# the whole shaft instead of stopping at the floor they were built on. The Utility
# floor (Floor 0) builds its own animated pipes separately; these are the cross-floor copies.
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
	var b: float = 0.0   # 0 = deep interior, 1 = at the wall/threshold; only meaningful on the ground floor
	if _current_level == _SPAWN_LEVEL and _player:
		var half: float = float(_c.FLOOR_3D_SIZE) * 0.5
		var pos: Vector3 = _player.global_position
		var edge_dist: float = maxf(absf(pos.x), absf(pos.z))   # Chebyshev: distance to the nearest wall plane
		b = smoothstep(half * 0.5, half, edge_dist)             # 0 deep interior → 1 at the wall/threshold
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
	# Opening gate (opening_sequence_spec Step 5): the Garden reads UNPOWERED —
	# dim + cool — until the utilities come on. When interiors_unlocked flips true,
	# the per-frame ease below warms it back to full identity: the felt payoff.
	if _current_level == _SPAWN_LEVEL and _gs and not bool(_gs.get("interiors_unlocked")):
		# Fade the unpowered darkening by doorway distance (same `b` as the daylight
		# blend above): 0 at the threshold → no darkening, so the exterior/ground reads
		# the SAME daylight whether you're inside or out; 1 deep inside → full dim+cool.
		# Entering is now a gradient, not a cut to night.
		var d: float = 1.0 - b
		energy *= lerpf(1.0, 0.42, d)
		sun *= lerpf(1.0, 0.30, d)
		amb = (amb as Color).lerp(Color(0.10, 0.12, 0.18), 0.5 * d)
		bg = (bg as Color).lerp(Color(0.03, 0.04, 0.06), 0.55 * d)
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
			node.set_slab_alpha(float(_c.CANOPY_SLAB_ON_ALPHA))
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


# Called by the crane when its drive-off-the-edge plunge gag bottoms out and it
# flashes back to the roof. The player rode the cab the whole way (its own
# physics skipped), so the controller never re-grounded a floor and _current_level
# is still the roof-fall sentinel (-1). Snap the view back to the Roof so the deck,
# the restored beams, and the seated player render normally again.
func recover_from_crane_plunge() -> void:
	_gs.set("roof_falling", false)
	_current_level = _top_level
	_pulse_level = _top_level
	_update(true)


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
	var r: float = float(_c.CANOPY_CEILING_PING_RADIUS)
	var quad := QuadMesh.new()
	quad.size = Vector2(r * 2.0, r * 2.0)
	_wall_glow.mesh = quad
	var sh := Shader.new()
	sh.code = _WALL_BUMP_SHADER
	_wall_glow_mat = ShaderMaterial.new()
	_wall_glow_mat.shader = sh
	var g: Color = _c.CANOPY_GLASS_COLOR
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
	_rollout_elapsed = 0.0
	_rotate_started = false
	_rotate_t = 0.0
	_convo_opened = false
	_convo_yaw = 0.0
	_oneline_said = false
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
	# Transform-owning traversal modes (crane / elevator / vacuum hop). Each owner's
	# _physics_process writes the player's transform every frame while active, so a
	# jump that interrupts one would yank/freeze the player on the target floor. Tell
	# each to release the rider AND clear its flag so the jump lands clean.
	_gs.set("driving_crane", false)
	_gs.set("riding_elevator", false)
	_gs.set("tube_hopping", false)
	_gs.set("in_tube_mouth", false)
	var crane: Node = get_node_or_null("Floors/Roof/Crane")
	if crane and crane.has_method("force_release"):
		crane.force_release()
	var elevator: Node = get_node_or_null("ElevatorPlatform")
	if elevator and elevator.has_method("force_release"):
		elevator.force_release()
	var lift: Node = get_node_or_null("VacuumLift")
	if lift and lift.has_method("force_release"):
		lift.force_release()
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


# World Y of a floor's walkable top surface (slab top). Public so the climbing construction
# worksite (scenes/shared/construction_pit.gd) can ride onto each built floor without
# hardcoding a stacked height (invariant #1).
func floor_top_y(level: int) -> float:
	return _base_y_for_level(level) + float(_c.FLOOR_3D_TOP_Y)


func _name_for_level(level: int) -> String:
	for f in _floors:
		if int(f.level) == level:
			return String(f.name)
	return ""


# The floor node the player is currently on (matches _current_level), or null.
# Public so the floor-agnostic placement verb (iso_player) + the Floor Tools HUD
# can drive the lifecycle on whatever floor the player is standing on.
func current_floor_node() -> Node3D:
	for f in _floors:
		if int(f.level) == _current_level:
			return f.node
	return null
