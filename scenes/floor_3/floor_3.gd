extends Node3D

# Floor 3 — Arboretum (ground level). Edge-only tree plots, central elevator,
# spiral staircase wrapping the elevator that ascends to Floor 4. Cody was
# "built for floor-three operations" per his dialogue tree — this is his
# native floor.
#
# Phase 1 (this commit): scaffold only. Footprint matches Floor 1/2 via
# FloorChrome, elevator wires to Garden (down), staircase climbs to Floor 4.
# Edge plot positions are computed and marked but no planting verb yet.
# Trees, water source, and sunlight source land in Phase 2.

const FloorChrome = preload("res://scenes/shared/floor_chrome.gd")
const SpiralStaircase = preload("res://scenes/shared/spiral_staircase.gd")

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

@export var player_path: NodePath
var _player: Node3D

# Geometry data returned by FloorChrome.build_elevator_core. Held so
# ElevatorHandler can read inner_mat for the travel glow.
var _elevator_data: Dictionary = {}

# Edge plot world positions, computed in _ready. Phase 2 reads these to
# render saplings + tree growth. List of Vector3 (centre point per plot).
var _edge_plots: Array = []


func _ready() -> void:
	if not player_path.is_empty():
		_player = get_node_or_null(player_path)

	FloorChrome.build_slab(self, _c, Color(0.34, 0.40, 0.32))
	FloorChrome.build_walls(self, _c)
	FloorChrome.build_extension_grid(self, _c)
	_elevator_data = FloorChrome.build_elevator_core(self, _c)
	FloorChrome.build_passive_spine_pipes(self, _c, _gs, _elevator_data)

	# Spiral ramp wraps the elevator octagon, ascending to Floor 4.
	# Starts at angle 0 (= +X axis); winds CCW; lands one story up.
	SpiralStaircase.build(self, _c, _c.FLOOR_3D_TOP_Y, 0.0)

	_compute_edge_plots()
	_render_edge_plot_markers()


# Identifies all edge plots — those exactly ARBORETUM_EDGE_INSET cells
# inside the wall — selected at every-other-cell stride along each side.
# Stores world-space centre Vector3s in _edge_plots for Phase 2 to consume.
func _compute_edge_plots() -> void:
	_edge_plots.clear()
	var grid: int = int(_c.GARDEN_GRID_SIZE)
	var plot: float = float(_c.GARDEN_PLOT_SIZE)
	var inset: int = int(_c.ARBORETUM_EDGE_INSET)
	var stride: int = int(_c.ARBORETUM_PLOT_STRIDE)
	var half: float = grid * plot * 0.5

	# Side coords (grid cell indices: 0..grid-1). For each side, the
	# perpendicular-axis cell index is fixed (= inset on the low side,
	# grid-1-inset on the high side); the along-axis index walks the cells.
	var side_indices := [inset, grid - 1 - inset]
	# Cell -> world: world = -half + (cell + 0.5) * plot.
	for perp in side_indices:
		var perp_world: float = -half + (perp + 0.5) * plot
		# Top + bottom sides (z = perp_world, walk x from inset to grid-1-inset)
		for x in range(inset, grid - inset, stride):
			var x_world: float = -half + (x + 0.5) * plot
			_edge_plots.append(Vector3(x_world, _c.FLOOR_3D_TOP_Y, perp_world))
	for perp2 in side_indices:
		var perp_world2: float = -half + (perp2 + 0.5) * plot
		# Left + right sides (x = perp_world2, walk z from inset+stride to grid-1-inset-stride
		# to avoid duplicating the four corner plots already captured above)
		for z in range(inset + stride, grid - inset - stride + 1, stride):
			var z_world: float = -half + (z + 0.5) * plot
			_edge_plots.append(Vector3(perp_world2, _c.FLOOR_3D_TOP_Y, z_world))


# Phase 1 visual marker — each edge plot gets a subtle darker square so
# the player can see WHERE trees can be planted before the planting verb
# ships in Phase 2. Replaced by tilled soil + sapling visuals in Phase 2.
func _render_edge_plot_markers() -> void:
	var plot: float = float(_c.GARDEN_PLOT_SIZE)
	var mat := StandardMaterial3D.new()
	# Bumped tint contrast vs the slab so plots read clearly. The
	# Phase-2 tilled-soil visuals will replace these.
	mat.albedo_color = Color(0.20, 0.32, 0.18)
	mat.roughness = 0.95
	mat.emission_enabled = true
	mat.emission = Color(0.06, 0.12, 0.05)
	mat.emission_energy_multiplier = 0.5
	for pos in _edge_plots:
		var marker := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(plot * 0.85, 0.02, plot * 0.85)
		marker.mesh = box
		marker.material_override = mat
		marker.position = pos + Vector3(0, 0.011, 0)
		add_child(marker)
