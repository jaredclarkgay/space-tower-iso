extends Control

# Programmatic portrait of Cody GX-5 — drawn directly with Control's _draw
# so we don't need any image assets. The palette mirrors the in-world
# robot's colours (bluish-teal chassis, grey dome, warm gold LED) so the
# portrait reads as obviously the same character.

func _draw() -> void:
	var c: Vector2 = size * 0.5
	# Inset background and a faint horizon line so the portrait isn't a flat sheet.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.08, 0.12, 1))
	draw_rect(Rect2(0, c.y + 28, size.x, size.y - (c.y + 28)), Color(0.07, 0.12, 0.18, 1))
	# Chassis — bluish-teal disc.
	draw_circle(c + Vector2(0, 22), 32, Color(0.25, 0.68, 0.80))
	draw_arc(c + Vector2(0, 22), 32, 0, TAU, 48, Color(0.08, 0.16, 0.22), 2)
	# Wheel hint shadows under the rim.
	draw_circle(c + Vector2(-22, 38), 4, Color(0.04, 0.06, 0.10))
	draw_circle(c + Vector2(22, 38), 4, Color(0.04, 0.06, 0.10))
	# Dome — light grey-blue.
	draw_circle(c + Vector2(0, -8), 22, Color(0.46, 0.50, 0.56))
	draw_arc(c + Vector2(0, -8), 22, 0, TAU, 48, Color(0.08, 0.16, 0.22), 1.5)
	# LED above the dome (warm gold).
	draw_circle(c + Vector2(0, -28), 5, Color(1.0, 0.85, 0.30))
	# Direction nub on the dome's front face.
	draw_rect(Rect2(c.x - 4, c.y - 8, 8, 6), Color(0.05, 0.10, 0.15))
	# Tiny eye dots so the portrait reads as alive.
	draw_circle(c + Vector2(-7, -6), 1.6, Color(0.05, 0.10, 0.15))
	draw_circle(c + Vector2(7, -6), 1.6, Color(0.05, 0.10, 0.15))
