extends CharacterBody3D

# Programmatic placeholder character for the iso slice. Walks on the floor
# plane via WASD / arrow keys, jumps with Space.
#
# Movement design: 4-direction, but expressed as a normalized Vector2 (so the
# implementer can flip to 8-direction with one comment if it feels stiff).
# 4-direction matches the iso cardinal axes after camera rotation, keeps
# depth-sort intuitions clean, and is honest about the slice's scope — we are
# testing whether iso *feels right*, not whether 8-way movement feels right.
#
# Movement is camera-relative: WASD maps to screen up/down/left/right, which
# means the world-space direction depends on the camera's current yaw. This
# is what makes WASD feel correct when the camera has been rotated.
#
# Body: programmatic primitives — legs, torso, arms, head, hardhat with brim,
# tool belt, facing nub. No animation in the slice; static geometry that
# reads as a person rather than a single capsule.

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

# Camera the player should be relative to. Set by floor_2.tscn.
@export var camera_pivot_path: NodePath
@export var iso_floor_path: NodePath
@export var iso_robot_path: NodePath
@export var iso_dispenser_path: NodePath
@export var iso_tubes_path: NodePath
var _camera_pivot: Node3D
var _iso_floor: Node3D
var _iso_robot: Node3D
var _iso_dispenser: Node3D
var _iso_tubes: Node3D
# Visual root — rotates Y with movement direction. Separate from the
# CharacterBody3D so the collision capsule doesn't spin with the body.
var _visual: Node3D
# Inner pivot at the body's centre of mass (waist) — rotates X for the
# tuck-and-flip when the jump was charged past TUCK_FLIP_CHARGE_THRESHOLD.
# All body parts are children of this so the flip pivots around the waist
# rather than around the feet.
var _flip_pivot: Node3D
# Articulated body pivots — each rotates X around a logical joint so we can
# compose plant-kneel / charge-windup / tuck / landing poses out of real
# joint angles instead of just a uniform scale.y squash.
var _legs_pivot: Node3D    # at the hip (top of thigh) — pulls knees up for tuck
var _torso_pivot: Node3D   # at the waist (rotation pivot for forward bend)
var _arms_pivot: Node3D    # at the shoulders (top of arm capsule)
var _head_pivot: Node3D    # at the base of the neck
# Per-limb pivots — children of the corresponding parent pivot. These
# rotate X for the walk / run cycle (alternating L/R) and compose
# multiplicatively with the parent pose, so a kneel can have arms
# reaching down AND a walk can have arms swinging at the shoulders.
var _leg_l_pivot: Node3D
var _leg_r_pivot: Node3D
var _arm_l_pivot: Node3D
var _arm_r_pivot: Node3D

# Locomotion cycle state. Phase advances while the player is moving on
# the ground; amplitude / lift / bob lerp up/down so legs ease into and
# out of the cycle on movement start/stop instead of snapping.
var _locomotion_phase: float = 0.0
var _locomotion_amp: float = 0.0
var _locomotion_lift: float = 0.0   # smoothed foot-lift height
var _locomotion_bob: float = 0.0    # smoothed body-bob magnitude

const VISUAL_PIVOT_Y := 0.85    # waist height — the flip's rotation centre
const HIP_OFFSET_Y := -0.23     # hip top in flip_pivot frame (top of leg capsule)
const SHOULDER_OFFSET_Y := 0.375  # shoulder top in torso_pivot frame
const NECK_OFFSET_Y := 0.39       # neck base in torso_pivot frame

# Pose targets — each entry is rotation.x for {legs, torso, arms, head} in
# radians. Positive values bend the joint "forward" (head/arms toward +Z in
# the body's local frame, after the Y facing rotation). Tuned so the body
# reads as actively kneeling / winding up / tucking, not just compressed.
const POSE_IDLE := {"legs_x": 0.0, "torso_x": 0.0, "arms_x": 0.0, "head_x": 0.0}
# Kneel — gentle forward bend, arms reach down with a natural angle (not
# fully horizontal), head tilts to look at where the seed lands without
# burying the chin in the chest. Tuned for "kneeling planter" rather than
# "doubled over picking up a coin".
const POSE_KNEEL := {"legs_x": 0.0, "torso_x": 0.42, "arms_x": -1.05, "head_x": 0.32}
# Charge — front-flip anticipation: slight forward lean, arms swung UP and
# FORWARD (like a diver loading the leap), head tilted slightly forward to
# track the launch arc. The previous arms-back pose read as a back-flip
# wind-up, which clashed with the body's actual forward rotation.
const POSE_CHARGE := {"legs_x": 0.0, "torso_x": 0.28, "arms_x": -2.20, "head_x": 0.18}
# Tuck — controlled mid-flip pose: knees pulled up but not buried in chest,
# arms held in front but not crammed into the face, head tilted but still
# in line with the body. Reads as a gymnastic tuck instead of a panic ball.
const POSE_TUCK := {"legs_x": -1.10, "torso_x": 0.22, "arms_x": -1.45, "head_x": 0.32}
# Landing — sharp forward absorption: deep torso bend, arms swing forward
# for balance, head dips. Bigger than v1 so the impact beat is unmissable.
const POSE_LAND := {"legs_x": 0.0, "torso_x": 0.55, "arms_x": -0.90, "head_x": 0.40}
# rad/s — how fast joints lerp toward target. Higher than the previous
# 14.0 so charge/land beats actually catch up to their target before the
# state passes (charge ramps over 1.0 s; land squash over 0.32 s).
const POSE_BLEND_RATE := 18.0
# Once the operator has held jump this long, the player commits to a charged
# spring and horizontal movement freezes. Below this threshold a quick tap
# stays free so run-and-jump still works.
const CHARGE_MOVE_LOCK_THRESHOLD := 0.12

# --- Walk + run cycle ---
# Cycle rate is DERIVED from current horizontal speed and stride amplitude
# rather than fixed, so feet appear to plant in the world instead of
# sliding. The plant phase of each leg is half the cycle (one sine period
# = two foot strikes); during plant the foot is held fixed in world space
# and the body translates over it. cycle_rate = π · speed / (2 · amp_z)
# is the rate at which the body covers exactly one foot-width per plant
# phase, so feet stay glued to the ground.
const LEG_LENGTH := 0.57              # hip pivot → boot, used by the IK math
const WALK_LIMB_AMPLITUDE := 0.55
const WALK_BOB_AMPLITUDE := 0.020
const WALK_FOOT_LIFT := 0.06          # how high the foot rises mid-swing
const RUN_LIMB_AMPLITUDE := 0.95
const RUN_BOB_AMPLITUDE := 0.055
const RUN_FOOT_LIFT := 0.12
const ARM_SWING_RATIO := 0.65         # arm amplitude as fraction of leg
const LOCOMOTION_BLEND_RATE := 12.0   # how fast amp lerps in/out

var _facing_yaw := 0.0     # smoothed yaw the visual is interpolating toward
const FACING_TURN_SPEED := 14.0   # rad/s — snappy but not jittery

# Jump state (tap = base jump, hold to charge for up to 4× height).
var _charge_time := 0.0
var _land_squash_t := 0.0
var _was_in_air := false
var _air_vy := 0.0          # vertical speed while airborne — read by the landing-dip camera kick
var _is_flipping := false   # true between a charged takeoff and the next landing
# Flip duration is computed from the jump's expected airtime so the rotation
# completes exactly TUCK_FLIP_ROTATIONS turns by the time the player lands.
var _flip_airtime_expected := 0.0   # seconds — set on takeoff
var _flip_airtime_elapsed := 0.0    # seconds — accumulated each airborne frame

