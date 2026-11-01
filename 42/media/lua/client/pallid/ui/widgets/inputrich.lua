require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/clip"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/inputarea"
require "pallid/ui/widgets/richtext"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local I = Pallid.UI._internal
local RECT_SHAPE = Pallid.UI.Shape.rect()

local CARET_BLINK_ON = 0.6

-- UITextBox2 works in Java UTF-16 code units; the shared helpers convert at the
-- string boundary so Cyrillic and emoji keep the caret aligned.
local utf8Length = I.utf8Length
local utf16Length = I.utf16Length
local utf16ToByte = I.utf16ToByte

--- Multi-line code editor with Pallid-drawn syntax highlighting.
---
--- The game's `ISTextEntryBox` owns editing (layouts, IME, clipboard,
--- undo-less key repeat), but its glyphs are never shown. `UITextBox2` passes
--- a hard-coded alpha of 1.0 to `DrawString` (UITextBox2.java:203), so
--- `setTextRGBA` cannot make the native text transparent; drawing a coloured
--- copy underneath produced a doubled, washed-out line. Instead the native box
--- is kept invisible (it still receives key input through
--- `Core.currentTextEntryBox`) and Pallid paints every line, the caret and the
--- selection itself.
---
--- Highlighting is rule based; see `Pallid.UI.RichText.registerLanguage`.
--- Inline icon runs are intentionally not supported; link runs render as text
--- without click handling.
--- @class PallidInputRich : PallidInputArea
--- @field language string Syntax language.
--- @field highlight fun(text: string): table[]|nil Custom run provider.
--- @field placeholder string|nil Placeholder text, or nil.
--- @field lineHeight number Line height in pixels.
local InputRich = Widgets.class("InputRich", Widgets.InputArea)

--- Creates a new `InputRich` instance.
--- @param x number X coordinate.
--- @param y number Y coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional settings.
--- @field opts.text string|nil Initial text.
--- @field opts.placeholder string|nil Placeholder text.
--- @field opts.language string|nil Name registered with Pallid.UI.RichText. Defaults to "lua".
--- @field opts.highlight fun(text: string): table[]|string|nil Custom run provider, or markup. Icon runs are ignored.
--- @field opts.multiline boolean|nil Defaults to true; set false for one-line code.
--- @field opts.font UIFont|string|nil Defaults to `Fonts.small` (language-aware, supports Cyrillic).
--- @field opts.background PallidColor|nil Background color.
--- @field opts.border PallidColor|nil Border color.
--- @field opts.padding number|nil Inner text padding. Defaults to 4.
--- @return PallidInputRich New rich input widget.
function InputRich.new(x, y, w, h, opts)
    opts = I.copyTable(opts)
    opts.transparent = true
    opts.multiline = opts.multiline ~= false
    if opts.pattern ~= nil or opts.mask ~= nil or opts.masked == true then
        Pallid.log("InputRich: pattern/mask options are not supported and were ignored")
        opts.pattern = nil
        opts.mask = nil
        opts.masked = false
    end
    if opts.numeric == true then
        Pallid.log("InputRich: numeric option is not supported and was ignored")
        opts.numeric = false
    end
    if opts.font == nil then
        -- `Fonts.codeSmall` is a Latin-only bitmap; Cyrillic/IME input in it
        -- renders as '?'. The regular small font is language-aware and keeps
        -- typing correct out of the box. Code editors can opt into a code font.
        opts.font = Pallid.UI.Fonts.small
    end

    local self = setmetatable({}, InputRich)
    self:initInput(x, y, w, h, opts)

    self.language = opts.language or "lua"
    self.highlight = opts.highlight
    self.placeholder = opts.placeholder
    self.showBackground = opts.showBackground ~= false
    self.bgFill = opts.background or Pallid.UI.Color.surface
    self.bgBorder = opts.border or Pallid.UI.Color.border
    self.radius = opts.radius or 3
    -- The native field draws its first line at `getInset()`; using the same
    -- padding is what makes our painted caret and the native hit-testing agree.
    if opts.padding == nil and self.box ~= nil and self.box.javaObject ~= nil and self.box.javaObject.getInset ~= nil then
        self.padding = self.box.javaObject:getInset() or 2
    else
        self.padding = opts.padding or 2
    end
    self.selectionColor = opts.selectionColor or Pallid.UI.Color.withAlpha(Pallid.UI.Color.primary, 0.38)
    self.placeholderColor = opts.placeholderColor or Pallid.UI.Color.textDisabled

    -- The native inset is what `UITextBox2.onMouseDown` subtracts from the
    -- click Y, so hit-testing must use it instead of our visual padding.
    self.nativeInset = self.inset or self.padding
    if self.box ~= nil and self.box.javaObject ~= nil and self.box.javaObject.getInset ~= nil then
        self.nativeInset = self.box.javaObject:getInset() or self.nativeInset
    end

    self.lineHeight = 0
    self._lines = {}
    self._layoutText = nil
    self._scrollLine = 0
    self._selAnchor = nil
    self._selectionActive = false
    self._stateCursor = 0
    self._lastCursor = 0
    self._mouseSelecting = false
    -- True when our painted anchor equals the native `toSelectionIndex`; then
    -- native Ctrl+C/X is authoritative and must not be mirrored (mirroring a
    -- cut would remove a second range).
    self._selNativeSynced = true
    self._customCacheText = nil
    self._customCacheRuns = nil
    self._defaultCacheText = nil
    self._defaultCacheRuns = nil

    -- The native layout must not wrap: Pallid owns line breaks, so one logical
    -- line is one drawn line and the caret maps 1:1.
    if self.box ~= nil and self.box.javaObject ~= nil and self.box.javaObject.setWrapLines ~= nil then
        self.box.javaObject:setWrapLines(false)
    end

    -- Reused per-run style; a table per token per frame is the main allocation
    -- cost of a syntax editor.
    self._style = {
        font = self.font,
        color = Pallid.UI.Color.text,
        alignH = "left",
        alignV = "top",
    }
    if self.readOnly and self.box ~= nil then
        -- Read-only editors still need native selection for copy; caret is
        -- suppressed in drawSelf instead.
        self.box:setEditable(false)
        self.box:setSelectable(true)
    end
    self.lineHeight = self:effectiveLineHeight()
    return self
