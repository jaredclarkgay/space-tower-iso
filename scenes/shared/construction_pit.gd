extends Node3D

# The CONSTRUCTION PIT — the cold open's hole in the ground (opening redesign Chapter 0).
# A square excavation at the footprint (x=0) with earthen walls, a gravel floor one story
# down (the Control Center / basement level, world y = -PIT_DEPTH), a south access ramp,
# and the inert central ELEVATOR-COLUMN standing in it — the dormant housing of the
# tower's GX-5 bot, look-but-don't-touch (world-fact: every tower begins as a column sunk
# in the ground). The player roams the rim, walks down the ramp (or drops in), and — in
# Chunk 6 — talks to the workers down here.
#
# Self-gates on the arc: ACTIVE during the free exterior cold open (GameDirector phase
# EMPTY_LOT/HIRE_PARTNER/BUILD_STRUCTURE) and NOT during the legacy dollhouse build or the
# exterior walk. While active it hides the built-tower elevator car (the column stands in
# for it); going inactive restores the car and drops the pit's collision so it can't
# phantom the basement once the real Floor 0 is built there.

const _CRANE := preload("res://scenes/roof/crane.gd")
const _WORKER := preload("res://scenes/shared/worker_npc.gd")

# The three pit workers — each a distinct personality + a shallow [E] dialogue (≤3 deep)
# that nudges the player to the booth/crane. A = the column/transport, B = the ground/
# control, C = the bot (opening redesign Chapter 0). They persist → future residents.
const WORKERS := [
	{
		"name": "RIGGS", "tint": Color(0.86, 0.45, 0.16), "home": Vector3(6.0, 0.0, 3.0),
		"tree": {
			"root": {
				"text": "See this column? That's the spine. Sink it deep, light it up, and it carries every soul in this tower — up. What do you want to know?",
				"choices": [
					{"label": "What's inside it?", "next": "inside"},
					{"label": "It moves people?", "next": "moves"},
					{"label": "Where do I start?", "next": "start"},
				],
			},
			"inside": {"text": "A GX-5. Standard issue — every tower gets a bot tucked in its spine. You'll meet yours once it's powered. Bit of a moment, that.", "choices": [{"label": "Back", "next": "root"}]},
			"moves": {"text": "Becomes the elevator, eventually. For now it just stands there looking important. Like the rest of us.", "choices": [{"label": "Back", "next": "root"}]},
			"start": {"text": "Sign the permit first — booth's right up on the rim. Then climb in the crane and we break ground.", "choices": []},
		},
	},
	{
		"name": "DELL", "tint": Color(0.20, 0.46, 0.78), "home": Vector3(-3.0, 0.0, -2.0),
		"tree": {
			"root": {
				"text": "This patch of dirt? Don't let it fool you. It becomes your Control Center — the whole tower runs from down here.",
				"choices": [
					{"label": "Control Center?", "next": "cc"},
					{"label": "Why dig so deep?", "next": "deep"},
					{"label": "What should I do?", "next": "do"},
				],
			},
			"cc": {"text": "Power, water, air, data, waste, cargo — all six route through this floor. Light it up first or nothing upstairs works.", "choices": [{"label": "Back", "next": "root"}]},
			"deep": {"text": "Foundation's got to hold a hundred floors someday. You don't skimp on the bottom.", "choices": [{"label": "Back", "next": "root"}]},
			"do": {"text": "Sign on with your partner at the booth. Then take the crane and we'll raise the first floor.", "choices": []},
		},
	},
	{
		"name": "TEO", "tint": Color(0.24, 0.62, 0.34), "home": Vector3(-5.0, 0.0, 4.0),
		"tree": {
			"root": {
				"text": "First build, right? I can tell. You're about to meet the tower's bot — a GX-5. First time's always something.",
				"choices": [
					{"label": "How can you tell?", "next": "tell"},
					{"label": "When do I meet it?", "next": "when"},
					{"label": "Anything I should do?", "next": "do"},
				],
			},
			"tell": {"text": "You keep eyeing the column like it might bite. It won't. Probably.", "choices": [{"label": "Back", "next": "root"}]},
			"when": {"text": "Once the Control Center's powered, it wakes up and rises out of the spine. Big moment. Don't blink.", "choices": [{"label": "Back", "next": "root"}]},
			"do": {"text": "Sign the permit at the booth, then get that crane working. We'll handle the rest.", "choices": []},
		},
	},
]

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")
@onready var _gd: Node = get_node("/root/GameDirector")

