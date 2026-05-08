extends RefCounted

# Shared "floor chrome" builders — the room frame any floor uses so they all
# read as part of the same building: slab, perimeter walls (low base + posts
# + translucent glass + top trim), the extension grid blueprint past the
# walls, and the central elevator/spine core.
#
# Used by floor_1 today; iso_prototype's iso_floor.gd will migrate over in a
# follow-up refactor (it currently has its own inline copies of these
# functions). All builders take a parent Node3D + Constants autoload ref so
# they don't need any scene-specific state.
#
# Loaded via preload, NOT class_name, to dodge the headless-import class
# registration issue (F-010): callers do
#   const FloorChrome = preload("res://scenes/shared/floor_chrome.gd")
#   FloorChrome.build_walls(self, _c)


# Builds the floor slab (StaticBody3D with collision) at y = 0. Mesh top
# face sits at y = 0 so the player walks on it. Slab thickness extends
# downward.
static func build_slab(parent: Node3D, c: Node, color: Color = Color(0.18, 0.18, 0.20)) -> void:
	var body := StaticBody3D.new()
	body.name = "SlabBody"
	parent.add_child(body)

	var size := Vector3(c.FLOOR_3D_SIZE, c.FLOOR_3D_SLAB_THICKNESS, c.FLOOR_3D_SIZE)
	var mesh := MeshInstance3D.new()
	mesh.name = "Slab"
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _flat_material(color)
	mesh.position.y = -c.FLOOR_3D_SLAB_THICKNESS * 0.5
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	col_shape.size = size
	col.shape = col_shape
	col.position.y = -c.FLOOR_3D_SLAB_THICKNESS * 0.5
	body.add_child(col)


# Builds 4 perimeter walls. Each wall: low solid base + collision spanning
# full height + vertical posts at WALL_POST_SPACING + thin top trim +
# translucent glass spanning the gap between base and trim.
static func build_walls(parent: Node3D, c: Node) -> void:
	var half: float = c.FLOOR_3D_SIZE * 0.5
	for side in ["+x", "-x", "+z", "-z"]:
		_build_one_wall(parent, c, side, half)


# Builds a faint blueprint-style grid extending outward from each wall —
# 6 perpendicular lines per side fading from solid to transparent over 2 m,
# plus a perpendicular crossbar at the solid/fade boundary that closes the
# rectangle around the room.
static func build_extension_grid(parent: Node3D, c: Node) -> void:
	var half: float = c.FLOOR_3D_SIZE * 0.5
	var y_offset := 0.005
	var pane_count: int = int(c.EXTENSION_PANE_COUNT)
	var pane_step: float = c.FLOOR_3D_SIZE / float(pane_count)
	var pane_positions: Array = []
	for k in range(pane_count):
		pane_positions.append(-half + (float(k) + 0.5) * pane_step)

	var line_mesh := _make_extension_line_mesh(c)
	var line_mat := _make_extension_line_material()
	var bar_mat := _make_extension_crossbar_material(c)

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

		for offset in pane_positions:
			var line := MeshInstance3D.new()
			line.name = "GridExtLine"
			line.mesh = line_mesh
			line.material_override = line_mat
			match s:
				"+x", "-x":
					line.position = origin + Vector3(0, 0, offset)
				"+z", "-z":
					line.position = origin + Vector3(offset, 0, 0)
			line.rotation.y = rot_y
			parent.add_child(line)

		var solid_dist: float = c.EXTENSION_LINE_SOLID_LENGTH
		var bar_length: float = c.FLOOR_3D_SIZE + 2.0 * solid_dist
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
		parent.add_child(bar)


