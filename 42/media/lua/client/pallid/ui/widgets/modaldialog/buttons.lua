require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/button"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local BUTTON_PADDING = 10
local ICON = 14
local ICON_GAP = 6

--- Adds button measurement, drawing and activation to the ModalDialog class.
--- @param Modal table PallidModalDialog class.
--- @return fun Augmenter that installs the methods.
return function(Modal)
    --- Measures and caches button labels, widths and rows.
    function Modal:_measureButtons()
        local manager = getTextManager()
        local maxWidth = math.max(1, self.w - self.padding * 2)
        local rows = {}
        local row = {}
        local rowWidth = 0

        for i = 1, #self.buttons do
            local button = self.buttons[i]
            local iconSlot = button.icon ~= nil and (ICON + ICON_GAP) or 0
            local natural = manager:MeasureStringX(self.buttonStyle.font, button.text)
                + BUTTON_PADDING * 2 + iconSlot
            local width = math.max(self.minButtonWidth, natural)
            if width > maxWidth then
                width = maxWidth
            end
            local labelWidth = math.max(0, width - BUTTON_PADDING * 2 - iconSlot)
            button._label = Pallid.UI.truncateText(button.text, self.buttonStyle.font, labelWidth)
            button._labelWidth = manager:MeasureStringX(self.buttonStyle.font, button._label)
            button._width = width
            button._iconSlot = iconSlot

            local extra = rowWidth > 0 and self.buttonGap or 0
            if rowWidth > 0 and rowWidth + extra + width > maxWidth then
                rows[#rows + 1] = { items = row, width = rowWidth }
                row = {}
                rowWidth = 0
                extra = 0
            end
            row[#row + 1] = button
            rowWidth = rowWidth + extra + width
        end
        if #row > 0 then
            rows[#rows + 1] = { items = row, width = rowWidth }
        end
        self._buttonRows = rows
        self._buttonAreaH = #rows * self.buttonHeight
            + math.max(0, #rows - 1) * self.buttonGap
        self._buttonsDirty = false
    end

    --- Computes button positions relative to the dialog.
    function Modal:_layoutButtons()
        if self._buttonsDirty or #self._buttonRects ~= #self.buttons then
            self:_measureButtons()
        end
        self._buttonRects = {}
        local y = self.h - self.padding - self._buttonAreaH
        for r = 1, #self._buttonRows do
            local row = self._buttonRows[r]
            local x = self.w - self.padding - row.width
            for i = 1, #row.items do
                local button = row.items[i]
                self._buttonRects[#self._buttonRects + 1] = {
                    x = x,
                    y = y,
                    w = button._width,
                    h = self.buttonHeight,
                }
                x = x + button._width + self.buttonGap
            end
            y = y + self.buttonHeight + self.buttonGap
        end

        if self._buttonWidgets ~= nil then
            for i = 1, #self._buttonWidgets do
                local rect = self._buttonRects[i]
                if rect ~= nil then
                    self._buttonWidgets[i]:setBounds(rect.x, rect.y, rect.w, rect.h)
                end
            end
        end
    end

    --- Returns the rectangle of a dialog button.
    --- @param index integer Button index.
    --- @return number x Root-local X.
    --- @return number y Root-local Y.
    --- @return number w Width.
    --- @return number h Height.
    function Modal:buttonRect(index)
        if self._buttonsDirty or #self._buttonRects ~= #self.buttons then
            self:_layoutButtons()
        end
        local rect = self._buttonRects[index]
        if rect == nil then
            return self:originX(), self:originY(), 0, 0
        end
        return self:originX() + rect.x, self:originY() + rect.y, rect.w, rect.h
    end

    --- Creates the actual Button widgets used for painting and input.
    function Modal:_createButtonWidgets()
        local old = self._buttonWidgets
        if old ~= nil then
            for i = 1, #old do
                self:remove(old[i])
            end
        end
        self._buttonWidgets = {}

        for i = 1, #self.buttons do
            local descriptor = self.buttons[i]
            local index = i
            local widget = Widgets.button(0, 0, 1, 1, {
                text = descriptor.text,
                icon = descriptor.icon,
                radius = self.buttonRadius or 4,
                sound = false,
                iconInset = 12,
                onClick = function()
                    self:_activateButton(index)
                end,
            })
            widget.borderColor = self.borderColor
            widget.fillInset = 1
            widget.fill = self.buttonFill
            widget.hoverFill = self.buttonHover
            widget.pressFill = self.buttonFill
            widget.textColor = self.buttonStyle.color
            widget.iconColor = self.buttonStyle.color
            if descriptor.disabled then
                widget:setEnabled(false)
                widget.fill = self.disabledFill
                widget.hoverFill = self.disabledFill
                widget.textColor = self.disabledText
                widget.iconColor = self.disabledText
            elseif descriptor.danger then
                widget.fill = self.dangerFill
                widget.hoverFill = self.dangerHover
                widget.pressFill = self.dangerHover
                widget.textColor = Pallid.UI.Color.contrastText(self.dangerFill)
                widget.iconColor = widget.textColor
            elseif descriptor.negative then
                widget.fill = self.warningFill
                widget.hoverFill = self.warningHover
                widget.pressFill = self.warningHover
                widget.textColor = Pallid.UI.Color.contrastText(self.warningFill)
                widget.iconColor = widget.textColor
            elseif descriptor.primary or descriptor.positive then
                widget.fill = self.primaryFill
                widget.hoverFill = self.primaryHover
                widget.pressFill = self.primaryHover
                widget.textColor = Pallid.UI.Color.contrastText(self.primaryFill)
                widget.iconColor = widget.textColor
            end
            widget.style.color = widget.textColor
            self._buttonWidgets[i] = widget
            self:add(widget)
        end
    end

    --- @param px number Cursor X.
    --- @param py number Cursor Y.
    --- @return integer|nil index Button under the cursor.
    function Modal:_buttonAt(px, py)
        for i = 1, #self.buttons do
            local x, y, w, h = self:buttonRect(i)
            if px >= x and px < x + w and py >= y and py < y + h then
                return i
            end
        end
        return nil
    end

    --- Finds a button by semantic role or conventional label.
    --- @param role "positive"|"negative" Role to find.
    --- @return integer|nil index Button index.
    function Modal:_findButton(role)
        local words = role == "positive"
            and { "ok", "okay", "accept", "yes", "apply", "принять", "да", "ок" }
            or { "cancel", "close", "no", "dismiss", "отмена", "закрыть", "нет" }

        for i = 1, #self.buttons do
            local button = self.buttons[i]
            if role == "positive" and (button.primary or button.positive) then
                return i
            end
            if role == "negative" and (button.negative or button.cancel) then
                return i
            end
        end
        for i = 1, #self.buttons do
            local button = self.buttons[i]
            local text = button.text:lower()
            for w = 1, #words do
                if text == words[w] then
                    return i
                end
            end
        end
        return nil
    end

    --- @param index integer Button index.
    function Modal:_activateButton(index)
        local button = self.buttons[index]
        if button == nil or button.disabled then
            return
        end
        self:_playSound()
        if button.closeOnClick then
            self:close()
        end
        if button.onClick ~= nil then
            button.onClick(button, self)
        end
        if self.onResult ~= nil then
            self.onResult(button, self)
        end
    end

    --- @param el ISUIElement Host element.
    function Modal:_drawButtons(el)
        if self._buttonWidgets == nil or #self._buttonWidgets ~= #self.buttons then
            self:_createButtonWidgets()
            self:_layoutButtons()
        end
        for i = 1, #self._buttonWidgets do
            local button = self._buttonWidgets[i]
            -- Draw directly: modal buttons are painted after clipped content,
            -- and must not depend on the generic child draw pass.
            button._ox = self:originX()
            button._oy = self:originY()
            button:drawSelf(el)
        end
    end
end
