require "utils/logger"

Pallid.UI = Pallid.UI or {}
Pallid.UI._internal = Pallid.UI._internal or {}

local I = Pallid.UI._internal

I.logger = Pallid.getLogger("UI")

--- OpenGL comparison enums used with SpriteRenderer.glAlphaFunc.
I.GL_GREATER = 516
I.GL_ALWAYS = 519

--- Monotonic draw-frame counter. Advanced when a root starts a frame so API
--- helpers can cache element origins without one Java round-trip per texture.
I.textureFrame = 0

--- Starts a new draw frame for per-frame texture caches.
function I.beginFrame()
    I.textureFrame = I.textureFrame + 1
end

--- Optional lightweight draw counters for the performance test tabs.
--- @class PallidPerfCounters
--- @field enabled boolean True while counters are being collected.
--- @field sprites integer Estimated sprite submissions.
--- @field textures integer Texture/subtexture submissions.
--- @field textLines integer Drawn text lines.
--- @field lines integer Vector line segments.
--- @type PallidPerfCounters
I.perf = {
    enabled   = false,
    sprites   = 0,
    textures  = 0,
    textLines = 0,
    lines     = 0,
}

--- Resets the optional draw counters.
function I.perfReset()
    local perf = I.perf
    perf.sprites = 0
    perf.textures = 0
    perf.textLines = 0
    perf.lines = 0
end

--- Returns the current optional draw counters.
--- @return integer sprites Estimated sprite submissions.
--- @return integer textures Texture/subtexture submissions.
--- @return integer textLines Drawn text lines.
--- @return integer lines Vector line segments.
function I.perfSnapshot()
    local perf = I.perf
    return perf.sprites, perf.textures, perf.textLines, perf.lines
end

--- Resolves a UI translation key, falling back to the English copy when the
--- key is missing (headless harness or a stripped install).
--- @param key string Translation key from this mod's `UI.json`.
--- @param fallback string English text used when the key has no translation.
--- @return string text Localized text, or `fallback` when the key is absent.
function I.translate(key, fallback)
    if getTextOrNull == nil then
        return fallback
    end
    return getTextOrNull(key) or fallback
end

--- Public translation helper for widgets. New widgets use this instead of
--- hard-coding user-visible English text, so every label can be translated
--- through the mod's UI.json files.
--- @param key string Translation key from this mod's `UI.json`.
--- @param fallback string English text used when the key has no translation.
--- @return string text Localized text, or `fallback` when the key is absent.
function Pallid.UI.translate(key, fallback)
    return I.translate(key, fallback)
end

--- Clamps a value into the inclusive range [lo, hi]. If lo > hi, lo wins.
--- @param value number Value to clamp.
--- @param lo number Inclusive lower bound.
--- @param hi number Inclusive upper bound.
--- @return number Clamped value.
function I.clamp(value, lo, hi)
    return math.max(lo, math.min(hi, value))
end

--- Shallow-copies a table so widget constructors never mutate the caller's
--- options table.
--- @param source table|nil Table to copy, or nil.
--- @return table copy Empty table when `source` is nil.
function I.copyTable(source)
    local copy = {}
    if source ~= nil then
        for key, value in pairs(source) do
            copy[key] = value
        end
    end
    return copy
end

--- Returns the UTF-8 sequence length for a lead byte.
--- @param byte integer First byte of a UTF-8 sequence.
--- @return integer length Sequence length in bytes.
function I.utf8Length(byte)
    if byte < 0x80 then
        return 1
    elseif byte < 0xE0 then
        return 2
    elseif byte < 0xF0 then
        return 3
    elseif byte < 0xF8 then
        return 4
    end
    return 1
end

--- Returns the UTF-16 code unit count.
--- @param str string Text to measure.
--- @return integer units UTF-16 code unit count.
function I.utf16Length(str)
    local index, units = 1, 0
    while index <= #str do
        local length = I.utf8Length(string.byte(str, index))
        units = units + (length == 4 and 2 or 1)
        index = index + length
    end
    return units
end

--- Converts a UTF-16 offset to a byte offset.
--- @param str string Source text.
--- @param units integer UTF-16 offset.
--- @return integer bytes Byte offset of the same position.
function I.utf16ToByte(str, units)
    local index, used = 1, 0
    while index <= #str and used < units do
        local length = I.utf8Length(string.byte(str, index))
        local step = (length == 4) and 2 or 1
        if used + step > units then
            break
        end
        used = used + step
        index = index + length
    end
    return index - 1
end

--- Snaps a coordinate to the nearest whole pixel. Java draw entry points cast
--- their double arguments to int, so fractional layout produces one-pixel
--- seams between neighbouring quads. Snapping edges (not sizes) keeps an
--- element flush with its right/bottom neighbour.
--- @param value number Coordinate to snap.
--- @return number Snapped coordinate.
function I.snap(value)
    return math.floor(value + 0.5)
end

--- Snaps a box to whole pixels using its edges.
--- A box with a positive size never collapses to zero (it is widened to at
--- least 1 px), but a box with a zero or negative size stays empty, so
--- zero-length elements such as an empty progress bar are not drawn.
--- @param x number X coordinate.
--- @param y number Y coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @return number x X coordinate.
--- @return number y Y coordinate.
--- @return number w Width in pixels.
--- @return number h Height in pixels.
function I.snapBox(x, y, w, h)
    local x1, y1 = I.snap(x), I.snap(y)
    if w <= 0 or h <= 0 then
        return x1, y1, 0, 0
    end
    local x2, y2 = I.snap(x + w), I.snap(y + h)
    if x2 <= x1 then
        x2 = x1 + 1
    end
    if y2 <= y1 then
        y2 = y1 + 1
    end
    return x1, y1, x2 - x1, y2 - y1
