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
const FLOOR_3D_STORY_HEIGHT := 6.0    # tall floors — room for trees to grow their canopy up onto the floor above
const FLOOR_3D_TOP_Y := FLOOR_3D_SLAB_THICKNESS  # player feet level

# --- Elevator core geometry ----------------------------------------------
# Square footprint with the corners cut at 45° — chamfered into a regular
# octagon-ish shape. The 4 cardinal faces hold sliding doors; the 4
# chamfered corner faces are where the spine pipes run up. Taller than
# the wall trim so the column reads as part of a multi-story shaft.
const ELEVATOR_CHAMFER := 0.7              # cut length on each corner edge
const ELEVATOR_HEIGHT_MULT := 1.45         # × WALL_HEIGHT, extends above ceiling
# Door panel width is half the chamfered side length; spans full elevator
# height; slides outward along the face's tangent axis when opening.
const ELEVATOR_DOOR_THICKNESS := 0.08
const ELEVATOR_DOOR_OPEN_OFFSET := 1.05    # m each panel slides apart
const ELEVATOR_DOOR_OPEN_DURATION := 0.35  # seconds — both directions

# Walls — perimeter framing with translucent window panels.
const WALL_HEIGHT := 5.2    # scaled with the doubled story height so walls/elevator keep their proportions
const WALL_BASE_HEIGHT := 0.6
const WALL_THICKNESS := 0.3
const WALL_POST_SPACING := 4.0           # vertical-post stride along each wall

# Player respawn fail-safe (bug F-005: avoid infinite fall if collision misses).
const PLAYER_FALL_RESPAWN_Y := -3.0   # below Floor 1 (the bottom floor sits at y=0); only fires if you clip out of the building entirely
# Edge-fall: how far you can plunge off an open edge before the game returns you
# to where you jumped from. Operator wants a real fall — the full height of the
# tower, up to 5 floors. Falls that land on a floor below first (e.g. through the
# Canopy tree-hole apertures down to the Arboretum) are NOT caught.
const FALL_CATCH_MAX_FLOORS := 5

# --- Camera (3D orthographic) ---
const CAMERA_TILT_DEG := -30.0          # X rotation: looks down at the floor
# Y rotation default — places the camera at the NW corner looking SE so the
# south-wall seed dispenser is visible front-and-centre on first spawn,
# rather than behind the camera (where 45° put it).
const CAMERA_YAW_DEG_INITIAL := -135.0
const CAMERA_ROTATE_DURATION := 0.2     # seconds per 90° snap
const CAMERA_DISTANCE := 20.0           # camera→pivot distance along its local frame
const CAMERA_ORTHO_SIZE_DEFAULT := 16.0 # initial size (smaller = zoomed in); operator: "a bit closer than now" (was 20)
const CAMERA_ORTHO_SIZE_MIN := 8.0
const CAMERA_ORTHO_SIZE_MAX := 50.0
const CAMERA_ZOOM_FACTOR := 0.9         # mouse wheel multiplier per tick

# --- Living iso camera (follow + juice + survey + traversal reveal) ---------
# The iso camera no longer sits dead at the origin: it softly follows the player,
# leads their motion, reacts to sprint + landings, and pulls back to a diorama on
# arrival / a held survey key or to reveal the floors during vertical travel.
# All magnitudes are tunable knobs so the operator can dial the feel.

# Gentle horizontal follow. The pivot eases toward the player once they drift
# past CAMERA_FOLLOW_DEADZONE from frame centre, leading slightly in their
# direction of travel so you see where you're going. Manual orbit composes on
# top (it rotates around the moving pivot).
const CAMERA_FOLLOW_DEADZONE := 2.0     # m — free movement before the camera starts following
const CAMERA_FOLLOW_RATE := 5.0         # ease rate toward the follow target
const CAMERA_FOLLOW_LEAD_TIME := 0.30   # s of velocity look-ahead (leads the player)
const CAMERA_FOLLOW_LEAD_MAX := 3.5     # m — clamp on the look-ahead offset

