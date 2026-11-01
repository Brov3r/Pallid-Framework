# Geometry

`Pallid.UI.Geometry` generates polygon points and `Pallid.UI.Shape` describes the
shape kinds the draw and clip APIs accept. Point and rectangle tests live directly
on `Pallid.UI`.

## PallidPoint

Point descriptor used by polygon shapes and the point-in-polygon test.

**Side:** client

| Field | Type | Meaning |
| --- | --- | --- |
| `x` | number | X coordinate. A fraction of the draw box width (0..1) inside `Shape.polygon`; absolute pixels everywhere else. |
| `y` | number | Y coordinate. A fraction of the draw box height (0..1) inside `Shape.polygon`; absolute pixels everywhere else. |

### Example
```lua
require "pallid/ui/api/geometry"

local center = { x = 0.5, y = 0.5 }
```

### Notes
- The same table shape is used in two coordinate spaces. `Shape.polygon` expects
  normalized values; `Pallid.UI.pointInPolygon` expects absolute values.

## PallidShape

Shape descriptor returned by the `Pallid.UI.Shape` constructors. Build it once and
reuse it for every frame.

**Side:** client

| Field | Type | Meaning |
| --- | --- | --- |
| `kind` | `"rect"`, `"circle"`, `"roundedRect"`, `"polygon"` | Shape kind. |
| `radius` | number or table or nil | Corner radius for `roundedRect`. |
| `points` | `PallidPoint[]` or nil | Normalized polygon points, 0..1. |
| `count` | integer or nil | Number of polygon points. |
| `sides` | integer or nil | Side count, set only by `Shape.regular`. |
| `rotation` | number or nil | Rotation in degrees, set only by `Shape.regular`. |

### Example
```lua
require "pallid/ui/api/geometry"

local Shape = Pallid.UI.Shape
local CARD = Shape.roundedRect(6)

-- CARD is a plain table:
-- { kind = "roundedRect", radius = 6 }
```

### Notes
- Shapes are plain tables; the draw helpers read them without copying, so build one
  per shape and keep it outside draw code.
- `sides` and `rotation` let the progress and fill helpers pick a baked
  anti-aliased texture instead of a triangle fan.

## Shape.rect

Defines a rectangle shape.

**Side:** client

### Returns
- PallidShape - New shape with `kind = "rect"`.

### Example
```lua
require "pallid/ui/api/geometry"

local RECT = Pallid.UI.Shape.rect()
```

### Notes
- Rectangles are clipped exactly by the engine's rectangular stencil; see
  [Clipping](ui-clipping.md).

## Shape.circle

Defines a circle or ellipse inscribed in the draw box.

**Side:** client

### Returns
- PallidShape - New shape with `kind = "circle"`.

### Example
```lua
require "pallid/ui/api/geometry"

local DOT = Pallid.UI.Shape.circle()
```

### Notes
- The shape has no radius field; the radius always comes from the draw box, so a
  non-square box produces an ellipse.
- The engine's elliptical stencil matches this shape, so it can be clipped.

## Shape.roundedRect

Defines a rounded rectangle shape.

**Side:** client

### Parameters
- radius (number|table|nil) - Corner radius. A number applies to all four corners.
  A table uses `{tl, tr, br, bl}` fields.

### Returns
- PallidShape - New shape with `kind = "roundedRect"` and the resolved radius.

### Example
```lua
require "pallid/ui/api/geometry"

local Shape = Pallid.UI.Shape
local PILL = Shape.roundedRect(8)
local CARD = Shape.roundedRect({ tl = 6, tr = 6, br = 0, bl = 0 })
```

### Notes
- A table radius is copied into a new table with `tl`/`tr`/`br`/`bl`, and any
  missing corner becomes 0. A partial table such as `{ tl = 6 }` therefore leaves
  the other three corners square.
- Radii are stored as given. Clamping to half the smaller side and shrinking
  overlapping corners happens at draw time.
- The radius is not a supported clip shape: `Pallid.UI.clip` rejects this kind, so
  clip with `Shape.rect` and round the drawn rectangle instead.

## Shape.polygon

Defines a polygon from normalized points.

**Side:** client

### Parameters
- points (PallidPoint[]) - At least three points, each a table with numeric `x`
  and `y` in the 0..1 range relative to the draw box.

### Returns
- PallidShape or nil - Shape with `kind = "polygon"`, or nil when fewer than three
  points are supplied or a point is malformed.

### Example
```lua
require "pallid/ui/api/geometry"

local Shape = Pallid.UI.Shape
local TRIANGLE = Shape.polygon({
    { x = 0.5, y = 0.0, },
    { x = 1.0, y = 1.0, },
    { x = 0.0, y = 1.0, },
})
```

### Notes
- The points are copied, so the caller's table is not retained and may be reused.
- Coordinates are fractions of the draw box, so the same shape scales with any size.
- Concavity is not checked. Filling uses a triangle fan, so a concave polygon
  renders incorrectly even though the shape is accepted.
- `nil` is returned rather than raising an error, so always check the result.

