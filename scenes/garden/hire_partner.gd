extends Control

# The hire flow — a face-call + permit-signing interface on the site's public call
# terminal (scenes/shared/phone_booth.gd). Opened by the booth when the player presses
# [E] at the kiosk (opening redesign Chapter 1; world-prompt grammar replaces the old
# centered card). Three screens on the "tablet":
#   ROSTER  -> the three partner candidates, each callable.
#   CALL    -> the chosen candidate on a video call (portrait + greeting) — Choose / Back.
#   SIGN    -> "sign the permit to break ground": mouse-DRAG to sign, then Confirm.
# Committing stores the partner, advances the arc, and the partner calls the player back
# through the Director "partner" mouth (partner_intro). NO player lock (Principle 1) —
# this is a device the player operates, not a cutscene. The kiosk hides once hired.

const _PORTRAIT := preload("res://scenes/shared/business_portrait.gd")
const _PHASE_BUILD_STRUCTURE := 2
const _SUIT_FALLBACK := Color(0.28, 0.30, 0.36)

# Per-candidate flavour for the call. Keyed by the names in Constants.PARTNER_NAMES.
const CANDIDATES := {
	"MARA": {
		"suit": Color(0.16, 0.42, 0.45),
		"tagline": "Logistics & supply lines",
		"greet": "Mara. You found the plot — I'll find everything that goes on it. Sign and I start sourcing today.",
	},
	"TOBIN": {
		"suit": Color(0.18, 0.24, 0.44),
		"tagline": "Contracts & permits",
		"greet": "Tobin here. I've read the permit twice — it's clean. Put your name on it and we break ground today.",
	},
	"REESE": {
		"suit": Color(0.44, 0.20, 0.26),
		"tagline": "Investors & the long game",
		"greet": "Reese. I don't back small towers. Good thing you're not building one. You in?",
	},
}

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")
@onready var _gd: Node = get_node("/root/GameDirector")

var _frame: PanelContainer       # the tablet device frame
var _screen: VBoxContainer       # swappable screen content
var _style_idle: StyleBoxFlat
var _style_hover: StyleBoxFlat


func _ready() -> void:
	add_to_group("hire_call")     # the phone booth opens us by group
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0
	_style_idle = _row_style(Color(0.08, 0.13, 0.13, 0.92), Color(0.30, 0.70, 0.55, 0.5))
	_style_hover = _row_style(Color(0.13, 0.22, 0.20, 0.97), Color(0.45, 0.92, 0.66, 0.95))
	_build_frame()
	visible = false


# Called by the phone booth on [E].
func open() -> void:
	visible = true
	_show_roster()


func close() -> void:
	visible = false


# --- Tablet frame --------------------------------------------------------------
func _build_frame() -> void:
	_frame = PanelContainer.new()
	_frame.anchor_left = 0.5
	_frame.anchor_right = 0.5
	_frame.anchor_top = 0.5
	_frame.anchor_bottom = 0.5
	_frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_frame.grow_vertical = Control.GROW_DIRECTION_BOTH
	_frame.custom_minimum_size = Vector2(720.0, 0.0)
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.08, 0.98)
	style.border_color = Color(0.30, 0.78, 0.70, 0.85)   # device bezel glow
	style.set_border_width_all(3)
	style.set_corner_radius_all(20)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	style.shadow_size = 22
	style.shadow_offset = Vector2(0, 8)
	_frame.add_theme_stylebox_override("panel", style)
	add_child(_frame)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	_frame.add_child(margin)

	_screen = VBoxContainer.new()
	_screen.add_theme_constant_override("separation", 16)
	margin.add_child(_screen)


func _clear_screen() -> void:
	for c in _screen.get_children():
		c.queue_free()


func _eyebrow(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 15)
	return l


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.94, 0.98, 0.95))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_font_size_override("font_size", 30)
	return l


# --- Screen 1: roster of callable candidates -----------------------------------
func _show_roster() -> void:
	_clear_screen()
	_screen.add_child(_eyebrow("◉  PUBLIC CALL TERMINAL", Color(0.40, 0.86, 0.70)))
	_screen.add_child(_title("CALL A PARTNER"))
	var hint := Label.new()
	hint.text = "Three are available to break ground with you. Tap to call."
	hint.add_theme_color_override("font_color", Color(0.78, 0.86, 0.82))
	hint.add_theme_font_size_override("font_size", 18)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_screen.add_child(hint)

	for nm in _c.PARTNER_NAMES:
		_screen.add_child(_candidate_row(String(nm)))


