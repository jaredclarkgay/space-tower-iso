# Label3D pixel_size must scale with orthographic camera size

## The problem

Label3D's on-screen height is governed by `pixel_size` (metres per glyph
pixel), but with an `orthographic` Camera3D the world-to-screen scale is
governed by `camera.size` (the "ortho_size"). With pixel_size held
constant, zooming out (increasing ortho_size) shrinks the label
linearly in screen space.

A label authored to read at 36 px on screen at `ortho_size = 40` collapses
to **9 px at `ortho_size = 160`** — invisible at the camera's wide
framing, fine at the close framing. The label is "correctly" rendering;
the rendering pipeline just doesn't know your intent.

## Symptoms

- "I can't see the E prompt unless I zoom in."
- A label tuned to look right in the editor disappears when the runtime
  camera defaults to a different zoom.
- HUD-style Label3Ds appear and disappear as the player wheel-zooms.

## The fix

Drive `pixel_size` per frame from current camera size:

```gdscript
label.pixel_size = base_pixel_size * (camera.size / default_ortho_size)
```

Where `base_pixel_size` is the value that read correctly at
`default_ortho_size`. The ratio cancels the orthographic projection's
scaling, giving constant on-screen pixel height regardless of zoom.

Pack it in a tiny static-method module (see this project's
`scenes/shared/label_scaler.gd`) so any prompt-owning controller's
`_process` is a one-liner:

```gdscript
LabelScaler.update(_prompt_e, c.LABEL_BASE_PX_BIG,
                   get_viewport().get_camera_3d(),
                   c.CAMERA_ORTHO_SIZE_DEFAULT)
```

## Why this matters in this project

The iso prototype uses `Camera3D` orthographic with mouse-wheel zoom.
Every floor's E-prompts, chooser items, plant prompts, and stairs
markers are Label3Ds in world space. Without per-frame scaling, the
operator's first instinct is "zoom in to read the prompt," which fights
the iso framing the camera is supposed to enforce.

## What NOT to do

- Don't switch the labels to CanvasItem 2D and project positions
  manually — you lose Label3D's `no_depth_test` / `fixed_size` / billboard
  modes, which are the whole reason to use Label3D in iso.
- Don't bump `font_size` to compensate. font_size is integer-quantised
  and the glyph cache rebuilds on change; pixel_size is the right knob.
- Don't apply the scale only when `camera.size` changes. Just run it
  every `_process` — it's a single multiply per label and Godot
  short-circuits redundant property writes.

## When pixel_size scaling is not needed

- The label uses `fixed_size = true` (it then ignores world distance
  entirely; behaves like a HUD billboard).
- The camera is `perspective` rather than orthographic — Label3D
  pixel_size already produces approximately constant on-screen size
  near the focal centre.
