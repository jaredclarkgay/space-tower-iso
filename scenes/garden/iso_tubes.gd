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

const VacuumTube = preload("res://scenes/shared/vacuum_tube.gd")

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
	# Geometry comes from the shared builder so the Garden's corner tubes are
	# identical to (and tile flush with) every other floor's segment. The Garden
	# is not the top floor (the Arboretum is above), so its tops stay open. We
	# keep the returned glow mats + anchors for the sell interaction + whoosh.
	var built: Array = VacuumTube.build_corner_tubes(self, _c, false)
	for entry in built:
		_tubes.append(entry.node)
		_tube_anchors.append(entry.anchor)


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
