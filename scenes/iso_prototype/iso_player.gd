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

# Camera the player should be relative to. Set by iso_prototype.tscn.
@export var camera_pivot_path: NodePath
@export var iso_floor_path: NodePath
var _camera_pivot: Node3D
var _iso_floor: Node3D
# Visual root — rotates Y with movement direction. Separate from the
# CharacterBody3D so the collision capsule doesn't spin with the body.
var _visual: Node3D
# Inner pivot at the body's centre of mass (waist) — rotates X for the
# tuck-and-flip when the jump was charged past TUCK_FLIP_CHARGE_THRESHOLD.
# All body parts are children of this so the flip pivots around the waist
# rather than around the feet.
var _flip_pivot: Node3D
const VISUAL_PIVOT_Y := 0.85    # waist height — the flip's rotation centre

var _facing_yaw := 0.0     # smoothed yaw the visual is interpolating toward
const FACING_TURN_SPEED := 14.0   # rad/s — snappy but not jittery

# Jump state (tap = base jump, hold to charge for up to 4× height).
var _charge_time := 0.0
var _land_squash_t := 0.0
var _was_in_air := false
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


func _ready() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_flip_pivot = Node3D.new()
	_flip_pivot.name = "FlipPivot"
	_flip_pivot.position.y = VISUAL_PIVOT_Y
	_visual.add_child(_flip_pivot)
	_build_visual()
	_build_collision()
	_build_charge_bar()
	_build_e_prompt()
	_build_harvest_bar()
	if camera_pivot_path:
		_camera_pivot = get_node(camera_pivot_path)
	if iso_floor_path:
		_iso_floor = get_node(iso_floor_path)


func _physics_process(delta: float) -> void:
	# Horizontal input — camera-relative.
	var input := Vector2(
		Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
		Input.get_action_strength(&"move_down") - Input.get_action_strength(&"move_up"),
	)
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

	# Harvest interaction. Look up the nearest harvestable plot every frame so
	# the E-prompt visibility tracks the player's position. Press-and-hold E
	# starts the harvest; movement, releasing E, or leaving the floor cancels.
	if _iso_floor:
		_nearest_plot = _iso_floor.find_nearest_harvestable_plot_near(
			global_position, _c.HARVEST_RADIUS
		)
	else:
		_nearest_plot = null

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
					_iso_floor.harvest_plot(_harvest_target)
				_gs.food_count += 1
				_is_harvesting = false
				_harvest_progress = 0.0
				_harvest_target = null
	elif Input.is_action_just_pressed(&"interact") \
			and _nearest_plot != null \
			and is_on_floor() \
			and input.length_squared() < 0.001:
		_is_harvesting = true
		_harvest_target = _nearest_plot
		_harvest_progress = 0.0
		# Snap the body to face the plot we're about to harvest.
		var to_plot: Vector3 = _harvest_target.world_pos - global_position
		if Vector2(to_plot.x, to_plot.z).length_squared() > 0.001:
			_facing_yaw = atan2(to_plot.x, to_plot.z)

	if _is_harvesting:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		velocity.x = world_dir.x * _c.PLAYER_MOVE_SPEED
		velocity.z = world_dir.z * _c.PLAYER_MOVE_SPEED

	# Charge + jump. Hold Space to accumulate charge; release fires the jump
	# with a velocity scaled between PLAYER_JUMP_VELOCITY (tap) and
	# PLAYER_JUMP_VELOCITY_MAX (full hold). Charge only accumulates on floor.
	var on_floor := is_on_floor()
	var just_landed := on_floor and _was_in_air
	if just_landed:
		_land_squash_t = _c.PLAYER_LAND_SQUASH_DURATION
	_was_in_air = not on_floor
	if _land_squash_t > 0.0:
		_land_squash_t = max(0.0, _land_squash_t - delta)

	if on_floor and not _is_harvesting:
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
	elif on_floor and _is_harvesting:
		# Rooted on the slab while harvesting — keep settled, no charge.
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

	move_and_slide()

	# Visual facing: smoothly rotate visual root toward movement direction.
	if Vector2(world_dir.x, world_dir.z).length_squared() > 0.01:
		_facing_yaw = atan2(world_dir.x, world_dir.z)
	if _visual:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, _facing_yaw, FACING_TURN_SPEED * delta)

	# Visual squat/squash:
	#   - while harvesting: kneel (deepest crouch). Takes priority.
	#   - while charging: scale.y from 1.0 → CROUCH_SCALE proportional to charge
	#   - on landing: brief squash to LAND_SCALE, recovers in LAND_SQUASH_DURATION
	#   - otherwise: scale.y = 1.0 (neutral standing pose)
	var charge_progress: float = _charge_time / _c.PLAYER_JUMP_CHARGE_DURATION
	var land_progress: float = _land_squash_t / _c.PLAYER_LAND_SQUASH_DURATION
	var target_scale_y := 1.0
	if _is_harvesting:
		target_scale_y = _c.HARVEST_KNEEL_SCALE_Y
	elif charge_progress > 0.0:
		target_scale_y = lerp(1.0, _c.PLAYER_VISUAL_CROUCH_SCALE, charge_progress)
	elif land_progress > 0.0:
		target_scale_y = lerp(1.0, _c.PLAYER_VISUAL_LAND_SCALE, land_progress)
	_visual.scale.y = lerp(_visual.scale.y, target_scale_y, 18.0 * delta)

	# Charge gauge visibility + fill update.
	_update_charge_bar(charge_progress)
	# Harvest gauge fill while harvesting; hidden otherwise.
	_update_harvest_bar(_harvest_progress if _is_harvesting else 0.0)
	# E prompt visible when there's a harvestable plot in range, we're on
	# the ground, not currently harvesting, and not charging a jump.
	if _prompt_root:
		var should_show: bool = (
			_nearest_plot != null
			and is_on_floor()
			and not _is_harvesting
			and charge_progress <= 0.001
		)
		_prompt_root.visible = should_show
		if should_show and _harvest_label:
			_harvest_label.text = "Harvest %s" % _nearest_plot.plant_type.name

	# Mirror to GameState as the single source of truth.
	_gs.player.iso_pos = global_position
	if input.length_squared() > 0.01:
		_gs.player.facing = _facing_from_input(input)

	# Fall fail-safe (F-005). Walls should keep us in, but if we ever escape,
	# snap back to spawn rather than drop forever.
	if global_position.y < _c.PLAYER_FALL_RESPAWN_Y:
		global_position = Vector3(0, 1.0, 0)
		velocity = Vector3.ZERO


