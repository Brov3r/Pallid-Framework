require "pallid/ui/internal"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local I = Pallid.UI._internal

local PI = math.pi
local TAU = PI * 2
local max, ceil = math.max, math.ceil
local sqrt, cos, sin = math.sqrt, math.cos, math.sin

-- Vector stroking primitives, published on Pallid.UI._internal because
-- Pallid.UI.line, polyline, ring, roundedBorder and Pallid.UI.progress all
-- share them. Not part of the public API.
--
-- The white texture is fetched through I.getWhiteTexture so a stroke costs one
-- cached lookup and one draw call per segment/quadrant.

--- Picks the triangle count for an arc: larger radii and wider spans get more
--- segments, capped so a per-frame arc stays cheap.
--- @param radius number Arc radius in pixels.
--- @param span number Radians.
--- @return integer Number of segments to use.
local function segmentsForArc(radius, span)
    local base
    if radius < 6 then
        base = 8
    elseif radius < 20 then
        base = 16
    elseif radius < 60 then
        base = 32
    else
        base = 64
    end
    local count = ceil(base * span / TAU)
    if count < 2 then
        count = 2
    elseif count > 96 then
        count = 96
    end
    return count
end
I.segmentsForArc = segmentsForArc

--- Draws a line segment as a solid quad. Coordinates are element-local.
--- @param el ISUIElement Target element.
--- @param x1 number First point X.
--- @param y1 number First point Y.
--- @param x2 number Second point X.
--- @param y2 number Second point Y.
--- @param thickness number Stroke thickness in pixels.
--- @param color PallidColor|nil Fill or tint color; nil means white.
--- @param maxLen number|nil Stop after this many pixels along the segment.
--- @return number|nil remaining Length left when maxLen was supplied.
local function strokeSegment(el, x1, y1, x2, y2, thickness, color, maxLen)
    local dx, dy = x2 - x1, y2 - y1
    local length = sqrt(dx * dx + dy * dy)
    if length < 0.0001 or thickness <= 0 then
        return maxLen
    end

    local ex, ey = x2, y2
    local drawn = length
    if maxLen ~= nil then
        if maxLen <= 0 then
            return 0
        end
        if maxLen < length then
            local t = maxLen / length
            ex = x1 + dx * t
            ey = y1 + dy * t
            drawn = maxLen
        end
    end

    local nx = -dy / length * thickness * 0.5
    local ny = dx / length * thickness * 0.5
    local white = I.getWhiteTexture()
    if white ~= nil then
        local r, g, b, a = I.colorParts(color)
        el:drawPolygon(white, x1 + nx, y1 + ny, ex + nx, ey + ny, ex - nx, ey - ny, x1 - nx, y1 - ny, r, g, b, a)
    end

    if maxLen == nil then
        return nil
    end
    return maxLen - drawn
end
I.strokeSegment = strokeSegment

--- Draws a ring/arc strip between radius r and r - thickness.
--- @param el ISUIElement Target element.
--- @param cx number Center X.
--- @param cy number Center Y.
--- @param rx number Outer radius X.
--- @param ry number Outer radius Y.
--- @param thickness number Ring thickness.
--- @param a0 number Start angle, radians.
--- @param a1 number End angle, radians.
--- @param color PallidColor|nil Fill or tint color; nil means white.
--- @param maxLen number|nil Stop after this many pixels along the outer edge.
--- @return number|nil remaining Seconds remaining, or nil.
local function strokeArc(el, cx, cy, rx, ry, thickness, a0, a1, color, maxLen)
    if a1 < a0 then
        a1 = a1 + TAU
    end
    local span = a1 - a0
    if span <= 0 or thickness <= 0 or rx <= 0 or ry <= 0 then
        return maxLen
    end
    if span > TAU then
        span = TAU
    end

    local innerRx = max(0, rx - thickness)
    local innerRy = max(0, ry - thickness)
    local steps = segmentsForArc(max(rx, ry), span)
    local step = span / steps
    local stepCos, stepSin = cos(step), sin(step)
    local ux, uy = cos(a0), sin(a0)
    local remaining = maxLen
    local white = I.getWhiteTexture()
    if white == nil then
        return remaining
    end
    local r, g, b, a = I.colorParts(color)

    for _ = 1, steps do
        local nx = ux * stepCos - uy * stepSin
        local ny = ux * stepSin + uy * stepCos

        local drawUx, drawUy = nx, ny
        local consume = 0
        if remaining ~= nil then
            if remaining <= 0 then
                break
            end
            local ddx, ddy = rx * (nx - ux), ry * (ny - uy)
            local segmentLength = sqrt(ddx * ddx + ddy * ddy)
            if segmentLength < 0.0001 then
                segmentLength = 0.0001
            end
            consume = segmentLength
            if remaining < segmentLength then
                local t = remaining / segmentLength
                local partial = step * t
                local pCos, pSin = cos(partial), sin(partial)
                drawUx = ux * pCos - uy * pSin
                drawUy = ux * pSin + uy * pCos
                consume = remaining
            end
        end

        el:drawPolygon(
            white,
            cx + rx * ux, cy + ry * uy,
            cx + rx * drawUx, cy + ry * drawUy,
            cx + innerRx * drawUx, cy + innerRy * drawUy,
            cx + innerRx * ux, cy + innerRy * uy,
            r, g, b, a
        )

        if remaining ~= nil then
            remaining = remaining - consume
            if remaining <= 0.0001 then
                return 0
            end
        end
        ux, uy = nx, ny
    end
    return remaining
