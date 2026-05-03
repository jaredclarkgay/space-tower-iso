extends Node3D

# Perimeter seed dispenser. Programmatic vending-machine-shaped body with a
# 2×3 grid of seed-window slots — one per crop type — that dim when empty
# and brighten when stocked. The selected slot (driven by the operator's
# 1..6 number-key choice via GameState.selected_seed_type) gets a glowing
# cyan frame so it's obvious which seed E will yield.
#
# Interaction surface mirrors iso_robot.gd:
#   is_interactable_at(pos, radius) -> bool
#   try_interact() -> bool                 # dispenses one seed if stocked
#   get_interaction_label() -> String       # label shown above the player
#
# Per-slot stock + per-slot refill timers tick in _process. Refill never
# overflows max — once at max, the accumulator does not bank time.

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

var _stock: Dictionary = {}
var _accum: Dictionary = {}

# Per-window visual handles. Keyed by seed string; each entry is
# { "frame": MeshInstance3D, "icon": MeshInstance3D, "icon_mat": StandardMaterial3D }.
var _windows: Dictionary = {}

# Selected-slot highlight — a single emissive frame that re-parents to the
# selected window each frame.
var _highlight: MeshInstance3D
var _highlight_target_world: Vector3 = Vector3.ZERO

# Overhead "SEEDS" beacon — only shown while the player is in range so it
# doesn't clutter the floor at game start.
var _overhead_label: Label3D
var _player_nearby: bool = false
var _label_tween: Tween

# The dispenser's interaction anchor. The player's distance is measured to
# this point so the radius isn't skewed by the body's bounding box.
var _interact_anchor: Vector3


func _ready() -> void:
	# Seed initial stock per Constants.DISPENSER_STARTS_FULL.
	for key in _c.SEED_TYPE_ORDER:
		var max_stock: int = int(_c.SEED_MAX_STOCK.get(key, 0))
		_stock[key] = max_stock if _c.DISPENSER_STARTS_FULL else 0
		_accum[key] = 0.0

	position = _c.DISPENSER_POSITION
	rotation.y = _c.DISPENSER_FACING_YAW
	_build_chassis()
	_build_windows()
	_build_highlight()
	_build_overhead_label()
	_interact_anchor = position
	_refresh_window_visuals()


func _process(delta: float) -> void:
	# Refill every slot independently. Don't bank time at max.
	for key in _c.SEED_TYPE_ORDER:
		var max_stock: int = int(_c.SEED_MAX_STOCK.get(key, 0))
		if int(_stock.get(key, 0)) >= max_stock:
			_accum[key] = 0.0
			continue
		_accum[key] = float(_accum.get(key, 0.0)) + delta
		var refill_s: float = float(_c.SEED_REFILL_SECONDS.get(key, 999.0))
		if _accum[key] >= refill_s:
			_stock[key] = int(_stock[key]) + 1
			_accum[key] = 0.0
			_refresh_one_window(key)
	_update_highlight()


# --- Public interaction API ----------------------------------------------

func is_interactable_at(player_world_pos: Vector3, radius: float) -> bool:
	# Track proximity as a side-effect so the overhead label (and any other
	# range-gated visuals) can fade in/out without the dispenser needing a
	# direct ref to the player. The player calls this every physics frame.
	var in_range: bool = _interact_anchor.distance_to(player_world_pos) <= radius
	if in_range != _player_nearby:
		_player_nearby = in_range
		_fade_overhead_label(in_range)
	return in_range


func try_interact() -> bool:
	var key: String = _gs.selected_seed_type
	if int(_stock.get(key, 0)) <= 0:
		return false
	_stock[key] = int(_stock[key]) - 1
	_gs.seed_pouch[key] = int(_gs.seed_pouch.get(key, 0)) + 1
	# Reveals the bottom-of-screen seed selector HUD on first use. Once
	# flipped this stays true for the rest of the session.
	_gs.dispenser_first_used = true
	_refresh_one_window(key)
	_spawn_dispense_feedback(key)
	return true


func _fade_overhead_label(visible_now: bool) -> void:
	if _overhead_label == null:
		return
	# Cancel any in-flight fade so rapid enter/exit doesn't stack tweens.
	if _label_tween and _label_tween.is_running():
		_label_tween.kill()
	var target_text_a: float = 1.0 if visible_now else 0.0
	var target_outline_a: float = 0.95 if visible_now else 0.0
	_label_tween = create_tween().set_parallel(true)
	_label_tween.tween_property(_overhead_label, ^"modulate:a", target_text_a, 0.25)
	_label_tween.tween_property(_overhead_label, ^"outline_modulate:a", target_outline_a, 0.25)


func get_interaction_label() -> String:
	var key: String = _gs.selected_seed_type
	var stock: int = int(_stock.get(key, 0))
	var max_stock: int = int(_c.SEED_MAX_STOCK.get(key, 0))
	var name: String = key.capitalize()
	if stock <= 0:
		return "%s seeds — empty" % name
	return "Take %s seed (%d/%d)" % [name, stock, max_stock]


