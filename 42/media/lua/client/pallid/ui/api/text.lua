require "pallid/ui/internal"
require "pallid/ui/api/clip"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/geometry"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local I = Pallid.UI._internal

--- @class PallidTextShadow Drop shadow options for Pallid.UI.text.
--- @field dx number Horizontal offset in pixels.
--- @field dy number Vertical offset in pixels.
--- @field color PallidColor|nil Shadow color. Defaults to black.

--- @class PallidTextOutline Outline options for Pallid.UI.text.
--- @field thickness number Outline thickness in pixels.
--- @field color PallidColor|nil Outline color. Defaults to black.

--- @class PallidTextStyle Text style used by Pallid.UI.text and Pallid.UI.measureText.
--- @field font UIFont|string|nil Game font or a key from Pallid.UI.Fonts. Defaults to UIFont.Small.
--- @field color PallidColor|nil Text color. Defaults to white.
--- @field alignH "left"|"center"|"right"|nil Horizontal anchor. Defaults to "left".
--- @field alignV "top"|"middle"|"bottom"|nil Vertical anchor. Defaults to "top".
--- @field scale number|nil Glyph scale. Defaults to 1.
--- @field bold boolean|nil Emulate a bold face by drawing a second copy one pixel right.
--- @field underline boolean|nil Draw a one-pixel rule under the text.
--- @field strike boolean|nil Draw a one-pixel rule through the text.
--- @field shadow PallidTextShadow|nil Optional drop shadow.
--- @field outline PallidTextOutline|nil Optional outline drawn as eight offset copies.
--- @field maxWidth number|nil Maximum line width in pixels. Enables truncation without wrap.
--- @field wrap boolean|nil Wrap text to maxWidth.
--- @field maxLines integer|nil Maximum wrapped lines. Requires wrap.
--- @field ellipsis boolean|string|nil Ellipsis suffix; false disables it, a string replaces "...".
--- @field lineSpacing number|nil Extra pixels between wrapped lines.

--- Prepared text layout returned by Pallid.UI.prepareText.
---
--- The table is owned by the caller. Pass the same table back as the third
--- argument of prepareText to reuse its arrays and avoid re-wrapping,
--- re-truncating and re-measuring unchanged text every frame. Drawing uses
--- Pallid.UI.textPrepared with the same style that produced the layout.
--- @class PallidPreparedText
--- @field text string Source text the layout was built from.
--- @field font UIFont Resolved font used for measuring.
--- @field scale number Glyph scale used for measuring.
--- @field maxWidth number Width budget used for layout.
--- @field wrap boolean|nil Wrapping mode used for layout.
--- @field maxLines integer|nil Maximum wrapped line count.
--- @field ellipsis boolean|string|nil Ellipsis setting used for layout.
--- @field lineSpacing number Extra spacing between wrapped lines.
--- @field lines string[]|nil Wrapped lines, or nil for a single-line layout.
--- @field single string Truncated single line; meaningful when `lines` is nil.
--- @field lineCount integer Number of drawable lines.
--- @field heights number[] Per-line pixel heights.
--- @field widths number[]|nil Per-line pixel widths, filled lazily.
--- @field widthsValid boolean True when `widths` matches the current layout.
--- @field width number Maximum line width; valid after widths are measured.
--- @field blockHeight number Total pixel height including line spacing.

--- Game fonts collected in one place.
--- @class PallidFontsModule Game fonts collected in one place.
local Fonts = {}
Pallid.UI.Fonts = Fonts

Fonts.small       = UIFont.Small
Fonts.medium      = UIFont.Medium
Fonts.large       = UIFont.Large
Fonts.massive     = UIFont.Massive
Fonts.newSmall    = UIFont.NewSmall
Fonts.newMedium   = UIFont.NewMedium
Fonts.newLarge    = UIFont.NewLarge
Fonts.code        = UIFont.Code
Fonts.codeSmall   = UIFont.CodeSmall
Fonts.codeMedium  = UIFont.CodeMedium
Fonts.codeLarge   = UIFont.CodeLarge
Fonts.dialogue    = UIFont.Dialogue
Fonts.intro       = UIFont.Intro
Fonts.handwritten = UIFont.Handwritten
Fonts.title       = UIFont.Title
Fonts.debug       = UIFont.DebugConsole
Fonts.default     = UIFont.Small

