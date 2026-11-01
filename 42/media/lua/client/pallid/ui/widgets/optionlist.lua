require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"
local normaliseOption = require "pallid/ui/widgets/internal/option_item"
local OptionUtil = require "pallid/ui/widgets/internal/option_util"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local ROW_HEIGHT = 22
local MARKER = 14
local MARKER_GAP = 8
local ICON_GAP = 6
local RIGHT_PAD = 4
local HOVER_SPEED = 16
local ICON_DIR = "media/assets/ui/pallid/icons/"
local CHECK_OPTS = { mode = "fit" }

--- Clamps a requested row height to a value that fits the marker.
--- @param height number|nil Requested row height.
--- @return number height Valid row height.
local function clampRowHeight(height)
    if type(height) ~= "number" or height ~= height then
        return ROW_HEIGHT
    end
    return math.max(MARKER + 2, math.floor(height + 0.5))
end

--- Adds shared layout, input, styling and drawing to a vertical option list.
--- Used by RadioGroup and ToggleGroup; both differ only in selection rules and
--- marker shape.
--- @param OptionList table PallidRadioGroup or PallidToggleGroup class.
--- @return fun Augmenter that installs the methods.
return function(OptionList)
    --- Initialises the shared option-list state. Subclasses must seed their
    --- selection fields before calling this method.
    --- @param options (string|table)[] Option definitions.
    --- @param opts table|nil Shared options.
    function OptionList:_setupOptionList(options, opts)
        opts = opts or {}

        self.options = {}
        self.items = {}
        self.rowHeight = clampRowHeight(opts.rowHeight)
        self.markerSize = math.min(MARKER, self.rowHeight - 2)
        self._autoHeight = true
        self._hasIcons = false
        self._labelTexts = {}

        self.style = {
            font = OptionUtil.resolveFont(opts.font),
            color = Pallid.UI.Color.text,
            alignH = "left",
            alignV = "middle",
            ellipsis = "...",
        }
        self.markerFill = Pallid.UI.Color.surface
        self.markerBorder = Pallid.UI.Color.border
        self.selectedFill = Pallid.UI.Color.primaryStrong
        self.checkColor = Pallid.UI.Color.contrastText(self.selectedFill)
        self._customCheckColor = false
        self.hoverColor = Pallid.UI.Color.withAlpha(Pallid.UI.Color.accentSoft, 0.6)
        self._checkTexture = Pallid.UI.Textures.get(ICON_DIR .. "tick.png")

        self.onChange = opts.onChange
        local sound = opts.sound
        if sound == nil then
            sound = self.defaultSound
        elseif sound == false or sound == "" then
            sound = nil
        end
        self.sound = sound

        self.hoverRow = 0
        self.hover = 0
        self:setOptions(options)
    end

    --- Replaces the option list and clamps the selection silently.
    --- @param options (string|table)[]|nil New options; nil clears the list.
    --- @return PallidWidget self For chaining.
    function OptionList:setOptions(options)
        if options ~= nil and type(options) ~= "table" then
            Pallid.log("OptionList:setOptions expects a table of options")
            options = {}
        end

        self.options = {}
        self.items = {}
        self._hasIcons = false
        local list = options or {}
        for i = 1, #list do
            self.options[i] = list[i]
            self.items[i] = normaliseOption(list[i])
            if self.items[i].hasIcon then
                self._hasIcons = true
            end
        end

        self.hoverRow = 0
        self.hover = 0
        self:_clampSelection()
        self:_syncHeight()
        self:_measureRows()
        return self
    end

    --- Recomputes the widget height while automatic sizing is enabled.
    function OptionList:_syncHeight()
        if self._autoHeight then
            self.h = self.rowHeight * #self.items
        end
    end

    --- Pre-truncates every label so drawing never allocates strings.
    function OptionList:_measureRows()
        local textOffset = self.markerSize + MARKER_GAP
        if self._hasIcons then
            textOffset = textOffset + self.markerSize + ICON_GAP
        end
        local maxWidth = math.max(0, self.w - textOffset - RIGHT_PAD)
        -- Keep the limit on the style as a second guard, so a direct font or
        -- width change cannot paint a stale, over-wide label.
        self.style.maxWidth = maxWidth > 0 and maxWidth or nil
        self._labelTexts = {}
        for i = 1, #self.items do
            self._labelTexts[i] = Pallid.UI.truncateText(
                self.items[i].label,
                self.style.font,
                maxWidth
            )
        end
    end

    --- Updates the widget bounds.
    --- @param x number New offset X from the parent's origin.
    --- @param y number New offset Y from the parent's origin.
    --- @param w number New width in pixels.
    --- @param h number New height in pixels; 0 re-enables automatic height.
    --- @return PallidWidget self For chaining.
    function OptionList:setBounds(x, y, w, h)
        self._autoHeight = (h or 0) <= 0
        Widgets.Widget.setBounds(self, x, y, w, h)
        self:_syncHeight()
        self:_measureRows()
        return self
    end

    --- Changes the row height and recalculates the automatic height.
    --- @param height number New row height in pixels.
    --- @return PallidWidget self For chaining.
    function OptionList:setRowHeight(height)
        if type(height) ~= "number" or height ~= height then
            Pallid.log("OptionList:setRowHeight expects a finite number")
            return self
        end
        self.rowHeight = clampRowHeight(height)
        self.markerSize = math.min(MARKER, self.rowHeight - 2)
        self:_syncHeight()
        self:_measureRows()
        return self
    end

    --- Replaces the label font.
    --- @param font UIFont|string|nil New font, or nil to keep the current one.
    --- @return PallidWidget self For chaining.
    function OptionList:setFont(font)
        if font ~= nil then
            self.style.font = OptionUtil.resolveFont(font)
            self:_measureRows()
        end
        return self
    end

    --- Replaces palette colours.
    --- @param colors table Keys: `text`, `markerFill`, `markerBorder`, `selectedFill`, `checkColor`, `hover`.
    --- @return PallidWidget self For chaining.
    function OptionList:setColors(colors)
        colors = colors or {}
        if colors.text ~= nil then
            self.style.color = colors.text
        end
        if colors.markerFill ~= nil then
            self.markerFill = colors.markerFill
        end
        if colors.markerBorder ~= nil then
            self.markerBorder = colors.markerBorder
        end
        if colors.selectedFill ~= nil then
            self.selectedFill = colors.selectedFill
            if not self._customCheckColor then
                self.checkColor = Pallid.UI.Color.contrastText(self.selectedFill)
            end
        end
        if colors.checkColor ~= nil then
            self.checkColor = colors.checkColor
            self._customCheckColor = true
        end
        if colors.hover ~= nil then
            self.hoverColor = colors.hover
        end
        return self
    end

    --- Enables or disables the widget.
    --- @param enabled boolean True enables the list and its input.
    --- @return PallidWidget self For chaining.
    function OptionList:setEnabled(enabled)
        Widgets.Widget.setEnabled(self, enabled)
        if not enabled then
            self.hoverRow = 0
            self.hover = 0
        end
        return self
    end

    --- @param index any Candidate option index.
    --- @return boolean valid True when index is an integer inside the list.
    function OptionList:_validIndex(index)
        if type(index) ~= "number" or index ~= index or math.floor(index) ~= index then
            return false
        end
        return index >= 1 and index <= #self.items
    end

    --- @param py number Cursor Y in root-local coordinates.
    --- @return integer|nil index Row under the cursor, or nil outside rows.
    function OptionList:_rowIndexAt(py)
        if self.rowHeight <= 0 or #self.items == 0 then
            return nil
        end
        local localY = py - self:originY()
        if localY < 0 or localY >= self.rowHeight * #self.items then
            return nil
        end
        local index = math.floor(localY / self.rowHeight) + 1
        if index < 1 or index > #self.items then
            return nil
        end
        return index
    end

    --- Plays the configured UI sound.
    function OptionList:_playSound()
        if self.sound ~= nil and getSoundManager ~= nil then
            getSoundManager():playUISound(self.sound)
        end
    end

    --- Handles a pointer press inside the widget.
    --- @param px number Cursor X in root-local coordinates.
    --- @param py number Cursor Y in root-local coordinates.
    --- @param button string|nil "left" or "right".
    --- @return boolean handled True when a row consumed the press.
    function OptionList:onDown(px, py, button)
        if not self.enabled or button == "right" then
            return false
        end
        local index = self:_rowIndexAt(py)
        if index == nil then
            return false
        end

        local item = self.items[index]
        if item.disabled then
            return true
        end
        if self:_activateRow(index) then
            self:_playSound()
        end
        return true
    end

    --- Updates hover state for the current pointer position.
    --- @param px number Cursor X in root-local coordinates.
    --- @param py number Cursor Y in root-local coordinates.
    function OptionList:onHoverMove(px, py)
        if not self.enabled then
            self.hoverRow = 0
            return
        end
        local row = self:_rowIndexAt(py) or 0
        if row ~= self.hoverRow then
            self.hover = 0
        end
        self.hoverRow = row
    end

    --- Clears the hovered row.
    function OptionList:onHoverEnd()
        self.hoverRow = 0
        Widgets.Widget.onHoverEnd(self)
    end

    --- Eases the row hover highlight. Per-frame so it does not step at the
    --- game tick.
    --- @param now number Current time in seconds.
    --- @param dt number Seconds since the previous animation frame, 0..0.1.
    function OptionList:onAnimate(now, dt)
        local item = self.items[self.hoverRow]
        local target = self._hover and self.enabled and item ~= nil and not item.disabled and 1 or 0
        self.hover = Widgets.approach(self.hover, target, HOVER_SPEED, dt)
    end

    --- Paints the widget into the host element.
    --- @param el ISUIElement Host element.
    function OptionList:drawSelf(el)
        local count = #self.items
        if count == 0 or self.w <= 0 or self.h <= 0 then
            return
        end

        local x, y = self:originX(), self:originY()
        local marker = self.markerSize
        local markerY = (self.rowHeight - marker) * 0.5
        local iconOffset = marker + MARKER_GAP
        local textOffset = iconOffset + (self._hasIcons and (marker + ICON_GAP) or 0)
        local textX = x + textOffset
        local canHover = self.enabled and self.hover > 0.01

        for i = 1, count do
            local item = self.items[i]
            local rowY = y + (i - 1) * self.rowHeight
            local disabled = item.disabled
            local selected = self:_isRowChecked(i)

            if canHover and i == self.hoverRow and not disabled then
                local fill = Pallid.UI.Anim.alpha(self.hoverColor, self.hover)
                Pallid.UI.rect(el, x, rowY, self.w, self.rowHeight, self:shade(fill))
            end

            local my = rowY + markerY
            local fill = selected and self.selectedFill or self.markerFill
            local border = self.markerBorder
            if disabled then
                fill = self.markerFill
            end

            if self.markerShape == "circle" then
                local radius = marker * 0.5
                Pallid.UI.circle(el, x + radius, my + radius, radius, self:shade(fill))
                Pallid.UI.ring(el, x + radius, my + radius, radius, 1, self:shade(border))
                if selected and not disabled then
                    Pallid.UI.circle(
                        el,
                        x + radius,
                        my + radius,
                        marker * 0.22,
                        self:shade(self.checkColor)
                    )
                end
            else
                -- A square marker avoids the AA corner texture halos that a
                -- small rounded checkbox produced at 14 px.
                Pallid.UI.roundedRect(el, x, my, marker, marker, 0, self:shade(fill))
                Pallid.UI.roundedBorder(el, x, my, marker, marker, 0, 1, self:shade(border))
                if selected and not disabled and self._checkTexture ~= nil then
                    local checkSize = marker * 0.72
                    Pallid.UI.texture(
                        el,
                        self._checkTexture,
                        x + (marker - checkSize) * 0.5,
                        my + (marker - checkSize) * 0.5,
                        checkSize,
                        checkSize,
                        self:shade(self.checkColor),
                        CHECK_OPTS
                    )
                end
            end

            local tint = disabled and Pallid.UI.Color.textDisabled or self.style.color
            if self._hasIcons then
                OptionUtil.drawIcon(el, item, x + iconOffset, rowY + markerY, marker, self:shade(tint))
            end

            local base = self.style.color
            self.style.color = self:shade(disabled and Pallid.UI.Color.textDisabled or base)
            Pallid.UI.text(el, self._labelTexts[i] or "", textX, rowY + self.rowHeight * 0.5, self.style)
            self.style.color = base
        end
    end
end
