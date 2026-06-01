extends Node3D

# Placeholder cityscape seen out the Sky Lounge glass: a ground plane + a ring
# of blocky distant buildings around the tower, shorter than it so you look DOWN
# onto them from up high. Throwaway geometry — a real skyline is the
# worldbuilding phase. The tower gates this node's visibility (CITY_REVEAL_LEVEL)
# so it only shows on the upper floors and doesn't clutter the Garden / Utility.
#
# World-space (parented to the tower root, not a floor): it sits at the city
# ground far below, independent of which floor the player is on.

@onready var _c: Node = get_node("/root/Constants")


func _ready() -> void:
	_build_ground()
	_build_buildings()


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "CityGround"
	var plane := PlaneMesh.new()
	var span: float = float(_c.CITY_RING_OUTER) * 2.6
	plane.size = Vector2(span, span)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.18, 0.22)
	mat.roughness = 0.95
	ground.material_override = mat
	ground.position = Vector3(0, float(_c.CITY_GROUND_Y), 0)
	add_child(ground)


func _build_buildings() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_c.CITY_RNG_SEED)
	var count: int = int(_c.CITY_RING_COUNT)
	var inner: float = float(_c.CITY_RING_INNER)
	var outer: float = float(_c.CITY_RING_OUTER)
	var ground_y: float = float(_c.CITY_GROUND_Y)
	var h_min: float = float(_c.CITY_HEIGHT_MIN)
	var h_max: float = float(_c.CITY_HEIGHT_MAX)

	for i in range(count):
		# Spread around the full circle with a little jitter so it doesn't read
		# as a perfect ring; push some buildings further out for depth.
		var ang: float = (float(i) / float(count)) * TAU + rng.randf_range(-0.04, 0.04)
		var radius: float = rng.randf_range(inner, outer)
		var x: float = cos(ang) * radius
		var z: float = sin(ang) * radius
		var h: float = rng.randf_range(h_min, h_max)
		# Further-out buildings trend shorter (atmospheric depth read).
		var falloff: float = 1.0 - clampf((radius - inner) / (outer - inner), 0.0, 1.0) * 0.45
		h *= falloff
		var w: float = rng.randf_range(4.0, 9.0)
		var d: float = rng.randf_range(4.0, 9.0)

		var b := MeshInstance3D.new()
		b.name = "Bldg_%d" % i
		var box := BoxMesh.new()
		box.size = Vector3(w, h, d)
		b.mesh = box
		var mat := StandardMaterial3D.new()
		# Cool, desaturated, dimming with distance — a hazy skyline silhouette.
		var tone: float = rng.randf_range(0.22, 0.40) * falloff
		mat.albedo_color = Color(tone * 0.9, tone * 0.95, tone * 1.15)
		mat.roughness = 0.85
		# A few windows-lit blocks for life.
		if rng.randf() < 0.35:
			mat.emission_enabled = true
			mat.emission = Color(0.95, 0.82, 0.5)
			mat.emission_energy_multiplier = rng.randf_range(0.08, 0.22)
		b.material_override = mat
		b.position = Vector3(x, ground_y + h * 0.5, z)
		b.rotation.y = rng.randf_range(0.0, PI)
		add_child(b)