## Shape.regular

Defines a regular convex polygon.

**Side:** client

### Parameters
- sides (integer) - Number of sides, at least 3. Fractional values are floored.
- rotation (number|nil) - Rotation in degrees. Defaults to 0, which points the
  first vertex right.

### Returns
- PallidShape or nil - Polygon shape with `sides` and `rotation` set, or nil when
  fewer than three sides are requested.

### Example
```lua
require "pallid/ui/api/geometry"

local Shape = Pallid.UI.Shape
local HEX = Shape.regular(6, 0)
```

### Notes
- The shape is built from `Geometry.regularPolygonPoints`, so it is inscribed in
  the unit box and centered at (0.5, 0.5).
- `sides` drives the baked texture path in `Pallid.UI.progress`; sides 3, 4, 5, 6
  and 8 have assets, other counts fall back to a vector fan.

## Geometry.regularPolygonPoints

Generates the vertices of a regular polygon in normalized 0..1 coordinates.

**Side:** client

### Parameters
- sides (integer|nil) - Number of sides. Values below 3 return an empty table.
- rotation (number|nil) - Rotation in degrees. Defaults to 0.

### Returns
- PallidPoint[] - Points ordered by increasing angle, centered at (0.5, 0.5).

### Example
```lua
require "pallid/ui/api/geometry"

local points = Pallid.UI.Geometry.regularPolygonPoints(5, 90)
```

### Notes
- The polygon is inscribed in a circle of radius 0.5, so vertices touch the box
  edge only when an angle aligns with an axis.
- The result is a new table on every call; build it once and store it.
- Screen Y grows downward, so increasing angle rotates the shape clockwise.

## Pallid.UI.pointInRect

Tests whether a point is inside an axis-aligned rectangle.

**Side:** client

### Parameters
- x (number) - Point X.
- y (number) - Point Y.
- rx (number) - Rectangle left edge.
- ry (number) - Rectangle top edge.
- rw (number) - Rectangle width.
- rh (number) - Rectangle height.

### Returns
- boolean - True when the point is inside or exactly on an edge.

### Example
```lua
require "pallid/ui/api/geometry"

local hit = Pallid.UI.pointInRect(mouseX, mouseY, 10, 10, 120, 32)
```

### Notes
- Bounds are inclusive on all four edges.
- A negative width or height is not normalized and yields false for every point.

## Pallid.UI.pointInCircle

Tests whether a point is inside a circle.

**Side:** client

### Parameters
- x (number) - Point X.
- y (number) - Point Y.
- cx (number) - Circle center X.
- cy (number) - Circle center Y.
- r (number) - Radius in pixels.

### Returns
- boolean - True when the point is inside or exactly on the circle.

### Example
```lua
require "pallid/ui/api/geometry"

local hit = Pallid.UI.pointInCircle(mouseX, mouseY, 64, 64, 32)
```

### Notes
- A radius of zero or less returns false, so degenerate circles never hit.
- This is a pure circle test. For an ellipse, scale the point coordinates before
  calling.

## Pallid.UI.pointInPolygon

Tests whether a point is inside a polygon using the ray-casting rule.

**Side:** client

### Parameters
- x (number) - Point X.
- y (number) - Point Y.
- points (PallidPoint[]) - At least three points in absolute coordinates.

### Returns
- boolean - True when the point is inside the polygon.

### Example
```lua
require "pallid/ui/api/geometry"

local triangle = {
    { x = 0,   y = 0,  },
    { x = 100, y = 0,  },
    { x = 50,  y = 80, },
}
local hit = Pallid.UI.pointInPolygon(40, 20, triangle)
```

### Notes
- Coordinates here are absolute pixels, unlike `Shape.polygon`, whose points are
  normalized 0..1. Scale the normalized points before hit testing.
- Malformed input (not a table, fewer than three points, or a first point without
  `x`) returns false instead of raising an error.
- Only the first point is validated. A later point without numeric `x`/`y` raises an
  arithmetic error rather than returning false.
- Ray casting handles concave polygons correctly, even though filling them does not.

## Pallid.UI.rectsOverlap

Tests whether two axis-aligned rectangles intersect.

**Side:** client

### Parameters
- x1 (number) - First rectangle left.
- y1 (number) - First rectangle top.
- w1 (number) - First rectangle width.
- h1 (number) - First rectangle height.
- x2 (number) - Second rectangle left.
- y2 (number) - Second rectangle top.
- w2 (number) - Second rectangle width.
- h2 (number) - Second rectangle height.

### Returns
- boolean - True when the rectangles overlap with positive area.

### Example
```lua
require "pallid/ui/api/geometry"

local visible = Pallid.UI.rectsOverlap(0, 0, 100, 40, 90, 20, 100, 40)
```

### Notes
- The comparison is strict, so rectangles that only touch an edge or a corner do
  not overlap.
- Zero-width or zero-height rectangles never overlap anything.
- Typically used for culling and hit boxes on widget draw boxes; see
  [Widgets](ui-widget.md).
