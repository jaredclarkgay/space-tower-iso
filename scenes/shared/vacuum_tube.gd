extends RefCounted

# Shared vacuum-tube geometry — the four corner conduits every floor renders so
# they tile corner-to-corner up the whole stack (the way the elevator spine
# pipes do via floor_chrome.build_passive_spine_pipes). Each floor builds its
# own one-story segment in LOCAL space (slab top at y=0); stacked at the story
# height, the segments meet flush and read as four continuous columns.
#
# Loaded via preload, NOT class_name, to dodge the headless-import class
# registration issue (F-010):
#   const VacuumTube = preload("res://scenes/shared/vacuum_tube.gd")
#   VacuumTube.build_corner_tubes(self, _c)
#
# The behaviour layered on top of this geometry lives elsewhere:
#   - scenes/garden/iso_tubes.gd     — Garden sell interaction (keeps the glow
#                                        mats returned here to drive its whoosh)
#   - scenes/shared/vacuum_lift.gd    — item transit + the player ±1-floor hop


# Corner anchors in floor-LOCAL space (XZ), y=0 at the slab top. Index 0..3 in
# the same CCW order iso_tubes used (0=-X-Z, 1=+X-Z, 2=+X+Z, 3=-X+Z) so the
# Garden sell logic keeps matching the same physical corners.
static func corner_anchors(c: Node) -> Array:
	var half: float = (c.GARDEN_GRID_SIZE * c.GARDEN_PLOT_SIZE) * 0.5
	var inset: float = half - c.VACUUM_TUBE_INSET
	var out: Array = []
	for i in range(4):
		var sign_x: float = -1.0 if i == 0 or i == 3 else 1.0
		var sign_z: float = -1.0 if i == 0 or i == 1 else 1.0
		out.append(Vector3(sign_x * inset, 0.0, sign_z * inset))
	return out


# Builds the four corner tube segments into `parent`. `is_top` seals the caps
# (no floor above to tile into). Returns one dict per tube:
#   {"node": Node3D, "glow_mat": StandardMaterial3D, "anchor": Vector3, "index": int}
# so callers (iso_tubes' whoosh) can pulse the glow without re-scanning children.
static func build_corner_tubes(parent: Node3D, c: Node, is_top: bool = false) -> Array:
	var tubes: Array = []
	var anchors: Array = corner_anchors(c)
	for i in range(anchors.size()):
		var built: Dictionary = _build_one(anchors[i], c, is_top)
		parent.add_child(built.node)
		built["index"] = i
		tubes.append(built)
	return tubes


static func _build_one(anchor: Vector3, c: Node, is_top: bool) -> Dictionary:
	var root := Node3D.new()
	root.name = "VacuumTube"
	root.position = anchor

	var story: float = float(c.VACUUM_TUBE_HEIGHT)

	# Translucent body — vertical cylinder spanning the full story height so
	# stacked segments meet flush.
	var body := MeshInstance3D.new()
	body.name = "Body"
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = c.VACUUM_TUBE_RADIUS
	body_mesh.bottom_radius = c.VACUUM_TUBE_RADIUS
	body_mesh.height = story
	body.mesh = body_mesh
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.45, 0.65, 0.85, 0.32)
	body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_mat.metallic = 0.6
	body_mat.roughness = 0.25
	body.material_override = body_mat
	body.position = Vector3(0, story * 0.5, 0)
	root.add_child(body)

	# Brass collar at floor level — the visible "mouth" the player hops into and
	# items drop through. Present on every floor so each story reads as a stop.
	var collar := MeshInstance3D.new()
	collar.name = "Collar"
	var collar_mesh := CylinderMesh.new()
	collar_mesh.top_radius = c.VACUUM_TUBE_RADIUS + 0.10
	collar_mesh.bottom_radius = c.VACUUM_TUBE_RADIUS + 0.10
	collar_mesh.height = 0.22
	collar.mesh = collar_mesh
	var collar_mat := StandardMaterial3D.new()
	collar_mat.albedo_color = Color(0.78, 0.55, 0.30)
	collar_mat.metallic = 0.85
	collar_mat.roughness = 0.3
	collar.material_override = collar_mat
	collar.position = Vector3(0, 0.11, 0)
	root.add_child(collar)

	# Internal warm glow disc just above the floor — pulsed by iso_tubes on a
	# sell, by vacuum_lift on a hop.
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	var glow_mesh := CylinderMesh.new()
	glow_mesh.top_radius = c.VACUUM_TUBE_RADIUS - 0.08
	glow_mesh.bottom_radius = c.VACUUM_TUBE_RADIUS - 0.08
	glow_mesh.height = 0.04
	glow.mesh = glow_mesh
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(1.0, 0.78, 0.32)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.65, 0.20)
	glow_mat.emission_energy_multiplier = 1.4
	glow.material_override = glow_mat
	glow.position = Vector3(0, 0.30, 0)
	root.add_child(glow)
	root.set_meta("glow_mat", glow_mat)

	# Top cap — only on the topmost floor, where there's no segment above to
	# tile into. A sealed brass disc closes the column off. On every other floor
	# the open top lets the next segment continue the run.
	if is_top:
		var cap := MeshInstance3D.new()
		cap.name = "TopCap"
		var cap_mesh := CylinderMesh.new()
		cap_mesh.top_radius = c.VACUUM_TUBE_RADIUS + 0.06
		cap_mesh.bottom_radius = c.VACUUM_TUBE_RADIUS + 0.06
		cap_mesh.height = 0.22
		cap.mesh = cap_mesh
		var cap_mat := StandardMaterial3D.new()
		cap_mat.albedo_color = Color(0.40, 0.30, 0.22)
		cap_mat.metallic = 0.85
		cap_mat.roughness = 0.4
		cap.material_override = cap_mat
		cap.position = Vector3(0, story + 0.02, 0)
		root.add_child(cap)

	return {"node": root, "glow_mat": glow_mat, "anchor": anchor}
