extends Node3D

# The Roof — the CONSTRUCTION VISTA, the top of the tower (for now). The build
# hasn't finished up here: a poured concrete slab, exposed steel structure
# (corner columns + a perimeter ring beam where the next floor's walls will go),
# the elevator/spine shaft topping out, and the corner vacuum tubes capping off.
# No glass walls — it's open to the sky, a vista point you reach by tube-hopping
# up the corners. You CAN leap off the open edge; the player's edge-fall catch
# drops you right back where you jumped from.
#
# Built in LOCAL space (slab top at y=0); the tower offsets the node to its
# stacked height like every other floor.

const FloorChrome = preload("res://scenes/shared/floor_chrome.gd")
const VacuumTube = preload("res://scenes/shared/vacuum_tube.gd")
const FloorConstruction = preload("res://scenes/shared/floor_construction.gd")

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

# Set from tower.tscn so the crane can ride the player + read the camera yaw.
@export var player_path: NodePath
@export var camera_pivot_path: NodePath

const CONCRETE := Color(0.46, 0.46, 0.48)
const STEEL := Color(0.38, 0.40, 0.44)
const STEEL_RUST := Color(0.52, 0.38, 0.26)

var _elevator_data: Dictionary = {}

# Per-component structural assembly (open deck: slab → core → risers → tubes; no
# walls/grid). The static steel Vista structure is content, built after.
var _construction: FloorConstruction = null


func _ready() -> void:
	# Concrete deck with the central shaft left open (the elevator/spine shaft
	# tops out here, unfinished). SlabBody name → the tower gates its collision
	# like a normal floor, so a tube-hop arrival lands solid.
	# Structural chrome via the per-component assembly module (open deck — no walls,
	# no grid; corner tubes cap off top-sealed). The shaft is left open at centre.
	_construction = FloorConstruction.new(self, _c, _gs, get_node_or_null("/root/Telemetry"), {
		"floor_color": CONCRETE,
		"shaft_half": float(_c.ELEVATOR_RADIUS) * float(_c.GARDEN_PLOT_SIZE),
		"tubes_top": true,
		"order": ["slab", "core", "risers", "tubes"],
	})
	_construction.build_all_instant()
	_elevator_data = _construction.elevator_data()
	_build_steel_structure()
	# NOTE: the construction crane no longer lives here. Opening redesign Chunk 8 unified the
	# two cranes into ONE climbing apparatus that rides the top of the tower (the build crane +
	# workers + open deck in scenes/shared/construction_pit.gd). The drive-off-the-edge plunge
	# gag went with it (dropped for now — see OR-001 Chunk 8). The roof keeps only its static
	# steel Vista; SEAM for Chunk 10: once the apparatus persists all the way up the stack it
	# arrives here and replaces this static steel as the live worksite.


# Exposed steel: four corner columns rising one story, a perimeter ring beam at
# their tops (the start of the next floor's frame), and low edge curbs — the
# unmistakable "still under construction" read, while leaving the deck open.
func _build_steel_structure() -> void:
	var half: float = float(_c.FLOOR_3D_SIZE) * 0.5
	var col_h: float = 4.2
	var inset: float = 0.6   # columns just inside the deck edge

	var corners := [
		Vector3(-half + inset, 0, -half + inset),
		Vector3(half - inset, 0, -half + inset),
		Vector3(half - inset, 0, half - inset),
		Vector3(-half + inset, 0, half - inset),
	]

	# Corner columns (I-beam-ish box steel).
	for cpos in corners:
		_beam(Vector3(0.28, col_h, 0.28), cpos + Vector3(0, col_h * 0.5, 0), STEEL)
		# A rusty cap plate on top of each column.
		_beam(Vector3(0.46, 0.08, 0.46), cpos + Vector3(0, col_h + 0.04, 0), STEEL_RUST)

	# Perimeter ring beam at the column tops — connects the four columns.
	var ring_y: float = col_h - 0.15
	_beam(Vector3((half - inset) * 2.0, 0.22, 0.22), Vector3(0, ring_y, -half + inset), STEEL)
	_beam(Vector3((half - inset) * 2.0, 0.22, 0.22), Vector3(0, ring_y, half - inset), STEEL)
	_beam(Vector3(0.22, 0.22, (half - inset) * 2.0), Vector3(-half + inset, ring_y, 0), STEEL)
	_beam(Vector3(0.22, 0.22, (half - inset) * 2.0), Vector3(half - inset, ring_y, 0), STEEL)

	# A couple of diagonal cross-braces on two sides for that scaffold look.
	_brace(corners[0] + Vector3(0, 0, 0), corners[1] + Vector3(0, ring_y, 0))
	_brace(corners[2] + Vector3(0, 0, 0), corners[3] + Vector3(0, ring_y, 0))

	# Low edge curbs (poured-concrete kerb) around the open perimeter — a hint of
	# an edge without enclosing the vista. Left with corner gaps (unfinished).
	var curb_h := 0.35
	var curb := Vector3(0.18, curb_h, 0.18)
	for v in [-half + 0.2, half - 0.2]:
		_beam(Vector3((half - 3.0) * 2.0, curb_h, 0.18), Vector3(0, curb_h * 0.5, v), CONCRETE)
		_beam(Vector3(0.18, curb_h, (half - 3.0) * 2.0), Vector3(v, curb_h * 0.5, 0), CONCRETE)

	# One leaning steel girder lying across the deck — building-material clutter.
	var girder := _beam(Vector3(0.3, 0.3, 9.0), Vector3(5.5, 0.7, -3.0), STEEL_RUST)
	girder.rotation = Vector3(0.0, deg_to_rad(28.0), deg_to_rad(6.0))


func _beam(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
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
	add_child(m)
	return m


# A thin diagonal brace between two points (start at a, end at b).
func _brace(a: Vector3, b: Vector3) -> void:
	var mid: Vector3 = (a + b) * 0.5
	var dir: Vector3 = b - a
	var length: float = dir.length()
	if length < 0.01:
		return
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.12, length)
	m.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = STEEL
	mat.metallic = 0.5
	mat.roughness = 0.6
	m.material_override = mat
	m.position = mid
	m.look_at_from_position(mid, b, Vector3.UP)
	add_child(m)
