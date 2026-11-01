require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/inputtext"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local Color = Pallid.UI.Color

local PANEL_W = 270
local PANEL_H = 334
local SV_X, SV_Y, SV_W, SV_H = 12, 12, 196, 176
local HUE_X, HUE_Y, HUE_W, HUE_H = 218, 12, 16, SV_H
local ALPHA_X, ALPHA_Y, ALPHA_W, ALPHA_H = 242, 12, 16, SV_H
local LABEL_Y = 200
local INPUT_Y, INPUT_H = 212, 24
local HEX_X, HEX_W = 12, 96
local FIELD_W = 30
local R_X, G_X, B_X, A_X = 116, 152, 188, 224
local PREVIEW_X, PREVIEW_Y = 12, 248
local PREVIEW_W, PREVIEW_H = PANEL_W - 24, 30
local PALETTE_SIZE = 14
local PALETTE_GAP = 4
local PALETTE_COLS = 13
local PALETTE_X = 20
local PALETTE_Y = 290
local SV_COLS, SV_ROWS = 22, 16
local HUE_STEPS = 20
local ALPHA_STEPS = 20
local CHECK_A = Color.surfaceMuted
local CHECK_B = Color.background

-- Quick picks below the preview. The list is intentionally opaque: a
-- transparent entry would need a checker behind every cell.
local PALETTE = {
    Color.white, Color.silver, Color.gray, Color.darkGray, Color.black,
    Color.red, Color.coral, Color.orange, Color.amber, Color.yellow,
    Color.lime, Color.emerald, Color.teal,
    Color.cyan, Color.sky, Color.steel, Color.blue, Color.indigo,
    Color.violet, Color.purple, Color.magenta, Color.hotPink, Color.pink,
    Color.brown, Color.primary, Color.error,
}

-- The hue strip never changes, so its colours are built once at load.
local HUE_COLORS = {}
for i = 0, HUE_STEPS - 1 do
    HUE_COLORS[i + 1] = Color.fromHSV((i + 0.5) / HUE_STEPS * 360, 1, 1, 1)
end

--- @param value number Value to process.
--- @return number clamped Value limited to 0..1.
local function clamp01(value)
    if value < 0 then
        return 0
    end
    if value > 1 then
        return 1
    end
    return value
end

--- @param value number Color component in 0..1.
--- @return integer byte Component rounded to 0..255.
local function byteOf(value)
    return math.floor(clamp01(value or 0) * 255 + 0.5)
end

--- @param color PallidColor Color to use.
--- @return number h Hue in degrees, 0..360.
--- @return number s Saturation, 0..1.
--- @return number v Value, 0..1.
local function rgbToHsv(color)
    local r, g, b = color.r or 0, color.g or 0, color.b or 0
    local maxc = math.max(r, g, b)
    local minc = math.min(r, g, b)
    local d = maxc - minc
    local h = 0
    if d ~= 0 then
        if maxc == r then
            h = ((g - b) / d) % 6
            -- Kahlua's `%` truncates instead of flooring (see
            -- KahluaThread.primitiveMath), so red-magenta colors would keep a
            -- negative hue and the marker would leave the bar.
            if h < 0 then
                h = h + 6
            end
        elseif maxc == g then
            h = (b - r) / d + 2
        else
            h = (r - g) / d + 4
        end
        h = h * 60
    end
    local s = maxc == 0 and 0 or d / maxc
    return h, s, maxc
end

--- @param color PallidColor Color to copy.
--- @return PallidColor copy Clamped independent copy.
local function copyColor(color)
    return {
        r = clamp01(color.r or 0),
        g = clamp01(color.g or 0),
        b = clamp01(color.b or 0),
        a = clamp01(color.a or 1),
    }
end

--- @param el ISUIElement Host element.
--- @param x number Left edge.
--- @param y number Top edge.
--- @param w number Width.
--- @param h number Height.
--- @param cell number Checker cell size.
local function drawChecker(el, x, y, w, h, cell)
    Pallid.UI.checker(el, x, y, w, h, cell, CHECK_A, CHECK_B)
