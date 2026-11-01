# Pallid.UI draw primitives

`Pallid.UI` draw helpers paint shapes into an `ISUIElement`. Coordinates are local to the element, colors are `PallidColor` tables with 0..1 components (see [ui-color.md](ui-color.md)), and every helper takes the host element as its first argument.

The host must be an `ISUIElement` with a Java peer (`el.javaObject`). A call made before `addToUIManager` is harmless: every helper checks the peer first and returns `false` (or nothing) instead of raising. Rectangles clamp to the software clip stack pushed by `Pallid.UI.clip` ([ui-clipping.md](ui-clipping.md)); vector shapes are only rejected when fully outside and otherwise rely on the engine stencil. Widgets that wrap these helpers are described in [ui-widget.md](ui-widget.md).

## Pallid.UI.rect

Fills an axis-aligned rectangle with a flat color.

**Side:** client

### Parameters
- el (ISUIElement) - Host element; must have a Java peer.
- x (number) - Left coordinate, local to the element.
- y (number) - Top coordinate, local to the element.
- w (number) - Width in pixels; values <= 0 draw nothing.
- h (number) - Height in pixels; values <= 0 draw nothing.
- color (PallidColor or nil) - Fill color; nil means white.

### Returns
- boolean - `false` when the element is invalid, the size is empty, or the box is fully outside the active clip.

### Example
```lua
local Panel = ISPanel:derive("PallidRectDemo")

function Panel:render()
    Pallid.UI.rect(self, 8, 8, 120, 40, Pallid.UI.Color.surface)
end

local panel = Panel:new(100, 100, 160, 80)
panel:addToUIManager()
```

### Notes
- Both edges of the box are snapped to whole pixels, so fractional layout stays flush with neighbours and a positive size never collapses below 1 px.
- The draw is a single solid quad; there is no anti-aliasing.

## Pallid.UI.border

Draws a rectangular outline made of four solid rectangles, inside the supplied bounds.

**Side:** client

### Parameters
- el (ISUIElement) - Host element; must have a Java peer.
- x (number) - Left coordinate.
- y (number) - Top coordinate.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- thickness (number) - Border thickness in pixels; values <= 0 draw nothing.
- color (PallidColor or nil) - Border color; nil means white.

### Returns
- boolean - `false` when the element is invalid or the input is empty.

### Example
```lua
Pallid.UI.border(el, 8, 8, 120, 40, 1, Pallid.UI.Color.border)
```

### Notes
- Thickness is snapped and raised to at least 1 px.
- When `thickness * 2` reaches the width or the height, the box is filled with `Pallid.UI.rect` instead of stroked, and that call's result is returned.
- There is no anti-aliasing and no radius; use `roundedBorder` for rounded corners.

## Pallid.UI.roundedRect

Fills a rectangle with per-corner radii.

**Side:** client

### Parameters
- el (ISUIElement) - Host element; must have a Java peer.
- x (number) - Left coordinate.
- y (number) - Top coordinate.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- radius (number or table) - Number for all four corners, or a table with `tl`, `tr`, `br`, `bl` fields.
- color (PallidColor or nil) - Fill color; nil means white.

### Returns
- boolean - `true` when something was drawn.

### Example
```lua
Pallid.UI.roundedRect(el, 8, 8, 120, 40, 6, Pallid.UI.Color.surfaceElevated)
```

### Notes
- Missing table keys fall back in this order: `tr` to `tl`, `br` to `tl`, `bl` to `tr`. A table with only `tr` set therefore rounds the top-right and bottom-left corners.
- Each radius is clamped to half the shorter side, adjacent radii are shrunk proportionally so they cannot overlap, and every radius is floored to a whole pixel; a radius below 1 becomes a square corner.
- Uniform radii use the anti-aliased circle texture between 2 and 96 px, a square block below 2 px, and a vector arc above 96 px. Non-uniform radii always use a vector fan.
- All radii at zero falls back to `Pallid.UI.rect`.

## Pallid.UI.roundedBorder

Draws a rounded rectangular outline inside the supplied bounds.

**Side:** client

### Parameters
- el (ISUIElement) - Host element; must have a Java peer.
- x (number) - Left coordinate.
- y (number) - Top coordinate.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- radius (number or table) - Number for all corners, or a table with `tl`, `tr`, `br`, `bl` fields.
- thickness (number) - Border thickness in pixels; values <= 0 draw nothing.
- color (PallidColor or nil) - Border color; nil means white.

### Returns
- boolean - `false` when the element is invalid or the input is empty.

### Example
```lua
Pallid.UI.roundedBorder(el, 8, 8, 120, 40, 6, 1, Pallid.UI.Color.borderStrong)
```

### Notes
- Radii are resolved and floored exactly like `roundedRect`; a corner is stroked as an arc only when its radius is at least the thickness, otherwise it is a square block.
- When `thickness * 2` reaches the width or the height, the box is filled with `Pallid.UI.roundedRect` instead.

## Pallid.UI.circle

Fills a circle or a pie sector.

