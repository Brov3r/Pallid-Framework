require "pallid/ui/internal"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local TAU = math.pi * 2
local rad = math.rad

--- @class PallidPoint Point with absolute or normalized x/y coordinates.
--- @field x number X coordinate. For Shape polygons this is a fraction of the draw box width (0..1); for point helpers it is absolute.
--- @field y number Y coordinate. For Shape polygons this is a fraction of the draw box height (0..1); for point helpers it is absolute.

--- Shape description used by clipping and progress.
--- Create it once with Pallid.UI.Shape and reuse it every frame.
--- @class PallidShape Shape description used by clipping and progress.
--- @field kind "rect"|"circle"|"roundedRect"|"polygon" Shape kind.
--- @field radius number|table|nil Corner radius for roundedRect.
--- @field points PallidPoint[]|nil Normalized polygon points for polygon (0..1).
--- @field count integer|nil Number of polygon points.
--- @field sides integer|nil Side count when the shape came from Shape.regular.
--- @field rotation number|nil Rotation in degrees when the shape came from Shape.regular.

--- Geometry helpers.
--- @class PallidGeometryModule Geometry helpers.
local Geometry = {}
Pallid.UI.Geometry = Geometry

--- Shape constructors.
--- @class PallidShapeModule Shape constructors.
local Shape = {}
Pallid.UI.Shape = Shape

--- Generates the vertices of a regular polygon in normalized 0..1 coordinates.
--- The polygon is centered at (0.5, 0.5) and inscribed in the unit box.
--- @param sides integer Number of sides. Values below 3 return an empty table.
--- @param rotation number|nil Rotation in degrees. Defaults to 0 (first vertex points right).
--- @return PallidPoint[] points Polygon points.
function Geometry.regularPolygonPoints(sides, rotation)
    local count = math.floor(sides or 0)
    if count < 3 then
        return {}
    end

    local points = {}
    local offset = rad(rotation or 0)
    for i = 0, count - 1 do
        local angle = offset + TAU * i / count
        points[i + 1] = {
            x = 0.5 + 0.5 * math.cos(angle),
            y = 0.5 + 0.5 * math.sin(angle),
        }
    end
    return points
end

--- Defines a rectangle shape. It is clipped exactly by the game stencil.
--- @return PallidShape New rectangle shape.
function Shape.rect()
    return { kind = "rect" }
end

--- Defines a circle/ellipse shape inscribed in the draw box.
--- The game's circle stencil supports the ellipse case exactly.
--- @return PallidShape New circle shape.
function Shape.circle()
    return { kind = "circle" }
end

--- Defines a rounded rectangle shape.
--- @param radius number|table Corner radius. A number applies to all corners; a table uses {tl, tr, br, bl} fields.
--- @return PallidShape New rounded rectangle shape.
function Shape.roundedRect(radius)
    if type(radius) == "table" then
        return {
            kind = "roundedRect",
            radius = {
                tl = radius.tl or 0,
                tr = radius.tr or 0,
                br = radius.br or 0,
                bl = radius.bl or 0,
            },
        }
    end
    return { kind = "roundedRect", radius = radius or 0 }
end

--- Defines a convex polygon shape. Points are normalized to the draw box (0..1),
--- so the same shape scales with any size.
--- @param points PallidPoint[] At least three normalized points.
--- @return PallidShape|nil shape Nil when fewer than three points are supplied or a point is malformed.
function Shape.polygon(points)
    if type(points) ~= "table" or #points < 3 then
        return nil
    end

    local copy = {}
    for i = 1, #points do
        local point = points[i]
        if type(point) ~= "table" then
            return nil
        end
        local px, py = point.x, point.y
        if type(px) ~= "number" or type(py) ~= "number" then
            return nil
        end
        copy[i] = { x = px, y = py }
    end
    return { kind = "polygon", points = copy, count = #copy }
end

--- Defines a regular convex polygon shape. The extra sides/rotation fields let
--- Pallid.UI.progress use the anti-aliased texture instead of a triangle fan.
--- @param sides integer Number of sides, at least 3.
--- @param rotation number|nil Rotation in degrees. Defaults to 0.
--- @return PallidShape|nil shape Matching shape, or nil.
function Shape.regular(sides, rotation)
    local shape = Shape.polygon(Geometry.regularPolygonPoints(sides, rotation))
    if shape ~= nil then
        shape.sides = math.floor(sides)
        shape.rotation = rotation or 0
    end
    return shape
end

--- Tests whether a point is inside an axis-aligned rectangle.
--- @param x number Point X.
--- @param y number Point Y.
--- @param rx number Rectangle left.
--- @param ry number Rectangle top.
--- @param rw number Rectangle width.
--- @param rh number Rectangle height.
--- @return boolean True when the point is inside the rectangle.
function Pallid.UI.pointInRect(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

--- Tests whether a point is inside a circle.
--- @param x number Point X.
--- @param y number Point Y.
--- @param cx number Circle center X.
--- @param cy number Circle center Y.
--- @param r number Radius.
--- @return boolean True when the point is inside the circle.
function Pallid.UI.pointInCircle(x, y, cx, cy, r)
    if r <= 0 then
        return false
    end
    local dx, dy = x - cx, y - cy
    return dx * dx + dy * dy <= r * r
end

--- Tests whether a point is inside a polygon using the ray-casting rule.
--- @param x number Point X.
--- @param y number Point Y.
--- @param points PallidPoint[] Absolute polygon points.
--- @return boolean True when the point is inside the polygon.
function Pallid.UI.pointInPolygon(x, y, points)
    if type(points) ~= "table" or #points < 3 or points[1] == nil or points[1].x == nil then
        return false
    end

    local inside = false
    local j = #points
    for i = 1, #points do
        local xi, yi = points[i].x, points[i].y
        local xj, yj = points[j].x, points[j].y
        if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

--- Tests whether two axis-aligned rectangles overlap.
--- @param x1 number First rectangle left.
--- @param y1 number First rectangle top.
--- @param w1 number First rectangle width.
--- @param h1 number First rectangle height.
--- @param x2 number Second rectangle left.
--- @param y2 number Second rectangle top.
--- @param w2 number Second rectangle width.
--- @param h2 number Second rectangle height.
--- @return boolean True when the rectangles intersect.
function Pallid.UI.rectsOverlap(x1, y1, w1, h1, x2, y2, w2, h2)
    return x1 < x2 + w2 and x1 + w1 > x2 and y1 < y2 + h2 and y1 + h1 > y2
end