# Sprint pull-back — a touch wider while running so speed reads. Additive on top
# of the player's chosen zoom, so manual zoom still wins as the baseline.
const CAMERA_SPRINT_ZOOM_ADD := 2.2     # ortho size added while sprint-moving
const CAMERA_SPRINT_ZOOM_RATE := 3.0

# Landing dip — a quick camera drop on a hard landing for impact. Magnitude
# scales with fall speed; decays fast.
const CAMERA_LAND_KICK_PER_SPEED := 0.022  # m of dip per m/s of downward landing speed
const CAMERA_LAND_KICK_MAX := 0.55         # m — cap on the dip
const CAMERA_LAND_KICK_DECAY := 7.0        # per-second decay of the dip

# Survey / diorama — pull back + flatten to read the whole floor as an object.
# Auto-pulses briefly on floor arrival; held continuously while the survey key
# is down (admire / plan).
const CAMERA_SURVEY_SIZE := 34.0
const CAMERA_SURVEY_TILT_DEG := -25.0
const CAMERA_SURVEY_RATE := 4.0          # ease rate in/out of survey
const CAMERA_ARRIVAL_SURVEY_HOLD := 0.65 # s of auto-survey when you change floors

# Vertical-traversal reveal — widen + lower the angle during a tube hop or an
# elevator ride so you see the floors passing. Between play and survey.
const CAMERA_REVEAL_SIZE := 24.0
const CAMERA_REVEAL_TILT_DEG := -21.0
const CAMERA_REVEAL_RATE := 3.5

# Soft focus (Cody arrival) — pivot eases to a world point + this medium-close zoom.
const CAMERA_FOCUS_SIZE := 12.0
const CAMERA_FOCUS_RATE := 3.0

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
const CAMERA_OTS_TILT_DEG := -8.0     # near-horizontal so you catch the character's own view, not a top-down angle
const CAMERA_OTS_DISTANCE := 7.0
const CAMERA_OTS_SIZE := 5.0
const CAMERA_OTS_HEIGHT_OFFSET := 1.8     # a little above the head, looking out near-level
const CAMERA_OTS_YAW_LERP_RATE := 6.0          # rad/s — how fast pivot yaw chases player facing

# --- Player movement (3D) ---
const PLAYER_MOVE_SPEED := 7.0          # m/s — brisk walk, feels athletic
const PLAYER_SPRINT_MULTIPLIER := 1.75  # held Shift → run at 1.75× walk speed
const PLAYER_GRAVITY := 32.0            # m/s² downward — heavier feel, less floaty
const PLAYER_JUMP_VELOCITY := 10.0      # m/s upward impulse on tap (~1.56 m peak)
const PLAYER_JUMP_VELOCITY_MAX := 24.0  # m/s at full charge → ~9 m, comfortably clears the 6 m story to land through a ring on Floor 4
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

# --- Vacuum tubes (cross-floor conduit + vacuum-lift traversal) ---
# One tube in each of the four floor corners, inset from the wall. The tubes
# now run the FULL height of every floor and tile corner-to-corner up the
# whole stack the way the elevator spine pipes do — each floor renders its own
# one-story segment (shared/vacuum_tube.gd), so stacked they read as four
# continuous columns. Three jobs:
#   1. SELL — on the Garden, dropping a backpack into a tube sends produce down
#      and out into the world for cash (iso_tubes.gd, unchanged).
#   2. ITEM TRANSIT — produce/cargo capsules visibly rise through the columns
#      (vacuum_lift.gd), the cross-floor conduit made literal.
#   3. VACUUM-LIFT HOP — the player presses jump in a tube mouth to get sucked
#      up one floor (hold the down key for a down-hop): a third vertical-
#      traversal method alongside the elevator (multi-floor ride) and the
#      3<->4 stairs, scoped to exactly ±1 floor.
const VACUUM_TUBE_INSET := 1.8           # m from the inside of the wall, into the floor
const VACUUM_TUBE_RADIUS := 0.55         # m — translucent vertical cylinder
const VACUUM_TUBE_HEIGHT := FLOOR_3D_STORY_HEIGHT   # one story so segments tile floor-to-floor
const VACUUM_TUBE_INTERACT_RADIUS := 1.6 # m — slightly larger than DISPENSER for forgiveness
# Sell economics. v1: cash awarded equals the carried sell value (sum of
# plant values from PLANT_TYPES). Future tiers can multiply by a floor-
# specific buyer markup, time-of-day, etc.
const TUBE_SELL_VALUE_MULTIPLIER := 1.0

