require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/geometry"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local I = Pallid.UI._internal
local TAU = math.pi * 2

--- @class PallidProgressStyle Style options for Pallid.UI.progress.
--- @field mode "linear"|"radial"|"outline"|nil Progress mode. Defaults to "linear".
--- @field direction "left"|"right"|"up"|"down"|nil Linear fill direction. Defaults to "right".
--- @field startAngle number|nil Radial start angle in degrees. Defaults to -90 (top).
--- @field clockwise boolean|nil Radial direction. Defaults to true.
--- @field fg PallidColor|nil Fill color. Defaults to white.
--- @field bg PallidColor|nil Track color. Defaults to a gray.
--- @field trackAlpha number|nil Track alpha override. Defaults to 0.22 when bg is omitted, or to bg.a (1 when bg has no a) when bg is supplied.
--- @field thickness number|nil Outline thickness in pixels. Defaults to 3.

local DEFAULT_PROGRESS_STYLE = {}
local RECT_SHAPE = { kind = "rect" }
local TRACK = Pallid.UI.Color.surfaceMuted
local SCRATCH = { r = 1, g = 1, b = 1, a = 1 }

--- Fills a shape with a flat color. Shape is one of rect, circle, roundedRect,
--- or polygon. rect uses drawRect, circle and roundedRect use the AA circle
--- texture with vector fallbacks, and polygon uses a baked AA texture for
--- regular shapes (3/4/5/6/8 sides) or a triangle fan otherwise.
--- @param el ISUIElement Target element.
--- @param shape PallidShape Shape created with Pallid.UI.Shape.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param color PallidColor|nil Fill or tint color; nil means white.
--- @return boolean True when the shape was filled.
local function drawShapeFill(el, shape, x, y, w, h, color)
    local kind = shape.kind
    if kind == "rect" then
        return Pallid.UI.rect(el, x, y, w, h, color)
    elseif kind == "circle" then
        return I.fillEllipse(el, x, y, w, h, color)
    elseif kind == "roundedRect" then
        return Pallid.UI.roundedRect(el, x, y, w, h, shape.radius, color)
    elseif kind == "polygon" then
        if shape.sides ~= nil then
            return I.fillRegularPolygon(el, shape.sides, x, y, w, h, shape.rotation or 0, color, shape.points)
        end
        return I.fillPolygonFractional(el, shape.points, x, y, w, h, color)
    end
    return false
end

