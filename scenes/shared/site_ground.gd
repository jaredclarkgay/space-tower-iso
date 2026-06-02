extends Node3D

# The build site's exterior ground — a wide walkable plane around the tower base
# with a path leading out from each of the four ground-floor doorways. Shown while
# the tower is raised + explored from outside (construction / exterior-walk), hidden
# once the player steps inside. Mirrors empty_lot.gd / cityscape.gd: programmatic
# placeholder geometry, parented to the tower root in world space (centred at x=0).

@onready var _c: Node = get_node("/root/Constants")


func _ready() -> void:
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

	var body := StaticBody3D.new()
	body.name = "SiteGroundBody"
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 0.4, size)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, -0.2, 0.0)   # top face flush with y=0
	add_child(body)

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