# Harvest state. The player roots in place, scales down to a kneel, and
# fills a horizontal green bar. Movement input or releasing E cancels.
var _is_harvesting := false
var _harvest_progress := 0.0          # 0..1
var _harvest_target: Variant = null   # plot Dictionary returned by iso_floor
var _nearest_plot: Variant = null     # cached this frame for E-prompt visibility

# Plant state. One-shot kneel of PLANT_DURATION starts on P press; movement
# input cancels mid-action. On completion the targeted empty plot becomes a
# stage-1 sprout via iso_floor.plant() and a seed is decremented from the
# player's pouch.
var _is_planting := false
var _plant_progress := 0.0
var _plant_target: Variant = null
var _nearest_empty_plot: Variant = null

# Prompt above the head when a harvestable plot is in range. Two stacked
# Label3Ds: a tiny "E" key label, and a slightly larger "Harvest <PlantName>"
# line below it. Both billboard so they stay readable from any iso angle.
# Harvest gauge: a horizontal green bar that fills over HARVEST_DURATION.
var _prompt_root: Node3D
var _e_prompt: Label3D
var _harvest_label: Label3D
var _harvest_bar_root: Node3D
var _harvest_bar_fill_pivot: Node3D
var _harvest_bar_fill_mesh: MeshInstance3D

# Charge gauge — vertical bar above the head. Fixed orientation in world,
# parented to self (not _visual) so it doesn't rotate with body facing.
var _bar_root: Node3D
var _bar_fill_pivot: Node3D
var _bar_fill_mesh: MeshInstance3D

# Backpack mesh — sits behind the torso, scales with backpack fill. Visual
# only; the cap/source-of-truth lives in GameState.backpack_count.
var _backpack: MeshInstance3D
var _backpack_strap_l: MeshInstance3D
var _backpack_strap_r: MeshInstance3D
const BACKPACK_EMPTY_SCALE := Vector3(0.55, 0.45, 0.30)
const BACKPACK_FULL_SCALE := Vector3(1.05, 1.10, 0.85)
# Cooldown gating the BACKPACK FULL floater so it doesn't stack on
# rapid-fire E presses.
var _backpack_full_floater_cooldown := 0.0


var _spawn_position: Vector3 = Vector3.ZERO
# Edge-fall catch — the "jump-from" point the player snaps back to after plunging
# off an open edge (see the catch logic at the end of _physics_process).
var _last_ground_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_flip_pivot = Node3D.new()
	_flip_pivot.name = "FlipPivot"
	_flip_pivot.position.y = VISUAL_PIVOT_Y
	_visual.add_child(_flip_pivot)
	# Articulated joint pivots. Build hierarchy first so _build_visual can
	# parent body parts directly into the right pivot.
	_legs_pivot = Node3D.new()
	_legs_pivot.name = "LegsPivot"
	_legs_pivot.position.y = HIP_OFFSET_Y
	_flip_pivot.add_child(_legs_pivot)
	_torso_pivot = Node3D.new()
	_torso_pivot.name = "TorsoPivot"
	_torso_pivot.position.y = 0.0   # waist origin
	_flip_pivot.add_child(_torso_pivot)
	_arms_pivot = Node3D.new()
	_arms_pivot.name = "ArmsPivot"
	_arms_pivot.position.y = SHOULDER_OFFSET_Y
	_torso_pivot.add_child(_arms_pivot)
	_head_pivot = Node3D.new()
	_head_pivot.name = "HeadPivot"
	_head_pivot.position.y = NECK_OFFSET_Y
	_torso_pivot.add_child(_head_pivot)
	# Per-limb pivots — each at the corresponding shoulder / hip in its
	# parent's frame. Limbs hang down from their own pivot so the walk /
	# run cycle rotates them naturally from the joint.
	_leg_l_pivot = Node3D.new()
	_leg_l_pivot.name = "LegLPivot"
	_leg_l_pivot.position = Vector3(-0.13, 0.0, 0.0)
	_legs_pivot.add_child(_leg_l_pivot)
	_leg_r_pivot = Node3D.new()
	_leg_r_pivot.name = "LegRPivot"
	_leg_r_pivot.position = Vector3(0.13, 0.0, 0.0)
	_legs_pivot.add_child(_leg_r_pivot)
	_arm_l_pivot = Node3D.new()
	_arm_l_pivot.name = "ArmLPivot"
	_arm_l_pivot.position = Vector3(-0.32, 0.0, 0.0)
	_arms_pivot.add_child(_arm_l_pivot)
	_arm_r_pivot = Node3D.new()
	_arm_r_pivot.name = "ArmRPivot"
	_arm_r_pivot.position = Vector3(0.32, 0.0, 0.0)
	_arms_pivot.add_child(_arm_r_pivot)
	_build_visual()
	_build_collision()
	_build_charge_bar()
	_build_e_prompt()
	_build_harvest_bar()
	if camera_pivot_path:
		_camera_pivot = get_node(camera_pivot_path)
	if iso_floor_path:
		_iso_floor = get_node(iso_floor_path)
	if iso_robot_path:
		_iso_robot = get_node(iso_robot_path)
	if iso_dispenser_path:
		_iso_dispenser = get_node(iso_dispenser_path)
	if iso_tubes_path:
		_iso_tubes = get_node(iso_tubes_path)

	# Spawn facing the camera so the player's front is visible on first
	# frame instead of their back. Camera yaw -135° puts the camera at NW
	# looking SE; player should look NW (toward the camera). Math: the
	# world direction from player toward camera maps via atan2(x,z) to the
	# same numeric value as CAMERA_YAW_DEG_INITIAL, so this stays correct
	# if the operator changes the default yaw later.
	_facing_yaw = deg_to_rad(_c.CAMERA_YAW_DEG_INITIAL)
	if _visual:
		_visual.rotation.y = _facing_yaw

	# Capture the spawn pose for the out-of-bounds fall fail-safe (respawn here
	# rather than to a hard-coded (0,1,0), which used to land on a shaft hole).
	_spawn_position = global_position
	_last_ground_pos = global_position


