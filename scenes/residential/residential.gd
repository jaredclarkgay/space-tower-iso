extends Node3D

# Floor 4 — RESIDENTIAL. The building shell wired into the tower like every other
# floor (slab with the central elevator shaft, perimeter walls + glass, the
# extension grid, the elevator/spine core, lit utility risers, four corner vacuum
# tubes). A future worldbuilding phase fills it with the REAL units + residents.
#
# OVERNIGHT SLICE (floor_population_spec): Residential is the SECOND floor to carry
# the reusable blank→lush lifecycle (after the Garden). It DECLARES a PLACEHOLDER
# palette into the shared scenes/shared/floor_lifecycle.gd — proving the mechanic
# generalizes. The "unit" component is deliberately PLACEHOLDER programmatic
# geometry (vivid magenta, "PLACEHOLDER" labels) — it is NOT the floor's real
# content. Mechanic only: no narrative sequencing, no who-lives-here design. The
# real Residential worldbuilding is a separate live session (request_queue Q-005).
#
# Built in LOCAL space (slab top at local y=0); the tower offsets the node to its
# stacked height. Mirrors the chrome any solid floor uses — see
# scenes/shared/floor_chrome.gd and rules/stacked_tower_invariants.md (#4).

const FloorChrome = preload("res://scenes/shared/floor_chrome.gd")
const VacuumTube = preload("res://scenes/shared/vacuum_tube.gd")
const FloorLifecycle = preload("res://scenes/shared/floor_lifecycle.gd")
const FloorConstruction = preload("res://scenes/shared/floor_construction.gd")

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")
@onready var _tel: Node = get_node_or_null("/root/Telemetry")

const FLOOR_COLOR := Color(0.34, 0.30, 0.28)   # warm residential concrete

var _elevator_data: Dictionary = {}

# Per-component structural assembly (slab → core → risers → walls → tubes → grid).
# Owns the build-step manifest + parametric grow animations. Built instantly in
# normal play; the animated sequence (play_sequence) is the same pieces, sequenced.
var _construction: FloorConstruction = null

# The reusable blank→lush lifecycle (shared with the Garden). Residential DECLARES
# its placeholder content into it; the module owns state/place-verb/ghost/telemetry/
# ALIVE. Built in _ready().
var _lifecycle: FloorLifecycle = null

# Local-space root for placed placeholder units (kept separate from chrome so the
# floor reads clearly before/after).
var _units_root: Node3D
# anchor (Vector2i) → true, for already-occupied slots (so a unit can't double-drop).
var _occupied: Dictionary = {}
# The provisional bloom light (placeholder), warmed in when the floor goes ALIVE.
var _bloom_light: OmniLight3D = null


func _ready() -> void:
	# Slab with the central shaft cut through it (same ±2 m hole as the Garden /
	# Arboretum), so the elevator car travels through and stops here (it serves
	# this floor) and the spine reads continuous. SlabBody name → the tower gates
	# its collision per the current floor like every solid floor.
	# Structural chrome now builds through the per-component assembly module so each
	# piece is individually addressable + animatable. Normal play builds it all at
	# once; the tower's construction flow (or a harness) can instead play_sequence()
	# to raise it piece-by-piece. A mid-stack floor → tubes stay open (not top-sealed).
	var shaft_half: float = float(_c.ELEVATOR_RADIUS) * float(_c.GARDEN_PLOT_SIZE)
	_construction = FloorConstruction.new(self, _c, _gs, _tel, {
		"floor_color": FLOOR_COLOR,
		"shaft_half": shaft_half,
		"tubes_top": false,
	})
	_construction.build_all_instant()

	_units_root = Node3D.new()
	_units_root.name = "PlaceholderUnits"
	add_child(_units_root)
	_init_lifecycle()