func _candidate_row(nm: String) -> PanelContainer:
	var info: Dictionary = CANDIDATES.get(nm, {})
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0.0, 78.0)
	row.add_theme_stylebox_override("panel", _style_idle)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.mouse_entered.connect(func(): row.add_theme_stylebox_override("panel", _style_hover))
	row.mouse_exited.connect(func(): row.add_theme_stylebox_override("panel", _style_idle))
	row.gui_input.connect(_on_row_input.bind(nm))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	row.add_child(h)

	var portrait := _PORTRAIT.new()
	portrait.custom_minimum_size = Vector2(58, 58)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.set("suit", info.get("suit", _SUIT_FALLBACK))
	h.add_child(portrait)

	var col := VBoxContainer.new()
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	h.add_child(col)
	var name_l := Label.new()
	name_l.text = nm
	name_l.add_theme_color_override("font_color", Color(0.94, 0.98, 0.94))
	name_l.add_theme_font_size_override("font_size", 24)
	col.add_child(name_l)
	var tag := Label.new()
	tag.text = String(info.get("tagline", ""))
	tag.add_theme_color_override("font_color", Color(0.66, 0.80, 0.74))
	tag.add_theme_font_size_override("font_size", 16)
	col.add_child(tag)

	var call_l := Label.new()
	call_l.text = "📞"
	call_l.add_theme_font_size_override("font_size", 26)
	call_l.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	call_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(call_l)
	return row


func _on_row_input(event: InputEvent, nm: String) -> void:
	if _is_left_click(event):
		_show_call(nm)
		accept_event()


# --- Screen 2: the video call with the chosen candidate ------------------------
func _show_call(nm: String) -> void:
	_clear_screen()
	var info: Dictionary = CANDIDATES.get(nm, {})
	_screen.add_child(_eyebrow("●  ON CALL", Color(0.40, 0.86, 0.58)))

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	_screen.add_child(h)

	var portrait := _PORTRAIT.new()
	portrait.custom_minimum_size = Vector2(140, 140)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.set("suit", info.get("suit", _SUIT_FALLBACK))
	h.add_child(portrait)

	var col := VBoxContainer.new()
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	h.add_child(col)
	col.add_child(_title(nm))
	var greet := Label.new()
	greet.text = String(info.get("greet", ""))
	greet.add_theme_color_override("font_color", Color(0.90, 0.96, 0.92))
	greet.add_theme_font_size_override("font_size", 20)
	greet.add_theme_constant_override("line_spacing", 4)
	greet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	greet.custom_minimum_size = Vector2(420.0, 0.0)
	col.add_child(greet)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	_screen.add_child(actions)
	var back := _button_cell("‹  Back")
	back.gui_input.connect(func(e): if _is_left_click(e): _show_roster())
	actions.add_child(back)
	var choose := _button_cell("Choose " + nm + "  ›", true)
	choose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choose.gui_input.connect(func(e): if _is_left_click(e): _show_sign(nm))
	actions.add_child(choose)


# --- Screen 3: sign the permit (mouse-drag) ------------------------------------
func _show_sign(nm: String) -> void:
	_clear_screen()
	_screen.add_child(_eyebrow("✎  PERMIT TO BREAK GROUND", Color(0.86, 0.78, 0.40)))
	_screen.add_child(_title("Sign to confirm " + nm))
	var hint := Label.new()
	hint.text = "Drag across the line to sign."
	hint.add_theme_color_override("font_color", Color(0.80, 0.84, 0.82))
	hint.add_theme_font_size_override("font_size", 17)
	_screen.add_child(hint)

	var pad := _SignaturePad.new()
	pad.custom_minimum_size = Vector2(0.0, 200.0)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen.add_child(pad)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	_screen.add_child(actions)
	var clear := _button_cell("Clear")
	clear.gui_input.connect(func(e): if _is_left_click(e): pad.clear_sig())
	actions.add_child(clear)
	var back := _button_cell("‹  Back")
	back.gui_input.connect(func(e): if _is_left_click(e): _show_call(nm))
	actions.add_child(back)
	var confirm := _button_cell("Confirm & break ground", true)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.modulate = Color(1, 1, 1, 0.45)   # disabled-looking until signed
	confirm.gui_input.connect(func(e):
		if _is_left_click(e) and pad.ink_length() >= 110.0:
			_commit(nm))
	actions.add_child(confirm)
	# Enable the confirm button's look once enough ink is on the line.
	pad.changed.connect(func():
		confirm.modulate = Color(1, 1, 1, 1.0) if pad.ink_length() >= 110.0 else Color(1, 1, 1, 0.45))


