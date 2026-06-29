extends Node3D

# The build site's exterior ground — a wide walkable plane around the tower base
# with a path leading out from each of the four ground-floor doorways. Shown while
# the tower is raised + explored from outside (construction / exterior-walk), hidden
# once the player steps inside. Mirrors empty_lot.gd / cityscape.gd: programmatic
# placeholder geometry, parented to the tower root in world space (centred at x=0).

@onready var _c: Node = get_node("/root/Constants")

var _paths: Array[MeshInstance3D] = []   # the doorway path strips, toggled by the controller
var _ground_mesh: MeshInstance3D         # the SiteGroundMesh child — recentered on the camera each frame


func _ready() -> void:
	add_to_group("site_ground")   # the construction pit hides the solid plane to reveal the hole
	var size: float = float(_c.SITE_GROUND_SIZE)

	# Walkable ground plane (player mask = layer 2). Thin collision box, top at y=0.
	var ground := MeshInstance3D.new()
	ground.name = "SiteGroundMesh"
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _c.SITE_GROUND_COLOR
	mat.roughness = 1.0
	ground.material_override = mat
	add_child(ground)
	_ground_mesh = ground

	# Collision is a FRAME with the tower footprint cut out: the exterior ground
	# only exists outside the building. The footprint itself is floored by the
	# Garden slab at grade — and leaving the hole open means the basement (which
	# sits a story BELOW this plane) isn't capped by an invisible ground-ceiling
	# when you jump down there.
	var body := StaticBody3D.new()
	body.name = "SiteGroundBody"
	body.collision_layer = 2
	body.collision_mask = 0
	body.position = Vector3(0.0, -0.2, 0.0)   # top face flush with y=0
	add_child(body)
	var site_half: float = size * 0.5
	var hole: float = float(_c.FLOOR_3D_SIZE) * 0.5   # footprint half — flush with the Garden slab edge
	var strip_w: float = site_half - hole             # strip width from footprint edge to site edge
	if strip_w > 0.01:
		var mid: float = (hole + site_half) * 0.5
		# +X / -X strips run the full depth; +Z / -Z strips fill the central gap.
		_add_coll_strip(body, Vector3(strip_w, 0.4, size), Vector3(mid, 0.0, 0.0))
		_add_coll_strip(body, Vector3(strip_w, 0.4, size), Vector3(-mid, 0.0, 0.0))
		_add_coll_strip(body, Vector3(2.0 * hole, 0.4, strip_w), Vector3(0.0, 0.0, mid))
		_add_coll_strip(body, Vector3(2.0 * hole, 0.4, strip_w), Vector3(0.0, 0.0, -mid))

	# A path strip running out from each doorway (the four wall midpoints).
	var half: float = float(_c.FLOOR_3D_SIZE) * 0.5
	var pw: float = float(_c.SITE_PATH_WIDTH)
	var pl: float = float(_c.SITE_PATH_LENGTH)
	var path_mat := StandardMaterial3D.new()
	path_mat.albedo_color = _c.SITE_PATH_COLOR
	path_mat.roughness = 1.0
	for side in ["+x", "-x", "+z", "-z"]:
		var along_x: bool = side in ["+z", "-z"]
		var sgn: float = 1.0 if side in ["+x", "+z"] else -1.0
		var out: float = sgn * (half + pl * 0.5)   # centre of the strip, beyond the wall
		var strip := MeshInstance3D.new()
		strip.name = "Path_" + side
		var pm := PlaneMesh.new()
		# +z/-z walls run along X, so the path runs out along Z (pw wide, pl long).
		pm.size = Vector2(pw, pl) if along_x else Vector2(pl, pw)
		strip.mesh = pm
		strip.material_override = path_mat
		strip.position = Vector3(0.0, 0.02, out) if along_x else Vector3(out, 0.02, 0.0)
		add_child(strip)
		_paths.append(strip)


# The doorway paths only make sense once there are doorways to lead from. The
# controller hides them during the empty-lot survey and shows them from the build
# onward. (The ground plane itself is always present — that's the continuity.)
func set_paths_visible(v: bool) -> void:
	for p in _paths:
		p.visible = v


# Hide/show the solid ground PLANE (not the collision frame, which keeps the footprint
# hole). The construction pit hides it during the cold open so its own apron — which has a
# real visual hole at the footprint — reveals the excavation; restored once the pit clears.
func set_plane_visible(v: bool) -> void:
	if _ground_mesh:
		_ground_mesh.visible = v


# Recenter the VISUAL ground mesh (the SiteGroundMesh child ONLY — not the doorway path
# strips, not the collision body) on the given world XZ, keeping it flat at y=0. Called
# every frame by the controller with the camera/player XZ so the flat ground plane always
# fills the view and its edge is NEVER visible, even from the pulled-back Roof survey
# (the Roof is 36 m up, where a fixed plane could otherwise show an edge). The collision
# frame stays put at x=0 — it only matters around the tower footprint, which the player
# never leaves except up the tower, so the visual-only recenter is risk-free.
func recenter_mesh(world_xz: Vector3) -> void:
	if _ground_mesh == null:
		return
	_ground_mesh.global_position = Vector3(world_xz.x, 0.0, world_xz.z)


# One collision strip of the perimeter frame (local-space box at the given size + center).
func _add_coll_strip(body: StaticBody3D, box_size: Vector3, center: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	shape.position = center
	body.add_child(shape)
