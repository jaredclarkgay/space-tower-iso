extends Node3D

# The empty lot — the game's exterior opening (GameDirector EMPTY_LOT phase).
# A flat patch of dirt under the iso camera with a solid surface to stand on,
# staged clear of the tower stack (LOT_CENTER). Mirrors cityscape.gd: throwaway
# placeholder geometry built in code, parented to the tower root in world space.
# The tower controller spawns the player here on the exterior boot and hides the
# floors; "entering the tower" hands off to the Garden spawn (no scene swap).

@onready var _c: Node = get_node("/root/Constants")


func _ready() -> void:
	var size: float = float(_c.LOT_SIZE)
	var center: Vector3 = _c.LOT_CENTER
	center.y = float(_c.LOT_GROUND_Y)

	# Visual dirt plane.
	var ground := MeshInstance3D.new()
	ground.name = "LotGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _c.LOT_DIRT_COLOR
	mat.roughness = 1.0
	ground.material_override = mat
	ground.position = center
	add_child(ground)

	# Solid surface so the player stands on it (slab collision layer = 2, like
	# the floor slabs the tower gates). A thin box just under the surface.
	var body := StaticBody3D.new()
	body.name = "LotBody"
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 0.4, size)
	shape.shape = box
	body.add_child(shape)
	body.position = center + Vector3(0.0, -0.2, 0.0)  # top face flush with the surface
	add_child(body)


# Where the player stands when the game opens on the lot: lot centre, feet on
# the surface.
func spawn_position() -> Vector3:
	var p: Vector3 = _c.LOT_CENTER
	p.y = float(_c.LOT_GROUND_Y) + float(_c.FLOOR_3D_TOP_Y)
	return p