# Vacuum-lift hop. The player must be grounded and within HOP_MOUTH_RADIUS (XZ)
# of a corner tube; jump = up one floor, jump while holding move_down = down one
# floor. The lift owns the player's transform for HOP_DURATION (a quick suction
# snap, NOT a slow elevator ride), lerping them to the destination floor's
# surface; the tower tracks _current_level during the hop so the destination
# slab is solid on arrival (same class of fix as the elevator ride — F-022).
const VACUUM_HOP_MOUTH_RADIUS := 0.85    # m — how close to the tube centre counts as "in the mouth"
const VACUUM_HOP_DURATION := 0.22        # s — suction-snap travel time for one floor
const VACUUM_HOP_BOTTOM_LEVEL := 0       # lowest floor the lift serves (Utility basement)
const VACUUM_HOP_TOP_LEVEL := 6          # highest floor the lift serves (the Roof/Vista is tube-reachable)

# Item-transit capsules — small produce blobs that rise through a corner tube
# on the player's current floor, the cross-floor conduit made visible. Purely
# cosmetic; spawned on a randomised cadence and freed at the ceiling.
const VACUUM_TRANSIT_INTERVAL_MIN := 2.2   # s — min gap between transit capsules
const VACUUM_TRANSIT_INTERVAL_MAX := 5.5   # s — max gap
const VACUUM_TRANSIT_RISE_SPEED := 5.0     # m/s — how fast a capsule rises the tube

# --- Sky Lounge: look-out-the-window POV camera + placeholder cityscape ------
# Walk up to a Sky Lounge window and press E to "look out": the camera drops to a
# third-person POV just over/behind the player's head (you see the back of the
# head). DRAG the mouse to free-look any direction; the character's body + head
# turn to face where you're looking — you're in the body, not through the eyes.
# A perspective camera while looking out (the rest of the game is orthographic),
# for a real sense of looking OUT into depth. Esc/E eases back to iso.
const LOOKOUT_WINDOW_RADIUS := 3.2     # m — how close to a wall offers the look-out
const LOOKOUT_EASE_RATE := 6.0         # ease speed INTO the POV pose (exponential)
const LOOKOUT_EXIT_DUR := 0.35         # s — fixed-duration ease BACK (always completes → restores ortho)
const LOOKOUT_FOV := 68.0              # perspective fov (deg) while looking out
const LOOKOUT_HEAD_Y := 1.5            # m — head anchor height above the player's feet
const LOOKOUT_BACK_DIST := 2.4         # m — camera behind the head along the look dir
const LOOKOUT_HEIGHT := 0.7            # m — camera above the head (over-the-head read)
const LOOKOUT_YAW_SENS := 0.0065       # rad per pixel of horizontal drag
const LOOKOUT_PITCH_SENS := 0.005      # rad per pixel of vertical drag
const LOOKOUT_PITCH_MIN := -1.0        # look-down clamp (rad)
const LOOKOUT_PITCH_MAX := 1.15        # look-up clamp (rad)
const LOOKOUT_KEY_YAW_RATE := 1.5      # rad/s — Q/R look fallback (no mouse)
const LOOKOUT_KEY_PITCH_RATE := 1.1    # rad/s — up/down arrow look fallback
const LOOKOUT_HEAD_PITCH_MUL := 0.55   # how much the head tilts with look pitch
const LOOKOUT_REENTER_COOLDOWN := 0.45 # s before the look-out can re-arm after exit

