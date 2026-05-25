extends RefCounted

# Spiral staircase that wraps the central elevator's outer octagon, climbing
# FLOOR_3D_STORY_HEIGHT (one story) in one full revolution. Used on Floor 3
# to ascend to Floor 4 (alternative travel to the elevator; Floor 4 has no
# elevator stop and is reachable ONLY via these stairs).
#
# Geometry strategy (rules/godot_collision_shape_too_aggressive.md applies):
# - Visible: STAIRCASE_STEP_COUNT individual step risers — small flat boxes
#   stacked spirally with no collision. Reads as a real staircase to the
#   player.
# - Collision: STAIRCASE_RAMP_SEGMENTS smooth tilted boxes underneath
#   (each segment covers 360°/N of arc and is tilted along its tangential
#   direction). The player walks UP the smooth slope while seeing the
#   discrete steps.
# - Handrail: a thin curved bar on the OUTER edge at handrail height,
#   built as the same N small box segments tangent to the spiral.
#
# Loaded via preload, NOT class_name (per F-010 / rules/gdscript_class_name_caveats.md).
#   const SpiralStaircase = preload("res://scenes/shared/spiral_staircase.gd")
#   SpiralStaircase.build(self, _c, base_y)
#
# `base_y` is the height of the bottom step's top surface. On Floor 3 this is
# FLOOR_3D_TOP_Y (player feet level); the top step lands at base_y + STORY_HEIGHT
# which is the surface of Floor 4 above.


# Builds the staircase as a child of `parent`. Returns nothing — the staircase
# is self-contained geometry; nothing else needs handles into it. `start_angle_rad`
# defines where step #0 is positioned (0 = +X axis, rotates CCW).
static func build(parent: Node3D, c: Node, base_y: float, start_angle_rad: float = 0.0) -> void:
	var root := Node3D.new()
	root.name = "SpiralStaircase"
	root.position = Vector3(0, base_y, 0)
	parent.add_child(root)

	_build_collision_ramps(root, c, start_angle_rad)
	_build_step_treads(root, c, start_angle_rad)
	_build_handrail(root, c, start_angle_rad)


# Builds STAIRCASE_RAMP_SEGMENTS tilted box StaticBody3D colliders that the
# player walks up. Each segment covers 2π/N angular arc and rises
# STORY_HEIGHT/N in height. The box is positioned at mid-arc, mid-height,
# mid-radius, rotated so its long axis is tangent to the spiral and tilted
# upward along that axis.
static func _build_collision_ramps(parent: Node3D, c: Node, start_angle_rad: float) -> void:
	var n: int = int(c.STAIRCASE_RAMP_SEGMENTS)
	var story: float = float(c.FLOOR_3D_STORY_HEIGHT)
	var r_in: float = float(c.STAIRCASE_INNER_RADIUS)
	var r_out: float = float(c.STAIRCASE_OUTER_RADIUS)
	var r_mid: float = (r_in + r_out) * 0.5
	var tread_depth: float = r_out - r_in           # radial extent of a tread
	var dtheta: float = TAU / float(n)
	var dheight: float = story / float(n)
	var arc_len: float = r_mid * dtheta             # tangential length of one segment at midradius
	var slope_rad: float = atan2(dheight, arc_len)  # tilt about tangential axis

	# Slight overlap between segments along the tangential axis so seams
	# don't introduce micro-gaps the player can clip into.
	var seam_overlap: float = 0.04

	for i in range(n):
		var theta_mid: float = start_angle_rad + (float(i) + 0.5) * dtheta
		var y_mid: float = (float(i) + 0.5) * dheight

		var body := StaticBody3D.new()
		body.name = "RampSeg_%d" % i
		parent.add_child(body)

		# Visible ramp underside (subtle, matches step riser tone).
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		# Length tangentially = arc + seam overlap; radial depth = tread depth;
		# vertical thickness = small (it's just the ramp slab).
		box.size = Vector3(arc_len + seam_overlap, 0.10, tread_depth)
		mesh.mesh = box
		mesh.material_override = _flat_material(c.STAIRCASE_RISER_COLOR)
		body.add_child(mesh)

		var col := CollisionShape3D.new()
		var col_shape := BoxShape3D.new()
		col_shape.size = Vector3(arc_len + seam_overlap, 0.10, tread_depth)
		col.shape = col_shape
		body.add_child(col)

		# Position: midradius point at midarc, lifted to midheight.
		# Rotation: face tangent (rotate Y by theta_mid + π/2 so long axis
		# is tangent), then tilt about that tangent axis by slope_rad
		# (positive tilt raises the leading edge in the direction of travel).
		var cx: float = r_mid * cos(theta_mid)
		var cz: float = r_mid * sin(theta_mid)
		var tangent_yaw: float = theta_mid + PI * 0.5
		var basis := Basis().rotated(Vector3.UP, tangent_yaw)
		# Tilt about the box's local X (now tangent) so the leading edge
		# rises in the direction of motion (CCW around +Y).
		basis = basis.rotated(basis.x, slope_rad)
		body.transform = Transform3D(basis, Vector3(cx, y_mid, cz))