func _physics_process(delta: float) -> void:
	# Debug stop-gap until M6 wires the elevator: backslash swaps the
	# current scene between Garden (floor_2) and Floor 1 (utility).
	# GameState autoload preserves cross-scene state.
	# (Debug floor cycling is handled by the tower controller now.)

	# While riding the elevator, mid vacuum-lift hop, OR operating the crane, that
	# system owns the player's transform — skip our own movement/physics entirely.
	if _gs and (_gs.get("riding_elevator") or _gs.get("tube_hopping") or _gs.get("driving_crane")):
		return

	# When the Cody dialogue or the Schematics modal is open, lock the
	# player in place — number-key shortcuts in the dialogue would
	# otherwise move the body, and movement would also drift the camera
	# target.
	var dialogue_open: bool = (
		_iso_robot != null
		and _iso_robot.has_method("is_dialogue_open")
		and _iso_robot.is_dialogue_open()
	)
	var schematic_open: bool = _gs.get("schematic_open") if _gs else false
	if dialogue_open or schematic_open:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = 0.0 if is_on_floor() else (velocity.y - _c.PLAYER_GRAVITY * delta)
		move_and_slide()
		if _prompt_root:
			_prompt_root.visible = false
		return

	# When standing in a corner tube mouth, jump is reserved for the vacuum hop
	# UP and the down key triggers the hop DOWN (both handled by vacuum_lift.gd).
	# Read it here so we can stop the down key from WALKING the player off the
	# mouth before they can descend — the down-hop only fires if they're still on
	# the tube. Other directions still step them out normally.
	var in_tube_mouth: bool = bool(_gs.get("in_tube_mouth")) if _gs else false

	# Horizontal input — camera-relative.
	var input := Vector2(
		Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		Input.get_action_strength(&"move_down") - Input.get_action_strength(&"move_up"),
	)
	# In a tube mouth, cancel the south/"down" component so it descends instead
	# of walking you off; up/left/right still move you out.
	if in_tube_mouth:
		input.y = minf(input.y, 0.0)
	if input.length() > 1.0:
		input = input.normalized()
	var yaw := 0.0
	if _camera_pivot:
		yaw = _camera_pivot.rotation.y
	var world_dir := Vector3(
		input.x * cos(yaw) + input.y * sin(yaw),
		0.0,
		-input.x * sin(yaw) + input.y * cos(yaw),
	)

	# Compute dispenser proximity first so number-key handling can decide
	# whether to dispense or just select. Interaction priority: dispenser >
	# robot > plot harvest. Plant (P) is independent and routes to the
	# nearest empty plot regardless of E-target.
	var dispenser_interactable: bool = (
		_iso_dispenser != null
		and _iso_dispenser.is_interactable_at(global_position, _c.DISPENSER_INTERACT_RADIUS)
	)

	# Number-key seed input. Outside the dispenser this only updates the
	# selection (used by P-plant). At the dispenser, the same key dispenses
	# a seed of that specific type — so the player gets an explicit
	# per-press answer instead of having to remember what's selected.
	for n in range(_c.SEED_TYPE_ORDER.size()):
		if Input.is_action_just_pressed(&"seed_select_%d" % (n + 1)):
			var key: String = _c.SEED_TYPE_ORDER[n]
			if dispenser_interactable:
				_iso_dispenser.try_dispense_type(key)
			else:
				_gs.selected_seed_type = key
	var robot_interactable: bool = (
		not dispenser_interactable
		and _iso_robot != null
		and _iso_robot.is_interactable_at(global_position, _c.ROBOT_INTERACT_RADIUS)
	)
	# Tube interaction is only "live" when there's something to sell — the
	# tube's own get_interaction_label returns "" with an empty backpack so
	# the prompt falls through to plot harvest naturally.
	var tube_interactable: bool = (
		not dispenser_interactable
		and not robot_interactable
		and _iso_tubes != null
		and _iso_tubes.is_interactable_at(global_position, _c.VACUUM_TUBE_INTERACT_RADIUS)
		and _gs.backpack_count > 0
	)
	var dispenser_label: String = ""
	var robot_label: String = ""
	var tube_label: String = ""
	if dispenser_interactable:
		dispenser_label = _iso_dispenser.get_interaction_label()
		_nearest_plot = null
	elif robot_interactable:
		robot_label = _iso_robot.get_interaction_label()
		_nearest_plot = null
	elif tube_interactable:
		tube_label = _iso_tubes.get_interaction_label()
		_nearest_plot = null
	elif _iso_floor:
		_nearest_plot = _iso_floor.find_nearest_harvestable_plot_near(
			global_position, _c.HARVEST_RADIUS
		)
	else:
		_nearest_plot = null

	# Always look up the nearest empty plot — the P prompt is allowed to
	# share screen space with the E prompt only when no E action is offered,
	# so the lookup itself is cheap and the prompt logic decides what to show.
	if _iso_floor:
		_nearest_empty_plot = _iso_floor.find_nearest_empty_plot_near(
			global_position, _c.HARVEST_RADIUS
		)
	else:
		_nearest_empty_plot = null

	if _is_harvesting:
		var move_canceled: bool = input.length_squared() > 0.001
		var released: bool = not Input.is_action_pressed(&"interact")
		if move_canceled or released or not is_on_floor():
			_is_harvesting = false
			_harvest_progress = 0.0
			_harvest_target = null
		else:
			_harvest_progress += delta / _c.HARVEST_DURATION
			if _harvest_progress >= 1.0:
				if _iso_floor and _harvest_target != null:
					var value: int = int(_harvest_target.plant_type.get("value", 1))
					_iso_floor.harvest_plot(_harvest_target)
					_gs.food_count += value
					_gs.backpack_count = mini(_gs.backpack_count + 1, _c.BACKPACK_CAPACITY)
					_gs.plants_harvested += 1
				_is_harvesting = false
				_harvest_progress = 0.0
				_harvest_target = null
	elif _is_planting:
		var plant_canceled: bool = input.length_squared() > 0.001
		if plant_canceled or not is_on_floor():
			_is_planting = false
			_plant_progress = 0.0
			_plant_target = null
		else:
			_plant_progress += delta / _c.PLANT_DURATION
			if _plant_progress >= 1.0:
				_complete_plant_action()
				_is_planting = false
				_plant_progress = 0.0
				_plant_target = null
	elif Input.is_action_just_pressed(&"interact") \
			and is_on_floor() \
			and input.length_squared() < 0.001:
		if dispenser_interactable:
			_iso_dispenser.try_interact()
		elif robot_interactable:
			_iso_robot.try_interact()
		elif tube_interactable:
			_iso_tubes.try_interact()
		elif _nearest_plot != null:
			# Snap the body to face the plot the player tried to grab —
			# whether or not we end up actually harvesting it.
			var to_plot: Vector3 = _nearest_plot.world_pos - global_position
			if Vector2(to_plot.x, to_plot.z).length_squared() > 0.001:
				_facing_yaw = atan2(to_plot.x, to_plot.z)
			# Backpack-full guard: don't start the harvest at all if there's
			# no room. Player has to offload at a tube first. The floater is
			# the one bit of feedback so the press doesn't feel ignored.
			if _gs.backpack_count >= _c.BACKPACK_CAPACITY:
				_spawn_backpack_full_floater()
			else:
				_is_harvesting = true
				_harvest_target = _nearest_plot
				_harvest_progress = 0.0
	elif Input.is_action_just_pressed(&"plant") \
			and is_on_floor() \
			and input.length_squared() < 0.001:
		# Only start the plant action if there's an empty plot in range AND
		# the player has at least one of the selected seed in their pouch.
		var seed_key: String = _gs.selected_seed_type
		var has_seed: bool = int(_gs.seed_pouch.get(seed_key, 0)) > 0
		if _nearest_empty_plot != null and has_seed:
			_is_planting = true
			_plant_target = _nearest_empty_plot
			_plant_progress = 0.0
			var to_plot: Vector3 = _plant_target.world_pos - global_position
			if Vector2(to_plot.x, to_plot.z).length_squared() > 0.001:
				_facing_yaw = atan2(to_plot.x, to_plot.z)

	# Committed-charge movement lock: once the player has held jump past the
	# CHARGE_LOCK_THRESHOLD they're winding up for a real spring — freezing
	# horizontal velocity then keeps the body from sliding around in a
	# crouched anticipation pose. Brief grace period preserves run-and-tap
	# jumps (release before the threshold = no lock).
	var committed_charge: bool = _charge_time > CHARGE_MOVE_LOCK_THRESHOLD
	if _is_harvesting or _is_planting or committed_charge:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		var move_speed: float = _c.PLAYER_MOVE_SPEED
		if Input.is_action_pressed(&"sprint"):
			move_speed *= _c.PLAYER_SPRINT_MULTIPLIER
		velocity.x = world_dir.x * move_speed
		velocity.z = world_dir.z * move_speed

	# Charge + jump. Hold Space to accumulate charge; release fires the jump
	# with a velocity scaled between PLAYER_JUMP_VELOCITY (tap) and
	# PLAYER_JUMP_VELOCITY_MAX (full hold). Charge only accumulates on floor.
	var on_floor := is_on_floor()
	var just_landed := on_floor and _was_in_air
	if just_landed:
		_land_squash_t = _c.PLAYER_LAND_SQUASH_DURATION
		# Hand the camera the impact speed so it can dip on a hard landing. Only
		# real drops (above a gentle settle) register; the camera scales + caps it.
		var impact: float = absf(_air_vy)
		if impact > 8.0 and _gs:
			_gs.camera_land_kick = maxf(float(_gs.get("camera_land_kick")), impact)
	_was_in_air = not on_floor
	if _land_squash_t > 0.0:
		_land_squash_t = max(0.0, _land_squash_t - delta)

	if on_floor and not _is_harvesting and not _is_planting and not in_tube_mouth:
		if Input.is_action_pressed(&"jump"):
			_charge_time = min(_charge_time + delta, _c.PLAYER_JUMP_CHARGE_DURATION)
		if Input.is_action_just_released(&"jump"):
			var t: float = _charge_time / _c.PLAYER_JUMP_CHARGE_DURATION
			velocity.y = lerp(_c.PLAYER_JUMP_VELOCITY, _c.PLAYER_JUMP_VELOCITY_MAX, t)
			# Trigger tuck-and-flip if charged past the threshold. Compute the
			# expected airtime now (2v/g for a free-fall hop) so the flip
			# rotation can pace itself across the actual hop and complete
			# exactly TUCK_FLIP_ROTATIONS turns when we land.
			if t >= _c.TUCK_FLIP_CHARGE_THRESHOLD:
				_is_flipping = true
				_flip_airtime_expected = 2.0 * velocity.y / _c.PLAYER_GRAVITY
				_flip_airtime_elapsed = 0.0
			else:
				_is_flipping = false
			_charge_time = 0.0
		elif velocity.y < 0:
			# Settle on the slab rather than letting move_and_slide accumulate
			# downward velocity while resting.
			velocity.y = -1.0
	elif on_floor and (_is_harvesting or _is_planting or in_tube_mouth):
		# Rooted on the slab during a harvest/plant action, OR standing in a
		# corner tube mouth where jump is reserved for the vacuum-lift hop
		# (vacuum_lift.gd handles the jump press). Keep settled, no charge.
		_charge_time = 0.0
		velocity.y = -1.0
	else:
		# Airborne — gravity accumulates, charge is cancelled.
		_charge_time = 0.0
		velocity.y -= _c.PLAYER_GRAVITY * delta

	# Tuck-and-flip rotation while airborne. Drive rotation by elapsed/expected
	# airtime ratio so the rotation finishes exactly when we land — no more
	# overshooting and snapping. Clamp at 1.0 in case the player gets hung up
	# on geometry mid-air. Land-squash on touchdown hides any tiny remainder.
	if _is_flipping and not on_floor:
		_flip_airtime_elapsed += delta
		var progress: float = clamp(_flip_airtime_elapsed / _flip_airtime_expected, 0.0, 1.0)
		_flip_pivot.rotation.x = progress * TAU * _c.TUCK_FLIP_ROTATIONS
	if just_landed:
		_is_flipping = false
		_flip_pivot.rotation.x = 0.0
		_flip_airtime_elapsed = 0.0

	# Remember the airborne vertical speed so the NEXT frame's just_landed can
	# read the impact velocity (move_and_slide zeroes it on contact).
	if not on_floor:
		_air_vy = velocity.y

	# Jumps are unobstructed by ceilings but never land you on the floor above.
	# The tower (tower_controller.gd) gates each floor's slab collision by the
	# player's CURRENT floor — floors above are made non-colliding — so a jump
	# arcs up through where the ceiling is and falls back to the SAME floor.
	# Vertical travel between floors is stairs + elevator, not jumping. The
	# Canopy slab (layer 1) stays solid as the one narrative glass ceiling, so
	# bonking it on Floor 3 still blocks. The player therefore keeps its
	# slab-collision mask (layer 2) on at all times — see set in _ready().
	move_and_slide()

	# Visual facing: smoothly rotate visual root toward movement direction.
	if Vector2(world_dir.x, world_dir.z).length_squared() > 0.01:
		_facing_yaw = atan2(world_dir.x, world_dir.z)
	if _visual:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, _facing_yaw, FACING_TURN_SPEED * delta)

	# Pose blending — drive real joint angles toward whichever named pose
	# matches the current state. The articulated rig (legs / torso / arms /
	# head) gives kneel-with-reach, charge-with-arm-swing-back, tuck-with-
	# knees-up, and landing-with-forward-bend their own shape language so
	# they don't all read as "vertical squash". scale.y stays as a
	# secondary effect for charge crouch + land squash.
	var charge_progress: float = _charge_time / _c.PLAYER_JUMP_CHARGE_DURATION
	var land_progress: float = _land_squash_t / _c.PLAYER_LAND_SQUASH_DURATION
	var target_pose: Dictionary = POSE_IDLE
	var target_scale_y := 1.0
	if _is_harvesting or _is_planting:
		target_pose = POSE_KNEEL
		target_scale_y = _c.HARVEST_KNEEL_SCALE_Y if _is_harvesting else _c.PLANT_KNEEL_SCALE_Y
	elif _is_flipping and not is_on_floor():
		target_pose = POSE_TUCK
	elif land_progress > 0.0:
		target_pose = _blend_pose_dicts(POSE_LAND, POSE_IDLE, 1.0 - land_progress)
		target_scale_y = lerp(1.0, _c.PLAYER_VISUAL_LAND_SCALE, land_progress)
	elif charge_progress > 0.0:
		target_pose = _blend_pose_dicts(POSE_IDLE, POSE_CHARGE, charge_progress)
		target_scale_y = lerp(1.0, _c.PLAYER_VISUAL_CROUCH_SCALE, charge_progress)

	_blend_joint(_legs_pivot, "legs_x", target_pose, delta)
	_blend_joint(_torso_pivot, "torso_x", target_pose, delta)
	_blend_joint(_arms_pivot, "arms_x", target_pose, delta)
	_blend_joint(_head_pivot, "head_x", target_pose, delta)
	_visual.scale.y = lerp(_visual.scale.y, target_scale_y, 18.0 * delta)

	# --- Walk / run cycle (speed-synced, foot-planted) ---
	# Each leg's cycle is split: half "plant" (foot fixed in world, body
	# moves over it), half "swing" (foot arcs forward through air). The
	# cycle_rate is computed from current horizontal speed and stride
	# amplitude so during the plant half the foot's body-relative motion
	# exactly cancels the body's forward velocity — no sliding.
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var locomotion_active: bool = (
		on_floor
		and horizontal_speed > 0.5
		and not _is_harvesting
		and not _is_planting
		and _charge_time <= CHARGE_MOVE_LOCK_THRESHOLD
		and land_progress <= 0.001
	)
	var target_amp: float = 0.0
	var target_lift: float = 0.0
	var target_bob: float = 0.0
	if locomotion_active:
		var sprinting: bool = Input.is_action_pressed(&"sprint")
		if sprinting:
			target_amp = RUN_LIMB_AMPLITUDE
			target_lift = RUN_FOOT_LIFT
			target_bob = RUN_BOB_AMPLITUDE
		else:
			target_amp = WALK_LIMB_AMPLITUDE
			target_lift = WALK_FOOT_LIFT
			target_bob = WALK_BOB_AMPLITUDE
	_locomotion_amp = lerp(_locomotion_amp, target_amp, LOCOMOTION_BLEND_RATE * delta)
	_locomotion_lift = lerp(_locomotion_lift, target_lift, LOCOMOTION_BLEND_RATE * delta)
	_locomotion_bob = lerp(_locomotion_bob, target_bob, LOCOMOTION_BLEND_RATE * delta)
	# amp_z is the foot's max forward / backward Z displacement from hip.
	# cycle_rate set so plant phase covers exactly amp_z * 2 of body travel.
	var amp_z: float = LEG_LENGTH * sin(_locomotion_amp)
	if locomotion_active and amp_z > 0.001:
		var cycle_rate: float = horizontal_speed * PI / (2.0 * amp_z)
		_locomotion_phase = fmod(_locomotion_phase + cycle_rate * delta, TAU)
	# Per-leg foot trajectory. Left and right are π out of phase. By the
	# convention used here phase 0..π is SWING (foot in air) and π..2π is
	# PLANT (foot fixed relative to world).
	_apply_leg_foot(_leg_l_pivot, _locomotion_phase, amp_z, _locomotion_lift)
	_apply_leg_foot(_leg_r_pivot, fmod(_locomotion_phase + PI, TAU), amp_z, _locomotion_lift)
	# Arms — sin-based, counter-phase to legs, smaller amplitude.
	var arm_swing: float = sin(_locomotion_phase) * _locomotion_amp * ARM_SWING_RATIO
	if _arm_l_pivot:
		_arm_l_pivot.rotation.x = -arm_swing
	if _arm_r_pivot:
		_arm_r_pivot.rotation.x = arm_swing
	# Body bob — body SINKS twice per stride (once per foot strike) and
	# rises through neutral when a single leg passes under the hip.
	if _flip_pivot:
		var bob: float = abs(sin(_locomotion_phase)) * _locomotion_bob
		_flip_pivot.position.y = VISUAL_PIVOT_Y - bob

	# Charge gauge visibility + fill update.
	_update_charge_bar(charge_progress)
	# Harvest gauge fills during harvest; reuses the same green bar visual
	# during plant so the player gets identical "I'm doing something" feedback.
	var bar_progress := 0.0
	if _is_harvesting:
		bar_progress = _harvest_progress
	elif _is_planting:
		bar_progress = _plant_progress
	_update_harvest_bar(bar_progress)
	# Prompt: shows the action key + verb for whichever interaction is
	# offered this frame. Priority: dispenser > robot > harvest plot > empty
	# plot (the P verb). Hidden during any locked action or while charging.
	if _prompt_root:
		var seed_key: String = _gs.selected_seed_type
		var has_seed: bool = int(_gs.seed_pouch.get(seed_key, 0)) > 0
		var prompt_action_key := ""
		var prompt_subtext := ""
		if dispenser_interactable:
			prompt_action_key = "E"
			prompt_subtext = dispenser_label
		elif robot_interactable:
			prompt_action_key = "E"
			prompt_subtext = robot_label
		elif tube_interactable:
			prompt_action_key = "E"
			prompt_subtext = tube_label
		elif _nearest_plot != null:
			prompt_action_key = "E"
			prompt_subtext = "Harvest %s" % _nearest_plot.plant_type.name
		elif _nearest_empty_plot != null and _gs.dispenser_first_used:
			# Pre-dispenser, the player doesn't yet know what seeds are or
			# where to get them — surfacing "No X seeds" before they've
			# learned the loop is just confusing. Gate this prompt on the
			# first successful dispense.
			prompt_action_key = "P"
			if has_seed:
				var pouch_count: int = int(_gs.seed_pouch.get(seed_key, 0))
				prompt_subtext = "Plant %s  (× %d)" % [seed_key.capitalize(), pouch_count]
			else:
				prompt_subtext = "No %s seeds" % seed_key.capitalize()
		var should_show: bool = (
			prompt_action_key != ""
			and is_on_floor()
			and not _is_harvesting
			and not _is_planting
			and charge_progress <= 0.001
		)
		_prompt_root.visible = should_show
		if should_show:
			if _e_prompt:
				_e_prompt.text = prompt_action_key
			if _harvest_label:
				_harvest_label.text = prompt_subtext
			# Keep the 3D prompt at roughly constant screen size as the
			# camera zooms — labels were sized for default ortho 40, so
			# in close camera modes (OTS at 5, PROFILE at 8, or any
			# user-zoom) they'd otherwise dominate the frame.
			var ortho_size: float = float(_gs.camera.get("ortho_size", _c.CAMERA_ORTHO_SIZE_DEFAULT))
			var prompt_scale: float = clamp(ortho_size / _c.CAMERA_ORTHO_SIZE_DEFAULT, 0.18, 1.0)
			_prompt_root.scale = Vector3.ONE * prompt_scale

	# Mirror to GameState as the single source of truth.
	_gs.player.iso_pos = global_position
	if input.length_squared() > 0.01:
		_gs.player.facing = _facing_from_input(input)

	# Edge-fall catch — "reappear where you jumped from", but let the fall PLAY.
	# Track the last grounded spot; if the player leaps off an open edge they
	# plunge a real distance — up to the full height of the tower (5 floors) or
	# just past the bottom — and only THEN return to where they jumped from.
	# Falls that reach a floor below first (e.g. dropping through the Canopy's
	# tree-hole apertures down onto the Arboretum slab) land normally and are not
	# caught. Legit vertical travel (tube hop / elevator ride) is exempt.
	var transit: bool = bool(_gs.get("riding_elevator")) or bool(_gs.get("tube_hopping")) if _gs else false
	if is_on_floor() and not transit:
		_last_ground_pos = global_position
	elif not transit:
		var max_drop: float = float(_c.FALL_CATCH_MAX_FLOORS) * float(_c.FLOOR_3D_STORY_HEIGHT)
		var bottom_y: float = -float(_c.FLOOR_3D_STORY_HEIGHT)   # one story below Floor 1
		if global_position.y < _last_ground_pos.y - max_drop or global_position.y < bottom_y:
			global_position = _last_ground_pos + Vector3(0.0, 0.05, 0.0)
			velocity = Vector3.ZERO

	# Deep backstop for true out-of-bounds clipping (should never normally fire).
	if global_position.y < -100.0:
		global_position = _spawn_position
		velocity = Vector3.ZERO

	_update_backpack_visual(delta)


