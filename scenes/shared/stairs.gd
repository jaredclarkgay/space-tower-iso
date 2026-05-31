extends RefCounted

# Straight inclined stairs from one floor to the next. Single piece of
# geometry — clean to read, simple to walk up.
#
# Layout: bottom of stairs sits south of the central elevator at
# (0, base_y, STAIRCASE_BOTTOM_Z), top is STAIRCASE_RUN south of that,
# STAIRCASE_RUN further south, at height base_y + FLOOR_3D_STORY_HEIGHT.
# Slope is ~28° (atan(3/5.5)) which the CharacterBody3D can walk up.
#
# Visible:
#   - Smooth inclined slab (the actual walkable surface + collision).
#   - STAIRCASE_STEP_COUNT step risers stacked on top as visual fidelity
#     (no collision — the player walks on the smooth slab beneath).
#   - Two side rails along the long edges so the staircase reads as a
#     contained structure.
#
# `base_y` is the height of the staircase's bottom edge on this floor.
# On Floor 3 this is FLOOR_3D_TOP_Y (~0.2 m); the staircase climbs to
# Floor 3's ceiling level (Floor 4's floor). On Floor 4 the same
# staircase is rendered with base_y = FLOOR_3D_TOP_Y - FLOOR_3D_STORY_HEIGHT
# (~-2.8 m) so the visible portion above Floor 4's slab matches the top
# of what's visible on Floor 3.
#
# Loaded via preload, NOT class_name (per F-010).


# Returns the world-space top point of the stairs (where the player arrives
# at the top of the ramp). Used by the floor controllers to position
# trigger zones + arrival spawns.
static func top_world_position(c: Node, base_y: float) -> Vector3:
	return Vector3(0.0, base_y + float(c.FLOOR_3D_STORY_HEIGHT), float(c.STAIRCASE_BOTTOM_Z) + float(c.STAIRCASE_RUN))


# Returns the world-space bottom point of the stairs (where the player
# starts walking up).
static func bottom_world_position(c: Node, base_y: float) -> Vector3:
	return Vector3(0.0, base_y, float(c.STAIRCASE_BOTTOM_Z))


# Builds the staircase as a child of `parent`. Returns nothing — the
# stairs are self-contained geometry and the floor controllers handle
# trigger zones separately.
static func build(parent: Node3D, c: Node, base_y: float) -> void:
	var root := Node3D.new()
	root.name = "Stairs"
	parent.add_child(root)

	var run: float = float(c.STAIRCASE_RUN)
	var rise: float = float(c.FLOOR_3D_STORY_HEIGHT)
	var width: float = float(c.STAIRCASE_WIDTH)
	var thickness: float = float(c.STAIRCASE_THICKNESS)
	var z0: float = float(c.STAIRCASE_BOTTOM_Z)
	var slope_rad: float = atan2(rise, run)
	var hypot: float = sqrt(run * run + rise * rise)

	# Inclined slab (collision + walkable surface). Box is tilted about
	# X so its top surface forms the ramp. Center of the box is at the
	# midpoint of the ramp, halfway between bottom and top.
	var body := StaticBody3D.new()
	body.name = "RampBody"
	root.add_child(body)

	var ramp_mat := StandardMaterial3D.new()
	ramp_mat.albedo_color = c.STAIRCASE_TREAD_COLOR
	ramp_mat.roughness = 0.85
	ramp_mat.emission_enabled = true
	ramp_mat.emission = c.STAIRCASE_TREAD_EMISSION
	ramp_mat.emission_energy_multiplier = 0.5

	var ramp_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, thickness, hypot)
	ramp_mesh.mesh = box
	ramp_mesh.material_override = ramp_mat
	body.add_child(ramp_mesh)

	# Collision is much thicker than the visual slab and shifted down along the
	# ramp normal so its WALKABLE TOP stays flush with the visible ramp while a
	# solid mass extends below — this buries the base lip under the floor slab
	# so the player walks straight on instead of catching on a thin edge.
	var col := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	var col_thickness: float = thickness * 5.0
	col_shape.size = Vector3(width, col_thickness, hypot)
	col.shape = col_shape
	col.position.y = -(col_thickness - thickness) * 0.5   # local -Y = ramp underside
	body.add_child(col)

	# Position + tilt the slab. Centre of the slab sits at the midpoint
	# of the ramp run, lifted to the midpoint of the rise.
	var centre_z: float = z0 + run * 0.5
	var centre_y: float = base_y + rise * 0.5
	var basis := Basis()
	# Rotate the box's long axis (local Z) to point along the ramp's
	# slope. The box's local +Z is "tangent up the slope" after this.
	basis = basis.rotated(Vector3.RIGHT, -slope_rad)
	body.transform = Transform3D(basis, Vector3(0, centre_y, centre_z))

	# Visible step risers on top of the ramp — no collision. Each riser
	# is a small horizontal tread + a thin vertical riser, stacked along
	# the ramp.
	_build_step_risers(root, c, base_y)
	# Side rails — thin boxes along the two long edges.
	_build_side_rails(root, c, base_y)


