extends RefCounted

# Procedural tree geometry for the Arboretum. Two varieties:
# - Variety 0: rounded crown (sphere mesh), lighter warm-green foliage,
#              brown trunk. "Apple-tree-ish."
# - Variety 1: pointed crown (cone via CylinderMesh with top_radius=0),
#              darker cool-green foliage, slightly darker trunk.
#              "Pine-tree-ish."
#
# Both varieties grow on the same height + crown-diameter curve, scaled
# from constants TREE_TRUNK_HEIGHT_MIN/MAX, TREE_CROWN_DIAMETER_MIN/MAX.
# The growth_t parameter (0..1) determines the current visual size.
#
# Floor 3 renders trees with their base at FLOOR_3D_TOP_Y (= ~0.2 m).
# Floor 4 renders the SAME trees offset by -FLOOR_3D_STORY_HEIGHT (= -3 m)
# so the visible portion above Floor 4's slab is exactly the part of the
# tree that's poking above Floor 3's ceiling. The Floor 4 slab has a hole
# at each tree position so the trunk reads as emerging from below.
#
# Loaded via preload, NOT class_name (per F-010).

const VARIETY_COUNT := 2


# Builds a single tree as a child of `parent`, returns a dict of refs the
# caller stores so `update()` can lerp the geometry each frame.
#   parent:         Node3D to add the tree to.
#   variety:        0 or 1 — chooses crown shape + colour palette.
#   world_position: Vector3 in `parent`'s local space — the tree's base.
static func build(parent: Node3D, c: Node, variety: int, world_position: Vector3) -> Dictionary:
	var v: int = variety % VARIETY_COUNT
	var data: Dictionary = _variety_data(v)

	var root := Node3D.new()
	root.name = "Tree_v%d" % v
	root.position = world_position
	parent.add_child(root)

	# Trunk — CylinderMesh, taller-than-wide, brown.
	var trunk := MeshInstance3D.new()
	trunk.name = "Trunk"
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = c.TREE_TRUNK_RADIUS_MIN * 0.7
	trunk_mesh.bottom_radius = c.TREE_TRUNK_RADIUS_MIN
	trunk_mesh.height = c.TREE_TRUNK_HEIGHT_MIN
	trunk.mesh = trunk_mesh
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = data.trunk_color
	trunk_mat.roughness = 0.95
	trunk.material_override = trunk_mat
	trunk.position.y = c.TREE_TRUNK_HEIGHT_MIN * 0.5
	root.add_child(trunk)

	# Crown — sphere for v0, cone for v1.
	var crown := MeshInstance3D.new()
	crown.name = "Crown"
	if String(data.crown_kind) == "sphere":
		var sphere := SphereMesh.new()
		sphere.radius = c.TREE_CROWN_DIAMETER_MIN * 0.5
		sphere.height = c.TREE_CROWN_DIAMETER_MIN
		crown.mesh = sphere
	else:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.005
		cone.bottom_radius = c.TREE_CROWN_DIAMETER_MIN * 0.5
		cone.height = c.TREE_CROWN_DIAMETER_MIN
		crown.mesh = cone
	var crown_mat := StandardMaterial3D.new()
	crown_mat.albedo_color = data.crown_color
	crown_mat.roughness = 0.9
	crown.material_override = crown_mat
	crown.position.y = c.TREE_TRUNK_HEIGHT_MIN + c.TREE_CROWN_DIAMETER_MIN * 0.5
	root.add_child(crown)

	return {
		"root": root,
		"trunk": trunk,
		"crown": crown,
		"variety": v,
	}


# Lerps the trunk + crown geometry to match the current growth_t.
# Called each frame from the floor controller.
static func update(refs: Dictionary, c: Node, growth_t: float) -> void:
	var t: float = clampf(growth_t, 0.0, 1.0)
	var trunk_height: float = lerpf(c.TREE_TRUNK_HEIGHT_MIN, c.TREE_TRUNK_HEIGHT_MAX, t)
	var trunk_radius: float = lerpf(c.TREE_TRUNK_RADIUS_MIN, c.TREE_TRUNK_RADIUS_MAX, t)
	var crown_diameter: float = lerpf(c.TREE_CROWN_DIAMETER_MIN, c.TREE_CROWN_DIAMETER_MAX, t)

	var trunk: MeshInstance3D = refs.trunk
	var trunk_mesh: CylinderMesh = trunk.mesh
	trunk_mesh.height = trunk_height
	trunk_mesh.top_radius = trunk_radius * 0.7
	trunk_mesh.bottom_radius = trunk_radius
	trunk.position.y = trunk_height * 0.5

	var crown: MeshInstance3D = refs.crown
	if crown.mesh is SphereMesh:
		var s: SphereMesh = crown.mesh
		s.radius = crown_diameter * 0.5
		s.height = crown_diameter
	else:
		var co: CylinderMesh = crown.mesh
		co.bottom_radius = crown_diameter * 0.5
		co.top_radius = 0.005
		co.height = crown_diameter * 1.4   # cones look better tall
	crown.position.y = trunk_height + crown_diameter * 0.5


# Maps a tree dict from GameState.floor_3.trees to its current growth_t
# in [0..1] based on elapsed time since planted_at_msec.
static func growth_t_for(tree: Dictionary, c: Node) -> float:
	var planted_at: int = int(tree.get("planted_at_msec", 0))
	var elapsed_ms: int = Time.get_ticks_msec() - planted_at
	if elapsed_ms <= 0:
		return 0.0
	var dur_ms: float = float(c.TREE_GROWTH_DURATION_MS)
	return clampf(float(elapsed_ms) / dur_ms, 0.0, 1.0)


static func _variety_data(v: int) -> Dictionary:
	if v == 1:
		return {
			"trunk_color": Color(0.32, 0.22, 0.14),
			"crown_color": Color(0.18, 0.40, 0.20),
			"crown_kind": "cone",
		}
	return {
		"trunk_color": Color(0.42, 0.28, 0.18),
		"crown_color": Color(0.36, 0.62, 0.30),
		"crown_kind": "sphere",
	}
