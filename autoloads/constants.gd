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

# --- Iso projection (placeholders, refined after Phase 1 research) ---
# Defaults assume 2:1 dimetric. Re-evaluate once iso_research.md lands.
const ISO_TILE_W := 64
const ISO_TILE_H := 32

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
