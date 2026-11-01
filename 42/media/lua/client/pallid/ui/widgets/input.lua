require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/mask"
require "pallid/ui/api/clip"
require "pallid/ui/widgets/widget"

local addValueMethods = require "pallid/ui/widgets/input/value"
local addNativeMethods = require "pallid/ui/widgets/input/native"

if ISTextEntryBox == nil then
    pcall(require, "ISUI/ISTextEntryBox")
end

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local I = Pallid.UI._internal

local TRANSPARENT = { r = 0, g = 0, b = 0, a = 0 }
local DEFAULT_RADIUS = 4

--- Extra padding that keeps text away from rounded corners.
--- @param radius number|table|nil Corner radius or {tl,tr,br,bl}.
--- @return number extra Half of the largest corner radius, rounded to pixels.
local function roundedPadding(radius)
    if radius == nil then
        return 0
    end
    local largest
    if type(radius) == "table" then
        largest = math.max(radius.tl or 0, radius.tr or 0, radius.br or 0, radius.bl or 0)
    else
        largest = radius
    end
    if largest <= 0 then
        return 0
    end
    return math.floor(largest * 0.5 + 0.5)
end

--- Base text field. The actual editing is done by the game's
--- ISTextEntryBox/UUITextBox2, so layouts, clipboard, selection, key repeat and
--- IME behave exactly like the vanilla text boxes. Pallid only positions the
--- native box, mirrors its text and adds patterns, password masking, placeholder
--- colours and optional rounded chrome.
--- @class PallidInputBase : PallidWidget
--- @field text string Mirror of the native text (formatted when `pattern` is set).
--- @field rawText string Slot characters without pattern literals.
--- @field box ISTextEntryBox|nil Native text box.
--- @field pattern PallidMask|nil Compiled input pattern.
--- @field masked boolean True when the native box hides the value with `*`.
--- @field multiline boolean True for a text area.
--- @field maxLength integer Hard input cap in characters; 0 keeps the engine default (2000).
--- @field font UIFont Resolved native font.
--- @field radius number|table|nil Corner radius; nil/0 draws square chrome.
--- @field paddingX number Horizontal text padding; 7 plus half radius, capped at 12 by default.
--- @field paddingY number Vertical text padding; 4 plus up to 2 px of radius by default.
--- @field fill PallidColor|nil Field fill; nil draws no fill.
--- @field borderColor PallidColor|nil Rounded border; nil draws no border.
--- @field borderWidth number Rounded border thickness.
--- @field transparent boolean True when neither the native box nor the widget draws chrome.
--- @field readOnly boolean True for a select-only field: no native caret; a click highlights all text.
--- @field placeholder string|nil Native placeholder text.
--- @field placeholderColor PallidColor Placeholder RGB tint; the engine forces alpha 1.
--- @field textColor PallidColor Text tint.
--- @field selectable boolean True when the native text can be selected.
--- @field onChange fun(input: PallidInputBase, text: string, raw: string)|nil Called after the value changes; receives formatted and raw text.
--- @field onSubmit fun(input: PallidInputBase, text: string, raw: string)|nil Called when Enter is pressed.
local Input = Widgets.class("InputBase")

