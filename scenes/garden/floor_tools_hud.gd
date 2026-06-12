extends Control

# Floor-tools palette — the bottom-centre HUD slot for the floor-population
# PLACEMENT verb (floor_design_system §6; floor_population_spec). For this first
# slice it carries ONE tool: the planter bed. It appears only during the PLACEMENT
# phase (gate lifted, Garden not yet alive) and shows the placement progress toward
# the ALIVE threshold (N / GARDEN_ALIVE_BED_COUNT). Mirrors the seed selector's
# shape; the palette grows (grow-light, water) in the next slice.
#
# Reveal/hide is state-driven: shown while `interiors_unlocked && !garden_alive()`,
# hidden otherwise (barren-unpowered, or once the floor blooms ALIVE).

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

const _CELL_W := 220.0
const _CELL_H := 84.0
const _HEADER_H := 22.0
const _BOTTOM_MARGIN := 132.0   # sits just above the seed-selector band

var _count_label: Label
var _shown := false


func _ready() -> void:
	var total_w: float = _CELL_W
	var total_h: float = _CELL_H + _HEADER_H + 4.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -total_w * 0.5
	offset_right = total_w * 0.5
	offset_top = -(total_h + _BOTTOM_MARGIN)
	offset_bottom = -_BOTTOM_MARGIN

	var header := Label.new()
	header.text = "FLOOR TOOLS"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.62, 0.92, 0.66, 0.9))
	header.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	header.add_theme_constant_override("outline_size", 4)
	header.anchor_right = 1.0
	header.offset_bottom = _HEADER_H
	add_child(header)

	# The one tool cell — a green-bordered panel with a swatch, name, [E] verb,
	# and the live placement count.
	var cell := PanelContainer.new()
	cell.anchor_top = 0.0
	cell.anchor_bottom = 1.0
	cell.anchor_left = 0.0
	cell.anchor_right = 1.0
	cell.offset_top = _HEADER_H + 4.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.12, 0.09, 0.82)
	style.border_color = Color(0.40, 0.88, 0.52, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	cell.add_theme_stylebox_override("panel", style)
	add_child(cell)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	cell.add_child(row)

	var swatch := ColorRect.new()
	swatch.color = _c.PLANTER_BED_RIM_COLOR
	swatch.custom_minimum_size = Vector2(26, 26)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_col)

	var name_label := Label.new()
	name_label.text = "[E]  Planter Bed"
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.92, 0.97, 0.90))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	name_label.add_theme_constant_override("outline_size", 3)
	text_col.add_child(name_label)

	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 13)
	_count_label.add_theme_color_override("font_color", Color(0.66, 0.86, 0.70))
	text_col.add_child(_count_label)

	modulate = Color(1, 1, 1, 0)   # start hidden; faded in on the placement phase
	visible = false


func _process(_delta: float) -> void:
	var should_show: bool = bool(_gs.get("interiors_unlocked")) and not bool(_gs.call("garden_alive"))
	if should_show != _shown:
		_shown = should_show
		visible = true
		var tween := create_tween()
		tween.tween_property(self, ^"modulate:a", 1.0 if should_show else 0.0, 0.3)
		if not should_show:
			tween.tween_callback(func(): visible = false)
	if should_show and _count_label:
		var placed: int = int(_gs.garden.get("populated", 0))
		var need: int = int(_c.GARDEN_ALIVE_BED_COUNT)
		_count_label.text = "%d / %d placed — bring the Garden alive" % [placed, need]
