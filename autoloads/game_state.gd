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

# Cumulative harvest VALUE (Red=1 ... Violet=15). Mirrored to the
# top-right HUD label.
var food_count := 0
# Number of times the player has manually harvested a plant. Drives the
# Cody-arrival threshold and the Schematics-button reveal — count, not
# value, so the unlock pace is steady regardless of which crops the
# player picks.
var plants_harvested := 0

# True while the Cody Schematics modal is open. iso_player + iso_robot
# both freeze input/movement when this is set.
var schematic_open := false

# True while the player is mid-conversation with Cody. iso_camera tweens
# in to a close-up on the player+Cody midpoint while this is set, and
# tweens back out when it clears.
var dialogue_open := false

# Customisable Cody appearance — set from the Schematics modal, applied
# both to the live robot and to the modal's 3D preview.
var cody_body_color: Color = Color(0.25, 0.68, 0.80)
var cody_dome_color: Color = Color(0.46, 0.50, 0.56)

# Active camera mode — "iso" (default), "profile" (side-on follow),
# or "ots" (over-the-shoulder). Set by the camera-mode HUD; iso_camera
# reads this every frame and tweens between presets when it changes.
var camera_mode: String = "iso"

# Player seed pouch — counts per seed type. Filled by interacting with the
# perimeter dispenser; drained by planting on empty plots. No cap. Keys
# match Constants.SEED_TYPE_ORDER (lowercase).
var seed_pouch := {
	"tomato": 0,
	"pumpkin": 0,
	"pepper": 0,
	"cucumber": 0,
	"blueberries": 0,
	"eggplant": 0,
}

# Currently selected seed type — drives both which slot the dispenser yields
# on E and which type the player plants on P. Number keys 1..6 set this.
var selected_seed_type: String = "tomato"

# Flips true the first time the player successfully takes a seed from the
# dispenser. Drives the bottom-of-screen seed selector HUD reveal — the
# panel stays hidden until this flag flips so the player isn't confused by
# a row of "× 0" entries before they understand the seed loop.
var dispenser_first_used: bool = false

# Dispenser stock mirrored from IsoDispenser. The dispenser is authoritative;
# this exists so the bottom seed HUD (and any future surfaces) can read
# current/max without a direct node reference.
var dispenser_stock := {
	"tomato": 0,
	"pumpkin": 0,
	"pepper": 0,
	"cucumber": 0,
	"blueberries": 0,
	"eggplant": 0,
}
