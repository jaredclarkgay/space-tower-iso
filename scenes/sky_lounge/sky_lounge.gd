extends Node3D

# Floor 5 — SKY LOUNGE (sky-bar observation lounge). Blank for now: the social
# floor near the top, ringed in glass with the sky visible beyond. Built with
# the standard floor chrome so it's solid + wired into the tower (slab + shaft +
# walls + elevator/spine core + lit risers + corner vacuum tubes).
#
# Its defining feature — floor-to-ceiling glass with a visible sky, and a
# "look out the window" camera move when you walk up to the glass — lands in the
# next pass; this is the wired shell it builds on.
#
# Built in LOCAL space (slab top at local y=0); the tower offsets the node up.

const FloorChrome = preload("res://scenes/shared/floor_chrome.gd")
const VacuumTube = preload("res://scenes/shared/vacuum_tube.gd")

@onready var _c: Node = get_node("/root/Constants")
@onready var _gs: Node = get_node("/root/GameState")

const FLOOR_COLOR := Color(0.40, 0.42, 0.47)   # pale, airy lounge floor

var _elevator_data: Dictionary = {}


func _ready() -> void:
	var shaft_half: float = float(_c.ELEVATOR_RADIUS) * float(_c.GARDEN_PLOT_SIZE)
	FloorChrome.build_slab(self, _c, FLOOR_COLOR, shaft_half)
	FloorChrome.build_walls(self, _c)
	FloorChrome.build_extension_grid(self, _c)
	_elevator_data = FloorChrome.build_elevator_core(self, _c)
	FloorChrome.build_passive_spine_pipes(self, _c, _gs, _elevator_data)
	# Corner vacuum tubes — open, tiling up into the Roof's capped segments.
	VacuumTube.build_corner_tubes(self, _c, false)
