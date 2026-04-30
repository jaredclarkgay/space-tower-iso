extends Node3D

# Renders one Garden floor (Floor 3) procedurally. Phase 3 of the iso slice,
# post-iteration: a square 20×20 m room with a 4×4 elevator shaft at center,
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
# Layout: 20×20 = 400 plot cells. Centre 4×4 (16 cells) is the elevator
# shaft. Remaining 384 cells get a planter; ~10% are upgraded to "feature
# plants" with stem + leafy foliage + tomato accents.
#
# Collision: slab is a StaticBody3D so the player walks/lands on it.
# Walls and the elevator core are StaticBody3D so the player can't escape
# the floor (fixes bug F-005, infinite fall).

@onready var _c: Node = get_node("/root/Constants")

var _grow_lights: Array[OmniLight3D] = []
var _time := 0.0
var _rng := RandomNumberGenerator.new()

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


func _process(delta: float) -> void:
	_time += delta
	# Slow pulse so the Garden reads as alive without being noisy.
	var pulse := 0.85 + 0.15 * sin(_time * TAU / 2.5)
	for light in _grow_lights:
		light.light_energy = pulse
	# Advance growth lifecycle for every plot.
	for plot in _plots:
		_update_plot(plot, delta)


func _update_plot(plot: Dictionary, delta: float) -> void:
	plot.time_in_stage += delta
	var stage: int = plot.stage
	if stage == 0:
		if plot.time_in_stage >= _c.POST_HARVEST_DURATION:
			plot.stage = 1
			plot.time_in_stage = 0.0
			_refresh_plot_visuals(plot)
	elif stage >= 1 and stage <= _c.GROWTH_STAGE_COUNT - 1:
		if plot.time_in_stage >= _c.GROWTH_STAGE_DURATION:
			plot.stage += 1
			plot.time_in_stage = 0.0
			_refresh_plot_visuals(plot)
	# stage == GROWTH_STAGE_COUNT (5): ready-to-harvest, no auto-advance.


# --- Public API used by iso_player.gd -------------------------------------

func find_nearest_harvestable_plot_near(world_pos: Vector3, radius: float) -> Variant:
	# Returns the closest plot with stage == 5 within `radius`, or null.
	var best: Variant = null
	var best_dist_sq: float = radius * radius
	for plot in _plots:
		if plot.stage != _c.GROWTH_STAGE_COUNT:
			continue
		var d_sq: float = (plot.world_pos - world_pos).length_squared()
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = plot
	return best


func harvest_plot(plot: Dictionary, with_feedback: bool = true) -> void:
	# Spawn a "+1 <PlantName>" floating label only when the player drives the
	# harvest. The robot defers feedback until the player collects from it,
	# so its individual plant grabs are silent — the +N is delivered when
	# food_count actually moves in GameState.
	if with_feedback:
		_spawn_harvest_feedback(plot)
	plot.stage = 0
	plot.time_in_stage = 0.0
	_refresh_plot_visuals(plot)


func _spawn_harvest_feedback(plot: Dictionary) -> void:
	var label := Label3D.new()
	label.text = "+1 %s" % plot.plant_type.name
	label.font_size = 40
	label.outline_size = 6
	label.modulate = Color(0.7, 1.0, 0.55, 1)
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.pixel_size = 0.011
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = plot.world_pos + Vector3(0, 0.7, 0)
	add_child(label)
	var start_y: float = label.position.y
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, ^"position:y", start_y + 1.4, 1.0)
	tween.tween_property(label, ^"modulate:a", 0.0, 1.0)
	tween.finished.connect(label.queue_free)


# --- Slab -------------------------------------------------------------------

func _build_slab() -> void:
	var body := StaticBody3D.new()
	body.name = "SlabBody"
	add_child(body)
	var size := Vector3(_c.FLOOR_3D_SIZE, _c.FLOOR_3D_SLAB_THICKNESS, _c.FLOOR_3D_SIZE)
	var mesh := MeshInstance3D.new()
	mesh.name = "Slab"
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _make_material(Color(0.18, 0.18, 0.20))
	mesh.position.y = -_c.FLOOR_3D_SLAB_THICKNESS * 0.5
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	col_shape.size = size
	col.shape = col_shape
	col.position.y = -_c.FLOOR_3D_SLAB_THICKNESS * 0.5
	body.add_child(col)


# --- Perimeter walls with vertical posts and translucent window panels ------

