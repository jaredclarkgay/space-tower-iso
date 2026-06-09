extends Node

# Telemetry — the session event recorder. The analysis-agent's data tap.
#
# WHY THIS EXISTS — the third axis. GameState says what is TRUE in the world;
# GameDirector says what should happen NEXT. Neither records what actually
# HAPPENED over a play session. Telemetry is that missing axis: an append-only
# stream of timestamped events (phase entered, partner hired, crop planted /
# harvested, floor reached) written to a file an OFFLINE agent can replay to
# analyze how real sessions unfold. It is a pure SINK — it reads world state and
# listens for announcements; it NEVER drives gameplay, mirrors state, or makes
# decisions. (That keeps the litmus clean: truth → GameState, next → GameDirector,
# history → here.)
#
# COUPLING — deliberately one-directional and minimal:
#   - Phase events come for FREE: we subscribe to GameDirector.phase_changed,
#     the same low-coupling pattern TimeOfDay uses to latch on TEMPORAL. The
#     director doesn't know we exist.
#   - Non-phase events are ANNOUNCED by their site with one fire-and-forget line:
#         var _tel := get_node_or_null("/root/Telemetry"); if _tel: _tel.record(...)
#     Sites stay ignorant of files/format; they just say what happened.
#
# FORMAT — JSON Lines (one JSON object per line), one file per session:
#   dev / from-source runs → res://_telemetry/session_<stamp>.jsonl — lives INSIDE
#     the project, so the stream is readable everywhere the repo is (your Mac, a
#     connected session) the instant a play session ends. The folder is gitignored.
#   exported / web builds   → user://telemetry/session_<stamp>.jsonl — res:// is
#     read-only there, so we fall back; web export stays intact. (See _resolve_dir.)
# Append-friendly, crash-tolerant (each line flushed), trivially streamable by an
# agent. Every record carries:
#   seq    — monotonic counter within the session
#   t_ms   — ms since session start (monotonic; "time-to-X" is a downstream delta,
#            so nothing here precomputes it)
#   phase  — the GameDirector phase name at the moment of the event
#   event  — the event name
#   ...    — event-specific payload merged in
#
# Toggle via Constants.TELEMETRY_ENABLED (recording on/off) and
# Constants.TELEMETRY_ECHO (mirror each event to the console for live dev).

var _file: FileAccess = null
var _session_start_ms: int = 0
var _seq: int = 0

@onready var _gs: Node = get_node_or_null("/root/GameState")
@onready var _gd: Node = get_node_or_null("/root/GameDirector")
@onready var _c: Node = get_node_or_null("/root/Constants")


func _ready() -> void:
	if not _enabled():
		return
	_open_session()
	if _gd != null and _gd.has_signal("phase_changed"):
		_gd.phase_changed.connect(_on_phase_changed)
	record("session_start", {
		"wall_clock": Time.get_datetime_string_from_system(),
	})


# A gameplay site calls this to announce something happened. Safe to call even
# when disabled (it no-ops because _file is null). `data` is merged over the
# standard envelope, so an event can name its own `phase`/`t_ms` only if it
# really means to override.
func record(event: String, data: Dictionary = {}) -> void:
	if _file == null:
		return
	_seq += 1
	var entry := {
		"seq": _seq,
		"t_ms": Time.get_ticks_msec() - _session_start_ms,
		"phase": _phase_name(),
		"event": event,
	}
	for k in data:
		entry[k] = data[k]
	_file.store_line(JSON.stringify(entry))
	_file.flush()
	if _echo():
		print("[telemetry] ", event, " ", data)


# Absolute path of the active session log (for a debug HUD line or a tail).
func session_path() -> String:
	return _file.get_path_absolute() if _file != null else ""


func _on_phase_changed(_p: int) -> void:
	# GameDirector._mirror() runs before phase_changed.emit(), so GameState.phase
	# is already the NEW phase when we read it in the envelope.
	record("phase_entered")


func _open_session() -> void:
	var dir: String = _resolve_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	_session_start_ms = Time.get_ticks_msec()
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path: String = "%s/session_%s.jsonl" % [dir, stamp]
	_file = FileAccess.open(path, FileAccess.WRITE)


func _resolve_dir() -> String:
	# Dev / from-source runs carry the "editor" feature: write INSIDE the project
	# (res:// globalizes to the repo) so the stream is readable everywhere the repo
	# is. Exported/web builds lack the feature and res:// is read-only there → user://.
	if OS.has_feature("editor"):
		return "res://_telemetry"
	return "user://telemetry"


func _phase_name() -> String:
	# is_instance_valid guards the quit-time path: _exit_tree writes session_end,
	# and the director/state autoloads may already be torn down by then.
	if is_instance_valid(_gd) and _gd.has_method("phase_name") and is_instance_valid(_gs):
		return String(_gd.phase_name(int(_gs.phase)))
	return "?"


func _enabled() -> bool:
	# Default to ON if Constants somehow isn't reachable — telemetry is cheap and
	# the data is the whole point.
	return _c == null or bool(_c.TELEMETRY_ENABLED)


func _echo() -> bool:
	return _c != null and bool(_c.TELEMETRY_ECHO)


func _exit_tree() -> void:
	# Autoloads get _exit_tree on quit — cap the stream with a session_end and
	# close the handle cleanly.
	if _file != null:
		record("session_end")
		_file.flush()
		_file.close()
		_file = null
