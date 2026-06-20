extends Node3D

# Renders one Garden floor (Floor 1) procedurally. Phase 3 of the iso slice,
# post-iteration: a square 30×30 m room with a 4×4 elevator shaft at center,
# perimeter walls framed by vertical posts and translucent window panels,
# and four spotlights outside the walls aiming inward to read as "sunlight
# through windows".
#
# Visual signature (sources: docs/space-tower-project-knowledge-v3.md,
# docs/player-journey-map-v3-final.html step 07 "The Garden of Eden"):
#   - Stacked planters with crops ripening
#   - Translucent water pipes with flowing water visible beneath the planters
#   - Warm grow-light glow over each planter
#
# Layout: 30×30 = 900 plot cells. Centre 4×4 (16 cells) is the elevator
# shaft. Remaining 884 cells get a planter; ~10% are upgraded to "feature
# plants" with stem + leafy foliage + tomato accents.
#
# Collision: slab is a StaticBody3D so the player walks/lands on it.
# Walls and the elevator core are StaticBody3D so the player can't escape
# the floor (fixes bug F-005, infinite fall).

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")
@onready var _tel: Node = get_node_or_null("/root/Telemetry")

const FloorChrome = preload("res://scenes/shared/floor_chrome.gd")
const FloorLifecycle = preload("res://scenes/shared/floor_lifecycle.gd")

# Elevator geometry data from FloorChrome. Mostly vestigial in the stacked
# tower (the ride-able car is elevator_platform.gd); we keep it for the
# `corners` spine-pipe mounts read by build_passive_spine_pipes.
var _elevator_data: Dictionary = {}

var _grow_lights: Array[OmniLight3D] = []
var _time := 0.0
var _rng := RandomNumberGenerator.new()

# Floor-population bloom: the grow-lights' energy is scaled by `_life` (0 = barren,
# dark field; 1 = alive, warm). It sits at 0 until the Garden crosses ALIVE, then
# the lifecycle's ALIVE bloom (_garden_bloom) tweens it to 1 — the provisional
# bloom (floor_population_spec Step 3).
var _life := 0.0
# The reusable blank→lush lifecycle (state, place verb, ghost, ALIVE transition,
# telemetry). The Garden DECLARES its content into it; the machinery is shared with
# every other populatable floor. Built in _ready().
var _lifecycle: FloorLifecycle = null

# Plot state. Each plot is a Dictionary tracking its current growth stage,
# elapsed time in that stage, and references to the meshes that visualise it.
# `stage` semantics:
#   0 → fresh dirt (POST_HARVEST_DURATION cooldown before the next sprout)
#   1..4 → growing
#   5 → ready-to-harvest (full foliage + fruit visible)
# Plot dictionaries are returned by find_nearest_harvestable_plot_near() and
# mutated by harvest_plot() — see iso_player.gd for the call sites.
var _plots: Array = []
# Plots also indexed by (row, col) so iso_robot.gd can snake-scan the grid.
var _plot_grid: Dictionary = {}
# Plant-type cluster assignment. Computed once in _build_garden_grid using
# a small Voronoi diagram (one seed per plant type), so plants of the same
# kind grow in connected patches instead of being randomly scattered.
var _plant_assignments: Dictionary = {}


func _ready() -> void:
	_rng.seed = 1   # deterministic so the operator gets the same room each run
	_build_slab()
	_build_walls_and_windows()
	_build_elevator_shaft()
	_build_garden_grid()
	_build_water_pipes()
	_build_extension_grid()
	_init_lifecycle()


# Declare the Garden's content into the shared lifecycle: planter beds snap to the
# plot grid, each activates a 3×3 dormant zone, GARDEN_ALIVE_BED_COUNT beds cross
# ALIVE → the grow-light bloom. The module owns state/telemetry/ghost/threshold.
func _init_lifecycle() -> void:
	var ghost_span: float = float(2 * int(_c.PLANTER_BED_ZONE_RADIUS) + 1) * _c.GARDEN_PLOT_SIZE - 0.1
	_lifecycle = FloorLifecycle.new(self, _gs, _c, _tel, {
		"floor_id": "garden",
		"level": 1,
		"threshold": int(_c.GARDEN_ALIVE_BED_COUNT),
		"component_type": "planter_bed",
		"ghost_span": ghost_span,
		"ghost_color": Color(0.45, 0.95, 0.55, 0.32),
		"is_populatable": _garden_is_populatable,
		"snap_anchor": _garden_snap_anchor,
		"is_valid_anchor": _is_valid_bed_anchor,
		"slot_local_pos": bed_slot_world_pos,
		"spawn_component": _garden_place_visuals,
		"on_alive": _garden_bloom,
	})


func _process(delta: float) -> void:
	_time += delta
	# Slow pulse so the Garden reads as alive without being noisy. Scaled by `_life`
	# so the field is dark while barren and warms in on the ALIVE bloom.
	var pulse := (0.85 + 0.15 * sin(_time * TAU / 2.5)) * _life
	for light in _grow_lights:
		light.light_energy = pulse
	# Advance growth lifecycle for every plot.
	for plot in _plots:
		_update_plot(plot, delta)


func _update_plot(plot: Dictionary, delta: float) -> void:
	# Empty plots (plant_type == null) wait for the player to plant; they
	# don't tick growth and have no grow_multiplier to read.
	if plot.plant_type == null:
		return
	plot.time_in_stage += delta
	var stage: int = plot.stage
	# Per-type grow rate. Violet plants take 3× longer per stage and 3×
	# longer to regrow after harvest; reds grow at the base rate.
	var multiplier: float = float(plot.plant_type.get("grow_multiplier", 1.0))
	if stage == 0:
		if plot.time_in_stage >= _c.POST_HARVEST_DURATION * multiplier:
			plot.stage = 1
			plot.time_in_stage = 0.0
			_refresh_plot_visuals(plot)
	elif stage >= 1 and stage <= _c.GROWTH_STAGE_COUNT - 1:
		if plot.time_in_stage >= _c.GROWTH_STAGE_DURATION * multiplier:
			plot.stage += 1
			plot.time_in_stage = 0.0
			_refresh_plot_visuals(plot)
	# stage == GROWTH_STAGE_COUNT (5): ready-to-harvest, no auto-advance.


# --- Public API used by iso_player.gd -------------------------------------

func find_nearest_harvestable_plot_near(world_pos: Vector3, radius: float) -> Variant:
	# Returns the closest plot with stage == 5 within `radius`, or null.
	# `plot.world_pos` is stored in THIS floor's local frame, so convert the
	# player's world position into the same frame first. In the stacked tower
	# the floor is offset (Garden at y=6); to_local cancels that offset, and
	# the full-3D distance then naturally Y-gates — a player standing a floor
	# above is >radius away in local space, so Garden plots don't trigger.
	var local_pos: Vector3 = to_local(world_pos)
	var best: Variant = null
	var best_dist_sq: float = radius * radius
	for plot in _plots:
		if plot.stage != _c.GROWTH_STAGE_COUNT:
			continue
		var d_sq: float = (plot.world_pos - local_pos).length_squared()
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = plot
	return best