func _build_walls_and_windows() -> void:
	var half: float = _c.FLOOR_3D_SIZE * 0.5
	# Each side: along its length axis, place a low solid base, vertical
	# posts every WALL_POST_SPACING, semi-transparent panels between, and
	# a thin top trim.
	# Encoded as (axis_label, transform-position-fn, length-axis):
	#   wall +X (east), wall -X (west), wall +Z (south), wall -Z (north)
	for side in ["+x", "-x", "+z", "-z"]:
		_build_one_wall(side, half)
		_build_window_spotlight(side, half)


func _build_one_wall(side: String, half: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Wall_" + side
	add_child(body)
	# Wall extends along one horizontal axis. Decide which.
	var wall_along_x: bool = side in ["+z", "-z"]
	var perp_pos: float = half if side in ["+x", "+z"] else -half
	var length: float = _c.FLOOR_3D_SIZE
	var thick: float = _c.WALL_THICKNESS

	# Solid base (full length).
	var base := MeshInstance3D.new()
	base.name = "Base"
	var base_size: Vector3
	if wall_along_x:
		base_size = Vector3(length, _c.WALL_BASE_HEIGHT, thick)
	else:
		base_size = Vector3(thick, _c.WALL_BASE_HEIGHT, length)
	var bm := BoxMesh.new()
	bm.size = base_size
	base.mesh = bm
	base.material_override = _make_material(Color(0.32, 0.32, 0.36))
	base.position = Vector3(
		0.0 if wall_along_x else perp_pos,
		_c.WALL_BASE_HEIGHT * 0.5,
		perp_pos if wall_along_x else 0.0
	)
	body.add_child(base)

	# Collision (full wall height, full length): the simple rectangle keeps
	# the player in. Player won't notice the windows aren't physically open.
	var col := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	if wall_along_x:
		col_shape.size = Vector3(length, _c.WALL_HEIGHT, thick)
	else:
		col_shape.size = Vector3(thick, _c.WALL_HEIGHT, length)
	col.shape = col_shape
	col.position = Vector3(
		0.0 if wall_along_x else perp_pos,
		_c.WALL_HEIGHT * 0.5,
		perp_pos if wall_along_x else 0.0
	)
	body.add_child(col)

	# Vertical posts at fixed intervals along the wall's length.
	var post_count := int(length / _c.WALL_POST_SPACING) + 1
	for k in range(post_count):
		var t: float = float(k) / float(post_count - 1)   # 0..1 inclusive
		var along: float = -length * 0.5 + t * length
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

	# Thin top trim (full length).
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

	# Window panels — one continuous semi-transparent strip filling the gap
	# between the base and the top trim. Posts will visually segment it.
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	var glass_mesh := BoxMesh.new()
	var glass_h: float = _c.WALL_HEIGHT - _c.WALL_BASE_HEIGHT - 0.12
	if wall_along_x:
		glass_mesh.size = Vector3(length - 0.4, glass_h, 0.05)
	else:
		glass_mesh.size = Vector3(0.05, glass_h, length - 0.4)
	glass.mesh = glass_mesh
	glass.material_override = _make_window_material()
	glass.position = Vector3(
		0.0 if wall_along_x else perp_pos,
		_c.WALL_BASE_HEIGHT + glass_h * 0.5,
		perp_pos if wall_along_x else 0.0
	)
	body.add_child(glass)


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
	var size: float = float(_c.ELEVATOR_RADIUS) * 2.0 * _c.GARDEN_PLOT_SIZE   # 4 m
	var body := StaticBody3D.new()
	body.name = "ElevatorCore"
	add_child(body)
	# Translucent shaft column reaching up past the wall trim.
	var shaft := MeshInstance3D.new()
	shaft.name = "Shaft"
	var sm := BoxMesh.new()
	sm.size = Vector3(size, _c.WALL_HEIGHT, size)
	shaft.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.32, 0.4, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.4
	mat.metallic = 0.3
	shaft.material_override = mat
	shaft.position.y = _c.WALL_HEIGHT * 0.5
	body.add_child(shaft)
	# Solid collision for the elevator footprint so the player can't enter.
	var col := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(size, _c.WALL_HEIGHT, size)
	col.shape = col_shape
	col.position.y = _c.WALL_HEIGHT * 0.5
	body.add_child(col)
	# Bright accent at the door height to suggest a control panel.
	var accent := MeshInstance3D.new()
	accent.name = "Accent"
	var accent_mesh := BoxMesh.new()
	accent_mesh.size = Vector3(size * 0.9, 0.06, size * 0.9)
	accent.mesh = accent_mesh
	accent.material_override = _make_emissive_material(Color(0.4, 0.7, 1.0), 0.8)
	accent.position.y = 1.6
	body.add_child(accent)


# --- 20×20 plot grid --------------------------------------------------------

func _build_garden_grid() -> void:
	_compute_plant_assignments()
	var origin: float = -_c.FLOOR_3D_SIZE * 0.5 + _c.GARDEN_PLOT_SIZE * 0.5
	for i in range(_c.GARDEN_GRID_SIZE):
		for j in range(_c.GARDEN_GRID_SIZE):
			if _is_elevator_cell(i, j):
				continue
			var x: float = origin + float(i) * _c.GARDEN_PLOT_SIZE
			var z: float = origin + float(j) * _c.GARDEN_PLOT_SIZE
			var plant_type: Dictionary = _plant_assignments[Vector2i(i, j)]
			var plot := _build_plot(x, z, plant_type)
			_plots.append(plot)
			_plot_grid[Vector2i(i, j)] = plot
			# Sparse grow-light fixtures on a 4×4 stride so the field has
			# warm overhead glow without 384 OmniLights eating the GPU.
			if i % 4 == 1 and j % 4 == 1:
				_build_plot_grow_light(x, z)


# One seed per plant type, dropped at a deterministic random cell. Each plot
# is then assigned the plant type of its nearest seed — a Voronoi diagram.
# Plots of the same type form connected patches instead of pepper plants
# being scattered between every tomato plant.
func _compute_plant_assignments() -> void:
	var grid_size: int = int(_c.GARDEN_GRID_SIZE)
	var seeds: Array = []
	var inset: float = 3.0   # keep seeds away from the very edges
	for type_data in _c.PLANT_TYPES:
		var sx: float = _rng.randf_range(inset, float(grid_size) - inset)
		var sy: float = _rng.randf_range(inset, float(grid_size) - inset)
		seeds.append({"pos": Vector2(sx, sy), "type": type_data})

	for i in range(grid_size):
		for j in range(grid_size):
			if _is_elevator_cell(i, j):
				continue
			var cell_pos := Vector2(float(i), float(j))
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


# Build a plot with growth-stage state. Spawns a permanent soil box, one
# foliage sphere (scaled per stage), and per-type fruit accents (visible
# only at stage 5). Plant type is pre-assigned by _compute_plant_assignments
# so plants of the same kind cluster into Voronoi patches.
func _build_plot(x: float, z: float, plant_type: Dictionary) -> Dictionary:
	var plant_color: Color = plant_type.foliage_color

	# Soil — its material is shared (we mutate albedo when stage = 0 to read
	# as freshly turned dirt). Each plot gets its own StandardMaterial3D.
	var soil := MeshInstance3D.new()
	soil.name = "Soil"
	var soil_mesh := BoxMesh.new()
	soil_mesh.size = Vector3(0.85, 0.18, 0.85)
	soil.mesh = soil_mesh
	soil.material_override = _make_material(_c.PLANTER_SOIL)
	soil.position = Vector3(x, 0.09, z)
	add_child(soil)

	# Plant — single SphereMesh with radius 1.0; we scale and reposition it
	# per growth stage in _refresh_plot_visuals().
	var plant := MeshInstance3D.new()
	plant.name = "Plant"
	var plant_mesh := SphereMesh.new()
	plant_mesh.radius = 1.0
	plant_mesh.height = 2.0
	plant.mesh = plant_mesh
	plant.material_override = _make_material(plant_color)
	add_child(plant)

	# Per-type fruit visuals — shape + count + position vary by plant type.
	# All start hidden; _refresh_plot_visuals shows them at stage 5.
	var fruits: Array = _build_fruits_for_type(plant_type, x, z)

	# Initial state — randomise across stages 1..5 with random elapsed time
	# inside the stage so the field reads as already alive when the player
	# spawns. Some plots will be immediately harvestable.
	var initial_stage: int = _rng.randi_range(1, _c.GROWTH_STAGE_COUNT)
	var initial_t: float = _rng.randf() * _c.GROWTH_STAGE_DURATION
	var plot := {
		"world_pos": Vector3(x, 0, z),
		"stage": initial_stage,
		"time_in_stage": initial_t,
		"plant_type": plant_type,
		"soil": soil,
		"plant": plant,
		"fruits": fruits,
	}
	_refresh_plot_visuals(plot)
	return plot


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
	var radii := [0.04, 0.08, 0.12, 0.16, 0.20]
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
