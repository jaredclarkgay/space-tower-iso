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
const ArboretumTree = preload("res://scenes/shared/arboretum_tree.gd")
const Stairs = preload("res://scenes/shared/stairs.gd")
const LabelScaler = preload("res://scenes/shared/label_scaler.gd")

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

@export var player_path: NodePath
var _player: Node3D

# Edge plot world positions (where tree-holes go). Same algorithm as Floor 3
# so the holes align perfectly with the tree positions one story below.
var _tree_hole_positions: Array = []

# Tree refs rendered on Floor 4 — keyed by plot_key. Floor 4 only shows a
# tree once its growth_t crosses TREE_FLOOR_4_VISIBLE_THRESHOLD (i.e. the
# trunk is tall enough to poke through the slab hole). Below that, the
# tree is on Floor 3 only.
var _tree_refs: Dictionary = {}


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

	# Stairs: same straight staircase, but offset down one story so its
	# top sits exactly at Floor 4's floor level (where the player arrives
	# coming up from Floor 3). The lower portion of the ramp is hidden
	# under Floor 4's slab.
	Stairs.build(self, _c, _c.FLOOR_3D_TOP_Y - _c.FLOOR_3D_STORY_HEIGHT)
	_build_stairs_marker_and_trigger()
	_apply_stairs_arrival()


# Each frame: lazily build tree visuals for any tree whose growth has
# passed TREE_FLOOR_4_VISIBLE_THRESHOLD, and lerp existing trees.
# Trees are positioned with their base offset down by STORY_HEIGHT so
# the part above Floor 4's slab is exactly what's poking above Floor 3.
func _process(_delta: float) -> void:
	var story: float = float(_c.FLOOR_3D_STORY_HEIGHT)
	var threshold: float = float(_c.TREE_FLOOR_4_VISIBLE_THRESHOLD)
	for key in _gs.floor_3.trees:
		var tree: Dictionary = _gs.floor_3.trees[key]
		var growth_t: float = ArboretumTree.growth_t_for(tree, _c)
		if growth_t < threshold:
			# Tree isn't tall enough yet — Floor 4 ignores it.
			if _tree_refs.has(key):
				# Edge case: player rewinds growth (not possible in v1 but
				# defensive). Free + drop ref.
				var stale: Dictionary = _tree_refs[key]
				if stale.root:
					stale.root.queue_free()
				_tree_refs.erase(key)
			continue
		if not _tree_refs.has(key):
			# Build the tree fresh, with base offset down one story so the
			# visible portion above Floor 4's slab matches the upper part
			# of the tree on Floor 3.
			var variety: int = int(tree.get("variety", 0))
			var world_pos: Vector3 = Vector3(tree.get("world_pos", Vector3.ZERO))
			var offset_pos: Vector3 = world_pos + Vector3(0, -story, 0)
			_tree_refs[key] = ArboretumTree.build(self, _c, variety, offset_pos)
		ArboretumTree.update(_tree_refs[key], _c, growth_t)

	_update_label_scale()
	_check_stairs_down_trigger()


