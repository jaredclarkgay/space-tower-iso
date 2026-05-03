extends Control

# Bottom-of-screen seed-selector hotbar. Six cells (one per crop type)
# laid out left-to-right in Constants.SEED_TYPE_ORDER. Each cell shows:
#   - Number key shortcut (1..6)
#   - A fruit-coloured swatch
#   - Crop name
#   - Current pouch count (× N)
#
# Click a cell OR press 1..6 to select. The selected cell gets a cyan
# border; the rest get an amber border. Pouch counts live-update from
# GameState.seed_pouch every frame.
#
# Reveal: hidden until GameState.dispenser_first_used flips, then header
# fades in and each cell slides up + fades in with a staggered cascade so
# the row builds left-to-right rather than appearing as a slab.

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

const _CELL_W := 122.0
const _CELL_H := 100.0
const _CELL_GAP := 8.0
const _SWATCH_SIZE := 22.0
const _BOTTOM_MARGIN := 24.0
const _HEADER_H := 22.0
const _CELL_RISE := 30.0           # how far below final each cell starts
const _CELL_REVEAL_DURATION := 0.42
const _CELL_REVEAL_STAGGER := 0.07
const _HEADER_REVEAL_DURATION := 0.30

var _cells: Dictionary = {}        # seed_key -> { root, count_label, ... }
var _header: Label
var _style_idle: StyleBoxFlat
var _style_selected: StyleBoxFlat
var _revealed: bool = false        # mirrors GameState.dispenser_first_used after reveal


func _ready() -> void:
	_style_idle = _make_idle_style()
	_style_selected = _make_selected_style()

	var n: int = int(_c.SEED_TYPE_ORDER.size())
	var total_w: float = n * _CELL_W + (n - 1) * _CELL_GAP
	var total_h: float = _CELL_H + _HEADER_H + 4.0

	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(total_w, total_h)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -total_w * 0.5
	offset_right = total_w * 0.5
	offset_top = -(total_h + _BOTTOM_MARGIN)
	offset_bottom = -_BOTTOM_MARGIN
	# Self stays visible — per-child alpha + position drives the reveal so
	# we can stagger individual cells.
	modulate = Color(1, 1, 1, 1)

	# Header centred above the cell row. Clarifies that the × N below are
	# seed counts, not fruit counts. Hidden until reveal.
	_header = Label.new()
	_header.name = "Header"
	_header.text = "SEEDS"
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.add_theme_font_size_override("font_size", 14)
	_header.add_theme_color_override("font_color", Color(0.94, 0.83, 0.45, 0.85))
	_header.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_header.add_theme_constant_override("outline_size", 4)
	_header.anchor_left = 0.0
	_header.anchor_right = 1.0
	_header.offset_top = 0
	_header.offset_bottom = _HEADER_H
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.modulate = Color(1, 1, 1, 0)
	add_child(_header)

	# Cells row — a plain Control with manually-positioned children so each
	# cell can be tweened on its own Y axis without an HBoxContainer
	# overriding positions every layout pass.
	var row := Control.new()
	row.name = "CellsRow"
	row.anchor_left = 0.0
	row.anchor_top = 0.0
	row.anchor_right = 1.0
	row.anchor_bottom = 1.0
	row.offset_top = _HEADER_H + 4.0
	row.offset_bottom = 0
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(row)

	for idx in range(n):
		var key: String = _c.SEED_TYPE_ORDER[idx]
		_build_cell(row, key, idx + 1, idx)

	_refresh()


func _process(_delta: float) -> void:
	if not _revealed and _gs.dispenser_first_used:
		_revealed = true
		_play_reveal_tween()
	_refresh()


# --- Build ---------------------------------------------------------------

