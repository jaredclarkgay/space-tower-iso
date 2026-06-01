extends Control

# Single, per-floor HUD for the stacked tower. Owns the chrome that changes
# with the player's current floor:
#   - the floor title (small "FLOOR N" eyebrow + big floor name),
#   - a per-floor wayfinding panel (global move keys + this-floor verbs),
#   - the Garden resources panel (backpack / cash + the Schematics button),
#   - and the visibility of the per-floor panel GROUPS (Garden / Utility),
#     so each floor's gameplay HUD only shows while you're on that floor.
#
# tower_controller.gd calls set_floor(level) whenever the current floor
# changes. The self-building panels (seed selector, Cody schematic, systems
# status, wayfinding arrows) live as child nodes under the group containers
# in tower.tscn; this manager only flips the groups on/off + drives the
# always-on chrome (title, wayfinding, resources).

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

@export var garden_group_path: NodePath
@export var utility_group_path: NodePath
@export var schematic_path: NodePath          # cody_schematic, opened by the button

# Shared visual language — matches the in-world floor panels.
const PANEL_BG := Color(0.06, 0.07, 0.05, 0.86)
const PANEL_BORDER := Color(0.82, 0.58, 0.30, 0.55)
const AMBER := Color(0.95, 0.86, 0.55)
const AMBER_DIM := Color(0.78, 0.68, 0.42)
const TITLE := Color(0.98, 0.93, 0.80)
const TEXT := Color(0.86, 0.84, 0.76)
const DIM := Color(0.60, 0.58, 0.50)
const KEYCAP := Color(0.96, 0.82, 0.46)
const BACKPACK_FULL := Color(1.00, 0.42, 0.36)
const CASH_COLOR := Color(0.78, 0.96, 0.55)
const SCHEM_UNLOCK := 10

# Per-floor wayfinding: the verbs that matter where you're standing. The
# global movement keys live on their own line above these.
const WAYFIND := {
	1: "[E]  pull the master breaker, then connect + activate the six systems",
	2: "[1–6]  pick a seed     [P]  plant     [E]  harvest · sell at a tube · talk to Cody",
	3: "[P]  plant a sapling     ·     take the south stairs up to the Canopy",
	4: "take the stairs back down     ·     the glass floor frames the grove below",
}
const MOVE_LINE := "[WASD] move   [Shift] sprint   [Space] jump   [Q/R] turn   [Wheel] zoom   [Tab] survey   [E] ride elevator"

var _garden_group: Control
var _utility_group: Control
var _schematic: Node

var _eyebrow: Label
var _title: Label
var _move_label: RichTextLabel
var _here_label: RichTextLabel

var _res_panel: PanelContainer
var _backpack_value: Label
var _cash_value: Label
var _schem_button: Button
var _schem_divider: HSeparator
var _schem_shown: bool = false
var _displayed_cash: int = 0
var _cash_flash: float = 0.0

var _current_level: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_garden_group = get_node_or_null(garden_group_path)
	_utility_group = get_node_or_null(utility_group_path)
	_schematic = get_node_or_null(schematic_path)
	_build_title()
	_build_wayfinding()
	_build_resources()
	_displayed_cash = int(_gs.cash)


# Called by tower_controller when the player's current floor changes.
func set_floor(level: int, display_name: String) -> void:
	_current_level = level
	# Title: split "FLOOR 2 / GARDEN" into eyebrow + name; fall back gracefully.
	var parts: PackedStringArray = display_name.split("/")
	if parts.size() >= 2:
		_eyebrow.text = parts[0].strip_edges().to_upper()
		_title.text = parts[1].strip_edges().to_upper()
	else:
		_eyebrow.text = "FLOOR %d" % level
		_title.text = display_name.to_upper()
	_here_label.text = _format_hint(String(WAYFIND.get(level, "")))
	if _garden_group:
		_garden_group.visible = (level == 2)
	if _utility_group:
		_utility_group.visible = (level == 1)
	if _res_panel:
		_res_panel.visible = (level == 2)


func _process(delta: float) -> void:
	# Resources only matter on the Garden; skip the work elsewhere.
	if _res_panel == null or not _res_panel.visible:
		return
	# Backpack N / cap, red at cap.
	var cap: int = int(_c.BACKPACK_CAPACITY)
	var n: int = int(_gs.backpack_count)
	_backpack_value.text = "%d / %d" % [n, cap]
	_backpack_value.add_theme_color_override("font_color", BACKPACK_FULL if n >= cap else KEYCAP)
	# Cash, flash green on deposit.
	if int(_gs.cash) != _displayed_cash:
		_displayed_cash = int(_gs.cash)
		_cash_value.text = "$%d" % _displayed_cash
		_cash_flash = 0.5
	if _cash_flash > 0.0:
		_cash_flash = maxf(0.0, _cash_flash - delta)
		_cash_value.add_theme_color_override("font_color",
			CASH_COLOR.lerp(Color(0.75, 1.5, 0.75), _cash_flash / 0.5))
	# Schematics unlock — bounce in once, then stop checking.
	if not _schem_shown and int(_gs.plants_harvested) >= SCHEM_UNLOCK:
		_schem_shown = true
		_reveal_schematics()


# --- Title ----------------------------------------------------------------