func find_nearest_empty_plot_near(world_pos: Vector3, radius: float) -> Variant:
	# Returns the closest plot with no plant (plant_type == null) within
	# `radius`, or null. Used by iso_player.gd to drive the P prompt and the
	# plant action. See find_nearest_harvestable_plot_near for the local-frame
	# + implicit Y-gate rationale (plot.world_pos is local to this floor node).
	var local_pos: Vector3 = to_local(world_pos)
	var best: Variant = null
	var best_dist_sq: float = radius * radius
	for plot in _plots:
		if plot.plant_type != null:
			continue
		# DORMANT plots are bare ground until a planter bed activates their zone —
		# not yet plantable, so they never satisfy the empty-plot (P) lookup.
		if plot.get("dormant", false):
			continue
		var d_sq: float = (plot.world_pos - local_pos).length_squared()
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = plot
	return best


# Public planting API. Parameterised by grid coord + lowercase seed key so a
# future Builder-Cody can call this exactly like the player. Returns true on
# success, false if the plot was already occupied or the seed is unknown.
func plant(plot_coord: Vector2i, seed_key: String) -> bool:
	var plot: Variant = _plot_grid.get(plot_coord, null)
	if plot == null:
		return false
	if plot.plant_type != null:
		return false
	var plant_type: Dictionary = _c.plant_type_by_seed(seed_key)
	if plant_type.is_empty():
		return false
	_convert_empty_to_planted(plot, plant_type)
	if _tel:
		_tel.record("crop_planted", {"x": plot_coord.x, "y": plot_coord.y, "seed": seed_key})
	return true


func harvest_plot(plot: Dictionary, with_feedback: bool = true) -> void:
	# Spawn a "+1 <PlantName>" floating label only when the player drives the
	# harvest. The robot defers feedback until the player collects from it,
	# so its individual plant grabs are silent — the +N is delivered when
	# food_count actually moves in GameState.
	if with_feedback:
		_spawn_harvest_feedback(plot)
	if _tel:
		_tel.record("crop_harvested", {"by_player": with_feedback, "stage": int(plot.stage)})
	plot.stage = 0
	plot.time_in_stage = 0.0
	_refresh_plot_visuals(plot)


func _spawn_harvest_feedback(plot: Dictionary) -> void:
	# Consistent harvest feedback: every crop reads as "+1 <Crop>" (one item into
	# the backpack), same colour + size. Each crop's value still accrues to
	# food_count under the hood for the eventual sell economy — that nuance will
	# get a clearer surfacing when the Garden economy is designed. For now a
	# tomato and an eggplant harvest look the same, so picking doesn't flash a
	# jarring "+15" on one crop and "+1" on the rest.
	var label := Label3D.new()
	label.text = "+1 %s" % plot.plant_type.name
	label.font_size = 42
	label.outline_size = 6
	label.modulate = Color(0.78, 1.00, 0.55, 1.0)   # uniform garden-green
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.pixel_size = _adapt_pixel_size(0.011)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = plot.world_pos + Vector3(0, 0.7, 0)
	add_child(label)
	var start_y: float = label.position.y
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, ^"position:y", start_y + 1.4, 1.0)
	tween.tween_property(label, ^"modulate:a", 0.0, 1.0)
	tween.finished.connect(label.queue_free)


# Scale a base Label3D pixel_size by the current camera ortho_size so 3D
# floaters stay roughly screen-constant from iso default down to OTS close-up.
# Clamped on the low end so the text can't go microscopic at extreme zoom.
func _adapt_pixel_size(base_pixel_size: float) -> float:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return base_pixel_size
	var ortho: float = float(gs.camera.get("ortho_size", _c.CAMERA_ORTHO_SIZE_DEFAULT))
	return base_pixel_size * clamp(ortho / _c.CAMERA_ORTHO_SIZE_DEFAULT, 0.22, 1.0)


# --- Slab -------------------------------------------------------------------

func _build_slab() -> void:
	# Slab with the central elevator shaft cut out so the car can travel through.
	FloorChrome.build_slab(self, _c, Color(0.18, 0.18, 0.20),
			float(_c.ELEVATOR_RADIUS) * float(_c.GARDEN_PLOT_SIZE))


# --- Perimeter walls with vertical posts and translucent window panels ------

func _build_walls_and_windows() -> void:
	var half: float = _c.FLOOR_3D_SIZE * 0.5
	# Each side: along its length axis, place a low solid base, vertical
	# posts every WALL_POST_SPACING, semi-transparent panels between, and
	# a thin top trim.
	# Encoded as (axis_label, transform-position-fn, length-axis):
	#   wall +X (east), wall -X (west), wall +Z (south), wall -Z (north)
	# The Garden is the ground floor (GROUND_LEVEL): each wall gets a centred
	# doorway so you walk straight in from the exterior site (the door you see is
	# the door you use). The gap has no collision; the fall-catch covers stepping
	# out during interior play (same accepted edge the basement had).
	for side in ["+x", "-x", "+z", "-z"]:
		_build_one_wall(side, half, true)
		_build_window_spotlight(side, half)


# One mesh-or-collision wall segment. `along` is the centre offset ALONG the wall;
# `thick` runs perpendicular into the room. Mirrors FloorChrome._wall_piece so the
# doored Garden walls line up with the shared doored walls elsewhere.
func _wall_seg(body: StaticBody3D, mat, wall_along_x: bool, perp_pos: float,
		along: float, along_len: float, y_center: float, y_height: float,
		thick: float, collide_only: bool) -> void:
	var pos := Vector3(along, y_center, perp_pos) if wall_along_x else Vector3(perp_pos, y_center, along)
	var size := Vector3(along_len, y_height, thick) if wall_along_x else Vector3(thick, y_height, along_len)
	if collide_only:
		var col := CollisionShape3D.new()
		var cs := BoxShape3D.new()
		cs.size = size
		col.shape = cs
		col.position = pos
		body.add_child(col)
	else:
		var m := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		m.mesh = box
		m.material_override = mat
		m.position = pos
		body.add_child(m)


