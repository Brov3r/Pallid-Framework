require "pallid/ui/internal"
require "pallid/ui/api/clip"
require "pallid/ui/api/fill"
require "pallid/ui/api/stroke"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local I = Pallid.UI._internal

local PI = math.pi
local TAU = PI * 2
local abs, min, max = math.abs, math.min, math.max
local floor = math.floor
local sqrt = math.sqrt

-- Whole-pixel snapping lives in core so texture helpers can use it too.
local snap, snapBox = I.snap, I.snapBox

-- Fill and stroke primitives live in fill.lua and stroke.lua: this file holds
-- the public API only. The dependencies are required above, so binding them
-- once here is safe and keeps the hot paths free of table lookups.
local fillArc            = I.fillArc
local fillEllipse        = I.fillEllipse
local fillRegularPolygon = I.fillRegularPolygon
local fillRoundedRectFan = I.fillRoundedRectFan
local drawCorner         = I.drawCorner
local strokeArc          = I.strokeArc
local strokeSegment      = I.strokeSegment

--- Draws a filled axis-aligned rectangle.
--- @param el ISUIElement Target element. Must be added to UIManager.
--- @param x number Left coordinate, local to the element.
--- @param y number Top coordinate, local to the element.
--- @param w number Width in pixels. Values <= 0 draw nothing.
--- @param h number Height in pixels. Values <= 0 draw nothing.
--- @param color PallidColor|nil Fill color. Nil means white.
--- @return boolean drawn False when the element or size is invalid.
function Pallid.UI.rect(el, x, y, w, h, color)
    if not I.hasJava(el) or w <= 0 or h <= 0 then
        return false
    end

    local cx, cy, cw, ch = Pallid.UI.clipRect()
    if cx ~= nil then
        local x2, y2 = x + w, y + h
        if x < cx then
            x = cx
        end
        if y < cy then
            y = cy
        end
        if x2 > cx + cw then
            x2 = cx + cw
        end
        if y2 > cy + ch then
            y2 = cy + ch
        end
        if x2 <= x or y2 <= y then
            return false
        end
        w = x2 - x
        h = y2 - y
    end

    x, y, w, h = snapBox(x, y, w, h)
    local r, g, b, a = I.colorParts(color)
    local perf = I.perf
    if perf.enabled then
        perf.sprites = perf.sprites + 1
    end
    el:drawRect(x, y, w, h, a, r, g, b)
    return true
end

--- Draws a checkerboard behind translucent colors. Cell edges are snapped so
--- adjacent cells touch and no dark hairlines show between them.
--- @param el ISUIElement Target element.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param cell number Preferred checker cell size in pixels.
--- @param colorA PallidColor Color of the even cells.
--- @param colorB PallidColor Color of the odd cells.
function Pallid.UI.checker(el, x, y, w, h, cell, colorA, colorB)
    if not I.hasJava(el) or w <= 0 or h <= 0 or cell <= 0 then
        return
    end
    x, y, w, h = snapBox(x, y, w, h)
    local columns = math.ceil(w / cell)
    local rows = math.ceil(h / cell)
    for row = 0, rows - 1 do
        local y1 = y + math.floor(row * h / rows)
        local y2 = y + math.floor((row + 1) * h / rows)
        for column = 0, columns - 1 do
            local x1 = x + math.floor(column * w / columns)
            local x2 = x + math.floor((column + 1) * w / columns)
            local color = ((row + column) % 2 == 0) and colorA or colorB
            Pallid.UI.rect(el, x1, y1, x2 - x1, y2 - y1, color)
        end
    end
end

