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

# Sell value of the produce currently on the player's back. Increments on
# harvest by the plant's `value` (Red=1 … Violet=15); zeroed when the player
# offloads at a vacuum tube. NOT a lifetime total — it's the carried value.
var food_count := 0
# Plant count currently in the backpack (1 per veggie, regardless of value).
# Capped at Constants.BACKPACK_CAPACITY by the harvest call sites, so this
# is what the HUD and the player's backpack visual both read.
var backpack_count := 0
# Lifetime cash earned by selling produce down the tubes. Accumulated when
# the player drops a backpack into a tube; never decremented by gameplay
# yet (no purchases wired up).
var cash := 0
# Number of times the player has manually harvested a plant. Drives the
# Cody-arrival threshold and the Schematics-button reveal — count, not
# value, so the unlock pace is steady regardless of which crops the
# player picks.
var plants_harvested := 0

# True while the Cody Schematics modal is open. iso_player + iso_robot
# both freeze input/movement when this is set.
var schematic_open := false

# True while the player is riding the elevator car — the elevator owns the
# player's transform, so iso_player skips its own movement/physics.
var riding_elevator := false

# True while the player is mid vacuum-lift hop (shared/vacuum_lift.gd owns the
# player's transform for the quick ±1-floor suction). Like riding_elevator,
# iso_player skips its own physics and the tower keeps tracking _current_level
# during the hop so the destination floor's slab is solid on arrival.
var tube_hopping := false

# True while the player is grounded inside a corner tube mouth with a hop
# available. The vacuum lift sets this each frame; iso_player reads it to swap
# its normal jump/charge for the vacuum hop (the lift handles the jump press).
var in_tube_mouth := false

# Camera juice signals (one-shot, producer sets / camera consumes):
#   camera_arrival_pulse — set by tower_controller when the player changes
#     floors, so iso_camera briefly pulls back to a survey of the new floor.
#   camera_land_kick — set by iso_player to the downward landing speed of a hard
#     landing, so iso_camera applies a quick dip. Camera zeroes it on read.
var camera_arrival_pulse := false
var camera_land_kick := 0.0

# Soft camera focus override (e.g. Cody's arrival ceremony): while active, the
# iso camera eases its pivot to camera_focus_point and zooms in, instead of
# following the player. Producer sets active + point; clears active when done.
var camera_focus_active := false
var camera_focus_point := Vector3.ZERO

# True while the player is operating the Vista crane — the crane owns the
# player's transform (rides the cab), so iso_player skips its own physics and
# the vacuum lift won't offer a hop.
var driving_crane := false

# True while the player is mid-conversation with Cody. iso_camera tweens
# in to a close-up on the player+Cody midpoint while this is set, and
# tweens back out when it clears.
var dialogue_open := false

# True while Cody's hopper is full and waiting for the player to collect.
# Drives the HUD "Cody is full" badge (cody_badge.gd) instead of a
# world-space marker, so the alert never renders through floors.
var cody_full := false

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

# (Retired with the scene-swap era: in_transit / arrived_via_stairs. The
# stacked tower has no scene swaps — you ride the elevator car and walk the
# stairs in one continuous world — so neither fade-coordination flag exists.)


# Floor 1 (utility) state. master_on flips when the player pulls the master
# breaker; per-system `connected` and `pipe_active` track each system's
# state. Survives floor switches so a return trip restores the lit room
# and primed/active sources without re-playing the intro.
var utility := {
	"master_on": false,
	"connected": {
		"water": false,
		"power": false,
		"atmosphere": false,
		"data": false,
		"waste": false,
		"cargo": false,
	},
	"pipe_active": {
		"water": false,
		"power": false,
		"atmosphere": false,
		"data": false,
		"waste": false,
		"cargo": false,
	},
}


# Floor 3 (Arboretum) state.
#   water_connected:    has the player connected the floor's irrigation
#                       (Phase 2B — currently always treated as on; trees
#                       grow as soon as planted).
#   sunlight_active:    has the player opened the Floor 4 skylight panel
#                       (Phase 2B — same).
#   trees:              per-plot tree state, keyed by "ix,iz" grid coords.
#                       Legacy keys (never repurposed): variety: 0|1,
#                       planted_at_msec, world_pos. Genome-era additions
#                       (see ArboretumTree): genome, rng_seed, generation,
#                       parents, growth_start_msec, o2_rate, fertile,
#                       last_seed_msec. planted_at/growth_start are SIM-clock
#                       timestamps. ArboretumTree.ensure_genome() migrates any
#                       entry missing the new keys.
#                       Both Floor 3 and Floor 4 controllers read this dict
#                       and render their slice (full tree on F3; canopy on F4
#                       once growth_t > TREE_FLOOR_4_VISIBLE_THRESHOLD).
#   next_variety:       0 or 1 — alternated on each plant so the mix reads
#                       as deliberately varied, not random.
var arboretum := {
	"water_connected": false,
	"sunlight_active": false,
	"trees": {},
	"next_variety": 0,
}

# SIM clock (milliseconds). Tree growth runs on THIS, not real engine time, so
# a future "speed up growth" affordance can scale growth without making ambient
# wind sway (which animates off the shader's real TIME) shimmy. Advanced every
# frame in _process. Persists across floor swaps because it's autoload state.
var sim_time_msec: float = 0.0
var sim_speed: float = 1.0


func _process(delta: float) -> void:
	sim_time_msec += delta * 1000.0 * sim_speed

# Floor 4 (Canopy deck) holds no independent state — it renders the same
# trees Floor 3 owns. Phase 1 keeps a slot here in case Phase 2 wants per-
# floor flags (e.g. skylight_open_t for the panel animation).
var canopy := {}
