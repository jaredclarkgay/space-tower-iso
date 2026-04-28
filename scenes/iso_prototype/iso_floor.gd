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
		0 if wall_along_x else perp_pos,
		_c.WALL_BASE_HEIGHT * 0.5,
		perp_pos if wall_along_x else 0
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
		0 if wall_along_x else perp_pos,
		_c.WALL_HEIGHT * 0.5,
		perp_pos if wall_along_x else 0
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
		0 if wall_along_x else perp_pos,
		_c.WALL_HEIGHT - 0.06,
		perp_pos if wall_along_x else 0
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
		0 if wall_along_x else perp_pos,
		_c.WALL_BASE_HEIGHT + glass_h * 0.5,
		perp_pos if wall_along_x else 0
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
	var origin: float = -_c.FLOOR_3D_SIZE * 0.5 + _c.GARDEN_PLOT_SIZE * 0.5
	for i in range(_c.GARDEN_GRID_SIZE):
		for j in range(_c.GARDEN_GRID_SIZE):
			if _is_elevator_cell(i, j):
				continue
			var x: float = origin + float(i) * _c.GARDEN_PLOT_SIZE
			var z: float = origin + float(j) * _c.GARDEN_PLOT_SIZE
			# ~12% of plots become "feature" plants with stem + extra foliage.
			var feature := _rng.randf() < 0.12
			# Light is shared across rows of feature plants (spaced out).
			_build_plot(x, z, feature)
			if feature and (i + j) % 4 == 0:
				_build_plot_grow_light(x, z)


func _is_elevator_cell(i: int, j: int) -> bool:
	# Elevator footprint: 4×4 cells centered on the grid centre.
	var center: float = float(_c.GARDEN_GRID_SIZE) * 0.5 - 0.5
	return absf(float(i) - center) < float(_c.ELEVATOR_RADIUS) \
		and absf(float(j) - center) < float(_c.ELEVATOR_RADIUS)


func _build_plot(x: float, z: float, feature: bool) -> void:
	# Soil — small box.
	var soil := MeshInstance3D.new()
	soil.name = "Soil"
	var soil_mesh := BoxMesh.new()
	soil_mesh.size = Vector3(0.85, 0.18, 0.85)
	soil.mesh = soil_mesh
	soil.material_override = _make_material(_c.PLANTER_SOIL)
	soil.position = Vector3(x, 0.09, z)
	add_child(soil)

	# Foliage — 1 base sphere always; feature plants get 2 extras.
	var greens := [
		_c.PLANTER_GREEN,
		Color(0.32, 0.55, 0.22),
		Color(0.45, 0.7, 0.34),
		Color(0.25, 0.45, 0.18),
	]
	var base_color: Color = greens[_rng.randi() % greens.size()]
	var base_radius: float = 0.18 + _rng.randf() * 0.08
	var base := MeshInstance3D.new()
	base.name = "Foliage"
	var bsphere := SphereMesh.new()
	bsphere.radius = base_radius
	bsphere.height = base_radius * 2.0
	base.mesh = bsphere
	base.material_override = _make_material(base_color)
	base.position = Vector3(x, 0.18 + base_radius * 0.8, z)
	add_child(base)

	if feature:
		# Stem.
		var stem := MeshInstance3D.new()
		stem.name = "Stem"
		var sm := CylinderMesh.new()
		sm.top_radius = 0.04
		sm.bottom_radius = 0.06
		sm.height = 0.5
		stem.mesh = sm
		stem.material_override = _make_material(Color(0.32, 0.42, 0.18))
		stem.position = Vector3(x, 0.43, z)
		add_child(stem)
		# Extra foliage spheres.
		for k in range(2):
			var color: Color = greens[_rng.randi() % greens.size()]
			var radius: float = 0.18 + _rng.randf() * 0.1
			var leaf := MeshInstance3D.new()
			leaf.name = "Foliage"
			var ls := SphereMesh.new()
			ls.radius = radius
			ls.height = radius * 2.0
			leaf.mesh = ls
			leaf.material_override = _make_material(color)
			var dx := (_rng.randf() - 0.5) * 0.3
			var dz := (_rng.randf() - 0.5) * 0.3
			var dy: float = 0.55 + _rng.randf() * 0.2
			leaf.position = Vector3(x + dx, dy, z + dz)
			add_child(leaf)
		# Fruit accent.
		if _rng.randf() < 0.7:
			var fruit := MeshInstance3D.new()
			fruit.name = "Fruit"
			var fmesh := SphereMesh.new()
			fmesh.radius = 0.08
			fmesh.height = 0.16
			fruit.mesh = fmesh
			fruit.material_override = _make_material(Color(0.85, 0.25, 0.2))
			fruit.position = Vector3(x + 0.1, 0.55, z + 0.1)
			add_child(fruit)


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
	var ext: float = _c.EXTENSION_GRID_LENGTH
	var y_offset := 0.005
	var pane_positions: Array = _c.EXTENSION_PANE_POSITIONS

	var line_mesh := _make_extension_line_mesh()
	var line_mat := _make_extension_line_material()
	var bar_mat := _make_extension_crossbar_material()

	# Per-side: 6 outgoing lines from pane centers, plus 1 crossbar at the
	# solid/fade boundary. Crossbar extends slightly past the corners
	# (length ext beyond, so it forms a closed blueprint rectangle).
	for s in ["+x", "-x", "+z", "-z"]:
		var rot_y := 0.0
		var origin: Vector3
		var crossbar_axis_along_x := false   # whether crossbar's length runs along X
		match s:
			"+x":
				rot_y = 0.0
				origin = Vector3(half, y_offset, 0)
				crossbar_axis_along_x = false   # crossbar along Z
			"-x":
				rot_y = PI
				origin = Vector3(-half, y_offset, 0)
				crossbar_axis_along_x = false
			"+z":
				rot_y = -PI * 0.5
				origin = Vector3(0, y_offset, half)
				crossbar_axis_along_x = true
			"-z":
				rot_y = PI * 0.5
				origin = Vector3(0, y_offset, -half)
				crossbar_axis_along_x = true

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
