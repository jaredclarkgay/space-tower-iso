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

# Harvested-plant counter, mirrored to the top-right HUD label.
var food_count := 0

# True while the Cody Schematics modal is open. iso_player + iso_robot
# both freeze input/movement when this is set.
var schematic_open := false

# Customisable Cody appearance — set from the Schematics modal, applied
# both to the live robot and to the modal's 3D preview.
var cody_body_color: Color = Color(0.25, 0.68, 0.80)
var cody_dome_color: Color = Color(0.46, 0.50, 0.56)
