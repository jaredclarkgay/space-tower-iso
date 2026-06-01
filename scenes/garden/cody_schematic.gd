extends Control

# Cody Schematics modal — full-screen overlay opened from the Resources
# panel button. Three columns:
#   1. SubViewport showing a live 3D render of Cody, mouse-drag rotatable
#   2. Status + chassis/dome colour pickers (changes mirror to the live robot)
#   3. Skill tree placeholder showing future progression nodes
# ESC closes; click outside the panel does not (modal is dismissive only via
# the close button or ESC).
#
# The 3D Cody preview is delegated to cody_3d_view.gd, the same component
# the dialogue panel uses, so the chat pop-up and the schematic show the
# exact same robot.

const _CODY_3D_VIEW := preload("res://scenes/garden/cody_3d_view.gd")

@onready var _gs: Node = get_node("/root/GameState")

@export var iso_robot_path: NodePath
var _iso_robot: Node3D

# References for animated open/close.
var _bg: ColorRect
var _panel: PanelContainer
var _cody_view: Node   # cody_3d_view.gd instance

# Body / dome colour palettes the player can choose from.
const BODY_COLORS := [
	{"name": "Teal",   "value": Color(0.25, 0.68, 0.80)},
	{"name": "Hardhat", "value": Color(0.85, 0.55, 0.25)},
	{"name": "Navy",   "value": Color(0.18, 0.30, 0.58)},
]
const DOME_COLORS := [
	{"name": "Steel", "value": Color(0.46, 0.50, 0.56)},
	{"name": "Brass", "value": Color(0.78, 0.62, 0.30)},
]

# Skill tree placeholder. `unlocked` is the only one currently active;
# the rest are visible-but-locked, telegraphing the upgrade path.
const SKILL_NODES := [
	{"name": "Harvester",         "desc": "Snake-scan and harvest plants.", "cost": 0,   "state": "current"},
	{"name": "Speed Boost",       "desc": "Wheels turn 2× faster.",          "cost": 50,  "state": "locked"},
	{"name": "Capacity +10",      "desc": "Hopper holds 40 instead of 30.",  "cost": 100, "state": "locked"},
	{"name": "Builder Mode",      "desc": "Place blocks alongside you.",     "cost": 200, "state": "locked"},
	{"name": "Steel Frame",       "desc": "Hardened chassis. Resists impact.","cost": 300, "state": "locked"},
	{"name": "Combat Module",     "desc": "Defend against floor invaders.",  "cost": 500, "state": "locked"},
	{"name": "Companion Bond",    "desc": "Cody chooses to stay forever.",   "cost": -1,  "state": "story"},
]


func _ready() -> void:
	# Hide first so any frame between scene load and _build_modal can't
	# show the modal — paired with `visible = false` on the .tscn node.
	visible = false
	if iso_robot_path:
		_iso_robot = get_node(iso_robot_path)
	_build_modal()


func open() -> void:
	_gs.schematic_open = true
	visible = true
	if _cody_view:
		_cody_view.reset_pose(0.6, -0.4)
		_cody_view.sync_colors_from_state()
	_animate_open()


func close() -> void:
	if not visible:
		return
	_animate_close()


# Eye-grabbing entrance: dim background fades in, panel scales up from 88%
# with TRANS_BACK so it overshoots slightly before settling, panel alpha
# fades in. Total duration ~0.4s.
func _animate_open() -> void:
	if _bg == null or _panel == null:
		return
	_bg.modulate.a = 0.0
	_panel.modulate.a = 0.0
	_panel.pivot_offset = Vector2(560, 310)   # half of the 1120×620 panel
	_panel.scale = Vector2(0.86, 0.86)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_bg, "modulate:a", 1.0, 0.30)
	tween.tween_property(_panel, "modulate:a", 1.0, 0.32)
	tween.tween_property(_panel, "scale", Vector2(1.0, 1.0), 0.42) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _animate_close() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_bg, "modulate:a", 0.0, 0.18)
	tween.tween_property(_panel, "modulate:a", 0.0, 0.18)
	tween.tween_property(_panel, "scale", Vector2(0.94, 0.94), 0.18)
	tween.chain().tween_callback(_finalize_close)