# --- Visual: legs + torso + arms + head + hardhat -----------------------

func _build_visual() -> void:
	# All body parts parent to _flip_pivot (which is at y=VISUAL_PIVOT_Y in
	# _visual), so positions here are expressed *relative to the waist* —
	# subtract VISUAL_PIVOT_Y from each Y so world heights stay unchanged.
	var v: Node3D = _flip_pivot
	var jumpsuit := Color(0.85, 0.55, 0.25)   # hardhat-orange
	var skin := Color(0.95, 0.78, 0.65)
	var hat_color := Color(1.0, 0.85, 0.2)
	var leather := Color(0.32, 0.22, 0.14)

	# Legs (two capsules, slightly apart on X).
	for sign_x in [-1, 1]:
		var leg := MeshInstance3D.new()
		leg.name = "Leg"
		var leg_mesh := CapsuleMesh.new()
		leg_mesh.radius = 0.11
		leg_mesh.height = 0.6
		leg.mesh = leg_mesh
		leg.material_override = _make_material(jumpsuit)
		leg.position = Vector3(0.13 * sign_x, 0.32 - VISUAL_PIVOT_Y, 0)
		v.add_child(leg)
		# Boot — small dark box at the foot.
		var boot := MeshInstance3D.new()
		boot.name = "Boot"
		var boot_mesh := BoxMesh.new()
		boot_mesh.size = Vector3(0.18, 0.08, 0.28)
		boot.mesh = boot_mesh
		boot.material_override = _make_material(leather)
		boot.position = Vector3(0.13 * sign_x, 0.05 - VISUAL_PIVOT_Y, 0.04)
		v.add_child(boot)

	# Torso.
	var torso := MeshInstance3D.new()
	torso.name = "Torso"
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.5, 0.55, 0.3)
	torso.mesh = torso_mesh
	torso.material_override = _make_material(jumpsuit)
	torso.position = Vector3(0, 0.95 - VISUAL_PIVOT_Y, 0)
	v.add_child(torso)

	# Tool belt — thin dark band around the waist.
	var belt := MeshInstance3D.new()
	belt.name = "Belt"
	var belt_mesh := BoxMesh.new()
	belt_mesh.size = Vector3(0.54, 0.08, 0.34)
	belt.mesh = belt_mesh
	belt.material_override = _make_material(leather)
	belt.position = Vector3(0, 0.7 - VISUAL_PIVOT_Y, 0)
	v.add_child(belt)

	# Arms (two capsules at the shoulders).
	for sign_x in [-1, 1]:
		var arm := MeshInstance3D.new()
		arm.name = "Arm"
		var arm_mesh := CapsuleMesh.new()
		arm_mesh.radius = 0.09
		arm_mesh.height = 0.55
		arm.mesh = arm_mesh
		arm.material_override = _make_material(jumpsuit)
		arm.position = Vector3(0.32 * sign_x, 0.95 - VISUAL_PIVOT_Y, 0)
		v.add_child(arm)
		# Hand — tiny skin-colored cube.
		var hand := MeshInstance3D.new()
		hand.name = "Hand"
		var hand_mesh := BoxMesh.new()
		hand_mesh.size = Vector3(0.12, 0.12, 0.14)
		hand.mesh = hand_mesh
		hand.material_override = _make_material(skin)
		hand.position = Vector3(0.32 * sign_x, 0.62 - VISUAL_PIVOT_Y, 0)
		v.add_child(hand)

	# Head.
	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.3, 0.32, 0.3)
	head.mesh = head_mesh
	head.material_override = _make_material(skin)
	head.position = Vector3(0, 1.4 - VISUAL_PIVOT_Y, 0)
	v.add_child(head)

	# Eyes — two tiny dark boxes on the front of the head.
	for sign_x in [-1, 1]:
		var eye := MeshInstance3D.new()
		eye.name = "Eye"
		var eye_mesh := BoxMesh.new()
		eye_mesh.size = Vector3(0.04, 0.04, 0.02)
		eye.mesh = eye_mesh
		eye.material_override = _make_material(Color(0.1, 0.1, 0.12))
		eye.position = Vector3(0.07 * sign_x, 1.42 - VISUAL_PIVOT_Y, 0.16)
		v.add_child(eye)

	# Hardhat brim — flat cylinder slightly wider than the head.
	var brim := MeshInstance3D.new()
	brim.name = "HardhatBrim"
	var brim_mesh := CylinderMesh.new()
	brim_mesh.top_radius = 0.26
	brim_mesh.bottom_radius = 0.26
	brim_mesh.height = 0.04
	brim.mesh = brim_mesh
	brim.material_override = _make_material(hat_color)
	brim.position = Vector3(0, 1.59 - VISUAL_PIVOT_Y, 0.04)
	v.add_child(brim)

	# Hardhat dome — slightly squashed sphere on top.
	var hat := MeshInstance3D.new()
	hat.name = "HardhatDome"
	var hat_mesh := SphereMesh.new()
	hat_mesh.radius = 0.2
	hat_mesh.height = 0.28
	hat.mesh = hat_mesh
	hat.material_override = _make_material(hat_color)
	hat.position = Vector3(0, 1.66 - VISUAL_PIVOT_Y, 0)
	v.add_child(hat)

	# Facing-direction nub on the brim front so iso direction stays readable.
	var nub := MeshInstance3D.new()
	nub.name = "FacingNub"
	var nub_mesh := BoxMesh.new()
	nub_mesh.size = Vector3(0.08, 0.06, 0.06)
	nub.mesh = nub_mesh
	nub.material_override = _make_material(Color(0.2, 0.2, 0.22))
	nub.position = Vector3(0, 1.59 - VISUAL_PIVOT_Y, 0.28)
	v.add_child(nub)