func _build_one_wall(side: String, half: float, doored: bool = false) -> void:
	var body := StaticBody3D.new()
	body.name = "Wall_" + side
	add_child(body)
	# Wall extends along one horizontal axis. Decide which.
	var wall_along_x: bool = side in ["+z", "-z"]
	var perp_pos: float = half if side in ["+x", "+z"] else -half
	var length: float = _c.FLOOR_3D_SIZE
	var thick: float = _c.WALL_THICKNESS
	var glass_h: float = _c.WALL_HEIGHT - _c.WALL_BASE_HEIGHT - 0.12
	var base_mat := _make_material(Color(0.32, 0.32, 0.36))
	# Doored: base/collision/glass are split into two flanks around a centred gap.
	var dw: float = _c.DOOR_WIDTH if doored else 0.0
	var side_len: float = (length - dw) * 0.5
	var side_ctr: float = (dw + side_len) * 0.5

	if doored:
		for sgn in [-1.0, 1.0]:
			var a: float = sgn * side_ctr
			_wall_seg(body, base_mat, wall_along_x, perp_pos, a, side_len, _c.WALL_BASE_HEIGHT * 0.5, _c.WALL_BASE_HEIGHT, thick, false)       # base
			_wall_seg(body, null, wall_along_x, perp_pos, a, side_len, _c.WALL_HEIGHT * 0.5, _c.WALL_HEIGHT, thick, true)                       # collision (full height)
			_wall_seg(body, _make_window_material(), wall_along_x, perp_pos, a, side_len - 0.2, _c.WALL_BASE_HEIGHT + glass_h * 0.5, glass_h, 0.05, false)  # glass
		# Door frame: jambs flanking the opening + a lintel above it (mesh only).
		var frame_mat := _make_material(Color(0.30, 0.30, 0.34))
		for sgn2 in [-1.0, 1.0]:
			_wall_seg(body, frame_mat, wall_along_x, perp_pos, sgn2 * dw * 0.5, 0.18, _c.DOOR_HEIGHT * 0.5, _c.DOOR_HEIGHT, thick * 1.1, false)
		var lintel_h: float = _c.WALL_HEIGHT - _c.DOOR_HEIGHT
		_wall_seg(body, frame_mat, wall_along_x, perp_pos, 0.0, dw, _c.DOOR_HEIGHT + lintel_h * 0.5, lintel_h, thick * 1.1, false)
	else:
		_wall_seg(body, base_mat, wall_along_x, perp_pos, 0.0, length, _c.WALL_BASE_HEIGHT * 0.5, _c.WALL_BASE_HEIGHT, thick, false)            # base
		_wall_seg(body, null, wall_along_x, perp_pos, 0.0, length, _c.WALL_HEIGHT * 0.5, _c.WALL_HEIGHT, thick, true)                            # collision
		_wall_seg(body, _make_window_material(), wall_along_x, perp_pos, 0.0, length - 0.4, _c.WALL_BASE_HEIGHT + glass_h * 0.5, glass_h, 0.05, false)  # glass

	# Vertical posts at fixed intervals — skip any that fall within the doorway gap.
	var post_count := int(length / _c.WALL_POST_SPACING) + 1
	for k in range(post_count):
		var t: float = float(k) / float(post_count - 1)   # 0..1 inclusive
		var along: float = -length * 0.5 + t * length
		if doored and absf(along) < dw * 0.5 + 0.2:
			continue
		var post := MeshInstance3D.new()
		post.name = "Post_%d" % k
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.18, _c.WALL_HEIGHT - _c.WALL_BASE_HEIGHT, 0.18)
		post.mesh = post_mesh
		post.material_override = _make_material(Color(0.38, 0.38, 0.42))
		post.position = Vector3(
			along if wall_along_x else perp_pos,
			(_c.WALL_BASE_HEIGHT + _c.WALL_HEIGHT) * 0.5,
			perp_pos if wall_along_x else along
		)
		body.add_child(post)

	# Thin top trim (full length — spans above the doorway like the shared walls).
	var trim := MeshInstance3D.new()
	trim.name = "TopTrim"
	var trim_mesh := BoxMesh.new()
	if wall_along_x:
		trim_mesh.size = Vector3(length, 0.12, thick * 1.05)
	else:
		trim_mesh.size = Vector3(thick * 1.05, 0.12, length)
	trim.mesh = trim_mesh
	trim.material_override = _make_material(Color(0.28, 0.28, 0.32))
	trim.position = Vector3(
		0.0 if wall_along_x else perp_pos,
		_c.WALL_HEIGHT - 0.06,
		perp_pos if wall_along_x else 0.0
	)
	body.add_child(trim)


func _build_window_spotlight(side: String, half: float) -> void:
	# A SpotLight3D outside each wall, pointing inward. Reads as sunlight
	# coming through the window panels.
	var spot := SpotLight3D.new()
	spot.name = "WindowLight_" + side
	spot.light_color = Color(1.0, 0.92, 0.78)   # warm
	spot.light_energy = 1.6
	spot.spot_range = 28.0
	spot.spot_angle = 50.0
	spot.spot_attenuation = 0.6
	# Position outside the wall, mid-height; aim toward the room centre.
	# add_child first — look_at requires the node to be in the tree.
	var outside_offset: float = half + 6.0
	var height := 3.5
	match side:
		"+x": spot.position = Vector3(outside_offset, height, 0)
		"-x": spot.position = Vector3(-outside_offset, height, 0)
		"+z": spot.position = Vector3(0, height, outside_offset)
		"-z": spot.position = Vector3(0, height, -outside_offset)
	add_child(spot)
	spot.look_at(Vector3(0, 0.5, 0), Vector3.UP)


# --- Elevator shaft (centre 4×4 plots) --------------------------------------

func _build_elevator_shaft() -> void:
	# Canonical elevator core built by FloorChrome (the static shaft; the car
	# is elevator_platform.gd). Garden also gets passive spine pipes — they reflect
	# the Utility floor's (Floor 0) connect/activate state so an online lane shows a glowing
	# pipe on every floor, not just where you flip the switch.
	_elevator_data = FloorChrome.build_elevator_core(self, _c)
	FloorChrome.build_passive_spine_pipes(self, _c, _gs, _elevator_data)


# --- 30×30 plot grid --------------------------------------------------------

func _build_garden_grid() -> void:
	# Opening-sequence Step 1: the Garden starts BARREN. Skip _seed_starter_garden()
	# (left defined) so _plant_assignments stays empty → every plot builds empty/tilled.
	var origin: float = -_c.FLOOR_3D_SIZE * 0.5 + _c.GARDEN_PLOT_SIZE * 0.5
	for i in range(_c.GARDEN_GRID_SIZE):
		for j in range(_c.GARDEN_GRID_SIZE):
			if _is_elevator_cell(i, j):
				continue
			if _is_dispenser_cell(i, j):
				continue
			var x: float = origin + float(i) * _c.GARDEN_PLOT_SIZE
			var z: float = origin + float(j) * _c.GARDEN_PLOT_SIZE
			# Empty plots get plant_type = null (operator plants into them).
			var assigned: Variant = _plant_assignments.get(Vector2i(i, j), null)
			var plot: Dictionary = _build_plot(x, z, assigned, Vector2i(i, j))
			_plots.append(plot)
			_plot_grid[Vector2i(i, j)] = plot
			# Sparse grow-light fixtures on a 4×4 stride so the field has
			# warm overhead glow without 384 OmniLights eating the GPU.
			if i % 4 == 1 and j % 4 == 1:
				_build_plot_grow_light(x, z)


