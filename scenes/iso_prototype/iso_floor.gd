extends Node3D

# Renders one Garden floor (Floor 3) procedurally. Phase 3 of the iso slice.
#
# Visual signature (sources: docs/space-tower-project-knowledge-v3.md,
# docs/player-journey-map-v3-final.html step 07 "The Garden of Eden"):
#   - Stacked planters with crops ripening
#   - Translucent water pipes with flowing water visible beneath the planters
#   - Warm grow-light glow over each planter
#
# Layout: two parallel rows of planters along Z, with a walkway between them
# and translucent water pipes running along the front and back of the floor.
# All visuals are programmatic primitives. Polish is explicitly forbidden in
# the slice — we are testing composition and feel.
#
# Collision: the slab is a StaticBody3D so the player can walk on it and
# land after jumping. Each planter is also a StaticBody3D so the player can
# bump into them rather than walk through (cheap iso "physicality").
#
# Iso-specific dimension notes:
#   - Sibling 2D project uses BLOCK_WIDTH=180 px, FLOOR_HEIGHT=144 px. In 3D
#     we move to meters: BLOCK_3D_W=2 m, BLOCK_3D_D=8 m (two-row Garden).
#     The 2D constants remain in Constants for any future minimap/HUD work.

@onready var _c: Node = get_node("/root/Constants")

# Animated grow lights — pulse on a 2.5s cycle.
var _grow_lights: Array[OmniLight3D] = []
var _time := 0.0


func _ready() -> void:
	_build_floor()
	_build_planter_rows()
	_build_water_pipes()


func _process(delta: float) -> void:
	_time += delta
	# Slow pulse so the Garden reads as alive without being noisy.
	var pulse := 0.85 + 0.15 * sin(_time * TAU / 2.5)
	for light in _grow_lights:
		light.light_energy = pulse


# --- Floor slab (with collision so the player has something to stand on) ----

func _build_floor() -> void:
	var slab_body := StaticBody3D.new()
	slab_body.name = "SlabBody"
	add_child(slab_body)

	var slab_size := Vector3(_c.FLOOR_3D_WIDTH, _c.FLOOR_3D_SLAB_THICKNESS, _c.BLOCK_3D_D)

	var slab_mesh := MeshInstance3D.new()
	slab_mesh.name = "Slab"
	var box := BoxMesh.new()
	box.size = slab_size
	slab_mesh.mesh = box
	slab_mesh.material_override = _make_material(Color(0.18, 0.18, 0.20))
	slab_mesh.position.y = -_c.FLOOR_3D_SLAB_THICKNESS * 0.5
	slab_body.add_child(slab_mesh)

	var slab_col := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	col_shape.size = slab_size
	slab_col.shape = col_shape
	slab_col.position.y = -_c.FLOOR_3D_SLAB_THICKNESS * 0.5
	slab_body.add_child(slab_col)


# --- Planter rows -----------------------------------------------------------

func _build_planter_rows() -> void:
	var floor_left: float = -_c.FLOOR_3D_WIDTH * 0.5
	for bi in range(_c.BLOCKS_PER_FLOOR):
		var block_center_x: float = floor_left + (bi + 0.5) * _c.BLOCK_3D_W
		if _c.is_win_block(bi):
			_build_window_post(block_center_x)
			continue
		if _c.is_elev_block(bi):
			_build_elevator_hint(block_center_x)
			continue
		# Buildable blocks: planter in each Z row, lit from above.
		for z_offset in _c.PLANTER_ROW_Z_OFFSETS:
			_build_planter(block_center_x, z_offset)
			_build_grow_light(block_center_x, z_offset)


func _build_planter(x: float, z: float) -> void:
	var w: float = _c.BLOCK_3D_W * 0.85
	var d := 1.6
	var h := 0.45

	var body := StaticBody3D.new()
	body.name = "PlanterBody"
	body.position = Vector3(x, 0, z)
	add_child(body)

	# Soil-filled planter box.
	var planter := MeshInstance3D.new()
	planter.name = "Planter"
	var pbox := BoxMesh.new()
	pbox.size = Vector3(w, h, d)
	planter.mesh = pbox
	planter.material_override = _make_material(_c.PLANTER_SOIL)
	planter.position.y = h * 0.5
	body.add_child(planter)

	# Collision matches the planter mesh.
	var planter_col := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(w, h, d)
	planter_col.shape = col_shape
	planter_col.position.y = h * 0.5
	body.add_child(planter_col)

	_build_leafy_plant(body, h)


# --- Leafy plant: stem + 3 staggered foliage spheres + 2 fruits -------------