end

--- Integer cell bounds for a gradient strip. Fractional edges are truncated by
--- the engine, which left one-pixel gaps that read as vertical black lines.
--- @param start number Strip offset along the axis.
--- @param total number Strip length in pixels.
--- @param parts integer Number of cells.
--- @param index integer Zero-based cell index.
--- @return number offset Cell offset from the strip start.
--- @return number size Cell size in pixels.
local function cellSpan(start, total, parts, index)
    local a = math.floor(index * total / parts + 0.5)
    local b = math.floor((index + 1) * total / parts + 0.5)
    return start + a, math.max(1, b - a)
end

--- @param index integer 1-based palette index.
--- @return number x Left offset inside the panel.
--- @return number y Top offset inside the panel.
local function paletteCell(index)
    local column = (index - 1) % PALETTE_COLS
    local row = math.floor((index - 1) / PALETTE_COLS)
    return PALETTE_X + column * (PALETTE_SIZE + PALETTE_GAP),
        PALETTE_Y + row * (PALETTE_SIZE + PALETTE_GAP)
end

--- Floating HSV picker with an SV square, vertical hue/alpha bars, HEX and
--- R/G/B/A inputs and a full-width preview. Owned by a `PallidColorPicker`
--- swatch and shown inside a popover.
--- @class PallidColorPickerPanel : PallidWidget
--- @field color PallidColor Authoritative RGBA color.
--- @field hue number Current hue in degrees, 0..360.
--- @field saturation number Current saturation, 0..1.
--- @field value number Current value, 0..1.
--- @field alphaValue number Current alpha, 0..1.
--- @field dragging string|nil Active region: "sv", "hue", "alpha" or nil.
--- @field onChange fun(panel: PallidColorPickerPanel, color: PallidColor)|nil
local Panel = Widgets.class("ColorPickerPanel")

--- Panel width in pixels, used by the owning popover.
Panel.WIDTH = PANEL_W
--- Panel height in pixels, used by the owning popover.
Panel.HEIGHT = PANEL_H

--- Wraps an input's blur so the panel can canonicalize its text.
--- @param input PallidInputBase Input to wrap.
--- @param handler fun(panel: PallidColorPickerPanel) Callback owned by the panel.
local function installBlur(input, handler)
    local base = input.onBlur
    input.onBlur = function(selfInput)
        base(selfInput)
        local panel = selfInput.parent
        if panel ~= nil and not panel._blurring then
            handler(panel)
        end
    end
end

