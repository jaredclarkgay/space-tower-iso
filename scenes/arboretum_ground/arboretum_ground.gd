extends Node3D

# Floor 3 — Arboretum (ground level). Edge-only tree plots, central elevator,
# spiral ramp wrapping the elevator that ascends to Floor 4. Cody was
# "built for floor-three operations" per his dialogue tree — this is his
# native floor.
#
# Phase 1 shipped the scaffold (floor + walls + elevator + stairs +
# plot markers). Phase 2A adds:
#   - Plant verb (P) — plant a sapling on the nearest empty edge plot
#   - Two tree varieties (alternating per plant)
#   - 60s continuous growth (no water/sunlight gating yet — Phase 2B)
#   - Tree state persisted in GameState.arboretum.trees so visits to other
#     floors don't reset growth
#   - Cross-floor rendering pattern: both Floor 3 and Floor 4 read the
#     same trees dict; F3 renders trunk-up-from-ground, F4 renders the
#     crown (the part above the slab hole).

const FloorChrome = preload("res://scenes/shared/floor_chrome.gd")
const VacuumTube = preload("res://scenes/shared/vacuum_tube.gd")
const Stairs = preload("res://scenes/shared/stairs.gd")
const ArboretumTree = preload("res://scenes/shared/arboretum_tree.gd")

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

@export var player_path: NodePath
var _player: Node3D

# Geometry data returned by FloorChrome.build_elevator_core. Held for its
# `corners` (spine-pipe mounts); the ride-able car is elevator_platform.gd.
var _elevator_data: Dictionary = {}

# Edge plot entries — each is a Dictionary:
#   {key: "ix,iz", world_pos: Vector3, marker: MeshInstance3D}
# The marker is the dim square that fades out when a tree is planted.
var _edge_plots: Array = []

# Live tree refs, keyed by plot_key. Value = the dict ArboretumTree.build()
# returns ({root, trunk, crown, variety}). Built on _ready for any trees
# already in GameState (returning from another floor) and on plant.
var _tree_refs: Dictionary = {}

# Plant-verb prompt — single Label3D hopping to the nearest empty plot.
var _plant_prompt_root: Node3D
var _plant_prompt_p: Label3D
var _plant_prompt_label: Label3D
# Cached "currently in range" edge plot entry (or null).
var _nearest_empty_plot: Variant = null


func _ready() -> void:
	if not player_path.is_empty():
		_player = get_node_or_null(player_path)

	FloorChrome.build_slab(self, _c, Color(0.34, 0.40, 0.32),
			float(_c.ELEVATOR_RADIUS) * float(_c.GARDEN_PLOT_SIZE))
	FloorChrome.build_walls(self, _c)
	FloorChrome.build_extension_grid(self, _c)
	_elevator_data = FloorChrome.build_elevator_core(self, _c)
	FloorChrome.build_passive_spine_pipes(self, _c, _gs, _elevator_data)
	# Corner vacuum tubes — tile down into the Garden's and up into the Canopy's.
	VacuumTube.build_corner_tubes(self, _c, false)

	# The single physical staircase that spans Floor 3 → Floor 4. Built in
	# Floor 3's frame at y=0 so its base sits FLUSH with the floor slab (no
	# lip to catch on); its top reaches one story up, at Floor 4's surface.
	# In the stacked tower the player just walks up/down it — no scene swap.
	Stairs.build(self, _c, 0.0)

	_compute_edge_plots()
	_render_edge_plot_markers()
	_build_plant_prompt()
	_restore_existing_trees()


func _process(_delta: float) -> void:
	if _player == null:
		return
	_update_plant_prompt()
	_handle_plant_input()
	_update_tree_geometry()
	_update_label_scale()


