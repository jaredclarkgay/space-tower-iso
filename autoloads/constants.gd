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
const GARDEN_GRID_SIZE := 20             # plots per side
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
const CAMERA_YAW_DEG_INITIAL := 45.0    # Y rotation default
const CAMERA_ROTATE_DURATION := 0.2     # seconds per 90° snap
const CAMERA_DISTANCE := 20.0           # camera→pivot distance along its local frame
const CAMERA_ORTHO_SIZE_DEFAULT := 28.0 # initial size (smaller = zoomed in); fits 20×20 floor
const CAMERA_ORTHO_SIZE_MIN := 6.0
const CAMERA_ORTHO_SIZE_MAX := 36.0
const CAMERA_ZOOM_FACTOR := 0.9         # mouse wheel multiplier per tick

# --- Player movement (3D) ---
const PLAYER_MOVE_SPEED := 7.0          # m/s — brisk walk, feels athletic
const PLAYER_GRAVITY := 32.0            # m/s² downward — heavier feel, less floaty
const PLAYER_JUMP_VELOCITY := 10.0      # m/s upward impulse on tap (~1.56 m peak)
const PLAYER_JUMP_VELOCITY_MAX := 20.0  # m/s upward impulse at full charge (4× height)
const PLAYER_JUMP_CHARGE_DURATION := 1.0  # seconds of held Space to reach max
const PLAYER_LAND_SQUASH_DURATION := 0.16 # seconds of squash on landing
const PLAYER_VISUAL_CROUCH_SCALE := 0.62  # visual.scale.y at full charge
const PLAYER_VISUAL_LAND_SCALE := 0.82    # visual.scale.y at landing peak

# --- Extension grid (suggests "tower could keep building outward") ---
const EXTENSION_GRID_LENGTH := 8.0      # m of grid line beyond each floor edge
const EXTENSION_LINE_COLOR := Color(1, 1, 1, 0.55)

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