# Builds STAIRCASE_STEP_COUNT visible step risers on top of the ramp.
# Each step gets a horizontal tread + thin vertical riser. Treads are
# tilted slightly to align with the ramp surface so they don't appear
# to float.
static func _build_step_risers(parent: Node3D, c: Node, base_y: float) -> void:
	var n: int = int(c.STAIRCASE_STEP_COUNT)
	var run: float = float(c.STAIRCASE_RUN)
	var rise: float = float(c.FLOOR_3D_STORY_HEIGHT)
	var width: float = float(c.STAIRCASE_WIDTH)
	var z0: float = float(c.STAIRCASE_BOTTOM_Z)
	var step_run: float = run / float(n)
	var step_rise: float = rise / float(n)

	var tread_mat := StandardMaterial3D.new()
	tread_mat.albedo_color = c.STAIRCASE_TREAD_COLOR
	tread_mat.roughness = 0.85

	var riser_mat := StandardMaterial3D.new()
	riser_mat.albedo_color = c.STAIRCASE_RISER_COLOR
	riser_mat.roughness = 0.95

	for i in range(n):
		var step_top_y: float = base_y + step_rise * float(i + 1)
		var step_back_z: float = z0 + step_run * float(i)
		var step_front_z: float = z0 + step_run * float(i + 1)
		var step_centre_z: float = (step_back_z + step_front_z) * 0.5

		# Tread (thin horizontal plate on top of the ramp at this step).
		var tread := MeshInstance3D.new()
		var tmesh := BoxMesh.new()
		tmesh.size = Vector3(width * 0.96, 0.04, step_run * 0.96)
		tread.mesh = tmesh
		tread.material_override = tread_mat
		tread.position = Vector3(0, step_top_y + 0.005, step_centre_z)
		parent.add_child(tread)

		# Riser (vertical face between this step and the one below).
		var riser := MeshInstance3D.new()
		var rmesh := BoxMesh.new()
		rmesh.size = Vector3(width * 0.96, step_rise * 0.95, 0.04)
		riser.mesh = rmesh
		riser.material_override = riser_mat
		riser.position = Vector3(0, step_top_y - step_rise * 0.5, step_back_z + 0.02)
		parent.add_child(riser)


# Two thin side rails along the long edges of the ramp, tilted to follow
# the slope. Pure visual — no collision.
static func _build_side_rails(parent: Node3D, c: Node, base_y: float) -> void:
	var run: float = float(c.STAIRCASE_RUN)
	var rise: float = float(c.FLOOR_3D_STORY_HEIGHT)
	var width: float = float(c.STAIRCASE_WIDTH)
	var z0: float = float(c.STAIRCASE_BOTTOM_Z)
	var hypot: float = sqrt(run * run + rise * rise)
	var slope_rad: float = atan2(rise, run)
	var rail_height: float = 0.95
	var rail_thickness: float = 0.06

	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = c.STAIRCASE_RAIL_COLOR
	rail_mat.roughness = 0.85

	var centre_z: float = z0 + run * 0.5
	var centre_y: float = base_y + rise * 0.5

	for x_side in [-1, 1]:
		var rail := MeshInstance3D.new()
		var rmesh := BoxMesh.new()
		rmesh.size = Vector3(rail_thickness, rail_thickness, hypot)
		rail.mesh = rmesh
		rail.material_override = rail_mat
		var basis := Basis().rotated(Vector3.RIGHT, -slope_rad)
		var rail_offset_x: float = float(x_side) * (width * 0.5 + rail_thickness * 0.5)
		rail.transform = Transform3D(basis, Vector3(rail_offset_x, centre_y + rail_height, centre_z))
		parent.add_child(rail)
