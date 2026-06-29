extends Node3D

# Floor 3 — Canopy deck. The upper half of the Arboretum. Its slab is built
# tile-by-tile with holes punched for the elevator shaft, the stairwell, and a
# generous disc per edge tree plot (the Floor 2 trees grow up through these).
#
# In the stacked tower this node lives at world y = (3-1)*STORY_HEIGHT; geometry
# is built in LOCAL space (slab top at local y=0). The trees + the staircase are
# single physical objects owned by Floor 2 that pass up through here.
#
# Floor 3's pieces are split so the tower controller can treat the slab as a
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
const VacuumTube = preload("res://scenes/shared/vacuum_tube.gd")

# Ceiling-bonk glow: a radial Gaussian falloff so the impact reads as a soft
# feathered halo, not a hard-edged disc. `intensity` (0..1) drives both the alpha
# and the emissive punch; the falloff fades to ~0 by the quad edge (circular).
const CEILING_PING_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec3 glow_color : source_color = vec3(0.8, 0.86, 0.92);
uniform float intensity = 0.0;
void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;          // 0 center -> 1 at the edge midpoint
	float a = exp(-d * d * 3.5);                       // soft Gaussian bell
	a *= 1.0 - smoothstep(0.7, 1.0, d);               // guarantee 0 by the quad edge
	ALBEDO = glow_color;
	EMISSION = glow_color * mix(0.4, 2.0, clamp(intensity, 0.0, 1.0));
	ALPHA = clamp(a, 0.0, 1.0) * clamp(intensity, 0.0, 1.0);
}
"""

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

# Edge plot positions (where tree-holes go). Same algorithm as Floor 2 so the
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
var _ceiling_ping_mat: ShaderMaterial
# Aperture rings — only shown from the floor directly below (aim targets) or on
# the Canopy itself; hidden from further down so they don't float overhead.
var _rings_node: Node3D

# Construction-assembly state. The Canopy is too special for the FloorConstruction
# manifest (glass-ceiling slab the tower drives), so it implements the same small
# assembler interface itself: prime_collapsed / play_sequence / is_complete /
# approx_duration. Assembly is 2-phase — the deck tiles sweep in, then the gated
# structure (walls / core / risers / tubes / grid) grows up. Tuned by the same
# CONSTRUCT_* constants as the other floors, so the feel stays consistent.
var _assembled: bool = true


func _ready() -> void:
	_compute_tree_hole_positions()

	_structure = Node3D.new()
	_structure.name = "Structure"
	add_child(_structure)
	FloorChrome.build_walls(_structure, _c)
	FloorChrome.build_extension_grid(_structure, _c)
	var elev_data: Dictionary = FloorChrome.build_elevator_core(_structure, _c)
	FloorChrome.build_passive_spine_pipes(_structure, _c, _gs, elev_data)
	# Corner vacuum tubes — the Canopy is no longer the top (the Vista is above),
	# so its tubes stay open and tile up into the Roof's. Built into the gated
	# structure so they hide/show with the rest of the Canopy chrome.
	VacuumTube.build_corner_tubes(_structure, _c, false)

	# The glass slab + aperture rings stay as direct (always-visible) children.
	_build_tiled_slab_with_holes()


# Hides/shows the walls + elevator structure (the slab + rings are handled
# separately so they can read as a glass ceiling/aim-target from below).
func set_structure_visible(v: bool) -> void:
	if _structure:
		_structure.visible = v


# --- Construction assembler interface (matches FloorConstruction) -----------

# Collapse the deck tiles + structure to their pre-grow state (no rebuild) so the
# Canopy doesn't flash full when it's revealed in the build flow.
func prime_collapsed() -> void:
	_assembled = false
	var cs: float = float(_c.CONSTRUCT_TILE_COLLAPSE)
	if _tiles_node:
		for t in _tiles_node.get_children():
			if t is MeshInstance3D:
				t.scale = Vector3(cs, cs, cs)
	if _structure:
		_structure.scale.y = float(_c.CONSTRUCT_GROW_EPSILON)


func is_complete() -> bool:
	return _assembled


func approx_duration() -> float:
	return float(_c.CONSTRUCT_SLAB_SWEEP_DUR) + float(_c.CONSTRUCT_STEP_DUR) \
		+ 2.0 * float(_c.CONSTRUCT_STEP_GAP)


# Two-phase assembly: the glass deck prints in from the centre, then the gated
# structure grows up out of it. Animates the already-built pieces (no rebuild).
func play_sequence() -> void:
	# Phase 1 — deck tiles sweep in, staggered by distance from the centre.
	if _tiles_node:
		var tiles: Array = _tiles_node.get_children()
		var max_d: float = 0.001
		for t in tiles:
			max_d = maxf(max_d, Vector2(t.position.x, t.position.z).length())
		var sweep: float = float(_c.CONSTRUCT_SLAB_SWEEP_DUR)
		var pop: float = float(_c.CONSTRUCT_SLAB_TILE_POP)
		for t in tiles:
			if not (t is MeshInstance3D):
				continue
			var d: float = Vector2(t.position.x, t.position.z).length()
			var tw := create_tween()
			tw.tween_interval((d / max_d) * sweep)
			tw.tween_property(t, "scale", Vector3.ONE, pop).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(sweep + pop + 0.02).timeout
	await get_tree().create_timer(float(_c.CONSTRUCT_STEP_GAP)).timeout
	# Phase 2 — the structure grows up out of the deck.
	if _structure:
		_structure.scale.y = float(_c.CONSTRUCT_GROW_EPSILON)
		var tw2 := create_tween()
		tw2.tween_property(_structure, "scale:y", 1.0, float(_c.CONSTRUCT_STEP_DUR)) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		await tw2.finished
	_assembled = true


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
	_ceiling_ping_mat.set_shader_parameter("intensity", clampf(intensity, 0.0, 1.0))
	var s: float = lerpf(0.85, 1.0, intensity)
	_ceiling_ping.scale = Vector3(s, 1.0, s)


func _build_ceiling_ping() -> void:
	_ceiling_ping = MeshInstance3D.new()
	_ceiling_ping.name = "CeilingPing"
	# A flat quad carrying the radial-falloff shader (XZ plane, faces up toward the
	# iso camera). Sized to the ping radius; the shader feathers within it.
	var r: float = float(_c.CANOPY_CEILING_PING_RADIUS)
	var quad := PlaneMesh.new()
	quad.size = Vector2(r * 2.0, r * 2.0)
	_ceiling_ping.mesh = quad
	var sh := Shader.new()
	sh.code = CEILING_PING_SHADER
	_ceiling_ping_mat = ShaderMaterial.new()
	_ceiling_ping_mat.shader = sh
	var glass: Color = _c.CANOPY_GLASS_COLOR
	_ceiling_ping_mat.set_shader_parameter("glow_color", Vector3(glass.r, glass.g, glass.b))
	_ceiling_ping_mat.set_shader_parameter("intensity", 0.0)
	_ceiling_ping.material_override = _ceiling_ping_mat
	_ceiling_ping.visible = false
	add_child(_ceiling_ping)


# Computes Floor-3-edge-plot positions (mirrors arboretum_ground.gd._compute_edge_plots).
func _compute_tree_hole_positions() -> void:
	_tree_hole_positions.clear()
	var grid: int = int(_c.GARDEN_GRID_SIZE)
	var plot: float = float(_c.GARDEN_PLOT_SIZE)
	var inset: int = int(_c.ARBORETUM_EDGE_INSET)
	var stride: int = int(_c.ARBORETUM_PLOT_STRIDE)
	var half: float = grid * plot * 0.5
	# Keep holes off the corner vacuum tubes — must match Floor 2's plot exclusion
	# exactly, or the Canopy would have an empty hole at each corner tube (and the
	# player would drop through it when hopping up the tube). 2 m clearance.
	var tube_anchors: Array = VacuumTube.corner_anchors(_c)

	var side_indices := [inset, grid - 1 - inset]
	for perp in side_indices:
		var perp_world: float = -half + (perp + 0.5) * plot
		for x in range(inset, grid - inset, stride):
			var x_world: float = -half + (x + 0.5) * plot
			var wp := Vector3(x_world, _c.FLOOR_3D_TOP_Y, perp_world)
			if not _near_any_tube(wp, tube_anchors, 2.0):
				_tree_hole_positions.append(wp)
	for perp2 in side_indices:
		var perp_world2: float = -half + (perp2 + 0.5) * plot
		for z in range(inset + stride, grid - inset - stride + 1, stride):
			var z_world: float = -half + (z + 0.5) * plot
			var wp2 := Vector3(perp_world2, _c.FLOOR_3D_TOP_Y, z_world)
			if not _near_any_tube(wp2, tube_anchors, 2.0):
				_tree_hole_positions.append(wp2)


func _near_any_tube(wp: Vector3, tube_anchors: Array, radius: float) -> bool:
	for a in tube_anchors:
		if Vector2(a.x - wp.x, a.z - wp.z).length() < radius:
			return true
	return false


# Builds the slab as one StaticBody3D with N child tile collision shapes.
# Tiles inside any skip region are omitted (player falls through onto Floor 2).
func _build_tiled_slab_with_holes() -> void:
	var grid: int = int(_c.GARDEN_GRID_SIZE)
	var plot: float = float(_c.GARDEN_PLOT_SIZE)
	var half: float = grid * plot * 0.5
	var slab_thickness: float = float(_c.FLOOR_3D_SLAB_THICKNESS)
	var vis_t: float = float(_c.CANOPY_SLAB_VISUAL_THICKNESS)   # thin tile MESH so edges read thin
	var elev_radius_m: float = float(_c.ELEVATOR_RADIUS) * plot  # ±2 m
	var stair_hw: float = float(_c.CANOPY_STAIRWELL_HALF_WIDTH)
	var stair_zmin: float = float(_c.CANOPY_STAIRWELL_Z_MIN)
	var stair_zmax: float = float(_c.CANOPY_STAIRWELL_Z_MAX)
	var tree_hole_r: float = float(_c.CANOPY_TREE_HOLE_RADIUS)
	var tile_inset: float = float(_c.CANOPY_TILE_INSET_GAP)

	# Glass canopy slab — translucent; the tower drives the alpha. Starts
	# invisible (it's a ceiling you only sense by bonking it / the rings).
	var glass: Color = _c.CANOPY_GLASS_COLOR
	_slab_mat = StandardMaterial3D.new()
	_slab_mat.albedo_color = Color(glass.r, glass.g, glass.b, 0.0)
	_slab_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_slab_mat.metallic = 0.0
	_slab_mat.roughness = 0.15

	# Aperture rings — faint glass, always visible so the player can aim jumps
	# up through them from below.
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(glass.r, glass.g, glass.b, float(_c.CANOPY_RING_ALPHA))
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.metallic = 0.0
	ring_mat.roughness = 0.1

	var body := StaticBody3D.new()
	body.name = "TiledSlabBody"
	add_child(body)
	_tiles_node = Node3D.new()
	_tiles_node.name = "Tiles"
	body.add_child(_tiles_node)

	# Invisible shaft grate over the central elevator opening (the Canopy isn't an
	# elevator stop, but you can tube-hop up here and walk to the centre — don't
	# drop down the open shaft). Collision-only, so it never blocks the cabin view;
	# the car (static) + a ride (transform-owned) pass through it freely.
	var grate := CollisionShape3D.new()
	grate.name = "ShaftGrate"
	var grate_shape := BoxShape3D.new()
	grate_shape.size = Vector3(2.0 * elev_radius_m, slab_thickness, 2.0 * elev_radius_m)
	grate.shape = grate_shape
	grate.position = Vector3(0, -slab_thickness * 0.5, 0)
	body.add_child(grate)

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