--- Draws an axis-aligned rectangular outline made of four solid rectangles.
--- The outline lies inside the supplied bounds.
--- @param el ISUIElement Target element.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param thickness number Border thickness in pixels. Values <= 0 draw nothing.
--- @param color PallidColor|nil Border color. Nil means white.
--- @return boolean drawn True when the draw call rendered something.
function Pallid.UI.border(el, x, y, w, h, thickness, color)
    if not I.hasJava(el) or w <= 0 or h <= 0 or thickness <= 0 then
        return false
    end
    x, y, w, h = snapBox(x, y, w, h)
    thickness = snap(thickness)
    if thickness < 1 then
        thickness = 1
    end
    if thickness * 2 >= w or thickness * 2 >= h then
        return Pallid.UI.rect(el, x, y, w, h, color)
    end

    Pallid.UI.rect(el, x, y, w, thickness, color)
    Pallid.UI.rect(el, x, y + h - thickness, w, thickness, color)
    Pallid.UI.rect(el, x, y + thickness, thickness, h - thickness * 2, color)
    Pallid.UI.rect(el, x + w - thickness, y + thickness, thickness, h - thickness * 2, color)
    return true
end

--- Resolves corner radii into tl/tr/br/bl and shrinks them proportionally so
--- corners sharing an edge never overlap.
--- @param radius number|table|nil Corner radius or a {tl,tr,br,bl} table.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @return number tl Top-left corner radius.
--- @return number tr Top-right corner radius.
--- @return number br Bottom-right corner radius.
--- @return number bl Bottom-left corner radius.
local function radii(radius, w, h)
    local tl, tr, br, bl
    if type(radius) == "table" then
        tl = radius.tl or 0
        tr = radius.tr or tl
        br = radius.br or tl
        bl = radius.bl or tr
    else
        tl = radius or 0
        tr, br, bl = tl, tl, tl
    end

    local limit = max(0, min(w, h) * 0.5)
    tl = I.clamp(tl, 0, limit)
    tr = I.clamp(tr, 0, limit)
    br = I.clamp(br, 0, limit)
    bl = I.clamp(bl, 0, limit)

    local sum = tl + tr
    if sum > w and sum > 0 then
        local k = w / sum
        tl, tr = tl * k, tr * k
    end
    sum = bl + br
    if sum > w and sum > 0 then
        local k = w / sum
        bl, br = bl * k, br * k
    end
    sum = tl + bl
    if sum > h and sum > 0 then
        local k = h / sum
        tl, bl = tl * k, bl * k
    end
    sum = tr + br
    if sum > h and sum > 0 then
        local k = h / sum
        tr, br = tr * k, br * k
    end
    -- Whole-pixel radii keep the four texture quadrants flush with the centre
    -- rectangles; a fractional radius leaves a one-pixel seam after the
    -- engine truncates the destination box.
    return floor(tl), floor(tr), floor(br), floor(bl)
end
I.radii = radii

--- Fills a rounded rectangle. Uniform radii use AA circle texture quadrants
--- (below 2 px the corner is square, above 96 px it is a vector arc);
--- non-uniform radii always use the vector fan because a rectangular
--- decomposition would paint over zero-radius corners.
--- @param el ISUIElement Target element.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param radius number|table Corner radius. Number for all corners, or {tl, tr, br, bl}.
--- @param color PallidColor|nil Fill color.
--- @return boolean drawn True when the draw call rendered something.
function Pallid.UI.roundedRect(el, x, y, w, h, radius, color)
    if not I.hasJava(el) or w <= 0 or h <= 0 then
        return false
    end
    if Pallid.UI.isClippedOut(x, y, w, h) then
        return false
    end
    x, y, w, h = snapBox(x, y, w, h)

    local tl, tr, br, bl = radii(radius, w, h)
    if tl <= 0 and tr <= 0 and br <= 0 and bl <= 0 then
        return Pallid.UI.rect(el, x, y, w, h, color)
    end
    if tl ~= tr or tr ~= br or br ~= bl then
        return fillRoundedRectFan(el, x, y, w, h, tl, tr, br, bl, color)
    end

    Pallid.UI.rect(el, x, y + tl, w, h - tl - bl, color)
    if tl > 0 and w - tl - tr > 0 then
        Pallid.UI.rect(el, x + tl, y, w - tl - tr, tl, color)
    end
    if bl > 0 and w - bl - br > 0 then
        Pallid.UI.rect(el, x + bl, y + h - bl, w - bl - br, bl, color)
    end

    drawCorner(el, x, y, tl, 0, 0, x + tl, y + tl, PI, PI * 1.5, color)
    drawCorner(el, x + w - tr, y, tr, 1, 0, x + w - tr, y + tr, PI * 1.5, TAU, color)
    drawCorner(el, x + w - br, y + h - br, br, 1, 1, x + w - br, y + h - br, 0, PI * 0.5, color)
    drawCorner(el, x, y + h - bl, bl, 0, 1, x + bl, y + h - bl, PI * 0.5, PI, color)
    return true