--- Draws a track and a fill in one call.
--- Linear mode works for every supported shape by clipping a rectangular band
--- with the game stencil. Radial mode is a filled pie and requires Shape.circle.
--- Outline mode strokes the vector perimeter; it works for rect, roundedRect,
--- circle, and polygon (including Shape.regular).
--- @param el ISUIElement Target element.
--- @param shape PallidShape|nil Shape created with Pallid.UI.Shape.
--- @param x number Left coordinate, local to the element.
--- @param y number Top coordinate, local to the element.
--- @param w number Width in pixels. Must be positive.
--- @param h number Height in pixels. Must be positive.
--- @param fraction number Completion, 0..1. Values outside the range are clamped.
--- @param style PallidProgressStyle|nil Style table. Create it once and reuse it.
--- @return boolean drawn True when the draw call rendered something.
--- @return string|nil reason Set when the shape/mode combination is unsupported.
function Pallid.UI.progress(el, shape, x, y, w, h, fraction, style)
    if not I.hasJava(el) then
        return false, "invalid element"
    end
    if shape == nil or shape.kind == nil then
        return false, "no shape"
    end
    if w <= 0 or h <= 0 then
        return false, "empty box"
    end

    style = style or DEFAULT_PROGRESS_STYLE
    local value = I.clamp(fraction or 0, 0, 1)
    local mode = style.mode or "linear"
    local fg = style.fg or Pallid.UI.Color.white
    local bg = style.bg or TRACK
    local trackAlpha = style.bg ~= nil and (style.trackAlpha or bg.a or 1) or (style.trackAlpha or 0.22)
    local track = SCRATCH
    track.r = bg.r or 1
    track.g = bg.g or 1
    track.b = bg.b or 1
    track.a = trackAlpha

    if mode == "linear" then
        if not drawShapeFill(el, shape, x, y, w, h, track) then
            return false, "could not draw the progress track"
        end
        if value <= 0 then
            return true
        end
        if value >= 1 then
            if not drawShapeFill(el, shape, x, y, w, h, fg) then
                return false, "shape fill failed"
            end
            return true
        end

        local direction = style.direction or "right"
        local bandX, bandY, bandW, bandH = x, y, w, h
        if direction == "left" then
            bandX = x + w * (1 - value)
            bandW = w * value
        elseif direction == "up" then
            bandY = y + h * (1 - value)
            bandH = h * value
        elseif direction == "down" then
            bandH = h * value
        else
            bandW = w * value
        end

        local entered = Pallid.UI.clip(el, RECT_SHAPE, bandX, bandY, bandW, bandH)
        if not entered then
            return false, "could not push the progress clip"
        end

        -- The stencil must be popped even when the fill raises: a leaked stencil
        -- level keeps clipping every later draw call on the element.
        local ok, drawn = pcall(drawShapeFill, el, shape, x, y, w, h, fg)
        Pallid.UI.clipEnd(el)
        if not ok then
            I.logger:error("progress: shape fill failed: " .. tostring(drawn))
            return false, "shape fill failed"
        end
        if not drawn then
            return false, "shape fill failed"
        end
        return true
    end

    if mode == "radial" then
        if shape.kind ~= "circle" then
            return false, "radial mode requires Shape.circle"
        end
        local rx, ry = w * 0.5, h * 0.5
        local cx, cy = x + rx, y + ry
        if not I.fillArc(el, cx, cy, rx, ry, 0, TAU, track) then
            return false, "could not draw the radial track"
        end
        if value <= 0 then
            return true
        end
        local startAngle = math.rad(style.startAngle or -90)
        local span = TAU * value
        local a0, a1
        if style.clockwise == false then
            a0, a1 = startAngle - span, startAngle
        else
            a0, a1 = startAngle, startAngle + span
        end
        return I.fillArc(el, cx, cy, rx, ry, a0, a1, fg)
    end

    if mode == "outline" then
        local thickness = style.thickness or 3
        local kind = shape.kind

        if kind == "circle" then
            local rx, ry = w * 0.5, h * 0.5
            local perimeter = I.ellipsePerimeter(rx, ry)
            I.strokeArc(el, x + rx, y + ry, rx, ry, thickness, 0, TAU, track, nil)
            if value > 0 then
                I.strokeArc(el, x + rx, y + ry, rx, ry, thickness, 0, TAU * value, fg, perimeter * value)
            end
            return true
        end

        if kind == "rect" or kind == "roundedRect" then
            local tl, tr, br, bl
            if kind == "rect" then
                tl, tr, br, bl = 0, 0, 0, 0
            else
                tl, tr, br, bl = I.radii(shape.radius, w, h)
            end
            local perimeter = I.roundedRectPerimeter(w, h, tl, tr, br, bl)
            I.strokeRoundedRectPath(el, x, y, w, h, tl, tr, br, bl, thickness, track, nil)
            if value > 0 then
                I.strokeRoundedRectPath(el, x, y, w, h, tl, tr, br, bl, thickness, fg, perimeter * value)
            end
            return true
        end

        if kind == "polygon" then
            local perimeter = I.polygonPerimeter(shape.points, x, y, w, h)
            I.strokePolylineFractional(el, shape.points, x, y, w, h, thickness, track, true, nil)
            if value > 0 then
                I.strokePolylineFractional(el, shape.points, x, y, w, h, thickness, fg, true, perimeter * value)
            end
            return true
        end

        return false, "unsupported shape kind: " .. tostring(kind)
    end

    return false, "unsupported progress mode: " .. tostring(mode)
end