func _build_cell(parent: Control, seed_key: String, number_key: int, idx: int) -> void:
	var pt: Dictionary = _c.plant_type_by_seed(seed_key)
	var fruit_color: Color = pt.get("fruit_color", Color.WHITE)

	var cell := PanelContainer.new()
	cell.name = "Cell_" + seed_key
	cell.size = Vector2(_CELL_W, _CELL_H)
	cell.position = Vector2(idx * (_CELL_W + _CELL_GAP), _CELL_RISE)  # off-final until reveal
	cell.modulate = Color(1, 1, 1, 0)                                  # invisible until reveal
	cell.add_theme_stylebox_override("panel", _style_idle)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cell.gui_input.connect(_on_cell_input.bind(seed_key))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(vbox)

	# Top row: number + colored swatch + name.
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_row)

	var num_label := Label.new()
	num_label.text = "%d" % number_key
	num_label.add_theme_font_size_override("font_size", 18)
	num_label.add_theme_color_override("font_color", Color(0.78, 0.84, 0.92, 0.85))
	num_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	num_label.add_theme_constant_override("outline_size", 3)
	num_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(num_label)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(_SWATCH_SIZE, _SWATCH_SIZE)
	swatch.color = fruit_color
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(swatch)

	var name_label := Label.new()
	name_label.text = seed_key.capitalize()
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", Color(0.93, 0.9, 0.78, 0.95))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	name_label.add_theme_constant_override("outline_size", 3)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(name_label)

	# Pouch count — what the player can plant right now.
	var count_label := Label.new()
	count_label.text = "× 0"
	count_label.add_theme_font_size_override("font_size", 26)
	count_label.add_theme_color_override("font_color", Color(0.96, 0.78, 0.32, 0.95))
	count_label.add_theme_color_override("font_outline_color", Color(0.10, 0.05, 0.0, 0.85))
	count_label.add_theme_constant_override("outline_size", 4)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(count_label)

	# Stock gauge — what the dispenser still has. Shown smaller + dimmer
	# than pouch so the visual hierarchy reads "what I have now" first,
	# "what I can refill to" second.
	var stock_label := Label.new()
	stock_label.text = "stock 0/0"
	stock_label.add_theme_font_size_override("font_size", 13)
	stock_label.add_theme_color_override("font_color", Color(0.78, 0.74, 0.66, 0.85))
	stock_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	stock_label.add_theme_constant_override("outline_size", 3)
	stock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(stock_label)

	parent.add_child(cell)
	_cells[seed_key] = {
		"root": cell,
		"count_label": count_label,
		"stock_label": stock_label,
		"name_label": name_label,
		"final_x": idx * (_CELL_W + _CELL_GAP),
	}


# --- Reveal --------------------------------------------------------------

func _play_reveal_tween() -> void:
	# Header fades in first as the row's "label", then cells cascade in
	# with a staggered slide-up. Header isn't staggered against cells —
	# they begin together so the empty area fills out continuously.
	var header_tween := create_tween()
	header_tween.tween_property(_header, ^"modulate:a", 1.0, _HEADER_REVEAL_DURATION)

	for idx in range(_c.SEED_TYPE_ORDER.size()):
		var key: String = _c.SEED_TYPE_ORDER[idx]
		var info: Dictionary = _cells[key]
		var cell: PanelContainer = info.root
		var delay: float = float(idx) * _CELL_REVEAL_STAGGER
		var t := create_tween().set_parallel(true)
		t.tween_property(cell, ^"modulate:a", 1.0, _CELL_REVEAL_DURATION).set_delay(delay)
		t.tween_property(cell, ^"position:y", 0.0, _CELL_REVEAL_DURATION) \
			.set_delay(delay) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- Update --------------------------------------------------------------

func _refresh() -> void:
	var sel: String = _gs.selected_seed_type
	for key in _cells:
		var info: Dictionary = _cells[key]
		var count: int = int(_gs.seed_pouch.get(key, 0))
		info.count_label.text = "× %d" % count
		var stock: int = int(_gs.dispenser_stock.get(key, 0))
		var max_stock: int = int(_c.SEED_MAX_STOCK.get(key, 1))
		info.stock_label.text = "stock %d/%d" % [stock, max_stock]
		var ratio: float = clamp(float(stock) / float(max_stock), 0.0, 1.0)
		if ratio < 0.34:
			info.stock_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45, 0.95))
		else:
			info.stock_label.add_theme_color_override("font_color", Color(0.78, 0.74, 0.66, 0.85))
		var cell: PanelContainer = info.root
		# Selection visual is purely the stylebox (cyan vs amber border).
		# Modulate is reserved for the reveal animation so we don't fight
		# the per-frame refresh.
		if key == sel:
			cell.add_theme_stylebox_override("panel", _style_selected)
		else:
			cell.add_theme_stylebox_override("panel", _style_idle)


# --- Click ---------------------------------------------------------------

func _on_cell_input(event: InputEvent, seed_key: String) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_gs.selected_seed_type = seed_key
		accept_event()


# --- Styles --------------------------------------------------------------

func _make_idle_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.08, 0.06, 0.86)
	s.border_color = Color(0.78, 0.55, 0.28, 0.45)
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_right = 8
	s.corner_radius_bottom_left = 8
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	return s


func _make_selected_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.12, 0.18, 0.22, 0.94)
	s.border_color = Color(0.30, 0.85, 1.0, 0.95)
	s.border_width_left = 3
	s.border_width_top = 3
	s.border_width_right = 3
	s.border_width_bottom = 3
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_right = 8
	s.corner_radius_bottom_left = 8
	s.shadow_color = Color(0.30, 0.85, 1.0, 0.40)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 0)
	return s
