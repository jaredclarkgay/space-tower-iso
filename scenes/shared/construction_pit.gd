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
var _shell_vis: Array = []     # earthen floor/ramp + column meshes — hidden once Floor 0 is built (CC slab takes over)
# The earthen EXCAVATION WALLS (the sides of the hole the tower rises out of). Unlike the rest
# of the shell, these PERSIST as the dirt you see through the Control Center's glass — until a
# floor is built ON TOP of the CC (built_level >= GROUND_LEVEL) and caps the excavation. So the
# CC reads as an open daylit hole, not a dark sealed basement, while it's the topmost floor.
var _excavation_vis: Array = []
var _south_fill: MeshInstance3D     # dirt liner for the south side, shown once the ramp is gone (CC poured)
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
	_build_earth_surround()
	_build_pit()
	_build_column()
	_build_worksite()
	_set_active(_compute_active())


# A solid EARTH mass filling everything below grade EXCEPT the excavation cavity (the footprint
# from grade down to the pit floor, where the Control Center sits). Without it you see the sky
# background straight THROUGH the ground below/around the below-grade CC (it's a hole in the
# earth). Permanent + always visible — the tower is sunk into real ground; the cavity stays
# open so you can be down in the CC. Visual only (no collision — the pit body / CC handle that).
func _build_earth_surround() -> void:
	var earth := Node3D.new()
	earth.name = "EarthSurround"
	add_child(earth)
	var half: float = float(_c.FLOOR_3D_SIZE) * 0.5   # footprint half (the excavation opening)
	var depth: float = float(_c.PIT_DEPTH)
	var reach: float = 90.0                            # extends well past the camera view
	var mat := _mat(_c.PIT_WALL_COLOR.darkened(0.25))  # underground reads a touch darker
	# Floor of the earth: one big slab UNDER the whole site, its top flush with the pit floor —
	# fills everything below the excavation so you never see sky straight down.
	_add_earth_box(earth, Vector3(2.0 * reach, 40.0, 2.0 * reach), Vector3(0.0, -depth - 20.0, 0.0), mat)
	# Perimeter earth: a frame from grade down to the pit floor, OUTSIDE the footprint, so the
	# strip of ground just beside the open excavation is dirt, not sky.
	var strip: float = reach - half
	if strip > 0.01:
		var mid: float = (half + reach) * 0.5
		var wall_y: float = -depth * 0.5
		_add_earth_box(earth, Vector3(2.0 * reach, depth, strip), Vector3(0.0, wall_y, mid), mat)
		_add_earth_box(earth, Vector3(2.0 * reach, depth, strip), Vector3(0.0, wall_y, -mid), mat)
		_add_earth_box(earth, Vector3(strip, depth, 2.0 * half), Vector3(mid, wall_y, 0.0), mat)
		_add_earth_box(earth, Vector3(strip, depth, 2.0 * half), Vector3(-mid, wall_y, 0.0), mat)


