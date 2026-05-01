# class_name vs preload + set_script

## Rule
For Control / Node subclasses that are instantiated programmatically, prefer `preload(...).new()` or `Control.new(); ctrl.set_script(preload(...))` over `class_name MyClass; MyClass.new()` — at least for the headless --import path.

## Why
`class_name` registers the class globally so it's available by bare name everywhere in the project. The registration happens during Godot's project scan. In `--headless --import` runs, the scan order isn't always what you'd expect, and an `iso_robot.gd` file that does `var p := CodyPortrait.new()` can fail with:

```
Parse Error: Identifier "CodyPortrait" not declared in the current scope.
```

This isn't a real bug at runtime in the editor (where the registry is built before scenes load), but it breaks headless validation runs.

## Quick fix
```gdscript
# Don't:
class_name CodyPortrait
extends Control

# Do:
extends Control
# (no class_name)

# In the caller:
const _CODY_PORTRAIT := preload("res://scenes/.../cody_portrait.gd")
var ctrl := Control.new()
ctrl.set_script(_CODY_PORTRAIT)
```

## When class_name is fine
- Autoloads (declared in project.godot's [autoload] section) — those are always registered first.
- Scripts referenced only by .tscn `script = ExtResource(...)` — Godot resolves those by path.
- Scripts referenced only after the editor has fully scanned (long-running editor sessions).

## See also
- `failure_log.json` F-010 (cody_portrait.gd class_name registration).