# --- Visual: legs + torso + arms + head + hardhat -----------------------

func _build_visual() -> void:
	# Body parts are parented into joint pivots so poses can rotate real
	# joints. Positions are expressed in each pivot's local frame:
	#   _legs_pivot at hip (HIP_OFFSET_Y from waist origin)
	#   _torso_pivot at waist (origin)
	#   _arms_pivot at shoulder (SHOULDER_OFFSET_Y above waist, inside torso)
	#   _head_pivot at neck base (NECK_OFFSET_Y above waist, inside torso)
	#
	# At idle (all rotations 0) the rendered body matches the previous
	# rigid layout exactly — the refactor only adds rotation centres.
	var jumpsuit := Color(0.85, 0.55, 0.25)
	var skin := Color(0.95, 0.78, 0.65)
	var hat_color := Color(1.0, 0.85, 0.2)
	var leather := Color(0.32, 0.22, 0.14)

	# --- Legs + boots (each in its own per-side pivot at the hip) ---
	# Per-limb pivots already carry the X offset; the leg + boot meshes
	# sit at local x=0 inside their pivot so rotation around the hip is
	# clean. Y positions match the original (pre-refactor) world heights.
	for entry in [[-1, _leg_l_pivot], [1, _leg_r_pivot]]:
		var pivot: Node3D = entry[1]
		var leg := MeshInstance3D.new()
		leg.name = "Leg"
		var leg_mesh := CapsuleMesh.new()
		leg_mesh.radius = 0.11
		leg_mesh.height = 0.6
		leg.mesh = leg_mesh
		leg.material_override = _make_material(jumpsuit)
		leg.position = Vector3(0.0, -0.30, 0.0)
		pivot.add_child(leg)
		var boot := MeshInstance3D.new()
		boot.name = "Boot"
		var boot_mesh := BoxMesh.new()
		boot_mesh.size = Vector3(0.18, 0.08, 0.28)
		boot.mesh = boot_mesh
		boot.material_override = _make_material(leather)
		boot.position = Vector3(0.0, -0.57, 0.04)
		pivot.add_child(boot)

	# --- Belt (direct child of _flip_pivot, stays put when torso bends) ---
	# Original belt world-y = 0.7, flip_pivot-relative = -0.15.
	var belt := MeshInstance3D.new()
	belt.name = "Belt"
	var belt_mesh := BoxMesh.new()
	belt_mesh.size = Vector3(0.54, 0.08, 0.34)
	belt.mesh = belt_mesh
	belt.material_override = _make_material(leather)
	belt.position = Vector3(0, -0.15, 0)
	_flip_pivot.add_child(belt)

	# --- Torso (child of _torso_pivot at waist origin) ---
	# Original torso world-y = 0.95, torso_pivot-relative = 0.10.
	var torso := MeshInstance3D.new()
	torso.name = "Torso"
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.5, 0.55, 0.3)
	torso.mesh = torso_mesh
	torso.material_override = _make_material(jumpsuit)
	torso.position = Vector3(0, 0.10, 0)
	_torso_pivot.add_child(torso)

	# --- Backpack (sits on the back of the torso, scales with fill) ---
	# Authored at unit size; runtime scale interpolates between
	# BACKPACK_EMPTY_SCALE and BACKPACK_FULL_SCALE based on backpack fill ratio.
	# Position is in torso_pivot-local frame: behind the torso (-Z), centred.
	var canvas := Color(0.42, 0.30, 0.20)
	var canvas_dark := Color(0.28, 0.20, 0.13)
	_backpack = MeshInstance3D.new()
	_backpack.name = "Backpack"
	var bp_mesh := BoxMesh.new()
	bp_mesh.size = Vector3(1.0, 1.0, 1.0)
	_backpack.mesh = bp_mesh
	_backpack.material_override = _make_material(canvas)
	_backpack.position = Vector3(0, 0.10, -0.25)
	_backpack.scale = BACKPACK_EMPTY_SCALE
	_torso_pivot.add_child(_backpack)
	# Two thin shoulder straps so the pack reads as a backpack, not a block.
	for sx in [-1, 1]:
		var strap := MeshInstance3D.new()
		strap.name = "BackpackStrap"
		var strap_mesh := BoxMesh.new()
		strap_mesh.size = Vector3(0.05, 0.45, 0.06)
		strap.mesh = strap_mesh
		strap.material_override = _make_material(canvas_dark)
		strap.position = Vector3(0.13 * sx, 0.18, -0.16)
		_torso_pivot.add_child(strap)
		if sx == -1:
			_backpack_strap_l = strap
		else:
			_backpack_strap_r = strap

	# --- Arms + hands (each in its own per-side pivot at the shoulder) ---
	# Same pattern as legs: pivot carries the X offset, mesh sits at
	# local x=0 so a per-arm cycle pivots from the shoulder cleanly.
	for entry in [[-1, _arm_l_pivot], [1, _arm_r_pivot]]:
		var pivot: Node3D = entry[1]
		var arm := MeshInstance3D.new()
		arm.name = "Arm"
		var arm_mesh := CapsuleMesh.new()
		arm_mesh.radius = 0.09
		arm_mesh.height = 0.55
		arm.mesh = arm_mesh
		arm.material_override = _make_material(jumpsuit)
		arm.position = Vector3(0.0, -0.275, 0.0)
		pivot.add_child(arm)
		var hand := MeshInstance3D.new()
		hand.name = "Hand"
		var hand_mesh := BoxMesh.new()
		hand_mesh.size = Vector3(0.12, 0.12, 0.14)
		hand.mesh = hand_mesh
		hand.material_override = _make_material(skin)
		hand.position = Vector3(0.0, -0.605, 0.0)
		pivot.add_child(hand)

	# --- Head + eyes + hat (children of _head_pivot at neck base) ---
	# Original head world-y = 1.40, head_pivot-relative = 0.16.
	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.3, 0.32, 0.3)
	head.mesh = head_mesh
	head.material_override = _make_material(skin)
	head.position = Vector3(0, 0.16, 0)
	_head_pivot.add_child(head)

	for sign_x in [-1, 1]:
		var eye := MeshInstance3D.new()
		eye.name = "Eye"
		var eye_mesh := BoxMesh.new()
		eye_mesh.size = Vector3(0.04, 0.04, 0.02)
		eye.mesh = eye_mesh
		eye.material_override = _make_material(Color(0.1, 0.1, 0.12))
		eye.position = Vector3(0.07 * sign_x, 0.18, 0.16)
		_head_pivot.add_child(eye)

	var brim := MeshInstance3D.new()
	brim.name = "HardhatBrim"
	var brim_mesh := CylinderMesh.new()
	brim_mesh.top_radius = 0.26
	brim_mesh.bottom_radius = 0.26
	brim_mesh.height = 0.04
	brim.mesh = brim_mesh
	brim.material_override = _make_material(hat_color)
	brim.position = Vector3(0, 0.35, 0.04)
	_head_pivot.add_child(brim)

	var hat := MeshInstance3D.new()
	hat.name = "HardhatDome"
	var hat_mesh := SphereMesh.new()
	hat_mesh.radius = 0.2
	hat_mesh.height = 0.28
	hat.mesh = hat_mesh
	hat.material_override = _make_material(hat_color)
	hat.position = Vector3(0, 0.42, 0)
	_head_pivot.add_child(hat)

	var nub := MeshInstance3D.new()
	nub.name = "FacingNub"
	var nub_mesh := BoxMesh.new()
	nub_mesh.size = Vector3(0.08, 0.06, 0.06)
	nub.mesh = nub_mesh
	nub.material_override = _make_material(Color(0.2, 0.2, 0.22))
	nub.position = Vector3(0, 0.35, 0.28)
	_head_pivot.add_child(nub)


