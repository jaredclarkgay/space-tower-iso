extends Node

# Constants for the iso vertical slice. Mirrors naming from sibling
# space-tower/autoloads/constants.gd so a future merge stays sane, but pares
# everything outside slice scope (no economy, no NPCs, no modules).

# --- Tower geometry (carry forward from sibling for cross-repo coherence) ---
const NUM_FLOORS := 10
const BLOCKS_PER_FLOOR := 12
const BLOCK_WIDTH := 180
const FLOOR_HEIGHT := 144
const FLOOR_SLAB := 4

# --- Iso projection ---
# Phase 2 architecture: 3D scene graph viewed through an orthographic
# Camera3D rotated -30° X / 45° Y. The 2:1 dimetric look is a property of the
# camera angles, not of explicit tile dimensions. ISO_TILE_W/H kept for any
# 2D HUD/minimap work that wants pixel-clean iso math.
const ISO_TILE_W := 64
const ISO_TILE_H := 32

# --- 3D world scale (Phase 3, post-iteration) ---
# The iso slice deviates from the sibling 2D sim's 12-block-per-floor
# convention: the operator asked for a square Garden floor with a 20×20 plot
# grid and a centered elevator shaft. BLOCKS_PER_FLOOR (above) and
# BLOCK_WIDTH/FLOOR_HEIGHT (above, 2D pixel values) are kept for sibling
# parity but unused in the iso scene; iso geometry uses the GARDEN_* and
# FLOOR_3D_* constants below.
const GARDEN_GRID_SIZE := 30             # plots per side; operator: +2 pane-units → +8 plots/side
const GARDEN_PLOT_SIZE := 1.0            # metres per plot
const ELEVATOR_RADIUS := 2               # plot cells from grid center on each axis
const FLOOR_3D_SIZE := float(GARDEN_GRID_SIZE) * GARDEN_PLOT_SIZE    # 20 m
const FLOOR_3D_SLAB_THICKNESS := 0.2
const FLOOR_3D_STORY_HEIGHT := 3.0
const FLOOR_3D_TOP_Y := FLOOR_3D_SLAB_THICKNESS  # player feet level

# Walls — perimeter framing with translucent window panels.
const WALL_HEIGHT := 2.6
const WALL_BASE_HEIGHT := 0.6
const WALL_THICKNESS := 0.3
const WALL_POST_SPACING := 4.0           # vertical-post stride along each wall

# Player respawn fail-safe (bug F-005: avoid infinite fall if collision misses).
const PLAYER_FALL_RESPAWN_Y := -10.0

# --- Camera (3D orthographic) ---
const CAMERA_TILT_DEG := -30.0          # X rotation: looks down at the floor
# Y rotation default — places the camera at the NW corner looking SE so the
# south-wall seed dispenser is visible front-and-centre on first spawn,
# rather than behind the camera (where 45° put it).
const CAMERA_YAW_DEG_INITIAL := -135.0
const CAMERA_ROTATE_DURATION := 0.2     # seconds per 90° snap
const CAMERA_DISTANCE := 20.0           # camera→pivot distance along its local frame
const CAMERA_ORTHO_SIZE_DEFAULT := 40.0 # initial size (smaller = zoomed in); fits 30×30 floor
const CAMERA_ORTHO_SIZE_MIN := 8.0
const CAMERA_ORTHO_SIZE_MAX := 50.0
const CAMERA_ZOOM_FACTOR := 0.9         # mouse wheel multiplier per tick

# Dialogue close-up: when the Cody chat panel opens, the camera tweens to
# look at the midpoint between player and Cody at this tight ortho size.
const CAMERA_DIALOGUE_FOCUS_SIZE := 7.0
const CAMERA_DIALOGUE_FOCUS_DURATION := 0.6   # seconds for tween in/out
const CAMERA_DIALOGUE_ORBIT_RATE := 0.15      # rad/s; slow steady camera orbit during chat

# --- Camera modes (toggleable from the HUD) ---
# ISO is the default free-pan iso view. PROFILE is a perpendicular side-on
# follow-cam that locks its yaw at mode-entry so the player can move through
# the frame. OTS is a tight chase cam behind the player that lerps to follow
# their facing. All non-iso modes track the player's world position and ignore
# pan + rotate input (zoom still works).
const CAMERA_MODE_ISO := "iso"
const CAMERA_MODE_PROFILE := "profile"
const CAMERA_MODE_OTS := "ots"