--- Wires keyboard and mouse handlers.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Shared input options; see the `opts.*` fields below.
--- @field opts.text string|nil Initial value.
--- @field opts.placeholder string|nil Placeholder shown while the value is empty.
--- @field opts.placeholderColor PallidColor|nil Placeholder RGB tint; defaults to gray (engine forces alpha 1).
--- @field opts.textColor PallidColor|nil Native text tint; defaults to textPrimary.
--- @field opts.font UIFont|string|nil Native font or a key from Pallid.UI.Fonts.
--- @field opts.maxLength integer|nil Input cap; 0 means the engine default (2000).
--- @field opts.multiline boolean|nil True creates a multiline native box.
--- @field opts.maxLines integer|nil Maximum lines for multiline boxes; defaults to 1000.
--- @field opts.wrap boolean|nil Multiline wrapping; defaults to true.
--- @field opts.pattern string|nil Input template such as `##-##-###`.
--- @field opts.masked boolean|nil Native password masking with `*`.
--- @field opts.mask boolean|string|nil Deprecated password alias; the string value is ignored.
--- @field opts.numeric boolean|nil Digits, one dot and an optional leading minus.
--- @field opts.decimals integer|nil Fractional digit limit when `numeric` is on.
--- @field opts.allowNegative boolean|nil Allows a leading minus; defaults to true.
--- @field opts.onlyText boolean|nil Native filter that accepts ASCII letters only.
--- @field opts.forceUpperCase boolean|nil Native upper-case conversion.
--- @field opts.clearButton boolean|nil Shows the native clear button.
--- @field opts.selectable boolean|nil Allows selecting the text; defaults to true.
--- @field opts.readOnly boolean|nil Select-only value: no native caret; a click highlights all text.
--- @field opts.rounded boolean|nil Enables rounded chrome with the default radius.
--- @field opts.radius number|table|nil Rounded corner radius; a number or {tl,tr,br,bl}.
--- @field opts.paddingX number|nil Horizontal text padding; defaults to 7 plus half radius, capped at 12.
--- @field opts.paddingY number|nil Vertical text padding; defaults to 4 plus up to 2 px of radius.
--- @field opts.padding number|nil Deprecated shorthand applying the same explicit padding on both axes.
--- @field opts.background PallidColor|false|nil Field fill; false disables it.
--- @field opts.border PallidColor|false|nil Field border; false disables it.
--- @field opts.borderWidth number|nil Border thickness; defaults to 1.
--- @field opts.transparent boolean|nil True draws no widget or native chrome.
--- @field opts.onChange fun(input: PallidInputBase, text: string, raw: string)|nil Called after the value changes.
--- @field opts.onSubmit fun(input: PallidInputBase, text: string, raw: string)|nil Called when Enter is pressed.
--- @field opts.onKeyPress fun(input: PallidInputBase, key: integer): boolean|nil Optional key hook. Returning true consumes the key before the built-in editor shortcuts.
--- @return PallidInputBase self The initialized base widget.
function Input:initInput(x, y, w, h, opts)
    opts = I.copyTable(opts)
    self:init(x, y, w, h)
    self.opts = opts
    self.text = opts.text or ""
    self.onChange = opts.onChange
    self.onSubmit = opts.onSubmit
    self.onKeyPressOption = opts.onKeyPress
    self.acceptsFocus = true
    self.multiline = opts.multiline or false
    self.maxLength = opts.maxLength or 0
    self.font = I.resolveFont(opts.font)
    self.placeholder = opts.placeholder
    -- UITextBox2 draws the placeholder with a hard-coded alpha of 1, so only
    -- the RGB part of this colour is visible. A mid grey keeps it clearly
    -- dimmer than the regular text.
    self.placeholderColor = opts.placeholderColor or Pallid.UI.Color.gray
    self.textColor = opts.textColor or Pallid.UI.Color.textPrimary
    self.selectable = opts.selectable ~= false
    self.readOnly = opts.readOnly == true or opts.editable == false
    self._readOnlySelecting = false
    self._selAnchor = 0
    self._selCaret = 0
    self._selStart = 0
    self._selEnd = 0
    self._selDownX = 0
    self._selDownY = 0
    self._selDragged = false
    self._lastText = self.text
    self._lastCursor = 0
    self.clearButton = opts.clearButton == true
    self.forceUpperCase = opts.forceUpperCase == true
    self.onlyText = opts.onlyText == true
    self.onlyNumbers = opts.numeric == true
    self.decimals = opts.decimals
    self.allowNegative = opts.allowNegative ~= false
    self.transparent = opts.transparent == true

    local maskOpt = opts.mask
    self.masked = opts.masked == true or (maskOpt ~= nil and maskOpt ~= false)

    self.radius = opts.radius
    if self.radius == nil and opts.rounded then
        self.radius = DEFAULT_RADIUS
    end
    local cornerPadding = roundedPadding(self.radius)
    local explicitX = opts.paddingX or opts.padding
    local explicitY = opts.paddingY or opts.padding
    -- The automatic rounded padding is capped so a large radius cannot eat the
    -- field; an explicit padding always wins and is used as-is.
    self.paddingX = explicitX and math.max(0, explicitX) or math.min(7 + cornerPadding, 12)
    self.paddingY = explicitY and math.max(0, explicitY) or (4 + math.min(cornerPadding, 2))
    self.fill = opts.background ~= false and (opts.background or Pallid.UI.Color.surface) or nil
    self.borderColor = opts.border ~= false and (opts.border or Pallid.UI.Color.border) or nil
    self.borderWidth = opts.borderWidth or 1

    self.rawText = self.text
    self.pattern = nil
    if opts.pattern ~= nil and opts.pattern ~= "" then
        if self.multiline then
            Pallid.log("Input: pattern is ignored for multiline fields")
        elseif self.masked then
            Pallid.log("Input: pattern is ignored for masked fields")
        else
            self.pattern = Pallid.UI.Mask.compile(opts.pattern)
            if self.pattern == nil then
                Pallid.log("Input: pattern has no input slots: " .. tostring(opts.pattern))
            else
                self.text = Pallid.UI.Mask.format(self.pattern, self.text)
                self.rawText = Pallid.UI.Mask.raw(self.pattern, self.text)
            end
        end
    end
    if self.pattern == nil then
        if self.maxLength > 0 and #self.text > self.maxLength then
            self.text = string.sub(self.text, 1, self.maxLength)
        end
        if self.onlyNumbers then
            self.text = self:_sanitizeNumeric(self.text)
        end
        self.rawText = self.text
    end

    self._formatting = false
    self._suppressChange = false
    self.box = self:createBox()
    if self.box ~= nil and self.box.javaObject ~= nil and self.box.javaObject.getInset ~= nil then
        self.inset = self.box.javaObject:getInset() or 2
    else
        self.inset = 2
    end
    if self.multiline and self.box ~= nil then
        self:_setNativeCaret(self.box, self.text, #self.text)
    end
    return self
end

--- Creates and configures the native text box.
--- @return ISTextEntryBox|nil box Native box, or nil when ISTextEntryBox is unavailable.
function Input:createBox()
    if ISTextEntryBox == nil then
        Pallid.error("Input: ISTextEntryBox is not available")
        return nil
    end

    local box = ISTextEntryBox:new(self.text, 0, 0, self.w, self.h)
    box:initialise()
    box:instantiate()
    self.box = box

    box:setFont(self.font)
    box:setMultipleLine(self.multiline)
    -- The engine centres a single-line value inside the box, but for a
    -- multiline box it centres the whole text block: the first line ends up in
    -- the middle and the caret for line 0 is drawn there too. Only single-line
    -- fields get the vertical centring.
    if box.javaObject ~= nil and box.javaObject.setCentreVertically ~= nil then
        box.javaObject:setCentreVertically(not self.multiline)
    end
    if self.multiline then
        -- UITextBox2 defaults maxLines to 1; the old hard-coded 8 silently
        -- capped the number of lines a text area could hold.
        box:setMaxLines(self.opts.maxLines or 1000)
        if box.javaObject ~= nil and box.javaObject.setWrapLines ~= nil then
            -- Re-assert the requested mode: the native setter is the only way to
            -- turn wrapping back on after a subclass changed it.
            box.javaObject:setWrapLines(self.opts.wrap ~= false)
        end
    end
    box:setMasked(self.masked)
    if self.maxLength > 0 and self.pattern == nil then
        box:setMaxTextLength(self.maxLength)
    elseif self.pattern ~= nil then
        box:setMaxTextLength(#self.pattern.pattern)
    end
    if self.placeholder ~= nil then
        box:setPlaceholderText(self.placeholder)
    end
    if self.placeholderColor ~= nil and box.setPlaceholderTextRGBA ~= nil then
        local c = self.placeholderColor
        box:setPlaceholderTextRGBA(c.r, c.g, c.b, c.a or 1)
    end
    box:setOnlyNumbers(self.onlyNumbers and self.pattern == nil)
    box:setOnlyText(self.onlyText and self.pattern == nil)
    if self.forceUpperCase and self.pattern == nil then
        box:setForceUpperCase(true)
    end
    if box.setClearButton ~= nil then
        box:setClearButton(self.clearButton)
    end

    box:setEditable(not self.readOnly)
    box:setSelectable(self.selectable and not self.readOnly)
    if box.setHasFrame ~= nil then
        box:setHasFrame(false)
    end
    self:_applyNativeColors()

    box.onTextChangeFunction = function(_, changed)
        self:_onTextChange(changed)
    end
    box.onCommandEntered = function()
        if self.onSubmit ~= nil then
            self.onSubmit(self, self:getText(), self:getRawText())
        end
    end

    box:setVisible(false)
    box:addToUIManager()
    -- The text box is a separate UIManager element and the world UI draws over
    -- ours, so force it to the top of the UI list. Without this the box renders
    -- behind the Pallid surface and only appears when that surface is hidden.
    if box.setAlwaysOnTop ~= nil then
        box:setAlwaysOnTop(true)
    end
    return box
end

--- Applies text, fill and border colours to the native box. Rounded chrome is
--- painted by the widget, so the native background and border become invisible.
function Input:_applyNativeColors()
    local box = self.box
    if box == nil then
        return
    end
    -- The widget always paints its own fill/border so padding, radius and
    -- read-only styling stay identical; the native background must stay invisible.
    box.backgroundColor = TRANSPARENT
    box.borderColor = TRANSPARENT
    local c
    if not self.enabled then
        c = Pallid.UI.Color.textDisabled
    elseif self.readOnly then
        c = Pallid.UI.Color.textMuted
    else
        c = self.textColor
    end
    box:setTextRGBA(c.r, c.g, c.b, c.a or 1)
end

--- Positions the native box over the widget and draws its chrome.
--- Called every frame before the native element renders.
--- @param el ISUIElement Host element the tree is rendered into.
function Input:drawSelf(el)
    local box = self.box
    if box == nil then
        return
    end

    local x, y = self:originX(), self:originY()
    local hasRadius = self.radius ~= nil and self.radius ~= 0
    if not self.transparent then
        local fill = self.readOnly and Pallid.UI.Color.surfaceMuted or self.fill
        local border = self.readOnly and Pallid.UI.Color.border or self.borderColor
        if hasRadius then
            if fill ~= nil then
                Pallid.UI.roundedRect(el, x, y, self.w, self.h, self.radius, self:shade(fill))
            end
            if border ~= nil and self.borderWidth > 0 then
                Pallid.UI.roundedBorder(el, x, y, self.w, self.h, self.radius, self.borderWidth, self:shade(border))
            end
        else
            if fill ~= nil then
                Pallid.UI.rect(el, x, y, self.w, self.h, self:shade(fill))
            end
            if border ~= nil and self.borderWidth > 0 then
                Pallid.UI.border(el, x, y, self.w, self.h, self.borderWidth, self:shade(border))
            end
        end
    end
    if self.readOnly and self:_hasReadOnlySelection() then
        self:_drawReadOnlySelection(el, x, y)
    end

    -- The native box is always transparent: the widget owns the fill and border
    -- so padding and radius stay identical with and without a pattern.
    box.backgroundColor = TRANSPARENT
    box.borderColor = TRANSPARENT

    local absX = el:getAbsoluteX() + x
    local absY = el:getAbsoluteY() + y
    local paddingX = self.paddingX or 0
    local paddingY = self.paddingY or 0
    local inset = self.inset or 2
    local boxX = absX + paddingX - inset
    local boxY = absY + paddingY - inset
    local boxW = math.max(1, self.w - paddingX * 2 + inset * 2 - (self.rightInset or 0))
    local boxH = math.max(1, self.h - paddingY * 2 + inset * 2)
    box:setX(boxX)
    box:setY(boxY)
    box:setWidth(boxW)
    box:setHeight(boxH)

    -- Native text boxes are always-on-top UIManager elements and cannot be
    -- stencilled. Hide one that is not fully inside the active software clip:
    -- a text box belonging to a half-scrolled row would otherwise draw over the
    -- scroll panel, the toolbar and its neighbours.
    local clipX, clipY, clipW, clipH = Pallid.UI.clipRect()
    local visible = true
    if clipX ~= nil then
        if clipW <= 0 or clipH <= 0
            or boxX < clipX or boxY < clipY
            or boxX + boxW > clipX + clipW or boxY + boxH > clipY + clipH then
            visible = false
        end
    end
    box:setVisible(visible)

    self._nativeLocalX = x
    self._nativeLocalY = y
    self._nativeW = self.w
    self._nativeH = self.h

    local root = self:getRoot()
    if root ~= nil and root ~= self and root.registerNative ~= nil and self._nativeRoot ~= root then
        self._nativeRoot = root
        root:registerNative(self)
    end
end

--- Keeps `root.focused` in sync when the native box is focused by clicking it.
--- @param now number Current game-tick time in seconds.
--- @param dt number Seconds since the previous tick, 0..0.1.
function Input:onUpdate(now, dt)
    if self._readOnlySelecting and Mouse ~= nil and Mouse.isButtonDown ~= nil
        and not Mouse.isButtonDown(0) then
        self._readOnlySelecting = false
    end
    local box = self.box
    if box == nil then
        return
    end
    local root = self:getRoot()
    if root == nil then
        return
    end
    if box:isFocused() then
        if root.focused ~= self then
            root.focused = self
        end
    elseif not self.readOnly and root.focused == self then
        root.focused = nil
    end
    self._lastText = self:getText()
    self._lastCursor = box:getCursorPos() or 0
    self:_pollWordKeys(now)
end

--- Gives keyboard focus to the native box. Read-only fields keep the Pallid
--- focus only, so the native caret is never drawn.
function Input:onFocus()
    if self.readOnly then
        return
    end
    if self.box ~= nil then
        self.box:focus()
    end
end

--- Removes keyboard focus and clears the read-only selection highlight.
function Input:onBlur()
    if self.readOnly then
        self._readOnlySelecting = false
        self._selAnchor = 0
        self._selCaret = 0
        self._selStart = 0
        self._selEnd = 0
        return
    end
    if self.box ~= nil then
        self.box:unfocus()
    end
end

--- Explicit blur always unfocuses the native box, even when the root's
--- `focused` pointer is out of sync (a click inside a popover can focus the
--- native field before the next update promotes it to `root.focused`).
--- @return boolean hadFocus True when the field had focus.
function Input:blur()
    local root = self:getRoot()
    local hadFocus = root ~= nil and root.focused == self
    if hadFocus then
        root.focused = nil
    end
    self:onBlur()
    return hadFocus
end

--- Handles a pointer press inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the press should focus the field.
function Input:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end
    if self.readOnly then
        -- Keep the native box unfocused so no caret blinks; selection is painted
        -- by the widget from the anchor/caret pair.
        self:focus()
        self._selAnchor = self:_readOnlyIndexAt(px, py)
        self._selCaret = self._selAnchor
        self._selStart = self._selAnchor
        self._selEnd = self._selAnchor
        self._selDownX = px
        self._selDownY = py
        self._selDragged = false
        self._readOnlySelecting = true
        return true
    end
    if self.box ~= nil then
        self.box:focus()
    end
    return true
end

--- Extends a read-only selection while the mouse is captured.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Input:onMove(px, py)
    if not self.readOnly or not self._readOnlySelecting then
        return
    end
    if Mouse ~= nil and Mouse.isButtonDown ~= nil and not Mouse.isButtonDown(0) then
        self._readOnlySelecting = false
        return
    end
    if not self._selDragged then
        if math.abs(px - self._selDownX) + math.abs(py - self._selDownY) < 2 then
            return
        end
        self._selDragged = true
    end
    self._selCaret = self:_readOnlyIndexAt(px, py)
    self:_refreshReadOnlySelection()
end

--- Finishes a read-only selection on release. A plain click keeps the caret at
--- the clicked position and shows no highlight; a drag selects text.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Input:onUp(px, py)
    if not self.readOnly or not self._readOnlySelecting then
        return
    end
    self._readOnlySelecting = false
    if not self._selDragged then
        self._selAnchor = self:_readOnlyIndexAt(px, py)
        self._selCaret = self._selAnchor
        self._selStart = self._selAnchor
        self._selEnd = self._selAnchor
        return
    end
    self._selCaret = self:_readOnlyIndexAt(px, py)
    self:_refreshReadOnlySelection()
end

--- Sets the placeholder text.
--- @param placeholder string|nil New placeholder; nil or empty clears it.
--- @return PallidInputBase self For chaining.
function Input:setPlaceholder(placeholder)
    self.placeholder = placeholder
    if self.box ~= nil then
        self.box:setPlaceholderText(placeholder or "")
    end
    return self
end

--- Returns the placeholder text.
--- @return string|nil placeholder Current placeholder.
function Input:getPlaceholder()
    return self.placeholder
end

--- Sets the placeholder color.
--- @param color PallidColor New placeholder RGB tint; the engine forces alpha 1.
--- @return PallidInputBase self For chaining.
function Input:setPlaceholderColor(color)
    self.placeholderColor = color
    if self.box ~= nil and color ~= nil and self.box.setPlaceholderTextRGBA ~= nil then
        self.box:setPlaceholderTextRGBA(color.r, color.g, color.b, color.a or 1)
    end
    return self
end

--- Sets the text color.
--- @param color PallidColor New native text tint.
--- @return PallidInputBase self For chaining.
function Input:setTextColor(color)
    self.textColor = color
    if self.box ~= nil and color ~= nil then
        self.box:setTextRGBA(color.r, color.g, color.b, color.a or 1)
    end
    return self
end

--- Sets the read-only state.
--- @param readOnly boolean True for a select-only field: no native caret, click selects all.
--- @return PallidInputBase self For chaining.
function Input:setReadOnly(readOnly)
    self.readOnly = readOnly == true
    self._readOnlySelecting = false
    self._selAnchor = 0
    self._selCaret = 0
    self._selStart = 0
    self._selEnd = 0
    if self.box ~= nil then
        self.box:setEditable(self.enabled and not self.readOnly)
        self.box:setSelectable(self.enabled and self.selectable and not self.readOnly)
        if self.readOnly then
            self.box:unfocus()
        end
        self:_applyNativeColors()
    end
    return self
end

--- Enables or disables the widget.
--- @param enabled boolean True enables editing and restores the text tint.
--- @return PallidInputBase self For chaining.
function Input:setEnabled(enabled)
    Widgets.Widget.setEnabled(self, enabled)
    local box = self.box
    if box ~= nil then
        box:setEditable(enabled and not self.readOnly)
        box:setSelectable(enabled and self.selectable and not self.readOnly)
        self:_applyNativeColors()
        if not enabled then
            self:blurNative()
        end
    end
    return self
end

--- Shows or hides the widget.
--- @param visible boolean True shows the field; false hides and blurs the native box.
--- @return PallidInputBase self For chaining.
function Input:setVisible(visible)
    Widgets.Widget.setVisible(self, visible)
    if not visible then
        self:setNativeVisible(false)
        self:blurNative()
    end
    return self
end

-- Value/mask methods and native overlay helpers live in separate files to keep
-- this glue module under the project's size limit.
addValueMethods(Input)
addNativeMethods(Input)