func _add_earth_box(parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


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
	var exposed: bool = _excavation_exposed()
	visible = true   # node stays renderable for the permanent EarthSurround; sub-parts gate below
	for m in _shell_vis:
		if is_instance_valid(m):
			m.visible = _active and not built_over
	# The excavation dirt walls persist (through the CC glass) until the CC is capped — shown
	# whenever the CC is the topmost floor, independent of the cold-open worksite being active.
	for m in _excavation_vis:
		if is_instance_valid(m):
			m.visible = exposed
	# South dirt fills in once the ramp is gone (CC poured) and the excavation is still exposed.
	if _south_fill:
		_south_fill.visible = exposed and built_over
	# The grade apron rims the open excavation while it's exposed; the worksite (crane + workers
	# + deck) belongs to the cold open only — it hides once you're inside.
	if _apron:
		_apron.visible = _active or exposed
	if _worksite:
		_worksite.visible = _active
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


# True while the Control Center is still the topmost floor — i.e. no floor has been built ON
# TOP of it yet. The excavation dirt (and the open-sky/daylit read) survive until the Garden
# caps it (built_level >= GROUND_LEVEL).
func _excavation_exposed() -> bool:
	return int(_gs.built_level) < int(_c.GROUND_LEVEL)


# Toggle every CollisionShape3D under a node (recursive). Used to drop the hidden elevator car's
# collision during the cold open so it isn't a phantom floor over the shaft.
func _set_node_collision_disabled(node: Node, disabled: bool) -> void:
	if node is CollisionShape3D and node.disabled != disabled:
		node.disabled = disabled
	for child in node.get_children():
		_set_node_collision_disabled(child, disabled)


func _set_active(a: bool) -> void:
	_active = a
	# The node stays renderable (the permanent EarthSurround lives under it); per-part visibility
	# is driven in _process.
	visible = true
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
		# During the arrival cinematic the controller's emergence owns the elevator (it hides the
		# real car so the animated spine can rise in its place), so don't fight it here.
		if not bool(_gs.get("arrival_cinematic")):
			_elevator.visible = not _active   # the column stands in for the car during the cold open
			# ...and its collision is OFF while hidden, or the car platform is a phantom floor at
			# grade over the shaft that you bonk jumping into the pit (the pit column stands in).
			_set_node_collision_disabled(_elevator, _active)
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
	# These three earthen walls are the EXCAVATION liner: they persist as the dirt seen through
	# the CC glass until a floor caps the CC (see _excavation_vis). Collision stays with the pit
	# body only while the cold open owns the ground (gated in _process); the CC's own walls take
	# over once you're inside.
	#
	# RIM IS OPEN to jump/drop in (Chapter 0 — "jump into the pit"): the COLLISION tops stop
	# RIM_OPEN below grade so a hop over the edge clears the lip and drops you in, instead of
	# landing on a grade-flush ledge. The VISUAL walls stay full height (the dirt looks right);
	# the shorter collider still contains you against the dirt at the pit floor.
	var rim_open: float = 2.0
	var coll_h: float = depth - rim_open                 # collider top sits rim_open below grade
	var coll_y: float = wall_y - rim_open * 0.5
	_excavation_vis.append(_add_box_visual(Vector3(2.0 * half + t, depth, t), Vector3(0.0, wall_y, half - t * 0.5), wall_mat))
	_add_box_coll(Vector3(2.0 * half + t, coll_h, t), Vector3(0.0, coll_y, half - t * 0.5))
	_excavation_vis.append(_add_box_visual(Vector3(t, depth, 2.0 * half + t), Vector3(half - t * 0.5, wall_y, 0.0), wall_mat))
	_add_box_coll(Vector3(t, coll_h, 2.0 * half + t), Vector3(half - t * 0.5, coll_y, 0.0))
	_excavation_vis.append(_add_box_visual(Vector3(t, depth, 2.0 * half + t), Vector3(-half + t * 0.5, wall_y, 0.0), wall_mat))
	_add_box_coll(Vector3(t, coll_h, 2.0 * half + t), Vector3(-half + t * 0.5, coll_y, 0.0))
	# South (-Z) is the access RAMP during the cold open, so it has no dirt wall then. Once the
	# CC is poured (built_over) the ramp's gone and you're inside — fill the south with dirt too
	# so the excavation reads complete on all four sides through the glass. Visual only (the CC's
	# own south wall handles collision). Gated in _process.
	_south_fill = _add_box_visual(Vector3(2.0 * half + t, depth, t), Vector3(0.0, wall_y, -half + t * 0.5), wall_mat)
	_south_fill.visible = false

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

	# Column collision: a SOLID full-height cylinder matching the visual shaft, so the stub is a
	# real structure in the player's space — you can't walk through it AND you can jump up onto
	# its cap (top at cy + h/2 ≈ the rise above grade). Radius a hair inside the visual so the
	# mesh always covers the collider.
	var cs := CollisionShape3D.new()
	var cshape := CylinderShape3D.new()
	cshape.radius = r - 0.05
	cshape.height = h
	cs.shape = cshape
	cs.position.y = cy
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