const CAMERA_MODE_TWEEN_DURATION := 0.45      # seconds for transition between modes

# PROFILE preset — slight downward tilt, mid-tight zoom, side-on framing.
const CAMERA_PROFILE_TILT_DEG := -8.0
const CAMERA_PROFILE_DISTANCE := 9.0
const CAMERA_PROFILE_SIZE := 8.0
const CAMERA_PROFILE_HEIGHT_OFFSET := 1.0     # raise pivot to player's chest

# OTS preset — over-the-shoulder, very close, tracks facing yaw.
const CAMERA_OTS_TILT_DEG := -25.0
const CAMERA_OTS_DISTANCE := 7.0
const CAMERA_OTS_SIZE := 5.0
const CAMERA_OTS_HEIGHT_OFFSET := 1.4
const CAMERA_OTS_YAW_LERP_RATE := 6.0          # rad/s — how fast pivot yaw chases player facing

# --- Player movement (3D) ---
const PLAYER_MOVE_SPEED := 7.0          # m/s — brisk walk, feels athletic
const PLAYER_SPRINT_MULTIPLIER := 1.75  # held Shift → run at 1.75× walk speed
const PLAYER_GRAVITY := 32.0            # m/s² downward — heavier feel, less floaty
const PLAYER_JUMP_VELOCITY := 10.0      # m/s upward impulse on tap (~1.56 m peak)
const PLAYER_JUMP_VELOCITY_MAX := 20.0  # m/s upward impulse at full charge (4× height)
const PLAYER_JUMP_CHARGE_DURATION := 1.0  # seconds of held Space to reach max
const PLAYER_LAND_SQUASH_DURATION := 0.32 # seconds of squash on landing — longer
                                           # so the bounce reads as a real beat
const PLAYER_VISUAL_CROUCH_SCALE := 0.62  # visual.scale.y at full charge
const PLAYER_VISUAL_LAND_SCALE := 0.65    # visual.scale.y at landing peak — deeper

# --- Plant growth + harvest lifecycle ---
# 5 visible growth stages (sprout → ready). Total growth time across the
# stages = GROWTH_TOTAL_DURATION (30 s, so 6 s per stage). After harvest the
# plot enters a "fresh dirt" stage for POST_HARVEST_DURATION (10 s) before
# the next sprout. Player presses+holds E to harvest; HARVEST_DURATION
# seconds of unmoving hold completes the harvest.
const GROWTH_STAGE_COUNT := 5
const GROWTH_TOTAL_DURATION := 30.0
const GROWTH_STAGE_DURATION := GROWTH_TOTAL_DURATION / float(GROWTH_STAGE_COUNT)
const POST_HARVEST_DURATION := 10.0
const HARVEST_DURATION := 0.25            # quick but the bar visibly plays — a real beat
const HARVEST_RADIUS := 1.2
const HARVEST_KNEEL_SCALE_Y := 0.55

# Plant types — each plot is randomly assigned one. Drives the prompt
# text, fruit-accent colour at stage 5, foliage tint at every stage,
# AND a ROYGBV value/scarcity/grow-rate gradient:
#   - Red end of the spectrum: cheap, fast-growing, common.
#   - Violet end: 3× more valuable than the tier below, slowest grow,
#     rarest spawn (~10% of plots).
# `seed_count` is how many Voronoi seeds this type plants in the grid:
# more seeds → bigger area / more common. `grow_multiplier` scales both
# GROWTH_STAGE_DURATION and POST_HARVEST_DURATION so a Violet plant takes
# 3× longer per stage and 3× longer to regrow after harvest.
const PLANT_TYPES := [
	{
		"name": "Tomato",
		"fruit_color": Color(0.85, 0.25, 0.20),
		"foliage_color": Color(0.42, 0.62, 0.28),
		"value": 1,
		"grow_multiplier": 1.0,
		"seed_count": 5,
	},
	{
		"name": "Pumpkin",
		"fruit_color": Color(0.95, 0.45, 0.10),
		"foliage_color": Color(0.40, 0.52, 0.22),
		"value": 1,
		"grow_multiplier": 1.0,
		"seed_count": 4,
	},
	{
		"name": "Pepper",
		"fruit_color": Color(1.00, 0.78, 0.15),
		"foliage_color": Color(0.52, 0.65, 0.28),
		"value": 2,
		"grow_multiplier": 1.2,
		"seed_count": 3,
	},
	{
		"name": "Cucumber",
		"fruit_color": Color(0.65, 0.85, 0.25),
		"foliage_color": Color(0.40, 0.55, 0.30),
		"value": 3,
		"grow_multiplier": 1.1,
		"seed_count": 3,
	},
	{
		"name": "Blueberries",
		"fruit_color": Color(0.30, 0.45, 0.85),
		"foliage_color": Color(0.30, 0.50, 0.40),
		"value": 5,
		"grow_multiplier": 1.3,
		"seed_count": 3,
	},
	{
		"name": "Eggplant",
		"fruit_color": Color(0.60, 0.20, 0.75),
		"foliage_color": Color(0.32, 0.40, 0.32),
		"value": 15,
		"grow_multiplier": 1.5,    # 1.5× → 60 s full cycle, "a full minute to regrow"
		"seed_count": 2,
	},
]