func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var col_shape := CapsuleShape3D.new()
	col_shape.radius = 0.3
	col_shape.height = 1.7
	col.shape = col_shape
	col.position = Vector3(0, 0.85, 0)
	add_child(col)

	# Floor/ramp walking config. Defaults leave the body catching on the
	# staircase's base lip (it reads as a wall) — block_on_wall=false lets it
	# mount the ramp, constant_speed keeps pace up the incline, and the
	# generous max_angle + snap keep the 28° staircase firmly "floor".
	floor_block_on_wall = false
	floor_constant_speed = true
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.6
	up_direction = Vector3.UP
	# Collide with regular floor slabs (layer 2) at all times. Jumping up through
	# a ceiling is handled by the tower toggling the floor-above slab's own
	# collision off (not the player's mask), so this stays on permanently.
	set_collision_mask_value(2, true)


# Vertical charge gauge — sits above the head. Parented to self (not _visual)
# so the bar's vertical axis stays world-aligned regardless of body facing.
# Background is a fixed-size dark box; fill is a child node-pair anchored at
# the bottom of the bar so scale.y = charge_progress grows the bar upward.
func _build_charge_bar() -> void:
	_bar_root = Node3D.new()
	_bar_root.name = "ChargeBar"
	_bar_root.position = Vector3(0, 2.55, 0)
	_bar_root.visible = false
	add_child(_bar_root)

	var bar_w := 0.14
	var bar_h := 0.7
	var bar_d := 0.04

	# Background — dark, semi-transparent.
	var bg := MeshInstance3D.new()
	bg.name = "BarBg"
	var bg_mesh := BoxMesh.new()
	bg_mesh.size = Vector3(bar_w, bar_h, bar_d)
	bg.mesh = bg_mesh
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.05, 0.05, 0.07, 0.7)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg.material_override = bg_mat
	_bar_root.add_child(bg)

	# Fill pivot anchored at the BOTTOM of the bar so fill_pivot.scale.y grows
	# the fill mesh upward from the bottom edge.
	_bar_fill_pivot = Node3D.new()
	_bar_fill_pivot.name = "FillPivot"
	_bar_fill_pivot.position = Vector3(0, -bar_h * 0.5, 0.01)
	_bar_fill_pivot.scale.y = 0.0
	_bar_root.add_child(_bar_fill_pivot)

	_bar_fill_mesh = MeshInstance3D.new()
	_bar_fill_mesh.name = "Fill"
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(bar_w * 0.78, bar_h, bar_d * 0.6)
	_bar_fill_mesh.mesh = fill_mesh
	# Mesh's bottom edge sits at the pivot's origin once positioned at +bar_h/2.
	_bar_fill_mesh.position = Vector3(0, bar_h * 0.5, 0)
	var fill_mat := StandardMaterial3D.new()
	fill_mat.albedo_color = Color(0.6, 0.85, 0.5)
	fill_mat.emission_enabled = true
	fill_mat.emission = Color(0.6, 0.85, 0.5)
	fill_mat.emission_energy_multiplier = 1.4
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bar_fill_mesh.material_override = fill_mat
	_bar_fill_pivot.add_child(_bar_fill_mesh)