# Skip plot construction in cells the dispenser body occupies so soil
# meshes don't poke through the chassis. Body is 0.95w × 0.45d, plot is
# 0.85 × 0.85 — a cell's center within (0.7, 0.6) of the dispenser center
# overlaps visually.
func _is_dispenser_cell(i: int, j: int) -> bool:
	var origin: float = -_c.FLOOR_3D_SIZE * 0.5 + _c.GARDEN_PLOT_SIZE * 0.5
	var x: float = origin + float(i) * _c.GARDEN_PLOT_SIZE
	var z: float = origin + float(j) * _c.GARDEN_PLOT_SIZE
	var dx: float = absf(x - _c.DISPENSER_POSITION.x)
	var dz: float = absf(z - _c.DISPENSER_POSITION.z)
	return dx < 0.7 and dz < 0.6


# Fill every cell within STARTER_GARDEN_RADIUS of the grid centre with a
# Voronoi-assigned plant type. Cells outside the radius stay empty for the
# player to plant into. The result reads as a tidy circular garden around
# the elevator core, with empty land beyond ready for expansion.
func _seed_starter_garden() -> void:
	var grid_size: int = int(_c.GARDEN_GRID_SIZE)
	var center := Vector2(
		float(grid_size) * 0.5 - 0.5,
		float(grid_size) * 0.5 - 0.5,
	)
	var radius: float = float(_c.STARTER_GARDEN_RADIUS)
	# Voronoi seeds inside the starter ring only, so per-type clusters stay
	# inside the planted region and the inset doesn't push them beyond it.
	var seed_inset: float = 1.0
	var seeds: Array = []
	for type_data in _c.PLANT_TYPES:
		var seed_count: int = int(type_data.get("seed_count", 1))
		for _s in range(seed_count):
			var theta: float = _rng.randf() * TAU
			var r: float = _rng.randf_range(0.0, max(0.0, radius - seed_inset))
			var sx: float = center.x + cos(theta) * r
			var sy: float = center.y + sin(theta) * r
			seeds.append({"pos": Vector2(sx, sy), "type": type_data})

	for i in range(grid_size):
		for j in range(grid_size):
			if _is_elevator_cell(i, j):
				continue
			if _is_dispenser_cell(i, j):
				continue
			var cell_pos := Vector2(float(i), float(j))
			if cell_pos.distance_to(center) > radius:
				continue
			var best_type: Dictionary = seeds[0].type
			var best_dist: float = INF
			for seed_data in seeds:
				var d: float = cell_pos.distance_squared_to(seed_data.pos)
				if d < best_dist:
					best_dist = d
					best_type = seed_data.type
			_plant_assignments[Vector2i(i, j)] = best_type


# Public lookup used by iso_robot.gd to snake-scan the grid.
func get_plot_at(i: int, j: int) -> Variant:
	return _plot_grid.get(Vector2i(i, j), null)


func _is_elevator_cell(i: int, j: int) -> bool:
	# Elevator footprint: 4×4 cells centered on the grid centre.
	var center: float = float(_c.GARDEN_GRID_SIZE) * 0.5 - 0.5
	return absf(float(i) - center) < float(_c.ELEVATOR_RADIUS) \
		and absf(float(j) - center) < float(_c.ELEVATOR_RADIUS)


# Build a plot. If `plant_type` is null, this becomes an empty (tilled) plot
# with sunken soil + furrow lines, ready for the player to plant into via
# the public plant() API. Otherwise it's a starter-garden plot at a random
# mature stage so the floor reads alive on first arrival.
func _build_plot(x: float, z: float, plant_type: Variant, coord: Vector2i) -> Dictionary:
	var plot := {
		"world_pos": Vector3(x, 0, z),
		"coord": coord,
		"stage": -1,
		"time_in_stage": 0.0,
		"plant_type": null,
		"dormant": false,
		"soil": null,
		"plant": null,
		"fruits": [] as Array,
		"furrows": [] as Array,
	}
	if plant_type == null:
		# floor_population_spec: a barren Garden boots with DORMANT plots — bare
		# ground, not the tilled/plantable state. A placed planter bed activates a
		# zone (dormant → tilled) via _activate_plot_zone. (Pre-population this was
		# tilled-empty directly; the dormant layer is the "before" of before/after.)
		plot.dormant = true
		_attach_dormant_plot_visuals(plot)
		return plot
	plot.plant_type = plant_type
	_attach_planted_plot_visuals(plot)
	# Random mature-mix stage so the starter garden doesn't read as freshly
	# seeded. Operator-tunable via STARTER_STAGE_MIN/MAX.
	plot.stage = _rng.randi_range(_c.STARTER_STAGE_MIN, _c.STARTER_STAGE_MAX)
	plot.time_in_stage = _rng.randf() * _c.GROWTH_STAGE_DURATION
	_refresh_plot_visuals(plot)
	return plot


# Empty plot visuals: a recessed darker soil pad with a few thin parallel
# furrow lines on top, reading as freshly tilled but unplanted soil.
func _attach_empty_plot_visuals(plot: Dictionary) -> void:
	var x: float = plot.world_pos.x
	var z: float = plot.world_pos.z
	# Sunken soil — same footprint, lower top edge so it reads recessed below
	# the surrounding planted plots.
	var soil := MeshInstance3D.new()
	soil.name = "EmptySoil"
	var soil_mesh := BoxMesh.new()
	soil_mesh.size = Vector3(0.85, 0.18, 0.85)
	soil.mesh = soil_mesh
	soil.material_override = _make_material(_c.EMPTY_PLOT_SOIL_COLOR)
	soil.position = Vector3(x, 0.09 - _c.EMPTY_PLOT_RECESS, z)
	add_child(soil)
	plot.soil = soil

	# Thin parallel furrow lines along Z. Slightly raised proud of the soil
	# top so they still read at iso angle, in a deeper brown.
	var furrows: Array = []
	var count: int = int(_c.EMPTY_PLOT_FURROW_COUNT)
	var furrow_top_y: float = 0.18 - _c.EMPTY_PLOT_RECESS + _c.EMPTY_PLOT_FURROW_DEPTH * 0.5
	for k in range(count):
		var t: float = (float(k) + 0.5) / float(count)
		var dx: float = -0.32 + t * 0.64   # spread across plot width
		var furrow := MeshInstance3D.new()
		furrow.name = "Furrow"
		var fm := BoxMesh.new()
		fm.size = Vector3(_c.EMPTY_PLOT_FURROW_THICKNESS, _c.EMPTY_PLOT_FURROW_DEPTH, 0.72)
		furrow.mesh = fm
		furrow.material_override = _make_material(_c.EMPTY_PLOT_FURROW_COLOR)
		furrow.position = Vector3(x + dx, furrow_top_y, z)
		add_child(furrow)
		furrows.append(furrow)
	plot.furrows = furrows


