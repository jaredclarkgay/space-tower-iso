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
# Stage 2 will gate `running` behind the TEMPORAL latch (default it false + flip on
# via start() when the director enters Phase.TEMPORAL). For now it free-runs so the
# ticking value is testable.

signal tick(t: float)   # normalized 0..1 time-of-day, emitted each frame while running

var running: bool = true

@onready var _gs: Node = get_node("/root/GameState")
@onready var _c: Node = get_node("/root/Constants")


func _process(_delta: float) -> void:
	if not running:
		return
	var day_len: float = float(_c.DAY_LENGTH_MSEC)
	var t: float = fmod(float(_gs.sim_time_msec), day_len) / day_len
	_gs.time_of_day = t
	tick.emit(t)


# Normalized 0..1 -> 24h "HH:MM" (debug/logging; no location logic).
func hour_string() -> String:
	var hours: float = float(_gs.time_of_day) * 24.0
	var h: int = int(hours)
	var m: int = int((hours - float(h)) * 60.0)
	return "%02d:%02d" % [h, m]