end

--- Draws a rounded rectangular outline. Corners smaller than the thickness
--- become square corners so the border never double-blends at the corner.
--- @param el ISUIElement Target element.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param radius number|table Corner radius. Number for all corners, or {tl, tr, br, bl}.
--- @param thickness number Border thickness in pixels.
--- @param color PallidColor|nil Border color.
--- @return boolean drawn True when the draw call rendered something.
function Pallid.UI.roundedBorder(el, x, y, w, h, radius, thickness, color)
    if not I.hasJava(el) or w <= 0 or h <= 0 or thickness <= 0 then
        return false
    end
    if thickness * 2 >= w or thickness * 2 >= h then
        return Pallid.UI.roundedRect(el, x, y, w, h, radius, color)
    end

    x, y, w, h = snapBox(x, y, w, h)
    thickness = snap(thickness)
    if thickness < 1 then
        thickness = 1
    end
    local tl, tr, br, bl = radii(radius, w, h)
    local tlSize = max(tl, thickness)
    local trSize = max(tr, thickness)
    local brSize = max(br, thickness)
    local blSize = max(bl, thickness)

    local topStart, topEnd = x + tlSize, x + w - trSize
    if topEnd > topStart then
        Pallid.UI.rect(el, topStart, y, topEnd - topStart, thickness, color)
    end
    local bottomStart, bottomEnd = x + blSize, x + w - brSize
    if bottomEnd > bottomStart then
        Pallid.UI.rect(el, bottomStart, y + h - thickness, bottomEnd - bottomStart, thickness, color)
    end
    local leftStart, leftEnd = y + tlSize, y + h - blSize
    if leftEnd > leftStart then
        Pallid.UI.rect(el, x, leftStart, thickness, leftEnd - leftStart, color)
    end
    local rightStart, rightEnd = y + trSize, y + h - brSize
    if rightEnd > rightStart then
        Pallid.UI.rect(el, x + w - thickness, rightStart, thickness, rightEnd - rightStart, color)
    end

    if tl > 0 and tl >= thickness then
        strokeArc(el, x + tl, y + tl, tl, tl, thickness, PI, PI * 1.5, color, nil)
    else
        Pallid.UI.rect(el, x, y, thickness, thickness, color)
    end
    if tr > 0 and tr >= thickness then
        strokeArc(el, x + w - tr, y + tr, tr, tr, thickness, PI * 1.5, TAU, color, nil)
    else
        Pallid.UI.rect(el, x + w - thickness, y, thickness, thickness, color)
    end
    if br > 0 and br >= thickness then
        strokeArc(el, x + w - br, y + h - br, br, br, thickness, 0, PI * 0.5, color, nil)
    else
        Pallid.UI.rect(el, x + w - thickness, y + h - thickness, thickness, thickness, color)
    end
    if bl > 0 and bl >= thickness then
        strokeArc(el, x + bl, y + h - bl, bl, bl, thickness, PI * 0.5, PI, color, nil)
    else
        Pallid.UI.rect(el, x, y + h - thickness, thickness, thickness, color)
    end
    return true
end