# Placeholder cityscape — a ring of distant blocky buildings on a ground plane,
# seen out the Sky Lounge glass. Throwaway: a real skyline is the worldbuilding
# phase. Revealed only on the upper floors (>= LOOKOUT level) so it doesn't
# clutter the tight iso framing down on the Garden / Utility.
const CITY_REVEAL_LEVEL := 4           # show the cityscape from this floor up
const CITY_RING_INNER := 48.0          # m — nearest buildings start out here
const CITY_RING_OUTER := 95.0          # m — furthest buildings
const CITY_RING_COUNT := 64            # number of buildings in the ring
const CITY_GROUND_Y := -2.0            # world y of the city ground plane
const CITY_HEIGHT_MIN := 6.0
const CITY_HEIGHT_MAX := 30.0          # shorter than the tower, so you look DOWN onto them
const CITY_RNG_SEED := 20260601        # fixed so the skyline layout is stable across runs

# --- Time-of-day (day/night cycle) --------------------------------------
# Normalized 0..1: 0.0/1.0 = midnight, 0.25 = dawn (~06:00), 0.5 = noon,
# 0.75 = dusk (~18:00). The TimeOfDay clock derives this from the monotonic
# sim clock (GameState.sim_time_msec) wrapped by DAY_LENGTH, so sim_speed stays
# the GLOBAL time-scale knob. Dawn/dusk windows are for the Stage-3 lighting
# modulation (soft, overlapping bands — gradients, not switches).
const DAY_LENGTH_MSEC := 240000.0      # one full day/night cycle (~4 min) in sim-ms
const CLOCK_START_FRAC := 7.0 / 24.0   # the clock latches on at ~07:00 (morning) at TEMPORAL
const DAWN_CENTER := 0.25              # sun rising
const DUSK_CENTER := 0.75              # sun setting
const TWILIGHT_HALF_WIDTH := 0.07      # half-width of each dawn/dusk transition band

# --- Boot / exterior opening (GameDirector EMPTY_LOT) --------------------
# The game's new front door: a stand-alone empty lot you open on, in-world
# inside tower.tscn (no scene swap). BOOT_TO_EXTERIOR picks the START STATE —
# real opening boots onto the lot; the dev fallback boots straight to the
# Garden so existing-floor work still launches in one step.
const BOOT_TO_EXTERIOR := true
const LOT_CENTER := Vector3(40.0, 0.0, 0.0)  # staged clear of the tower stack (which sits at x~0)
const LOT_SIZE := 24.0                        # m — dirt plane side length
const LOT_GROUND_Y := 0.0                     # top surface = player feet datum
const LOT_DIRT_COLOR := Color(0.33, 0.26, 0.19)
# Five helper names offered at the HIRE_PARTNER beat. Placeholder flavour names —
# the hire has no mechanical consequence; rename freely (worldbuilding is Q-005).
const PARTNER_NAMES := ["MARA", "TOBIN", "REESE", "IRIS", "VANCE"]

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
		# Floor pipe Manhattan route — list of waypoints. Each adjacent pair
		# is one axis-aligned segment, lateral first then longitudinal.
		"route": [Vector2(-9.4, -9.4), Vector2(-1.65, -9.4), Vector2(-1.65, -1.65)],
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
		"route": [Vector2(7.5, -9.4), Vector2(1.65, -9.4), Vector2(1.65, -1.65)],
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
		"route": [Vector2(7.5, 7.5), Vector2(1.65, 7.5), Vector2(1.65, 1.65)],
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
		"route": [Vector2(-9.4, 7.5), Vector2(-1.65, 7.5), Vector2(-1.65, 1.65)],
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
		"route": [Vector2(0.0, -5.6), Vector2(1.65, -5.6), Vector2(1.65, -1.65)],
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
		"route": [Vector2(0.0, 5.6), Vector2(-1.65, 5.6), Vector2(-1.65, 1.65)],
	},
]

