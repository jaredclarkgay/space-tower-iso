# Fading 3D meshes via material, not modulate

## Rule
`MeshInstance3D` and other `GeometryInstance3D` subclasses do **NOT** have
`modulate`. That's a `CanvasItem` (2D) property. To fade a 3D mesh in or
out, tween the material's `albedo_color:a` and `emission_energy_multiplier`
directly.

## Quick template
```gdscript
var mesh := MeshInstance3D.new()
var mat := StandardMaterial3D.new()
mat.albedo_color = Color(1.0, 0.85, 0.30, 0.22)
mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
mat.emission_enabled = true
mat.emission = Color(1.0, 0.85, 0.30)
mat.emission_energy_multiplier = 2.4
mesh.material_override = mat
add_child(mesh)

# Fade out via the material — keep the mat ref so the tween can find it.
var tween := create_tween().set_parallel(true)
tween.tween_property(mat, "albedo_color:a", 0.0, 1.0)
tween.tween_property(mat, "emission_energy_multiplier", 0.0, 1.0)
tween.chain().tween_callback(mesh.queue_free)
```

## Why this matters
- `modulate` exists on `Label3D` (so `tween_property(label3d, "modulate:a", ...)` works) but does NOT exist on `MeshInstance3D` / `SpotLight3D` / `OmniLight3D` / etc.
- A `Tween` targeting `modulate:a` on those nodes throws a runtime error per tween call.
- Material-level fades require `transparency = TRANSPARENCY_ALPHA` on the material; without it the alpha tween won't render translucent.

## See also
- `failure_log.json` F-007 (Cody arrival light column).