# Dormant-plot visuals: a flat, dark, inert ground pad — no furrows, sitting a
# touch lower than tilled soil so a barren floor reads as bare earth waiting to be
# worked. Placing a planter bed over its zone converts it to the tilled state.
func _attach_dormant_plot_visuals(plot: Dictionary) -> void:
	var x: float = plot.world_pos.x
	var z: float = plot.world_pos.z
	var pad := MeshInstance3D.new()
	pad.name = "DormantSoil"
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(0.92, 0.12, 0.92)   # slightly wider + flatter than tilled soil
	pad.mesh = pad_mesh
	pad.material_override = _make_material(_c.DORMANT_PLOT_COLOR)
	pad.position = Vector3(x, 0.06 - _c.EMPTY_PLOT_RECESS, z)
	add_child(pad)
	plot.soil = pad


# --- Component placement (floor_population_spec) ----------------------------
# A planter bed is placed via grid-snapped tap-E: the player stands on the grid,
# the nearest cell is offered as the bed ANCHOR (centre of a square zone), and E
# places it. Placing activates the zone's dormant plots and advances `populated`.

# World-space (LOCAL-frame) centre of the bed zone anchored at grid `coord`.
func bed_slot_world_pos(coord: Vector2i) -> Vector3:
	var origin: float = -_c.FLOOR_3D_SIZE * 0.5 + _c.GARDEN_PLOT_SIZE * 0.5
	var x: float = origin + float(coord.x) * _c.GARDEN_PLOT_SIZE
	var z: float = origin + float(coord.y) * _c.GARDEN_PLOT_SIZE
	return Vector3(x, 0.0, z)


# Is `anchor` a legal bed anchor? Every cell in its square zone must exist in the
# grid AND still be dormant — so beds can't straddle the elevator/dispenser holes,
# run off the grid edge, or overlap an already-placed bed's activated zone.
func _is_valid_bed_anchor(anchor: Vector2i) -> bool:
	var r: int = int(_c.PLANTER_BED_ZONE_RADIUS)
	for di in range(-r, r + 1):
		for dj in range(-r, r + 1):
			var plot: Variant = _plot_grid.get(Vector2i(anchor.x + di, anchor.y + dj), null)
			if plot == null or not bool(plot.get("dormant", false)):
				return false
	return true


# The placement verb is the shared FloorLifecycle's; these three keep their public
# names so iso_player + _floorpop_harness call them unchanged. Each delegates to the
# module, which routes state/telemetry/threshold through GameState.floor_state.
func find_nearest_bed_slot_near(world_pos: Vector3, radius: float) -> Variant:
	return _lifecycle.find_slot(world_pos, radius)


func update_bed_ghost(anchor_or_null) -> void:
	_lifecycle.update_ghost(anchor_or_null)


func place_planter_bed(coord: Vector2i) -> bool:
	return _lifecycle.place(coord)


# --- Garden's content declaration (the per-floor half of the lifecycle) -----

# The Garden's populating gate: power lifts placement (interiors_unlocked), and the
# phase closes once it blooms ALIVE.
func _garden_is_populatable() -> bool:
	return bool(_gs.interiors_unlocked) and not bool(_gs.garden_alive())


# Nearest plot cell to a LOCAL-frame position (pure grid math; the module supplies
# the to_local and the reach check).
func _garden_snap_anchor(local_pos: Vector3) -> Vector2i:
	var origin: float = -_c.FLOOR_3D_SIZE * 0.5 + _c.GARDEN_PLOT_SIZE * 0.5
	var ci: int = int(round((local_pos.x - origin) / _c.GARDEN_PLOT_SIZE))
	var cj: int = int(round((local_pos.z - origin) / _c.GARDEN_PLOT_SIZE))
	return Vector2i(ci, cj)


# Build a placed bed's visuals: the bed mesh, the zone activation (dormant → tilled),
# and the "it's taking shape" dirt poof — the content the module's place() spawns.
func _garden_place_visuals(anchor: Vector2i) -> void:
	_spawn_planter_bed(anchor)
	_activate_plot_zone(anchor)
	_spawn_plant_dirt_poof(bed_slot_world_pos(anchor))


# Activate every dormant plot in the bed's square zone: tear down the inert pad and
# attach the tilled-empty visuals, flipping the cell plantable.
func _activate_plot_zone(anchor: Vector2i) -> void:
	var r: int = int(_c.PLANTER_BED_ZONE_RADIUS)
	for di in range(-r, r + 1):
		for dj in range(-r, r + 1):
			var plot: Variant = _plot_grid.get(Vector2i(anchor.x + di, anchor.y + dj), null)
			if plot == null or not bool(plot.get("dormant", false)):
				continue
			if plot.soil != null:
				plot.soil.queue_free()
				plot.soil = null
			plot.dormant = false
			_attach_empty_plot_visuals(plot)