**Side:** client

### Parameters
- el (ISUIElement) - Host element; must have a Java peer.
- cx (number) - Center X.
- cy (number) - Center Y.
- r (number) - Radius in pixels.
- color (PallidColor or nil) - Fill color; nil means white.
- a0 (number or nil) - Start angle in radians; omit for a full circle.
- a1 (number or nil) - End angle in radians; omit for a full circle.

### Returns
- boolean - `true` when something was drawn.

### Example
```lua
Pallid.UI.circle(el, 40, 40, 16, Pallid.UI.Color.primary)
```

### Notes
- If either `a0` or `a1` is nil the whole circle is drawn, so passing only one angle does not produce a sector.
- Angles use +x right and +y down, so increasing angle runs clockwise on screen. An `a1` below `a0` is wrapped by adding 2*pi.
- A full circle uses the anti-aliased texture between 2 and 96 px radius and a vector fan outside that range; a sector always uses the fan.

## Pallid.UI.ring

Strokes a ring or an arc.

**Side:** client

### Parameters
- el (ISUIElement) - Host element; must have a Java peer.
- cx (number) - Center X.
- cy (number) - Center Y.
- r (number) - Outer radius in pixels.
- thickness (number) - Ring thickness in pixels; values <= 0 draw nothing.
- color (PallidColor or nil) - Stroke color; nil means white.
- a0 (number or nil) - Start angle in radians; defaults to 0.
- a1 (number or nil) - End angle in radians; defaults to 2*pi.

### Returns
- boolean - `true` when something was drawn.

### Example
```lua
Pallid.UI.ring(el, 40, 40, 16, 2, Pallid.UI.Color.primaryStrong, -math.pi / 2, 0)
```

### Notes
- The stroke lies between `r` and `r - thickness`, so it stays inside the outer radius.
- Spans wider than 2*pi are clamped to a full ring, and an `a1` below `a0` is wrapped by adding 2*pi.
- The arc is built from a strip of quads; the segment count depends on radius and span and is capped at 96.

## Pallid.UI.line

Draws a straight line with an optional dash pattern.

**Side:** client

### Parameters
- el (ISUIElement) - Host element; must have a Java peer.
- x1 (number) - Start X.
- y1 (number) - Start Y.
- x2 (number) - End X.
- y2 (number) - End Y.
- thickness (number) - Line thickness in pixels; values <= 0 draw nothing.
- color (PallidColor or nil) - Line color; nil means white.
- dash (number or nil) - Dash length in pixels; nil or <= 0 draws a solid line.
- gap (number or nil) - Gap length in pixels; defaults to `dash`, negative values become 0.

### Returns
- boolean - `true` when something was drawn.

### Example
```lua
Pallid.UI.line(el, 8, 60, 128, 60, 1, Pallid.UI.Color.borderStrong, 4, 2)
```

### Notes
- The line is a solid quad with no anti-aliasing, and each dash is a separate quad, so the pattern restarts at `(x1, y1)`.
- A dashed line of zero length returns `false`; a solid line never checks its length.
- `dash` and `gap` are absolute pixel lengths and are not scaled by thickness.

## Pallid.UI.polyline

Draws a polyline through a list of points.

**Side:** client

### Parameters
- el (ISUIElement) - Host element; must have a Java peer.
- points (PallidPoint[]) - Absolute element-local points with `x` and `y` fields; at least two.
- thickness (number) - Line thickness in pixels; values <= 0 draw nothing.
- color (PallidColor or nil) - Line color; nil means white.
- closed (boolean or nil) - Connect the last point back to the first.

### Returns
- boolean - `true` when something was drawn.

### Example
```lua
Pallid.UI.polyline(el, {
    { x = 8,  y = 40, },
    { x = 40, y = 12, },
    { x = 72, y = 40, },
}, 2, Pallid.UI.Color.primary, true)
```

### Notes
- Unlike `polygon`, the points are not validated: a malformed entry raises a Lua error instead of returning `false`.
- Each segment is an independent quad, so thick polylines show a notch on the outside of sharp joins.
- Passing a repeated first/last point with `closed` adds a zero-length segment, which is skipped.

## Pallid.UI.regularPolygon

Fills a regular polygon inscribed in a circle.

**Side:** client

### Parameters
- el (ISUIElement) - Host element; must have a Java peer.
- sides (integer) - Number of sides; floored, values below 3 return `false`.
- cx (number) - Center X.
- cy (number) - Center Y.
- radius (number) - Distance from the center to each vertex.
- rotation (number or nil) - Rotation in degrees; defaults to 0, first vertex pointing right.
- color (PallidColor or nil) - Fill color; nil means white.

### Returns
- boolean - `true` when something was drawn.

### Example
```lua
Pallid.UI.regularPolygon(el, 6, 40, 40, 18, 0, Pallid.UI.Color.primarySoft)
```

### Notes
- Side counts 3, 4, 5, 6 and 8 use a baked anti-aliased texture; every other count falls back to a triangle fan with hard edges.
- Rotation is in degrees and turns clockwise on screen, because +y points down.
- The bounding box is always square, so the texture path applies to those side counts at any rotation.