--- Creates a new `Panel` instance.
--- @param color PallidColor Initial color.
--- @param onChange fun(panel: PallidColorPickerPanel, color: PallidColor)|nil Change callback.
--- @return PallidColorPickerPanel panel New picker panel.
function Panel.new(color, onChange)
    local self = setmetatable({}, Panel)
    self:init(0, 0, PANEL_W, PANEL_H)

    self.onChange = onChange
    self.dragging = nil
    self._syncing = false
    self._blurring = false
    self._hexValid = true
    self._svHue = nil
    self._lastR, self._lastG, self._lastB, self._lastA = nil, nil, nil, nil
    self._lastHexText = nil

    self.hue, self.saturation, self.value = 0, 1, 1
    self.alphaValue = 1
    self.color = { r = 1, g = 1, b = 1, a = 1 }

    -- Per-cell colors are filled in place on input, so draw never allocates.
    self._svColors = {}
    for i = 1, SV_COLS * SV_ROWS do
        self._svColors[i] = { r = 0, g = 0, b = 0, a = 1 }
    end
    self._alphaColors = {}
    for i = 1, ALPHA_STEPS do
        self._alphaColors[i] = { r = 0, g = 0, b = 0, a = 1 }
    end

    self.labelStyle = {
        font   = Pallid.UI.Fonts.small,
        color  = Color.textMuted,
        alignH = "left",
        alignV = "middle",
    }

    self.hexInput = Widgets.inputText(HEX_X, INPUT_Y, HEX_W, INPUT_H, {
        text           = "#FFFFFFFF",
        maxLength      = 9,
        forceUpperCase = true,
        placeholder    = "#RRGGBBAA",
        paddingX       = 6,
        onChange       = function(_, text)
            self:_onHexChanged(text)
        end,
    })
    self.rInput = Widgets.inputText(R_X, INPUT_Y, FIELD_W, INPUT_H, {
        text      = "0",
        maxLength = 3,
        numeric   = true,
        paddingX  = 4,
        onChange  = function(_, text)
            self:_onChannelChanged("r", text)
        end,
    })
    self.gInput = Widgets.inputText(G_X, INPUT_Y, FIELD_W, INPUT_H, {
        text      = "0",
        maxLength = 3,
        numeric   = true,
        paddingX  = 4,
        onChange  = function(_, text)
            self:_onChannelChanged("g", text)
        end,
    })
    self.bInput = Widgets.inputText(B_X, INPUT_Y, FIELD_W, INPUT_H, {
        text      = "0",
        maxLength = 3,
        numeric   = true,
        paddingX  = 4,
        onChange  = function(_, text)
            self:_onChannelChanged("b", text)
        end,
    })
    self.aInput = Widgets.inputText(A_X, INPUT_Y, FIELD_W, INPUT_H, {
        text      = "255",
        maxLength = 3,
        numeric   = true,
        paddingX  = 4,
        onChange  = function(_, text)
            self:_onChannelChanged("a", text)
        end,
    })

    self._inputs = { self.hexInput, self.rInput, self.gInput, self.bInput, self.aInput }
    for i = 1, #self._inputs do
        self:add(self._inputs[i])
    end

    self._inputBorder = self.hexInput.borderColor or Color.border
    installBlur(self.hexInput, Panel._canonicalizeHex)
    installBlur(self.rInput, Panel._canonicalizeChannel)
    installBlur(self.gInput, Panel._canonicalizeChannel)
    installBlur(self.bInput, Panel._canonicalizeChannel)
    installBlur(self.aInput, Panel._canonicalizeChannel)

    self:setColor(color or Color.primary)
    return self
end

--- Sets the color.
--- @param color PallidColor New color.
--- @return PallidColorPickerPanel self This panel, for chaining.
function Panel:setColor(color)
    return self:_setColor(color, nil, false)
end

--- Returns the current color.
--- @return PallidColor color Copy of the current color.
function Panel:getColor()
    return copyColor(self.color)
end

--- Applies a color, refreshes the cached gradients and syncs the inputs.
--- @param color PallidColor Source color.
--- @param skipKey string|nil Input key to leave untouched ("hex", "r", "g", "b", "a").
--- @param notify boolean True to fire `onChange`.
--- @return PallidColorPickerPanel self This panel, for chaining.
function Panel:_setColor(color, skipKey, notify)
    local copy = copyColor(color)
    self.color = copy
    self.hue, self.saturation, self.value = rgbToHsv(copy)
    self.alphaValue = copy.a
    self:refreshSvCache()
    self:refreshAlphaCache()
    self:syncInputs(skipKey)
    self:_setHexValid(true)
    if notify and self.onChange ~= nil then
        self.onChange(self, self.color)
    end
    return self
end

--- Rebuilds the SV grid when the hue changed.
function Panel:refreshSvCache()
    if self._svHue == self.hue then
        return
    end
    self._svHue = self.hue

    local colors = self._svColors
    local index = 0
    for row = 0, SV_ROWS - 1 do
        local v = 1 - (row + 0.5) / SV_ROWS
        for column = 0, SV_COLS - 1 do
            local s = (column + 0.5) / SV_COLS
            index = index + 1
            Color.hsvInto(colors[index], self.hue, s, v, 1)
        end
    end
