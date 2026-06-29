extends Control

# The Partner — the Director's BUSINESS mouth (vision.md §1-2; opening redesign Part 0
# Principle 3). A *human* who NEVER appears in person: they reach the player by PHONE,
# rendered as a dialogue box with a business portrait, framed as a call. Their domain
# is external resources / contracts / world-facing detail — the things Cody (the
# construction & tending mouth) wouldn't touch.
#
# This is a registered Director mouth (mouth_id "partner"): GameDirector.issue_directive()
# routes any directive with `"speaker": "partner"` here. It renders the lines one at a
# time, advance-to-continue, exactly like Cody's director mode — but CRUCIALLY it does
# NOT freeze the player. A phone call needs no arrival cinematic and no lock; the player
# stays free (Principle 1). That's the whole reason the Partner is a call, not a cutscene.
#
# House idioms reused: the panel styling mirrors Cody's box (scenes/garden/iso_robot.gd
# _build_dialogue_panel); the advance affordance is a gui_input PanelContainer, NOT a
# Button, so it can't steal the Space/Enter ui_accept that jump is bound to (F-008) while
# the player roams freely during the call. The portrait is programmatic placeholder art
# (a stylized business bust), tinted per candidate — matching the no-asset-pipeline style.

const _PORTRAIT := preload("res://scenes/shared/business_portrait.gd")
const MOUTH_PRIORITY := 10   # a character mouth, same tier as Cody (routing is by speaker name)

# Per-candidate suit palette for the placeholder bust. Keyed by the names in
# Constants.PARTNER_NAMES; anything else falls back to a neutral slate.
const SUITS := {
	"MARA":  Color(0.16, 0.42, 0.45),   # teal
	"TOBIN": Color(0.18, 0.24, 0.44),   # navy
	"REESE": Color(0.44, 0.20, 0.26),   # burgundy
}
const SUIT_FALLBACK := Color(0.28, 0.30, 0.36)

var mouth_id := "partner"

@onready var _gs: Node = get_node("/root/GameState")
@onready var _gd: Node = get_node("/root/GameDirector")

var _panel: PanelContainer
var _portrait: Control
var _name_label: Label
var _msg: Label
var _chips: VBoxContainer
var _lines: Array = []
var _idx: int = 0


func _ready() -> void:
	# Full-rect container; ignore mouse on the root so only the panel/chip catch clicks.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0
	if _gd and _gd.has_method("register_mouth"):
		_gd.register_mouth(self, MOUTH_PRIORITY)


# --- Director-mouth interface --------------------------------------------------
# Accept any directive addressed to us (or unaddressed). Render its lines as a call.
# Returns true once taken — we are the speaker. No player freeze (Principle 1).
func deliver_directive(d: Dictionary) -> bool:
	var speaker: String = String(d.get("speaker", ""))
	if speaker != "" and speaker != mouth_id:
		return false
	var lines: Array = d.get("lines", [])
	if lines.is_empty():
		return false
	if _panel == null:
		_build_panel()
	_lines = lines
	_idx = 0
	_refresh_caller()
	_render_line()
	_panel.visible = true
	return true


func is_call_open() -> bool:
	return _panel != null and _panel.visible


func end_call() -> void:
	if _panel:
		_panel.visible = false


# Pull the chosen partner's name + suit tint at call time (set at the hire beat).
func _refresh_caller() -> void:
	var nm: String = String(_gs.partner_name) if _gs else ""
	if nm == "":
		nm = "PARTNER"
	_name_label.text = nm
	_portrait.set("suit", SUITS.get(nm, SUIT_FALLBACK))
	_portrait.queue_redraw()


func _render_line() -> void:
	_msg.text = String(_lines[_idx])
	for c in _chips.get_children():
		c.queue_free()
	var last: bool = _idx >= _lines.size() - 1
	var chip := _make_chip("▸  Got it" if last else "▸  Continue")
	chip.gui_input.connect(_on_chip_input)
	_chips.add_child(chip)


func _on_chip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_idx += 1
		if _idx >= _lines.size():
			end_call()
		else:
			_render_line()
		accept_event()


# --- Panel construction (mirrors Cody's box, recoloured as a phone call) --------
func _build_panel() -> void:
	var p := PanelContainer.new()
	p.name = "PartnerCall"
	# Bottom-CENTER, distinct from Cody's bottom-left box and the bottom-right camera
	# buttons. Anchors collapse to the bottom-center point; it grows up + out from there.
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 1.0
	p.anchor_bottom = 1.0
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_bottom = -30.0
	p.custom_minimum_size = Vector2(640.0, 0.0)
	p.mouse_filter = Control.MOUSE_FILTER_PASS

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.12, 0.10, 0.96)
	style.border_color = Color(0.34, 0.80, 0.56, 0.80)   # cool green = "on a call" (vs Cody's teal/amber)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 16
	style.shadow_offset = Vector2(0, 6)
	p.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	p.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	# Header: portrait bust + (name over an "● ON CALL" eyebrow).
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	col.add_child(header)

	_portrait = _PORTRAIT.new()
	_portrait.custom_minimum_size = Vector2(84, 84)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_portrait)

	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 2)
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(names)

	var eyebrow := Label.new()
	eyebrow.text = "●  ON CALL"
	eyebrow.add_theme_color_override("font_color", Color(0.40, 0.86, 0.58))
	eyebrow.add_theme_font_size_override("font_size", 14)
	names.add_child(eyebrow)

	_name_label = Label.new()
	_name_label.text = "PARTNER"
	_name_label.add_theme_color_override("font_color", Color(0.92, 0.98, 0.92))
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_name_label.add_theme_constant_override("outline_size", 4)
	_name_label.add_theme_font_size_override("font_size", 28)
	names.add_child(_name_label)

	_msg = Label.new()
	_msg.add_theme_color_override("font_color", Color(0.93, 0.97, 0.94))
	_msg.add_theme_font_size_override("font_size", 23)
	_msg.add_theme_constant_override("line_spacing", 5)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_msg)

	_chips = VBoxContainer.new()
	_chips.add_theme_constant_override("separation", 8)
	col.add_child(_chips)

	add_child(p)
	_panel = p
	_panel.visible = false


# A click chip in the phone-call palette (gui_input PanelContainer — not a Button — so
# it never steals the Space/Enter that jump is bound to while the player roams; F-008).
func _make_chip(text: String) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(0.0, 46.0)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var idle := _chip_style(Color(0.10, 0.22, 0.17, 0.90), Color(0.30, 0.70, 0.50, 0.55))
	var hover := _chip_style(Color(0.15, 0.32, 0.24, 0.97), Color(0.45, 0.92, 0.62, 0.95))
	cell.add_theme_stylebox_override("panel", idle)
	cell.mouse_entered.connect(func(): cell.add_theme_stylebox_override("panel", hover))
	cell.mouse_exited.connect(func(): cell.add_theme_stylebox_override("panel", idle))

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.88, 0.98, 0.90))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(label)
	return cell


func _chip_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.border_width_left = 5   # bright accent strip down the left edge (matches Cody's chips)
	s.set_corner_radius_all(9)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s
