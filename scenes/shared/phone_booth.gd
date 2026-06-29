extends Node3D

# The site's PUBLIC CALL TERMINAL — a "public iPad on a stand" the player walks up to
# in the cold open to hire their Partner (opening redesign Chapter 1). Replaces the old
# centered hire card with world-prompt grammar (Principle 2): approach → a glowing [E]
# indicator → press E to open the face-call + permit-signing flow (scenes/garden/
# hire_partner.gd, the "hire_call" HUD). Self-polls the player by distance and listens
# for the `interact` action itself — the same self-contained pattern as the roof crane,
# so it needs no edits to iso_player. No player lock (Principle 1): it's a device you use.
#
# Lifecycle: visible + interactable only during the exterior cold open (GameDirector
# phase EMPTY_LOT/HIRE_PARTNER) and only until a partner is hired; once hired it hides
# (it stands where the tower will later rise).

const INTERACT_RADIUS := 3.2   # m — how close to use the terminal

const STEEL := Color(0.20, 0.22, 0.26)
const DARK := Color(0.10, 0.11, 0.13)
const SCREEN := Color(0.30, 0.78, 0.86)   # the call-screen glow (matches the "on call" palette family)
const RING := Color(0.40, 0.86, 0.58)     # the "interact here" indicator green

@onready var _gs: Node = get_node("/root/GameState")
@onready var _gd: Node = get_node("/root/GameDirector")

var _player: Node3D
var _prompt_root: Node3D
var _prompt_e: Label3D
var _prompt_label: Label3D
var _ring: MeshInstance3D
var _screen_mat: StandardMaterial3D
var _t: float = 0.0


func _ready() -> void:
	_build_kiosk()
	_build_indicator()


func _physics_process(delta: float) -> void:
	_t += delta
	# Active only during the exterior cold open, before a partner is hired.
	var active: bool = int(_gd.current_phase) <= 1 and String(_gs.partner_name) == ""
	visible = active
	if not active:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	# Pulse the ground ring + screen so the terminal reads as "interact with me".
	var pulse: float = 0.5 + 0.5 * sin(_t * 2.4)
	if _ring:
		var s: float = 1.0 + 0.06 * pulse
		_ring.scale = Vector3(s, 1.0, s)
		_ring.transparency = 0.15 + 0.35 * (1.0 - pulse)
	if _screen_mat:
		_screen_mat.emission_energy_multiplier = 0.9 + 0.5 * pulse

	var near: bool = _player_near()
	var ui_open: bool = _hire_ui_open()
	_prompt_root.visible = near and not ui_open
	if near and not ui_open and Input.is_action_just_pressed(&"interact"):
		_open_hire()


func _hire_ui_open() -> bool:
	var ui: Node = get_tree().get_first_node_in_group("hire_call")
	return ui != null and bool(ui.get("visible"))


func _player_near() -> bool:
	var p: Vector3 = _player.global_position
	var c: Vector3 = global_position
	return absf(p.y - c.y) < 4.0 and Vector2(p.x - c.x, p.z - c.z).length() <= INTERACT_RADIUS


func _open_hire() -> void:
	var ui: Node = get_tree().get_first_node_in_group("hire_call")
	if ui and ui.has_method("open"):
		ui.call("open")


# --- Geometry: a pedestal + an angled glowing tablet, flanked by privacy panels -----
func _build_kiosk() -> void:
	# Base pad.
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.55
	base_mesh.bottom_radius = 0.62
	base_mesh.height = 0.16
	base.mesh = base_mesh
	base.material_override = _mat(DARK)
	base.position.y = 0.08
	add_child(base)

	# Post.
	var post := MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.18, 1.25, 0.18)
	post.mesh = post_mesh
	post.material_override = _mat(STEEL)
	post.position.y = 0.78
	add_child(post)

	# Tablet body — a flat slab tilted back, screen toward -Z (the approach side).
	var head := Node3D.new()
	head.position = Vector3(0.0, 1.45, 0.0)
	head.rotation.x = deg_to_rad(-18.0)   # tilt the face up toward the player
	add_child(head)

	var bezel := MeshInstance3D.new()
	var bezel_mesh := BoxMesh.new()
	bezel_mesh.size = Vector3(0.92, 0.66, 0.07)
	bezel.mesh = bezel_mesh
	bezel.material_override = _mat(DARK)
	head.add_child(bezel)

	# Glowing screen face, slightly proud of the bezel on the -Z side.
	var screen := MeshInstance3D.new()
	var screen_mesh := BoxMesh.new()
	screen_mesh.size = Vector3(0.80, 0.54, 0.02)
	screen.mesh = screen_mesh
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.albedo_color = SCREEN
	_screen_mat.emission_enabled = true
	_screen_mat.emission = SCREEN
	_screen_mat.emission_energy_multiplier = 1.1
	screen.material_override = _screen_mat
	screen.position.z = -0.045
	head.add_child(screen)

	# Two thin privacy panels flanking the post (the "booth" read).
	for sx in [-1.0, 1.0]:
		var panel := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.06, 1.6, 0.7)
		panel.mesh = pm
		var glass := _mat(Color(0.16, 0.20, 0.24, 0.55))
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		panel.material_override = glass
		panel.position = Vector3(sx * 0.62, 0.95, 0.0)
		add_child(panel)


# --- The "interact here" indicator: a pulsing ground ring + the [E] billboard prompt --
func _build_indicator() -> void:
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.5
	torus.outer_radius = 1.72
	_ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = RING
	ring_mat.emission_enabled = true
	ring_mat.emission = RING
	ring_mat.emission_energy_multiplier = 1.4
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring.material_override = ring_mat
	_ring.position.y = 0.04   # just above the ground
	add_child(_ring)

	_prompt_root = Node3D.new()
	_prompt_root.position = Vector3(0.0, 2.15, 0.0)
	_prompt_root.visible = false
	add_child(_prompt_root)

	_prompt_e = Label3D.new()
	_prompt_e.text = "E"
	_prompt_e.font_size = 84
	_prompt_e.outline_size = 12
	_prompt_e.modulate = Color(1.0, 0.92, 0.55)
	_prompt_e.outline_modulate = Color(0, 0, 0, 0.92)
	_prompt_e.pixel_size = 0.01
	_prompt_e.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_e.no_depth_test = true
	_prompt_e.position = Vector3(0, 0.5, 0)
	_prompt_root.add_child(_prompt_e)

	_prompt_label = Label3D.new()
	_prompt_label.text = "Hire your partner"
	_prompt_label.font_size = 52
	_prompt_label.outline_size = 8
	_prompt_label.modulate = Color(1.0, 0.96, 0.85)
	_prompt_label.outline_modulate = Color(0, 0, 0, 0.92)
	_prompt_label.pixel_size = 0.01
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.position = Vector3(0, -0.1, 0)
	_prompt_root.add_child(_prompt_label)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m