# Identifies all edge plots — those exactly ARBORETUM_EDGE_INSET cells
# inside the wall — selected at every-other-cell stride along each side.
# Stores entries with {key, world_pos, marker=null} so plant/render code
# can index by key.
func _compute_edge_plots() -> void:
	_edge_plots.clear()
	var grid: int = int(_c.GARDEN_GRID_SIZE)
	var plot: float = float(_c.GARDEN_PLOT_SIZE)
	var inset: int = int(_c.ARBORETUM_EDGE_INSET)
	var stride: int = int(_c.ARBORETUM_PLOT_STRIDE)
	var half: float = grid * plot * 0.5
	# Corner vacuum-tube anchors — keep tree plots clear of them so a tree never
	# grows up through a tube. Skip any plot within this XZ radius of a tube.
	var tube_anchors: Array = VacuumTube.corner_anchors(_c)
	var tube_clear: float = 2.0

	# Top + bottom sides (z fixed; walk x from inset to grid-1-inset).
	for perp in [inset, grid - 1 - inset]:
		var perp_world: float = -half + (perp + 0.5) * plot
		for x in range(inset, grid - inset, stride):
			var x_world: float = -half + (x + 0.5) * plot
			var wp := Vector3(x_world, _c.FLOOR_3D_TOP_Y, perp_world)
			if _near_any_tube(wp, tube_anchors, tube_clear):
				continue
			_edge_plots.append({"key": "%d,%d" % [x, perp], "world_pos": wp, "marker": null})
	# Left + right sides (x fixed; walk z to avoid duplicating corner plots).
	for perp2 in [inset, grid - 1 - inset]:
		var perp_world2: float = -half + (perp2 + 0.5) * plot
		for z in range(inset + stride, grid - inset - stride + 1, stride):
			var z_world: float = -half + (z + 0.5) * plot
			var wp2 := Vector3(perp_world2, _c.FLOOR_3D_TOP_Y, z_world)
			if _near_any_tube(wp2, tube_anchors, tube_clear):
				continue
			_edge_plots.append({"key": "%d,%d" % [perp2, z], "world_pos": wp2, "marker": null})


# True if a plot world position is within `radius` (XZ) of any corner tube.
func _near_any_tube(wp: Vector3, tube_anchors: Array, radius: float) -> bool:
	for a in tube_anchors:
		if Vector2(a.x - wp.x, a.z - wp.z).length() < radius:
			return true
	return false


# Visual marker per edge plot — subtle darker square so the player can
# read planting positions before any sapling is planted. Markers are
# hidden once the corresponding plot gets a tree.
func _render_edge_plot_markers() -> void:
	var plot: float = float(_c.GARDEN_PLOT_SIZE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.32, 0.18)
	mat.roughness = 0.95
	mat.emission_enabled = true
	mat.emission = Color(0.06, 0.12, 0.05)
	mat.emission_energy_multiplier = 0.5
	for entry in _edge_plots:
		var marker := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(plot * 0.85, 0.02, plot * 0.85)
		marker.mesh = box
		marker.material_override = mat
		marker.position = entry.world_pos + Vector3(0, 0.011, 0)
		add_child(marker)
		entry.marker = marker


# Builds the 3D "P / Plant" prompt hovering above whichever empty edge
# plot the player is currently nearest. Same visual language as the
# elevator and master-breaker prompts.
func _build_plant_prompt() -> void:
	_plant_prompt_root = Node3D.new()
	_plant_prompt_root.name = "PlantPrompt"
	_plant_prompt_root.visible = false
	add_child(_plant_prompt_root)

	_plant_prompt_p = Label3D.new()
	_plant_prompt_p.text = "P"
	_plant_prompt_p.font_size = 72
	_plant_prompt_p.outline_size = 10
	_plant_prompt_p.modulate = Color(0.78, 0.95, 0.62, 1.0)
	_plant_prompt_p.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	_plant_prompt_p.pixel_size = 0.008
	_plant_prompt_p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_plant_prompt_p.no_depth_test = true
	_plant_prompt_p.position = Vector3(0, 0.78, 0)
	_plant_prompt_root.add_child(_plant_prompt_p)

	_plant_prompt_label = Label3D.new()
	_plant_prompt_label.text = "Plant sapling"
	_plant_prompt_label.font_size = 40
	_plant_prompt_label.outline_size = 6
	_plant_prompt_label.modulate = Color(0.92, 0.98, 0.85, 1.0)
	_plant_prompt_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	_plant_prompt_label.pixel_size = 0.008
	_plant_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_plant_prompt_label.no_depth_test = true
	_plant_prompt_label.position = Vector3(0, 0.12, 0)
	_plant_prompt_root.add_child(_plant_prompt_label)


