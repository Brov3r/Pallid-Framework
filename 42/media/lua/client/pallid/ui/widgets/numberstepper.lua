require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/inputtext"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local Textures = Pallid.UI.Textures

local ICON_DIR = "media/assets/ui/pallid/icons/"
local ICON_OPTS = { mode = "fit" }
local REPEAT_DELAY = 0.4
local REPEAT_INTERVAL = 0.08

--- Number field with minus/plus buttons. The number itself is an
--- ISTextEntryBox-backed input, so the value can be typed directly.
---
--- Pressing a button changes the value once and starts auto-repeat after a
--- short hold. Typing updates `value` live, while Enter/clamping rewrites the
--- canonical text. The widget propagates `setEnabled`/`setVisible` to the
--- native field so a hidden or disabled stepper cannot keep accepting input.
--- @class PallidNumberStepper : PallidWidget
--- @field value number Current value.
--- @field min number Minimum inclusive value.
--- @field max number Maximum inclusive value.
--- @field step number Increment used by the buttons and repeat.
--- @field decimals integer Fractional digits kept in the value and shown in the field.
--- @field allowNegative boolean True when a leading minus is accepted in the field.
--- @field input PallidInputText Native-backed text field in the middle.
--- @field onChange fun(stepper: PallidNumberStepper, value: number)|nil Called when the value changes.
--- @field onCommit fun(stepper: PallidNumberStepper, value: number)|nil Called after Enter or an explicit commit.
--- @field hoverSide "minus"|"plus"|nil Button under the cursor.
--- @field pressedSide "minus"|"plus"|nil Button currently held for repeat.
--- @field fill PallidColor Outer fill.
--- @field borderColor PallidColor Outer border.
--- @field buttonFill PallidColor Idle button fill.
--- @field buttonHover PallidColor Hovered button fill.
--- @field buttonPressed PallidColor Held button fill.
--- @field glyphColor PallidColor Plus/minus glyph tint.
--- @field textColor PallidColor Centred value text tint.
local NumberStepper = Widgets.class("NumberStepper")