end

--- Returns true only for an instantiated ISUIElement. All drawing functions use
--- this before touching javaObject, so calling them before addToUIManager() is
--- harmless.
--- @param el ISUIElement|nil Element to test.
--- @return boolean True when the element has a Java peer.
function I.hasJava(el)
    return type(el) == "table" and el.javaObject ~= nil
end

--- Expands a color table. Missing channels default to 1, including alpha, so a
--- caller may pass { r = 1, g = 0.5, b = 0.5 } without an alpha field.
--- @param color PallidColor|nil Color to split.
--- @return number r Red component.
--- @return number g Green component.
--- @return number b Blue component.
--- @return number a Alpha component.
function I.colorParts(color)
    if color == nil then
        return 1, 1, 1, 1
    end
    return color.r or 1, color.g or 1, color.b or 1, color.a or 1
end

--- Cached engine handles. Only successful lookups are cached: a failure (for
--- example a call made before the renderer is initialised) is retried on the
--- next call instead of disabling the feature for the rest of the session.
local whiteTexture = nil
local cachedRenderer = nil

--- Set to false only when SpriteRenderer.glAlphaFunc itself is missing or
--- rejects the call. That is a property of the game build, not a timing issue,
--- so it is cached for the session.
local alphaFuncSupported = nil

--- Returns the game's 32x32 white texture. It is used for solid-color quads
--- (polygons, lines, arcs) and is cached after the first successful call.
--- @return Texture|nil Shared white texture, or nil.
function I.getWhiteTexture()
    if whiteTexture == nil then
        local ok, tex = pcall(Texture.getWhite)
        if ok and tex then
            whiteTexture = tex
        end
    end
    return whiteTexture
end

--- Returns the SpriteRenderer singleton. Used only for the alpha test threshold
--- workaround around setStencilCircle. Cached after the first successful call.
--- @return SpriteRenderer|nil Renderer for the element, or nil.
function I.getRenderer()
    if cachedRenderer == nil then
        local ok, renderer = pcall(getRenderer)
        if ok and renderer then
            cachedRenderer = renderer
        end
    end
    return cachedRenderer
end

--- Queues an alpha test function on the sprite renderer.
--- @param compare integer OpenGL comparison enum.
--- @param threshold number Alpha threshold in 0..1.
--- @return boolean applied True when the queued call was accepted.
local function queueAlpha(compare, threshold)
    if alphaFuncSupported == false then
        return false
    end

    local renderer = I.getRenderer()
    if renderer == nil then
        return false
    end

    local ok = pcall(renderer.glAlphaFunc, renderer, compare, threshold)
    if not ok then
        alphaFuncSupported = false
        return false
    end
    alphaFuncSupported = true
    return true
end

--- Queues an alpha test threshold before setStencilCircle. The game's circle
--- stencil normally runs with GL_ALWAYS, which writes the transparent corners
--- of circle.png into the stencil and turns the circle into a square.
--- GL_GREATER with 0.5 keeps only the disc.
---
--- Every successful call MUST be paired with I.restoreAlphaFunc() after the
--- stencil is set up, otherwise the altered alpha test leaks into all later
--- UI drawing. Wrap the drawing in pcall so the restore runs even on error.
--- @param compare integer OpenGL comparison enum (I.GL_GREATER).
--- @param threshold number Alpha threshold in 0..1.
--- @return boolean applied True when the queued call was accepted.
function I.queueAlphaFunc(compare, threshold)
    return queueAlpha(compare, threshold)
end

--- Restores the default alpha test (GL_ALWAYS, 0.0), which is the value
--- UIElement.clearStencilRect leaves behind.
--- @return boolean applied True when the queued call was accepted.
function I.restoreAlphaFunc()
    return queueAlpha(I.GL_ALWAYS, 0.0)
end

--- Asset paths used by Pallid.UI. Paths are relative to media/.
--- All silhouettes are white with an alpha channel, so they are tinted by the
--- color argument of Pallid.UI.texture.
--- @class PallidAssets
--- @field dir string Directory prefix for all Pallid UI textures.
--- @field circle string Filled white anti-aliased circle (256x256).
--- @field panel string Filled white rounded rectangle (256x256), used by nineSlice.
--- @field triangle string Regular 3-gon, first vertex pointing right.
--- @field square string Regular 4-gon at rotation 0, i.e. a diamond.
--- @field pentagon string Regular 5-gon.
--- @field hexagon string Regular 6-gon.
--- @field octagon string Regular 8-gon.
--- @field polygons table<integer, string> Side count to texture path. Sides without an entry are drawn as a vector fan.
local DIR = "media/assets/ui/pallid/shapes/"

local ASSETS = {
    dir      = DIR,
    circle   = DIR .. "circle.png",
    panel    = DIR .. "panel.png",
    triangle = DIR .. "triangle.png",
    square   = DIR .. "square.png",
    pentagon = DIR .. "pentagon.png",
    hexagon  = DIR .. "hexagon.png",
    octagon  = DIR .. "octagon.png",
}
ASSETS.polygons = {
    [3] = ASSETS.triangle,
    [4] = ASSETS.square,
    [5] = ASSETS.pentagon,
    [6] = ASSETS.hexagon,
    [8] = ASSETS.octagon,
}

Pallid.UI.Assets = ASSETS