func _finalize_close() -> void:
	visible = false
	_gs.schematic_open = false


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()


# --- Layout build ---------------------------------------------------------

func _build_modal() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Dimming background — kept as a member so _animate_open can fade it.
	_bg = ColorRect.new()
	_bg.color = Color(0.0, 0.0, 0.0, 0.55)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)

	# Centered main panel — also a member, so the open animation can scale
	# and fade it without a node-find.
	var panel := PanelContainer.new()
	_panel = panel
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -560
	panel.offset_top = -310
	panel.offset_right = 560
	panel.offset_bottom = 310

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.10, 0.16, 0.96)
	style.border_color = Color(0.30, 0.68, 0.78, 0.7)
	style.border_width_left = 2
	style.border_width_top = 3
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	style.shadow_size = 16
	style.shadow_offset = Vector2(0, 6)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	# Title bar with close button
	var title_hbox := HBoxContainer.new()
	title_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(title_hbox)
	var title := Label.new()
	title.text = "·  CODY GX-5 SCHEMATICS  ·"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.94, 0.83, 0.45, 0.95))
	title.add_theme_font_size_override("font_size", 22)
	title_hbox.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.custom_minimum_size = Vector2(36, 36)
	close_btn.pressed.connect(close)
	title_hbox.add_child(close_btn)

	var divider := HSeparator.new()
	vbox.add_child(divider)

	# Three-column body
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

	_build_viewport_column(body)
	_build_status_column(body)
	_build_skill_tree_column(body)


func _build_viewport_column(parent: Container) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(vbox)

	var label := Label.new()
	label.text = "PREVIEW"
	label.add_theme_color_override("font_color", Color(0.94, 0.83, 0.45, 0.85))
	label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(label)

	# Cody 3D view — drag-rotatable, no auto-spin (the player drives it).
	_cody_view = _CODY_3D_VIEW.new()
	_cody_view.custom_minimum_size = Vector2(360, 360)
	_cody_view.rotatable = true
	_cody_view.auto_spin = false
	_cody_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cody_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_cody_view)

	var hint := Label.new()
	hint.text = "Click and drag to rotate."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.55, 0.65, 0.78, 0.8))
	hint.add_theme_font_size_override("font_size", 12)
	vbox.add_child(hint)


func _build_status_column(parent: Container) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.custom_minimum_size = Vector2(280, 0)
	parent.add_child(vbox)

	var label := Label.new()
	label.text = "STATUS"
	label.add_theme_color_override("font_color", Color(0.94, 0.83, 0.45, 0.85))
	label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(label)

	# Stats lines (static for the slice — placeholders for real telemetry).
	var stats := [
		"Model:     Cody-Class GX-5",
		"Online:    18,943 days",
		"Harvested: 2,184,012 crops",
		"Capacity:  30 / 30 hopper",
		"Speed:     2.0 m/s",
	]
	for line in stats:
		var l := Label.new()
		l.text = line
		l.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0, 0.92))
		l.add_theme_font_size_override("font_size", 14)
		vbox.add_child(l)

	vbox.add_child(HSeparator.new())

	var custom_label := Label.new()
	custom_label.text = "CUSTOMISE"
	custom_label.add_theme_color_override("font_color", Color(0.94, 0.83, 0.45, 0.85))
	custom_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(custom_label)

	# Body colour row
	var body_label := Label.new()
	body_label.text = "Chassis"
	body_label.add_theme_color_override("font_color", Color(0.85, 0.92, 0.98, 0.85))
	body_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(body_label)
	var body_row := HBoxContainer.new()
	body_row.add_theme_constant_override("separation", 6)
	vbox.add_child(body_row)
	for choice in BODY_COLORS:
		body_row.add_child(_make_color_button(choice.value, choice.name, _on_body_color_picked))

	# Dome colour row
	var dome_label := Label.new()
	dome_label.text = "Dome"
	dome_label.add_theme_color_override("font_color", Color(0.85, 0.92, 0.98, 0.85))
	dome_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(dome_label)
	var dome_row := HBoxContainer.new()
	dome_row.add_theme_constant_override("separation", 6)
	vbox.add_child(dome_row)
	for choice in DOME_COLORS:
		dome_row.add_child(_make_color_button(choice.value, choice.name, _on_dome_color_picked))