end

--- Factory shortcut for `InputRich.new`.
--- @param x number X coordinate.
--- @param y number Y coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional settings.
--- @return PallidInputRich New rich input widget.
function Widgets.inputRich(x, y, w, h, opts)
    return InputRich.new(x, y, w, h, opts)
end

--- Keeps native selection available for read-only editors after enable/disable.
--- @param enabled boolean True enables editing and selection.
--- @return PallidInputRich self The same instance, for chaining.
function InputRich:setEnabled(enabled)
    Widgets.InputBase.setEnabled(self, enabled)
    if self.box ~= nil then
        self.box:setSelectable(enabled and (self.readOnly or self.selectable))
    end
    return self
end

--- Read-only editors keep native selection so Ctrl+C works; the caret is
--- suppressed in drawSelf.
--- @param readOnly boolean True prevents editing but keeps text selectable.
--- @return PallidInputRich self The same instance, for chaining.
function InputRich:setReadOnly(readOnly)
    self.readOnly = readOnly == true
    if self.box ~= nil then
        self.box:setEditable(self.enabled and not self.readOnly)
        self.box:setSelectable(self.enabled and (self.readOnly or self.selectable))
        if self.readOnly then
            self._selAnchor = nil
            self._selectionActive = false
            self._selNativeSynced = true
        end
    end
    return self
end

--- Replaces the editor value and drops the cached layout/selection.
--- @param value string New text.
--- @param silent boolean|nil True suppresses `onChange`.
--- @return PallidInputRich self The same instance, for chaining.
function InputRich:setText(value, silent)
    Widgets.InputBase.setText(self, value, silent)
    self._layoutText = nil
    self._layoutFont = nil
    self._selAnchor = nil
    self._selectionActive = false
    self._selNativeSynced = true
    self._mouseSelecting = false
    self._scrollLine = 0
    self._lastCursor = 0
    return self
end

--- Enables or disables syntax highlighting.
--- @param highlight fun(text: string): table[]|string|nil
--- @return PallidInputRich self The same instance, for chaining.
function InputRich:setHighlight(highlight)
    self.highlight = highlight
    self._customCacheText = nil
    self._layoutText = nil
    return self
end

--- Sets the syntax language.
--- @param language string Syntax language.
--- @return PallidInputRich self The same instance, for chaining.
function InputRich:setLanguage(language)
    self.language = language or "lua"
    self._layoutText = nil
    self._defaultCacheText = nil
    return self
end

