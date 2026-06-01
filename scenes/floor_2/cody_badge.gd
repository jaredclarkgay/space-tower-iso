extends Control

# Small "Cody needs you" HUD badge, bottom-left. Appears when Cody's hopper is
# full (GameState.cody_full) with a little programmatic Cody portrait and a
# subtly blinking red LED on his antenna — replaces the old world-space "!"
# that rendered through floors. Lives under the Garden HUD group, so it only
# shows on the Garden and hides on other floors automatically.

@onready var _gs: Node = get_node("/root/GameState")

const W := 250.0
const H := 62.0
const LEFT_MARGIN := 24.0
const BOTTOM_MARGIN := 24.0

const PANEL_BG := Color(0.06, 0.07, 0.05, 0.90)
const PANEL_BORDER := Color(0.82, 0.58, 0.30, 0.62)
const CHASSIS := Color(0.42, 0.47, 0.55)
const DOME := Color(0.60, 0.66, 0.74)
const EYE := Color(0.35, 0.85, 1.0)
const LED := Color(1.0, 0.32, 0.24)

var _t: float = 0.0
var _shown: bool = false
var _panel_style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, H)
	size = Vector2(W, H)
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = LEFT_MARGIN
	offset_right = LEFT_MARGIN + W
	offset_top = -(H + BOTTOM_MARGIN)
	offset_bottom = -BOTTOM_MARGIN
	visible = false

	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = PANEL_BG
	_panel_style.border_color = PANEL_BORDER
	_panel_style.set_border_width_all(2)
	_panel_style.border_width_top = 3
	_panel_style.set_corner_radius_all(10)
	_panel_style.shadow_color = Color(0, 0, 0, 0.5)
	_panel_style.shadow_size = 10
	_panel_style.shadow_offset = Vector2(0, 4)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.95, 0.86, 0.55))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("outline_size", 3)
	title.text = "CODY"
	title.position = Vector2(70, 10)
	add_child(title)

	var sub := Label.new()
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.84, 0.82, 0.74))
	sub.text = "hopper full · press E"
	sub.position = Vector2(70, 32)
	add_child(sub)


func _process(delta: float) -> void:
	var want: bool = bool(_gs.get("cody_full"))
	if want != _shown:
		_shown = want
		visible = want
		if want:
			# Gentle pop-in.
			modulate.a = 0.0
			pivot_offset = Vector2(0, H)
			scale = Vector2(0.9, 0.9)
			var tw := create_tween().set_parallel(true)
			tw.tween_property(self, "modulate:a", 1.0, 0.25)
			tw.tween_property(self, "scale", Vector2.ONE, 0.32) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if visible:
		_t += delta
		queue_redraw()   # drive the LED blink


func _draw() -> void:
	draw_style_box(_panel_style, Rect2(Vector2.ZERO, size))

	# --- Little Cody portrait, left side. ---
	var cx := 36.0
	# Body / chassis (rounded).
	var body := StyleBoxFlat.new()
	body.bg_color = CHASSIS
	body.set_corner_radius_all(6)
	draw_style_box(body, Rect2(cx - 16.0, 30.0, 32.0, 20.0))
	# Dome (head).
	draw_circle(Vector2(cx, 28.0), 13.0, DOME)
	# Eye.
	draw_circle(Vector2(cx, 27.0), 4.2, EYE)
	draw_circle(Vector2(cx, 27.0), 2.0, Color(0.92, 0.99, 1.0))
	# Antenna + blinking red LED.
	draw_line(Vector2(cx, 15.0), Vector2(cx, 9.0), Color(0.5, 0.55, 0.62), 2.0)
	var blink: float = 0.45 + 0.55 * (0.5 + 0.5 * sin(_t * TAU * 1.1))   # ~1.1 Hz, subtle
	draw_circle(Vector2(cx, 8.0), 6.5, Color(LED.r, LED.g, LED.b, 0.18 * blink))  # soft glow
	draw_circle(Vector2(cx, 8.0), 3.4, Color(LED.r, LED.g, LED.b, blink))