end
I.strokeArc = strokeArc

--- Perimeter of a rounded rectangle: the straight edges plus one quarter arc
--- per corner. Exact, because each corner swaps two radius-long straights for
--- a (pi/2)*r arc.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param tl number Top-left corner radius.
--- @param tr number Top-right corner radius.
--- @param br number Bottom-right corner radius.
--- @param bl number Bottom-left corner radius.
--- @return number Perimeter in pixels.
local function roundedRectPerimeter(w, h, tl, tr, br, bl)
    return 2 * (w + h) + (PI * 0.5 - 2) * (tl + tr + br + bl)
end
I.roundedRectPerimeter = roundedRectPerimeter

--- Ramanujan approximation. Exact for circles.
--- @param rx number Outer radius X.
--- @param ry number Outer radius Y.
--- @return number Approximate perimeter in pixels.
local function ellipsePerimeter(rx, ry)
    if rx <= 0 or ry <= 0 then
        return 0
    end
    return PI * (3 * (rx + ry) - sqrt((3 * rx + ry) * (rx + 3 * ry)))
end
I.ellipsePerimeter = ellipsePerimeter

--- Closed-loop length of a normalized polygon, used to stop outline progress
--- after a fraction of the perimeter.
--- @param points PallidPoint[] Points, one entry per vertex.
--- @param x number Box left coordinate.
--- @param y number Box top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @return number Closed-loop length in pixels.
local function polygonPerimeter(points, x, y, w, h)
    local count = points and #points or 0
    if count < 2 then
        return 0
    end
    local total = 0
    local px = x + points[count].x * w
    local py = y + points[count].y * h
    for i = 1, count do
        local cx = x + points[i].x * w
        local cy = y + points[i].y * h
        local dx, dy = cx - px, cy - py
        total = total + sqrt(dx * dx + dy * dy)
        px, py = cx, cy
    end
    return total
end
I.polygonPerimeter = polygonPerimeter

--- Strokes a normalized convex polygon, optionally stopping after maxLen pixels.
--- @param el ISUIElement Target element.
--- @param points PallidPoint[] Points, one entry per vertex.
--- @param x number Box left coordinate.
--- @param y number Box top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param thickness number Stroke thickness in pixels.
--- @param color PallidColor|nil Fill or tint color; nil means white.
--- @param closed boolean Connect the last point to the first.
--- @param maxLen number|nil Stop after this many pixels.
--- @return number|nil remaining Seconds remaining, or nil.
local function strokePolylineFractional(el, points, x, y, w, h, thickness, color, closed, maxLen)
    local count = points and #points or 0
    if count < 2 then
        return maxLen
    end
    local remaining = maxLen
    local px = x + points[1].x * w
    local py = y + points[1].y * h
    local last = closed and count + 1 or count
    for i = 2, last do
        local point = points[(i - 1) % count + 1]
        local cx = x + point.x * w
        local cy = y + point.y * h
        remaining = strokeSegment(el, px, py, cx, cy, thickness, color, remaining)
        if remaining ~= nil and remaining <= 0 then
            return 0
        end
        px, py = cx, cy
    end
    return remaining
end
I.strokePolylineFractional = strokePolylineFractional

--- Strokes a rounded rectangle path, optionally stopping after maxLen pixels.
--- @param el ISUIElement Target element.
--- @param x number Box left coordinate.
--- @param y number Box top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param tl number Top-left corner radius.
--- @param tr number Top-right corner radius.
--- @param br number Bottom-right corner radius.
--- @param bl number Bottom-left corner radius.
--- @param thickness number Stroke thickness in pixels.
--- @param color PallidColor|nil Fill or tint color; nil means white.
--- @param maxLen number|nil Stop after this many pixels.
--- @return number|nil remaining Seconds remaining, or nil.
local function strokeRoundedRectPath(el, x, y, w, h, tl, tr, br, bl, thickness, color, maxLen)
    local remaining = maxLen
    remaining = strokeSegment(el, x + tl, y, x + w - tr, y, thickness, color, remaining)
    if remaining ~= nil and remaining <= 0 then
        return 0
    end
    remaining = strokeArc(el, x + w - tr, y + tr, tr, tr, thickness, -PI * 0.5, 0, color, remaining)
    if remaining ~= nil and remaining <= 0 then
        return 0
    end
    remaining = strokeSegment(el, x + w, y + tr, x + w, y + h - br, thickness, color, remaining)
    if remaining ~= nil and remaining <= 0 then
        return 0
    end
    remaining = strokeArc(el, x + w - br, y + h - br, br, br, thickness, 0, PI * 0.5, color, remaining)
    if remaining ~= nil and remaining <= 0 then
        return 0
    end
    remaining = strokeSegment(el, x + w - br, y + h, x + bl, y + h, thickness, color, remaining)
    if remaining ~= nil and remaining <= 0 then
        return 0
    end
    remaining = strokeArc(el, x + bl, y + h - bl, bl, bl, thickness, PI * 0.5, PI, color, remaining)
    if remaining ~= nil and remaining <= 0 then
        return 0
    end
    remaining = strokeSegment(el, x, y + h - bl, x, y + tl, thickness, color, remaining)
    if remaining ~= nil and remaining <= 0 then
        return 0
    end
    remaining = strokeArc(el, x + tl, y + tl, tl, tl, thickness, PI, PI * 1.5, color, remaining)
    return remaining
end
I.strokeRoundedRectPath = strokeRoundedRectPath
