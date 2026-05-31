extends Node3D

# Floor 4 — Canopy deck. The upper half of the Arboretum. Its slab is built
# tile-by-tile with holes punched for the elevator shaft, the stairwell, and a
# generous disc per edge tree plot (the Floor 3 trees grow up through these).
#
# In the stacked tower this node lives at world y = (4-1)*STORY_HEIGHT; geometry
# is built in LOCAL space (slab top at local y=0). The trees + the staircase are
# single physical objects owned by Floor 3 that pass up through here.
#
# Floor 4's pieces are split so the tower controller can treat the slab as a
# GLASS CEILING from below:
#   - _structure (walls / elevator / pipes / grid): hidden while the player is
#     on a floor below — gated by set_structure_visible().
#   - the slab (a StaticBody, collision ALWAYS on so you can bonk it from below)
#     uses a glass material whose alpha the tower drives: invisible from below,
#     a translucent "pulse" when you hit your head on it, frosted-glass floor
#     while you stand on it.
#   - the aperture rings use a faint glass material and stay visible always, so
#     from below you can see where to aim a jump through them.

const FloorChrome = preload("res://scenes/shared/floor_chrome.gd")

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

# Edge plot positions (where tree-holes go). Same algorithm as Floor 3 so the
# holes align with the trunks one story below.
var _tree_hole_positions: Array = []

# Gated structure (walls / elevator / spine pipes / extension grid).
var _structure: Node3D
# Shared glass material for the slab tiles — the tower drives its alpha.
var _slab_mat: StandardMaterial3D
# Slab tile MESHES live here so they can be hidden wholesale when the glass is
# invisible (no transparent-pass overdraw); collision + rings stay live.
var _tiles_node: Node3D
# Localized "you bonked the ceiling here" glass glow — a disc moved to the hit
# point and faded by the tower (only a radius around the impact lights up).
var _ceiling_ping: MeshInstance3D
var _ceiling_ping_mat: StandardMaterial3D
# Aperture rings — only shown from the floor directly below (aim targets) or on
# the Canopy itself; hidden from further down so they don't float overhead.
var _rings_node: Node3D


func _ready() -> void:
	_compute_tree_hole_positions()

	_structure = Node3D.new()
	_structure.name = "Structure"
	add_child(_structure)
	FloorChrome.build_walls(_structure, _c)
	FloorChrome.build_extension_grid(_structure, _c)
	var elev_data: Dictionary = FloorChrome.build_elevator_core(_structure, _c)
	FloorChrome.build_passive_spine_pipes(_structure, _c, _gs, elev_data)

	# The glass slab + aperture rings stay as direct (always-visible) children.
	_build_tiled_slab_with_holes()


# Hides/shows the walls + elevator structure (the slab + rings are handled
# separately so they can read as a glass ceiling/aim-target from below).
func set_structure_visible(v: bool) -> void:
	if _structure:
		_structure.visible = v


# Drives the slab glass opacity (0 = invisible ceiling, up to ~0.7 frosted
# glass floor). Collision is unaffected — you always bonk it from below. When
# fully invisible the tile meshes are hidden so they don't sit in the
# transparent pass; the rings + collision stay live.
func set_slab_alpha(a: float) -> void:
	var alpha: float = clampf(a, 0.0, 1.0)
	if _slab_mat:
		_slab_mat.albedo_color.a = alpha
	if _tiles_node:
		_tiles_node.visible = alpha > 0.01


# Shows a soft glass glow on the slab underside at `world_pos`, intensity 0..1
# (0 hides it). Localized — only a radius around the bonk point lights up, so
# hitting your head reads as a specific impact, not the whole floor flashing.
func set_ceiling_ping(world_pos: Vector3, intensity: float) -> void:
	if _ceiling_ping == null:
		_build_ceiling_ping()
	if intensity <= 0.01:
		_ceiling_ping.visible = false
		return
	var lp: Vector3 = to_local(world_pos)
	_ceiling_ping.position = Vector3(lp.x, -0.04, lp.z)
	_ceiling_ping.visible = true
	var glass: Color = _c.FLOOR_4_GLASS_COLOR
	_ceiling_ping_mat.albedo_color = Color(glass.r, glass.g, glass.b, clampf(intensity, 0.0, 1.0))
	_ceiling_ping_mat.emission_energy_multiplier = lerpf(0.4, 2.0, intensity)
	var s: float = lerpf(0.7, 1.0, intensity)
	_ceiling_ping.scale = Vector3(s, 1.0, s)


func _build_ceiling_ping() -> void:
	_ceiling_ping = MeshInstance3D.new()
	_ceiling_ping.name = "CeilingPing"
	var disc := CylinderMesh.new()
	disc.top_radius = float(_c.FLOOR_4_CEILING_PING_RADIUS)
	disc.bottom_radius = float(_c.FLOOR_4_CEILING_PING_RADIUS)
	disc.height = 0.03
	_ceiling_ping.mesh = disc
	_ceiling_ping_mat = StandardMaterial3D.new()
	_ceiling_ping_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ceiling_ping_mat.emission_enabled = true
	_ceiling_ping_mat.emission = _c.FLOOR_4_GLASS_COLOR
	_ceiling_ping.material_override = _ceiling_ping_mat
	_ceiling_ping.visible = false
	add_child(_ceiling_ping)