func _update_charge_bar(progress: float) -> void:
	if _bar_root == null or _bar_fill_pivot == null or _bar_fill_mesh == null:
		return
	if progress <= 0.005:
		_bar_root.visible = false
		_bar_fill_pivot.scale.y = 0.0
		return
	_bar_root.visible = true
	_bar_fill_pivot.scale.y = clamp(progress, 0.0, 1.0)
	# Color ramp green → orange → bright yellow as charge climbs.
	var color: Color
	if progress < 0.5:
		color = lerp(Color(0.55, 0.85, 0.45), Color(1.0, 0.78, 0.25), progress * 2.0)
	else:
		color = lerp(Color(1.0, 0.78, 0.25), Color(1.0, 0.5, 0.15), (progress - 0.5) * 2.0)
	var mat := _bar_fill_mesh.material_override as StandardMaterial3D
	mat.albedo_color = color
	mat.emission = color
	mat.emission_energy_multiplier = lerp(1.2, 2.4, progress)


func set_facing_yaw(yaw: float) -> void:
	_facing_yaw = yaw
	if _visual:
		_visual.rotation.y = yaw


func get_facing_yaw() -> float:
	# Smoothed facing yaw of the player's visual root, in radians. Used by
	# iso_camera.gd to keep PROFILE / OTS framings aligned with the body's
	# direction. Value is 0 when the player faces +Z (south).
	return _facing_yaw