## Pallid.UI.polygon

Fills a convex polygon with a triangle fan.

**Side:** client

### Parameters
- el (ISUIElement) - Host element; must have a Java peer.
- points (PallidPoint[]) - Absolute element-local points with numeric `x` and `y`; at least three.
- color (PallidColor or nil) - Fill color; nil means white.

### Returns
- boolean - `false` when the element is invalid, fewer than three points are given, a point is malformed, or the white texture is unavailable.

### Example
```lua
Pallid.UI.polygon(el, {
    { x = 40, y = 8,  },
    { x = 72, y = 64, },
    { x = 8,  y = 64, },
}, Pallid.UI.Color.primary)
```

### Notes
- Only convex input is supported; a concave polygon renders incorrectly.
- The fan diagonals are not anti-aliased. For a regular shape prefer `regularPolygon`, which uses the baked texture.

## Pallid.UI.checker

Fills a rectangle with a two-color checkerboard, typically behind translucent colors.

**Side:** client

### Parameters
- el (ISUIElement) - Host element; must have a Java peer.
- x (number) - Left coordinate.
- y (number) - Top coordinate.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- cell (number) - Preferred cell size in pixels; values <= 0 draw nothing.
- colorA (PallidColor) - Color of the even cells.
- colorB (PallidColor) - Color of the odd cells.

### Example
```lua
Pallid.UI.checker(el, 8, 8, 64, 64, 8, Pallid.UI.Color.cloud, Pallid.UI.Color.mist)
```

### Notes
- The grid is `ceil(w / cell)` by `ceil(h / cell)` cells, and each cell edge is snapped, so the drawn cell size is `w / columns` by `h / rows` rather than exactly `cell`.
- A cell is even when `row + column` is even; that is `colorA`.
- Every cell is a separate `Pallid.UI.rect` call, so a small cell over a large area costs one draw call per cell.
- The function returns nothing, and invalid input or a missing Java peer silently draws nothing.

## Pallid.UI.progress

Draws a track and a fill in one call, in linear, radial or outline mode.

**Side:** client

### Parameters
- el (ISUIElement) - Host element; must have a Java peer.
- shape (PallidShape) - Shape from `Pallid.UI.Shape` ([ui-geometry.md](ui-geometry.md)); `nil` is rejected with `"no shape"`.
- x (number) - Left coordinate, local to the element.
- y (number) - Top coordinate, local to the element.
- w (number) - Width in pixels; must be positive.
- h (number) - Height in pixels; must be positive.
- fraction (number or nil) - Completion, clamped to 0..1; nil counts as 0.
- style (table or nil) - `PallidProgressStyle`; create it once and reuse it.

### Style fields
- mode (string) - `"linear"` (default), `"radial"` or `"outline"`.
- direction (string) - Linear fill direction: `"right"` (default), `"left"`, `"up"` or `"down"`.
- startAngle (number) - Radial start angle in degrees; default -90, the top.
- clockwise (boolean) - Radial direction; default `true`, `false` fills counter-clockwise.
- fg (PallidColor) - Fill color; default white.
- bg (PallidColor) - Track color; default `Pallid.UI.Color.surfaceMuted`.
- trackAlpha (number) - Track alpha; defaults to 0.22 when `bg` is omitted, otherwise to `bg.a` (1 when `bg` has no `a`).
- thickness (number) - Outline stroke width in pixels; default 3, used only by outline mode.

### Returns
- boolean - `true` when the track was drawn, and the fill when `fraction` is above 0.
- string or nil - Failure reason, for example `"no shape"`, `"empty box"`, `"could not push the progress clip"`, `"radial mode requires Shape.circle"` or `"unsupported progress mode: ..."`.

### Example
```lua
local SHAPE = Pallid.UI.Shape.roundedRect(4)
local STYLE = {
    mode      = "linear",
    direction = "right",
    fg        = Pallid.UI.Color.primary,
}

local Panel = ISPanel:derive("PallidProgressDemo")

function Panel:render()
    Pallid.UI.progress(self, SHAPE, 8, 8, 160, 10, 0.4, STYLE)
end

local panel = Panel:new(100, 100, 180, 30)
panel:addToUIManager()
```

### Notes
- Linear mode fills the shape with the track color, then fills it again clipped to an axis-aligned band, so a partial fill of a circle or rounded rect has a straight leading edge. It needs a working stencil and returns `false, "could not push the progress clip"` when the clip cannot be pushed. At fraction 0 only the track is drawn; at 1 the shape is filled directly with no clip.
- Radial mode requires a `Shape.circle`; the track is a full pie and the fill spans `2*pi*fraction` from `startAngle`. This path returns the fill result directly, so `reason` can be nil on failure.
- Outline mode strokes the perimeter with `thickness` and supports rect, roundedRect, circle and polygon shapes; it ignores `direction`.
- The style table is read only; `progress` does not modify it.