# Declare Residential's PLACEHOLDER content into the shared lifecycle: "units" snap
# to a coarse grid (centre cell = the elevator shaft, skipped), each places a
# placeholder box, RESIDENTIAL_ALIVE_UNIT_COUNT units cross ALIVE → a provisional
# placeholder bloom. The module owns state/telemetry/ghost/threshold — identical
# machinery to the Garden; only this content declaration differs.
func _init_lifecycle() -> void:
	var ghost_span: float = float(_c.RESIDENTIAL_UNIT_FOOTPRINT)
	_lifecycle = FloorLifecycle.new(self, _gs, _c, _tel, {
		"floor_id": "residential",
		"level": 4,
		"threshold": int(_c.RESIDENTIAL_ALIVE_UNIT_COUNT),
		"component_type": "unit",
		"ghost_span": ghost_span,
		"ghost_color": Color(_c.PLACEHOLDER_COLOR.r, _c.PLACEHOLDER_COLOR.g, _c.PLACEHOLDER_COLOR.b, 0.30),
		"is_populatable": _is_populatable,
		"snap_anchor": _snap_anchor,
		"is_valid_anchor": _is_valid_anchor,
		"slot_local_pos": _slot_local_pos,
		"spawn_component": _spawn_unit,
		"on_alive": _bloom,
	})


# --- Generic lifecycle interface (the player + HUD + harness call these) ------
# Mirror names every populatable floor exposes, so the place verb is floor-agnostic.
func populate_find_slot(world_pos: Vector3, reach: float) -> Variant:
	return _lifecycle.find_slot(world_pos, reach)


func populate_update_ghost(anchor_or_null) -> void:
	_lifecycle.update_ghost(anchor_or_null)


func populate_place(anchor: Vector2i) -> bool:
	return _lifecycle.place(anchor)


func populate_is_alive() -> bool:
	return _lifecycle.is_alive()


func populate_reach() -> float:
	return float(_c.RESIDENTIAL_UNIT_REACH)


func populate_slot_local_pos(anchor: Vector2i) -> Vector3:
	return _slot_local_pos(anchor)


# Palette descriptor for the bottom-centre Floor Tools HUD.
func populate_palette() -> Dictionary:
	var st: Dictionary = _gs.floor_state("residential")
	return {
		"floor_id": "residential",
		"label": "Unit (placeholder)",
		"swatch": _c.PLACEHOLDER_COLOR,
		"populated": int(st.get("populated", 0)),
		"threshold": int(_c.RESIDENTIAL_ALIVE_UNIT_COUNT),
		"populatable": bool(_is_populatable.call()),
		"prompt": "bring Residential alive",
	}


# --- Residential's content declaration (the per-floor half of the lifecycle) --

# Minimal REVERSIBLE populating trigger (OVERNIGHT SLICE locked decision): Residential
# is populatable on first reach — placeable as soon as the player can stand on it,
# until it blooms ALIVE. No narrative gate (whether/when/why the player is sent here
# is deferred; logged R-001). Reversible: swap this predicate to `_gs.garden_alive()`
# to gate it behind the Garden instead.
func _is_populatable() -> bool:
	return not _gs.floor_alive("residential")


# Coarse placeholder grid: anchors run -HALF_SPAN..HALF_SPAN on each axis, spaced
# RESIDENTIAL_UNIT_PITCH apart, centred on the floor. Snap a LOCAL-frame position to
# the nearest anchor (clamped into range).
func _snap_anchor(local_pos: Vector3) -> Vector2i:
	var pitch: float = float(_c.RESIDENTIAL_UNIT_PITCH)
	var n: int = int(_c.RESIDENTIAL_UNIT_HALF_SPAN)
	var ci: int = clampi(int(round(local_pos.x / pitch)), -n, n)
	var cj: int = clampi(int(round(local_pos.z / pitch)), -n, n)
	return Vector2i(ci, cj)