# Linear blend between two pose dicts at parameter t (0 → a, 1 → b). Used
# to ramp into / out of charge + landing poses smoothly, rather than slamming
# from idle to a named pose target.
func _blend_pose_dicts(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var k: float = clamp(t, 0.0, 1.0)
	return {
		"legs_x": lerp(float(a.legs_x), float(b.legs_x), k),
		"torso_x": lerp(float(a.torso_x), float(b.torso_x), k),
		"arms_x": lerp(float(a.arms_x), float(b.arms_x), k),
		"head_x": lerp(float(a.head_x), float(b.head_x), k),
	}


# Step a joint pivot's rotation.x toward the target's matching key by the
# pose blend rate. Pivot may not exist yet on the very first frame after
# tree entry — silently skip in that case.
func _blend_joint(pivot: Node3D, key: String, target_pose: Dictionary, delta: float) -> void:
	if pivot == null:
		return
	var goal: float = float(target_pose.get(key, 0.0))
	pivot.rotation.x = lerp(pivot.rotation.x, goal, POSE_BLEND_RATE * delta)


# Drive a single leg's pivot from a per-leg phase value.
#  phase 0..π   — SWING: foot moves from -amp_z (back) to +amp_z (front)
#                 through the air, with a sine arc lift to clear the ground.
#  phase π..2π  — PLANT: foot held at decreasing body-relative Z so it
#                 cancels the body's forward velocity (foot fixed in world).
# rotation.x is solved from foot_z via inverse-sin since each leg is a
# single rigid capsule pivoting from the hip.
func _apply_leg_foot(pivot: Node3D, leg_phase: float, amp_z: float, lift_amp: float) -> void:
	if pivot == null:
		return
	var foot_z: float
	var foot_lift: float
	if leg_phase < PI:
		# Swing — foot lifts at mid-air, plants at strike.
		var t: float = leg_phase / PI
		foot_z = lerp(-amp_z, amp_z, t)
		foot_lift = sin(t * PI) * lift_amp
	else:
		# Plant — foot relative-to-body marches backward at body speed.
		var t: float = (leg_phase - PI) / PI
		foot_z = lerp(amp_z, -amp_z, t)
		foot_lift = 0.0
	# Foot-z relative to body is -leg_length·sin(rotation.x) (rotation
	# math from _build_visual). Solve for rotation.x:
	var ratio: float = clamp(-foot_z / LEG_LENGTH, -1.0, 1.0)
	pivot.rotation.x = asin(ratio)
	pivot.position.y = foot_lift


func is_holding_pose() -> bool:
	# True while the player is rooted in a deliberate beat (mid-harvest,
	# mid-plant, or charging a jump). The OTS camera reads this to freeze
	# its yaw-chase so the world doesn't rotate around the player during the
	# moment they're standing still to do something.
	return _is_harvesting or _is_planting or _charge_time > 0.0


func _facing_from_input(input: Vector2) -> int:
	# Map input vector to cardinal index 0..3 (N, E, S, W). Used for future
	# anim/sprite selection; not visually meaningful with a placeholder mesh.
	if abs(input.x) > abs(input.y):
		return 1 if input.x > 0 else 3
	return 2 if input.y > 0 else 0


# Called when _plant_progress crosses 1.0. The pouch may have been drained
# between the press and the completion (e.g. the dispenser ran dry and someone
# poked the GameState directly), so re-check before paying the seed.
func _complete_plant_action() -> void:
	if _plant_target == null or _iso_floor == null:
		return
	var seed_key: String = _gs.selected_seed_type
	var pouch: int = int(_gs.seed_pouch.get(seed_key, 0))
	if pouch <= 0:
		return
	if _plant_target.plant_type != null:
		# Race condition fail-safe: someone else planted this plot mid-action.
		return
	var coord: Vector2i = _plant_target.coord
	if _iso_floor.plant(coord, seed_key):
		_gs.seed_pouch[seed_key] = pouch - 1


func _make_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	return m


# Lerps the backpack mesh between empty and full sizes based on the current
# fill ratio. Called every physics frame; the lerp toward target gives a
# subtle swell as the pack loads up rather than a snap.
func _update_backpack_visual(delta: float) -> void:
	if _backpack == null:
		return
	var ratio: float = clampf(float(_gs.backpack_count) / float(_c.BACKPACK_CAPACITY), 0.0, 1.0)
	var target: Vector3 = BACKPACK_EMPTY_SCALE.lerp(BACKPACK_FULL_SCALE, ratio)
	# Critically-damped-ish smoothing — fast enough you can see it react,
	# slow enough that a single pickup doesn't feel like a snap.
	var k: float = 1.0 - exp(-12.0 * delta)
	_backpack.scale = _backpack.scale.lerp(target, k)
	if _backpack_full_floater_cooldown > 0.0:
		_backpack_full_floater_cooldown = max(0.0, _backpack_full_floater_cooldown - delta)


# Red "BACKPACK FULL" floater above the head when E is pressed on a plot
# but the pack is already at capacity. Cooldown gates rapid re-spawns.
func _spawn_backpack_full_floater() -> void:
	if _backpack_full_floater_cooldown > 0.0:
		return
	_backpack_full_floater_cooldown = 1.2
	var label := Label3D.new()
	label.text = "BACKPACK FULL"
	label.font_size = 56
	label.outline_size = 10
	label.modulate = Color(1.0, 0.40, 0.35, 1.0)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 2.4, 0.0)
	add_child(label)
	var start_y: float = label.position.y
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, ^"position:y", start_y + 0.9, 1.1)
	tween.tween_property(label, ^"modulate:a", 0.0, 1.1)
	tween.finished.connect(label.queue_free)