# --- Helper robot (Roomba MK1) -----------------------------------------------
# Earned after the player manually harvests this many plants. On unlock the
# robot appears beside the elevator awaiting activation. After E-press the
# robot snake-scans the field row-by-row, harvesting stage-5 plots one by
# one until its hopper fills; the player walks over and presses E again to
# collect, which empties the hopper into food_count and the robot resumes.
# Long-term: this state machine is the place LLM-driven directives would
# plug in (override target plot, override pattern, etc.).
const ROBOT_UNLOCK_THRESHOLD := 10        # plants_harvested needed to unlock Cody
const ROBOT_SPEED := 2.0                  # m/s — slower than the player
const ROBOT_HARVEST_DURATION := 0.83      # seconds at each plot — operator: 3× faster (was 2.5)
const ROBOT_CAPACITY := 30                # plots before pickup needed (operator: 3× of 10)
const ROBOT_INTERACT_RADIUS := 1.5        # m — player must be this close
const ROBOT_REACH_DISTANCE := 0.7         # m — robot stops to harvest at this distance

# --- Tuck-and-flip (triggered above a charge threshold) ---
# Charge threshold expressed as a fraction of PLAYER_JUMP_CHARGE_DURATION;
# 0.3 corresponds to ~1.3× tap-jump velocity (10 + 0.3 × (20-10) = 13 m/s).
# Rotation rate is *derived per-jump* from the expected airtime so the flip
# completes exactly TUCK_FLIP_ROTATIONS turns in one hop. See iso_player.gd.
const TUCK_FLIP_CHARGE_THRESHOLD := 0.3
const TUCK_FLIP_ROTATIONS := 1.0          # full forward rotations per jump

# --- Extension grid (faint blueprint-style hint that tower could expand) ---
# Grid unit = one floor's story height (FLOOR_3D_STORY_HEIGHT = 3 m). Each
# perpendicular line extends 2 units (6 m) outward from the wall, solid for
# the first 1 unit (3 m) and fading to 0 alpha across the second unit.
# The perpendicular crossbar runs at distance 1 unit from the wall.
const EXTENSION_GRID_UNIT := FLOOR_3D_STORY_HEIGHT  # 3 m — one floor height
const EXTENSION_GRID_LENGTH := 2.0 * EXTENSION_GRID_UNIT          # 6 m
const EXTENSION_LINE_SOLID_LENGTH := 1.0 * EXTENSION_GRID_UNIT    # 3 m
const EXTENSION_LINE_PEAK_ALPHA := 0.30   # very subtle even at full opacity
const EXTENSION_PANE_COUNT := 6           # extension lines per side; positions computed at runtime

# --- Crop planting v1 (player-driven planting loop) -------------------------
# The grid no longer auto-fills end-to-end. A starter garden seeds ~30% of
# plots via the existing Voronoi pattern; the remaining ~70% are tilled
# empty plots the player plants into using seeds dispensed by the perimeter
# dispenser. Total density is conserved relative to the old auto-fill so the
# floor doesn't read sparse on first arrival.
# Starter garden is a contiguous circular region around the elevator — every
# cell within STARTER_GARDEN_RADIUS (in grid units) is planted, every cell
# outside is left empty for the player to plant into. Voronoi cluster
# assignment still applies inside the ring for natural patch shapes. Halved
# from the v1 radius (was 9.5 → ~265 cells planted) so the player has more
# empty land to expand into; area scales with R², so √(9.5² / 2) ≈ 6.72.
const STARTER_GARDEN_RADIUS := 6.7
const STARTER_STAGE_MIN := 2               # mature mix so the floor reads alive
const STARTER_STAGE_MAX := 5