# Builds the "↓ STAIRS DOWN" 3D prompt at the top of the descending
# staircase. Always visible — there's no interaction verb, just a wayfinding
# label so the player understands what the stairwell is.
var _stairs_down_label_root: Node3D
var _stairs_down_arrow: Label3D
var _stairs_down_label: Label3D
func _build_stairs_marker_and_trigger() -> void:
	_stairs_down_label_root = Node3D.new()
	_stairs_down_label_root.name = "StairsDownMarker"
	# Position above the stair top (where the player arrives if coming up).
	var top: Vector3 = Stairs.top_world_position(_c, _c.FLOOR_3D_TOP_Y - _c.FLOOR_3D_STORY_HEIGHT)
	_stairs_down_label_root.position = top + Vector3(0, 1.6, 0)
	add_child(_stairs_down_label_root)

	_stairs_down_arrow = Label3D.new()
	_stairs_down_arrow.text = "↓"
	_stairs_down_arrow.font_size = 96
	_stairs_down_arrow.outline_size = 12
	_stairs_down_arrow.modulate = Color(0.95, 0.82, 0.50, 1.0)
	_stairs_down_arrow.outline_modulate = Color(0, 0, 0, 0.92)
	_stairs_down_arrow.pixel_size = 0.014
	_stairs_down_arrow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_stairs_down_arrow.no_depth_test = true
	_stairs_down_arrow.position = Vector3(0, 0.4, 0)
	_stairs_down_label_root.add_child(_stairs_down_arrow)

	_stairs_down_label = Label3D.new()
	_stairs_down_label.text = "Stairs to Arboretum"
	_stairs_down_label.font_size = 44
	_stairs_down_label.outline_size = 8
	_stairs_down_label.modulate = Color(0.96, 0.92, 0.78, 1.0)
	_stairs_down_label.outline_modulate = Color(0, 0, 0, 0.92)
	_stairs_down_label.pixel_size = 0.014
	_stairs_down_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_stairs_down_label.no_depth_test = true
	_stairs_down_label.position = Vector3(0, 0.0, 0)
	_stairs_down_label_root.add_child(_stairs_down_label)


# Polled trigger — fires when the player walks down the visible portion
# of the staircase past the y threshold. Scene swap back to Floor 3 with
# arrived_via_stairs set so Floor 3 puts the player at the matching
# top-of-stairs spot.
func _check_stairs_down_trigger() -> void:
	if _player == null:
		return
	var pos: Vector3 = _player.global_position
	# Must be within the stairwell footprint (x in [-W/2-margin, +W/2+margin],
	# z in [stair_zmin, stair_zmax]).
	var hw: float = float(_c.FLOOR_4_STAIRWELL_HALF_WIDTH)
	var zmin: float = float(_c.FLOOR_4_STAIRWELL_Z_MIN)
	var zmax: float = float(_c.FLOOR_4_STAIRWELL_Z_MAX) + 0.5
	if abs(pos.x) > hw or pos.z < zmin or pos.z > zmax:
		return
	# AND descending past half-story below the Floor 4 surface.
	if pos.y > _c.FLOOR_3D_TOP_Y - 1.0:
		return
	_gs.set("arrived_via_stairs", true)
	get_tree().change_scene_to_file("res://scenes/floor_3/floor_3.tscn")


# Spawns the player at the top of the staircase if they arrived via stairs
# from Floor 3. Called from _ready.
func _apply_stairs_arrival() -> void:
	if not _gs.get("arrived_via_stairs"):
		return
	_gs.set("arrived_via_stairs", false)
	if _player == null:
		return
	# Place the player just south of the stair top so they're cleanly on
	# Floor 4's slab, facing north (back toward the stairwell).
	var top: Vector3 = Stairs.top_world_position(_c, _c.FLOOR_3D_TOP_Y - _c.FLOOR_3D_STORY_HEIGHT)
	_player.global_position = top + Vector3(0, 0.1, 0.6)
	if _player.has_method("set_facing_yaw"):
		_player.set_facing_yaw(PI)   # face north (toward smaller z)


# Per-frame label scaling for the stairs-down marker.
func _update_label_scale() -> void:
	if _stairs_down_label_root == null:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var def: float = float(_c.CAMERA_ORTHO_SIZE_DEFAULT)
	LabelScaler.update(_stairs_down_arrow, _c.LABEL_BASE_PX_BIG, cam, def)
	LabelScaler.update(_stairs_down_label, _c.LABEL_BASE_PX_MID, cam, def)


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
	var stair_hw: float = float(_c.FLOOR_4_STAIRWELL_HALF_WIDTH)
	var stair_zmin: float = float(_c.FLOOR_4_STAIRWELL_Z_MIN)
	var stair_zmax: float = float(_c.FLOOR_4_STAIRWELL_Z_MAX)
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
			# Skip 2: stairwell rectangle (where the descending staircase
			# is visible from above as an open stairwell).
			if abs(x_world) <= stair_hw and z_world >= stair_zmin and z_world <= stair_zmax:
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