# Legal if the anchor is in range, NOT the centre cell (the elevator shaft), and not
# already occupied.
func _is_valid_anchor(anchor: Vector2i) -> bool:
	var n: int = int(_c.RESIDENTIAL_UNIT_HALF_SPAN)
	if anchor.x < -n or anchor.x > n or anchor.y < -n or anchor.y > n:
		return false
	if anchor == Vector2i.ZERO:
		return false   # centre = elevator shaft
	return not _occupied.has(anchor)


# Local-frame centre of the slot at `anchor`.
func _slot_local_pos(anchor: Vector2i) -> Vector3:
	var pitch: float = float(_c.RESIDENTIAL_UNIT_PITCH)
	return Vector3(float(anchor.x) * pitch, 0.0, float(anchor.y) * pitch)


# Build a placed PLACEHOLDER unit: an unmistakably-magenta box with a "PLACEHOLDER"
# label and a small "it's taking shape" pop. The module advances state + telemetry.
func _spawn_unit(anchor: Vector2i) -> void:
	_occupied[anchor] = true
	var center: Vector3 = _slot_local_pos(anchor)
	var foot: float = float(_c.RESIDENTIAL_UNIT_FOOTPRINT)
	var height: float = foot * 0.8

	var unit := Node3D.new()
	unit.name = "PLACEHOLDER_Unit_%d_%d" % [anchor.x, anchor.y]
	unit.position = center
	_units_root.add_child(unit)

	# The body — vivid magenta, slightly emissive so it reads as obviously-not-final.
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Vector3(foot, height, foot)
	body.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _c.PLACEHOLDER_COLOR
	mat.emission_enabled = true
	mat.emission = _c.PLACEHOLDER_COLOR
	mat.emission_energy_multiplier = 0.18
	mat.roughness = 0.6
	body.material_override = mat
	body.position = Vector3(0, height * 0.5 + 0.05, 0)
	unit.add_child(body)

	# Darker base ring so the footprint reads on the floor grid.
	var base := MeshInstance3D.new()
	var basem := BoxMesh.new()
	basem.size = Vector3(foot + 0.5, 0.14, foot + 0.5)
	base.mesh = basem
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = _c.PLACEHOLDER_COLOR_DIM
	base.material_override = bmat
	base.position = Vector3(0, 0.07, 0)
	unit.add_child(base)

	# "PLACEHOLDER" label so no one mistakes it for final content.
	var label := Label3D.new()
	label.text = "UNIT\n(placeholder)"
	label.font_size = 40
	label.outline_size = 8
	label.modulate = Color(1.0, 0.92, 0.99, 1.0)
	label.outline_modulate = Color(0.18, 0.0, 0.14, 0.95)
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, height + 1.2, 0)
	unit.add_child(label)

	# A small "it's taking shape" pop.
	unit.scale = Vector3(1.0, 0.01, 1.0)
	var tween := create_tween()
	tween.tween_property(unit, ^"scale", Vector3.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Residential's provisional PLACEHOLDER bloom — the floor's `on_alive` callback. The
# module has already flipped `alive` + emitted `floor_alive` telemetry. Here we run
# only the felt moment: a placeholder warm light warms in at floor centre.
# NOTE (scope): deliberately minimal + placeholder — the REAL Residential bloom
# (lighting / ambience / residents) is a separate live design session.
func _bloom() -> void:
	if _bloom_light == null:
		_bloom_light = OmniLight3D.new()
		_bloom_light.name = "PlaceholderBloomLight"
		_bloom_light.position = Vector3(0, float(_c.WALL_HEIGHT) * 0.7, 0)
		_bloom_light.omni_range = float(_c.FLOOR_3D_SIZE) * 0.9
		_bloom_light.light_color = Color(1.0, 0.86, 0.72)
		_bloom_light.light_energy = 0.0
		add_child(_bloom_light)
	var tween := create_tween()
	tween.tween_property(_bloom_light, ^"light_energy", 1.4, 1.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