# Empty plot visuals — sunken brown soil with thin parallel furrow lines.
const EMPTY_PLOT_SOIL_COLOR := Color(0.22, 0.15, 0.10)   # darker than PLANTER_SOIL
const EMPTY_PLOT_FURROW_COLOR := Color(0.16, 0.10, 0.07) # darker still
const EMPTY_PLOT_RECESS := 0.04            # how much lower than a planted plot's top
const EMPTY_PLOT_FURROW_COUNT := 3
const EMPTY_PLOT_FURROW_THICKNESS := 0.025
const EMPTY_PLOT_FURROW_DEPTH := 0.012     # how deep each furrow line cuts visually

# Seed type order — the canonical mapping for number-key selection 1..6 and
# for any code that iterates seed types in display order.
const SEED_TYPE_ORDER: Array = [
	"tomato", "pumpkin", "pepper", "cucumber", "blueberries", "eggplant",
]

# Per-type dispenser stocking. Common types refill fast and stock high so the
# player essentially always has them; rare types (eggplant) refill slowly and
# stock low, making them feel earned.
const SEED_MAX_STOCK := {
	"tomato": 40,
	"pumpkin": 30,
	"pepper": 25,
	"cucumber": 20,
	"blueberries": 15,
	"eggplant": 5,
}

const SEED_REFILL_SECONDS := {
	"tomato": 5.0,
	"pumpkin": 8.0,
	"pepper": 12.0,
	"cucumber": 20.0,
	"blueberries": 30.0,
	"eggplant": 60.0,
}

const DISPENSER_STARTS_FULL := true
const DISPENSER_INTERACT_RADIUS := 1.6     # m — slightly larger than ROBOT_INTERACT_RADIUS
# Placed against the south interior wall, directly south of the elevator core,
# so the player exits the elevator and walks straight to it. Local front face
# is at -Z, which points toward the room interior (north) at yaw=0.
const DISPENSER_POSITION := Vector3(0.0, 0.0, 14.0)
const DISPENSER_FACING_YAW := 0.0

# Plant verb (P) — kneel-press-stand and a sprout emerge tween. Player input
# is locked during the kneel; the sprout grows from scale-zero to stage-1 size
# over SPROUT_EMERGE_DURATION immediately after the kneel completes.
const PLANT_DURATION := 0.5
const SPROUT_EMERGE_DURATION := 1.0
const PLANT_KNEEL_SCALE_Y := 0.55          # mirrors HARVEST_KNEEL_SCALE_Y for visual parity

# --- Slice scope ---
const GARDEN_FLOOR_INDEX := 2  # Floor 3, 0-indexed (the Garden of Eden)

# --- Player backpack ---
# Cap on how many veggies (plant count, not value) the player can carry. The
# backpack mesh on the player's torso scales with fill, and harvest is blocked
# when at cap — forcing the player to offload via a vacuum tube before they
# can keep picking. Cody's hopper-collect is also gated on this.
const BACKPACK_CAPACITY := 20

# --- Vacuum tubes (cross-floor item conduit) ---
# One tube in each of the four floor corners, inset from the wall. Each tube
# has a DOWN port (always active — items go down through Floor 1 and out
# into the world for cash) and an UP port (only active if a floor exists
# above the current one; on Floor 2 the up port is sealed). The tubes are
# the standard cross-floor mechanic; every floor will have them.
const VACUUM_TUBE_INSET := 1.8           # m from the inside of the wall, into the floor
const VACUUM_TUBE_RADIUS := 0.55         # m — translucent vertical cylinder
const VACUUM_TUBE_HEIGHT := 3.0          # m — full story height, visible top to bottom
const VACUUM_TUBE_INTERACT_RADIUS := 1.6 # m — slightly larger than DISPENSER for forgiveness
const VACUUM_TUBE_HAS_FLOOR_ABOVE := false  # Floor 2 (Garden) has no Floor 3 yet — operator
                                            # is building Floor 1 elsewhere; up tubes seal.
# Sell economics. v1: cash awarded equals the carried sell value (sum of
# plant values from PLANT_TYPES). Future tiers can multiply by a floor-
# specific buyer markup, time-of-day, etc.
const TUBE_SELL_VALUE_MULTIPLIER := 1.0