# --- Commit the hire -----------------------------------------------------------
func _commit(nm: String) -> void:
	_gs.partner_name = nm
	var tel: Node = get_node_or_null("/root/Telemetry")
	if tel:
		tel.call("record", "partner_hired", {"name": nm})
	close()
	_gd.set_phase(_PHASE_BUILD_STRUCTURE)
	# The partner calls back to set the goal (Chapter 1 → 2 handoff). Player stays free;
	# the actual build happens from the crane later (Chunk 7), not auto-triggered here.
	_gd.call("issue_directive", "partner_intro")


# --- Shared widgets ------------------------------------------------------------
func _button_cell(text: String, accent: bool = false) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(0.0, 50.0)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var idle := _row_style(
		Color(0.13, 0.26, 0.22, 0.95) if accent else Color(0.10, 0.14, 0.16, 0.92),
		Color(0.40, 0.86, 0.62, 0.85) if accent else Color(0.40, 0.55, 0.55, 0.6))
	var hover := _row_style(
		Color(0.18, 0.34, 0.28, 0.98) if accent else Color(0.15, 0.20, 0.22, 0.97),
		Color(0.55, 0.96, 0.74, 0.98) if accent else Color(0.6, 0.8, 0.8, 0.95))
	cell.add_theme_stylebox_override("panel", idle)
	cell.mouse_entered.connect(func(): cell.add_theme_stylebox_override("panel", hover))
	cell.mouse_exited.connect(func(): cell.add_theme_stylebox_override("panel", idle))
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 21)
	l.add_theme_color_override("font_color", Color(0.92, 0.98, 0.93))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(l)
	return cell


func _is_left_click(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT


func _row_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.border_width_left = 5
	s.set_corner_radius_all(10)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 9
	s.content_margin_bottom = 9
	return s


# --- A mouse-drag signature pad ------------------------------------------------
class _SignaturePad extends Control:
	signal changed
	var _strokes: Array = []   # Array[PackedVector2Array]
	var _drawing := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_CROSS

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_drawing = true
				_strokes.append(PackedVector2Array([e.position]))
			else:
				_drawing = false
			queue_redraw()
			changed.emit()
			accept_event()
		elif e is InputEventMouseMotion and _drawing and _strokes.size() > 0:
			var cur: PackedVector2Array = _strokes[_strokes.size() - 1]
			cur.append(e.position)
			_strokes[_strokes.size() - 1] = cur
			queue_redraw()
			changed.emit()
			accept_event()

	func clear_sig() -> void:
		_strokes.clear()
		_drawing = false
		queue_redraw()
		changed.emit()

	func ink_length() -> float:
		var total := 0.0
		for s in _strokes:
			for i in range(1, s.size()):
				total += s[i].distance_to(s[i - 1])
		return total

	func _draw() -> void:
		# Paper.
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.95, 0.95, 0.92))
		# Signature line + ✕ marker.
		var ly: float = size.y * 0.74
		draw_line(Vector2(20, ly), Vector2(size.x - 20, ly), Color(0.45, 0.48, 0.52), 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(24, ly - 6),
			"✕", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.45, 0.48, 0.52))
		# Ink.
		for s in _strokes:
			if s.size() >= 2:
				draw_polyline(s, Color(0.06, 0.08, 0.20), 3.0, true)
			elif s.size() == 1:
				draw_circle(s[0], 1.6, Color(0.06, 0.08, 0.20))
