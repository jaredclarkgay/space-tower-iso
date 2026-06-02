extends Node

# TimeOfDay — the day/night clock: the CYCLIC-axis broadcaster, sibling to
# GameDirector (the LINEAR narrative axis). It derives a normalized hour from the
# monotonic sim clock, mirrors it into GameState.time_of_day (world truth), and
# BROADCASTS tick(t) for subscribers to interpret LOCALLY. It holds ZERO
# per-location logic — it only announces the hour; floors/characters subscribe
# and decide what dawn/noon/dusk means for them.
#
# Source: GameState.sim_time_msec (shared monotonic clock) wrapped by
# Constants.DAY_LENGTH_MSEC — so sim_speed stays the GLOBAL time-scale. time_of_day
# is 0..1: 0.0/1.0 = midnight, 0.25 = dawn, 0.5 = noon, 0.75 = dusk.
#
# Dormant until the narrative reaches Phase.TEMPORAL: the clock SELF-LATCHES by
# subscribing to GameDirector.phase_changed and flipping its own `running` on when
# it sees TEMPORAL (the director never commands the clock — it only announces the
# phase). The latch is ONE-WAY: once on, it stays on under every later phase.

signal tick(t: float)   # normalized 0..1 time-of-day, emitted each frame while running

var running: bool = false
var _start_offset_msec: float = 0.0   # anchors the first day to CLOCK_START_FRAC

@onready var _gs: Node = get_node("/root/GameState")
@onready var _c: Node = get_node("/root/Constants")


func _ready() -> void:
	var gd: Node = get_node_or_null("/root/GameDirector")
	if gd and gd.has_signal("phase_changed"):
		gd.phase_changed.connect(_on_phase_changed)


func _on_phase_changed(p: int) -> void:
	var gd: Node = get_node_or_null("/root/GameDirector")
	if not running and gd != null and int(p) == int(gd.Phase.TEMPORAL):
		start()


# Latch the clock on (one-way), anchoring the first day to CLOCK_START_FRAC so it
# always switches on at the same hour regardless of how much sim time has elapsed.
func start() -> void:
	if running:
		return
	_start_offset_msec = float(_gs.sim_time_msec) - float(_c.DAY_LENGTH_MSEC) * float(_c.CLOCK_START_FRAC)
	running = true


func _process(_delta: float) -> void:
	if not running:
		return
	var day_len: float = float(_c.DAY_LENGTH_MSEC)
	# (sim - offset) is always >= day_len*CLOCK_START_FRAC >= 0 (sim is monotonic).
	var t: float = fmod(float(_gs.sim_time_msec) - _start_offset_msec, day_len) / day_len
	_gs.time_of_day = t
	tick.emit(t)


# Normalized 0..1 -> 24h "HH:MM" (debug/logging; no location logic).
func hour_string() -> String:
	var hours: float = float(_gs.time_of_day) * 24.0
	var h: int = int(hours)
	var m: int = int((hours - float(h)) * 60.0)
	return "%02d:%02d" % [h, m]
