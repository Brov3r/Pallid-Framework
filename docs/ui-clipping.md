# Clipping

`Pallid.UI.clip` bounds drawing to a rectangle or ellipse by pushing an engine
stencil level and a matching software clip level. Every successful `clip` must be
paired with exactly one `clipEnd` on the same element.

## Clip stack

Nesting rules shared by all clip functions.

**Side:** client

### Notes
- Each `clip` call intersects its box with the enclosing level and pushes one level.
  Nested clips therefore narrow the visible area and never widen it.
- `clipEnd` pops one level and restores the parent rectangle unchanged.
- The software stack is module-global, not per element. Pushing on one element and
  popping on another still pops the global stack; only the element depth check
  differs.
- The stack is pooled at 16 levels. Deeper nesting grows the pool once and logs a
  warning, so depth is not a hard limit.
- Each level records whether it is backed by the engine stencil. Draw helpers use
  the innermost rectangle to clamp geometry and to cull invisible calls.
- Widget trees reset the stack themselves at a frame root, so a normal widget
  `draw` implementation does not need to call `resetClip`.

## Pallid.UI.clip

Pushes a clipping region for the target element.

**Side:** client

### Parameters
- el (ISUIElement) - Target element. It must already have a Java peer.
- shape (PallidShape|nil) - Shape created with `Pallid.UI.Shape`. Only
  `Shape.rect` and `Shape.circle` are exact.
- x (number) - Left coordinate, local to the element.
- y (number) - Top coordinate, local to the element.
- w (number) - Width in pixels. Must be positive.
- h (number) - Height in pixels. Must be positive.

### Returns
- boolean - True when a stencil level was pushed.
- string - Mode: `"rect"`, `"circle"`, `"circle-nofilter"` or `"none"`.
- string or nil - Reason when the clip could not be applied exactly.

### Example
```lua
require "pallid/ui/api/geometry"
require "pallid/ui/api/clip"

local Shape = Pallid.UI.Shape
local RECT = Shape.rect()

local entered = Pallid.UI.clip(el, RECT, contentX, contentY, contentW, contentH)
if entered then
    -- draw clipped content here
    Pallid.UI.clipEnd(el)
end
```

### Notes
- The box is snapped to whole pixels with edges rounded to nearest, and the size is
  forced to at least 1x1. Pass `w <= 0` or `h <= 0` to skip clipping instead of
  expecting an empty clip.
- Returns `false, "none", reason` for an element without a Java peer, a nil shape, a
  shape without `kind`, or an empty box. Nothing is pushed in that case.
- `Shape.circle` queues an alpha threshold (`GL_GREATER`, 0.5) so the transparent
  corners of the circle texture are not written to the stencil, then restores
  `GL_ALWAYS`. If the threshold is unavailable the stencil may be rectangular; the
  call still succeeds with mode `"circle-nofilter"` and warns once.
- Any other shape kind warns once per kind and returns `false, "none", reason`
  without pushing a level, so `clipEnd` must not be called for it.
- Coordinates are element-local, the same space as `Pallid.UI.rect`.

## Pallid.UI.clipEnd

Pops one clipping level pushed by `Pallid.UI.clip`.

**Side:** client

### Parameters
- el (ISUIElement) - Element the level was pushed on.

### Returns
- boolean - True when a level was popped.

### Example
```lua
require "pallid/ui/api/geometry"
require "pallid/ui/api/clip"

local RECT = Pallid.UI.Shape.rect()

if Pallid.UI.clip(el, RECT, x, y, w, h) then
    -- clipped drawing
    Pallid.UI.clipEnd(el)
end
```

### Notes
- Call it exactly once per successful `clip`. Popping without a matching level
  returns false and logs a warning, so guard on the `clip` result.
- The first unbalanced pop logs the element name plus both stack depths; repeats are
  only counted and logged every 600 occurrences.
- After popping it calls `clearStencilRect`, then repaints the remaining
  stencil-backed parent level with `repaintStencilRect` so drawing that follows is
  not rejected inside the popped rectangle.
- An element drawn with `parent == nil` is treated as a frame root and resets both
  stacks. A container that draws its content manually must set `content.parent = self`,
  otherwise its `clipEnd` has no matching level.

## Pallid.UI.clipRect

Returns the current software clip rectangle.

**Side:** client

### Returns
- number or nil - Clip left, or nil when nothing is clipped.
- number - Clip top.
- number - Clip width in pixels, 0 for an empty clip.
- number - Clip height in pixels, 0 for an empty clip.