# Source / pipe / activation timing knobs.
const SOURCE_INTERACT_RADIUS := 1.7
const SOURCE_CONNECT_DURATION := 0.6     # tap-E lay-pipe animation
const SOURCE_ACTIVATE_DURATION := 0.7    # tap-E activate animation
const SPINE_PIPE_FILL_DURATION := 1.4    # bottom-up fill after activate
const FLOOR_PIPE_BRIGHT_DURATION := 0.5  # cold→bright after activate
const FLOOR_PIPE_BASE_Y := 0.05          # height above slab
const FLOOR_PIPE_HEIGHT := 0.18          # vertical thickness of pipe boxes
# Pipe-to-corner mapping. The elevator core has four 45° chamfered corners;
# six pipes distribute as 1-2-1-2 across them. Each entry is [corner, slot]
# where corner ∈ {NW, NE, SE, SW} and slot is the index within that corner
# (0 if alone, 0 or 1 if shared with a sibling).
const FLOOR_1_PIPE_CORNERS := {
	"water":      ["NW", 0],
	"power":      ["NE", 0],
	"waste":      ["NE", 1],
	"atmosphere": ["SE", 0],
	"data":       ["SW", 0],
	"cargo":      ["SW", 1],
}
# Counts per corner (computed implicitly above, restated for the builder).
const FLOOR_1_CORNER_COUNTS := {"NW": 1, "NE": 2, "SE": 1, "SW": 2}
# Brightness multipliers per source state on the source body and the
# floor pipe albedo. Cold dim, primed mid-pulse, active full bright.
const SOURCE_PRIMED_MULT := 0.78
const SOURCE_ACTIVE_MULT := 1.10
const FLOOR_PIPE_COLD_MULT := 0.42
const FLOOR_PIPE_BRIGHT_MULT := 1.05

# Source body bounding box (brief: 0.7 × 0.7 × 1.0).
const FLOOR_1_SOURCE_SIZE := Vector3(0.7, 1.0, 0.7)
# Cold (pre-connect) brightness multiplier on each source's base color.
const FLOOR_1_SOURCE_COLD_MULT := 0.42
# Spine pipe geometry — six vertical pipes attached to the south face of the
# central elevator/spine column.
const FLOOR_1_SPINE_PIPE_RADIUS := 0.10
# Run the spine pipes the FULL height of the elevator core (one story) so they
# read as continuous risers and tile floor-to-floor up the shaft, instead of
# stopping partway up the column.
const FLOOR_1_SPINE_PIPE_BASE_Y := 0.0
const FLOOR_1_SPINE_PIPE_TOP_Y := FLOOR_3D_STORY_HEIGHT

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


# --- Floor 3-4 (Arboretum) -------------------------------------------------
# Floor 3 (Arboretum ground): edge-only plots, central elevator + spiral
# staircase, water + sunlight sources. Floor 4 (Canopy deck): same footprint
# with holes cut in the slab above every tree plot AND a full annular hole
# for the staircase to emerge through. Trees grow continuously, height up to
# two stories so the crown fills Floor 4. Phase 2 wires planting + growth.

const ARBORETUM_HEADER_AMBER := Color(0.95, 0.86, 0.55, 0.95)
const ARBORETUM_AMBIENT_TINT := Color(0.62, 0.72, 0.66, 1.0)   # green-tinted ambient
const ARBORETUM_SKYLIGHT_COLOR := Color(1.0, 0.96, 0.84, 1.0)
const ARBORETUM_SKY_BG := Color(0.06, 0.10, 0.08, 1.0)

# Every-other-edge-cell pattern — every second plot in a 1-cell-deep ring
# just inside the perimeter walls is a tree plot. With GARDEN_GRID_SIZE = 30
# this yields ~52 plots (every second along each side, four corners trimmed
# to avoid double-counting).
const ARBORETUM_EDGE_INSET := 2                              # cells inside the wall (offset from the glass so crowns clear it)
const ARBORETUM_PLOT_STRIDE := 3                             # every third cell — room for crowns to spread without overlapping
const ARBORETUM_PLOT_TINT := Color(0.22, 0.30, 0.20)         # tilled green-brown
const ARBORETUM_PLOT_HOLE_TINT := Color(0.08, 0.10, 0.08)    # rim around Floor 4 holes
const ARBORETUM_PLOT_HOLE_RADIUS := 0.36                     # m — (legacy) small rim radius, superseded by FLOOR_4_TREE_HOLE_RADIUS
const FLOOR_4_TREE_HOLE_RADIUS := 1.5                        # m — open radius per tree so the whole crown clears the slab

