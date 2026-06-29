extends Node3D

# A construction WORKER NPC for the cold-open pit (opening redesign Chapter 0). Three of
# them work the pit, each with a distinct personality + a shallow branching [E] dialogue
# (≤3 deep) that points the player to the phone booth to sign the permit. They WANDER
# their posts — drift to nearby spots, amble over to inspect the crane, or walk to the rim
# and look off into the vista — so the pit reads alive. They PERSIST (group "worker_npc")
# and are intended to become Residential residents once housing exists.
#
# Self-contained like the crane/booth: builds its own placeholder body, self-polls the
# player by distance, shows its own [E] prompt, and renders dialogue in its own CanvasLayer.
# NO player lock while talking (Principle 1: "talking to workers happens while the player
# moves freely") — the box is mouse-driven and auto-closes if the player wanders off.

const WALK_SPEED := 1.7
const INTERACT_RADIUS := 3.0
const TALK_CLOSE_RADIUS := 5.5      # walk this far from the worker and the chat closes
const ARRIVE_EPS := 0.4

@onready var _gs: Node = get_node("/root/GameState")

# Configured by the pit before _ready (see configure()).
var worker_name: String = "WORKER"
var tint: Color = Color(0.86, 0.45, 0.16)
var tree: Dictionary = {}
var home: Vector3 = Vector3.ZERO       # post anchor (local pit coords, on the floor)
var crane_spot: Vector3 = Vector3.ZERO # where the crane stands (an excursion target)
var enabled: bool = true               # the pit gates this to the cold open

var _visual: Node3D
var _prompt_root: Node3D
var _prompt_e: Label3D
var _prompt_label: Label3D
var _layer: CanvasLayer
var _panel: PanelContainer
var _text: Label
var _chips: VBoxContainer
var _player: Node3D

# Wander AI.
enum AI { IDLE, WALK }
var _ai: int = AI.IDLE
var _target: Vector3 = Vector3.ZERO
var _ai_timer: float = 0.0
var _bob: float = 0.0
var _talking: bool = false
var _seed: float = 0.0


func configure(nm: String, col: Color, dtree: Dictionary, home_pos: Vector3, crane: Vector3, idx: int) -> void:
	worker_name = nm
	tint = col
	tree = dtree
	home = home_pos
	crane_spot = crane
	_seed = float(idx) * 1.7   # de-sync the three so they don't bob/decide in lockstep


func _ready() -> void:
	add_to_group("worker_npc")
	position = home
	_build_body()
	_build_prompt()
	_build_dialogue()
	_ai_timer = 1.0 + _seed


func _physics_process(delta: float) -> void:
	if not enabled:
		if _prompt_root:
			_prompt_root.visible = false
		if _talking:
			close_dialogue()
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	_run_ai(delta)
	_animate(delta)
	_poll_interaction()


# --- Wander AI -----------------------------------------------------------------
func _run_ai(delta: float) -> void:
	if _talking:
		_ai = AI.IDLE   # hold still while the player reads
		return
	_ai_timer -= delta
	if _ai == AI.WALK:
		var to: Vector3 = _target - position
		to.y = 0.0
		if to.length() <= ARRIVE_EPS:
			_ai = AI.IDLE
			_ai_timer = randf_range(1.5, 4.0)
		else:
			var step: Vector3 = to.normalized() * WALK_SPEED * delta
			position += step
			if _visual:
				_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(step.x, step.z), 8.0 * delta)
	elif _ai_timer <= 0.0:
		_pick_wander()


