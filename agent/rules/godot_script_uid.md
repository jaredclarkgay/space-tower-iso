# Godot script .uid files matter

## Rule

After creating a new `.gd` file that's referenced by a `.tscn`, run
`godot --headless --path . --import` once before relying on the scene.
Without the `.uid` companion file on disk, the `.tscn`'s `ExtResource`
reference can resolve to a script-less Node — symptom is a node that
appears in the tree but has no behavior, no fields, no methods.

## Why

Godot 4 uses UID-based references between resources. When you add a new
script, the `.tscn` either references it by path alone:

```
[ext_resource type="Script" path="res://scenes/foo.gd" id="1_foo"]
```

…which works only as long as Godot can resolve the path at load time.
If the `.uid` companion (`scenes/foo.gd.uid`) hasn't been generated
yet because no editor or import has run since the script was created,
some load paths will silently fall back to a Node-with-no-script —
the scene loads, the node exists, but the behavior is missing.

In our case the seed dispenser appeared as an empty `Node3D` at game
start — no chassis, no windows, no interaction surface — even though
the script was complete. Headless `--quit-after` validation passed
because the bare `Node3D` doesn't error.

## Fix

```sh
# Run once after creating any new .gd that's referenced from a .tscn.
godot --headless --path . --import 2>&1 | tail -5

# Verify the .uid was generated:
cat scenes/iso_prototype/foo.gd.uid
# → uid://b4b340og50t0n
```

Then pin the `uid` in the `.tscn` ExtResource line so the reference is
stable even if paths shift later:

```
[ext_resource type="Script" uid="uid://b4b340og50t0n"
              path="res://scenes/iso_prototype/foo.gd"
              id="1_foo"]
```

## When to suspect this

If a node "should be there" but appears as empty Node3D / Node / Control:
- No script effects (no _ready prints, no _process effects)
- No fields visible in scene tree at runtime
- No errors in the console either way (silent)

## When NOT to suspect this

- Old scripts that have been imported many times — `.uid` is committed.
- Scripts referenced by `class_name` or `preload(...)` — those use
  different resolution paths (preload is by literal path).

## See also

- `failure_log.json` F-011 (the dispenser missing on first F5).