func _build_leafy_plant(parent: StaticBody3D, planter_top_y: float) -> void:
	# Stem — thin cylinder rising from the soil.
	var stem := MeshInstance3D.new()
	stem.name = "Stem"
	var smesh := CylinderMesh.new()
	smesh.top_radius = 0.04
	smesh.bottom_radius = 0.06
	smesh.height = 0.5
	stem.mesh = smesh
	stem.material_override = _make_material(Color(0.32, 0.42, 0.18))
	stem.position = Vector3(0, planter_top_y + 0.25, 0)
	parent.add_child(stem)

	# Three foliage spheres in slightly different greens, staggered for volume.
	var foliage_data := [
		{ "pos": Vector3(0.0, planter_top_y + 0.55, 0.0), "r": 0.30, "color": _c.PLANTER_GREEN },
		{ "pos": Vector3(-0.18, planter_top_y + 0.42, 0.12), "r": 0.22, "color": Color(0.32, 0.55, 0.22) },
		{ "pos": Vector3(0.20, planter_top_y + 0.45, -0.10), "r": 0.24, "color": Color(0.45, 0.7, 0.34) },
	]
	for f in foliage_data:
		var leaf := MeshInstance3D.new()
		leaf.name = "Foliage"
		var sm := SphereMesh.new()
		sm.radius = f["r"]
		sm.height = f["r"] * 2.0
		leaf.mesh = sm
		leaf.material_override = _make_material(f["color"])
		leaf.position = f["pos"]
		parent.add_child(leaf)

	# Two fruits — small red spheres tucked among the foliage.
	var fruits := [
		{ "pos": Vector3(0.18, planter_top_y + 0.32, 0.18), "r": 0.10 },
		{ "pos": Vector3(-0.12, planter_top_y + 0.30, -0.16), "r": 0.08 },
	]
	for fr in fruits:
		var fruit := MeshInstance3D.new()
		fruit.name = "Fruit"
		var fmesh := SphereMesh.new()
		fmesh.radius = fr["r"]
		fmesh.height = fr["r"] * 2.0
		fruit.mesh = fmesh
		fruit.material_override = _make_material(Color(0.85, 0.25, 0.2))
		fruit.position = fr["pos"]
		parent.add_child(fruit)


func _build_grow_light(x: float, z: float) -> void:
	# Fixture above the planter, with an emissive bulb and an OmniLight3D.
	var fixture := MeshInstance3D.new()
	fixture.name = "GrowLightFixture"
	var fmesh := BoxMesh.new()
	fmesh.size = Vector3(0.6, 0.08, 0.4)
	fixture.mesh = fmesh
	fixture.material_override = _make_material(Color(0.15, 0.15, 0.18))
	fixture.position = Vector3(x, 2.4, z)
	add_child(fixture)
	# Emissive bulb.
	var bulb := MeshInstance3D.new()
	bulb.name = "GrowLightBulb"
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(0.5, 0.05, 0.32)
	bulb.mesh = bmesh
	bulb.material_override = _make_emissive_material(_c.GROW_LIGHT_COLOR, 1.6)
	bulb.position = Vector3(x, 2.34, z)
	add_child(bulb)
	# OmniLight3D for the actual illumination.
	var light := OmniLight3D.new()
	light.name = "GrowLight"
	light.light_color = _c.GROW_LIGHT_COLOR
	light.light_energy = 1.0
	light.omni_range = 2.8
	light.omni_attenuation = 1.5
	light.position = Vector3(x, 2.1, z)
	add_child(light)
	_grow_lights.append(light)


func _build_window_post(x: float) -> void:
	for z in [_c.BLOCK_3D_D * 0.4, -_c.BLOCK_3D_D * 0.4]:
		var post := MeshInstance3D.new()
		post.name = "WindowPost"
		var box := BoxMesh.new()
		box.size = Vector3(0.15, 2.6, 0.15)
		post.mesh = box
		post.material_override = _make_material(Color(0.5, 0.5, 0.55))
		post.position = Vector3(x, 1.3, z)
		add_child(post)


func _build_elevator_hint(x: float) -> void:
	var shaft := MeshInstance3D.new()
	shaft.name = "ElevatorHint"
	var box := BoxMesh.new()
	box.size = Vector3(_c.BLOCK_3D_W * 0.6, 2.6, _c.BLOCK_3D_D * 0.4)
	shaft.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.27, 0.35, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shaft.material_override = mat
	shaft.position = Vector3(x, 1.3, 0.0)
	add_child(shaft)


# --- Water pipes ------------------------------------------------------------

func _build_water_pipes() -> void:
	# Long translucent cylinders running along X, in front of and behind the
	# two planter rows. They read as visible plumbing the player walks past.
	var pipe_z: float = _c.BLOCK_3D_D * 0.45
	for z_offset in [pipe_z, -pipe_z]:
		var pipe := MeshInstance3D.new()
		pipe.name = "WaterPipe"
		var cyl := CylinderMesh.new()
		cyl.height = _c.FLOOR_3D_WIDTH
		cyl.top_radius = 0.08
		cyl.bottom_radius = 0.08
		pipe.mesh = cyl
		pipe.material_override = _make_water_material()
		# Cylinder defaults to Y-axis; rotate to lie along X.
		pipe.rotation = Vector3(0, 0, deg_to_rad(90))
		pipe.position = Vector3(0.0, 0.18, z_offset)
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