func _build_title() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -4)
	box.position = Vector2(24, 12)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_eyebrow = Label.new()
	_eyebrow.add_theme_font_size_override("font_size", 19)
	_eyebrow.add_theme_color_override("font_color", AMBER_DIM)
	_eyebrow.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_eyebrow.add_theme_constant_override("outline_size", 4)
	_eyebrow.text = "FLOOR"
	box.add_child(_eyebrow)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 54)
	_title.add_theme_color_override("font_color", TITLE)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_title.add_theme_constant_override("outline_size", 7)
	_title.text = "GARDEN"
	box.add_child(_title)


# --- Wayfinding -----------------------------------------------------------

func _build_wayfinding() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.position = Vector2(24, 96)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	_move_label = _hint_label()
	_move_label.text = _format_hint(MOVE_LINE)
	vbox.add_child(_move_label)

	var rule := HSeparator.new()
	rule.add_theme_stylebox_override("separator", _divider_style())
	vbox.add_child(rule)

	_here_label = _hint_label()
	_here_label.text = _format_hint(WAYFIND.get(2, ""))
	vbox.add_child(_here_label)


# Builds a RichTextLabel sized to its content so keycaps can be tinted.
func _hint_label() -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	rt.add_theme_font_size_override("normal_font_size", 14)
	rt.add_theme_color_override("default_color", TEXT)
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rt


# Tints any [KEY] tokens amber + bold so the verbs read at a glance.
func _format_hint(raw: String) -> String:
	var out := ""
	var in_key := false
	for ch in raw:
		if ch == "[":
			out += "[color=#f0d27a][b]"
			in_key = true
		elif ch == "]":
			out += "[/b][/color]"
			in_key = false
		else:
			out += ch
	return out


# --- Resources (Garden) ---------------------------------------------------

func _build_resources() -> void:
	_res_panel = PanelContainer.new()
	_res_panel.add_theme_stylebox_override("panel", _panel_style())
	_res_panel.anchor_left = 1.0
	_res_panel.anchor_right = 1.0
	_res_panel.offset_left = -286.0
	_res_panel.offset_top = 18.0
	_res_panel.offset_right = -22.0
	_res_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Owned by the Garden group so it shows/hides with the floor.
	if _garden_group:
		_garden_group.add_child(_res_panel)
	else:
		add_child(_res_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 13)
	margin.add_theme_constant_override("margin_bottom", 13)
	_res_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 9)
	margin.add_child(vbox)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", AMBER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "· RESOURCES ·"
	vbox.add_child(title)

	var rule := HSeparator.new()
	rule.add_theme_stylebox_override("separator", _divider_style())
	vbox.add_child(rule)

	_backpack_value = _stat_row(vbox, "Backpack", "0 / %d" % int(_c.BACKPACK_CAPACITY), KEYCAP, 30)
	_cash_value = _stat_row(vbox, "Cash", "$0", CASH_COLOR, 28)

	_schem_divider = HSeparator.new()
	_schem_divider.add_theme_stylebox_override("separator", _divider_style())
	_schem_divider.visible = false
	vbox.add_child(_schem_divider)

	_schem_button = Button.new()
	_schem_button.text = "▸  CODY SCHEMATICS"
	_schem_button.focus_mode = Control.FOCUS_NONE   # never steal Space/Enter (F-008)
	_schem_button.flat = true
	_schem_button.add_theme_font_size_override("font_size", 15)
	_schem_button.add_theme_color_override("font_color", AMBER)
	_schem_button.add_theme_color_override("font_hover_color", TITLE)
	_schem_button.visible = false
	_schem_button.pressed.connect(_on_schematics_pressed)
	vbox.add_child(_schem_button)


# One "Label .... Value" row; returns the value Label for live updates.
func _stat_row(parent: VBoxContainer, label_text: String, value_text: String,
		value_color: Color, value_size: int) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)

	var name_lbl := Label.new()
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", TEXT)
	name_lbl.text = label_text
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	var value := Label.new()
	value.add_theme_font_size_override("font_size", value_size)
	value.add_theme_color_override("font_color", value_color)
	value.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	value.add_theme_constant_override("outline_size", 3)
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return value


func _on_schematics_pressed() -> void:
	if _schematic and _schematic.has_method("open"):
		_schematic.open()


func _reveal_schematics() -> void:
	_schem_divider.visible = true
	_schem_divider.modulate.a = 0.0
	create_tween().tween_property(_schem_divider, "modulate:a", 1.0, 0.4)
	_schem_button.visible = true
	await get_tree().process_frame
	_schem_button.pivot_offset = _schem_button.size * 0.5
	_schem_button.modulate.a = 0.0
	_schem_button.scale = Vector2(0.5, 0.5)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_schem_button, "modulate:a", 1.0, 0.5)
	tween.tween_property(_schem_button, "scale", Vector2.ONE, 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- Shared styles --------------------------------------------------------

func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	s.border_color = PANEL_BORDER
	s.border_width_left = 2
	s.border_width_top = 3
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.set_corner_radius_all(10)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 12
	s.shadow_offset = Vector2(0, 5)
	s.set_content_margin_all(0)
	return s


func _divider_style() -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = Color(0.78, 0.55, 0.28, 0.40)
	return s