local DEFAULT_TEXT_STYLE = {}
-- Shared one-entry layout cache for plain text/measure calls. Widgets that
-- draw many different strings should pass their own cache to prepareText.
local DEFAULT_LAYOUT = {}

--- @param font UIFont|string|nil Font or a key from Pallid.UI.Fonts.
--- @return UIFont Resolved game font.
local function resolveFont(font)
    if font == nil then
        return Fonts.default
    end
    if type(font) == "string" then
        return Fonts[font] or Fonts.default
    end
    return font
end
I.resolveFont = resolveFont

--- @param s string Input string.
--- @return string[] One string per line.
local function splitLines(s)
    local lines = {}
    local start = 1
    while true do
        local newline = string.find(s, "\n", start, true)
        if newline == nil then
            lines[#lines + 1] = string.sub(s, start)
            return lines
        end
        lines[#lines + 1] = string.sub(s, start, newline - 1)
        start = newline + 1
    end
end

--- Cuts a UTF-8 string without splitting a multi-byte sequence.
--- @param s string Input string.
--- @param count integer Maximum byte count.
--- @return string Prefix that ends on a UTF-8 boundary.
local function safeSub(s, count)
    if count <= 0 then
        return ""
    end
    if count >= #s then
        return s
    end
    while count > 0 do
        local byte = string.byte(s, count + 1)
        if byte == nil or byte < 0x80 or byte >= 0xC0 then
            break
        end
        count = count - 1
    end
    return string.sub(s, 1, count)
end

--- Shortens str until it fits maxWidth together with the suffix. The cut is
--- made on a UTF-8 boundary so a multi-byte glyph is never split.
--- @param str string Text to draw.
--- @param font UIFont Game font to measure with.
--- @param maxWidth number Maximum line width in pixels.
--- @param suffix string Suffix appended when the text is cut.
--- @return string Text cut to fit together with the suffix.
local function truncateWith(str, font, maxWidth, suffix)
    if maxWidth <= 0 then
        return ""
    end
    if getTextManager():MeasureStringX(font, str) <= maxWidth then
        return str
    end

    suffix = suffix or "..."
    local suffixWidth = getTextManager():MeasureStringX(font, suffix)
    if suffixWidth > maxWidth then
        return ""
    end

    local available = maxWidth - suffixWidth
    local low, high = 0, #str
    while low < high do
        local middle = math.floor((low + high + 1) * 0.5)
        local candidate = safeSub(str, middle)
        if getTextManager():MeasureStringX(font, candidate) <= available then
            low = middle
        else
            high = middle - 1
        end
    end

    local head = safeSub(str, low)
    if head == "" then
        return suffix
    end
    return head .. suffix
end

--- @param str string Text to draw.
--- @param font UIFont Game font to measure with.
--- @param maxWidth number Maximum line width in pixels.
--- @param maxLines integer|nil Maximum number of lines.
--- @param suffix string Suffix appended when the text is cut.
--- @return string[] Wrapped lines.
local function wrapLines(str, font, maxWidth, maxLines, suffix)
    if maxWidth <= 0 then
        return { str }
    end
    local wrapped
    if maxLines ~= nil then
        wrapped = getTextManager():WrapText(font, str, maxWidth, maxLines, suffix)
    else
        wrapped = getTextManager():WrapText(font, str, maxWidth)
    end
    return splitLines(wrapped)
end

--- Resolves the suffix appended to truncated and line-limited text.
--- @param style PallidTextStyle Text style; create it once and reuse it.
--- @return string Suffix to append, empty when ellipsis is disabled.
local function ellipsisOf(style)
    if style.ellipsis == false then
        return ""
    end
    if type(style.ellipsis) == "string" then
        return style.ellipsis
    end
    return "..."
end

--- Applies the wrap/truncate rules of a style and measures the block height.
--- Shared by Pallid.UI.text and Pallid.UI.measureText: a separate copy in each
--- function is how "measures one thing, draws another" bugs appear.
--- @param str string Text to draw.
--- @param style PallidTextStyle Text style; create it once and reuse it.
--- @param font UIFont Game font to measure with.
--- @param scale number Scale multiplier.
--- @param maxWidth number Maximum line width in pixels.
--- @param lineSpacing number Extra pixels between wrapped lines.
--- @param needHeight boolean Skip the height pass when the caller anchors to the top.
--- @return string[]|nil lines Wrapped lines, or nil when the text stays on one line.
--- @return string single The (possibly truncated) line; meaningful when lines is nil.
--- @return number|nil height Block height in pixels, nil when needHeight is false.
local function layoutBlock(str, style, font, scale, maxWidth, lineSpacing, needHeight)
    local tm = getTextManager()

    if style.wrap and maxWidth > 0 then
        local suffix = ""
        if style.maxLines ~= nil then
            suffix = ellipsisOf(style)
        end
        local lines = wrapLines(str, font, maxWidth, style.maxLines, suffix)
        local height = 0
        if needHeight then
            for i = 1, #lines do
                height = height + tm:MeasureStringY(font, lines[i]) * scale
            end
            if #lines > 1 then
                height = height + lineSpacing * (#lines - 1)
            end
        end
        return lines, "", height
    end

    if maxWidth > 0 then
        str = truncateWith(str, font, maxWidth / scale, ellipsisOf(style))
    end
    if not needHeight then
        return nil, str, nil
    end
    return nil, str, tm:MeasureStringY(font, str) * scale
end

--- Fills per-line widths and the maximum line width when they are stale.
--- @param prepared PallidPreparedText Prepared layout to update.
local function ensurePreparedWidths(prepared)
    if prepared.widthsValid then
        return
    end

    local widths = prepared.widths
    if widths == nil then
        widths = {}
        prepared.widths = widths
    end

    local manager = getTextManager()
    local font = prepared.font
    local scale = prepared.scale
    local lines = prepared.lines
    local maxWidth = 0
    for i = 1, prepared.lineCount do
        local line = lines and lines[i] or prepared.single
        local width = manager:MeasureStringX(font, line) * scale
        widths[i] = width
        if width > maxWidth then
            maxWidth = width
        end
    end
    prepared.width = maxWidth
    prepared.widthsValid = true
end

--- Prepares a text layout for repeated drawing or measuring.
---
--- Pass the same `cache` table on every frame; the layout is rebuilt only when
--- the text or one of the layout-affecting style fields changes. The returned
--- table is owned by the caller and must not be shared between different text
--- contents unless that sharing is intentional.
--- @param str string Text to prepare.
--- @param style PallidTextStyle|nil Text style; only layout fields are used.
--- @param cache PallidPreparedText|nil Optional reusable layout table.
--- @return PallidPreparedText prepared Reusable prepared layout.
function Pallid.UI.prepareText(str, style, cache)
    style = style or DEFAULT_TEXT_STYLE
    if type(str) ~= "string" then
        str = ""
    end

    local font = resolveFont(style.font)
    local scale = style.scale or 1
    if scale <= 0 then
        scale = 1
    end
    local maxWidth = style.maxWidth or 0
    local lineSpacing = style.lineSpacing or 0
    local prepared = cache or {}

    if prepared.text == str
        and prepared.font == font
        and prepared.scale == scale
        and prepared.maxWidth == maxWidth
        and prepared.wrap == style.wrap
        and prepared.maxLines == style.maxLines
        and prepared.ellipsis == style.ellipsis
        and prepared.lineSpacing == lineSpacing then
        return prepared
    end

    local lines, single = layoutBlock(str, style, font, scale, maxWidth, lineSpacing, false)
    prepared.text = str
    prepared.font = font
    prepared.scale = scale
    prepared.maxWidth = maxWidth
    prepared.wrap = style.wrap
    prepared.maxLines = style.maxLines
    prepared.ellipsis = style.ellipsis
    prepared.lineSpacing = lineSpacing
    prepared.lines = lines
    prepared.single = single
    prepared.lineCount = lines and #lines or 1
    prepared.widthsValid = false

    local heights = prepared.heights
    if heights == nil then
        heights = {}
        prepared.heights = heights
    end

    local manager = getTextManager()
    local height = 0
    for i = 1, prepared.lineCount do
        local line = lines and lines[i] or single
        local lineHeight = manager:MeasureStringY(font, line) * scale
        heights[i] = lineHeight
        height = height + lineHeight
    end
    if prepared.lineCount > 1 then
        height = height + lineSpacing * (prepared.lineCount - 1)
    end
    prepared.blockHeight = height
    return prepared
end

--- Measures a prepared layout without rebuilding it.
--- @param prepared PallidPreparedText Prepared layout.
--- @return number width Maximum line width in pixels.
--- @return number height Total block height in pixels.
function Pallid.UI.measurePrepared(prepared)
    if type(prepared) ~= "table" then
        return 0, 0
    end
    ensurePreparedWidths(prepared)
    return prepared.width or 0, prepared.blockHeight or 0
end

--- Splits text into wrapped lines.
--- @param str string Text to wrap.
--- @param font UIFont|string Font or a key from Pallid.UI.Fonts.
--- @param maxWidth number Maximum line width in pixels.
--- @param maxLines integer|nil Maximum number of lines.
--- @return string[] lines Wrapped lines.
function Pallid.UI.wrapText(str, font, maxWidth, maxLines)
    font = resolveFont(font)
    if type(str) ~= "string" then
        return {}
    end
    return wrapLines(str, font, maxWidth or 0, maxLines, "")
end

--- Truncates text to maxWidth and appends an ellipsis when needed.
--- @param str string Text to truncate.
--- @param font UIFont|string Font or a key from Pallid.UI.Fonts.
--- @param maxWidth number Maximum width in pixels.
--- @return string truncated Truncated text.
function Pallid.UI.truncateText(str, font, maxWidth)
    font = resolveFont(font)
    if type(str) ~= "string" then
        return ""
    end
    return truncateWith(str, font, maxWidth or 0, "...")
end

--- @param el ISUIElement Target element.
--- @param str string Text to draw.
--- @param x number Anchor X.
--- @param y number Anchor Y.
--- @param font UIFont Game font to measure with.
--- @param r number Red component, 0..1.
--- @param g number Green component, 0..1.
--- @param b number Blue component, 0..1.
--- @param a number Alpha, 0..1.
--- @param scale number Scale multiplier.
--- @param alignH string Horizontal anchor: left, center or right.
local function drawOnce(el, str, x, y, font, r, g, b, a, scale, alignH)
    if scale == 1 then
        if alignH == "center" then
            el:drawTextCentre(str, x, y, r, g, b, a, font)
        elseif alignH == "right" then
            el:drawTextRight(str, x, y, r, g, b, a, font)
        else
            el:drawText(str, x, y, r, g, b, a, font)
        end
        return
    end

    local width = getTextManager():MeasureStringX(font, str) * scale
    local drawX = x
    if alignH == "center" then
        drawX = x - width * 0.5
    elseif alignH == "right" then
        drawX = x - width
    end
    el:drawTextZoomed(str, drawX, y, scale, r, g, b, a, font)
end

--- Draws one run, optionally with the synthetic bold pass.
--- @param el ISUIElement Target element.
--- @param str string Text to draw.
--- @param x number Anchor X.
--- @param y number Anchor Y.
--- @param font UIFont Game font to measure with.
--- @param r number Red component, 0..1.
--- @param g number Green component, 0..1.
--- @param b number Blue component, 0..1.
--- @param a number Alpha, 0..1.
--- @param scale number Scale multiplier.
--- @param alignH string Horizontal anchor: left, center or right.
--- @param bold boolean|nil Draw a second copy one pixel right to fake bold.
local function drawRun(el, str, x, y, font, r, g, b, a, scale, alignH, bold)
    drawOnce(el, str, x, y, font, r, g, b, a, scale, alignH)
    if bold then
        drawOnce(el, str, x + 1, y, font, r, g, b, a, scale, alignH)
    end
end

--- @param el ISUIElement Target element.
--- @param str string Text to draw.
--- @param x number Anchor X.
--- @param y number Anchor Y.
--- @param font UIFont Game font to measure with.
--- @param r number Red component, 0..1.
--- @param g number Green component, 0..1.
--- @param b number Blue component, 0..1.
--- @param a number Alpha, 0..1.
--- @param scale number Scale multiplier.
--- @param alignH string Horizontal anchor: left, center or right.
--- @param shadow PallidTextShadow|nil Optional drop shadow.
--- @param outline PallidTextOutline|nil Optional outline.
--- @param bold boolean|nil Draw a second copy one pixel right to fake bold.
local function drawStyledRun(el, str, x, y, font, r, g, b, a, scale, alignH, shadow, outline, bold)
    if shadow ~= nil then
        local sr, sg, sb, sa = I.colorParts(shadow.color or Pallid.UI.Color.black)
        drawRun(el, str, x + (shadow.dx or 0), y + (shadow.dy or 0), font, sr, sg, sb, sa, scale, alignH, bold)
    end

    if outline ~= nil then
        local thickness = outline.thickness or 1
        if thickness > 0 then
            local orr, og, ob, oa = I.colorParts(outline.color or Pallid.UI.Color.black)
            drawRun(el, str, x - thickness, y - thickness, font, orr, og, ob, oa, scale, alignH, bold)
            drawRun(el, str, x + thickness, y - thickness, font, orr, og, ob, oa, scale, alignH, bold)
            drawRun(el, str, x - thickness, y + thickness, font, orr, og, ob, oa, scale, alignH, bold)
            drawRun(el, str, x + thickness, y + thickness, font, orr, og, ob, oa, scale, alignH, bold)
            drawRun(el, str, x, y - thickness, font, orr, og, ob, oa, scale, alignH, bold)
            drawRun(el, str, x, y + thickness, font, orr, og, ob, oa, scale, alignH, bold)
            drawRun(el, str, x - thickness, y, font, orr, og, ob, oa, scale, alignH, bold)
            drawRun(el, str, x + thickness, y, font, orr, og, ob, oa, scale, alignH, bold)
        end
    end

    drawRun(el, str, x, y, font, r, g, b, a, scale, alignH, bold)
end

--- Measures a text block with the same wrapping and truncation rules as
--- Pallid.UI.text, so the returned width matches what is drawn.
--- @param str string Text to measure.
--- @param style PallidTextStyle|nil Style table; only font, scale, wrap, maxWidth, maxLines, ellipsis, lineSpacing are used.
--- @return number width Measured width in pixels.
--- @return number height Measured height in pixels.
function Pallid.UI.measureText(str, style)
    if type(str) ~= "string" then
        return 0, 0
    end
    return Pallid.UI.measurePrepared(Pallid.UI.prepareText(str, style, DEFAULT_LAYOUT))
end

--- Draws a prepared text layout. x/y are anchors selected by the style's
--- alignH/alignV; font, scale, width, wrapping and line heights come from the
--- prepared layout itself.
--- @param el ISUIElement Target element.
--- @param prepared PallidPreparedText Layout returned by Pallid.UI.prepareText.
--- @param x number Anchor X: left edge, center, or right edge depending on alignH.
--- @param y number Anchor Y: top, middle, or bottom depending on alignV.
--- @param style PallidTextStyle|nil Style supplying colour and decoration flags.
--- @return boolean drawn True when the draw call rendered something.
function Pallid.UI.textPrepared(el, prepared, x, y, style)
    if not I.hasJava(el) or type(prepared) ~= "table" then
        return false
    end
    style = style or DEFAULT_TEXT_STYLE

    local font = prepared.font or resolveFont(style.font)
    local scale = prepared.scale or 1
    if scale <= 0 then
        scale = 1
    end
    local alignH = style.alignH or "left"
    local alignV = style.alignV or "top"
    local lineSpacing = prepared.lineSpacing or 0
    local r, g, b, a = I.colorParts(style.color)

    local blockHeight = prepared.blockHeight or 0
    local startY = y
    if alignV == "middle" then
        startY = y - blockHeight * 0.5
    elseif alignV == "bottom" then
        startY = y - blockHeight
    end

    local clipX, clipY, clipW, clipH = Pallid.UI.clipRect()
    local clipX2, clipY2 = 0, 0
    if clipX ~= nil then
        clipX2 = clipX + clipW
        clipY2 = clipY + clipH
    end

    -- Widths are needed only for alignment, decoration rules and clipping.
    local needWidth = style.underline or style.strike or alignH ~= "left" or clipX ~= nil
    if needWidth then
        ensurePreparedWidths(prepared)
    end
    local widths = prepared.widths
    local lines = prepared.lines
    local heights = prepared.heights
    local lineCount = prepared.lineCount or 1
    local tm = getTextManager()

    local currentY = startY
    local hasStencil = Pallid.UI.clipHasStencil ~= nil and Pallid.UI.clipHasStencil()
    local perf = I.perf
    for i = 1, lineCount do
        local line = lines and lines[i] or prepared.single or ""
        local lineH = heights and heights[i]
        if lineH == nil then
            lineH = tm:MeasureStringY(font, line) * scale
        end
        local lineW = 0
        if needWidth then
            lineW = widths and widths[i] or (tm:MeasureStringX(font, line) * scale)
        end
        local lineX = x
        if alignH == "center" then
            lineX = x - lineW * 0.5
        elseif alignH == "right" then
            lineX = x - lineW
        end
        local draw = true

        if clipX ~= nil then
            local intersects = currentY + lineH > clipY
                and currentY < clipY2
                and lineX + lineW > clipX
                and lineX < clipX2
            if not intersects then
                draw = false
            elseif hasStencil then
                -- The engine stencil cuts the glyphs, so a line that only
                -- partly fits is still worth drawing. Dropping it made a row
                -- vanish after a one-pixel vertical scroll.
                draw = true
            elseif currentY < clipY or currentY + lineH > clipY2 then
                -- No stencil: never draw a line that straddles the clip.
                draw = false
            elseif lineX >= clipX and lineX + lineW <= clipX2 then
                draw = true
            elseif alignH == "left" and lineX >= clipX then
                local available = clipX2 - lineX
                if available <= 8 then
                    draw = false
                else
                    line = truncateWith(line, font, available / scale, "...")
                    -- The rule below the text must follow the truncated string:
                    -- the width measured before truncation would overshoot the
                    -- glyphs and run past the clip edge.
                    lineW = tm:MeasureStringX(font, line) * scale
                    lineX = x
                end
            else
                draw = false
            end
        end

        if draw then
            if perf.enabled then
                perf.textLines = perf.textLines + 1
                perf.sprites = perf.sprites + 1
            end
            drawStyledRun(
                el, line, x, currentY, font, r, g, b, a, scale, alignH,
                style.shadow, style.outline, style.bold
            )
            if lineW > 0 and (style.underline or style.strike) then
                local ruleColor = style.color or Pallid.UI.Color.white
                if style.underline then
                    Pallid.UI.rect(el, lineX, currentY + lineH - 1, lineW, 1, ruleColor)
                end
                if style.strike then
                    Pallid.UI.rect(el, lineX, currentY + lineH * 0.55, lineW, 1, ruleColor)
                end
            end
        end
        currentY = currentY + lineH + lineSpacing
    end
    return true
end

--- Draws a text block. x/y are anchors selected by alignH/alignV.
--- @param el ISUIElement Target element.
--- @param str string Text to draw.
--- @param x number Anchor X: left edge, center, or right edge depending on alignH.
--- @param y number Anchor Y: top, middle, or bottom depending on alignV.
--- @param style PallidTextStyle|nil Text style. Create it once and reuse it.
--- @return boolean drawn True when the draw call rendered something.
function Pallid.UI.text(el, str, x, y, style)
    if not I.hasJava(el) or type(str) ~= "string" then
        return false
    end
    style = style or DEFAULT_TEXT_STYLE
    return Pallid.UI.textPrepared(
        el,
        Pallid.UI.prepareText(str, style, DEFAULT_LAYOUT),
        x,
        y,
        style
    )
end
