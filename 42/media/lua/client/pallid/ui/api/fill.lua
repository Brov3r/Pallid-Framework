require "pallid/ui/internal"
require "pallid/ui/api/geometry"
require "pallid/ui/api/stroke"
require "pallid/ui/api/textures"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local I = Pallid.UI._internal

local PI = math.pi
local TAU = PI * 2
local abs, max = math.abs, math.max
local cos, sin = math.cos, math.sin

-- Fill primitives, published on Pallid.UI._internal because Pallid.UI.circle,
-- roundedRect, regularPolygon and Pallid.UI.progress share them. Not part of
-- the public API.
--
-- Pallid.UI.rect and Pallid.UI.subTexture are owned by draw.lua and
-- textures.lua and resolved at draw time: this file is required by draw.lua,
-- so referencing them at load would see nil.

local segmentsForArc = I.segmentsForArc

-- A circle radius up to this value is drawn with the 256x256 AA texture.
-- Above it the texture would be visibly soft, so the vector fan takes over.
local TEXTURE_CIRCLE_MAX_R = 96
-- Below this radius a texture quadrant has no room for meaningful AA.
local TEXTURE_CIRCLE_MIN_R = 2

-- Side counts with a baked AA texture. The texture path costs one draw call
-- instead of sides-2 triangles, so it is both smoother and cheaper.
local POLYGON_TEXTURE_SIDES = { [3] = true, [4] = true, [5] = true, [6] = true, [8] = true }
-- The bake keeps a 1/256 margin around each vertex so Lanczos has room for a
-- soft edge; scaling the box by this factor restores the exact vertex radius.
local POLYGON_TEXTURE_SCALE = 0.5 / (0.5 - 1 / 256)
-- Reused by the texture path so drawing never allocates an options table.
local POLYGON_OPTS = { mode = "stretch", rotation = 0 }

--- Draws a filled pie/ellipse sector. Angles are in radians.
--- @param el ISUIElement Target element.
--- @param cx number Center X.
--- @param cy number Center Y.
--- @param rx number Outer radius X.
--- @param ry number Outer radius Y.
--- @param a0 number Start angle in radians.
--- @param a1 number End angle in radians.
--- @param color PallidColor|nil Fill or tint color; nil means white.
--- @return boolean drawn True when the draw call rendered something.
local function fillArc(el, cx, cy, rx, ry, a0, a1, color)
    if a1 < a0 then
        a1 = a1 + TAU
    end
    local span = a1 - a0
    if span <= 0 or rx <= 0 or ry <= 0 then
        return false
    end
    if span > TAU then
        span = TAU
    end

    local steps = segmentsForArc(max(rx, ry), span)
    local step = span / steps
    local stepCos, stepSin = cos(step), sin(step)
    local ux, uy = cos(a0), sin(a0)
    local white = I.getWhiteTexture()
    if white == nil then
        return false
    end
    local r, g, b, a = I.colorParts(color)

    for _ = 1, steps do
        local nx = ux * stepCos - uy * stepSin
        local ny = ux * stepSin + uy * stepCos
        el:drawPolygon(white, cx, cy, cx + rx * ux, cy + ry * uy, cx + rx * nx, cy + ry * ny, cx, cy, r, g, b, a)
        ux, uy = nx, ny
    end
    return true
end
I.fillArc = fillArc

--- Draws one corner of a rounded rectangle. A texture quadrant is used when the
--- radius is in [TEXTURE_CIRCLE_MIN_R, TEXTURE_CIRCLE_MAX_R]; outside that range
--- the corner is a square block or a vector arc.
--- @param el ISUIElement Target element.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param r number Corner radius in pixels.
--- @param quadX integer Quadrant column, 0 or 1.
--- @param quadY integer Quadrant row, 0 or 1.
--- @param cx number Center X.
--- @param cy number Center Y.
--- @param a0 number Start angle in radians.
--- @param a1 number End angle in radians.
--- @param color PallidColor|nil Fill or tint color; nil means white.
local function drawCorner(el, x, y, r, quadX, quadY, cx, cy, a0, a1, color)
    if r <= 0 then
        return
    end
    if r < TEXTURE_CIRCLE_MIN_R then
        Pallid.UI.rect(el, x, y, r, r, color)
        return
    end
    if r <= TEXTURE_CIRCLE_MAX_R then
        local texture = Pallid.UI.Textures.get(Pallid.UI.Assets.circle)
        if texture ~= nil then
            local tw, th = texture:getWidth(), texture:getHeight()
            local halfW, halfH = tw * 0.5, th * 0.5
            Pallid.UI.subTexture(el, texture, quadX * halfW, quadY * halfH, halfW, halfH, x, y, r, r, color)
            return
        end
    end
    fillArc(el, cx, cy, r, r, a0, a1, color)