# Builds STAIRCASE_STEP_COUNT visible step risers, each a flat tread box and
# a thin vertical riser. No collision — the ramp underneath carries that.
# Each step is positioned at its angular slot with its top surface exactly
# matching the smooth ramp height at that angle.
static func _build_step_treads(parent: Node3D, c: Node, start_angle_rad: float) -> void:
	var n: int = int(c.STAIRCASE_STEP_COUNT)
	var story: float = float(c.FLOOR_3D_STORY_HEIGHT)
	var r_in: float = float(c.STAIRCASE_INNER_RADIUS)
	var r_out: float = float(c.STAIRCASE_OUTER_RADIUS)
	var r_mid: float = (r_in + r_out) * 0.5
	var tread_depth: float = r_out - r_in
	var dtheta: float = TAU / float(n)
	var dheight: float = story / float(n)
	var arc_len: float = r_mid * dtheta

	var tread_mat := _flat_material(c.STAIRCASE_TREAD_COLOR)
	var riser_mat := _flat_material(c.STAIRCASE_RISER_COLOR)

	for i in range(n):
		var theta_mid: float = start_angle_rad + (float(i) + 0.5) * dtheta
		# Step top surface y = ramp height at theta_mid. Top of step #i
		# sits at the height the ramp passes through at this angle.
		var top_y: float = (float(i) + 0.5) * dheight

		var cx: float = r_mid * cos(theta_mid)
		var cz: float = r_mid * sin(theta_mid)
		var tangent_yaw: float = theta_mid + PI * 0.5
		var basis := Basis().rotated(Vector3.UP, tangent_yaw)

		# Tread plate — small flat box sitting at top_y.
		var tread := MeshInstance3D.new()
		tread.name = "StepTread_%d" % i
		var tmesh := BoxMesh.new()
		tmesh.size = Vector3(arc_len * 0.95, float(c.STAIRCASE_STEP_THICKNESS), tread_depth * 0.95)
		tread.mesh = tmesh
		tread.material_override = tread_mat
		tread.transform = Transform3D(basis, Vector3(cx, top_y + 0.005, cz))
		parent.add_child(tread)

		# Riser — thin vertical strip on the leading (low-angle) edge of
		# this tread. Sits underneath the tread plate.
		var riser := MeshInstance3D.new()
		riser.name = "StepRiser_%d" % i
		var rmesh := BoxMesh.new()
		rmesh.size = Vector3(dheight + 0.01, dheight, tread_depth * 0.93)
		riser.mesh = rmesh
		riser.material_override = riser_mat
		# Place riser at the trailing edge of the previous step (= leading edge
		# of this step). The riser is centered tangentially at theta_mid - dtheta * 0.5
		# and vertically halfway down from top_y.
		var theta_back: float = theta_mid - dtheta * 0.5
		var cx_back: float = r_mid * cos(theta_back)
		var cz_back: float = r_mid * sin(theta_back)
		var basis_back := Basis().rotated(Vector3.UP, theta_back + PI * 0.5)
		riser.transform = Transform3D(basis_back, Vector3(cx_back, top_y - dheight * 0.5, cz_back))
		parent.add_child(riser)


# Builds the outer-edge handrail as N short cylinder segments tangent to
# the spiral at handrail height. Subtle cool-grey material.
static func _build_handrail(parent: Node3D, c: Node, start_angle_rad: float) -> void:
	var n: int = int(c.STAIRCASE_STEP_COUNT)
	var story: float = float(c.FLOOR_3D_STORY_HEIGHT)
	var r_out: float = float(c.STAIRCASE_OUTER_RADIUS)
	var rail_height: float = float(c.STAIRCASE_HANDRAIL_HEIGHT)
	var rail_radius: float = float(c.STAIRCASE_HANDRAIL_RADIUS)
	var dtheta: float = TAU / float(n)
	var dheight: float = story / float(n)
	# Place handrail slightly inboard of the outer edge so it visually reads
	# as belonging to the staircase, not floating off it.
	var rail_r: float = r_out - 0.06
	var arc_len: float = rail_r * dtheta
	var handrail_mat := _flat_material(c.STAIRCASE_HANDRAIL_COLOR)

	for i in range(n):
		var theta_mid: float = start_angle_rad + (float(i) + 0.5) * dtheta
		var top_y: float = (float(i) + 0.5) * dheight

		var seg := MeshInstance3D.new()
		seg.name = "Handrail_%d" % i
		var mesh := CylinderMesh.new()
		mesh.top_radius = rail_radius
		mesh.bottom_radius = rail_radius
		mesh.height = arc_len + 0.04
		seg.mesh = mesh
		seg.material_override = handrail_mat

		var cx: float = rail_r * cos(theta_mid)
		var cz: float = rail_r * sin(theta_mid)
		var tangent_yaw: float = theta_mid + PI * 0.5
		# Cylinder's local +Y points up; rotate so it's tangent (lay it
		# along the spiral arc).
		var basis := Basis().rotated(Vector3.UP, tangent_yaw)
		basis = basis.rotated(basis.x, PI * 0.5)  # lay cylinder on its side
		seg.transform = Transform3D(basis, Vector3(cx, top_y + rail_height, cz))
		parent.add_child(seg)

		# Vertical baluster every 2 steps connecting tread → handrail.
		if i % 2 == 0:
			var balu := MeshInstance3D.new()
			balu.name = "Baluster_%d" % i
			var bmesh := CylinderMesh.new()
			bmesh.top_radius = rail_radius * 0.65
			bmesh.bottom_radius = rail_radius * 0.65
			bmesh.height = rail_height - 0.03
			balu.mesh = bmesh
			balu.material_override = handrail_mat
			balu.position = Vector3(cx, top_y + rail_height * 0.5, cz)
			parent.add_child(balu)


static func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat
