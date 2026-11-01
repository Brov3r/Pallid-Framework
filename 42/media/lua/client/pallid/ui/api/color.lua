require "pallid/ui/internal"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local I = Pallid.UI._internal

--- @class PallidColor RGBA color with components in 0..1.
--- @field r number Red component, 0..1.
--- @field g number Green component, 0..1.
--- @field b number Blue component, 0..1.
--- @field a number Alpha component, 0..1.

--- Color helpers and shared color constants.
--- @class PallidColorModule Color helpers and shared color constants.
local Color = {}
Pallid.UI.Color = Color

-- Shared with the rest of the UI layer and captured once, so the hot colour
-- paths do not pay for a table lookup.
local clamp = I.clamp

--- @param r number Red component, 0..1.
--- @param g number Green component, 0..1.
--- @param b number Blue component, 0..1.
--- @param a number Alpha, 0..1.
--- @return PallidColor New color table with r/g/b/a set.
local function make(r, g, b, a)
    return { r = r, g = g, b = b, a = a }
end

--- Creates a color from components in the 0..1 range.
--- @param r number Red, 0..1.
--- @param g number Green, 0..1.
--- @param b number Blue, 0..1.
--- @param a number|nil Alpha, 0..1. Defaults to 1.
--- @return PallidColor New color with clamped components.
function Color.new(r, g, b, a)
    return make(
        clamp(r or 0, 0, 1),
        clamp(g or 0, 0, 1),
        clamp(b or 0, 0, 1),
        clamp(a == nil and 1 or a, 0, 1)
    )
end

--- Creates a color from components in the 0..255 range.
--- @param r number Red, 0..255.
--- @param g number Green, 0..255.
--- @param b number Blue, 0..255.
--- @param a number|nil Alpha, 0..255. Defaults to 255.
--- @return PallidColor New color with components scaled to 0..1.
function Color.fromBytes(r, g, b, a)
    return make(
        clamp((r or 0) / 255, 0, 1),
        clamp((g or 0) / 255, 0, 1),
        clamp((b or 0) / 255, 0, 1),
        clamp((a == nil and 255 or a) / 255, 0, 1)
    )
end

--- Parses "#RRGGBB" or "#RRGGBBAA". The leading # is optional.
--- @param hex string Six or eight hexadecimal digits, with or without leading #.
--- @return PallidColor|nil color nil when the string is malformed.
function Color.fromHex(hex)
    if type(hex) ~= "string" then
        return nil
    end

    local value = hex
    if string.sub(value, 1, 1) == "#" then
        value = string.sub(value, 2)
    end
    if #value ~= 6 and #value ~= 8 then
        return nil
    end

    local r = tonumber(string.sub(value, 1, 2), 16)
    local g = tonumber(string.sub(value, 3, 4), 16)
    local b = tonumber(string.sub(value, 5, 6), 16)
    local a = #value == 8 and tonumber(string.sub(value, 7, 8), 16) or 255
    if r == nil or g == nil or b == nil or a == nil then
        return nil
    end
    return Color.fromBytes(r, g, b, a)
end

--- Writes an HSV color into an existing table so hot paths can reuse colors.
--- @param out PallidColor Destination table; r/g/b/a are overwritten.
--- @param h number Hue in degrees. Wraps at 360.
--- @param s number Saturation, 0..1.
--- @param v number Value, 0..1.
--- @param a number|nil Alpha, 0..1. Defaults to 1.
--- @return PallidColor out The destination table.
function Color.hsvInto(out, h, s, v, a)
    local hue = h or 0
    if hue < 0 or hue >= 360 then
        hue = hue % 360
        -- Kahlua's `%` truncates instead of flooring (see KahluaThread.primitiveMath),
        -- so a negative hue comes back negative; wrap it explicitly.
        if hue < 0 then
            hue = hue + 360 * math.ceil(-hue / 360)
        end
    end
    local sat = clamp(s or 0, 0, 1)
    local val = clamp(v or 0, 0, 1)

    local sector = hue / 60
    local index = math.floor(sector)
    local f = sector - index
    local p = val * (1 - sat)
    local q = val * (1 - f * sat)
    local t = val * (1 - (1 - f) * sat)

    local r, g, b
    if index == 0 then
        r, g, b = val, t, p
    elseif index == 1 then
        r, g, b = q, val, p
    elseif index == 2 then
        r, g, b = p, val, t
    elseif index == 3 then
        r, g, b = p, q, val
    elseif index == 4 then
        r, g, b = t, p, val
    else
        r, g, b = val, p, q
    end

    out.r, out.g, out.b = r, g, b
    out.a = clamp(a == nil and 1 or a, 0, 1)
    return out
end

--- Converts HSV to RGB.
--- @param h number Hue in degrees. Wraps at 360.
--- @param s number Saturation, 0..1.
--- @param v number Value, 0..1.
--- @param a number|nil Alpha, 0..1. Defaults to 1.
--- @return PallidColor New RGB color for the given hue.
function Color.fromHSV(h, s, v, a)
    return Color.hsvInto(make(1, 1, 1, 1), h, s, v, a)
end

--- Returns a copy of color with a different alpha.
--- @param color PallidColor|nil Source color. Nil is treated as white.
--- @param a number New alpha, 0..1.
--- @return PallidColor Copy of the color with the new alpha.
function Color.withAlpha(color, a)
    color = color or Color.white
    local r, g, b = color.r or 1, color.g or 1, color.b or 1
    return make(r, g, b, clamp(a or 1, 0, 1))
end

--- Blends `from` towards `to` and writes the result into an existing table.
--- @param out PallidColor Destination table; r/g/b/a are overwritten.
--- @param from PallidColor Color at t = 0.
--- @param to PallidColor Color at t = 1.
--- @param t number Interpolation factor, 0..1.
--- @return PallidColor out The destination table.
function Color.mixInto(out, from, to, t)
    local f = clamp(t or 0, 0, 1)
    out.r = from.r + (to.r - from.r) * f
    out.g = from.g + (to.g - from.g) * f
    out.b = from.b + (to.b - from.b) * f
    out.a = from.a + (to.a - from.a) * f
    return out
end

--- Linearly interpolates two colors.
--- @param c1 PallidColor|nil Color at t = 0. Nil is treated as white.
--- @param c2 PallidColor|nil Color at t = 1. Nil is treated as white.
--- @param t number Interpolation factor, 0..1.
--- @return PallidColor Interpolated color.
function Color.lerp(c1, c2, t)
    c1 = c1 or Color.white
    c2 = c2 or Color.white
    local f = clamp(t or 0, 0, 1)
    local r1, g1, b1, a1 = c1.r or 1, c1.g or 1, c1.b or 1, c1.a or 1
    local r2, g2, b2, a2 = c2.r or 1, c2.g or 1, c2.b or 1, c2.a or 1
    return make(
        r1 + (r2 - r1) * f,
        g1 + (g2 - g1) * f,
        b1 + (b2 - b1) * f,
        a1 + (a2 - a1) * f
    )
end

--- Picks black or white text for a background using approximate relative
--- luminance (linear coefficients, no gamma conversion).
--- @param bgColor PallidColor|nil Background color. Nil is treated as white.
--- @return PallidColor Either Color.black or Color.white.
function Color.contrastText(bgColor)
    local r, g, b = 1, 1, 1
    if bgColor ~= nil then
        r, g, b = bgColor.r or 1, bgColor.g or 1, bgColor.b or 1
    end
    local luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return luminance > 0.5 and Color.black or Color.white
end

-- Constants are allocated once at load time. UI code reads them every frame, so
-- they must never be created inside a draw call. Treat them as immutable:
-- withAlpha() and lerp() return copies, and semantic aliases below share the
-- same table as their source color.
--
-- Neutrals, light to dark. The ramp is deliberately dense: mixing two
-- neighbours with lerp() covers the values in between.
Color.white        = Color.fromHex("#FFFFFF")
Color.snow         = Color.fromHex("#FCFCFC")
Color.ivory        = Color.fromHex("#FAF7F0")
Color.offWhite     = Color.fromHex("#F5F5F0")
Color.pearl        = Color.fromHex("#EDEDEB")
Color.cloud        = Color.fromHex("#E6E6E6")
Color.mist         = Color.fromHex("#DBDBDE")
Color.silver       = Color.fromHex("#D1D1D6")
Color.lightGray    = Color.fromHex("#BFBFBF")
Color.gray         = Color.fromHex("#808080")
Color.slate        = Color.fromHex("#5C6673")
Color.gunmetal     = Color.fromHex("#4A4F54")
Color.darkGray     = Color.fromHex("#404040")
Color.graphite     = Color.fromHex("#363638")
Color.charcoal     = Color.fromHex("#29292B")
Color.obsidian     = Color.fromHex("#1A1A1C")
Color.ink          = Color.fromHex("#0D0D0F")
Color.black        = Color.fromHex("#000000")
Color.transparent  = Color.fromHex("#00000000")

-- Reds.
Color.lightRed     = Color.fromHex("#FF9999")
Color.salmon       = Color.fromHex("#FA8073")
Color.coral        = Color.fromHex("#FF804F")
Color.tomato       = Color.fromHex("#FF6347")
Color.red          = Color.fromHex("#FF0000")
Color.crimson      = Color.fromHex("#DB143D")
Color.darkRed      = Color.fromHex("#8C0D0D")
Color.maroon       = Color.fromHex("#66000D")

-- Oranges and browns.
Color.peach        = Color.fromHex("#FFCC9E")
Color.orange       = Color.fromHex("#FF8C00")
Color.amber        = Color.fromHex("#FFBF1A")
Color.darkOrange   = Color.fromHex("#CC6600")
Color.brown        = Color.fromHex("#8C5933")
Color.darkBrown    = Color.fromHex("#4C2E1A")

