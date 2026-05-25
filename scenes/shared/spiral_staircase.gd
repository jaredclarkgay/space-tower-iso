extends RefCounted

# Spiral ramp wrapping the elevator's outer octagon. Climbs
# FLOOR_3D_STORY_HEIGHT in one full revolution. Used on Floor 3 to reach
# Floor 4 (alternative travel to the elevator; Floor 4 has no elevator stop).
#
# Geometry strategy:
# - Single continuous-looking ramp built from N tilted box segments.
# - Adjacent segments OVERLAP tangentially by ~40% of their arc length so
#   there are no floor gaps at the outer edge as the box rotates 360/N
#   degrees between neighbours. (Without this overlap, the player walks
#   off the segment they're on at the seam and lands in a wedge-shaped
#   void at the outer edge — the original v1 navigation bug.)
# - Each segment carries its own thin BoxShape3D collider so the player
#   walks up the ramp surface directly. No separate "collision under
#   visible steps" trickery.
# - No discrete step risers, no balusters, no handrail. V1 had all three;
#   the result was unreadable visual noise. A single warm-wood spiral
#   reads as a real piece of architecture and is easy to navigate.
# - Inner edge gets a thin dark stripe so the spiral curve reads even when
#   the player is standing on it from above.
#
# Loaded via preload, NOT class_name (per F-010).

const RAMP_THICKNESS := 0.10                     # m
const SEAM_OVERLAP_FRACTION := 0.40              # arc-length overlap between adjacent segments
const EDGE_STRIPE_DEPTH := 0.08                  # m radial — dark stripe along inner edge


# Builds the ramp as a child of `parent`. `base_y` is the height of the
# bottom of the first segment; the top of the last segment lands at
# base_y + FLOOR_3D_STORY_HEIGHT. `start_angle_rad` defines where the
# bottom of the ramp is (0 = +X axis, rotates CCW around +Y as you climb).
static func build(parent: Node3D, c: Node, base_y: float, start_angle_rad: float = 0.0) -> void:
	var root := Node3D.new()
	root.name = "SpiralRamp"
	root.position = Vector3(0, base_y, 0)
	parent.add_child(root)

	_build_ramp_segments(root, c, start_angle_rad)


static func _build_ramp_segments(parent: Node3D, c: Node, start_angle_rad: float) -> void:
	var n: int = int(c.STAIRCASE_RAMP_SEGMENTS)
	var story: float = float(c.FLOOR_3D_STORY_HEIGHT)
	var r_in: float = float(c.STAIRCASE_INNER_RADIUS)
	var r_out: float = float(c.STAIRCASE_OUTER_RADIUS)
	var r_mid: float = (r_in + r_out) * 0.5
	var tread_depth: float = r_out - r_in
	var dtheta: float = TAU / float(n)
	var dheight: float = story / float(n)
	var arc_len: float = r_mid * dtheta
	var slope_rad: float = atan2(dheight, arc_len)
	var seam_overlap: float = arc_len * SEAM_OVERLAP_FRACTION

	# Warm wood material, slightly emissive so the ramp reads in dim rooms.
	var ramp_mat := StandardMaterial3D.new()
	ramp_mat.albedo_color = c.STAIRCASE_TREAD_COLOR
	ramp_mat.roughness = 0.85
	ramp_mat.emission_enabled = true
	ramp_mat.emission = c.STAIRCASE_TREAD_EMISSION
	ramp_mat.emission_energy_multiplier = 0.6

	# Thin dark inset stripe along the inner edge — readable from above,
	# helps the spiral curve read visually without adding handrail clutter.
	var stripe_mat := StandardMaterial3D.new()
	stripe_mat.albedo_color = c.STAIRCASE_EDGE_STRIPE_COLOR
	stripe_mat.roughness = 0.95

	for i in range(n):
		var theta_mid: float = start_angle_rad + (float(i) + 0.5) * dtheta
		var y_mid: float = (float(i) + 0.5) * dheight

		var cx: float = r_mid * cos(theta_mid)
		var cz: float = r_mid * sin(theta_mid)
		var tangent_yaw: float = theta_mid + PI * 0.5
		var basis := Basis().rotated(Vector3.UP, tangent_yaw)
		# Tilt about the box's local X (now tangent) so the leading edge
		# rises in the direction of motion (CCW around +Y).
		basis = basis.rotated(basis.x, slope_rad)
		var segment_transform := Transform3D(basis, Vector3(cx, y_mid, cz))

		var body := StaticBody3D.new()
		body.name = "RampSeg_%d" % i
		body.transform = segment_transform
		parent.add_child(body)

		# Ramp top surface mesh — visible and walkable.
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(arc_len + seam_overlap, RAMP_THICKNESS, tread_depth)
		mesh.mesh = box
		mesh.material_override = ramp_mat
		body.add_child(mesh)

		# Matching collision.
		var col := CollisionShape3D.new()
		var col_shape := BoxShape3D.new()
		col_shape.size = Vector3(arc_len + seam_overlap, RAMP_THICKNESS, tread_depth)
		col.shape = col_shape
		body.add_child(col)

		# Dark stripe along the inner edge (visible from above as the
		# spiral curve). Inset slightly above the ramp surface.
		var stripe := MeshInstance3D.new()
		var stripe_box := BoxMesh.new()
		stripe_box.size = Vector3(arc_len + seam_overlap, 0.015, EDGE_STRIPE_DEPTH)
		stripe.mesh = stripe_box
		stripe.material_override = stripe_mat
		stripe.position = Vector3(0, RAMP_THICKNESS * 0.5 + 0.008, -tread_depth * 0.5 + EDGE_STRIPE_DEPTH * 0.5)
		body.add_child(stripe)
