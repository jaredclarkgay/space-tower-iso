extends Node3D

# Floor 4 — Canopy deck. The upper half of the Arboretum. The slab is
# built tile-by-tile so we can punch holes in three regions:
#   1. Central square ±ELEVATOR_RADIUS — the elevator shaft passes through.
#   2. Annular ring along STAIRCASE_HOLE_INNER_RADIUS..STAIRCASE_HOLE_OUTER_RADIUS
#      — the spiral staircase emerges from below.
#   3. Edge tree plots (every-other-cell at ARBORETUM_EDGE_INSET from each
#      wall) — mature tree crowns rise through these in Phase 2.
#
# Floor 4 has NO elevator stop. The elevator visually continues up through
# this floor's hole but doesn't open here. The ONLY way to reach Floor 4
# is to walk up the spiral stairs from Floor 3 (this is the architectural
# meaning of the floor — a private, elevated space accessible only on foot).
#
# Phase 1 (this commit): scaffold, slab with all holes pre-cut, walls and
# extension grid match the floor below, passive elevator shaft + spine pipes
# visible through the central hole. Trees, skylight panel, planting all
# Phase 2.

const FloorChrome = preload("res://scenes/shared/floor_chrome.gd")

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

@export var player_path: NodePath
var _player: Node3D

# Edge plot world positions (where tree-holes go). Same algorithm as Floor 3
# so the holes align perfectly with the tree positions one story below.
var _tree_hole_positions: Array = []


func _ready() -> void:
	if not player_path.is_empty():
		_player = get_node_or_null(player_path)

	_compute_tree_hole_positions()
	_build_tiled_slab_with_holes()
	FloorChrome.build_walls(self, _c)
	FloorChrome.build_extension_grid(self, _c)
	# Elevator core is visible (passes through this floor's hole) but the
	# handler is NOT instanced — Floor 4 has no elevator stop. The pipes
	# still render so the architectural continuity reads.
	var elev_data: Dictionary = FloorChrome.build_elevator_core(self, _c)
	FloorChrome.build_passive_spine_pipes(self, _c, _gs, elev_data)


# Computes Floor-3-edge-plot positions (mirrors floor_3.gd._compute_edge_plots).
# Stored so _build_tiled_slab_with_holes knows which tiles to skip so tree
# crowns can emerge through. Must match the algorithm in floor_3.gd exactly.
func _compute_tree_hole_positions() -> void:
	_tree_hole_positions.clear()
	var grid: int = int(_c.GARDEN_GRID_SIZE)
	var plot: float = float(_c.GARDEN_PLOT_SIZE)
	var inset: int = int(_c.ARBORETUM_EDGE_INSET)
	var stride: int = int(_c.ARBORETUM_PLOT_STRIDE)
	var half: float = grid * plot * 0.5

	var side_indices := [inset, grid - 1 - inset]
	for perp in side_indices:
		var perp_world: float = -half + (perp + 0.5) * plot
		for x in range(inset, grid - inset, stride):
			var x_world: float = -half + (x + 0.5) * plot
			_tree_hole_positions.append(Vector3(x_world, _c.FLOOR_3D_TOP_Y, perp_world))
	for perp2 in side_indices:
		var perp_world2: float = -half + (perp2 + 0.5) * plot
		for z in range(inset + stride, grid - inset - stride + 1, stride):
			var z_world: float = -half + (z + 0.5) * plot
			_tree_hole_positions.append(Vector3(perp_world2, _c.FLOOR_3D_TOP_Y, z_world))


# Builds the slab as one StaticBody3D with N child tile collision shapes.
# Tiles inside any of the three skip regions are omitted. A subtle dark rim
# is drawn around each tree hole so the player can read where canopies
# will emerge in Phase 2.
func _build_tiled_slab_with_holes() -> void:
	var grid: int = int(_c.GARDEN_GRID_SIZE)
	var plot: float = float(_c.GARDEN_PLOT_SIZE)
	var half: float = grid * plot * 0.5
	var slab_thickness: float = float(_c.FLOOR_3D_SLAB_THICKNESS)
	var elev_radius_m: float = float(_c.ELEVATOR_RADIUS) * plot  # ±2 m
	var hole_inner_r: float = float(_c.STAIRCASE_HOLE_INNER_RADIUS)
	var hole_outer_r: float = float(_c.STAIRCASE_HOLE_OUTER_RADIUS)
	var tree_hole_r: float = float(_c.ARBORETUM_PLOT_HOLE_RADIUS)
	var tile_inset: float = float(_c.FLOOR_4_TILE_INSET_GAP)
	var slab_color: Color = Color(0.32, 0.36, 0.30)
	var tile_mat := StandardMaterial3D.new()
	tile_mat.albedo_color = slab_color
	tile_mat.roughness = 0.85
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = _c.ARBORETUM_PLOT_HOLE_TINT
	rim_mat.roughness = 0.95

	var body := StaticBody3D.new()
	body.name = "TiledSlabBody"
	add_child(body)

	for ix in range(grid):
		for iz in range(grid):
			var x_world: float = -half + (ix + 0.5) * plot
			var z_world: float = -half + (iz + 0.5) * plot
			# Skip 1: central elevator footprint.
			if abs(x_world) <= elev_radius_m and abs(z_world) <= elev_radius_m:
				continue
			# Skip 2: staircase annulus.
			var r_tile: float = sqrt(x_world * x_world + z_world * z_world)
			if r_tile >= hole_inner_r and r_tile <= hole_outer_r:
				continue
			# Skip 3: tree-hole tiles (each tree gets one missing tile).
			var is_tree_tile: bool = false
			for hole_pos in _tree_hole_positions:
				if abs(hole_pos.x - x_world) < 0.5 * plot and abs(hole_pos.z - z_world) < 0.5 * plot:
					is_tree_tile = true
					break
			if is_tree_tile:
				# Draw a thin dark rim mesh where the hole sits so the
				# player can read where a tree canopy will emerge in Phase 2.
				_build_tree_hole_rim(body, x_world, z_world, tree_hole_r, plot, rim_mat)
				continue

			var tile_mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(plot - tile_inset, slab_thickness, plot - tile_inset)
			tile_mesh.mesh = box
			tile_mesh.material_override = tile_mat
			tile_mesh.position = Vector3(x_world, -slab_thickness * 0.5, z_world)
			body.add_child(tile_mesh)

			var col := CollisionShape3D.new()
			var col_shape := BoxShape3D.new()
			col_shape.size = Vector3(plot - tile_inset, slab_thickness, plot - tile_inset)
			col.shape = col_shape
			col.position = Vector3(x_world, -slab_thickness * 0.5, z_world)
			body.add_child(col)


# Builds a thin dark ring around a tree-hole position to read as a fitted
# rim on the slab. Annulus from tree_hole_r to ~0.48 * plot (just inside
# the missing tile's outer edge).
func _build_tree_hole_rim(body: StaticBody3D, x_world: float, z_world: float,
		inner_r: float, plot: float, mat: StandardMaterial3D) -> void:
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = inner_r
	torus.outer_radius = inner_r + 0.10
	torus.rings = 24
	torus.ring_segments = 8
	rim.mesh = torus
	rim.material_override = mat
	rim.position = Vector3(x_world, 0.015, z_world)
	# TorusMesh lies flat on XZ by default — no rotation needed.
	body.add_child(rim)