# Computes Floor-3-edge-plot positions (mirrors floor_3.gd._compute_edge_plots).
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
# Tiles inside any skip region are omitted (player falls through onto Floor 3).
func _build_tiled_slab_with_holes() -> void:
	var grid: int = int(_c.GARDEN_GRID_SIZE)
	var plot: float = float(_c.GARDEN_PLOT_SIZE)
	var half: float = grid * plot * 0.5
	var slab_thickness: float = float(_c.FLOOR_3D_SLAB_THICKNESS)
	var vis_t: float = float(_c.FLOOR_4_SLAB_VISUAL_THICKNESS)   # thin tile MESH so edges read thin
	var elev_radius_m: float = float(_c.ELEVATOR_RADIUS) * plot  # ±2 m
	var stair_hw: float = float(_c.FLOOR_4_STAIRWELL_HALF_WIDTH)
	var stair_zmin: float = float(_c.FLOOR_4_STAIRWELL_Z_MIN)
	var stair_zmax: float = float(_c.FLOOR_4_STAIRWELL_Z_MAX)
	var tree_hole_r: float = float(_c.FLOOR_4_TREE_HOLE_RADIUS)
	var tile_inset: float = float(_c.FLOOR_4_TILE_INSET_GAP)

	# Glass canopy slab — translucent; the tower drives the alpha. Starts
	# invisible (it's a ceiling you only sense by bonking it / the rings).
	var glass: Color = _c.FLOOR_4_GLASS_COLOR
	_slab_mat = StandardMaterial3D.new()
	_slab_mat.albedo_color = Color(glass.r, glass.g, glass.b, 0.0)
	_slab_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_slab_mat.metallic = 0.0
	_slab_mat.roughness = 0.15

	# Aperture rings — faint glass, always visible so the player can aim jumps
	# up through them from below.
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(glass.r, glass.g, glass.b, float(_c.FLOOR_4_RING_ALPHA))
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.metallic = 0.0
	ring_mat.roughness = 0.1

	var body := StaticBody3D.new()
	body.name = "TiledSlabBody"
	add_child(body)
	_tiles_node = Node3D.new()
	_tiles_node.name = "Tiles"
	body.add_child(_tiles_node)

	for ix in range(grid):
		for iz in range(grid):
			var x_world: float = -half + (ix + 0.5) * plot
			var z_world: float = -half + (iz + 0.5) * plot
			# Skip 1: central elevator footprint.
			if abs(x_world) <= elev_radius_m and abs(z_world) <= elev_radius_m:
				continue
			# Skip 2: stairwell rectangle (where the staircase emerges).
			if abs(x_world) <= stair_hw and z_world >= stair_zmin and z_world <= stair_zmax:
				continue
			# Skip 3: open a generous disc around each tree so the WHOLE crown
			# clears the slab, not just the trunk. Aperture rims drawn after.
			var is_tree_hole: bool = false
			for hole_pos in _tree_hole_positions:
				if Vector2(hole_pos.x - x_world, hole_pos.z - z_world).length() < tree_hole_r:
					is_tree_hole = true
					break
			if is_tree_hole:
				continue

			var tile_mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(plot - tile_inset, vis_t, plot - tile_inset)
			tile_mesh.mesh = box
			tile_mesh.material_override = _slab_mat
			tile_mesh.position = Vector3(x_world, -vis_t * 0.5, z_world)
			_tiles_node.add_child(tile_mesh)

			var col := CollisionShape3D.new()
			var col_shape := BoxShape3D.new()
			col_shape.size = Vector3(plot - tile_inset, slab_thickness, plot - tile_inset)
			col.shape = col_shape
			col.position = Vector3(x_world, -slab_thickness * 0.5, z_world)
			body.add_child(col)

	# Aperture rims live under a toggleable node (see set_apertures_visible).
	_rings_node = Node3D.new()
	_rings_node.name = "Rings"
	body.add_child(_rings_node)
	for hole_pos in _tree_hole_positions:
		_build_tree_hole_rim(_rings_node, hole_pos.x, hole_pos.z, tree_hole_r, ring_mat)


# Builds a thin glass ring around a tree-hole position — an aim target visible
# from below.
func _build_tree_hole_rim(parent: Node3D, x_world: float, z_world: float,
		inner_r: float, mat: StandardMaterial3D) -> void:
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = inner_r
	torus.outer_radius = inner_r + 0.12
	torus.rings = 24
	torus.ring_segments = 8
	rim.mesh = torus
	rim.material_override = mat
	rim.position = Vector3(x_world, 0.015, z_world)
	# TorusMesh lies flat on XZ by default — no rotation needed.
	parent.add_child(rim)


# Rings show only from the floor directly below (jump-aim targets) or when on
# the Canopy — not from further down, where they'd float overhead.
func set_apertures_visible(v: bool) -> void:
	if _rings_node:
		_rings_node.visible = v