end

--- Rebuilds the vertical alpha gradient for the current hue/saturation/value.
function Panel:refreshAlphaCache()
    for i = 1, ALPHA_STEPS do
        Color.hsvInto(
            self._alphaColors[i],
            self.hue,
            self.saturation,
            self.value,
            1 - (i - 0.5) / ALPHA_STEPS
        )
    end
end

--- Writes the current color into every input except `skipKey`.
--- @param skipKey string|nil Input key to leave untouched.
--- @param force boolean|nil True rewrites even when the bytes did not change.
function Panel:syncInputs(skipKey, force)
    local color = self.color
    local r, g, b, a = byteOf(color.r), byteOf(color.g), byteOf(color.b), byteOf(color.a)
    if not force and skipKey == nil
        and r == self._lastR and g == self._lastG
        and b == self._lastB and a == self._lastA then
        return
    end
    self._lastR, self._lastG, self._lastB, self._lastA = r, g, b, a

    self._syncing = true
    if skipKey ~= "hex" then
        local text = string.format("#%02X%02X%02X%02X", r, g, b, a)
        self._lastHexText = text
        self.hexInput:setText(text)
    end
    if skipKey ~= "r" then
        self.rInput:setText(tostring(r))
    end
    if skipKey ~= "g" then
        self.gInput:setText(tostring(g))
    end
    if skipKey ~= "b" then
        self.bInput:setText(tostring(b))
    end
    if skipKey ~= "a" then
        self.aInput:setText(tostring(a))
    end
    self._syncing = false

    if self._hexValid then
        self.hexInput.borderColor = self._inputBorder
    end
end

--- @param valid boolean True when the hex text parses.
function Panel:_setHexValid(valid)
    if self._hexValid == valid then
        return
    end
    self._hexValid = valid
    self.hexInput.borderColor = valid and self._inputBorder or Color.error
end

--- @param text string Current hex text.
function Panel:_onHexChanged(text)
    if self._syncing or text == self._lastHexText then
        return
    end
    local parsed = Color.fromHex(text)
    if parsed == nil then
        self:_setHexValid(false)
        return
    end
    self:_setHexValid(true)
    self._lastHexText = text
    self:_setColor(parsed, "hex", true)
end

--- @param key "r"|"g"|"b"|"a" Channel key.
--- @param text string Current field text.
function Panel:_onChannelChanged(key, text)
    if self._syncing then
        return
    end
    local value = tonumber(text)
    if value == nil then
        return
    end
    value = math.max(0, math.min(255, math.floor(value + 0.5)))
    if value == byteOf(self.color[key]) then
        return
    end

    local copy = copyColor(self.color)
    copy[key] = value / 255
    self:_setColor(copy, key, true)
end

--- Restores a canonical hex after editing or cancels an invalid value.
function Panel:_canonicalizeHex()
    local parsed = Color.fromHex(self.hexInput:getText())
    if parsed ~= nil then
        self:_setColor(parsed, nil, false)
    end
    -- Force a rewrite so partial input such as "#12" snaps back.
    self:syncInputs(nil, true)
    self:_setHexValid(true)
end

--- Restores canonical R/G/B/A values after editing.
function Panel:_canonicalizeChannel()
    self:syncInputs(nil, true)
end

--- Blurs every native input field. Used when the canvas is clicked.
function Panel:_blurInputs()
    self._blurring = true
    for i = 1, #self._inputs do
        self._inputs[i]:blur()
    end
    self._blurring = false
    self:_canonicalizeHex()
end

--- Applies SV or hue changes: RGB is rebuilt from HSV.
function Panel:_applyHsv()
    self.color = Color.fromHSV(self.hue, self.saturation, self.value, self.alphaValue)
    self.alphaValue = self.color.a
    self:refreshSvCache()
    self:refreshAlphaCache()
    self:syncInputs(nil)
    if self.onChange ~= nil then
        self.onChange(self, self.color)
    end