# --- Floor 1 (utility / infrastructure floor under the Garden) -----------
# Operator's renumber: Garden = Floor 2, Floor 1 = utility floor below.
# Footprint matches the Garden (FLOOR_3D_SIZE = 30 m, same walls + extension
# grid) so floors read as the same building viewed at different stories.
# 6 lanes — water, power, atmosphere, data, waste, cargo — feed up the
# central elevator/spine; the cargo lane is bidirectional (sells produce
# down, delivers supplies up to Garden corner tubes). Tap-E throughout.
const FLOOR_1_CAMERA_TILT_DEG := -30.0
const FLOOR_1_CAMERA_YAW_DEG := -135.0
const FLOOR_1_CAMERA_DISTANCE := 20.0
# Match the Garden's default — operator: "1st floor also looks a lot smaller
# than the second". Same scene size with the same ortho framing reads as
# the same building.
const FLOOR_1_CAMERA_ORTHO_SIZE := 40.0

# Master breaker — south wall, inset from the corner. Position scaled from
# the brief's (9.7, 14) on a 0..16 grid to fit the 30×30 floor centred at
# the origin: (9.7 × 30/16 − 15, 0, 14 × 30/16 − 15) ≈ (3.2, 0, 11.25).
const MASTER_BREAKER_POSITION := Vector3(3.2, 0.0, 11.25)
const MASTER_BREAKER_INTERACT_RADIUS := 1.7
const MASTER_BREAKER_PULL_DURATION := 0.5    # tap-E animation length
const ROOM_LIGHT_FADE_DURATION := 0.7
const FLOOR_1_DARK_AMBIENT_MULT := 0.32      # boosted from 0.18 — operator
                                              # said the room was unreadable
                                              # at full-dark; this still feels
                                              # "before lights on" but the
                                              # walls + character are visible.
const FLOOR_1_LIT_AMBIENT_MULT := 1.0

# Emergency lighting that's always on, even before the master breaker is
# pulled, so the room reads as "low-light maintenance lighting" rather than
# "void". One overhead OmniLight3D at the room centre, plus soft warm
# spotlights on the player and the breaker for legibility.
const FLOOR_1_EMERGENCY_OMNI_ENERGY := 0.55
const FLOOR_1_EMERGENCY_OMNI_RANGE := 18.0
const FLOOR_1_PLAYER_SPOT_ENERGY := 1.4
const FLOOR_1_BREAKER_SPOT_ENERGY := 2.4

# Floor 1 utility systems. Six lanes feed the central elevator/spine —
# water/power/atmosphere/data/waste are utility upflow, cargo is bidirectional
# (sells produce out, delivers supplies up to Garden corner tubes).
# Positions scaled from the brief's 0..16 grid to the 30×30 floor centred at
# the origin: world_pos = (brief_pos × 30 / 16) − (15, 15). Cargo placed
# south-of-centre, mirroring waste north-of-centre.
const FLOOR_1_SYSTEMS := [
	{
		"id": "water",
		"name": "Water",
		"position": Vector3(-9.4, 0.0, -9.4),
		"base_color": Color(0.227, 0.561, 0.784),
		"glow_color": Color(0.494, 0.765, 0.929),
		"disc_desc": "Glass intake. Cold pump. No pipe to the spine yet.",
		"connected_desc": "Pipe laid. The wheel valve still needs turning.",
		"online_desc": "Water pressure equalized. Feeds the spine.",
		"connect_verb": "lay the pipe",
		"activate_verb": "open the valve",
		"mechanical_detail": "wheel_valve",
		"pipe_index": 0,
		"pipe_width": 0.16,
	},
	{
		"id": "power",
		"name": "Power",
		"position": Vector3(7.5, 0.0, -9.4),
		"base_color": Color(0.910, 0.565, 0.188),
		"glow_color": Color(1.000, 0.722, 0.400),
		"disc_desc": "Copper core. Three knife switches in series. No conduit run.",
		"connected_desc": "Conduit linked. The knife switches wait to be thrown.",
		"online_desc": "Mains armed. Copper conducts.",
		"connect_verb": "run the conduit",
		"activate_verb": "throw the switches",
		"mechanical_detail": "knife_switches",
		"pipe_index": 1,
		"pipe_width": 0.16,
	},
	{
		"id": "atmosphere",
		"name": "Atmosphere",
		"position": Vector3(7.5, 0.0, 7.5),
		"base_color": Color(0.565, 0.596, 0.627),
		"glow_color": Color(0.804, 0.835, 0.863),
		"disc_desc": "A blower the size of a refrigerator. Ducting still detached.",
		"connected_desc": "Ducting joined. The big red button waits.",
		"online_desc": "Air handler spooled. Ducts breathing.",
		"connect_verb": "join the ducts",
		"activate_verb": "press ignition",
		"mechanical_detail": "fan_button",
		"pipe_index": 2,
		"pipe_width": 0.22,
	},
	{
		"id": "data",
		"name": "Data",
		"position": Vector3(-9.4, 0.0, 7.5),
		"base_color": Color(0.365, 0.753, 0.376),
		"glow_color": Color(0.573, 0.878, 0.510),
		"disc_desc": "Server rack. Cold. No fiber to the spine.",
		"connected_desc": "Fiber bundle joined. The rack is ready to boot.",
		"online_desc": "Backbone online. Bits flowing up.",
		"connect_verb": "pull the fiber",
		"activate_verb": "boot the rack",
		"mechanical_detail": "led_grid",
		"pipe_index": 3,
		"pipe_width": 0.14,
	},
	{
		"id": "waste",
		"name": "Waste",
		"position": Vector3(0.0, 0.0, -5.6),
		"base_color": Color(0.816, 0.345, 0.267),
		"glow_color": Color(0.941, 0.518, 0.439),
		"disc_desc": "Cast-iron drain. Sluice gate up. Outflow not tied in yet.",
		"connected_desc": "Drain tied in. The sluice lever still in the up position.",
		"online_desc": "Drainage open. Gravity does the rest.",
		"connect_verb": "tie in the drain",
		"activate_verb": "open the sluice",
		"mechanical_detail": "sluice_lever",
		"pipe_index": 4,
		"pipe_width": 0.20,
	},
	{
		"id": "cargo",
		"name": "Cargo",
		"position": Vector3(0.0, 0.0, 5.6),
		"base_color": Color(0.722, 0.451, 0.200),
		"glow_color": Color(0.918, 0.659, 0.345),
		"disc_desc": "Pneumatic cargo line. Up-tubes upstairs not routed; out-tube to the world is open but unloaded.",
		"connected_desc": "Cargo loop spliced. The dispatcher console waits to be flipped.",
		"online_desc": "Cargo flowing both ways. Up-tubes feed; down-tubes sell.",
		"connect_verb": "splice the cargo line",
		"activate_verb": "flip the dispatcher",
		"mechanical_detail": "dispatcher_panel",
		"pipe_index": 5,
		"pipe_width": 0.20,
	},
]

