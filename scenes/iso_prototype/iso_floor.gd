extends Node3D

# Renders one Garden floor (Floor 3) procedurally. Phase 3 of the iso slice.
#
# Visual signature (sources: docs/space-tower-project-knowledge-v3.md,
# docs/player-journey-map-v3-final.html step 07 "The Garden of Eden"):
#   - Stacked planters with crops ripening
#   - Translucent water pipes with flowing water visible beneath the planters
#   - Warm grow-light glow over each planter
#
# All visuals are programmatic primitives (CSG / MeshInstance3D). Polish is
# explicitly forbidden in the slice — we are testing composition and feel.
#
# Iso-specific dimension notes:
#   - Sibling 2D project uses BLOCK_WIDTH=180 px, FLOOR_HEIGHT=144 px. In 3D
#     we move to meters: BLOCK_3D_W=2 m, FLOOR_3D_STORY_HEIGHT=3 m. The 2D
#     constants remain in Constants for any future minimap/HUD work.

@onready var _c: Node = get_node("/root/Constants")

# Animated grow lights — pulse on a 2–3s cycle
var _grow_lights: Array[OmniLight3D] = []
var _time := 0.0


func _ready() -> void:
	_build_floor()
	_build_planters_and_lights()
	_build_water_pipes()


func _process(delta: float) -> void:
	_time += delta
	# Slow pulse so the Garden reads as alive without being noisy.
	var pulse := 0.85 + 0.15 * sin(_time * TAU / 2.5)
	for light in _grow_lights:
		light.light_energy = pulse


# --- Floor slab -------------------------------------------------------------

func _build_floor() -> void:
	var slab := MeshInstance3D.new()
	slab.name = "Slab"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(_c.FLOOR_3D_WIDTH, _c.FLOOR_3D_SLAB_THICKNESS, _c.BLOCK_3D_D)
	slab.mesh = mesh
	slab.material_override = _make_material(Color(0.18, 0.18, 0.20))  # dark grey
	# Slab top sits at y=0; center is below.
	slab.position.y = -_c.FLOOR_3D_SLAB_THICKNESS * 0.5
	add_child(slab)


# --- Planters + grow lights -------------------------------------------------

func _build_planters_and_lights() -> void:
	var floor_left: float = -_c.FLOOR_3D_WIDTH * 0.5
	for bi in range(_c.BLOCKS_PER_FLOOR):
		var block_center_x: float = floor_left + (bi + 0.5) * _c.BLOCK_3D_W
		if _c.is_win_block(bi):
			# Window — leave a visible gap so the slice reads the fixed-block
			# semantics from the sibling sim. A short fence post hints at
			# "structure exists here, just no buildable block."
			_build_window_post(block_center_x)
			continue
		if _c.is_elev_block(bi):
			# Elevator shaft — render a thin vertical column hint.
			_build_elevator_hint(block_center_x)
			continue
		_build_planter(block_center_x)
		_build_grow_light(block_center_x)


func _build_planter(x: float) -> void:
	var w: float = _c.BLOCK_3D_W * 0.85
	var d: float = _c.BLOCK_3D_D * 0.55
	var h := 0.45
	# Soil-filled box.
	var planter := MeshInstance3D.new()
	planter.name = "Planter"
	var box := BoxMesh.new()
	box.size = Vector3(w, h, d)
	planter.mesh = box
	planter.material_override = _make_material(_c.PLANTER_SOIL)
	planter.position = Vector3(x, h * 0.5, 0.0)
	add_child(planter)
	# A simple "plant" on top — sphere with a stem cylinder. Single mesh per
	# planter to keep the slice cheap.
	var plant := MeshInstance3D.new()
	plant.name = "Plant"
	var sphere := SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.6
	plant.mesh = sphere
	plant.material_override = _make_material(_c.PLANTER_GREEN)
	plant.position = Vector3(x, h + 0.32, 0.0)
	add_child(plant)
	# Tomato-like accent: a smaller red sphere offset to one side.
	var fruit := MeshInstance3D.new()
	fruit.name = "Fruit"
	var fmesh := SphereMesh.new()
	fmesh.radius = 0.1
	fmesh.height = 0.2
	fruit.mesh = fmesh
	fruit.material_override = _make_material(Color(0.85, 0.25, 0.2))
	fruit.position = Vector3(x + 0.18, h + 0.25, 0.18)
	add_child(fruit)


func _build_grow_light(x: float) -> void:
	# Fixture above the planter, with an emissive bulb and an OmniLight3D.
	var fixture := MeshInstance3D.new()
	fixture.name = "GrowLightFixture"
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 0.08, 0.4)
	fixture.mesh = box
	fixture.material_override = _make_material(Color(0.15, 0.15, 0.18))
	fixture.position = Vector3(x, 2.4, 0.0)
	add_child(fixture)
	# Emissive bulb.
	var bulb := MeshInstance3D.new()
	bulb.name = "GrowLightBulb"
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(0.5, 0.05, 0.32)
	bulb.mesh = bmesh
	bulb.material_override = _make_emissive_material(_c.GROW_LIGHT_COLOR, 1.6)
	bulb.position = Vector3(x, 2.34, 0.0)
	add_child(bulb)
	# OmniLight3D for the actual illumination.
	var light := OmniLight3D.new()
	light.name = "GrowLight"
	light.light_color = _c.GROW_LIGHT_COLOR
	light.light_energy = 1.0
	light.omni_range = 2.5
	light.omni_attenuation = 1.5
	light.position = Vector3(x, 2.1, 0.0)
	add_child(light)
	_grow_lights.append(light)


func _build_window_post(x: float) -> void:
	var post := MeshInstance3D.new()
	post.name = "WindowPost"
	var box := BoxMesh.new()
	box.size = Vector3(0.15, 2.6, 0.15)
	post.mesh = box
	post.material_override = _make_material(Color(0.5, 0.5, 0.55))
	post.position = Vector3(x, 1.3, 0.0)
	add_child(post)


func _build_elevator_hint(x: float) -> void:
	var shaft := MeshInstance3D.new()
	shaft.name = "ElevatorHint"
	var box := BoxMesh.new()
	box.size = Vector3(_c.BLOCK_3D_W * 0.6, 2.6, _c.BLOCK_3D_D * 0.5)
	shaft.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.27, 0.35, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shaft.material_override = mat
	shaft.position = Vector3(x, 1.3, 0.0)
	add_child(shaft)


# --- Water pipes ------------------------------------------------------------

func _build_water_pipes() -> void:
	# Two long translucent cylinders running along X, in front of the planters
	# (positive Z) so they read as visible plumbing the player walks past.
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