# --- Visuals ------------------------------------------------------------

const _BODY_W := 0.95
const _BODY_H := 1.7
const _BODY_D := 0.45
const _WINDOW_SIZE := 0.18
const _WINDOW_GAP := 0.06
const _WINDOW_FRONT_Z := -_BODY_D * 0.5 - 0.01

func _build_chassis() -> void:
	var body := StaticBody3D.new()
	body.name = "DispenserBody"
	add_child(body)

	# Main case.
	var case_mesh := MeshInstance3D.new()
	case_mesh.name = "Case"
	var bm := BoxMesh.new()
	bm.size = Vector3(_BODY_W, _BODY_H, _BODY_D)
	case_mesh.mesh = bm
	case_mesh.material_override = _make_material(Color(0.18, 0.20, 0.24), 0.5, 0.4)
	case_mesh.position = Vector3(0, _BODY_H * 0.5, 0)
	body.add_child(case_mesh)

	# Frame around the front-face window grid — a very slightly recessed dark
	# rectangle so the seed windows read as inset behind glass rather than
	# stuck on the front.
	var grid_w: float = _BODY_W * 0.85
	var grid_h: float = _BODY_H * 0.55
	var frame := MeshInstance3D.new()
	frame.name = "WindowFrame"
	var fm := BoxMesh.new()
	fm.size = Vector3(grid_w, grid_h, 0.04)
	frame.mesh = fm
	frame.material_override = _make_material(Color(0.08, 0.09, 0.11), 0.7, 0.0)
	frame.position = Vector3(0, _BODY_H * 0.62, _WINDOW_FRONT_Z)
	body.add_child(frame)

	# Decorative top-light bar — emissive amber, reads as "machine on".
	var lamp := MeshInstance3D.new()
	lamp.name = "TopLamp"
	var lm := BoxMesh.new()
	lm.size = Vector3(_BODY_W * 0.6, 0.05, 0.05)
	lamp.mesh = lm
	lamp.material_override = _make_emissive(Color(1.0, 0.78, 0.32), 1.6)
	lamp.position = Vector3(0, _BODY_H - 0.06, _WINDOW_FRONT_Z - 0.02)
	body.add_child(lamp)

	# Coin-return-style bottom slot — visual only; reads as "seeds dispense
	# here".
	var slot := MeshInstance3D.new()
	slot.name = "DispenseSlot"
	var slot_mesh := BoxMesh.new()
	slot_mesh.size = Vector3(_BODY_W * 0.45, 0.06, 0.04)
	slot.mesh = slot_mesh
	slot.material_override = _make_material(Color(0.05, 0.05, 0.07), 0.8, 0.0)
	slot.position = Vector3(0, 0.20, _WINDOW_FRONT_Z)
	body.add_child(slot)

	var col := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(_BODY_W, _BODY_H, _BODY_D)
	col.shape = col_shape
	col.position = Vector3(0, _BODY_H * 0.5, 0)
	body.add_child(col)


# 2 columns × 3 rows of seed windows. Type order top→bottom, left→right
# follows Constants.SEED_TYPE_ORDER for legibility (number key 1 = top-left).
func _build_windows() -> void:
	var grid_origin_y: float = _BODY_H * 0.62
	var col_x: Array = [-(_WINDOW_SIZE + _WINDOW_GAP) * 0.5, (_WINDOW_SIZE + _WINDOW_GAP) * 0.5]
	var row_y: Array = [
		grid_origin_y + (_WINDOW_SIZE + _WINDOW_GAP),
		grid_origin_y,
		grid_origin_y - (_WINDOW_SIZE + _WINDOW_GAP),
	]
	var z: float = _WINDOW_FRONT_Z - 0.022
	for idx in range(_c.SEED_TYPE_ORDER.size()):
		var key: String = _c.SEED_TYPE_ORDER[idx]
		var col: int = idx % 2
		var row: int = idx / 2
		var pt: Dictionary = _c.plant_type_by_seed(key)
		var fruit_color: Color = pt.get("fruit_color", Color.WHITE) if not pt.is_empty() else Color.WHITE

		# Window pane backdrop — a slightly inset darker square.
		var pane := MeshInstance3D.new()
		pane.name = "Pane_" + key
		var pmesh := BoxMesh.new()
		pmesh.size = Vector3(_WINDOW_SIZE, _WINDOW_SIZE, 0.02)
		pane.mesh = pmesh
		pane.material_override = _make_material(Color(0.04, 0.05, 0.07), 0.4, 0.1)
		pane.position = Vector3(col_x[col], row_y[row], z)
		add_child(pane)

		# Seed icon — a tiny fruit-colored sphere centered in the pane.
		var icon := MeshInstance3D.new()
		icon.name = "Icon_" + key
		var im := SphereMesh.new()
		im.radius = _WINDOW_SIZE * 0.32
		im.height = _WINDOW_SIZE * 0.64
		icon.mesh = im
		var icon_mat := _make_emissive(fruit_color, 0.8)
		icon.material_override = icon_mat
		icon.position = Vector3(col_x[col], row_y[row], z - 0.020)
		add_child(icon)

		_windows[key] = {
			"frame": pane,
			"icon": icon,
			"icon_mat": icon_mat,
			"world_offset": Vector3(col_x[col], row_y[row], z - 0.04),
		}