# --- Straight stairs (Floor 3 ↔ Floor 4) -----------------------------------
# Simple straight inclined ramp going south from the elevator's south face,
# climbing FLOOR_3D_STORY_HEIGHT (3 m) in STAIRCASE_RUN (5.5 m) — a ~28°
# slope that the CharacterBody3D walks up smoothly. Replaces the v1/v2
# spiral, which was over-engineered AND hard to navigate (rotating
# segments left collision gaps + the camera-relative input mapping
# disagreed with the spiral's curving heading).
#
# At the top of the stairs on Floor 3 sits an Area3D that scene-swaps to
# Floor 4. Floor 4 has the matching bottom-of-stairs trigger zone — the
# player walks "down" past it to scene-swap back.
const STAIRCASE_RUN := 10.0                           # m — horizontal length (longer to climb the 6 m story at a walkable ~31° slope)
const STAIRCASE_WIDTH := 1.6                          # m — walkable width
const STAIRCASE_THICKNESS := 0.12                     # m — ramp slab thickness
const STAIRCASE_BOTTOM_Z := 3.8                       # m — ramp base, pushed south of the elevator so there's room to walk onto it
const STAIRCASE_STEP_COUNT := 14                      # visible step risers on top (no collision)
const STAIRCASE_TREAD_COLOR := Color(0.55, 0.42, 0.30)
const STAIRCASE_TREAD_EMISSION := Color(0.10, 0.07, 0.04)
const STAIRCASE_RISER_COLOR := Color(0.22, 0.16, 0.12)
const STAIRCASE_RAIL_COLOR := Color(0.32, 0.28, 0.22)

# Trigger zone radius around the top-of-stairs world point that fires the
# scene swap. Player enters → scene_change_to_file.
const STAIRCASE_TRIGGER_RADIUS := 1.2

# Floor 4 slab rectangular hole where the straight staircase passes through.
# Tiles whose centres fall inside (abs(x) <= W/2 + margin) AND
# (FLOOR_4_STAIRWELL_Z_MIN <= z <= FLOOR_4_STAIRWELL_Z_MAX) are skipped so the
# descending staircase is visible from Floor 4 as an open stairwell.
const FLOOR_4_STAIRWELL_HALF_WIDTH := STAIRCASE_WIDTH * 0.5 + 0.1
const FLOOR_4_STAIRWELL_Z_MIN := 3.2                          # just south of elevator
const FLOOR_4_STAIRWELL_Z_MAX := STAIRCASE_BOTTOM_Z + STAIRCASE_RUN - 0.1  # cuts off before stair top so the player lands on solid slab

# --- Floor 4 slab tiling ---------------------------------------------------
# Floor 4's slab is built tile-by-tile (vs. Floor 3's single BoxMesh) so the
# tree holes + staircase annulus + central elevator footprint can all be
# punched out. Tile is the GARDEN_PLOT_SIZE grid.
const FLOOR_4_TILE_INSET_GAP := 0.006                        # m — thin gaps so the glass-floor grid is subtle, not distracting
const FLOOR_4_SLAB_VISUAL_THICKNESS := 0.20                  # m — tile MESH depth (restored; the thin GAP, not thin tiles, keeps the grid subtle)

# Canopy glass — the Floor 4 slab + aperture rings read as glass so the player
# can (a) see the rings from below to aim jumps through them, and (b) get a
# translucent "ceiling pulse" when they bonk their head on the slab from below.
const FLOOR_4_GLASS_COLOR := Color(0.80, 0.86, 0.92)         # white-with-a-little-grey
const FLOOR_4_RING_ALPHA := 0.28                             # rings always faintly visible from below (aim targets)
const FLOOR_4_SLAB_ON_ALPHA := 0.70                          # glass-floor opacity while standing ON Floor 4
const FLOOR_4_CEILING_PULSE_ALPHA := 0.45                    # peak slab glass when you hit the ceiling from below
const FLOOR_4_CEILING_PULSE_DECAY := 2.5                     # per-second fade of the bonk pulse
const FLOOR_4_CEILING_PING_RADIUS := 2.6                     # m — radius of the localized glass glow where you bonk the ceiling