func _pick_wander() -> void:
	# Mostly drift near the post; occasionally amble to the crane or to a pit edge to look out.
	var roll: float = randf()
	if roll < 0.18:
		_target = crane_spot + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(1.5, 2.5))
	elif roll < 0.36:
		# Toward a pit edge (look off into the vista) — pick a cardinal wall, stop short of it.
		var half: float = 12.0
		var dirs := [Vector3(half, 0, 0), Vector3(-half, 0, 0), Vector3(0, 0, half), Vector3(0, 0, -half)]
		_target = dirs[randi() % dirs.size()]
	else:
		_target = home + Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
	# Keep inside the pit, clear of the central column, and NORTH of the south access ramp
	# (z >= -4) so they work the flat floor and never clip into the sloped ramp.
	_target.x = clampf(_target.x, -12.0, 12.0)
	_target.z = clampf(_target.z, -4.0, 12.0)
	var flat := Vector2(_target.x, _target.z)
	if flat.length() < 3.2:
		flat = (flat.normalized() if flat.length() > 0.01 else Vector2(1, 0)) * 3.2
		_target.x = flat.x
		_target.z = flat.y
	_target.y = position.y
	_ai = AI.WALK


func _animate(delta: float) -> void:
	if _visual == null:
		return
	var moving: bool = _ai == AI.WALK and not _talking
	_bob += delta * (8.0 if moving else 2.2)
	var amp: float = 0.08 if moving else 0.02
	_visual.position.y = abs(sin(_bob + _seed)) * amp


# --- Interaction ---------------------------------------------------------------
func _poll_interaction() -> void:
	if _player == null:
		return
	if _talking:
		if _player.global_position.distance_to(global_position) > TALK_CLOSE_RADIUS:
			close_dialogue()
		return
	var near: bool = _near()
	_prompt_root.visible = near and not _other_worker_talking()
	if _prompt_root.visible and Input.is_action_just_pressed(&"interact") \
			and not bool(_gs.get("driving_crane")):
		open_dialogue()


func _near() -> bool:
	var p: Vector3 = _player.global_position
	return absf(p.y - global_position.y) < 3.0 \
		and Vector2(p.x - global_position.x, p.z - global_position.z).length() <= INTERACT_RADIUS


func _other_worker_talking() -> bool:
	for w in get_tree().get_nodes_in_group("worker_npc"):
		if w != self and bool(w.get("_talking")):
			return true
	return false


func open_dialogue() -> void:
	for w in get_tree().get_nodes_in_group("worker_npc"):
		if w != self and w.has_method("close_dialogue"):
			w.call("close_dialogue")
	_talking = true
	_prompt_root.visible = false
	_show_node("root")
	_panel.visible = true


func close_dialogue() -> void:
	_talking = false
	if _panel:
		_panel.visible = false


func _show_node(id: String) -> void:
	var node: Dictionary = tree.get(id, {})
	_text.text = String(node.get("text", ""))
	for c in _chips.get_children():
		c.queue_free()
	var choices: Array = node.get("choices", [])
	if choices.is_empty():
		_chips.add_child(_make_chip("▸  Back to work", ""))
	else:
		for ch in choices:
			_chips.add_child(_make_chip(String(ch.get("label", "...")), String(ch.get("next", ""))))


func _on_chip(event: InputEvent, goto: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if goto == "" or goto == "leave":
			close_dialogue()
		else:
			_show_node(goto)
		get_viewport().set_input_as_handled()


# --- Placeholder humanoid body (blocky hardhat worker, tinted per role) ---------
func _build_body() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var skin := _mat(Color(0.82, 0.64, 0.50))
	var vest := _mat(tint)
	var dark := _mat(Color(0.18, 0.18, 0.21))
	# Legs.
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.22, 0.7, 0.22), Vector3(sx * 0.14, 0.35, 0.0), dark)
	# Torso (vest).
	_box(Vector3(0.62, 0.7, 0.34), Vector3(0.0, 1.05, 0.0), vest)
	# Arms.
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.16, 0.62, 0.16), Vector3(sx * 0.42, 1.05, 0.0), vest)
	# Head.
	_box(Vector3(0.34, 0.34, 0.34), Vector3(0.0, 1.6, 0.0), skin)
	# Hardhat (dome + brim).
	var hat := _mat(Color(0.95, 0.78, 0.15))
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.22; sm.height = 0.30
	dome.mesh = sm; dome.material_override = hat; dome.position = Vector3(0.0, 1.82, 0.0)
	_visual.add_child(dome)
	_box(Vector3(0.40, 0.05, 0.40), Vector3(0.0, 1.74, 0.0), hat)
	# Facing nub (so you can read which way they look).
	_box(Vector3(0.10, 0.10, 0.10), Vector3(0.0, 1.6, 0.20), dark)


