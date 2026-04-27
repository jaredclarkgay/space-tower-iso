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

# --- 3D world scale (Phase 3) ---
# Each block in the sim is 2 m wide along X, 4 m deep along Z. Floor slab is
# 0.2 m thick; one floor "story" is 3 m tall. Player walks on top of the slab.
const BLOCK_3D_W := 2.0
const BLOCK_3D_D := 4.0
const FLOOR_3D_SLAB_THICKNESS := 0.2
const FLOOR_3D_STORY_HEIGHT := 3.0
const FLOOR_3D_TOP_Y := FLOOR_3D_SLAB_THICKNESS  # player feet level

# Total floor extent
const FLOOR_3D_WIDTH := float(BLOCKS_PER_FLOOR) * BLOCK_3D_W   # 12 * 2 = 24 m

# --- Camera (3D orthographic) ---
const CAMERA_TILT_DEG := -30.0          # X rotation: looks down at the floor
const CAMERA_YAW_DEG_INITIAL := 45.0    # Y rotation default
const CAMERA_ROTATE_DURATION := 0.2     # seconds per 90° snap
const CAMERA_ORTHO_SIZE_DEFAULT := 14.0 # initial size (smaller = zoomed in)
const CAMERA_ORTHO_SIZE_MIN := 6.0
const CAMERA_ORTHO_SIZE_MAX := 36.0
const CAMERA_ZOOM_FACTOR := 0.9         # mouse wheel multiplier per tick

# --- Player movement (3D) ---
const PLAYER_MOVE_SPEED := 4.0          # m/s

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
