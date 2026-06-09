#!/usr/bin/env python3
"""session_summary — the first lens on the Telemetry event stream.

The Telemetry autoload (autoloads/telemetry.gd) writes one JSON object per line
to user://telemetry/session_*.jsonl during play. This reads the latest such
session (or one you name) and prints what happened: how far through the arc the
player got, the time-to-X milestones, and the crop plant-vs-harvest tally.

It is the SEED of the analysis agent: deliberately a pure reader (it never
touches game code or the engine), and it speaks JSON too (--json) so a future
agent can consume its output instead of re-parsing the raw stream.

USAGE
    python3 agent/analysis/session_summary.py            # latest session, human report
    python3 agent/analysis/session_summary.py PATH       # a specific .jsonl file or dir
    python3 agent/analysis/session_summary.py --list      # list available sessions
    python3 agent/analysis/session_summary.py --json      # machine-readable summary
    python3 agent/analysis/session_summary.py --all        # aggregate across all sessions

Where the data lives (resolved automatically): Godot's user:// for this project,
i.e. on macOS
    ~/Library/Application Support/Godot/app_userdata/Space-Tower-Iso/telemetry
and on Linux
    ~/.local/share/godot/app_userdata/Space-Tower-Iso/telemetry
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
from pathlib import Path

# The linear narrative spine, in order — mirrors GameDirector.Phase. Used to rank
# "how far did they get". Keep in sync if the enum gains a beat.
PHASE_ORDER = [
    "EMPTY_LOT",
    "HIRE_PARTNER",
    "BUILD_STRUCTURE",
    "BUILD_INTERIORS",
    "ACTIVATE_FLOORS",
    "SHARE",
    "TEMPORAL",
]

DEFAULT_DIRS = [
    Path.home() / "Library/Application Support/Godot/app_userdata/Space-Tower-Iso/telemetry",
    Path.home() / ".local/share/godot/app_userdata/Space-Tower-Iso/telemetry",
]


# ---------------------------------------------------------------- loading -----

def resolve_target(arg: str | None) -> tuple[Path | None, list[Path]]:
    """Return (chosen_file, all_session_files). chosen_file is None for --list/--all."""
    if arg:
        p = Path(arg).expanduser()
        if p.is_file():
            return p, [p]
        if p.is_dir():
            return None, _sessions_in(p)
        sys.exit(f"error: no such file or directory: {p}")
    for d in DEFAULT_DIRS:
        if d.is_dir():
            return None, _sessions_in(d)
    sys.exit(
        "error: no telemetry directory found. Play a session first, or pass a path.\n"
        "  looked in:\n    " + "\n    ".join(str(d) for d in DEFAULT_DIRS)
    )


def _sessions_in(d: Path) -> list[Path]:
    # Sort by filename: the session_<YYYY-MM-DD_HH-MM-SS> stamp sorts lexically =
    # chronologically, so files[-1] is always the newest. (mtime is unreliable —
    # some mounts only keep second-granularity timestamps.)
    return sorted(d.glob("session_*.jsonl"), key=lambda f: f.name)


def load_events(path: Path) -> list[dict]:
    events = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            # A crash mid-write can leave one torn final line — skip it, keep the rest.
            continue
    return events


# -------------------------------------------------------------- analysis -----

def fmt_ms(ms: int | float | None) -> str:
    if ms is None:
        return "—"
    s = ms / 1000.0
    if s < 60:
        return f"{s:.1f}s"
    return f"{int(s // 60)}m {s % 60:04.1f}s"


def first_event(events: list[dict], name: str) -> dict | None:
    for e in events:
        if e.get("event") == name:
            return e
    return None


def summarize(path: Path) -> dict:
    """Reduce one session's event list to a structured summary dict."""
    events = load_events(path)
    start = first_event(events, "session_start")
    duration = max((int(e.get("t_ms", 0)) for e in events), default=0)

    # Phase progression: the start phase, then every phase actually entered.
    progression: list[str] = []
    if start and start.get("phase"):
        progression.append(start["phase"])
    for e in events:
        if e.get("event") == "phase_entered":
            progression.append(e.get("phase", "?"))
    reached = [p for p in progression if p in PHASE_ORDER]
    furthest = max(reached, key=PHASE_ORDER.index) if reached else "?"

    # Floors.
    floor_events = [e for e in events if e.get("event") == "floor_reached"]
    levels = sorted({int(e["level"]) for e in floor_events if "level" in e})
    interior = [lv for lv in levels if lv >= 0]
    max_level = max(interior) if interior else None

    # Crops.
    planted = [e for e in events if e.get("event") == "crop_planted"]
    harvested = [e for e in events if e.get("event") == "crop_harvested"]
    by_seed: dict[str, int] = {}
    for e in planted:
        by_seed[e.get("seed", "?")] = by_seed.get(e.get("seed", "?"), 0) + 1
    harvested_by_player = sum(1 for e in harvested if e.get("by_player"))

    # Time-to-X (from session start, which is t_ms≈0).
    hire = first_event(events, "partner_hired")
    first_plant = planted[0] if planted else None
    first_harvest = harvested[0] if harvested else None
    first_interior = next((e for e in floor_events if int(e.get("level", -1)) >= 0), None)

    return {
        "file": path.name,
        "started": start.get("wall_clock") if start else None,
        "duration_ms": duration,
        "partner": hire.get("name") if hire else None,
        "furthest_phase": furthest,
        "reached_temporal": "TEMPORAL" in reached,
        "phases_entered": progression,
        "levels_reached": levels,
        "max_interior_level": max_level,
        "crops_planted": len(planted),
        "crops_planted_by_seed": by_seed,
        "crops_harvested": len(harvested),
        "crops_harvested_by_player": harvested_by_player,
        "time_to": {
            "hire_ms": int(hire["t_ms"]) if hire else None,
            "first_floor_ms": int(first_interior["t_ms"]) if first_interior else None,
            "first_plant_ms": int(first_plant["t_ms"]) if first_plant else None,
            "first_harvest_ms": int(first_harvest["t_ms"]) if first_harvest else None,
        },
        "event_count": len(events),
    }