func _build_skill_tree_column(parent: Container) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.custom_minimum_size = Vector2(320, 0)
	parent.add_child(vbox)

	var label := Label.new()
	label.text = "SKILL TREE"
	label.add_theme_color_override("font_color", Color(0.94, 0.83, 0.45, 0.85))
	label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(label)

	for i in range(SKILL_NODES.size()):
		var node_data: Dictionary = SKILL_NODES[i]
		vbox.add_child(_make_skill_row(node_data))
		if i < SKILL_NODES.size() - 1:
			var connector := Label.new()
			connector.text = "│"
			connector.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			connector.add_theme_color_override("font_color", Color(0.30, 0.48, 0.58, 0.6))
			connector.add_theme_font_size_override("font_size", 14)
			vbox.add_child(connector)


func _make_skill_row(node_data: Dictionary) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	var dot := Label.new()
	var dot_color := Color(0.55, 0.55, 0.6, 0.55)
	var marker := "○"
	match node_data.state:
		"current":
			marker = "●"
			dot_color = Color(0.55, 1.0, 0.55, 1.0)
		"story":
			marker = "✦"
			dot_color = Color(0.85, 0.55, 1.0, 0.7)
		_:
			marker = "○"
			dot_color = Color(0.55, 0.62, 0.7, 0.55)
	dot.text = marker
	dot.add_theme_color_override("font_color", dot_color)
	dot.add_theme_font_size_override("font_size", 18)
	dot.custom_minimum_size = Vector2(22, 0)
	box.add_child(dot)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 1)
	box.add_child(info_vbox)

	var name_label := Label.new()
	name_label.text = node_data.name
	var name_color: Color
	if node_data.state == "current":
		name_color = Color(0.96, 0.78, 0.32, 1.0)
	elif node_data.state == "story":
		name_color = Color(0.85, 0.65, 1.0, 0.8)
	else:
		name_color = Color(0.70, 0.78, 0.85, 0.75)
	name_label.add_theme_color_override("font_color", name_color)
	name_label.add_theme_font_size_override("font_size", 15)
	info_vbox.add_child(name_label)

	var desc_label := Label.new()
	var desc_text: String = node_data.desc
	if node_data.state == "locked":
		desc_text += "  ·  costs %d food" % int(node_data.cost)
	elif node_data.state == "story":
		desc_text += "  ·  story-locked"
	desc_label.text = desc_text
	desc_label.add_theme_color_override("font_color", Color(0.55, 0.65, 0.75, 0.65))
	desc_label.add_theme_font_size_override("font_size", 11)
	info_vbox.add_child(desc_label)

	return box


# --- Customisation handlers ----------------------------------------------

func _make_color_button(color: Color, label_text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = "  " + label_text
	b.custom_minimum_size = Vector2(80, 28)
	b.add_theme_font_size_override("font_size", 12)
	# Tint the button itself with the swatch colour so it reads as a swatch.
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = Color(0.0, 0.0, 0.0, 0.5)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_bottom_left = 4
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.pressed.connect(func(): callback.call(color))
	return b


func _on_body_color_picked(color: Color) -> void:
	_gs.cody_body_color = color
	if _cody_view:
		_cody_view.sync_colors_from_state()
	if _iso_robot and _iso_robot.has_method("apply_customization"):
		_iso_robot.apply_customization()


func _on_dome_color_picked(color: Color) -> void:
	_gs.cody_dome_color = color
	if _cody_view:
		_cody_view.sync_colors_from_state()
	if _iso_robot and _iso_robot.has_method("apply_customization"):
		_iso_robot.apply_customization()