--- Creates a new `NumberStepper` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional range, formatting, palette and callbacks.
--- @field opts.min number|nil Minimum value, defaults to 0.
--- @field opts.max number|nil Maximum value, defaults to 100.
--- @field opts.step number|nil Button increment, defaults to 1.
--- @field opts.value number|nil Initial value, defaults to `min`.
--- @field opts.decimals integer|nil Fractional digits, defaults to 0.
--- @field opts.allowNegative boolean|nil Allows a leading minus; defaults to `min < 0`.
--- @field opts.onChange fun(stepper: PallidNumberStepper, value: number)|nil Called whenever the value changes.
--- @field opts.onCommit fun(stepper: PallidNumberStepper, value: number)|nil Called after Enter or an explicit commit.
--- @field opts.background PallidColor|nil Outer fill.
--- @field opts.border PallidColor|nil Outer border color.
--- @field opts.buttonFill PallidColor|nil Idle button fill.
--- @field opts.buttonHoverColor PallidColor|nil Hovered button fill.
--- @field opts.buttonPressedColor PallidColor|nil Held button fill.
--- @field opts.glyphColor PallidColor|nil Plus/minus glyph tint.
--- @field opts.textColor PallidColor|nil Centred value text tint.
--- @return PallidNumberStepper stepper New number stepper instance.
function NumberStepper.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, NumberStepper)
    self:init(x, y, w, h)

    --- Returns a value when it is a real number, otherwise the fallback.
    --- @param value any Candidate value.
    --- @param fallback number Value used when the candidate is not a number.
    --- @return number value The candidate or the fallback.
    local function numberOr(value, fallback)
        if type(value) == "number" and value == value then
            return value
        end
        return fallback
    end

    self.min = numberOr(opts.min, 0)
    self.max = numberOr(opts.max, 100)
    if self.min > self.max then
        Pallid.log("NumberStepper: min > max; swapping the range")
        self.min, self.max = self.max, self.min
    end

    self.step = numberOr(opts.step, 1)
    if self.step <= 0 then
        Pallid.log("NumberStepper: step must be positive; using 1")
        self.step = 1
    end

    self.decimals = math.max(0, math.min(12, math.floor(numberOr(opts.decimals, 0) + 0.5)))
    if self.step < 10 ^ -self.decimals then
        Pallid.log("NumberStepper: step is finer than decimals; increase decimals to use it")
    end

    local initial = opts.value ~= nil and numberOr(opts.value, self.min) or self.min
    self.value = self:clamp(initial)
    self.allowNegative = opts.allowNegative == true or self.min < 0

    self.onChange = opts.onChange
    self.onCommit = opts.onCommit
    self._syncing = false

    local Color = Pallid.UI.Color
    self.fill = opts.background or Color.surface
    self.borderColor = opts.border or Color.border
    self.buttonFill = opts.buttonFill or Color.surfaceMuted
    self.buttonHover = opts.buttonHoverColor or Color.accentSoft
    self.buttonPressed = opts.buttonPressedColor or Color.primarySoft
    self.glyphColor = opts.glyphColor or Color.textPrimary
    self.textColor = opts.textColor or Color.textPrimary

    self.textStyle = {
        font = Pallid.UI.Fonts.small,
        color = self.textColor,
        alignH = "center",
        alignV = "middle",
    }
    self.hoverSide = nil
    self.pressedSide = nil
    self._pressedT = 0
    self._repeatT = 0
    self._minusRadii = { tl = 2, tr = 0, br = 0, bl = 2 }
    self._plusRadii = { tl = 0, tr = 2, br = 2, bl = 0 }
    self._minusTexture = Textures.get(ICON_DIR .. "minus.png")
    self._plusTexture = Textures.get(ICON_DIR .. "plus.png")

    self._textValue = nil
    self._textDecimals = nil
    self._text = ""

    local buttonW = self:_buttonWidth()
    local middleW = math.max(1, self.w - buttonW * 2 - 2)
    local middleH = math.max(1, self.h - 2)
    self.input = Widgets.inputText(buttonW + 1, 1, middleW, middleH, {
        text = self:valueText(),
        numeric = true,
        decimals = self.decimals,
        allowNegative = self.allowNegative,
        transparent = true,
        font = self.textStyle.font,
        textColor = self.textColor,
        maxLength = 16,
        onChange = function(_, text)
            if self._syncing then
                return
            end
            local number = tonumber(text)
            if number == nil then
                return
            end
            local clamped = self:clamp(number)
            if clamped ~= self.value then
                self.value = clamped
                if self.onChange ~= nil then
                    self.onChange(self, clamped)
                end
            end
        end,
        onSubmit = function(_, text)
            self:commit(text)
        end,
    })
    self:add(self.input)
    return self
end

--- Moves or resizes the stepper and keeps the native field aligned.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidNumberStepper self For chaining.
function NumberStepper:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:_layoutInput()
    return self
end

