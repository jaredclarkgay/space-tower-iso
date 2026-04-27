extends Node

# Slice-scoped game state. The full sibling game_state.gd holds hunger,
# political power, lit floors, modules, the Reckoning, etc. — all out of
# scope for this prototype. We only track what the iso prototype needs to
# render and respond to input.

# Player state on the iso plane.
#   iso_pos: world-space position on the floor (Vector2)
#   facing:  cardinal facing index, 0..3 (N, E, S, W) for sprite/anim selection
var player := {
	"iso_pos": Vector2.ZERO,
	"facing": 0,
}

# Camera state. angle_step rotates in 90° increments (0..3) so depth-sort
# math stays integer-clean.
var camera := {
	"target": Vector2.ZERO,
	"zoom": 1.0,
	"angle_step": 0,
}
