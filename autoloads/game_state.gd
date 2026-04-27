extends Node

# Slice-scoped game state. The full sibling game_state.gd holds hunger,
# political power, lit floors, modules, the Reckoning, etc. — all out of
# scope for this prototype. We only track what the iso prototype needs to
# render and respond to input.

# Player state in the 3D world.
#   iso_pos: world-space Vector3 of the player's feet (Y on the floor surface)
#   facing:  cardinal facing index, 0..3 (N, E, S, W); future use for anim
var player := {
	"iso_pos": Vector3.ZERO,
	"facing": 0,
}

# Camera state. angle_step rotates the pivot in 90° increments (0..3).
#   target: world-space Vector3 the camera looks at
#   ortho_size: orthographic projection size (smaller = zoomed in)
var camera := {
	"target": Vector3.ZERO,
	"ortho_size": 14.0,
	"angle_step": 0,
}