# Billboarded "SEEDS" label that floats above the dispenser. Hidden by
# default — fades in only when the player walks into interaction range so
# the floor stays uncluttered at spawn. Sits well above the chassis so the
# label and dispenser body don't crowd each other in iso framing.
func _build_overhead_label() -> void:
	_overhead_label = Label3D.new()
	_overhead_label.name = "OverheadLabel"
	_overhead_label.text = "SEEDS"
	_overhead_label.font_size = 80
	_overhead_label.outline_size = 10
	_overhead_label.modulate = Color(1.0, 0.85, 0.45, 0.0)   # warm amber, starts fully transparent
	_overhead_label.outline_modulate = Color(0.10, 0.05, 0.0, 0.0)
	_overhead_label.pixel_size = 0.0085
	_overhead_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_overhead_label.no_depth_test = true
	_overhead_label.position = Vector3(0, _BODY_H + 1.4, 0)   # raised — clear breathing room
	add_child(_overhead_label)


func _build_highlight() -> void:
	# Slightly larger frame that hovers in front of the selected window.
	_highlight = MeshInstance3D.new()
	_highlight.name = "SelectedHighlight"
	var hm := BoxMesh.new()
	hm.size = Vector3(_WINDOW_SIZE + 0.04, _WINDOW_SIZE + 0.04, 0.012)
	_highlight.mesh = hm
	# Emissive cyan ring — bright enough to register at iso distance.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.85, 1.0, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.30, 0.85, 1.0)
	mat.emission_energy_multiplier = 2.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight.material_override = mat
	add_child(_highlight)


func _update_highlight() -> void:
	var key: String = _gs.selected_seed_type
	if not _windows.has(key):
		return
	var w: Dictionary = _windows[key]
	_highlight.position = w.world_offset
	# Subtle pulse so the highlight reads as alive on a static dispenser.
	var t: float = Time.get_ticks_msec() / 1000.0
	var pulse: float = 0.85 + 0.15 * sin(t * TAU / 1.2)
	var mat := _highlight.material_override as StandardMaterial3D
	mat.emission_energy_multiplier = 1.8 * pulse


func _refresh_window_visuals() -> void:
	for key in _c.SEED_TYPE_ORDER:
		_refresh_one_window(key)


func _refresh_one_window(key: String) -> void:
	if not _windows.has(key):
		return
	var w: Dictionary = _windows[key]
	var mat: StandardMaterial3D = w.icon_mat
	var stock: int = int(_stock.get(key, 0))
	var max_stock: int = int(_c.SEED_MAX_STOCK.get(key, 1))
	if stock <= 0:
		# Drained — read as empty: low-alpha icon, no emission.
		mat.albedo_color = Color(0.18, 0.18, 0.20)
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 0.0
		w.icon.scale = Vector3(0.7, 0.7, 0.7)
	else:
		var pt: Dictionary = _c.plant_type_by_seed(key)
		var fruit_color: Color = pt.get("fruit_color", Color.WHITE)
		mat.albedo_color = fruit_color
		mat.emission = fruit_color
		# Slight alpha-by-stock cue: full stock = bright, near-empty = dimmer.
		var fill: float = clamp(float(stock) / float(max_stock), 0.2, 1.0)
		mat.emission_energy_multiplier = lerp(0.6, 1.6, fill)
		w.icon.scale = Vector3(1, 1, 1) * lerp(0.85, 1.0, fill)


# Brief "+1" feedback — a tiny floater in the dispenser's slot color.
func _spawn_dispense_feedback(key: String) -> void:
	var pt: Dictionary = _c.plant_type_by_seed(key)
	var color: Color = pt.get("fruit_color", Color.WHITE) if not pt.is_empty() else Color.WHITE
	var label := Label3D.new()
	label.text = "+1 %s" % key.capitalize()
	label.font_size = 36
	label.outline_size = 5
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.pixel_size = 0.010
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	# Spawn just above the dispense slot.
	label.position = Vector3(0, 0.5, _WINDOW_FRONT_Z - 0.05)
	add_child(label)
	var start_y: float = label.position.y
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, ^"position:y", start_y + 1.0, 0.85)
	tween.tween_property(label, ^"modulate:a", 0.0, 0.85)
	tween.finished.connect(label.queue_free)


# --- Materials ----------------------------------------------------------

func _make_material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


func _make_emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	m.metallic = 0.0
	return m