var _body: StaticBody3D
var _seam: MeshInstance3D
var _seam_mat: StandardMaterial3D
var _elevator: Node3D
var _site_ground: Node
var _apron: Node3D
var _crane: Node3D
var _crane_setup: bool = false
var _workers: Array = []
var _shell_vis: Array = []     # earthen floor/walls/ramp + column meshes — hidden once Floor 0 is built
var _active: bool = false
var _t: float = 0.0

# --- The climbing WORKSITE (opening redesign Chunk 8 / Principle 6) ------------------
# The crane + the three workers + an open steel construction deck are ONE apparatus that
# RIDES THE TOP OF THE TOWER: it starts on the pit floor (building the Control Center
# foundation) and relocates onto the edges of each newly-built floor, so the top of the
# tower is always a live, see-through worksite that climbs as the building grows. The
# earthen pit shell, column, and apron do NOT climb — they're the cold-open hole and hide
# once Floor 0 is poured. _worksite is the node everything that climbs hangs off; moving its
# Y is the whole relocation.
var _worksite: Node3D
var _worksite_deck: Node3D     # open steel frame (the unfinished-top read); shown once the climb begins
var _relocated_level: int = -999
var _climb_tween: Tween


func _ready() -> void:
	_build_apron()
	_build_pit()
	_build_column()
	_build_worksite()
	_set_active(_compute_active())


func _process(delta: float) -> void:
	_t += delta
	var a: bool = _compute_active()
	if a != _active:
		_set_active(a)
	_apply_world_swaps()   # idempotent; resolves the car + site ground if they grouped after our _ready
	# Once Floor 0 (the Control Center) is built, its slab replaces the earthen pit: hide the
	# dirt shell + column and drop the pit's footing (the slab takes over). The apron stays;
	# the WORKSITE (crane + workers + steel deck) climbs onto the built floors above.
	var built_over: bool = int(_gs.built_level) >= 0
	for m in _shell_vis:
		if is_instance_valid(m):
			m.visible = _active and not built_over
	if _body:
		_body.collision_layer = 2 if (_active and not built_over) else 0
	if _active and not built_over and _seam_mat:
		_seam_mat.emission_energy_multiplier = 0.7 + 0.5 * (0.5 + 0.5 * sin(_t * 1.8))
	# Drive the worksite's height off built_level every frame (invariant: cross-floor state is
	# LIVE, not baked) so it climbs no matter which path raised the floor (crane build or a
	# harness/dev jump). Hold position WHILE a floor is mid-assembly — the apparatus builds the
	# new floor from the one below, then climbs onto it once it tops out. The open steel deck
	# appears once the first floor is poured.
	var bl: int = int(_gs.built_level)
	var tc: Node = get_tree().get_first_node_in_group("tower_controller")
	var mid_build: bool = tc != null and tc.has_method("is_crane_building") and bool(tc.call("is_crane_building"))
	if bl != _relocated_level and not mid_build:
		_relocated_level = bl
		if bl >= 0:
			relocate_to_level(bl)
	if _worksite_deck:
		_worksite_deck.visible = _active and built_over


func _compute_active() -> bool:
	var phase: int = int(_gd.current_phase)
	return phase <= 2 and not bool(_gs.get("constructing")) and not bool(_gs.get("exterior_walk"))


func _set_active(a: bool) -> void:
	_active = a
	visible = a
	if _body:
		_body.collision_layer = 2 if a else 0   # layer 2 = the ground/world layer the player masks
	_apply_world_swaps()


# Apply the cold-open world swaps for the current _active state. Idempotent — called every
# frame so it's robust to nodes that registered their groups AFTER our _ready (the elevator
# + site ground both join their groups in their own _ready, which may run after ours).
func _apply_world_swaps() -> void:
	if _elevator == null or not is_instance_valid(_elevator):
		_elevator = get_tree().get_first_node_in_group("elevator")
	if _elevator:
		_elevator.visible = not _active   # the column stands in for the car during the cold open
	if _site_ground == null or not is_instance_valid(_site_ground):
		_site_ground = get_tree().get_first_node_in_group("site_ground")
	if _site_ground and _site_ground.has_method("set_plane_visible"):
		_site_ground.call("set_plane_visible", not _active)   # reveal the excavation through our apron
	# Wire the pit crane to the player + camera once they exist, and gate it to the cold open.
	if _crane:
		if not _crane_setup:
			var pl: Node = get_tree().get_first_node_in_group("player")
			var pivot: Node = get_parent().get_node_or_null("CameraPivot") if get_parent() else null
			if pl:
				_crane.call("setup", pl, pivot, null)
				_crane_setup = true
		_crane.set("enabled", _active)
	for w in _workers:
		if is_instance_valid(w):
			w.set("enabled", _active)