--- Drops cached runs after rules changed at runtime.
--- @return PallidInputRich self The same instance, for chaining.
function InputRich:refreshHighlight()
    self._layoutText = nil
    self._defaultCacheText = nil
    self._customCacheText = nil
    return self
end

--- The native box is an input device only; it must never paint over the
--- highlighted copy.
--- @param visible boolean Whether the element is visible.
function InputRich:setNativeVisible(visible) -- luacheck: ignore
    if self.box ~= nil then
        self.box:setVisible(false)
    end
end

--- Handles focus loss.
function InputRich:onBlur()
    Widgets.InputBase.onBlur(self)
    self._selAnchor = nil
    self._selectionActive = false
    self._selNativeSynced = true
    self._mouseSelecting = false
    self._clipboardHeld = false
    self._lastCaretLine = nil
end

--- Builds styled runs for the text.
--- @param text string Text to split.
--- @return table[]|string Styled runs, or the raw text when highlighting is disabled.
function InputRich:buildRuns(text)
    if self.highlight ~= nil then
        if self._customCacheText == text and self._customCacheRuns ~= nil then
            return self._customCacheRuns
        end
        local runs = self.highlight(text)
        if type(runs) == "string" then
            runs = Pallid.UI.RichText.parse(runs)
        elseif runs == nil then
            runs = Pallid.UI.RichText.highlight(text, self.language)
        end
        self._customCacheText = text
        self._customCacheRuns = runs
        return runs
    end
    -- A per-editor cache: Rich.highlight() keeps one entry per language, and
    -- two editors drawn in the same frame would otherwise evict each other.
    if self._defaultCacheText == text and self._defaultCacheRuns ~= nil then
        return self._defaultCacheRuns
    end
    local runs = Pallid.UI.RichText.highlight(text, self.language)
    self._defaultCacheText = text
    self._defaultCacheRuns = runs
    return runs
end

