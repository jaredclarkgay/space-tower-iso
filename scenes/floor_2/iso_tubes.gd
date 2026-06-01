extends Node3D

# Cross-floor item conduits — one tube in each of the four floor corners.
# Each tube has a DOWN port (always active — sends produce down to Floor 1
# and out into the world for cash) and an UP port (active only when a floor
# exists above). On the Garden floor (now Floor 2), the up port is sealed:
# the operator is building Floor 1 elsewhere, so down is the only direction
# that resolves to a destination.
#
# Standard for every floor — every floor gets four corner tubes. The Garden
# only wires the player-sell path; future floors can add receive-from-tube
# and Cody-transit on top of the same chassis.
#
# Interaction surface mirrors iso_robot.gd and iso_dispenser.gd:
#   is_interactable_at(pos, radius) -> bool
#   try_interact() -> bool
#   get_interaction_label() -> String

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

# Per-tube scene refs and interaction anchors. Index 0..3 in CCW corner
# order starting from -X -Z. The anchor is at floor level.
var _tubes: Array = []
var _tube_anchors: Array = []

# Index of the tube the player is currently nearest (when in range), or -1.
# Set as a side effect of is_interactable_at so try_interact / label lookup
# don't have to re-do the distance scan.
var _nearest_index: int = -1


func _ready() -> void:
	var half: float = (_c.GARDEN_GRID_SIZE * _c.GARDEN_PLOT_SIZE) * 0.5
	# Inset from the interior wall, into the corner. The corner of the
	# usable floor is at (±half, ±half); tubes sit `inset` units toward
	# the centre on both axes.
	var c: float = half - _c.VACUUM_TUBE_INSET
	for i in range(4):
		var sign_x: float = -1.0 if i == 0 or i == 3 else 1.0
		var sign_z: float = -1.0 if i == 0 or i == 1 else 1.0
		var anchor := Vector3(sign_x * c, 0.0, sign_z * c)
		var tube := _build_tube(anchor, not _c.VACUUM_TUBE_HAS_FLOOR_ABOVE)
		add_child(tube)
		_tubes.append(tube)
		_tube_anchors.append(anchor)


func _process(delta: float) -> void:
	_update_pulse(delta)


# --- Public API ----------------------------------------------------------

# Side-effect: caches the nearest-tube index for the rest of the frame.
func is_interactable_at(player_world_pos: Vector3, radius: float) -> bool:
	# Y-gate: _nearest_in_range matches on XZ only (offset-safe, but blind to
	# height), so in the stacked tower a player standing on the floor directly
	# above — same XZ as a Garden corner tube — would otherwise read as in
	# range. global_position.y is this floor's surface; require the player to
	# be on it before any tube is sellable.
	if absf(player_world_pos.y - global_position.y) > 1.5:
		_nearest_index = -1
		return false
	_nearest_index = _nearest_in_range(player_world_pos, radius)
	return _nearest_index >= 0


# Empty when the nearest tube is too far OR the player has nothing to sell.
# Player.gd reads this and falls through to the next prompt source.
func get_interaction_label() -> String:
	if _nearest_index < 0:
		return ""
	if _gs.backpack_count <= 0:
		return ""
	return "Sell %d for $%d" % [_gs.backpack_count, _expected_sale_value()]


func try_interact() -> bool:
	if _nearest_index < 0:
		return false
	if _gs.backpack_count <= 0:
		return false
	_sell_at(_nearest_index)
	return true


# --- Sell flow -----------------------------------------------------------

func _expected_sale_value() -> int:
	return int(round(float(_gs.food_count) * _c.TUBE_SELL_VALUE_MULTIPLIER))


func _sell_at(index: int) -> void:
	var sale: int = _expected_sale_value()
	var count: int = _gs.backpack_count
	_gs.cash += sale
	_gs.food_count = 0
	_gs.backpack_count = 0
	_spawn_sell_floater(_tube_anchors[index], sale, count)
	_trigger_whoosh(index)


# --- Geometry ------------------------------------------------------------

