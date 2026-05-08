# GDScript identifier shadowing

## Rule

GDScript silently shadows **built-in functions** and **inherited node
properties** when a local variable or method parameter reuses the name.
The script compiles, the project runs, and Godot's reload mechanism
emits a warning per shadow that's easy to miss in the output panel.

Don't use these names as locals or parameters:

| Identifier | What it is | Where it bites |
|---|---|---|
| `sin`, `cos`, `tan` | Trig built-ins (`@GlobalScope`) | Any script |
| `abs`, `min`, `max`, `clamp`, `sign`, `floor`, `ceil`, `round` | Math built-ins | Any script |
| `lerp`, `lerpf`, `lerp_angle`, `inverse_lerp` | Interpolation built-ins | Any script |
| `position`, `rotation`, `scale` | `Node3D` / `Control` / `Node2D` properties | Any script extending those |
| `name`, `owner`, `tree`, `multiplayer` | `Node` properties | Any node script |
| `visible`, `modulate`, `pivot_offset`, `size`, `anchor_*` | `Control` properties | Any Control script |
| `velocity`, `motion_mode` | `CharacterBody3D` properties | Player/enemy scripts |
| `mesh`, `material_override` | `MeshInstance3D` properties | Mesh scripts |

Locals shadowing class methods bite the same way — if `class_name FooBar`
defines `func plant():`, a local `var plant` inside another method on
the same class shadows it for the rest of the scope.

## Why it matters

- **Silent during dev.** The warning lands in Godot's output panel
  alongside import noise. Easy to skip past for a few sessions, then
  you have ten of them piled up (F-015).
- **Surprising at use site.** If someone writes `var s = scale * 2`
  expecting the parent's transform scale, but a local `var scale: float`
  was declared earlier in the function, they get the local — no error,
  silent semantic bug.
- **Not all editors flag it the same.** VS Code's GDScript extension
  may or may not surface the warning depending on version; Godot's own
  editor reload is the reliable surface.

## Fix

Rename locals to **domain-specific** names that describe what the value
*is*, not what type it is:

```gdscript
# Bad
var tan: Vector3 = ...           # shadows the trig function
var scale: float = arrow_scale   # shadows Control.scale
var plant := _make_plant_visual() # shadows class method plant()

# Good
var tangent_dir: Vector3 = ...
var arrow_scale: float = base_scale
var plant_visual := _make_plant_visual()
```

For deliberately-int-divided expressions (e.g. row index from grid
position), use `@warning_ignore("integer_division")` on the line, not a
rename — the warning is the right reminder for accidental cases.

## Detection

Run a parse pass periodically:

```sh
godot --headless --path . --import 2>&1 | grep -i 'shadow\|unused\|warning'
```

A clean run is achievable; treat any new warning as a first-class fix.