--- Draws a filled circle or a pie sector.
--- @param el ISUIElement Target element.
--- @param cx number Center X.
--- @param cy number Center Y.
--- @param r number Radius in pixels.
--- @param color PallidColor|nil Fill color.
--- @param a0 number|nil Start angle in radians. Omit for a full circle.
--- @param a1 number|nil End angle in radians. Omit for a full circle.
--- @return boolean drawn True when the draw call rendered something.
function Pallid.UI.circle(el, cx, cy, r, color, a0, a1)
    if not I.hasJava(el) or r <= 0 then
        return false
    end
    if Pallid.UI.isClippedOut(cx - r, cy - r, r * 2, r * 2) then
        return false
    end
    if a0 == nil or a1 == nil then
        return fillEllipse(el, cx - r, cy - r, r * 2, r * 2, color)
    end
    return fillArc(el, cx, cy, r, r, a0, a1, color)
end

--- Draws a ring or an arc. The stroke lies inside the outer radius.
--- @param el ISUIElement Target element.
--- @param cx number Center X.
--- @param cy number Center Y.
--- @param r number Outer radius in pixels.
--- @param thickness number Ring thickness in pixels.
--- @param color PallidColor|nil Stroke color.
--- @param a0 number|nil Start angle in radians. Defaults to 0.
--- @param a1 number|nil End angle in radians. Defaults to 2*pi.
--- @return boolean drawn True when the draw call rendered something.
function Pallid.UI.ring(el, cx, cy, r, thickness, color, a0, a1)
    if not I.hasJava(el) or r <= 0 or thickness <= 0 then
        return false
    end
    if Pallid.UI.isClippedOut(cx - r, cy - r, r * 2, r * 2) then
        return false
    end
    strokeArc(el, cx, cy, r, r, thickness, a0 or 0, a1 or TAU, color, nil)
    return true
end

--- Draws a straight line with optional dash pattern.
--- The line is a solid quad and has no anti-aliasing.
--- @param el ISUIElement Target element.
--- @param x1 number Start X.
--- @param y1 number Start Y.
--- @param x2 number End X.
--- @param y2 number End Y.
--- @param thickness number Line thickness in pixels.
--- @param color PallidColor|nil Line color.
--- @param dash number|nil Dash length. Omit for a solid line.
--- @param gap number|nil Gap length. Defaults to dash.
--- @return boolean drawn True when the draw call rendered something.
function Pallid.UI.line(el, x1, y1, x2, y2, thickness, color, dash, gap)
    if not I.hasJava(el) or thickness <= 0 then
        return false
    end
    local half = thickness * 0.5
    local bx = min(x1, x2) - half
    local by = min(y1, y2) - half
    local bw = abs(x1 - x2) + thickness
    local bh = abs(y1 - y2) + thickness
    if Pallid.UI.isClippedOut(bx, by, bw, bh) then
        return false
    end
    local perf = I.perf
    if dash == nil or dash <= 0 then
        if perf.enabled then
            perf.lines = perf.lines + 1
            perf.sprites = perf.sprites + 1
        end
        strokeSegment(el, x1, y1, x2, y2, thickness, color, nil)
        return true
    end

    local dx, dy = x2 - x1, y2 - y1
    local length = sqrt(dx * dx + dy * dy)
    if length <= 0 then
        return false
    end

    gap = gap or dash
    if gap < 0 then
        gap = 0
    end
    local step = dash + gap
    if step <= 0 then
        step = dash
    end

    local position = 0
    while position < length do
        local endPosition = min(position + dash, length)
        local t0, t1 = position / length, endPosition / length
        strokeSegment(
            el,
            x1 + dx * t0, y1 + dy * t0,
            x1 + dx * t1, y1 + dy * t1,
            thickness, color, nil
        )
        position = position + step
    end
    return true
end