--- Splits runs into one segment list per logical line.
--- @param text string Text to lay out.
function InputRich:_rebuildLines(text)
    local runs = self:buildRuns(text)
    local manager = getTextManager()
    local font = self.font
    local lines = {}
    local current = { segments = {}, text = "", start0 = 0, width = 0, x = 0 }
    lines[1] = current

    --- Appends the current line to the list when it is not already there.
    local function ensureLine()
        if lines[#lines] ~= current then
            lines[#lines + 1] = current
        end
    end

    for r = 1, #runs do
        local run = runs[r]
        if run.text ~= nil and run.text ~= "" then
            local start = 1
            while true do
                local newline = string.find(run.text, "\n", start, true)
                local part = newline and string.sub(run.text, start, newline - 1)
                    or string.sub(run.text, start)
                if part ~= "" then
                    local width = manager:MeasureStringX(font, part)
                    current.segments[#current.segments + 1] = {
                        text = part,
                        x = current.x,
                        w = width,
                        color = run.color,
                        bold = run.bold,
                        underline = run.underline,
                        strike = run.strike,
                    }
                    current.text = current.text .. part
                    current.x = current.x + width
                    current.width = current.x
                end
                if newline == nil then
                    break
                end
                ensureLine()
                current = { segments = {}, text = "", start0 = 0, width = 0, x = 0 }
                lines[#lines + 1] = current
                start = newline + 1
            end
        elseif run.newline then
            current = { segments = {}, text = "", start0 = 0, width = 0, x = 0 }
            lines[#lines + 1] = current
        elseif run.icon ~= nil then
            -- InputRich is a text editor: inline icons are intentionally not
            -- supported. Warn once instead of silently dropping markup.
            if not self._iconWarned then
                self._iconWarned = true
                Pallid.log("InputRich: icon runs are not supported and were ignored")
            end
        end
    end

    -- start0 is the zero-based UTF-16 offset of the first code unit of the
    -- line; UITextBox2.getCursorPos() uses the same convention.
    local offset = 0
    for i = 1, #lines do
        lines[i].start0 = offset
        offset = offset + utf16Length(lines[i].text) + 1
    end

    self._lines = lines
    self._layoutText = text
    self._layoutFont = font
    self._maxLineWidth = 0
    for i = 1, #lines do
        if lines[i].width > self._maxLineWidth then
            self._maxLineWidth = lines[i].width
        end
    end
end

--- Returns the caret line and column.
--- @return integer line 1-based
--- @return integer column 1-based
function InputRich:cursorLineCol()
    local cursor = self.box ~= nil and self.box:getCursorPos() or 0
    local lines = self._lines
    for i = 1, #lines do
        local start0 = lines[i].start0
        local finish = start0 + utf16Length(lines[i].text)
        if cursor <= finish then
            return i, cursor - start0
        end
    end
    local last = lines[#lines]
    if last == nil then
        return 1, 0
    end
    return #lines, utf16Length(last.text)
end

--- Returns the effective line height.
--- @return number lineHeight Line height in pixels.
function InputRich:effectiveLineHeight()
    if self.lineHeight ~= nil and self.lineHeight > 0 and self._lineHeightFont == self.font then
        return self.lineHeight
    end
    local manager = getTextManager()
    local fontObj
    if manager.getFontFromEnum ~= nil then
        local ok, got = pcall(manager.getFontFromEnum, manager, self.font)
        if ok then
            fontObj = got
        end
    end
    local h
    if fontObj ~= nil and fontObj.getLineHeight ~= nil then
        local ok, got = pcall(fontObj.getLineHeight, fontObj)
        if ok then
            h = got
        end
    end
    if h == nil or h <= 0 then
        h = manager:MeasureStringY(self.font, "Ag")
    end
    if h ~= self.lineHeight then
        self.lineHeight = h
    end
    self._lineHeightFont = self.font
    return self.lineHeight
end

--- Returns the number of visible lines.
--- @return number visibleLines Number of visible lines.
function InputRich:visibleLineCount()
    return math.max(1, math.floor((self.h - self.padding * 2) / self:effectiveLineHeight()))
end

--- Keeps the native field's vertical scroll in sync with our visible line.
--- `UITextBox2.onMouseDown` computes the cursor line from `y - inset - yScroll`,
--- so this is required for click-to-caret to match the painted view.
function InputRich:syncNativeScroll()
    if self.box ~= nil and self.box.setYScroll ~= nil then
        self.box:setYScroll(-(self._scrollLine or 0) * self:effectiveLineHeight())
    end
end

--- Keeps the caret inside the text viewport.
function InputRich:ensureCaretVisible()
    local line, col = self:cursorLineCol()
    local visible = self:visibleLineCount()
    local maxLine = math.max(1, #self._lines)

    if line < self._scrollLine + 1 then
        self._scrollLine = line - 1
    elseif line > self._scrollLine + visible then
        self._scrollLine = line - visible
    end
    self._scrollLine = math.max(0, math.min(math.max(0, maxLine - visible), self._scrollLine))
    self:syncNativeScroll()
end

--- Advances state once per frame.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous frame.
function InputRich:onUpdate(now, dt)
    Widgets.InputBase.onUpdate(self, now, dt)

    local text = self:getText()
    if text ~= self._layoutText or self.font ~= self._layoutFont then
        self:_rebuildLines(text)
        self._selAnchor = nil
        self._selectionActive = false
        self._stateCursor = self.box ~= nil and self.box:getCursorPos() or 0
        self._lastCaretLine = nil
        self._lastCaretCol = nil
    end
    if self.box ~= nil then
        self.box:setVisible(false)
    end

    local cursor = self.box ~= nil and self.box:getCursorPos() or 0
    local focused = self.box ~= nil and self.box:isFocused()
    local keyboard = Keyboard
    local ctrl = focused and keyboard ~= nil and keyboard.isKeyDown ~= nil
        and (keyboard.isKeyDown(keyboard.KEY_LCONTROL) or keyboard.isKeyDown(keyboard.KEY_RCONTROL))

    -- A release outside the editor may skip `onUp`; do not keep a stale drag
    -- flag, otherwise plain arrow keys would not clear the painted selection.
    if self._mouseSelecting and Mouse ~= nil and Mouse.isButtonDown ~= nil
        and not Mouse.isButtonDown(0) then
        self._mouseSelecting = false
        local boxCursor = self.box ~= nil and self.box:getCursorPos() or 0
        self._selectionActive = self._selAnchor ~= nil and self._selAnchor ~= boxCursor
        if self.box ~= nil and self.box.javaObject ~= nil and self.box.javaObject.setSelectingRange ~= nil then
            pcall(self.box.javaObject.setSelectingRange, self.box.javaObject, false)
        end
    end

    local ctrlA = ctrl and keyboard ~= nil and keyboard.isKeyDown(keyboard.KEY_A)
    if not ctrlA then
        self._ctrlAHeld = false
    end

    if not focused then
        self._clipboardHeld = false
    elseif ctrlA then
        if self._ctrlAHeld ~= true then
            self._ctrlAHeld = true
            -- Let the native field own the selection so its copy/cut/arrows
            -- agree with what we paint.
            if self.box ~= nil and self.box.javaObject ~= nil and self.box.javaObject.selectAll ~= nil then
                local ok = pcall(self.box.javaObject.selectAll, self.box.javaObject)
                if ok then
                    cursor = self.box:getCursorPos() or cursor
                end
            end
            self._selAnchor = 0
            self._lastCursor = cursor
            self._stateCursor = cursor
            self._selNativeSynced = true
            self._selectionActive = cursor > 0
        end
    end
    self._lastCursor = cursor

    -- `UITextBox2` already copies/cuts its own selection from Ctrl+C/X. Mirror
    -- only when our painted anchor is not the native one (double-click word and
    -- Shift+click); otherwise a second cut would delete another range.
    if focused and ctrl and keyboard ~= nil then
        local selFrom, selTo
        if not self._selNativeSynced and self._selAnchor ~= nil and self._selAnchor ~= cursor then
            selFrom = math.min(self._selAnchor, cursor)
            selTo = math.max(self._selAnchor, cursor)
        end
        local copyDown = keyboard.isKeyDown(keyboard.KEY_C)
        local cutDown = keyboard.isKeyDown(keyboard.KEY_X)
        if selFrom ~= nil and (copyDown or cutDown) then
            if not self._clipboardHeld then
                self._clipboardHeld = true
                local fromByte = utf16ToByte(text, selFrom)
                local toByte = utf16ToByte(text, selTo)
                local selected = string.sub(text, fromByte + 1, toByte)
                if Clipboard ~= nil and Clipboard.setClipboard ~= nil then
                    pcall(Clipboard.setClipboard, selected)
                end
                if cutDown and self.box ~= nil then
                    local nextText = string.sub(text, 1, fromByte) .. string.sub(text, toByte + 1)
                    self.box:setText(nextText)
                    self:_rebuildLines(nextText)
                    self:_setCaret(selFrom)
                    self._selAnchor = nil
                    self._selectionActive = false
                end
            end
        elseif not copyDown and not cutDown then
            self._clipboardHeld = false
        end
    end

    if focused then
        local caretLine, caretCol = self:cursorLineCol()
        if caretLine ~= self._lastCaretLine or caretCol ~= self._lastCaretCol then
            self._lastCaretLine = caretLine
            self._lastCaretCol = caretCol
            self:ensureCaretVisible()
        end
    end
end

--- Returns the value index at the point.
--- @param px number Pointer X in local coordinates.
--- @param py number Pointer Y in local coordinates.
--- @return integer|nil absolute zero-based index
--- @return integer|nil line Line index, or nil.
function InputRich:indexAt(px, py)
    if #self._lines == 0 then
        return 0, 1
    end
    local lineH = self:effectiveLineHeight()
    local localY = py - (self:originY() + self.padding)
    local line = math.floor(localY / lineH) + self._scrollLine + 1
    if line < 1 then
        line = 1
    elseif line > #self._lines then
        line = #self._lines
    end

    local current = self._lines[line]
    local localX = px - (self:originX() + self.padding)
    local text = current.text
    local manager = getTextManager()
    local best = 0
    local previous = 0
    local previousBoundary = 0
    local col = 0
    while col <= #text do
        local width = manager:MeasureStringX(self.font, string.sub(text, 1, col))
        if width >= localX then
            if col > 0 and (width - localX) > (localX - previous) then
                best = previousBoundary
            else
                best = col
            end
            break
        end
        previous = width
        best = col
        previousBoundary = col
        if col >= #text then
            break
        end
        col = col + utf8Length(string.byte(text, col + 1))
    end
    return current.start0 + utf16Length(string.sub(text, 1, best)), line
end

--- Places the native caret at an absolute UTF-16 index.
---
--- `UITextBox2.setCursorPos` clamps the index to the *current* line, so the
--- line has to be set first; otherwise an index that belongs to a later line
--- is silently clamped to the end of the previous one.
--- @param index integer Item index.
function InputRich:_setCaret(index)
    local box = self.box
    if box == nil then
        return
    end
    local line = #self._lines
    for i = 1, #self._lines do
        local current = self._lines[i]
        if index <= current.start0 + utf16Length(current.text) then
            line = i
            break
        end
    end
    if line < 1 then
        line = 1
    end
    if box.javaObject ~= nil and box.javaObject.setCursorLine ~= nil then
        box.javaObject:setCursorLine(line - 1)
    end
    box:setCursorPos(index)
end

--- Runs the native `UITextBox2.onMouseDown`, which is the only place that
--- resolves a click to an exact character (kerning, UTF-16, double-width
--- glyphs). It only clamps `cursorLine` from above, so the point is clamped
--- into the first/last line here: a click in the top padding or a drag above
--- the field otherwise becomes line -4 and crashes the native line lookup.
--- @param px number Pointer X in local coordinates.
--- @param py number Pointer Y in local coordinates.
--- @return integer|nil caret Absolute UTF-16 index, or nil when unavailable.
function InputRich:_nativeClick(px, py)
    local box = self.box
    local java = box ~= nil and box.javaObject or nil
    if java == nil or java.onMouseDown == nil then
        return nil
    end
    local lineH = self:effectiveLineHeight()
    local inset = self.nativeInset or 2
    local scroll = -(self._scrollLine or 0) * lineH
    local localX = px - self:originX()
    local localY = py - self:originY()
    local minY = inset + scroll
    local maxY = minY + (math.max(1, #self._lines) - 1) * lineH
    if localY < minY then
        localY = minY
    elseif localY > maxY then
        localY = maxY
    end

    self:syncNativeScroll()
    box:setVisible(true)
    local ok = pcall(java.onMouseDown, java, localX, localY)
    -- With no current entry box `onMouseDown` sets `selectingRange` itself, but
    -- on every later press it does not. Without this flag the native drag
    -- handlers ignore the pointer and only our fallback would move the caret.
    if ok and java.setSelectingRange ~= nil then
        pcall(java.setSelectingRange, java, true)
    end
    box:setVisible(false)
    if not ok then
        return nil
    end
    return box:getCursorPos() or 0
end

--- Continues a drag through the native field. `onMouseMove` does not clamp a
--- negative `cursorLine` (it reads the absolute mouse position), while
--- `onMouseMoveOutside` clamps both ends and updates the native anchor exactly
--- like a drag inside the game. The call is safe even when the pointer is far
--- outside the editor.
--- @return integer|nil caret Caret index, or nil.
function InputRich:_nativeDrag()
    local box = self.box
    local java = box ~= nil and box.javaObject or nil
    if java == nil or java.onMouseMoveOutside == nil then
        return nil
    end
    box:setVisible(true)
    local ok = pcall(java.onMouseMoveOutside, java, 0, 0)
    box:setVisible(false)
    if not ok then
        return nil
    end
    return box:getCursorPos() or 0
end

--- Keeps the painted selection in sync with Shift and the native caret. Runs at
--- render rate so key repeat cannot paint a range from a stale anchor.
function InputRich:_syncSelectionState()
    local box = self.box
    if box == nil then
        return
    end
    local cursor = box:getCursorPos() or 0
    if self._mouseSelecting then
        self._stateCursor = cursor
        return
    end
    local keyboard = Keyboard
    local shift = keyboard ~= nil and keyboard.isKeyDown ~= nil
        and (keyboard.isKeyDown(keyboard.KEY_LSHIFT) or keyboard.isKeyDown(keyboard.KEY_RSHIFT))
    local moved = cursor ~= self._stateCursor

    if shift and moved then
        if self._selAnchor == nil then
            self._selAnchor = self._stateCursor
        end
        self._selectionActive = self._selAnchor ~= cursor
    elseif not shift and moved then
        -- A plain arrow/Home/End moved the caret: collapse the selection.
        self._selAnchor = nil
        self._selectionActive = false
        self._selNativeSynced = true
    end
    self._stateCursor = cursor
end

--- Advances the eased transitions for the current frame.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function InputRich:onAnimate(now, dt)
    self:_syncSelectionState()
end

--- Handles a pointer press inside the widget.
--- @param px number Pointer X in local coordinates.
--- @param py number Pointer Y in local coordinates.
--- @param button string|nil Mouse button identifier.
--- @return boolean True when the press was handled.
function InputRich:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end

    local nowMs = getTimestampMs()
    local previousCursor = self._lastCursor
    local shift = Keyboard ~= nil and Keyboard.isKeyDown ~= nil
        and (Keyboard.isKeyDown(Keyboard.KEY_LSHIFT) or Keyboard.isKeyDown(Keyboard.KEY_RSHIFT))
    local doubleClick = self._lastClickAt ~= nil
        and nowMs - self._lastClickAt < 350
        and self._lastClickX ~= nil
        and math.abs(px - self._lastClickX) < 6
        and math.abs(py - self._lastClickY) < 6

    -- Native onMouseDown handles focus itself (and unfocuses the previous
    -- field). Only the headless fallback has to do it manually.
    local caret = self:_nativeClick(px, py)
    if caret == nil then
        if self.box ~= nil then
            self.box:focus()
        end
        -- No native field (headless tests): approximate with our own layout.
        local index = self:indexAt(px, py)
        caret = index or 0
        self:_setCaret(caret)
    end
    self._lastCursor = caret

    if doubleClick then
        -- Select the whitespace-delimited word under the caret.
        local line = self:cursorLineCol()
        local current = self._lines[line]
        if current ~= nil then
            local byte = utf16ToByte(current.text, math.max(0, caret - current.start0))
            local left, right = byte, byte
            -- Move at UTF-8 boundaries; stepping one byte would split Cyrillic
            -- and emoji and corrupt the selection offsets.
            while left > 0 do
                local previous = 1
                local index = 1
                while index < left do
                    previous = index
                    index = index + utf8Length(string.byte(current.text, index))
                end
                local ch = string.sub(current.text, previous, previous)
                if ch == " " or ch == "\t" then
                    break
                end
                if previous == left then
                    left = 0
                    break
                end
                left = previous
            end
            while right < #current.text do
                local nextIndex = right + utf8Length(string.byte(current.text, right + 1))
                local ch = string.sub(current.text, right + 1, right + 1)
                if ch == " " or ch == "\t" then
                    break
                end
                right = nextIndex
            end
            self._selAnchor = current.start0 + utf16Length(string.sub(current.text, 1, left))
            caret = current.start0 + utf16Length(string.sub(current.text, 1, right))
            self:_setCaret(caret)
            self._lastCursor = caret
            self._selNativeSynced = false
            self._selectionActive = true
        end
    elseif shift and previousCursor ~= nil then
        -- Shift+click extends from the previous caret, like the native field.
        self._selAnchor = previousCursor
        self._selNativeSynced = false
        self._selectionActive = caret ~= previousCursor
    else
        self._selAnchor = caret
        self._selNativeSynced = true
        self._selectionActive = false
    end

    self._lastClickAt = nowMs
    self._lastClickX = px
    self._lastClickY = py
    self._stateCursor = caret
    self._mouseSelecting = true
    return true
end

--- Handles pointer movement.
--- @param px number Pointer X in local coordinates.
--- @param py number Pointer Y in local coordinates.
function InputRich:onMove(px, py)
    if not self._mouseSelecting or self.box == nil then
        return
    end
    local caret = self:_nativeDrag()
    if caret == nil then
        local index = self:indexAt(px, py)
        caret = index or self._lastCursor or 0
        if self.box.javaObject ~= nil then
            self:_setCaret(caret)
        end
    end
    self._lastCursor = caret
    self._stateCursor = caret
    if self._selAnchor ~= nil and self._selAnchor ~= caret then
        self._selectionActive = true
    end
end

--- Handles a pointer release.
--- @param px number Pointer X in local coordinates.
--- @param py number Pointer Y in local coordinates.
function InputRich:onUp(px, py)
    self._mouseSelecting = false
    local box = self.box
    if box ~= nil and box.javaObject ~= nil and box.javaObject.setSelectingRange ~= nil then
        pcall(box.javaObject.setSelectingRange, box.javaObject, false)
    end
end

--- Handles a mouse-wheel event.
--- @param delta number Wheel delta in steps.
--- @return boolean True when the wheel event was handled.
function InputRich:onWheel(delta)
    if not self.enabled then
        return false
    end
    local visible = self:visibleLineCount()
    local maximum = math.max(0, #self._lines - visible)
    self._scrollLine = math.max(0, math.min(maximum, self._scrollLine + delta))
    self:syncNativeScroll()
    return true
end

--- Returns the text area rectangle.
--- @return number x X coordinate.
--- @return number y Y coordinate.
--- @return number w Width in pixels.
--- @return number h Height in pixels.
function InputRich:textRect()
    return self:originX() + self.padding,
        self:originY() + self.padding,
        math.max(1, self.w - self.padding * 2),
        math.max(1, self.h - self.padding * 2)
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element used for drawing.
function InputRich:drawSelf(el)
    -- Keep the native field positioned and invisible. `setVisible(false)` is
    -- repeated because the root hides/shows natives at the start of a frame.
    if self.box ~= nil then
        self.box:setX(el:getAbsoluteX() + self:originX())
        self.box:setY(el:getAbsoluteY() + self:originY())
        self.box:setWidth(self.w)
        self.box:setHeight(self.h)
        self.box:setVisible(false)
    end

    local x, y = self:originX(), self:originY()
    if self.showBackground then
        Pallid.UI.roundedRect(el, x, y, self.w, self.h, self.radius, self:shade(self.bgFill))
        Pallid.UI.roundedBorder(el, x, y, self.w, self.h, self.radius, 1, self:shade(self.bgBorder))
    end

    local text = self:getText()
    if text ~= self._layoutText or self.font ~= self._layoutFont then
        self:_rebuildLines(text)
    end

    local tx, ty, tw, th = self:textRect()
    local lineH = self:effectiveLineHeight()
    local visible = self:visibleLineCount()
    local manager = getTextManager()
    local style = self._style
    style.font = self.font
    style.alignH = "left"
    style.alignV = "top"

    local entered = Pallid.UI.clip(el, RECT_SHAPE, tx, ty, tw, th)

    local focused = self.box ~= nil and self.box:isFocused()
    local cursor = self.box ~= nil and self.box:getCursorPos() or 0
    local cursorLine, cursorCol = self:cursorLineCol()

    -- Selection is derived from the native caret plus the anchor tracked in
    -- onUpdate/onDown: UITextBox2 exposes no selection accessor.
    local selFrom, selTo
    if self._selectionActive and self._selAnchor ~= nil and self._selAnchor ~= cursor then
        selFrom = math.min(self._selAnchor, cursor)
        selTo = math.max(self._selAnchor, cursor)
    end

    local first = self._scrollLine + 1
    local last = math.min(#self._lines, self._scrollLine + visible + 1)
    for i = first, last do
        local line = self._lines[i]
        local lineY = ty + (i - 1 - self._scrollLine) * lineH

        local lineUnits = utf16Length(line.text)
        if selFrom ~= nil and line.start0 <= selTo and line.start0 + lineUnits >= selFrom then
            local from = math.max(selFrom, line.start0) - line.start0
            local to = math.min(selTo, line.start0 + lineUnits) - line.start0
            if to > from then
                local fromByte = utf16ToByte(line.text, from)
                local toByte = utf16ToByte(line.text, to)
                local x1 = manager:MeasureStringX(self.font, string.sub(line.text, 1, fromByte))
                local x2 = manager:MeasureStringX(self.font, string.sub(line.text, 1, toByte))
                Pallid.UI.rect(el, tx + x1, lineY, x2 - x1, lineH, self.selectionColor)
            end
        end

        local baseX = tx
        for s = 1, #line.segments do
            local segment = line.segments[s]
            local sx = baseX + segment.x
            if sx + segment.w >= tx - 2 and sx <= tx + tw + 2 then
                style.color = segment.color or Pallid.UI.RichText.Palette.text
                style.bold = segment.bold
                style.underline = segment.underline
                style.strike = segment.strike
                Pallid.UI.text(el, segment.text, sx, lineY, style)
            end
        end
    end

    if text == "" and self.placeholder ~= nil and self.placeholder ~= "" then
        style.color = self.placeholderColor
        style.bold = nil
        style.underline = nil
        style.strike = nil
        style.maxWidth = tw
        Pallid.UI.text(el, self.placeholder, tx, ty, style)
        style.maxWidth = nil
    end

    if focused and not self.readOnly and Pallid.UI.Anim.now() % 1 < CARET_BLINK_ON then
        local current = self._lines[cursorLine]
        local prefix = current and string.sub(current.text, 1, utf16ToByte(current.text, cursorCol)) or ""
        local caretX = tx + manager:MeasureStringX(self.font, prefix)
        local caretY = ty + (cursorLine - 1 - self._scrollLine) * lineH
        Pallid.UI.rect(el, caretX, caretY, 1, lineH, Pallid.UI.Color.textPrimary)
    end

    if entered then
        Pallid.UI.clipEnd(el)
    end
end

--- Returns the current text.
--- @return string Current text.
function InputRich:getText()
    if self.box ~= nil then
        if self.box.getInternalText ~= nil then
            return self.box:getInternalText() or ""
        end
        return self.box:getText() or ""
    end
    return self.text or ""
end