func _box(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm; mi.material_override = mat; mi.position = pos
	_visual.add_child(mi)


func _build_prompt() -> void:
	_prompt_root = Node3D.new()
	_prompt_root.position = Vector3(0.0, 2.5, 0.0)
	_prompt_root.visible = false
	add_child(_prompt_root)
	_prompt_e = _label("E", 72, Color(1.0, 0.92, 0.55), 0.55)
	_prompt_root.add_child(_prompt_e)
	_prompt_label = _label("Talk to " + worker_name, 44, Color(1.0, 0.96, 0.85), -0.05)
	_prompt_root.add_child(_prompt_label)


func _label(text: String, fs: int, col: Color, y: float) -> Label3D:
	var l := Label3D.new()
	l.text = text; l.font_size = fs; l.outline_size = max(6, fs / 7)
	l.modulate = col; l.outline_modulate = Color(0, 0, 0, 0.92)
	l.pixel_size = 0.01; l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true; l.position = Vector3(0, y, 0)
	return l


func _build_dialogue() -> void:
	_layer = CanvasLayer.new()
	add_child(_layer)
	_panel = PanelContainer.new()
	_panel.anchor_top = 1.0; _panel.anchor_bottom = 1.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = 28.0; _panel.offset_top = -28.0; _panel.offset_bottom = -28.0
	_panel.custom_minimum_size = Vector2(560.0, 0.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.09, 0.07, 0.96)
	style.border_color = tint
	style.set_border_width_all(2)
	style.set_corner_radius_all(13)
	style.shadow_color = Color(0, 0, 0, 0.5); style.shadow_size = 14; style.shadow_offset = Vector2(0, 5)
	_panel.add_theme_stylebox_override("panel", style)
	_layer.add_child(_panel)
	var margin := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 20)
	_panel.add_child(margin)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	var nm := Label.new()
	nm.text = worker_name
	nm.add_theme_color_override("font_color", tint.lightened(0.4))
	nm.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	nm.add_theme_constant_override("outline_size", 4)
	nm.add_theme_font_size_override("font_size", 24)
	col.add_child(nm)
	_text = Label.new()
	_text.add_theme_color_override("font_color", Color(0.94, 0.92, 0.88))
	_text.add_theme_font_size_override("font_size", 21)
	_text.add_theme_constant_override("line_spacing", 4)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_text)
	_chips = VBoxContainer.new(); _chips.add_theme_constant_override("separation", 7)
	col.add_child(_chips)
	_panel.visible = false


func _make_chip(label: String, goto: String) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(0.0, 40.0)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var idle := _chip_style(Color(0.15, 0.13, 0.10, 0.92), tint.darkened(0.1))
	var hover := _chip_style(Color(0.22, 0.19, 0.13, 0.97), tint.lightened(0.2))
	cell.add_theme_stylebox_override("panel", idle)
	cell.mouse_entered.connect(func(): cell.add_theme_stylebox_override("panel", hover))
	cell.mouse_exited.connect(func(): cell.add_theme_stylebox_override("panel", idle))
	cell.gui_input.connect(_on_chip.bind(goto))
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", Color(0.93, 0.90, 0.84))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(l)
	return cell


func _chip_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.set_border_width_all(2); s.border_width_left = 5
	s.set_corner_radius_all(8)
	s.content_margin_left = 14; s.content_margin_right = 14
	s.content_margin_top = 8; s.content_margin_bottom = 8
	return s


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.roughness = 1.0
	return m