### Example
```lua
require "pallid/ui/api/clip"

local clipX, clipY, clipW, clipH = Pallid.UI.clipRect()
if clipX ~= nil then
    local visibleWidth = math.min(width, clipX + clipW - x)
end
```

### Notes
- Only the innermost level is returned. Because levels are intersected on push, that
  rectangle already represents the full visible area.
- Coordinates are root-local: the same element-local space the clip was pushed in.
- The built-in draw helpers call this themselves, so manual use is only needed for
  custom drawing.

## Pallid.UI.clipHasStencil

Reports whether the innermost clip level is backed by the engine stencil.

**Side:** client

### Returns
- boolean - True when the innermost level was pushed by `Pallid.UI.clip`.

### Example
```lua
require "pallid/ui/api/clip"

if Pallid.UI.clipHasStencil() then
    -- the GPU can cut a partially visible line
end
```

### Notes
- `Pallid.UI.clip` is the only public path that pushes a level, so this is true
  whenever a clip is active.
- It reports the stencil, not the software clip. A suspended stencil still counts as
  present.
- Text drawing uses this to decide whether a line that straddles the clip can be cut
  by the GPU instead of being dropped whole.

## Pallid.UI.isClippedOut

Tests whether a rectangle is completely invisible under the active clip.

**Side:** client

### Parameters
- x (number) - Left coordinate.
- y (number) - Top coordinate.
- w (number) - Width in pixels.
- h (number) - Height in pixels.

### Returns
- boolean - True when nothing inside the rectangle can be visible.

### Example
```lua
require "pallid/ui/api/clip"

if not Pallid.UI.isClippedOut(x, y, w, h) then
    -- draw the box
end
```

### Notes
- Returns false when no clip is active, and true when the innermost clip is empty.
- Only the innermost level is tested, which is sufficient because levels are already
  intersected.
- It is a whole-box test: a box that is partially visible returns false and still
  needs clamping by the draw helper.
- The stencil is not consulted, so a suspended stencil does not change the result.

## Pallid.UI.resetClip

Clears the software clip stack and the element's recorded clip depth.

**Side:** client

### Parameters
- el (ISUIElement|nil) - Host element whose clip depth is also reset. Optional.

### Example
```lua
require "pallid/ui/api/clip"

function MyHost:draw()
    Pallid.UI.resetClip(self)
    -- draw the root and its children
end
```

### Notes
- Call it once at the start of a frame, before drawing the root, so an interrupted
  frame cannot leak a clip into the next one.
- When `el` has a depth above zero and a Java peer, the engine stencil is cleared
  too. Without `el`, a leaked stencil is not cleared and later draws can be rejected
  outside its rectangle, which reads as a black screen.
- It also advances the internal draw-frame counter used for per-frame texture caches,
  so call it once per frame rather than around each element.
- Widget trees already call this at a frame root; manual use is for custom hosts.

## Pallid.UI.clipSuspend

Temporarily disables the stencil and alpha tests without changing clip depth.

**Side:** client

### Parameters
- el (ISUIElement) - Target element.

### Returns
- boolean - False when the element is invalid or already suspended.

### Example
```lua
require "pallid/ui/api/clip"

if Pallid.UI.clipSuspend(el) then
    -- stencil is off here
    Pallid.UI.clipResume(el)
end
```

### Notes
- The clip depth and software rectangle are unchanged. The `Pallid.UI` draw helpers
  still clamp and cull against `clipRect`, so this alone does not let them draw
  outside the clip.
- Pair it with `clipResume`; a suspended stencil left on leaks into later frames
  because it is stored on the element.

## Pallid.UI.clipResume

Re-enables the stencil state disabled by `Pallid.UI.clipSuspend`.

**Side:** client

### Parameters
- el (ISUIElement) - Target element.

### Returns
- boolean - False when the element is invalid or nothing was suspended.

### Example
```lua
require "pallid/ui/api/clip"

Pallid.UI.clipResume(el)
```

### Notes
- Resuming an element that was never suspended returns false and changes nothing.
- The call is safe to repeat; the second call is a no-op.

## Pallid.UI.clipDepth

Returns the element's current clip depth.

**Side:** client

### Parameters
- el (ISUIElement|nil) - Target element.

### Returns
- integer - Depth, or 0 when no clip is active or the element is invalid.

### Example
```lua
require "pallid/ui/api/clip"

local depth = Pallid.UI.clipDepth(el)
```

### Notes
- This is the element's own counter, which `clipEnd` trusts. It is not the global
  software depth, so the two can differ after unbalanced calls.
- `clipEnd` and `resetClip` keep it in sync; do not assign it directly.