# --- The climbing worksite: crane + workers + open steel deck, all parented under one node
# whose Y is the apparatus's height. It starts on the pit floor (y = -PIT_DEPTH, where the
# Control Center pours) and relocate_to_level() rides it onto each built floor. Everything
# under _worksite uses LOCAL coords (deck surface at local y=0).
func _build_worksite() -> void:
	_worksite = Node3D.new()
	_worksite.name = "Worksite"
	_worksite.position.y = -float(_c.PIT_DEPTH)   # on the pit floor for the cold-open build
	add_child(_worksite)
	_build_crane()
	_build_workers()
	_build_worksite_deck()


# Reuses the drivable crane in BUILD MODE (stationary build station, no plunge). The cab IS
# the build verb (Chunk 7); the player rides it up as the worksite climbs (Chunk 8).
func _build_crane() -> void:
	_crane = _CRANE.new()
	_crane.set("build_mode", true)
	_crane.set("idle_label", "Operate crane")
	_worksite.add_child(_crane)
	# Off to one side of the deck, clear of the central shaft/column.
	_crane.position = Vector3(-8.0, 0.0, -4.0)


# --- The three workers (personalities + wander AI + [E] dialogue) — they ride the deck up.
func _build_workers() -> void:
	var crane_spot := Vector3(-8.0, 0.0, -4.0)
	for i in WORKERS.size():
		var def: Dictionary = WORKERS[i]
		var w: Node3D = _WORKER.new()
		var home: Vector3 = def.home
		home.y = 0.0   # stand on the deck surface (local)
		w.call("configure", String(def.name), def.tint, def.tree, home, crane_spot, i)
		_worksite.add_child(w)
		_workers.append(w)


# --- The open steel construction deck — the unmistakable "still being built / see-through
# top" read that rides the worksite: four corner columns rising a story, a perimeter ring
# beam (the next floor's frame), low edge curbs, and a leaning girder of clutter. Open at the
# centre (the shaft) and the top (no ceiling) so the player watches the next floor assemble.
# Hidden until the first floor is poured (the cold-open pit stays uncluttered).
func _build_worksite_deck() -> void:
	_worksite_deck = Node3D.new()
	_worksite_deck.name = "WorksiteDeck"
	_worksite_deck.visible = false
	_worksite.add_child(_worksite_deck)

	var half: float = float(_c.FLOOR_3D_SIZE) * 0.5
	var col_h: float = 4.2
	var inset: float = 0.6
	var steel := Color(0.38, 0.40, 0.44)
	var rust := Color(0.52, 0.38, 0.26)
	var concrete := Color(0.46, 0.46, 0.48)
	var corners := [
		Vector3(-half + inset, 0, -half + inset), Vector3(half - inset, 0, -half + inset),
		Vector3(half - inset, 0, half - inset), Vector3(-half + inset, 0, half - inset),
	]
	for cpos in corners:
		_deck_box(Vector3(0.28, col_h, 0.28), cpos + Vector3(0, col_h * 0.5, 0), steel)
		_deck_box(Vector3(0.46, 0.08, 0.46), cpos + Vector3(0, col_h + 0.04, 0), rust)
	var ring_y: float = col_h - 0.15
	_deck_box(Vector3((half - inset) * 2.0, 0.22, 0.22), Vector3(0, ring_y, -half + inset), steel)
	_deck_box(Vector3((half - inset) * 2.0, 0.22, 0.22), Vector3(0, ring_y, half - inset), steel)
	_deck_box(Vector3(0.22, 0.22, (half - inset) * 2.0), Vector3(-half + inset, ring_y, 0), steel)
	_deck_box(Vector3(0.22, 0.22, (half - inset) * 2.0), Vector3(half - inset, ring_y, 0), steel)
	# Low edge curbs (corner gaps left open — unfinished).
	var curb_h := 0.35
	for v in [-half + 0.2, half - 0.2]:
		_deck_box(Vector3((half - 3.0) * 2.0, curb_h, 0.18), Vector3(0, curb_h * 0.5, v), concrete)
		_deck_box(Vector3(0.18, curb_h, (half - 3.0) * 2.0), Vector3(v, curb_h * 0.5, 0), concrete)
	# A leaning girder lying across the deck — building-material clutter.
	var girder := _deck_box(Vector3(0.3, 0.3, 9.0), Vector3(5.5, 0.7, -3.0), rust)
	girder.rotation = Vector3(0.0, deg_to_rad(28.0), deg_to_rad(6.0))


