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

# --- Player movement (3D) ---
const PLAYER_MOVE_SPEED := 7.0          # m/s — brisk walk, feels athletic
const PLAYER_SPRINT_MULTIPLIER := 1.75  # held Shift → run at 1.75× walk speed
const PLAYER_GRAVITY := 32.0            # m/s² downward — heavier feel, less floaty
const PLAYER_JUMP_VELOCITY := 10.0      # m/s upward impulse on tap (~1.56 m peak)
const PLAYER_JUMP_VELOCITY_MAX := 20.0  # m/s upward impulse at full charge (4× height)
const PLAYER_JUMP_CHARGE_DURATION := 1.0  # seconds of held Space to reach max
const PLAYER_LAND_SQUASH_DURATION := 0.16 # seconds of squash on landing
const PLAYER_VISUAL_CROUCH_SCALE := 0.62  # visual.scale.y at full charge
const PLAYER_VISUAL_LAND_SCALE := 0.82    # visual.scale.y at landing peak

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
# Starter garden is now a contiguous circular region around the elevator —
# every cell within STARTER_GARDEN_RADIUS (in grid units) is planted, every
# cell outside is left empty for the player to plant into. Voronoi cluster
# assignment still applies inside the ring for natural patch shapes. Radius
# is tuned so the ring's area minus the elevator footprint ≈ 30% of the
# floor (matches the original auto-fill density).
const STARTER_GARDEN_RADIUS := 9.5
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
# stock low, making them feel earned. Halved from the v1 values — the original
# numbers read as a wall of seeds at game start; this trims the initial supply
# while keeping the relative scarcity gradient intact.
const SEED_MAX_STOCK := {
	"tomato": 20,
	"pumpkin": 15,
	"pepper": 12,
	"cucumber": 10,
	"blueberries": 8,
	"eggplant": 3,
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
