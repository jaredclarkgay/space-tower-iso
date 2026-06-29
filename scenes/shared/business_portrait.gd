extends Control

# A programmatic placeholder "business person" portrait — a stylized bust drawn in
# code (head, hair, eyes, shirt collar, suit shoulders), tinted per candidate by the
# `suit` colour. Matches the no-asset-pipeline house style. Shared by the Partner
# phone-call box (scenes/shared/partner_phone.gd) and the hire face-call screen
# (scenes/garden/hire_partner.gd) so the same caller looks identical everywhere.

@export var suit: Color = Color(0.28, 0.30, 0.36):
	set(v):
		suit = v
		queue_redraw()
@export var skin: Color = Color(0.82, 0.64, 0.50)
@export var hair: Color = Color(0.18, 0.14, 0.11)
@export var shirt: Color = Color(0.90, 0.92, 0.95)
@export var bg: Color = Color(0.05, 0.09, 0.08, 1.0)


func _ready() -> void:
	clip_contents = true   # keep the bust inside its frame (no disc spilling past the box)


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var cx: float = w * 0.5
	# Call-screen backdrop.
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	# Shoulders: a large disc rising from the bottom, clipped by the frame.
	draw_circle(Vector2(cx, h * 1.18), w * 0.60, suit)
	# Shirt collar V over the suit.
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, h * 0.72), Vector2(cx - w * 0.16, h * 0.86), Vector2(cx + w * 0.16, h * 0.86),
	]), shirt)
	# Neck.
	draw_rect(Rect2(Vector2(cx - w * 0.085, h * 0.50), Vector2(w * 0.17, h * 0.22)), skin)
	# Head.
	draw_circle(Vector2(cx, h * 0.40), w * 0.21, skin)
	# Hair: a thick arc across the crown.
	draw_arc(Vector2(cx, h * 0.40), w * 0.215, PI * 1.08, PI * 1.92, 20, hair, w * 0.10)
	# Eyes.
	var eye := Color(0.12, 0.12, 0.14)
	draw_circle(Vector2(cx - w * 0.075, h * 0.40), w * 0.022, eye)
	draw_circle(Vector2(cx + w * 0.075, h * 0.40), w * 0.022, eye)