# Builds the central elevator / spine core. Octagonal cross-section
# (square with 45° chamfered corners). Chamfered corners are flat panels
# where the spine pipes run; cardinal faces are doors that slide apart
# (the doors themselves are owned by ElevatorHandler so it can animate
# them based on player proximity). Returns a Dictionary the handler
# uses to attach + drive door panels:
#   {
#     "core": StaticBody3D,             # the elevator root
#     "size": float,                    # outer square side length
#     "chamfer": float,                 # corner cut length
#     "height": float,                  # full elevator visual height
#     "side_length": float,             # cardinal face length after chamfer
#     "cardinals": [{"normal": Vector3, "tangent": Vector3, "centre": Vector3}, ...],
#     "corners":   {"NW": {"centre": Vector3, "tangent": Vector3}, ...},
#   }
# Doors are NOT built here — handler builds them with the geometry data.
static func build_elevator_core(parent: Node3D, c: Node) -> Dictionary:
	var size: float = float(c.ELEVATOR_RADIUS) * 2.0 * c.GARDEN_PLOT_SIZE
	var chamfer: float = c.ELEVATOR_CHAMFER
	var height: float = c.WALL_HEIGHT * c.ELEVATOR_HEIGHT_MULT
	var side_length: float = size - 2.0 * chamfer

	var body := StaticBody3D.new()
	body.name = "ElevatorCore"
	parent.add_child(body)

	# --- Floor + ceiling caps (octagonal prism)
	# Built as 8 wedge-shaped triangles around the centre, top + bottom.
	# Easier: two separate cylinder MeshInstance3D nodes with 8 sides.
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.28, 0.30, 0.36)
	cap_mat.roughness = 0.55
	cap_mat.metallic = 0.4

	# Outer "halo ring" at the top, matching the chamfered footprint.
	var top := MeshInstance3D.new()
	top.name = "TopCap"
	var top_mesh := CylinderMesh.new()
	top_mesh.top_radius = size * 0.5 * 0.92
	top_mesh.bottom_radius = size * 0.5 * 0.92
	top_mesh.height = 0.2
	top_mesh.radial_segments = 8
	top.mesh = top_mesh
	top.material_override = cap_mat
	top.position.y = height + 0.1
	top.rotation.y = PI * 0.125  # rotate to align flat sides with N/S/E/W
	body.add_child(top)

	# Inner translucent core column — taller than wall height so it pokes
	# above the ceiling, suggesting it continues to other floors.
	var inner := MeshInstance3D.new()
	inner.name = "InnerCore"
	var inner_mesh := CylinderMesh.new()
	inner_mesh.top_radius = side_length * 0.5
	inner_mesh.bottom_radius = side_length * 0.5
	inner_mesh.height = height
	inner_mesh.radial_segments = 8
	inner.mesh = inner_mesh
	var inner_mat := StandardMaterial3D.new()
	inner_mat.albedo_color = Color(0.20, 0.25, 0.34, 0.55)
	inner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inner_mat.roughness = 0.3
	inner_mat.metallic = 0.5
	inner_mat.emission_enabled = true
	inner_mat.emission = Color(0.30, 0.55, 0.85)
	inner_mat.emission_energy_multiplier = 0.4
	inner.material_override = inner_mat
	inner.position.y = height * 0.5
	inner.rotation.y = PI * 0.125
	body.add_child(inner)

	# --- Chamfered corner panels (4) — pipes will mount on these.
	for corner in ["NW", "NE", "SE", "SW"]:
		var sx: float = -1.0 if corner == "NW" or corner == "SW" else 1.0
		var sz: float = -1.0 if corner == "NW" or corner == "NE" else 1.0
		var panel := MeshInstance3D.new()
		panel.name = "Chamfer_" + corner
		var pm := BoxMesh.new()
		# Chamfer face is a rectangle: width = chamfer * sqrt(2), height = full.
		pm.size = Vector3(chamfer * sqrt(2.0), height, 0.08)
		panel.mesh = pm
		panel.material_override = cap_mat
		# Position at the corner, midpoint between (size/2, 0, size/2 - chamfer)
		# and (size/2 - chamfer, 0, size/2). Centre = (size/2 - chamfer/2).
		var cx: float = sx * (size * 0.5 - chamfer * 0.5)
		var cz: float = sz * (size * 0.5 - chamfer * 0.5)
		panel.position = Vector3(cx, height * 0.5, cz)
		# Each corner panel is rotated 45° around Y, with sign depending on
		# which corner.
		var yaw_for_corner: float
		match corner:
			"NW": yaw_for_corner = PI * 0.25
			"NE": yaw_for_corner = -PI * 0.25
			"SE": yaw_for_corner = PI * 0.25
			"SW": yaw_for_corner = -PI * 0.25
		panel.rotation.y = yaw_for_corner
		body.add_child(panel)

	# --- Solid collision (square footprint — simpler than octagonal,
	# player can't tell from outside, and saves complexity).
	var col := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(size, height, size)
	col.shape = col_shape
	col.position.y = height * 0.5
	body.add_child(col)

	# --- Geometry-data dict for handler to build doors against.
	# Cardinal faces (N/S/E/W) — used by ElevatorHandler to spawn door
	# panels along each face's tangent axis.
	var cardinals := []
	for spec in [
		{"name": "N", "normal": Vector3(0, 0, -1), "tangent": Vector3(1, 0, 0), "centre_offset": Vector3(0, 0, -size * 0.5)},
		{"name": "S", "normal": Vector3(0, 0, 1), "tangent": Vector3(1, 0, 0), "centre_offset": Vector3(0, 0, size * 0.5)},
		{"name": "E", "normal": Vector3(1, 0, 0), "tangent": Vector3(0, 0, 1), "centre_offset": Vector3(size * 0.5, 0, 0)},
		{"name": "W", "normal": Vector3(-1, 0, 0), "tangent": Vector3(0, 0, 1), "centre_offset": Vector3(-size * 0.5, 0, 0)},
	]:
		cardinals.append(spec)

	var corners := {}
	for corner in ["NW", "NE", "SE", "SW"]:
		var sx: float = -1.0 if corner == "NW" or corner == "SW" else 1.0
		var sz: float = -1.0 if corner == "NW" or corner == "NE" else 1.0
		var cx: float = sx * (size * 0.5 - chamfer * 0.5)
		var cz: float = sz * (size * 0.5 - chamfer * 0.5)
		# Tangent runs along the chamfer face — clockwise around the elevator.
		var tan: Vector3
		match corner:
			"NW": tan = Vector3(1, 0, -1).normalized()
			"NE": tan = Vector3(1, 0, 1).normalized()
			"SE": tan = Vector3(-1, 0, 1).normalized()
			"SW": tan = Vector3(-1, 0, -1).normalized()
		corners[corner] = {
			"centre": Vector3(cx, 0, cz),
			"tangent": tan,
			"normal": Vector3(sx, 0, sz).normalized(),
		}

	return {
		"core": body,
		"size": size,
		"chamfer": chamfer,
		"height": height,
		"side_length": side_length,
		"cardinals": cardinals,
		"corners": corners,
	}


