extends Control

# The exterior hire beat (GameDirector EMPTY_LOT -> HIRE_PARTNER). A centered card
# on the empty lot:
#   EMPTY_LOT    -> a single "HIRE A PARTNER" CTA.
#   HIRE_PARTNER -> "CHOOSE YOUR PARTNER" + the five names; picking one stores it
#                   in GameState, advances the phase, and hands off into the tower.
# Pure story beat — no mechanical consequence. Mirrors camera_modes_hud.gd:
# clickable PanelContainer cells via gui_input (NOT Button, so nothing can steal
# the Space/Enter ui_accept that jump is bound to — F-008).

# GameDirector.Phase values (ints; set_phase takes the enum). Kept as literals to
# avoid any cross-autoload enum-resolution fuss, matching GameState.phase.
const _PHASE_EMPTY_LOT := 0
const _PHASE_HIRE_PARTNER := 1
const _PHASE_BUILD_STRUCTURE := 2

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")
@onready var _gd: Node = get_node("/root/GameDirector")

var _title: Label
var _cta_cell: PanelContainer
var _names_box: VBoxContainer
var _style_idle: StyleBoxFlat
var _style_hover: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	anchor_right = 1.0
	anchor_bottom = 1.0
	_style_idle = _make_style(Color(0.07, 0.08, 0.06, 0.9), Color(0.78, 0.55, 0.28, 0.5))
	_style_hover = _make_style(Color(0.16, 0.13, 0.07, 0.96), Color(0.96, 0.74, 0.36, 0.95))

	# Centered card.
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_style(Color(0.05, 0.05, 0.06, 0.82), Color(0.78, 0.55, 0.28, 0.35)))
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	# Centered, shrink-wrapped to its content so the CTA card is compact and the
	# name list grows the card from the centre (no fixed empty space).
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(card)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(vbox)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Color(0.96, 0.92, 0.8))
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_title.add_theme_constant_override("outline_size", 5)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_title)

	# CTA cell (EMPTY_LOT).
	_cta_cell = _make_cell("▸  HIRE A PARTNER")
	_cta_cell.gui_input.connect(_on_cta_input)
	vbox.add_child(_cta_cell)

	# Five name cells (HIRE_PARTNER).
	_names_box = VBoxContainer.new()
	_names_box.add_theme_constant_override("separation", 6)
	_names_box.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(_names_box)
	for nm in _c.PARTNER_NAMES:
		var cell := _make_cell(String(nm))
		cell.gui_input.connect(_on_name_input.bind(String(nm)))
		_names_box.add_child(cell)

	if _gd.has_signal("phase_changed"):
		_gd.phase_changed.connect(_on_phase_changed)
	_refresh()


func _on_phase_changed(_phase: int) -> void:
	_refresh()


# Show the layout matching the current phase; hide the panel off the exterior.
func _refresh() -> void:
	var phase: int = int(_gd.current_phase)
	visible = phase == _PHASE_EMPTY_LOT or phase == _PHASE_HIRE_PARTNER
	if not visible:
		return
	var hiring: bool = phase == _PHASE_HIRE_PARTNER
	_title.text = "CHOOSE YOUR PARTNER" if hiring else "AN EMPTY LOT"
	_cta_cell.visible = not hiring
	_names_box.visible = hiring


func _on_cta_input(event: InputEvent) -> void:
	if _is_left_click(event):
		_gd.set_phase(_PHASE_HIRE_PARTNER)
		accept_event()


func _on_name_input(event: InputEvent, nm: String) -> void:
	if _is_left_click(event):
		_gs.partner_name = nm
		var _tel: Node = get_node_or_null("/root/Telemetry")
		if _tel:
			_tel.record("partner_hired", {"name": nm})
		_gd.set_phase(_PHASE_BUILD_STRUCTURE)
		var tower: Node = get_tree().get_first_node_in_group("tower_controller")
		if tower and tower.has_method("begin_build_structure"):
			tower.begin_build_structure()   # construct-from-empty, or straight to Garden if the flag's off
		accept_event()


func _is_left_click(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT


func _make_cell(label_text: String) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(280.0, 40.0)
	cell.add_theme_stylebox_override("panel", _style_idle)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cell.mouse_entered.connect(func(): cell.add_theme_stylebox_override("panel", _style_hover))
	cell.mouse_exited.connect(func(): cell.add_theme_stylebox_override("panel", _style_idle))

	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.93, 0.9, 0.78, 0.96))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(label)
	return cell


func _make_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_right = 6
	s.corner_radius_bottom_left = 6
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s