# Source body bounding box (brief: 0.7 × 0.7 × 1.0).
const FLOOR_1_SOURCE_SIZE := Vector3(0.7, 1.0, 0.7)
# Cold (pre-connect) brightness multiplier on each source's base color.
const FLOOR_1_SOURCE_COLD_MULT := 0.42
# Spine pipe geometry — six vertical pipes attached to the south face of the
# central elevator/spine column.
const FLOOR_1_SPINE_PIPE_RADIUS := 0.10
const FLOOR_1_SPINE_PIPE_BASE_Y := 0.30
const FLOOR_1_SPINE_PIPE_TOP_Y := 2.5

# --- Garden visual signature (drives iso_floor.gd in Phase 3) ---
# Sources: docs/space-tower-project-knowledge-v3.md,
# docs/player-journey-map-v3-final.html (step 07 "The Garden of Eden")
const WATER_PIPE_COLOR := Color(0.3, 0.6, 1.0, 0.4)   # translucent blue
const GROW_LIGHT_COLOR := Color(1.0, 0.8, 0.2, 0.8)   # warm amber
const PLANTER_GREEN    := Color(0.4, 0.65, 0.3)
const PLANTER_SOIL     := Color(0.32, 0.22, 0.16)

# --- Camera ---
const CAMERA_ZOOM_MIN := 0.5
const CAMERA_ZOOM_MAX := 3.0
const CAMERA_ZOOM_STEP := 0.1

# --- Block predicates (carry semantics from sibling for parity if Phase 3
# decides to render window/elevator gaps in the iso floor) ---
func is_win_block(bi: int) -> bool:
	return bi in [3, 7, 11]

func is_elev_block(bi: int) -> bool:
	return bi == 6

func is_buildable(bi: int) -> bool:
	return not is_win_block(bi) and not is_elev_block(bi)


# Map a lowercase seed key (matches SEED_TYPE_ORDER) to the corresponding
# PLANT_TYPES dictionary. Returns {} if the seed key is unknown.
func plant_type_by_seed(seed_key: String) -> Dictionary:
	var capitalized: String = seed_key.capitalize()
	for t in PLANT_TYPES:
		if t.name == capitalized:
			return t
	return {}