end

--- Applies alpha changes without rebuilding RGB.
function Panel:_applyAlpha()
    self.color.a = self.alphaValue
    self:syncInputs(nil)
    if self.onChange ~= nil then
        self.onChange(self, self.color)
    end
end

--- Returns the palette entry at the point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return PallidColor|nil color Palette color under the pointer, or nil.
function Panel:paletteAt(px, py)
    local x, y = self:originX(), self:originY()
    for i = 1, #PALETTE do
        local bx, by = paletteCell(i)
        bx, by = x + bx, y + by
        if px >= bx and px < bx + PALETTE_SIZE
            and py >= by and py < by + PALETTE_SIZE then
            return PALETTE[i]
        end
    end
    return nil
end

--- Returns the palette region at the point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return string|nil region "sv", "hue", "alpha" or nil.
function Panel:regionAt(px, py)
    local x, y = self:originX(), self:originY()
    if px >= x + SV_X and px < x + SV_X + SV_W and py >= y + SV_Y and py < y + SV_Y + SV_H then
        return "sv"
    end
    if px >= x + HUE_X and px < x + HUE_X + HUE_W and py >= y + HUE_Y and py < y + HUE_Y + HUE_H then
        return "hue"
    end
    if px >= x + ALPHA_X and px < x + ALPHA_X + ALPHA_W
        and py >= y + ALPHA_Y and py < y + ALPHA_Y + ALPHA_H then
        return "alpha"
    end
    return nil
end

--- Updates the picked color from the point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Panel:updateFromPoint(px, py)
    local x, y = self:originX(), self:originY()
    if self.dragging == "sv" then
        self.saturation = clamp01((px - x - SV_X) / SV_W)
        self.value = 1 - clamp01((py - y - SV_Y) / SV_H)
        self:_applyHsv()
    elseif self.dragging == "hue" then
        self.hue = clamp01((py - y - HUE_Y) / HUE_H) * 360
        self:_applyHsv()
    elseif self.dragging == "alpha" then
        self.alphaValue = 1 - clamp01((py - y - ALPHA_Y) / ALPHA_H)
        self:_applyAlpha()
    end
end

--- Handles a pointer press inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean handled True when the press belongs to the panel.
function Panel:onDown(px, py)
    if not self.enabled then
        return false
    end
    -- A canvas press must drop native focus, otherwise keystrokes keep going
    -- to the last R/G/B/A or hex box while the pointer drags the SV cursor.
    self:_blurInputs()
    self.dragging = nil

    local preset = self:paletteAt(px, py)
    if preset ~= nil then
        self:_setColor(preset, nil, true)
        return true
    end

    local region = self:regionAt(px, py)
    if region == nil then
        -- Consume clicks on the panel body so a stale drag cannot repaint.
        return self:isInside(px, py)
    end
    self.dragging = region
    self:updateFromPoint(px, py)
    return true
end

--- Handles pointer movement.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Panel:onMove(px, py)
    if self.dragging ~= nil then
        self:updateFromPoint(px, py)
    end
end

--- Handles a pointer release.
function Panel:onUp()
    self.dragging = nil
end