func _deck_box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.5
	mat.roughness = 0.55
	m.material_override = mat
	m.position = pos
	_worksite_deck.add_child(m)
	return m


# Ride the apparatus onto the edges of `level` — the top surface of the floor just built, so
# the next floor assembles in open air above it (Principle 6). World-Y derived from the tower
# (never hardcoded — invariant #1). Eased so the climb plays as a visible beat; the player,
# if still in the cab, rides up with it.
func relocate_to_level(level: int) -> void:
	if _worksite == null:
		return
	var tc: Node = get_tree().get_first_node_in_group("tower_controller")
	var top_y: float = -float(_c.PIT_DEPTH)
	if tc and tc.has_method("floor_top_y"):
		top_y = float(tc.call("floor_top_y", level))
	if _worksite_deck:
		_worksite_deck.visible = true
	if _climb_tween and _climb_tween.is_valid():
		_climb_tween.kill()
	_climb_tween = create_tween()
	_climb_tween.tween_property(_worksite, "position:y", top_y, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


# --- Ground apron: the cold-open ground at y=0, framed with a footprint-sized hole so
# the excavation is visible (the solid site-ground plane is hidden while we're active).
func _build_apron() -> void:
	_apron = Node3D.new()
	_apron.name = "Apron"
	add_child(_apron)
	var site_half: float = float(_c.SITE_GROUND_SIZE) * 0.5
	var hole: float = float(_c.FLOOR_3D_SIZE) * 0.5
	var strip_w: float = site_half - hole
	if strip_w <= 0.01:
		return
	var mid: float = (hole + site_half) * 0.5
	var mat := _mat(_c.SITE_GROUND_COLOR)
	_add_apron_strip(Vector2(strip_w, 2.0 * site_half), Vector3(mid, 0.0, 0.0), mat)
	_add_apron_strip(Vector2(strip_w, 2.0 * site_half), Vector3(-mid, 0.0, 0.0), mat)
	_add_apron_strip(Vector2(2.0 * hole, strip_w), Vector3(0.0, 0.0, mid), mat)
	_add_apron_strip(Vector2(2.0 * hole, strip_w), Vector3(0.0, 0.0, -mid), mat)


func _add_apron_strip(size2: Vector2, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size2
	mi.mesh = pm
	mi.material_override = mat
	mi.position = pos
	_apron.add_child(mi)


# --- Pit shell: gravel floor + three earthen walls + a south access ramp -----------
func _build_pit() -> void:
	var depth: float = float(_c.PIT_DEPTH)
	var half: float = float(_c.FLOOR_3D_SIZE) * 0.5   # opening = the footprint
	var wall_mat := _mat(_c.PIT_WALL_COLOR)
	var floor_mat := _mat(_c.PIT_FLOOR_COLOR)

	_body = StaticBody3D.new()
	_body.name = "PitBody"
	_body.collision_layer = 2
	_body.collision_mask = 0
	add_child(_body)

	# Floor (top face at y = -depth).
	_shell_vis.append(_add_box_visual(Vector3(2.0 * half, 0.4, 2.0 * half), Vector3(0.0, -depth - 0.2, 0.0), floor_mat))
	_add_box_coll(Vector3(2.0 * half, 0.4, 2.0 * half), Vector3(0.0, -depth - 0.2, 0.0))

	# Earthen walls — North (+Z), East (+X), West (-X). South is the ramp. The walls sit
	# just INSIDE the footprint (outer face flush with the rim at ±half) so their top faces
	# don't lie coplanar with the ground apron at y=0 — that overlap was the z-fighting flicker.
	var t: float = 0.6
	var wall_y: float = -depth * 0.5
	_shell_vis.append(_add_box_visual(Vector3(2.0 * half + t, depth, t), Vector3(0.0, wall_y, half - t * 0.5), wall_mat))
	_add_box_coll(Vector3(2.0 * half + t, depth, t), Vector3(0.0, wall_y, half - t * 0.5))
	_shell_vis.append(_add_box_visual(Vector3(t, depth, 2.0 * half + t), Vector3(half - t * 0.5, wall_y, 0.0), wall_mat))
	_add_box_coll(Vector3(t, depth, 2.0 * half + t), Vector3(half - t * 0.5, wall_y, 0.0))
	_shell_vis.append(_add_box_visual(Vector3(t, depth, 2.0 * half + t), Vector3(-half + t * 0.5, wall_y, 0.0), wall_mat))
	_add_box_coll(Vector3(t, depth, 2.0 * half + t), Vector3(-half + t * 0.5, wall_y, 0.0))

	# South access ramp: a thin gravel ramp whose TOP SURFACE lands exactly on the slope from
	# the rim (z=-half, y=0) down to the floor (z=-half+run, y=-depth) — flush with the apron,
	# no lip. Built so the box's top face (not its centre) sits on that line, and extended a
	# little past the floor end so the bottom merges into the slab.
	var run: float = float(_c.PIT_RAMP_RUN)
	var L: float = sqrt(run * run + depth * depth)
	var angle: float = atan2(depth, run)
	var ramp_t: float = 0.3
	var dir_norm := Vector3(0.0, -depth, run) / L          # down-slope, from rim to floor
	var normal := Vector3(0.0, run, depth) / L             # surface up-normal
	var top := Vector3(0.0, 0.0, -half)                    # the flush-with-apron rim point
	var length: float = L + 1.5                            # overrun into the floor, no gap
	var ramp_center := top + dir_norm * (length * 0.5) - normal * (ramp_t * 0.5)
	var ramp_mat := _mat(_c.PIT_RAMP_COLOR)
	var ramp_vis := _add_box_visual(Vector3(2.0 * half, ramp_t, length), ramp_center, ramp_mat)
	ramp_vis.rotation.x = angle
	_shell_vis.append(ramp_vis)
	var ramp_shape := CollisionShape3D.new()
	var rb := BoxShape3D.new()
	rb.size = Vector3(2.0 * half, ramp_t, length)
	ramp_shape.shape = rb
	ramp_shape.position = ramp_center
	ramp_shape.rotation.x = angle
	_body.add_child(ramp_shape)


# --- The dormant elevator-column standing at the shaft centre ----------------------
func _build_column() -> void:
	var depth: float = float(_c.PIT_DEPTH)
	var rise: float = float(_c.PIT_COLUMN_RISE)
	var r: float = float(_c.PIT_COLUMN_RADIUS)
	var h: float = depth + rise
	var cy: float = -depth + h * 0.5

	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = h
	shaft.mesh = cyl
	shaft.material_override = _mat(_c.PIT_COLUMN_COLOR)
	shaft.position.y = cy
	add_child(shaft)
	_shell_vis.append(shaft)

	# Top cap (slightly wider).
	var cap := MeshInstance3D.new()
	var capm := CylinderMesh.new()
	capm.top_radius = r * 1.12
	capm.bottom_radius = r * 1.12
	capm.height = 0.4
	cap.mesh = capm
	cap.material_override = _mat(Color(0.12, 0.13, 0.16))
	cap.position.y = -depth + h + 0.1
	add_child(cap)
	_shell_vis.append(cap)

	# Glow seam on the -Z face (toward the approaching player) — the dormant GX-5 inside.
	_seam = MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.28, h * 0.78, 0.12)
	_seam.mesh = sb
	_seam_mat = StandardMaterial3D.new()
	_seam_mat.albedo_color = _c.PIT_COLUMN_GLOW
	_seam_mat.emission_enabled = true
	_seam_mat.emission = _c.PIT_COLUMN_GLOW
	_seam_mat.emission_energy_multiplier = 1.0
	_seam.mesh.material = _seam_mat
	_seam.position = Vector3(0.0, cy, -(r + 0.02))
	add_child(_seam)
	_shell_vis.append(_seam)

	# Column collision: a SHORT cylinder covering only the base (floor up ~3.5 m), set a
	# touch inside the visual radius. Just enough to stop you walking through the spine —
	# but low + slim so jumping next to it can't wedge the player against the upper shaft.
	var cs := CollisionShape3D.new()
	var cshape := CylinderShape3D.new()
	cshape.radius = r - 0.25
	cshape.height = 3.5
	cs.shape = cshape
	cs.position.y = -depth + 1.75
	_body.add_child(cs)


func _add_box_visual(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _add_box_coll(size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	_body.add_child(cs)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m