end
I.drawCorner = drawCorner

--- @param el ISUIElement Target element.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param color PallidColor|nil Fill or tint color; nil means white.
--- @return boolean True when something was drawn.
local function fillEllipse(el, x, y, w, h, color)
    local rx, ry = w * 0.5, h * 0.5
    if rx <= 0 or ry <= 0 then
        return false
    end
    if abs(rx - ry) < 0.5 and rx >= TEXTURE_CIRCLE_MIN_R and rx <= TEXTURE_CIRCLE_MAX_R then
        local texture = Pallid.UI.Textures.get(Pallid.UI.Assets.circle)
        if texture ~= nil then
            return Pallid.UI.texture(el, texture, x, y, w, h, color)
        end
    end
    return fillArc(el, x + rx, y + ry, rx, ry, 0, TAU, color)
end
I.fillEllipse = fillEllipse

--- @param el ISUIElement Target element.
--- @param white Texture White texture used as the quad fill.
--- @param cx number Center X.
--- @param cy number Center Y.
--- @param ax number First fan point X.
--- @param ay number First fan point Y.
--- @param bx number Second fan point X.
--- @param by number Second fan point Y.
--- @param r number Red component, 0..1.
--- @param g number Green component, 0..1.
--- @param b number Blue component, 0..1.
--- @param a number Alpha, 0..1.
local function fanTriangle(el, white, cx, cy, ax, ay, bx, by, r, g, b, a)
    el:drawPolygon(white, cx, cy, ax, ay, bx, by, cx, cy, r, g, b, a)
end

--- @param el ISUIElement Target element.
--- @param white Texture White texture used as the quad fill.
--- @param cx number Center X.
--- @param cy number Center Y.
--- @param arcCx number Arc center X.
--- @param arcCy number Arc center Y.
--- @param radius number Arc radius in pixels.
--- @param a0 number Start angle in radians.
--- @param a1 number End angle in radians.
--- @param r number Red component, 0..1.
--- @param g number Green component, 0..1.
--- @param b number Blue component, 0..1.
--- @param a number Alpha, 0..1.
local function fanArc(el, white, cx, cy, arcCx, arcCy, radius, a0, a1, r, g, b, a)
    if radius <= 0 or a1 <= a0 then
        return
    end
    local steps = segmentsForArc(radius, a1 - a0)
    local step = (a1 - a0) / steps
    local stepCos, stepSin = cos(step), sin(step)
    local ux, uy = cos(a0), sin(a0)
    for _ = 1, steps do
        local nx = ux * stepCos - uy * stepSin
        local ny = ux * stepSin + uy * stepCos
        fanTriangle(
            el, white, cx, cy,
            arcCx + radius * ux, arcCy + radius * uy,
            arcCx + radius * nx, arcCy + radius * ny,
            r, g, b, a
        )
        ux, uy = nx, ny
    end
end

--- Fills a rounded rectangle with non-uniform corner radii. A rectangular
--- decomposition would cover a zero-radius corner with the neighbouring
--- rounded corner, so this path uses a convex fan.
--- @param el ISUIElement Target element.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param tl number Top-left corner radius.
--- @param tr number Top-right corner radius.
--- @param br number Bottom-right corner radius.
--- @param bl number Bottom-left corner radius.
--- @param color PallidColor|nil Fill or tint color; nil means white.
--- @return boolean True when the fan was drawn.
local function fillRoundedRectFan(el, x, y, w, h, tl, tr, br, bl, color)
    local white = I.getWhiteTexture()
    if white == nil then
        return false
    end
    local r, g, b, a = I.colorParts(color)
    local cx, cy = x + w * 0.5, y + h * 0.5

    fanTriangle(el, white, cx, cy, x + tl, y, x + w - tr, y, r, g, b, a)
    fanTriangle(el, white, cx, cy, x + w, y + tr, x + w, y + h - br, r, g, b, a)
    fanTriangle(el, white, cx, cy, x + w - br, y + h, x + bl, y + h, r, g, b, a)
    fanTriangle(el, white, cx, cy, x, y + h - bl, x, y + tl, r, g, b, a)

    fanArc(el, white, cx, cy, x + w - tr, y + tr, tr, -PI * 0.5, 0, r, g, b, a)
    fanArc(el, white, cx, cy, x + w - br, y + h - br, br, 0, PI * 0.5, r, g, b, a)
    fanArc(el, white, cx, cy, x + bl, y + h - bl, bl, PI * 0.5, PI, r, g, b, a)
    fanArc(el, white, cx, cy, x + tl, y + tl, tl, PI, PI * 1.5, r, g, b, a)
    return true