# Walks edge plots, picks the nearest unplanted one within
# TREE_PLANT_INTERACT_RADIUS of the player. Updates the prompt's
# position + visibility accordingly.
func _update_plant_prompt() -> void:
	_nearest_empty_plot = null
	# Only interact when the player is actually standing on this floor (not on
	# a floor above it in the stacked tower). Work in this floor's LOCAL frame
	# so the proximity math is agnostic to the floor's vertical offset.
	if not _player_on_this_floor():
		_plant_prompt_root.visible = false
		return
	var player_local: Vector3 = to_local(_player.global_position)
	var best_d2: float = float(_c.TREE_PLANT_INTERACT_RADIUS) ** 2
	for entry in _edge_plots:
		if _gs.arboretum.trees.has(entry.key):
			continue
		var d2: float = player_local.distance_squared_to(entry.world_pos)
		if d2 < best_d2:
			best_d2 = d2
			_nearest_empty_plot = entry
	if _nearest_empty_plot != null:
		_plant_prompt_root.position = _nearest_empty_plot.world_pos
		_plant_prompt_root.visible = true
	else:
		_plant_prompt_root.visible = false


# True when the player's feet are at this floor's surface level — not a floor
# above or below it in the stacked tower. Guards ground interactions so a
# Floor-4 player doesn't trigger Floor-3 prompts directly beneath them.
func _player_on_this_floor() -> bool:
	if _player == null:
		return false
	var surface_y: float = global_position.y + float(_c.FLOOR_3D_TOP_Y)
	return absf(_player.global_position.y - surface_y) < 1.5


# Handles the `plant` InputMap action (bound to P). Fires only when there's
# a nearest empty plot in range. Picks variety from GameState.arboretum
# .next_variety and alternates it.
func _handle_plant_input() -> void:
	if _nearest_empty_plot == null:
		return
	if not Input.is_action_just_pressed(&"plant"):
		return
	var entry: Dictionary = _nearest_empty_plot
	var variety: int = int(_gs.arboretum.next_variety)
	# Founder tree-state carries a genome + rng_seed (see ArboretumTree).
	# Growth is timed off the sim clock; manual plants start immediately.
	var tree: Dictionary = ArboretumTree.new_tree_state(variety, entry.world_pos, _gs.sim_time_msec)
	_gs.arboretum.trees[entry.key] = tree
	_gs.arboretum.next_variety = (variety + 1) % 2
	# Hide the plot marker — it's now a tree.
	if entry.marker:
		entry.marker.visible = false
	# Spawn the tree geometry immediately at growth_t = 0.
	_tree_refs[entry.key] = ArboretumTree.build(self, _c, tree, entry.world_pos)


# Rebuilds tree geometry for every tree already in GameState (player came
# back to Floor 3 after planting elsewhere). Each tree appears at its
# current growth state — no replaying of growth.
func _restore_existing_trees() -> void:
	for key in _gs.arboretum.trees:
		var tree: Dictionary = _gs.arboretum.trees[key]
		# Migrates any pre-genome tree in place before building.
		ArboretumTree.ensure_genome(tree)
		var world_pos: Vector3 = Vector3(tree.get("world_pos", Vector3.ZERO))
		_tree_refs[key] = ArboretumTree.build(self, _c, tree, world_pos)
		# Hide the matching plot marker so the marker doesn't double-render
		# under the tree's trunk.
		for entry in _edge_plots:
			if entry.key == key:
				if entry.marker:
					entry.marker.visible = false
				break


# Lerps every live tree's geometry to its current growth_t. Called every
# frame; the lerp is fast (60 fps × tiny per-frame delta) so growth reads
# as smooth even though the underlying time math is integer milliseconds.
func _update_tree_geometry() -> void:
	for key in _tree_refs:
		var tree: Dictionary = _gs.arboretum.trees.get(key, {})
		if tree.is_empty():
			continue
		var growth_t: float = ArboretumTree.growth_t_for(tree, _c, _gs.sim_time_msec)
		ArboretumTree.update(_tree_refs[key], _c, tree, growth_t)


# Per-frame label scaling so prompts stay readable at any zoom.
func _update_label_scale() -> void:
	if _plant_prompt_root == null or not _plant_prompt_root.visible:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	# Scale the whole prompt group as one (matches the player + elevator prompts)
	# so "P" and "Plant sapling" keep their spacing at any zoom — scaling the two
	# labels' pixel_size independently at fixed positions made them overlap when
	# zoomed out.
	var def: float = float(_c.CAMERA_ORTHO_SIZE_DEFAULT)
	_plant_prompt_root.scale = Vector3.ONE * clampf(cam.size / def, 0.18, 1.0)