--- Draws a polyline through absolute points.
--- @param el ISUIElement Target element.
--- @param points PallidPoint[] Absolute points; at least two.
--- @param thickness number Line thickness in pixels.
--- @param color PallidColor|nil Line color.
--- @param closed boolean|nil Connect the last point to the first.
--- @return boolean drawn True when the draw call rendered something.
function Pallid.UI.polyline(el, points, thickness, color, closed)
    if not I.hasJava(el) or type(points) ~= "table" or #points < 2 or thickness <= 0 then
        return false
    end
    local minX, minY, maxX, maxY = points[1].x, points[1].y, points[1].x, points[1].y
    for i = 2, #points do
        local point = points[i]
        if point.x < minX then
            minX = point.x
        end
        if point.x > maxX then
            maxX = point.x
        end
        if point.y < minY then
            minY = point.y
        end
        if point.y > maxY then
            maxY = point.y
        end
    end
    if Pallid.UI.isClippedOut(minX - thickness, minY - thickness, maxX - minX + thickness * 2, maxY - minY + thickness * 2) then
        return false
    end
    for i = 1, #points - 1 do
        strokeSegment(el, points[i].x, points[i].y, points[i + 1].x, points[i + 1].y, thickness, color, nil)
    end
    if closed then
        local first, last = points[1], points[#points]
        strokeSegment(el, last.x, last.y, first.x, first.y, thickness, color, nil)
    end
    return true
end

--- Draws a filled regular polygon. Vertices lie on a circle of the given
--- radius. Side counts 3, 4, 5, 6 and 8 use an anti-aliased texture; other
--- counts fall back to a triangle fan, which leaves hard edges.
--- @param el ISUIElement Target element.
--- @param sides integer Number of sides, at least 3.
--- @param cx number Center X.
--- @param cy number Center Y.
--- @param radius number Distance from the center to each vertex.
--- @param rotation number|nil Rotation in degrees. Defaults to 0 (first vertex points right).
--- @param color PallidColor|nil Fill color. Nil means white.
--- @return boolean drawn True when the draw call rendered something.
function Pallid.UI.regularPolygon(el, sides, cx, cy, radius, rotation, color)
    if not I.hasJava(el) or radius <= 0 then
        return false
    end
    if Pallid.UI.isClippedOut(cx - radius, cy - radius, radius * 2, radius * 2) then
        return false
    end
    local count = floor(sides or 0)
    if count < 3 then
        return false
    end
    return fillRegularPolygon(
        el, count,
        cx - radius, cy - radius, radius * 2, radius * 2,
        rotation or 0, color
    )
end

--- Fills a convex polygon using a triangle fan. Points are absolute coordinates.
--- Concave polygons are not supported and may render incorrectly, and the
--- diagonals are not anti-aliased: for a regular polygon prefer
--- Pallid.UI.regularPolygon, which uses a baked AA texture.
--- @param el ISUIElement Target element.
--- @param points PallidPoint[] Absolute points; at least three.
--- @param color PallidColor|nil Fill color.
--- @return boolean drawn True when the draw call rendered something.
function Pallid.UI.polygon(el, points, color)
    if not I.hasJava(el) or type(points) ~= "table" or #points < 3 then
        return false
    end
    for i = 1, #points do
        local point = points[i]
        if type(point) ~= "table" or point.x == nil or point.y == nil then
            return false
        end
    end
    local x1, y1 = points[1].x, points[1].y
    local white = I.getWhiteTexture()
    if white == nil then
        return false
    end
    local r, g, b, a = I.colorParts(color)
    local perf = I.perf
    local triangles = math.max(0, #points - 2)
    if perf.enabled then
        perf.sprites = perf.sprites + triangles
    end
    for i = 2, #points - 1 do
        local x2, y2 = points[i].x, points[i].y
        local x3, y3 = points[i + 1].x, points[i + 1].y
        el:drawPolygon(white, x1, y1, x2, y2, x3, y3, x1, y1, r, g, b, a)
    end
    return true
end