# --- Arboretum trees -------------------------------------------------------
# Trees plant on Floor 3 edge plots and grow continuously over
# TREE_GROWTH_DURATION_MS to maturity. Two varieties (visual only, no
# mechanical difference) alternate on plant so the floor reads as a mixed
# arboretum. Mature trees span two stories — the trunk passes through the
# Floor 4 slab hole and the crown emerges above. Phase 2A: plant + grow.
# Phase 2B will add the water + sunlight gating that the user designed.
const TREE_GROWTH_DURATION_MS := 120_000                     # 120 s, plant → mature (sim clock)
const TREE_PLANT_INTERACT_RADIUS := 1.1                      # m — player → edge-plot distance
const TREE_FLOOR_4_VISIBLE_THRESHOLD := 0.55                 # growth_t at which canopy starts to read on F4

# Developmental growth (Phase B). The reveal shader eases each vertex from its
# baked growth-origin over `span` once `growth` passes the vertex's birth time.
const TREE_REVEAL_SPAN := 0.24                               # reveal duration per element, in growth units
const TREE_WIND_STRENGTH := 0.035                            # ambient sway amplitude (real-time, not sim-time)
const TREE_SPROUT_STAGGER_MS := 1200                         # batch ripple offset between consecutive plantings

# Trunk + crown waypoints. Tweened linearly between MIN and MAX from
# growth_t = 0 → 1. Mature trunk height (4.5 m) is well above one
# story (3 m), so the canopy sits cleanly above Floor 4's slab.
const TREE_TRUNK_HEIGHT_MIN := 0.4
const TREE_TRUNK_HEIGHT_MAX := 9.0    # tall enough that mature crowns clear the 6 m canopy floor
const TREE_CROWN_DIAMETER_MIN := 0.25
const TREE_CROWN_DIAMETER_MAX := 2.4
const TREE_TRUNK_RADIUS_MIN := 0.045
const TREE_TRUNK_RADIUS_MAX := 0.28    # sturdier trunks to match the taller trees

# Growth-curve shaping. Default = saturating exponential (fast early progress,
# graceful plateau, fits the 60 s budget):
#   growth = (1 - exp(-K*u)) / (1 - exp(-K))
# The Gompertz constants below are the alternate establishment-lag (true
# sigmoid) feel; ArboretumTree.growth_t_for() documents how to swap them in.
const TREE_GROWTH_CURVE_K := 3.5
const TREE_GOMPERTZ_B := 4.0
const TREE_GOMPERTZ_C := 5.0

# Max trunk/crown lean tilt (degrees) at lean gene = 1.0. Auto-clamped further
# at runtime so a leaning trunk still clears the Floor 4 canopy hole.
const TREE_LEAN_MAX_DEG := 12.0

# HUD-only stage names for the per-tree growth readout (Phase 2B HUD).
const TREE_STAGE_NAMES := ["sapling", "young", "maturing", "mature"]

# --- Label3D auto-scaling --------------------------------------------------
# Base pixel_size values picked so labels read at consistent on-screen height
# regardless of camera zoom. The LabelScaler module multiplies these by
# (current ortho_size / CAMERA_ORTHO_SIZE_DEFAULT) each frame.
#
# Effective height on a 1080p display at default zoom:
#   font_size × base_px × 1080 / CAMERA_ORTHO_SIZE_DEFAULT
#   e.g. 96 × 0.014 × 1080 / 40 = ~36 px for the "E" prompt.
const LABEL_BASE_PX_BIG := 0.014       # primary letter prompts (E, P)
const LABEL_BASE_PX_MID := 0.014       # main label lines ("Travel to X", chooser items)
const LABEL_BASE_PX_SMALL := 0.011     # hints like "[ESC] cancel"