func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var col_shape := CapsuleShape3D.new()
	col_shape.radius = 0.3
	col_shape.height = 1.7
	col.shape = col_shape
	col.position = Vector3(0, 0.85, 0)
	add_child(col)


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


func _facing_from_input(input: Vector2) -> int:
	# Map input vector to cardinal index 0..3 (N, E, S, W). Used for future
	# anim/sprite selection; not visually meaningful with a placeholder mesh.
	if abs(input.x) > abs(input.y):
		return 1 if input.x > 0 else 3
	return 2 if input.y > 0 else 0


func _make_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	return m


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
	_e_prompt.font_size = 28
	_e_prompt.outline_size = 4
	_e_prompt.modulate = Color(1, 1, 1, 0.85)
	_e_prompt.outline_modulate = Color(0, 0, 0, 0.85)
	_e_prompt.pixel_size = 0.008
	_e_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_e_prompt.no_depth_test = true
	_e_prompt.position = Vector3(0, 0.32, 0)
	_prompt_root.add_child(_e_prompt)

	_harvest_label = Label3D.new()
	_harvest_label.name = "HarvestLabel"
	_harvest_label.text = "Harvest"
	_harvest_label.font_size = 24
	_harvest_label.outline_size = 4
	_harvest_label.modulate = Color(0.9, 0.98, 0.8, 0.85)
	_harvest_label.outline_modulate = Color(0, 0, 0, 0.85)
	_harvest_label.pixel_size = 0.008
	_harvest_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_harvest_label.no_depth_test = true
	_harvest_label.position = Vector3(0, 0.12, 0)
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
