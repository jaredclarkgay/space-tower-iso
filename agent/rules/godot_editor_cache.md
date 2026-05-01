# Godot editor cache (.godot/) holds stale state

## Rule
When .tscn / .gd disk fixes don't appear to take effect in the running editor — and `godot --headless --quit-after` confirms the fix works in code — suspect the **editor cache**.

## Symptom
- You edited a .tscn (e.g. set `visible = false` on a Control).
- Disk has the fix; `git diff` confirms.
- Headless run shows no error, no symptom.
- Press F5 in the editor → bug persists.
- Three rounds of code-level "fixes" don't help.

## Cause
Godot caches a lot in `.godot/` next to your project root:
- Imported assets
- Compiled GDScript bytecode
- Scene-state metadata
- Script class registry

When you edit while the editor has the scene open, the editor's in-memory representation can diverge from disk, and the running game uses the cached version.

## Fix
Two-step:
```sh
# Close Godot completely (Cmd-Q on macOS — not just the window).
# Then:
cd /path/to/project
rm -rf .godot/
# Reopen Godot. First open will re-import everything (~10–30 s).
# Press F5.
```

Alternative for a softer reset (often enough): `Project → Reload Current Project` in the editor.

## When to clear the cache
- After heavy .tscn restructuring (re-IDing nodes, reorganising the tree).
- When ext_resource UIDs were missing and Godot is re-assigning them.
- When the symptom is "old behavior persists despite disk being correct".

## When NOT to clear
- For ordinary script edits — Godot picks those up reliably.
- For first-time scene setup — the cache hasn't formed yet.

## Diagnostic shortcut
Always confirm the bug with `--headless --quit-after N` first. If the headless run is silent and the editor still shows the bug, **stop coding** and clear the cache.

## See also
- `failure_log.json` F-009 (CodySchematic appearing at game start).