--- Clears transient interaction state before the panel is shown again.
function Panel:reset()
    self.dragging = nil
    self:_blurInputs()
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element.
function Panel:drawSelf(el)
    local x, y = self:originX(), self:originY()

    local svColors = self._svColors
    local index = 0
    for row = 0, SV_ROWS - 1 do
        local y1, ch = cellSpan(SV_Y, SV_H, SV_ROWS, row)
        for column = 0, SV_COLS - 1 do
            local x1, cw = cellSpan(SV_X, SV_W, SV_COLS, column)
            index = index + 1
            Pallid.UI.rect(el, x + x1, y + y1, cw, ch, svColors[index])
        end
    end
    Pallid.UI.border(el, x + SV_X, y + SV_Y, SV_W, SV_H, 1, Color.black)

    local cursorX = x + SV_X + self.saturation * SV_W
    local cursorY = y + SV_Y + (1 - self.value) * SV_H
    Pallid.UI.circle(el, cursorX, cursorY, 5, Color.black)
    Pallid.UI.circle(el, cursorX, cursorY, 4, Color.white)

    for i = 1, HUE_STEPS do
        local y1, ch = cellSpan(HUE_Y, HUE_H, HUE_STEPS, i - 1)
        Pallid.UI.rect(el, x + HUE_X, y + y1, HUE_W, ch, HUE_COLORS[i])
    end
    Pallid.UI.border(el, x + HUE_X, y + HUE_Y, HUE_W, HUE_H, 1, Color.black)
    local hueY = y + HUE_Y + clamp01(self.hue / 360) * HUE_H
    Pallid.UI.rect(el, x + HUE_X - 2, hueY - 1, HUE_W + 4, 3, Color.white)
    Pallid.UI.border(el, x + HUE_X - 2, hueY - 1, HUE_W + 4, 3, 1, Color.black)

    drawChecker(el, x + ALPHA_X, y + ALPHA_Y, ALPHA_W, ALPHA_H, 7)
    for i = 1, ALPHA_STEPS do
        local y1, ch = cellSpan(ALPHA_Y, ALPHA_H, ALPHA_STEPS, i - 1)
        Pallid.UI.rect(el, x + ALPHA_X, y + y1, ALPHA_W, ch, self._alphaColors[i])
    end
    Pallid.UI.border(el, x + ALPHA_X, y + ALPHA_Y, ALPHA_W, ALPHA_H, 1, Color.black)
    -- Top is opaque, bottom is transparent.
    local alphaY = y + ALPHA_Y + (1 - clamp01(self.alphaValue)) * ALPHA_H
    Pallid.UI.rect(el, x + ALPHA_X - 2, alphaY - 1, ALPHA_W + 4, 3, Color.white)
    Pallid.UI.border(el, x + ALPHA_X - 2, alphaY - 1, ALPHA_W + 4, 3, 1, Color.black)

    drawChecker(el, x + PREVIEW_X, y + PREVIEW_Y, PREVIEW_W, PREVIEW_H, 8)
    Pallid.UI.rect(el, x + PREVIEW_X, y + PREVIEW_Y, PREVIEW_W, PREVIEW_H, self.color)
    Pallid.UI.border(el, x + PREVIEW_X, y + PREVIEW_Y, PREVIEW_W, PREVIEW_H, 1, Color.black)

    -- Quick palette. The swatch matching the current RGB gets a white border.
    local r, g, b = byteOf(self.color.r), byteOf(self.color.g), byteOf(self.color.b)
    for i = 1, #PALETTE do
        local preset = PALETTE[i]
        local bx, by = paletteCell(i)
        bx, by = x + bx, y + by
        Pallid.UI.rect(el, bx, by, PALETTE_SIZE, PALETTE_SIZE, preset)
        local selected = byteOf(preset.r) == r
            and byteOf(preset.g) == g
            and byteOf(preset.b) == b
        Pallid.UI.border(el, bx, by, PALETTE_SIZE, PALETTE_SIZE, 1,
            selected and Color.white or Color.black)
    end

    local style = self.labelStyle
    style.alignH = "left"
    Pallid.UI.text(el, "HEX", x + HEX_X, y + LABEL_Y, style)
    style.alignH = "center"
    Pallid.UI.text(el, "R", x + R_X + FIELD_W * 0.5, y + LABEL_Y, style)
    Pallid.UI.text(el, "G", x + G_X + FIELD_W * 0.5, y + LABEL_Y, style)
    Pallid.UI.text(el, "B", x + B_X + FIELD_W * 0.5, y + LABEL_Y, style)
    Pallid.UI.text(el, "A", x + A_X + FIELD_W * 0.5, y + LABEL_Y, style)
    style.alignH = "left"
end

return Panel
