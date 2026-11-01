require "pallid/ui/internal"
require "pallid/ui/animation/util"
require "pallid/ui/api/text"
require "pallid/ui/api/color"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Anim = Pallid.UI.Anim
local I = Pallid.UI._internal
local TAU = math.pi * 2

-- Shared with Pallid.UI.text so per-character drawing resolves fonts the same
-- way the block renderer does.
local resolveFont = I.resolveFont

--- Returns the byte length of the UTF-8 sequence that starts with `byte`.
--- @param byte integer First byte of the UTF-8 sequence.
--- @return integer Byte length of the sequence.
local function charSize(byte)
    if byte >= 0xF0 then
        return 4
    end
    if byte >= 0xE0 then
        return 3
    end
    if byte >= 0xC0 then
        return 2
    end
    return 1
end

-- Per-string character slices. Animated labels draw one glyph at a time, so
-- slicing every frame would allocate on every frame; the cache pays that cost
-- once per string. Bounded because a caption could stream arbitrary text, and
-- 64 entries is far more than any real UI shows at once.
local SLICE_CACHE_MAX = 64
local sliceCache = {}
local sliceCount = 0

--- Splits a UTF-8 string into characters once per string. The returned array is
--- shared and must not be modified.
--- @param str string Text to draw.
--- @return string[] Shared array of single-character strings.
local function charSlices(str)
    local cached = sliceCache[str]
    if cached ~= nil then
        return cached
    end
    if sliceCount >= SLICE_CACHE_MAX then
        sliceCache = {}
        sliceCount = 0
    end

    local slices = {}
    local i = 1
    local length = #str
    while i <= length do
        local size = charSize(string.byte(str, i))
        slices[#slices + 1] = string.sub(str, i, i + size - 1)
        i = i + size
    end

    sliceCache[str] = slices
    sliceCount = sliceCount + 1
    return slices
end

--- Draws the wave. Split out so the caller can restore the style even when a
--- glyph draw raises.
--- @param el ISUIElement Target element.
--- @param chars string[] Pre-sliced characters.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param style PallidTextStyle Text style; create it once and reuse it.
--- @param font UIFont Game font to measure with.
--- @param time number Current time in seconds.
--- @param speed number Palette steps per second.
--- @param step number Phase shift between characters in radians.
--- @param amplitude number Vertical amplitude in pixels.
local function drawWave(el, chars, x, y, style, font, time, speed, step, amplitude)
    local manager = getTextManager()
    local drawX = x

    for index = 1, #chars do
        local char = chars[index]
        local offset = math.sin(time * speed + (index - 1) * step) * amplitude
        Pallid.UI.text(el, char, drawX, y + offset, style)
        drawX = drawX + manager:MeasureStringX(font, char)
    end
end

--- Draws a string with every character bouncing in a sine wave.
---
--- Characters are drawn one by one, so a wave of N letters costs N draw calls.
--- `x` is the left edge and `style.alignH` is ignored; `alignV` still applies
--- to each character. The style is restored before returning.
---
--- Limits, because each glyph is a separate draw: `style.wrap`, `maxWidth` and
--- `maxLines` do not apply, and `underline`, `strike`, `shadow` and `outline`
--- are drawn per character, which produces gaps or doubled edges.
--- @param el ISUIElement Target element.
--- @param str string Text to draw.
--- @param x number Left edge of the first character.
--- @param y number Top edge used as the wave origin.
--- @param style PallidTextStyle Text style. Create it once and reuse it.
--- @param time number Seconds, usually Anim.now().
--- @param amplitude number|nil Vertical amplitude in pixels. Defaults to 4.
--- @param frequency number|nil Waves per second. Defaults to 1.2.
--- @param phaseStep number|nil Phase shift between characters in radians. Defaults to 0.6.
--- @return boolean drawn True when the draw call rendered something.
function Anim.waveText(el, str, x, y, style, time, amplitude, frequency, phaseStep)
    if type(str) ~= "string" or str == "" or style == nil then
        return false
    end
    if not I.hasJava(el) then
        return false
    end

    local chars = charSlices(str)
    local font = resolveFont(style.font)
    local baseAlign = style.alignH
    style.alignH = "left"

    local ok, err = pcall(
        drawWave,
        el, chars, x, y, style, font,
        time, (frequency or 1.2) * TAU, phaseStep or 0.6, amplitude or 4
    )

    -- The style belongs to the caller: restore it even when a draw raised.
    style.alignH = baseAlign
    if not ok then
        I.logger:error("Anim.waveText: draw failed: " .. tostring(err))
        return false
    end
    return true
end

--- Draws the rainbow run. Split out so the caller can restore the style even
--- when a glyph draw raises.
--- @param el ISUIElement Target element.
--- @param chars string[] Pre-sliced characters.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param style PallidTextStyle Text style; create it once and reuse it.
--- @param font UIFont Game font to measure with.
--- @param palette PallidColor[] Color wheel to pick from.
--- @param shift integer Palette offset in steps.
--- @param baseAlpha number Alpha taken from the caller's color.
local function drawRainbow(el, chars, x, y, style, font, palette, shift, baseAlpha)
    local manager = getTextManager()
    local paletteSize = #palette
    local drawX = x

    for index = 1, #chars do
        local char = chars[index]
        style.color = Anim.alpha(palette[(index - 1 + shift) % paletteSize + 1], baseAlpha)
        Pallid.UI.text(el, char, drawX, y, style)
        drawX = drawX + manager:MeasureStringX(font, char)
    end
end

--- Draws a string where each character takes the next cached color from
--- Pallid.UI.Color.rainbow, and the whole wheel shifts over time.
---
--- One draw call per character; the per-character slices are cached per string,
--- so no substring is allocated while the text stays the same. `style.color`
--- only contributes its alpha; the hue comes from the palette.
---
--- Limits are the same as Anim.waveText: wrapping, truncation and text
--- decoration are applied per character and produce gaps.
--- @param el ISUIElement Target element.
--- @param str string Text to draw.
--- @param x number Left edge of the first character.
--- @param y number Top edge.
--- @param style PallidTextStyle Text style. Create it once and reuse it.
--- @param time number Seconds, usually Anim.now().
--- @param speed number|nil Palette steps per second. Defaults to 4.
--- @return boolean drawn True when the draw call rendered something.
function Anim.rainbowText(el, str, x, y, style, time, speed)
    if type(str) ~= "string" or str == "" or style == nil then
        return false
    end
    if not I.hasJava(el) then
        return false
    end

    local palette = Pallid.UI.Color.rainbow
    local chars = charSlices(str)
    local font = resolveFont(style.font)
    local shift = math.floor((time or 0) * (speed or 4))

    local baseColor = style.color
    local baseAlpha = baseColor and baseColor.a or 1
    local baseAlign = style.alignH
    style.alignH = "left"

    local ok, err = pcall(drawRainbow, el, chars, x, y, style, font, palette, shift, baseAlpha)

    -- The style belongs to the caller: restore it even when a draw raised.
    style.color = baseColor
    style.alignH = baseAlign
    if not ok then
        I.logger:error("Anim.rainbowText: draw failed: " .. tostring(err))
        return false
    end
    return true
end