--- Factory shortcut for `NumberStepper.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional range, formatting, palette and callbacks.
--- @return PallidNumberStepper stepper New number stepper instance.
function Widgets.numberStepper(x, y, w, h, opts)
    return NumberStepper.new(x, y, w, h, opts)
end

--- Width of one side button; keeps at least one pixel for the middle field.
--- @return number width Button width in pixels.
function NumberStepper:_buttonWidth()
    local maxButton = math.max(1, math.floor((self.w - 2) * 0.5))
    return math.max(1, math.min(math.max(1, self.h), maxButton))
end

--- Keeps the native field inside the current button layout.
function NumberStepper:_layoutInput()
    local input = self.input
    if input == nil then
        return
    end
    local buttonW = self:_buttonWidth()
    local middleW = math.max(1, self.w - buttonW * 2 - 2)
    local middleH = math.max(1, self.h - 2)
    if input.x ~= buttonW + 1 or input.y ~= 1
        or input.w ~= middleW or input.h ~= middleH then
        input:setBounds(buttonW + 1, 1, middleW, middleH)
    end
end

--- Clamps and rounds a value to the configured range and precision.
--- @param value number Value to clamp.
--- @return number clamped Rounded value inside `min..max`.
function NumberStepper:clamp(value)
    if type(value) ~= "number" or value ~= value then
        return self.min
    elseif value == math.huge then
        return self.max
    elseif value == -math.huge then
        return self.min
    end

    local result = value
    if result < self.min then
        result = self.min
    elseif result > self.max then
        result = self.max
    end

    local scale = 10 ^ self.decimals
    if result >= 0 then
        result = math.floor(result * scale + 0.5) / scale
    else
        result = math.ceil(result * scale - 0.5) / scale
    end

    -- Rounding can cross a range boundary when min/max have more decimals.
    if result < self.min then
        result = self.min
    elseif result > self.max then
        result = self.max
    end
    return result
end

--- Cached canonical value text.
--- @return string text Value formatted with `decimals`.
function NumberStepper:valueText()
    if self._textValue == self.value and self._textDecimals == self.decimals then
        return self._text
    end
    local ok, text = pcall(string.format, "%." .. self.decimals .. "f", self.value)
    if not ok then
        text = tostring(self.value)
    end
    self._textValue = self.value
    self._textDecimals = self.decimals
    self._text = text
    return text
end

--- Writes the formatted value into the native box without re-entering onChange.
function NumberStepper:syncText()
    self:_syncTextNow()
end

--- Writes the canonical text even when the field is focused.
function NumberStepper:_syncTextNow()
    local input = self.input
    if input == nil or input.box == nil then
        return
    end
    self._syncing = true
    input:setText(self:valueText())
    self._syncing = false
end

--- Sets the value. Non-number and NaN values are ignored.
--- @param value number New target value.
--- @param silent boolean|nil True skips the `onChange` callback.
--- @return PallidNumberStepper self For chaining.
function NumberStepper:setValue(value, silent)
    if type(value) ~= "number" or value ~= value then
        Pallid.log("NumberStepper:setValue expects a finite number")
        return self
    end
    local clamped = self:clamp(value)
    if clamped == self.value then
        return self
    end
    self.value = clamped

    if not silent and self.input ~= nil and self.input.box ~= nil
        and not self.input.box:isFocused() then
        self:_syncTextNow()
    end
    if not silent and self.onChange ~= nil then
        self.onChange(self, clamped)
    end
    return self
end

--- Returns the current value.
--- @return number value Current value.
function NumberStepper:getValue()
    return self.value
end

--- Changes the value by one `step` in the given direction.
--- @param direction integer -1 for minus, 1 for plus.
function NumberStepper:change(direction)
    if direction ~= -1 and direction ~= 1 then
        return
    end
    self:setValue(self.value + self.step * direction)
    -- While the native field is focused `setValue` does not touch it (it would
    -- fight with what the user is typing), but a +/- click must still show it.
    if self.input ~= nil and self.input.box ~= nil then
        self:_syncTextNow()
    end
end

--- Accepts the text currently typed in the field: clamps it, rewrites the
--- canonical form and drops focus. Enter submits.
--- @param text string|nil Text to commit; nil reads the native field.
--- @return number value Committed value.
function NumberStepper:commit(text)
    if text == nil then
        text = self.input ~= nil and self.input:getText() or ""
    end
    local number = tonumber(text)
    if number ~= nil then
        local snapped = self:clamp(number)
        if snapped ~= self.value then
            self.value = snapped
            if self.onChange ~= nil then
                self.onChange(self, snapped)
            end
        end
    end

    if self.input ~= nil then
        self:_syncTextNow()
        self.input:blur()
    end
    self:blur()
    if self.onCommit ~= nil then
        self.onCommit(self, self.value)
    end
    return self.value
end

--- Changes the minimum and keeps the current value inside the new range.
--- @param value number New minimum.
--- @param silent boolean|nil True skips the `onChange` callback.
--- @return PallidNumberStepper self For chaining.
function NumberStepper:setMin(value, silent)
    if type(value) ~= "number" or value ~= value then
        Pallid.log("NumberStepper:setMin expects a finite number")
        return self
    end
    self.min = value
    if self.min > self.max then
        self.max = self.min
    end
    self:_applyRange(silent)
    return self
end

--- Changes the maximum and keeps the current value inside the new range.
--- @param value number New maximum.
--- @param silent boolean|nil True skips the `onChange` callback.
--- @return PallidNumberStepper self For chaining.
function NumberStepper:setMax(value, silent)
    if type(value) ~= "number" or value ~= value then
        Pallid.log("NumberStepper:setMax expects a finite number")
        return self
    end
    self.max = value
    if self.max < self.min then
        self.min = self.max
    end
    self:_applyRange(silent)
    return self
end

--- Sets both range bounds.
--- @param min number New minimum.
--- @param max number New maximum.
--- @param silent boolean|nil True skips the `onChange` callback.
--- @return PallidNumberStepper self For chaining.
function NumberStepper:setRange(min, max, silent)
    if type(min) ~= "number" or type(max) ~= "number" or min ~= min or max ~= max then
        Pallid.log("NumberStepper:setRange expects finite numbers")
        return self
    end
    if min > max then
        min, max = max, min
    end
    self.min, self.max = min, max
    self:_applyRange(silent)
    return self
end

--- Sets the increment step.
--- @param value number New positive step.
--- @return PallidNumberStepper self For chaining.
function NumberStepper:setStep(value)
    if type(value) ~= "number" or value ~= value or value <= 0 then
        Pallid.log("NumberStepper:setStep expects a positive number")
        return self
    end
    self.step = value
    return self
end

--- Changes the displayed precision and re-clamps the value.
--- @param decimals integer New fractional digit count, 0..12.
--- @param silent boolean|nil True skips the `onChange` callback.
--- @return PallidNumberStepper self For chaining.
function NumberStepper:setDecimals(decimals, silent)
    if type(decimals) ~= "number" then
        Pallid.log("NumberStepper:setDecimals expects a number")
        return self
    end
    self.decimals = math.max(0, math.min(12, math.floor(decimals + 0.5)))
    if self.input ~= nil then
        self.input.decimals = self.decimals
    end
    self:_applyRange(silent)
    return self
end

--- Applies the current range/precision to the value and syncs the text.
--- @param silent boolean|nil True skips the `onChange` callback.
function NumberStepper:_applyRange(silent)
    if self.input ~= nil then
        self.input.allowNegative = self.allowNegative or self.min < 0
    end
    local clamped = self:clamp(self.value)
    if clamped ~= self.value then
        self.value = clamped
        if not silent and self.onChange ~= nil then
            self.onChange(self, clamped)
        end
    end
    if self.input ~= nil and self.input.box ~= nil
        and not self.input.box:isFocused() then
        self:_syncTextNow()
    end
end

--- Keeps the native text in sync with the value after editing or stepping.
--- @param now number Current game-tick time in seconds.
--- @param dt number Seconds since the previous tick, 0..0.1.
function NumberStepper:onUpdate(now, dt)
    local input = self.input
    if input == nil or input.box == nil then
        return
    end
    local box = input.box
    if not box:isFocused() then
        local text = self:valueText()
        local current = box.getInternalText ~= nil and box:getInternalText() or box:getText()
        if current ~= text then
            self:_syncTextNow()
        end
    end
end

--- Advances the held-button auto-repeat.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function NumberStepper:onAnimate(now, dt)
    if self.pressedSide == nil then
        return
    end
    self._pressedT = self._pressedT + dt
    if self._pressedT < REPEAT_DELAY then
        return
    end
    self._repeatT = self._repeatT + dt
    while self._repeatT >= REPEAT_INTERVAL do
        self._repeatT = self._repeatT - REPEAT_INTERVAL
        self:change(self.pressedSide == "plus" and 1 or -1)
    end
end

--- Starts a press on one side button.
--- @param side "minus"|"plus" Pressed side.
function NumberStepper:_press(side)
    self.pressedSide = side
    self.hoverSide = side
    self._pressedT = 0
    self._repeatT = 0
    self:change(side == "plus" and 1 or -1)
end

--- Handles a pointer press inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the press was accepted.
function NumberStepper:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end
    local x = self:originX()
    local buttonW = self:_buttonWidth()
    if px < x + buttonW then
        self:_press("minus")
        return true
    end
    if px >= x + self.w - buttonW then
        self:_press("plus")
        return true
    end

    -- Fallback for a host that does not route clicks to the child input.
    if self.input ~= nil and self.input.box ~= nil then
        self.input.box:focus()
    end
    return true
end

--- Ends the press and stops auto-repeat.
--- @param px number Cursor X in root-local coordinates; unused.
--- @param py number Cursor Y in root-local coordinates; unused.
function NumberStepper:onUp(px, py)
    self.pressedSide = nil
    self._pressedT = 0
    self._repeatT = 0
end

--- Updates hover state for the current pointer position.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function NumberStepper:onHoverMove(px, py)
    if not self.enabled then
        self.hoverSide = nil
        return
    end
    local x = self:originX()
    local buttonW = self:_buttonWidth()
    if px < x + buttonW then
        self.hoverSide = "minus"
    elseif px >= x + self.w - buttonW then
        self.hoverSide = "plus"
    else
        self.hoverSide = nil
    end
end

--- Clears the button hover highlight.
function NumberStepper:onHoverEnd()
    self.hoverSide = nil
    Widgets.Widget.onHoverEnd(self)
end

--- Propagates enabled state to the native field and cancels a press.
--- @param enabled boolean True enables the stepper.
--- @return PallidNumberStepper self For chaining.
function NumberStepper:setEnabled(enabled)
    Widgets.Widget.setEnabled(self, enabled)
    if self.input ~= nil then
        self.input:setEnabled(enabled)
        if not enabled then
            self.input:blur()
        end
    end
    if not enabled then
        self.hoverSide = nil
        self.pressedSide = nil
        self._pressedT = 0
        self._repeatT = 0
    end
    return self
end

--- Propagates visibility to the native field so a hidden stepper cannot leave
--- a floating text box behind.
--- @param visible boolean True shows the stepper.
--- @return PallidNumberStepper self For chaining.
function NumberStepper:setVisible(visible)
    Widgets.Widget.setVisible(self, visible)
    if self.input ~= nil then
        self.input:setVisible(visible)
        if not visible then
            self.input:blur()
        end
    end
    if not visible then
        self.hoverSide = nil
        self.pressedSide = nil
        self._pressedT = 0
        self._repeatT = 0
    end
    return self
end

--- Draws the native field while it is being edited, centred on the current
--- text. When idle the box is hidden and `drawSelf` draws the value instead.
--- @param el ISUIElement Host element the widget is rendered into.
function NumberStepper:drawChildren(el)
    local input = self.input
    if input == nil or input.box == nil then
        return
    end
    self:_layoutInput()
    input._ox = self:originX()
    input._oy = self:originY()
    input:drawSelf(el)

    local box = input.box
    if not box:isFocused() then
        box:setVisible(false)
        return
    end

    -- The native field is left-aligned and has no horizontal alignment option.
    -- Shrink the field to the current text and centre the whole field instead,
    -- so the number stays visually centred while it is being typed too.
    local text = box:getText() or ""
    local font = input.font or self.textStyle.font
    local textW = getTextManager():MeasureStringX(font, text)
    local inset = input.inset or 2
    local middleW = input.w
    -- Match the idle text exactly: both use the same whole-pixel left edge.
    -- DrawStringCentre divides the measured width as an integer, so centring
    -- the native box independently could differ by one pixel.
    local centerX = input:originX() + middleW * 0.5
    local textLeft = math.floor(centerX - textW * 0.5)
    local boxX = textLeft - inset
    -- Two extra pixels on the right keep the caret from forcing a horizontal
    -- scroll, which used to shift the text one pixel when editing started.
    local boxW = textW + inset * 2 + 2
    if boxW > middleW then
        boxW = middleW
    end
    box:setX(el:getAbsoluteX() + boxX)
    box:setWidth(math.max(1, math.floor(boxW + 0.5)))
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the widget is rendered into.
function NumberStepper:drawSelf(el)
    if self.w <= 0 or self.h <= 0 then
        return
    end
    local x, y = self:originX(), self:originY()
    local buttonW = self:_buttonWidth()
    local middleW = math.max(0, self.w - buttonW * 2)

    Pallid.UI.roundedRect(el, x, y, self.w, self.h, 3, self:shade(self.fill))
    Pallid.UI.roundedBorder(el, x, y, self.w, self.h, 3, 1, self:shade(self.borderColor))

    local minusFill = self.buttonFill
    if self.enabled and self.pressedSide == "minus" then
        minusFill = self.buttonPressed
    elseif self.enabled and self.hoverSide == "minus" then
        minusFill = self.buttonHover
    end
    local plusFill = self.buttonFill
    if self.enabled and self.pressedSide == "plus" then
        plusFill = self.buttonPressed
    elseif self.enabled and self.hoverSide == "plus" then
        plusFill = self.buttonHover
    end

    Pallid.UI.roundedRect(el, x + 1, y + 1, math.max(0, buttonW - 1), self.h - 2,
        self._minusRadii, self:shade(minusFill))
    Pallid.UI.roundedRect(el, x + self.w - buttonW, y + 1, math.max(0, buttonW - 1), self.h - 2,
        self._plusRadii, self:shade(plusFill, 2))
    Pallid.UI.rect(el, x + buttonW, y + 2, 1, math.max(0, self.h - 4), self:shade(self.borderColor))
    Pallid.UI.rect(el, x + self.w - buttonW - 1, y + 2, 1, math.max(0, self.h - 4), self:shade(self.borderColor))

    local cy = y + self.h * 0.5
    local leftX = x + buttonW * 0.5
    local rightX = x + self.w - buttonW * 0.5
    local iconSize = math.min(12, math.max(0, buttonW - 4), math.max(0, self.h - 4))
    local glyph = self:shade(self.glyphColor)
    if self._minusTexture ~= nil and iconSize >= 8 then
        Pallid.UI.texture(el, self._minusTexture,
            leftX - iconSize * 0.5, cy - iconSize * 0.5, iconSize, iconSize, glyph, ICON_OPTS)
    else
        local half = 4
        Pallid.UI.line(el, leftX - half, cy, leftX + half, cy, 1, glyph)
    end
    if self._plusTexture ~= nil and iconSize >= 8 then
        Pallid.UI.texture(el, self._plusTexture,
            rightX - iconSize * 0.5, cy - iconSize * 0.5, iconSize, iconSize, glyph, ICON_OPTS)
    else
        local half = 4
        Pallid.UI.line(el, rightX - half, cy, rightX + half, cy, 1, glyph)
        Pallid.UI.line(el, rightX, cy - half, rightX, cy + half, 1, glyph)
    end

    local box = self.input ~= nil and self.input.box or nil
    if box == nil or not box:isFocused() then
        local valueText = self:valueText()
        local middleW = math.max(0, self.w - buttonW * 2)
        local textW = getTextManager():MeasureStringX(self.textStyle.font, valueText)
        local centerX = x + buttonW + 1 + middleW * 0.5
        local textLeft = math.floor(centerX - textW * 0.5)
        self.textStyle.maxWidth = math.max(0, middleW - 4)
        self.textStyle.alignH = "left"
        local base = self.textStyle.color
        self.textStyle.color = self:shade(self.textColor)
        Pallid.UI.text(el, valueText, textLeft, y + self.h * 0.5, self.textStyle)
        self.textStyle.color = base
        self.textStyle.alignH = "center"
    end
end