# --- Internal --------------------------------------------------------------

static func _build_one_wall(parent: Node3D, c: Node, side: String, half: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Wall_" + side
	parent.add_child(body)
	var wall_along_x: bool = side in ["+z", "-z"]
	var perp_pos: float = half if side in ["+x", "+z"] else -half
	var length: float = c.FLOOR_3D_SIZE
	var thick: float = c.WALL_THICKNESS

	var base := MeshInstance3D.new()
	base.name = "Base"
	var base_size: Vector3
	if wall_along_x:
		base_size = Vector3(length, c.WALL_BASE_HEIGHT, thick)
	else:
		base_size = Vector3(thick, c.WALL_BASE_HEIGHT, length)
	var bm := BoxMesh.new()
	bm.size = base_size
	base.mesh = bm
	base.material_override = _flat_material(Color(0.32, 0.32, 0.36))
	base.position = Vector3(
		0.0 if wall_along_x else perp_pos,
		c.WALL_BASE_HEIGHT * 0.5,
		perp_pos if wall_along_x else 0.0,
	)
	body.add_child(base)

	var col := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	if wall_along_x:
		col_shape.size = Vector3(length, c.WALL_HEIGHT, thick)
	else:
		col_shape.size = Vector3(thick, c.WALL_HEIGHT, length)
	col.shape = col_shape
	col.position = Vector3(
		0.0 if wall_along_x else perp_pos,
		c.WALL_HEIGHT * 0.5,
		perp_pos if wall_along_x else 0.0,
	)
	body.add_child(col)

	var post_count := int(length / c.WALL_POST_SPACING) + 1
	for k in range(post_count):
		var t: float = float(k) / float(post_count - 1)
		var along: float = -length * 0.5 + t * length
		var post := MeshInstance3D.new()
		post.name = "Post_%d" % k
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.18, c.WALL_HEIGHT - c.WALL_BASE_HEIGHT, 0.18)
		post.mesh = post_mesh
		post.material_override = _flat_material(Color(0.38, 0.38, 0.42))
		post.position = Vector3(
			along if wall_along_x else perp_pos,
			(c.WALL_BASE_HEIGHT + c.WALL_HEIGHT) * 0.5,
			perp_pos if wall_along_x else along,
		)
		body.add_child(post)

	var trim := MeshInstance3D.new()
	trim.name = "TopTrim"
	var trim_mesh := BoxMesh.new()
	if wall_along_x:
		trim_mesh.size = Vector3(length, 0.12, thick * 1.05)
	else:
		trim_mesh.size = Vector3(thick * 1.05, 0.12, length)
	trim.mesh = trim_mesh
	trim.material_override = _flat_material(Color(0.28, 0.28, 0.32))
	trim.position = Vector3(
		0.0 if wall_along_x else perp_pos,
		c.WALL_HEIGHT - 0.06,
		perp_pos if wall_along_x else 0.0,
	)
	body.add_child(trim)

	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	var glass_mesh := BoxMesh.new()
	var glass_h: float = c.WALL_HEIGHT - c.WALL_BASE_HEIGHT - 0.12
	if wall_along_x:
		glass_mesh.size = Vector3(length - 0.4, glass_h, 0.05)
	else:
		glass_mesh.size = Vector3(0.05, glass_h, length - 0.4)
	glass.mesh = glass_mesh
	glass.material_override = _make_window_material()
	glass.position = Vector3(
		0.0 if wall_along_x else perp_pos,
		c.WALL_BASE_HEIGHT + glass_h * 0.5,
		perp_pos if wall_along_x else 0.0,
	)
	body.add_child(glass)


