extends Control

# Top-right "Systems" status panel for Floor 1. Six rows (water, power,
# atmosphere, data, waste, cargo), each showing the system's state with a
# colour-coded dot:
#   ● red    offline   (not yet connected)
#   ● amber  connected (pipe laid, not activated)
#   ● green  online    (active)
#
# Mirrors the Garden's ResourcesPanel style so the top-right slot reads
# as the canonical "what's the state of this floor" panel across floors.
# Polls GameState.floor_1.connected / pipe_active each frame; per-row
# refs live in _rows so updates touch only the dot + status text.

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

const _RIGHT_MARGIN := 20.0
const _TOP_MARGIN := 20.0
const _PANEL_WIDTH := 320.0

const COLOR_OFFLINE := Color(0.78, 0.32, 0.28, 1.0)
const COLOR_CONNECTED := Color(0.96, 0.78, 0.32, 1.0)
const COLOR_ONLINE := Color(0.36, 0.79, 0.55, 1.0)
const COLOR_TEXT := Color(0.93, 0.9, 0.78, 0.95)
const COLOR_TEXT_DIM := Color(0.78, 0.74, 0.62, 0.82)

var _rows: Dictionary = {}   # id -> { dot: Label, status: Label }


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -(_PANEL_WIDTH + _RIGHT_MARGIN)
	offset_right = -_RIGHT_MARGIN
	offset_top = _TOP_MARGIN
	# offset_bottom expands as rows are added; we'll set it after _build.

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "·  SYSTEMS  ·"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.94, 0.83, 0.45, 0.92))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)

	var divider := HSeparator.new()
	divider.add_theme_stylebox_override("separator", _make_divider_style())
	vbox.add_child(divider)

	# One row per system, keyed by id.
	for sys in _c.FLOOR_1_SYSTEMS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(row)

		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_font_size_override("font_size", 22)
		dot.add_theme_color_override("font_color", COLOR_OFFLINE)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(dot)

		var name_lbl := Label.new()
		name_lbl.text = String(sys.name)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 18)
		name_lbl.add_theme_color_override("font_color", COLOR_TEXT)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_lbl)

		var status := Label.new()
		status.text = "offline"
		status.add_theme_font_size_override("font_size", 16)
		status.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(status)

		_rows[String(sys.id)] = {"dot": dot, "status": status}


func _process(_delta: float) -> void:
	for id in _rows.keys():
		var info: Dictionary = _rows[id]
		var connected: bool = bool(_gs.floor_1.connected.get(id, false))
		var active: bool = bool(_gs.floor_1.pipe_active.get(id, false))
		var dot: Label = info.dot
		var status: Label = info.status
		if active:
			dot.add_theme_color_override("font_color", COLOR_ONLINE)
			status.text = "online"
			status.add_theme_color_override("font_color", COLOR_TEXT)
		elif connected:
			dot.add_theme_color_override("font_color", COLOR_CONNECTED)
			status.text = "connected"
			status.add_theme_color_override("font_color", COLOR_TEXT)
		else:
			dot.add_theme_color_override("font_color", COLOR_OFFLINE)
			status.text = "offline"
			status.add_theme_color_override("font_color", COLOR_TEXT_DIM)


func _make_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.08, 0.06, 0.92)
	s.border_color = Color(0.82, 0.58, 0.30, 0.62)
	s.border_width_left = 2
	s.border_width_top = 3
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left = 10
	s.corner_radius_top_right = 10
	s.corner_radius_bottom_right = 10
	s.corner_radius_bottom_left = 10
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 12
	s.shadow_offset = Vector2(0, 5)
	return s


func _make_divider_style() -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = Color(0.78, 0.55, 0.28, 0.45)
	return s