# The planter bed mesh: a raised dark-soil bed ringed by a warm wood rim, spanning
# the activated zone so the placement reads as a clear, solid object on the grid.
func _spawn_planter_bed(anchor: Vector2i) -> void:
	var center: Vector3 = bed_slot_world_pos(anchor)
	var span: float = float(2 * int(_c.PLANTER_BED_ZONE_RADIUS) + 1) * _c.GARDEN_PLOT_SIZE - 0.12
	var bed := Node3D.new()
	bed.name = "PlanterBed_%d_%d" % [anchor.x, anchor.y]
	bed.position = center
	add_child(bed)

	# Fresh dark soil infill, raised proud of the surrounding tilled cells.
	var soil := MeshInstance3D.new()
	var soil_mesh := BoxMesh.new()
	soil_mesh.size = Vector3(span, 0.22, span)
	soil.mesh = soil_mesh
	soil.material_override = _make_material(_c.PLANTER_BED_SOIL_COLOR)
	soil.position = Vector3(0, 0.13, 0)
	bed.add_child(soil)

	# Four wood rim rails around the perimeter, taller than the soil so the bed
	# reads as a built frame, not a patch of dirt.
	var rim_h: float = 0.30
	var rim_t: float = 0.14
	var half: float = span * 0.5
	var rim_mat := _make_material(_c.PLANTER_BED_RIM_COLOR)
	for spec in [
		{"size": Vector3(span + rim_t, rim_h, rim_t), "pos": Vector3(0, rim_h * 0.5, half)},
		{"size": Vector3(span + rim_t, rim_h, rim_t), "pos": Vector3(0, rim_h * 0.5, -half)},
		{"size": Vector3(rim_t, rim_h, span + rim_t), "pos": Vector3(half, rim_h * 0.5, 0)},
		{"size": Vector3(rim_t, rim_h, span + rim_t), "pos": Vector3(-half, rim_h * 0.5, 0)},
	]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = spec.size
		rail.mesh = rm
		rail.material_override = rim_mat
		rail.position = spec.pos
		bed.add_child(rail)

	# A small "it's taking shape" pop — the bed scales up from flat on placement.
	bed.scale = Vector3(1.0, 0.01, 1.0)
	var tween := create_tween()
	tween.tween_property(bed, ^"scale", Vector3.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# The Garden's provisional bloom — the floor's `on_alive` content callback. The
# module has already flipped `alive` + emitted `floor_alive` telemetry by the time
# this runs; here we run only the FELT moment: grow-lights warm in, Cody acknowledges
# through the mouth channel, and planting opens (iso_player gates P on garden_alive).
# NOTE (scope): the bloom is deliberately minimal for this slice — just the lights
# warming. Ambience/lighting polish + grow-light/water components are the next slice.
func _garden_bloom() -> void:
	# Warm the grow-lights in over ~1.6s (the _life factor scales their energy in
	# _process; it sits at 0 while barren so the field is dark before this).
	var tween := create_tween()
	tween.tween_method(_set_life, _life, 1.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var gd: Node = get_node_or_null("/root/GameDirector")
	if gd and gd.has_method("confirm_garden_alive"):
		gd.call("confirm_garden_alive")


func _set_life(v: float) -> void:
	_life = v


# Planted-plot visuals — the original soil + plant + fruits triple. Always
# called for both starter-garden cells and post-plant() conversions.
func _attach_planted_plot_visuals(plot: Dictionary) -> void:
	var x: float = plot.world_pos.x
	var z: float = plot.world_pos.z
	var plant_type: Dictionary = plot.plant_type
	var plant_color: Color = plant_type.foliage_color

	var soil := MeshInstance3D.new()
	soil.name = "Soil"
	var soil_mesh := BoxMesh.new()
	soil_mesh.size = Vector3(0.85, 0.18, 0.85)
	soil.mesh = soil_mesh
	soil.material_override = _make_material(_c.PLANTER_SOIL)
	soil.position = Vector3(x, 0.09, z)
	add_child(soil)
	plot.soil = soil

	var plant_visual := MeshInstance3D.new()
	plant_visual.name = "Plant"
	var plant_mesh := SphereMesh.new()
	plant_mesh.radius = 1.0
	plant_mesh.height = 2.0
	plant_visual.mesh = plant_mesh
	plant_visual.material_override = _make_material(plant_color)
	add_child(plant_visual)
	plot.plant = plant_visual

	plot.fruits = _build_fruits_for_type(plant_type, x, z)


# Convert an empty plot to a stage-1 sprout of `plant_type`. Called by the
# public plant() API after pouch/dispenser checks have passed.
func _convert_empty_to_planted(plot: Dictionary, plant_type: Dictionary) -> void:
	# Tear down empty visuals first so we don't leave the recessed soil under
	# the new planted soil.
	if plot.soil != null:
		plot.soil.queue_free()
		plot.soil = null
	for f in plot.furrows:
		f.queue_free()
	plot.furrows = []

	plot.plant_type = plant_type
	_attach_planted_plot_visuals(plot)
	plot.stage = 1
	plot.time_in_stage = 0.0
	_refresh_plot_visuals(plot)

	# Sprout-emerge tween: scale the foliage from zero up to its stage-1 size
	# so the moment of planting reads as a beat rather than a property flip.
	if plot.plant != null:
		var target_radius: float = _stage_to_plant_radius(1)
		var target_scale: Vector3 = Vector3(target_radius, target_radius, target_radius)
		plot.plant.scale = Vector3(target_radius, 0.01, target_radius)
		var tween := create_tween()
		tween.tween_property(
			plot.plant, ^"scale", target_scale, _c.SPROUT_EMERGE_DURATION
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Tiny dirt-poof: spawn a few small brown sphere bursts around the soil
	# that fade out as they rise. Cheap moment without extra dependencies.
	_spawn_plant_dirt_poof(plot.world_pos)
	# "+ Planted" floater so the action has a visible result beat — without
	# it the kneel ends and the only feedback is a quietly emerging sprout.
	_spawn_plant_feedback(plot, plant_type)


func _spawn_plant_feedback(plot: Dictionary, plant_type: Dictionary) -> void:
	var label := Label3D.new()
	label.text = "Planted %s" % plant_type.name
	label.font_size = 40
	label.outline_size = 6
	label.modulate = Color(0.65, 0.95, 0.55, 1.0)
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.pixel_size = _adapt_pixel_size(0.011)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = plot.world_pos + Vector3(0, 0.55, 0)
	add_child(label)
	var start_y: float = label.position.y
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, ^"position:y", start_y + 1.1, 1.1)
	tween.tween_property(label, ^"modulate:a", 0.0, 1.1)
	tween.finished.connect(label.queue_free)


func _spawn_plant_dirt_poof(world_pos: Vector3) -> void:
	var poof_color := Color(0.45, 0.32, 0.20)
	for k in range(5):
		var puff := MeshInstance3D.new()
		puff.name = "DirtPoof"
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.10
		puff.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(poof_color.r, poof_color.g, poof_color.b, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		puff.material_override = mat
		var angle: float = (float(k) / 5.0) * TAU + _rng.randf() * 0.4
		var radius: float = 0.18 + _rng.randf() * 0.08
		puff.position = world_pos + Vector3(
			cos(angle) * radius, 0.20, sin(angle) * radius
		)
		add_child(puff)
		var lift: float = 0.25 + _rng.randf() * 0.15
		var tween := create_tween().set_parallel(true)
		tween.tween_property(puff, ^"position:y", puff.position.y + lift, 0.55)
		tween.tween_property(mat, ^"albedo_color:a", 0.0, 0.55)
		tween.chain().tween_callback(puff.queue_free)


# Update plant scale, plant position (so its base stays on the soil), fruit
# visibility, and soil tint based on the current stage.
func _refresh_plot_visuals(plot: Dictionary) -> void:
	var stage: int = plot.stage
	var has_plant: bool = stage >= 1 and stage <= _c.GROWTH_STAGE_COUNT
	plot.plant.visible = has_plant
	var show_fruits: bool = stage == _c.GROWTH_STAGE_COUNT
	for fruit in plot.fruits:
		fruit.visible = show_fruits
	if has_plant:
		var r: float = _stage_to_plant_radius(stage)
		plot.plant.scale = Vector3(r, r, r)
		plot.plant.position = Vector3(plot.world_pos.x, 0.18 + r, plot.world_pos.z)
	# Soil reads slightly darker at stage 0 — "fresh dirt".
	var soil_mat: StandardMaterial3D = plot.soil.material_override
	if stage == 0:
		soil_mat.albedo_color = Color(
			_c.PLANTER_SOIL.r * 0.8,
			_c.PLANTER_SOIL.g * 0.8,
			_c.PLANTER_SOIL.b * 0.8,
		)
	else:
		soil_mat.albedo_color = _c.PLANTER_SOIL


func _stage_to_plant_radius(stage: int) -> float:
	# Stages 1..5 → progressively larger foliage. Stage 5 capped at 0.20 so
	# the fruit accents (positioned above and outside the sphere) actually
	# read at iso distance instead of being engulfed by green leaves.
	# Stage 1 raised from 0.04 → 0.10 so a freshly-planted sprout is
	# actually visible after the kneel; previous value was a green pinhead.
	var radii := [0.10, 0.13, 0.155, 0.18, 0.20]
	return radii[stage - 1]


# Build the stage-5 fruit visuals for a plant type. Each crop has a
# distinct shape (scale-warped sphere or cylinder) and count; everything
# stays hidden until _refresh_plot_visuals() flips visibility at stage 5.
func _build_fruits_for_type(plant_type: Dictionary, x: float, z: float) -> Array:
	var fruits: Array = []
	var color: Color = plant_type.fruit_color
	match plant_type.name:
		"Tomato":
			# Cluster of 3 small round red tomatoes sitting on top of the
			# foliage so the red reads from iso angle.
			for i in range(3):
				var f := MeshInstance3D.new()
				f.name = "Tomato"
				var m := SphereMesh.new()
				m.radius = 0.10
				m.height = 0.20
				f.mesh = m
				f.material_override = _make_material(color)
				var angle: float = float(i) * (TAU / 3.0) + 0.5
				var dx: float = cos(angle) * 0.13
				var dz: float = sin(angle) * 0.13
				f.position = Vector3(x + dx, 0.62 + float(i) * 0.04, z + dz)
				add_child(f)
				fruits.append(f)
		"Pepper":
			# Two slim, vertically-elongated peppers sticking up out of the
			# foliage. Top of the pepper is well above the foliage crown.
			for i in range(2):
				var f := MeshInstance3D.new()
				f.name = "Pepper"
				var m := SphereMesh.new()
				m.radius = 0.07
				m.height = 0.14
				f.mesh = m
				f.scale = Vector3(1.0, 1.9, 1.0)
				f.material_override = _make_material(color)
				var sign_v: int = -1 if i == 0 else 1
				f.position = Vector3(x + sign_v * 0.16, 0.55, z + 0.04)
				add_child(f)
				fruits.append(f)
		"Eggplant":
			# One tall vertical purple ellipsoid sticking up out of the
			# foliage with a green calyx capping it. Much larger than the
			# first pass so the purple registers across the field.
			var body := MeshInstance3D.new()
			body.name = "EggplantBody"
			var bm := SphereMesh.new()
			bm.radius = 0.16
			bm.height = 0.32
			body.mesh = bm
			body.scale = Vector3(0.7, 1.45, 0.7)
			body.material_override = _make_material(color)
			body.position = Vector3(x + 0.05, 0.62, z + 0.05)
			add_child(body)
			fruits.append(body)
			var cap := MeshInstance3D.new()
			cap.name = "EggplantCap"
			var cm := BoxMesh.new()
			cm.size = Vector3(0.10, 0.05, 0.10)
			cap.mesh = cm
			cap.material_override = _make_material(Color(0.30, 0.50, 0.20))
			cap.position = Vector3(x + 0.05, 0.84, z + 0.05)
			add_child(cap)
			fruits.append(cap)
		"Pumpkin":
			# One squashed orange sphere sitting on the soil OUTSIDE the
			# foliage horizontally so the orange peeks out from beside the
			# green ball, not under it.
			var body := MeshInstance3D.new()
			body.name = "PumpkinBody"
			var bm := SphereMesh.new()
			bm.radius = 0.13
			bm.height = 0.26
			body.mesh = bm
			body.scale = Vector3(1.0, 0.72, 1.0)
			body.material_override = _make_material(color)
			body.position = Vector3(x + 0.30, 0.27, z + 0.22)
			add_child(body)
			fruits.append(body)
			# Dark green stem on top.
			var stem := MeshInstance3D.new()
			stem.name = "PumpkinStem"
			var sm := CylinderMesh.new()
			sm.top_radius = 0.025
			sm.bottom_radius = 0.04
			sm.height = 0.08
			stem.mesh = sm
			stem.material_override = _make_material(Color(0.25, 0.40, 0.15))
			stem.position = Vector3(x + 0.30, 0.39, z + 0.22)
			add_child(stem)
			fruits.append(stem)
		"Cucumber":
			# Two long thin green cylinders sticking up out of the foliage,
			# tilted opposite directions. Top of each cylinder is above the
			# foliage crown so the lime green is clearly visible.
			for i in range(2):
				var f := MeshInstance3D.new()
				f.name = "Cucumber"
				var m := CylinderMesh.new()
				m.top_radius = 0.05
				m.bottom_radius = 0.05
				m.height = 0.30
				f.mesh = m
				f.material_override = _make_material(color)
				var sign_v: int = -1 if i == 0 else 1
				f.rotation = Vector3(0, 0, deg_to_rad(22.0 * sign_v))
				f.position = Vector3(x + sign_v * 0.16, 0.55, z - 0.05 * sign_v)
				add_child(f)
				fruits.append(f)
		"Blueberries":
			# Cluster of 6 small blue berries above the foliage canopy at
			# slightly varied heights. Reads as a hanging berry bunch from
			# any iso angle.
			for i in range(6):
				var f := MeshInstance3D.new()
				f.name = "Blueberry"
				var m := SphereMesh.new()
				m.radius = 0.055
				m.height = 0.11
				f.mesh = m
				f.material_override = _make_material(color)
				var angle: float = float(i) * (TAU / 6.0)
				var dx: float = cos(angle) * 0.12
				var dz: float = sin(angle) * 0.12
				var dy: float = 0.62 + float(i % 3) * 0.04
				f.position = Vector3(x + dx, dy, z + dz)
				add_child(f)
				fruits.append(f)
	for f in fruits:
		f.visible = false
	return fruits


func _build_plot_grow_light(x: float, z: float) -> void:
	var fixture := MeshInstance3D.new()
	fixture.name = "GrowLightFixture"
	var fmesh := BoxMesh.new()
	fmesh.size = Vector3(0.45, 0.07, 0.32)
	fixture.mesh = fmesh
	fixture.material_override = _make_material(Color(0.15, 0.15, 0.18))
	fixture.position = Vector3(x, 2.2, z)
	add_child(fixture)
	var bulb := MeshInstance3D.new()
	bulb.name = "GrowLightBulb"
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(0.36, 0.04, 0.24)
	bulb.mesh = bmesh
	bulb.material_override = _make_emissive_material(_c.GROW_LIGHT_COLOR, 1.6)
	bulb.position = Vector3(x, 2.16, z)
	add_child(bulb)
	var light := OmniLight3D.new()
	light.name = "GrowLight"
	light.light_color = _c.GROW_LIGHT_COLOR
	light.light_energy = 0.9
	light.omni_range = 2.5
	light.omni_attenuation = 1.4
	light.position = Vector3(x, 2.0, z)
	add_child(light)
	_grow_lights.append(light)


# --- Water pipes (perimeter loop just inside the walls) ---------------------

func _build_water_pipes() -> void:
	var inset: float = _c.FLOOR_3D_SIZE * 0.5 - 0.5
	var height: float = 0.22
	# Two pipes parallel to X (front/back), two parallel to Z (left/right).
	for z_offset in [inset, -inset]:
		var pipe := MeshInstance3D.new()
		pipe.name = "WaterPipeX"
		var cyl := CylinderMesh.new()
		cyl.height = _c.FLOOR_3D_SIZE
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.07
		pipe.mesh = cyl
		pipe.material_override = _make_water_material()
		pipe.rotation = Vector3(0, 0, deg_to_rad(90))
		pipe.position = Vector3(0.0, height, z_offset)
		add_child(pipe)
	for x_offset in [inset, -inset]:
		var pipe := MeshInstance3D.new()
		pipe.name = "WaterPipeZ"
		var cyl := CylinderMesh.new()
		cyl.height = _c.FLOOR_3D_SIZE
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.07
		pipe.mesh = cyl
		pipe.material_override = _make_water_material()
		pipe.rotation = Vector3(deg_to_rad(90), 0, 0)
		pipe.position = Vector3(x_offset, height, 0.0)
		add_child(pipe)


# --- Materials --------------------------------------------------------------

func _make_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	return m


func _make_emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _make_water_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = _c.WATER_PIPE_COLOR
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.2
	m.metallic = 0.1
	return m


func _make_window_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.85, 1.0, 0.25)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.5
	return m


# --- Extension grid: a subtle blueprint-style hint that the tower could
# extend outward. 6 perpendicular lines per side (one per window pane),
# each 2 m long, solid for the first 1 m and fading to 0 alpha across the
# second 1 m via vertex-color alpha on an ArrayMesh. A single perpendicular
# crossbar per side at distance 1 m forms the blueprint grid.

func _build_extension_grid() -> void:
	var half: float = _c.FLOOR_3D_SIZE * 0.5
	var y_offset := 0.005
	# 6 lines per side, evenly spaced across the wall — computed from the
	# floor size so the grid auto-rebalances if GARDEN_GRID_SIZE changes.
	var pane_count: int = int(_c.EXTENSION_PANE_COUNT)
	var pane_step: float = _c.FLOOR_3D_SIZE / float(pane_count)
	var pane_positions: Array = []
	for k in range(pane_count):
		pane_positions.append(-half + (float(k) + 0.5) * pane_step)

	var line_mesh := _make_extension_line_mesh()
	var line_mat := _make_extension_line_material()
	var bar_mat := _make_extension_crossbar_material()

	# Per-side: 6 outgoing lines from pane centers, plus 1 crossbar at the
	# solid/fade boundary. Crossbar extends slightly past the corners
	# (length ext beyond, so it forms a closed blueprint rectangle).
	for s in ["+x", "-x", "+z", "-z"]:
		var rot_y := 0.0
		var origin: Vector3
		match s:
			"+x":
				rot_y = 0.0
				origin = Vector3(half, y_offset, 0)
			"-x":
				rot_y = PI
				origin = Vector3(-half, y_offset, 0)
			"+z":
				rot_y = -PI * 0.5
				origin = Vector3(0, y_offset, half)
			"-z":
				rot_y = PI * 0.5
				origin = Vector3(0, y_offset, -half)

		# Outgoing lines.
		for offset in pane_positions:
			var line := MeshInstance3D.new()
			line.name = "GridExtLine"
			line.mesh = line_mesh
			line.material_override = line_mat
			# Position the line's start (its local origin) at the wall edge,
			# offset along the wall by `offset`. The mesh extends along its
			# local +X direction; rotation_y aims that direction outward.
			match s:
				"+x", "-x":
					line.position = origin + Vector3(0, 0, offset)
				"+z", "-z":
					line.position = origin + Vector3(offset, 0, 0)
			line.rotation.y = rot_y
			add_child(line)

		# Crossbar at distance EXTENSION_LINE_SOLID_LENGTH from the wall,
		# parallel to the wall. Length extends 1 grid unit past each corner so
		# the four crossbars meet exactly at the corners of the blueprint
		# frame (each side at x or z = ±(half + solid_dist)).
		var solid_dist: float = _c.EXTENSION_LINE_SOLID_LENGTH
		var bar_length: float = _c.FLOOR_3D_SIZE + 2.0 * solid_dist
		var bar := MeshInstance3D.new()
		bar.name = "GridExtCrossbar"
		var box := BoxMesh.new()
		match s:
			"+x":
				box.size = Vector3(0.04, 0.01, bar_length)
				bar.position = Vector3(half + solid_dist, y_offset, 0)
			"-x":
				box.size = Vector3(0.04, 0.01, bar_length)
				bar.position = Vector3(-half - solid_dist, y_offset, 0)
			"+z":
				box.size = Vector3(bar_length, 0.01, 0.04)
				bar.position = Vector3(0, y_offset, half + solid_dist)
			"-z":
				box.size = Vector3(bar_length, 0.01, 0.04)
				bar.position = Vector3(0, y_offset, -half - solid_dist)
		bar.mesh = box
		bar.material_override = bar_mat
		add_child(bar)


# Thin horizontal strip 2 m long: solid (alpha PEAK_ALPHA) for 0..1 m,
# fades to alpha 0 at the 2 m mark via vertex colors.
func _make_extension_line_mesh() -> ArrayMesh:
	var thick := 0.04
	var solid_len: float = _c.EXTENSION_LINE_SOLID_LENGTH
	var total_len: float = _c.EXTENSION_GRID_LENGTH
	var peak: float = _c.EXTENSION_LINE_PEAK_ALPHA

	var verts := PackedVector3Array([
		Vector3(0.0,       0, -thick * 0.5), Vector3(0.0,       0, thick * 0.5),
		Vector3(solid_len, 0, -thick * 0.5), Vector3(solid_len, 0, thick * 0.5),
		Vector3(total_len, 0, -thick * 0.5), Vector3(total_len, 0, thick * 0.5),
	])
	var solid := Color(1, 1, 1, peak)
	var fade := Color(1, 1, 1, 0.0)
	var colors := PackedColorArray([solid, solid, solid, solid, fade, fade])
	var indices := PackedInt32Array([
		0, 1, 2,  1, 3, 2,    # quad 1 — solid
		2, 3, 4,  3, 5, 4,    # quad 2 — solid → faded
	])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _make_extension_line_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1, 1)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _make_extension_crossbar_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1, _c.EXTENSION_LINE_PEAK_ALPHA)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