# ---------------------------------------------------------------- output -----

def print_report(s: dict) -> None:
    print(f"\n  SESSION  {s['file']}")
    print(f"  started  {s['started'] or '—'}    duration {fmt_ms(s['duration_ms'])}    events {s['event_count']}")
    print("  " + "─" * 56)

    arc_pos = PHASE_ORDER.index(s["furthest_phase"]) + 1 if s["furthest_phase"] in PHASE_ORDER else 0
    print(f"  Partner hired ....... {s['partner'] or '— (none)'}")
    print(f"  Furthest phase ...... {s['furthest_phase']}  ({arc_pos}/{len(PHASE_ORDER)} beats)")
    print(f"  Day/night reached ... {'yes' if s['reached_temporal'] else 'no'}")
    if s["levels_reached"]:
        top = s["max_interior_level"]
        print(f"  Floors reached ...... {s['levels_reached']}    (top interior: {top if top is not None else '—'})")
    else:
        print("  Floors reached ...... — (never entered the tower)")

    print(f"  Crops planted ....... {s['crops_planted']}" + (f"  {s['crops_planted_by_seed']}" if s["crops_planted_by_seed"] else ""))
    print(f"  Crops harvested ..... {s['crops_harvested']}  ({s['crops_harvested_by_player']} by player, {s['crops_harvested'] - s['crops_harvested_by_player']} by robot)")

    tt = s["time_to"]
    print("  " + "─" * 56)
    print("  TIME-TO")
    print(f"    hire ............. {fmt_ms(tt['hire_ms'])}")
    print(f"    enter tower ...... {fmt_ms(tt['first_floor_ms'])}")
    print(f"    first plant ...... {fmt_ms(tt['first_plant_ms'])}")
    print(f"    first harvest .... {fmt_ms(tt['first_harvest_ms'])}")
    print()


def print_list(files: list[Path]) -> None:
    if not files:
        print("no sessions found.")
        return
    print(f"\n  {len(files)} session(s):\n")
    for f in files:
        try:
            n = len(load_events(f))
        except OSError:
            n = 0
        print(f"    {f.name:<40} {n:>4} events")
    print()


def print_aggregate(files: list[Path]) -> None:
    summaries = [summarize(f) for f in files]
    if not summaries:
        print("no sessions to aggregate.")
        return

    def med(key_path):
        vals = []
        for s in summaries:
            v = s["time_to"][key_path]
            if v is not None:
                vals.append(v)
        return statistics.median(vals) if vals else None

    reached_counts = {}
    for s in summaries:
        reached_counts[s["furthest_phase"]] = reached_counts.get(s["furthest_phase"], 0) + 1

    print(f"\n  AGGREGATE over {len(summaries)} session(s)")
    print("  " + "─" * 56)
    print(f"  Reached the tower ... {sum(1 for s in summaries if s['levels_reached'])}/{len(summaries)}")
    print(f"  Hired a partner ..... {sum(1 for s in summaries if s['partner'])}/{len(summaries)}")
    print(f"  Reached TEMPORAL .... {sum(1 for s in summaries if s['reached_temporal'])}/{len(summaries)}")
    print("  Furthest-phase spread:")
    for p in PHASE_ORDER:
        if reached_counts.get(p):
            print(f"    {p:<16} {reached_counts[p]}")
    print("  Median time-to:")
    print(f"    hire ............. {fmt_ms(med('hire_ms'))}")
    print(f"    enter tower ...... {fmt_ms(med('first_floor_ms'))}")
    print(f"    first plant ...... {fmt_ms(med('first_plant_ms'))}")
    print(f"    first harvest .... {fmt_ms(med('first_harvest_ms'))}")
    print()


# ------------------------------------------------------------------ main -----

def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Summarize a Space Tower Iso telemetry session.")
    ap.add_argument("path", nargs="?", help="a session_*.jsonl file or a telemetry dir (default: auto)")
    ap.add_argument("--list", action="store_true", help="list available sessions and exit")
    ap.add_argument("--json", action="store_true", help="emit the summary as JSON")
    ap.add_argument("--all", action="store_true", help="aggregate across all sessions")
    args = ap.parse_args(argv)

    chosen, files = resolve_target(args.path)

    if args.list:
        print_list(files)
        return 0

    if args.all:
        if args.json:
            print(json.dumps([summarize(f) for f in files], indent=2))
        else:
            print_aggregate(files)
        return 0

    target = chosen or (files[-1] if files else None)
    if target is None:
        sys.exit("error: no sessions found to summarize.")

    summary = summarize(target)
    if args.json:
        print(json.dumps(summary, indent=2))
    else:
        print_report(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