func _build_tube(anchor: Vector3, top_sealed: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "VacuumTube"
	root.position = anchor

	# Translucent body — vertical cylinder spanning the full story height.
	var body := MeshInstance3D.new()
	body.name = "Body"
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = _c.VACUUM_TUBE_RADIUS
	body_mesh.bottom_radius = _c.VACUUM_TUBE_RADIUS
	body_mesh.height = _c.VACUUM_TUBE_HEIGHT
	body.mesh = body_mesh
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.45, 0.65, 0.85, 0.32)
	body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_mat.metallic = 0.6
	body_mat.roughness = 0.25
	body.material_override = body_mat
	body.position = Vector3(0, _c.VACUUM_TUBE_HEIGHT * 0.5, 0)
	root.add_child(body)

	# Top cap — sealed brass disc when no floor above; thinner brass ring
	# (an open mouth) when the up port is wired up. The shape is the same;
	# colour + thickness signal sealed-vs-open.
	var cap := MeshInstance3D.new()
	cap.name = "TopCap"
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = _c.VACUUM_TUBE_RADIUS + 0.06
	cap_mesh.bottom_radius = _c.VACUUM_TUBE_RADIUS + 0.06
	cap_mesh.height = 0.22 if top_sealed else 0.10
	cap.mesh = cap_mesh
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = (
		Color(0.40, 0.30, 0.22) if top_sealed
		else Color(0.78, 0.55, 0.30)
	)
	cap_mat.metallic = 0.85
	cap_mat.roughness = 0.4
	cap.material_override = cap_mat
	cap.position = Vector3(0, _c.VACUUM_TUBE_HEIGHT + 0.02, 0)
	root.add_child(cap)

	# Brass collar at floor level — visible "mouth" where items drop in.
	var collar := MeshInstance3D.new()
	collar.name = "Collar"
	var collar_mesh := CylinderMesh.new()
	collar_mesh.top_radius = _c.VACUUM_TUBE_RADIUS + 0.10
	collar_mesh.bottom_radius = _c.VACUUM_TUBE_RADIUS + 0.10
	collar_mesh.height = 0.22
	collar.mesh = collar_mesh
	var collar_mat := StandardMaterial3D.new()
	collar_mat.albedo_color = Color(0.78, 0.55, 0.30)
	collar_mat.metallic = 0.85
	collar_mat.roughness = 0.3
	collar.material_override = collar_mat
	collar.position = Vector3(0, 0.11, 0)
	root.add_child(collar)

	# Internal warm glow disc — sits just above the floor and emits.
	# Pulses gently when player is near with non-empty backpack.
	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	var glow_mesh := CylinderMesh.new()
	glow_mesh.top_radius = _c.VACUUM_TUBE_RADIUS - 0.08
	glow_mesh.bottom_radius = _c.VACUUM_TUBE_RADIUS - 0.08
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
	# Cache the glow material so _update_pulse / _trigger_whoosh can drive
	# emission energy without scanning children each frame.
	root.set_meta("glow_mat", glow_mat)

	# Down-arrow above the tube — directional cue. Always on so the corner
	# reads as a drop point at a glance.
	var arrow := Label3D.new()
	arrow.text = "▼"
	arrow.font_size = 90
	arrow.outline_size = 10
	arrow.modulate = Color(1.0, 0.78, 0.32)
	arrow.outline_modulate = Color(0.05, 0.05, 0.0, 0.9)
	arrow.pixel_size = 0.010
	arrow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	arrow.no_depth_test = true
	arrow.position = Vector3(0, _c.VACUUM_TUBE_HEIGHT + 0.62, 0)
	root.add_child(arrow)

	return root


# --- Feedback ------------------------------------------------------------

func _spawn_sell_floater(anchor: Vector3, dollars: int, veggies: int) -> void:
	var label := Label3D.new()
	label.text = "+$%d  (%d sold)" % [dollars, veggies]
	label.font_size = 64
	label.outline_size = 12
	label.modulate = Color(0.78, 1.0, 0.55, 1.0)
	label.outline_modulate = Color(0.05, 0.10, 0.0, 0.9)
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = anchor + Vector3(0.0, 2.3, 0.0)
	add_child(label)
	var start_y: float = label.position.y
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, ^"position:y", start_y + 1.6, 1.4)
	tween.tween_property(label, ^"modulate:a", 0.0, 1.4)
	tween.finished.connect(label.queue_free)


func _trigger_whoosh(index: int) -> void:
	var tube: Node3D = _tubes[index]
	var glow_mat = tube.get_meta("glow_mat", null)
	if glow_mat == null:
		return
	var tween := create_tween()
	tween.tween_property(glow_mat, "emission_energy_multiplier", 5.0, 0.08)
	tween.tween_property(glow_mat, "emission_energy_multiplier", 1.4, 0.6)


# --- Internal -----------------------------------------------------------

func _nearest_in_range(player_world_pos: Vector3, radius: float) -> int:
	var best := -1
	var best_d: float = radius
	for i in range(_tube_anchors.size()):
		var anchor: Vector3 = _tube_anchors[i]
		# Compare in the floor plane (XZ) — the player is always near Y=0,
		# but their feet are slightly above floor so 3D distance would skew.
		var dx: float = anchor.x - player_world_pos.x
		var dz: float = anchor.z - player_world_pos.z
		var d: float = sqrt(dx * dx + dz * dz)
		if d <= best_d:
			best_d = d
			best = i
	return best


# Slow ambient pulse on the glow disc; brighter when the player is in range
# with a non-empty backpack so the tube reads as "ready to take that".
func _update_pulse(_delta: float) -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	var base: float = 1.4
	var hot: bool = _nearest_index >= 0 and _gs.backpack_count > 0
	var amp: float = 0.8 if hot else 0.2
	var energy: float = base + sin(t * 2.6) * amp
	for tube in _tubes:
		var glow_mat = tube.get_meta("glow_mat", null)
		if glow_mat == null:
			continue
		# Don't fight the whoosh tween — it briefly drives energy to ~5.0
		# and decays. Only override if we're already near base range.
		if glow_mat.emission_energy_multiplier < 3.0:
			glow_mat.emission_energy_multiplier = lerp(
				glow_mat.emission_energy_multiplier, energy, 0.18
			)
