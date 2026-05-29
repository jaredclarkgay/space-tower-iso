extends Control

# Compact 3-button strip that toggles GameState.camera_mode between
# "iso", "profile", and "ots". Click any button to switch — iso_camera.gd
# polls _gs.camera_mode every frame and tweens the camera to the matching
# preset.
#
# Layout: vertical stack anchored bottom-right, well clear of the
# Resources panel which lives top-right. Operator: "the camera toggles
# should be on the lower right, they're bumping up against resources".

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

const _BUTTON_W := 124.0
const _BUTTON_H := 38.0
const _BUTTON_GAP := 4.0
const _RIGHT_MARGIN := 20.0
const _BOTTOM_MARGIN := 20.0

var _buttons: Dictionary = {}        # mode_key -> { root, label }
var _style_idle: StyleBoxFlat
var _style_selected: StyleBoxFlat


func _ready() -> void:
	_style_idle = _make_idle_style()
	_style_selected = _make_selected_style()

	var entries: Array = [
		[_c.CAMERA_MODE_ISO, "ISO"],
		[_c.CAMERA_MODE_PROFILE, "PROFILE"],
		[_c.CAMERA_MODE_OTS, "OVER-SHOULDER"],
	]
	var n: int = entries.size()
	var total_h: float = n * _BUTTON_H + (n - 1) * _BUTTON_GAP

	# Account for the header label that sits above the buttons.
	var header_h: float = 18.0
	var stack_h: float = total_h + header_h + 4.0
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(_BUTTON_W, stack_h)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -(_BUTTON_W + _RIGHT_MARGIN)
	offset_right = -_RIGHT_MARGIN
	offset_top = -(stack_h + _BOTTOM_MARGIN)
	offset_bottom = -_BOTTOM_MARGIN

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(_BUTTON_GAP))
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(vbox)

	# Header label so the column reads as a control surface, not stray buttons.
	var header := Label.new()
	header.text = "CAMERA"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.94, 0.83, 0.45, 0.78))
	header.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	header.add_theme_constant_override("outline_size", 3)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header)

	for entry in entries:
		_build_button(vbox, entry[0], entry[1])
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _build_button(parent: VBoxContainer, mode_key: String, label_text: String) -> void:
	var cell := PanelContainer.new()
	cell.name = "Cell_" + mode_key
	cell.custom_minimum_size = Vector2(_BUTTON_W, _BUTTON_H)
	cell.add_theme_stylebox_override("panel", _style_idle)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cell.gui_input.connect(_on_button_input.bind(mode_key))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(margin)

	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.93, 0.9, 0.78, 0.95))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(label)

	parent.add_child(cell)
	_buttons[mode_key] = {"root": cell, "label": label}


func _on_button_input(event: InputEvent, mode_key: String) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_gs.camera_mode = mode_key
		accept_event()


func _refresh() -> void:
	var sel: String = String(_gs.camera_mode)
	for key in _buttons:
		var info: Dictionary = _buttons[key]
		var cell: PanelContainer = info.root
		if key == sel:
			cell.add_theme_stylebox_override("panel", _style_selected)
		else:
			cell.add_theme_stylebox_override("panel", _style_idle)


func _make_idle_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.08, 0.06, 0.86)
	s.border_color = Color(0.78, 0.55, 0.28, 0.45)
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_right = 6
	s.corner_radius_bottom_left = 6
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 2)
	return s


func _make_selected_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.12, 0.18, 0.22, 0.94)
	s.border_color = Color(0.30, 0.85, 1.0, 0.95)
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_right = 6
	s.corner_radius_bottom_left = 6
	s.shadow_color = Color(0.30, 0.85, 1.0, 0.40)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 0)
	return s