# Tiny "E" key + "Harvest <PlantName>" subtext above the head, shown when a
# harvestable plot is in range. Parent group toggles visibility so both
# labels appear/disappear together.
func _build_e_prompt() -> void:
	_prompt_root = Node3D.new()
	_prompt_root.name = "EPromptGroup"
	_prompt_root.position = Vector3(0, 2.55, 0)
	_prompt_root.visible = false
	add_child(_prompt_root)

	_e_prompt = Label3D.new()
	_e_prompt.name = "EKey"
	_e_prompt.text = "E"
	_e_prompt.font_size = 84
	_e_prompt.outline_size = 12
	_e_prompt.modulate = Color(1, 1, 1, 0.92)
	_e_prompt.outline_modulate = Color(0, 0, 0, 0.9)
	_e_prompt.pixel_size = 0.008
	_e_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_e_prompt.no_depth_test = true
	_e_prompt.position = Vector3(0, 0.66, 0)   # extra headroom so "E" clears the label
	_prompt_root.add_child(_e_prompt)

	_harvest_label = Label3D.new()
	_harvest_label.name = "HarvestLabel"
	_harvest_label.text = "Harvest"
	_harvest_label.font_size = 72
	_harvest_label.outline_size = 12
	_harvest_label.modulate = Color(0.92, 0.99, 0.82, 0.92)
	_harvest_label.outline_modulate = Color(0, 0, 0, 0.9)
	_harvest_label.pixel_size = 0.008
	_harvest_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_harvest_label.no_depth_test = true
	_harvest_label.position = Vector3(0, -0.34, 0)
	_prompt_root.add_child(_harvest_label)


# Horizontal harvest gauge — fills left-to-right over HARVEST_DURATION.
# Same anchored-pivot pattern as the vertical charge bar.
func _build_harvest_bar() -> void:
	_harvest_bar_root = Node3D.new()
	_harvest_bar_root.name = "HarvestBar"
	_harvest_bar_root.position = Vector3(0, 2.4, 0)
	_harvest_bar_root.visible = false
	add_child(_harvest_bar_root)

	var bar_w := 0.85
	var bar_h := 0.1
	var bar_d := 0.04

	var bg := MeshInstance3D.new()
	bg.name = "BarBg"
	var bg_mesh := BoxMesh.new()
	bg_mesh.size = Vector3(bar_w, bar_h, bar_d)
	bg.mesh = bg_mesh
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.05, 0.05, 0.07, 0.7)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg.material_override = bg_mat
	_harvest_bar_root.add_child(bg)

	# Fill pivot anchored at the LEFT of the bar so scale.x grows rightward.
	_harvest_bar_fill_pivot = Node3D.new()
	_harvest_bar_fill_pivot.name = "FillPivot"
	_harvest_bar_fill_pivot.position = Vector3(-bar_w * 0.5, 0, 0.01)
	_harvest_bar_fill_pivot.scale.x = 0.0
	_harvest_bar_root.add_child(_harvest_bar_fill_pivot)

	_harvest_bar_fill_mesh = MeshInstance3D.new()
	_harvest_bar_fill_mesh.name = "Fill"
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(bar_w, bar_h * 0.78, bar_d * 0.6)
	_harvest_bar_fill_mesh.mesh = fill_mesh
	# Mesh's left edge sits at the pivot's origin once positioned at +bar_w/2.
	_harvest_bar_fill_mesh.position = Vector3(bar_w * 0.5, 0, 0)
	var fill_mat := StandardMaterial3D.new()
	var green := Color(0.45, 0.85, 0.45)
	fill_mat.albedo_color = green
	fill_mat.emission_enabled = true
	fill_mat.emission = green
	fill_mat.emission_energy_multiplier = 1.6
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_harvest_bar_fill_mesh.material_override = fill_mat
	_harvest_bar_fill_pivot.add_child(_harvest_bar_fill_mesh)


func _update_harvest_bar(progress: float) -> void:
	if _harvest_bar_root == null:
		return
	if progress <= 0.005:
		_harvest_bar_root.visible = false
		_harvest_bar_fill_pivot.scale.x = 0.0
		return
	_harvest_bar_root.visible = true
	_harvest_bar_fill_pivot.scale.x = clamp(progress, 0.0, 1.0)


# Lets the tower anchor the respawn point after it positions the player at the
# correct stacked-world spawn (the tower owns spawn placement, not the .tscn).
func set_spawn_here() -> void:
	_spawn_position = global_position
	_last_ground_pos = global_position