static func _flat_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	return m


static func _make_window_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.85, 1.0, 0.25)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.5
	return m


static func _make_extension_line_mesh(c: Node) -> ArrayMesh:
	var thick := 0.04
	var solid_len: float = c.EXTENSION_LINE_SOLID_LENGTH
	var total_len: float = c.EXTENSION_GRID_LENGTH
	var peak: float = c.EXTENSION_LINE_PEAK_ALPHA

	var verts := PackedVector3Array([
		Vector3(0.0,       0, -thick * 0.5), Vector3(0.0,       0, thick * 0.5),
		Vector3(solid_len, 0, -thick * 0.5), Vector3(solid_len, 0, thick * 0.5),
		Vector3(total_len, 0, -thick * 0.5), Vector3(total_len, 0, thick * 0.5),
	])
	var solid := Color(1, 1, 1, peak)
	var fade := Color(1, 1, 1, 0.0)
	var colors := PackedColorArray([solid, solid, solid, solid, fade, fade])
	var indices := PackedInt32Array([
		0, 1, 2,  1, 3, 2,
		2, 3, 4,  3, 5, 4,
	])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


static func _make_extension_line_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1, 1)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _make_extension_crossbar_material(c: Node) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1, c.EXTENSION_LINE_PEAK_ALPHA)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