end
I.fillRoundedRectFan = fillRoundedRectFan

--- Fills a convex polygon whose points are normalized to the draw box. Points
--- are 0..1. Used by Pallid.UI.progress for shapes without a baked texture and
--- as the fallback in fillRegularPolygon.
--- @param el ISUIElement Target element.
--- @param points PallidPoint[] Points, one entry per vertex.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param color PallidColor|nil Fill or tint color; nil means white.
--- @return boolean True when the fan was drawn.
local function fillPolygonFractional(el, points, x, y, w, h, color)
    local count = points and #points or 0
    if count < 3 then
        return false
    end
    local white = I.getWhiteTexture()
    if white == nil then
        return false
    end
    local r, g, b, a = I.colorParts(color)
    local px1, py1 = x + points[1].x * w, y + points[1].y * h
    for i = 2, count - 1 do
        local x2 = x + points[i].x * w
        local y2 = y + points[i].y * h
        local x3 = x + points[i + 1].x * w
        local y3 = y + points[i + 1].y * h
        el:drawPolygon(white, px1, py1, x2, y2, x3, y3, px1, py1, r, g, b, a)
    end
    return true
end
I.fillPolygonFractional = fillPolygonFractional

--- Returns the baked texture for a side count, or nil when that shape has to
--- be drawn as a triangle fan.
--- @param sides integer Number of sides, at least 3.
--- @return Texture|nil Baked texture, or nil when the shape must be fanned.
local function polygonTexture(sides)
    if not POLYGON_TEXTURE_SIDES[sides] then
        return nil
    end
    return Pallid.UI.Textures.get(Pallid.UI.Assets.polygons[sides])
end
I.polygonTexture = polygonTexture

-- Normalized point sets for polygons without a baked texture. Built once per
-- (sides, rotation) and reused: fillRegularPolygon runs inside render, so
-- rebuilding them every frame would allocate. A non-integer rotation is usually
-- animated, so it is not cached and the table stays bounded.
local polygonPointsCache = {}

--- Returns the normalized point set for a regular polygon, caching integer
--- rotations.
--- @param sides integer Number of sides, at least 3.
--- @param rotation number Degrees.
--- @return PallidPoint[] Normalized points of the polygon.
local function regularPoints(sides, rotation)
    if rotation % 1 ~= 0 then
        return Pallid.UI.Geometry.regularPolygonPoints(sides, rotation)
    end
    local key = sides .. "|" .. rotation
    local points = polygonPointsCache[key]
    if points == nil then
        points = Pallid.UI.Geometry.regularPolygonPoints(sides, rotation)
        polygonPointsCache[key] = points
    end
    return points
end

--- Fills a regular polygon inscribed in the box. A baked texture is used when
--- the side count has one and the geometry stays undistorted: at rotation 0 any
--- box is exact, at other angles the box must be square, because the texture
--- rotates rigidly with the quad while the vector fallback rotates the points
--- before any non-uniform scale.
--- @param el ISUIElement Target element.
--- @param sides integer Number of sides, at least 3.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param rotation number Degrees.
--- @param color PallidColor|nil Fill or tint color; nil means white.
--- @param points PallidPoint[]|nil Precomputed normalized points for the fallback.
--- @return boolean drawn True when the draw call rendered something.
local function fillRegularPolygon(el, sides, x, y, w, h, rotation, color, points)
    if w <= 0 or h <= 0 or sides < 3 then
        return false
    end

    local texture = polygonTexture(sides)
    if texture ~= nil and (rotation == 0 or abs(w - h) < 0.5) then
        local growX = w * POLYGON_TEXTURE_SCALE
        local growY = h * POLYGON_TEXTURE_SCALE
        POLYGON_OPTS.rotation = rotation
        return Pallid.UI.texture(
            el, texture,
            x - (growX - w) * 0.5, y - (growY - h) * 0.5, growX, growY,
            color, POLYGON_OPTS
        )
    end

    points = points or regularPoints(sides, rotation)
    if points == nil or #points < 3 then
        return false
    end
    return fillPolygonFractional(el, points, x, y, w, h, color)
end
I.fillRegularPolygon = fillRegularPolygon
