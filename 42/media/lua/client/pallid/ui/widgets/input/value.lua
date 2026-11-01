require "pallid/ui/internal"
require "pallid/ui/api/draw"
require "pallid/ui/api/mask"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local SELECTION = Pallid.UI.Color.withAlpha(Pallid.UI.Color.primary, 0.25)
local I = Pallid.UI._internal

--- Adds value, pattern and mask methods to the input class.
--- @param Input table PallidInputBase class.
--- @return fun Augmenter that installs the methods.
return function(Input)
    local utf8Length = I.utf8Length
    local utf16Length = I.utf16Length
    local utf16ToByte = I.utf16ToByte

    --- @param text string Source text.
    --- @param pos integer Byte offset.
    --- @return integer start Byte offset of the previous UTF-8 character.
    local function previousCharStart(text, pos)
        local index, previous = 1, 0
        while index < pos do
            previous = index
            index = index + utf8Length(string.byte(text, index))
        end
        return previous
    end

    --- @param ch string Single character.
    --- @return boolean space True for space, tab and line breaks.
    local function isSpace(ch)
        return ch == " " or ch == "\t" or ch == "\n" or ch == "\r"
    end

    --- @param text string Source text.
    --- @param cursor integer UTF-16 caret offset.
    --- @return integer target UTF-16 offset at the previous word start.
    local function wordLeft(text, cursor)
        local pos = utf16ToByte(text, cursor)
        while pos > 0 do
            local start = previousCharStart(text, pos)
            if not isSpace(string.sub(text, start, start)) then
                break
            end
            pos = start
        end
        while pos > 0 do
            local start = previousCharStart(text, pos)
            if isSpace(string.sub(text, start, start)) then
                break
            end
            pos = start
        end
        return utf16Length(string.sub(text, 1, pos))
    end

    --- @param text string Source text.
    --- @param cursor integer UTF-16 caret offset.
    --- @return integer target UTF-16 offset at the next word start.
    local function wordRight(text, cursor)
        local pos = utf16ToByte(text, cursor)
        while pos < #text do
            local ch = string.sub(text, pos + 1, pos + 1)
            if isSpace(ch) then
                break
            end
            pos = pos + utf8Length(string.byte(text, pos + 1))
        end
        while pos < #text do
            local ch = string.sub(text, pos + 1, pos + 1)
            if not isSpace(ch) then
                break
            end
            pos = pos + utf8Length(string.byte(text, pos + 1))
        end
        return utf16Length(string.sub(text, 1, pos))
    end

    --- Keeps digits, one decimal point and an optional leading minus. Invalid
    --- and extra characters are dropped. Returns the caret mapped into the result.
    --- @param text string Input text.
    --- @param decimals integer|nil Maximum fractional digits; nil means unlimited.
    --- @param allowNegative boolean True when a leading minus is accepted.
    --- @param caret integer|nil Caret offset in the input.
    --- @return string value Sanitized text.
    --- @return integer caretOut Caret offset in the sanitized text.
    local function sanitizeNumeric(text, decimals, allowNegative, caret)
        local negative = false
        local start = 1
        if allowNegative and string.sub(text, 1, 1) == "-" then
            negative = true
            start = 2
        end

        local out = {}
        local positions = {}
        local dot = false
        local fraction = 0
        for index = start, #text do
            local ch = string.sub(text, index, index)
            if ch >= "0" and ch <= "9" then
                if dot then
                    if decimals == nil or fraction < decimals then
                        out[#out + 1] = ch
                        positions[#positions + 1] = index
                        fraction = fraction + 1
                    end
                else
                    out[#out + 1] = ch
                    positions[#positions + 1] = index
                end
            elseif ch == "." and not dot and (decimals == nil or decimals > 0) then
                dot = true
                out[#out + 1] = "."
                positions[#positions + 1] = index
            end
        end

        local value = table.concat(out)
        if negative then
            value = "-" .. value
        end

        local caretOut = #value
        if caret ~= nil then
            local accepted = 0
            for i = 1, #positions do
                if positions[i] <= caret then
                    accepted = accepted + 1
                else
                    break
                end
            end
            caretOut = accepted + (negative and 1 or 0)
        end
        return value, caretOut
    end

    --- Applies the instance's numeric options to `text`.
    --- @param text string Input text.
    --- @param caret integer|nil Caret offset in the input.
    --- @return string value Sanitized text.
    --- @return integer caretOut Caret offset in the sanitized text.
    function Input:_sanitizeNumeric(text, caret)
        return sanitizeNumeric(text, self.decimals, self.allowNegative, caret)
    end

    --- Places the native caret, selecting the correct multiline row first:
    --- `UITextBox2.setCursorPos` clamps the index to the current `cursorLine`, so
    --- setting the position alone would jump back to the previous line.
    --- @param changed ISTextEntryBox Native box.
    --- @param text string Text currently in the native box.
    --- @param caret integer Caret offset in `text`.
    function Input:_setNativeCaret(changed, text, caret)
        local java = changed.javaObject
        if java ~= nil and java.setCursorLine ~= nil then
            local line = 0
            local pos = 1
            while true do
                local newline = string.find(text, "\n", pos, true)
                if newline == nil or newline >= caret then
                    break
                end
                line = line + 1
                pos = newline + 1
            end
            java:setCursorLine(line)
        end
        changed:setCursorPos(caret)
    end

    --- Formats a native change, keeps the caret inside the field and updates the
    --- mirrors. `SetText` calls `onTextChange` synchronously, so `_formatting`
    --- stops the nested callback from running the formatter twice.
    --- @param changed ISTextEntryBox Native box that changed.
    function Input:_onTextChange(changed)
        if self._formatting then
            return
        end

        local raw = changed:getInternalText() or ""
        local caret = changed:getCursorPos()
        local value = raw
        local rawText = raw
        local caretOut = caret

        if self.pattern ~= nil then
            local formatted, formattedRaw, formattedCaret = Pallid.UI.Mask.format(self.pattern, raw, caret)
            value, rawText, caretOut = formatted, formattedRaw, formattedCaret
        else
            if self.maxLength > 0 and #value > self.maxLength then
                value = string.sub(value, 1, self.maxLength)
                caretOut = #value
            end
            if self.onlyNumbers then
                value, caretOut = self:_sanitizeNumeric(value, caretOut)
            end
            rawText = value
        end

        if value ~= raw then
            self._formatting = true
            changed:setText(value)
            self:_setNativeCaret(changed, value, caretOut)
            self._formatting = false
        elseif caretOut ~= caret then
            self:_setNativeCaret(changed, value, caretOut)
        end

        self.text = value
        self.rawText = rawText
        if not self._suppressChange and self.onChange ~= nil then
            self.onChange(self, value, rawText)
        end
    end

    --- Returns the live native value (formatted when a pattern is set).
    --- @return string text Current value.
    function Input:getText()
        if self.box ~= nil then
            if self.box.getInternalText ~= nil then
                return self.box:getInternalText()
            end
            return self.box:getText()
        end
        return self.text
    end

    --- Returns the unformatted text.
    --- @return string text Text without pattern literals.
    function Input:getRawText()
        if self.pattern ~= nil then
            return Pallid.UI.Mask.raw(self.pattern, self:getText())
        end
        return self:getText()
    end

    --- Returns true when the text satisfies the mask.
    --- @return boolean complete True when every pattern slot is filled.
    function Input:isComplete()
        if self.pattern ~= nil then
            return Pallid.UI.Mask.isComplete(self.pattern, self:getText())
        end
        return self:getText() ~= ""
    end

    --- Replaces the value. A pattern reformats the input; `silent` suppresses the
    --- `onChange` callback.
    --- @param value string New value.
    --- @param silent boolean|nil True suppresses `onChange`.
    --- @return PallidInputBase self For chaining.
    function Input:setText(value, silent)
        value = value or ""
        local formatted = value
        local rawText = value

        if self.pattern ~= nil then
            formatted, rawText = Pallid.UI.Mask.format(self.pattern, value, nil)
        else
            if self.maxLength > 0 and #formatted > self.maxLength then
                formatted = string.sub(formatted, 1, self.maxLength)
            end
            if self.onlyNumbers then
                formatted = self:_sanitizeNumeric(formatted)
            end
            rawText = formatted
        end

        self.text = formatted
        self.rawText = rawText
        if self.box ~= nil then
            self._suppressChange = silent == true
            self.box:setText(formatted)
            if self.multiline then
                self:_setNativeCaret(self.box, formatted, #formatted)
            end
            self._suppressChange = false
        end
        return self
    end

    --- Replaces the input pattern. Pass nil to remove it.
    --- @param pattern string|nil Pattern such as `##-##-###`.
    --- @return PallidInputBase self For chaining.
    function Input:setPattern(pattern)
        if self.multiline or self.masked then
            Pallid.log("Input: pattern requires a single-line unmasked field")
            return self
        end
        local raw = self:getRawText()
        self.pattern = nil
        if pattern ~= nil and pattern ~= "" then
            self.pattern = Pallid.UI.Mask.compile(pattern)
            if self.pattern == nil then
                Pallid.log("Input: pattern has no input slots: " .. tostring(pattern))
            end
        end
        self:setText(raw)
        return self
    end

    --- Enables or disables native password masking. The mask glyph is always `*`
    --- because the engine exposes no API for a custom one.
    --- @param masked boolean True hides the value.
    --- @return PallidInputBase self For chaining.
    function Input:setMasked(masked)
        masked = masked == true
        if masked and self.pattern ~= nil then
            -- Pattern literals would be hidden as asterisks; keep only characters.
            local raw = self:getRawText()
            self.pattern = nil
            self:setText(raw, true)
        end
        self.masked = masked
        if self.box ~= nil then
            self.box:setMasked(self.masked)
        end
        return self
    end

    --- Returns true when the field masks its text.
    --- @return boolean masked True while the native value is hidden.
    function Input:isMasked()
        return self.masked
    end

    --- Returns the caret position.
    --- @return integer cursor Current native caret offset.
    function Input:getCursorPos()
        if self.box ~= nil then
            return self.box:getCursorPos()
        end
        return 0
    end

    --- Sets the caret position.
    --- @param position integer Caret offset, 0..length.
    --- @return PallidInputBase self For chaining.
    function Input:setCursorPos(position)
        if self.box ~= nil then
            self.box:setCursorPos(position)
        end
        return self
    end

    --- Selects the whole native value.
    --- @return PallidInputBase self For chaining.
    function Input:selectAll()
        if self.box ~= nil then
            self.box:selectAll()
        end
        return self
    end

    --- Clears the native value through the game's own clear method.
    --- @return PallidInputBase self For chaining.
    function Input:clear()
        if self.box ~= nil then
            self.box:clear()
        end
        return self
    end

    --- @return boolean selected True when a read-only range is non-empty.
    function Input:_hasReadOnlySelection()
        return self.readOnly and (self._selEnd or 0) > (self._selStart or 0)
    end

    --- Returns the 0-based character index nearest to a local X position.
    --- @param font UIFont Font used to measure the text.
    --- @param text string Line text.
    --- @param x number Local X inside the text.
    --- @return integer index Character offset, 0..length.
    local function indexFromX(font, text, x)
        if x <= 0 then
            return 0
        end
        local tm = getTextManager()
        local previous = 0
        for i = 1, #text do
            local width = tm:MeasureStringX(font, string.sub(text, 1, i))
            if width >= x then
                if x - previous <= width - x then
                    return i - 1
                end
                return i
            end
            previous = width
        end
        return #text
    end

    --- Maps a root-local point to a character index for read-only selection.
    --- Multiline selection is approximated from hard newlines because the native
    --- Java editor does not expose its soft-wrapped line table to Lua.
    --- @param px number Cursor X in root-local coordinates.
    --- @param py number Cursor Y in root-local coordinates.
    --- @return integer index Character offset, 0..length.
    function Input:_readOnlyIndexAt(px, py)
        local text = self:getText()
        local paddingX = self.paddingX or 0
        local paddingY = self.paddingY or 0
        local x = px - (self:originX() + paddingX)
        if not self.multiline then
            return indexFromX(self.font, text, x)
        end

        local lineHeight = getTextManager():MeasureStringY(self.font, "Ag")
        local line = math.floor((py - (self:originY() + paddingY)) / lineHeight) + 1
        local offset = 0
        local lines = {}
        local start = 1
        while true do
            local newline = string.find(text, "\n", start, true)
            local part = newline ~= nil and string.sub(text, start, newline - 1) or string.sub(text, start)
            lines[#lines + 1] = { text = part, offset = offset }
            offset = offset + #part + 1
            if newline == nil then
                break
            end
            start = newline + 1
        end
        line = math.max(1, math.min(line, #lines))
        return lines[line].offset + indexFromX(self.font, lines[line].text, x)
    end

    --- Recomputes the selected range from the anchor and the current caret.
    function Input:_refreshReadOnlySelection()
        local anchor = self._selAnchor or 0
        local caret = self._selCaret or 0
        self._selStart = math.min(anchor, caret)
        self._selEnd = math.max(anchor, caret)
    end

    --- Draws the read-only selection highlight behind the native text.
    --- @param el ISUIElement Host element the tree is rendered into.
    --- @param x number Absolute X of the widget.
    --- @param y number Absolute Y of the widget.
    function Input:_drawReadOnlySelection(el, x, y)
        local text = self:getText()
        local paddingX = self.paddingX or 0
        local paddingY = self.paddingY or 0
        local lineHeight = getTextManager():MeasureStringY(self.font, "Ag")
        local textH = getTextManager():MeasureStringY(self.font, text)
        local startIndex = self._selStart or 0
        local endIndex = self._selEnd or 0

        if not self.multiline then
            local prefix = string.sub(text, 1, startIndex)
            local selected = string.sub(text, startIndex + 1, endIndex)
            local w = getTextManager():MeasureStringX(self.font, selected)
            if w > 0 then
                local sx = x + paddingX + getTextManager():MeasureStringX(self.font, prefix)
                local sy = y + (self.h - textH) * 0.5
                Pallid.UI.rect(el, sx, sy, w, textH, SELECTION)
            end
            return
        end

        local offset = 0
        local line = 1
        local lineStart = 1
        while offset <= #text do
            local newline = string.find(text, "\n", lineStart, true)
            local part = newline ~= nil and string.sub(text, lineStart, newline - 1) or string.sub(text, lineStart)
            local lineOffset = offset
            local lineEnd = offset + #part
            local from = math.max(startIndex, lineOffset)
            local to = math.min(endIndex, lineEnd)
            if to > from then
                local prefix = string.sub(part, 1, from - lineOffset)
                local selected = string.sub(part, from - lineOffset + 1, to - lineOffset)
                local w = getTextManager():MeasureStringX(self.font, selected)
                if w > 0 then
                    local sx = x + paddingX + getTextManager():MeasureStringX(self.font, prefix)
                    local sy = y + paddingY + (line - 1) * lineHeight
                    Pallid.UI.rect(el, sx, sy, w, lineHeight, SELECTION)
                end
            end
            if newline == nil then
                break
            end
            offset = lineEnd + 1
            lineStart = newline + 1
            line = line + 1
        end
    end

    --- Moves the native caret one word left or right. Native `onKeyLeft/Right`
    --- honour the physical Shift key, so the same method extends the selection.
    --- @param direction integer -1 for left, 1 for right.
    function Input:_moveCaretWord(direction)
        local box = self.box
        if box == nil then
            return
        end
        local text = box:getInternalText() or ""
        local cursor = box:getCursorPos() or 0
        local target = direction < 0 and wordLeft(text, cursor) or wordRight(text, cursor)
        local java = box.javaObject
        if java ~= nil and java.onKeyLeft ~= nil and java.onKeyRight ~= nil then
            local steps = math.abs(target - cursor)
            for _ = 1, steps do
                if direction < 0 then
                    pcall(java.onKeyLeft, java)
                else
                    pcall(java.onKeyRight, java)
                end
            end
        else
            box:setCursorPos(target)
        end
    end

    --- Deletes the word before the caret. Uses the last observed text because the
    --- native box has already handled the physical Backspace before this hook.
    function Input:_deleteWordBack()
        local box = self.box
        if box == nil then
            return
        end
        local text = self._lastText or box:getInternalText() or ""
        local cursor = self._lastCursor or box:getCursorPos() or 0
        local target = wordLeft(text, cursor)
        if target >= cursor then
            return
        end
        local from = utf16ToByte(text, target)
        local to = utf16ToByte(text, cursor)
        local nextText = string.sub(text, 1, from) .. string.sub(text, to + 1)
        box:setText(nextText)
        self:_setNativeCaret(box, nextText, target)
    end

    --- Polls editor shortcuts because `Events.OnKeyPressed` is suppressed while
    --- a native text box owns text entry. Edge detection prevents repeats from
    --- moving several words per tick.
    --- @param now number Current game-tick time in seconds.
    function Input:_pollWordKeys(now)
        local box = self.box
        if box == nil or self.readOnly then
            return
        end
        local keyboard = Keyboard
        if keyboard == nil or keyboard.isKeyDown == nil then
            return
        end
        local ctrl = keyboard.isKeyDown(keyboard.KEY_LCONTROL) or keyboard.isKeyDown(keyboard.KEY_RCONTROL)
        local shift = keyboard.isKeyDown(keyboard.KEY_LSHIFT) or keyboard.isKeyDown(keyboard.KEY_RSHIFT)
        local left = ctrl and keyboard.isKeyDown(keyboard.KEY_LEFT)
        local right = ctrl and keyboard.isKeyDown(keyboard.KEY_RIGHT)
        local back = ctrl and shift and keyboard.isKeyDown(keyboard.KEY_BACK)

        if left and not self._wordLeftHeld then
            self:_moveCaretWord(-1)
        end
        if right and not self._wordRightHeld then
            self:_moveCaretWord(1)
        end
        if back and not self._wordBackHeld then
            self:_deleteWordBack()
        end
        self._wordLeftHeld = left
        self._wordRightHeld = right
        self._wordBackHeld = back
    end

    --- Handles Ctrl+Left/Right word movement, Ctrl+Shift+Left/Right selection
    --- extension and Ctrl+Shift+Backspace word deletion, plus Ctrl+C for a
    --- read-only selection.
    --- @param key integer Keyboard.KEY_* value.
    function Input:onKeyPress(key)
        local hook = self.onKeyPressOption
        if hook ~= nil and hook(self, key) == true then
            return true
        end
        local keyboard = Keyboard
        local ctrl = keyboard ~= nil and keyboard.isKeyDown ~= nil
            and (keyboard.isKeyDown(keyboard.KEY_LCONTROL) or keyboard.isKeyDown(keyboard.KEY_RCONTROL))
        local shift = keyboard ~= nil and keyboard.isKeyDown ~= nil
            and (keyboard.isKeyDown(keyboard.KEY_LSHIFT) or keyboard.isKeyDown(keyboard.KEY_RSHIFT))

        if ctrl and not self.readOnly then
            if key == keyboard.KEY_LEFT then
                self:_moveCaretWord(-1)
            elseif key == keyboard.KEY_RIGHT then
                self:_moveCaretWord(1)
            elseif shift and key == keyboard.KEY_BACK then
                self:_deleteWordBack()
            end
        end

        if not shift and (key == keyboard.KEY_LEFT or key == keyboard.KEY_RIGHT
            or key == keyboard.KEY_UP or key == keyboard.KEY_DOWN
            or key == keyboard.KEY_HOME or key == keyboard.KEY_END) then
            -- Plain navigation drops any painted selection immediately, both
            -- for InputRich and for the read-only select-all highlight.
            self._selAnchor = nil
            self._selectionActive = false
            self._selNativeSynced = true
            self._readOnlySelecting = false
            self._selStart = 0
            self._selEnd = 0
            if self.box ~= nil then
                self._lastCursor = self.box:getCursorPos() or self._lastCursor
            end
        end

        if not self.readOnly or not self:_hasReadOnlySelection() then
            return
        end
        if keyboard == nil or keyboard.isKeyDown == nil or key ~= keyboard.KEY_C then
            return
        end
        if not ctrl then
            return
        end
        if Clipboard ~= nil and Clipboard.setClipboard ~= nil then
            local text = self:getText()
            Clipboard.setClipboard(string.sub(text, (self._selStart or 0) + 1, self._selEnd or 0))
        end
    end
end