-- Yellows.
Color.lightYellow  = Color.fromHex("#FFFFB2")
Color.yellow       = Color.fromHex("#FFFF00")
Color.gold         = Color.fromHex("#FFD600")
Color.olive        = Color.fromHex("#808000")
Color.darkGold     = Color.fromHex("#B28C00")

-- Greens.
Color.mint         = Color.fromHex("#99FFCC")
Color.lightGreen   = Color.fromHex("#8CE68C")
Color.lime         = Color.fromHex("#80FF00")
Color.green        = Color.fromHex("#00FF00")
Color.emerald      = Color.fromHex("#4FC778")
Color.forest       = Color.fromHex("#218C21")
Color.darkGreen    = Color.fromHex("#006600")
Color.teal         = Color.fromHex("#008080")

-- Cyans and blues.
Color.cyan         = Color.fromHex("#00FFFF")
Color.aqua         = Color.fromHex("#80FFFF")
Color.sky          = Color.fromHex("#87CFEB")
Color.lightBlue    = Color.fromHex("#99CCFF")
Color.steel        = Color.fromHex("#4582B5")
Color.azure        = Color.fromHex("#0080FF")
Color.blue         = Color.fromHex("#0000FF")
Color.royalBlue    = Color.fromHex("#4069E0")
Color.darkBlue     = Color.fromHex("#00008C")
Color.navy         = Color.fromHex("#0D1A4C")
Color.indigo       = Color.fromHex("#4A0082")

-- Purples and pinks.
Color.lavender     = Color.fromHex("#CCBFF2")
Color.violet       = Color.fromHex("#994CE6")
Color.purple       = Color.fromHex("#800080")
Color.darkPurple   = Color.fromHex("#4C0059")
Color.plum         = Color.fromHex("#8C4073")
Color.pink         = Color.fromHex("#FFBFCC")
Color.hotPink      = Color.fromHex("#FF69B5")
Color.magenta      = Color.fromHex("#FF00FF")

-- Default soft pastel theme. Near-black neutrals stay untinted; only the accent,
-- status and highlight roles carry colour. Widgets read these tokens for chrome,
-- so changing the palette does not require touching every widget.
Color.background      = Color.fromHex("#1A1A1A")
Color.surface         = Color.fromHex("#222222")
Color.surfaceElevated = Color.fromHex("#2A2A2A")
Color.surfaceMuted    = Color.fromHex("#1E1E1E")
Color.border          = Color.fromHex("#3A3A3A")
Color.borderStrong    = Color.fromHex("#4D4D4D")
Color.primarySoft     = Color.fromHex("#26332F")
Color.primary         = Color.fromHex("#9BD1C1")
Color.primaryStrong   = Color.fromHex("#BCE3D5")
Color.secondarySoft   = Color.fromHex("#2D2B33")
Color.secondary       = Color.fromHex("#B9B4D6")
-- Hover backgrounds stay neutral: near-black chrome must not pick up the warm accent.
Color.accentSoft      = Color.fromHex("#2E2E2E")
Color.accent          = Color.fromHex("#E7C3B4")
Color.textPrimary     = Color.fromHex("#ECECEC")
Color.textMuted       = Color.fromHex("#B9B9B9")
Color.textDisabled    = Color.fromHex("#7C7C7C")
Color.success         = Color.fromHex("#AEDCB6")
Color.warning         = Color.fromHex("#E8D4A2")
Color.error           = Color.fromHex("#E9B4B4")
Color.info            = Color.fromHex("#B3CCE8")
Color.focusRing       = Color.fromHex("#BCE3D5")

-- Semantic aliases. They point at the same cached tables, so mutating one
-- changes every alias; derive variants with withAlpha() or lerp() instead.
Color.text         = Color.textPrimary
Color.danger       = Color.error
Color.panel        = Color.surface
Color.panelBorder  = Color.border
Color.overlay      = Color.fromHex("#00000080")
Color.overlayLight = Color.fromHex("#00000040")

-- Cached hue wheel for per-character color effects. Indexing this table is
-- free; building the colors per frame would allocate.
Color.rainbow = {
    Color.fromHex("#FF2626"), -- 0°
    Color.fromHex("#FF9326"), -- 30°
    Color.fromHex("#FFFF26"), -- 60°
    Color.fromHex("#93FF26"), -- 90°
    Color.fromHex("#26FF26"), -- 120°
    Color.fromHex("#26FF93"), -- 150°
    Color.fromHex("#26FFFF"), -- 180°
    Color.fromHex("#2693FF"), -- 210°
    Color.fromHex("#2626FF"), -- 240°
    Color.fromHex("#9326FF"), -- 270°
    Color.fromHex("#FF26FF"), -- 300°
    Color.fromHex("#FF2693"), -- 330°
}
