require "pallid/ui/internal"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Adds mouse, hover and wheel handling to the PopupSelect class.
--- @param PopupSelect table PallidPopupSelect class.
--- @return fun Augmenter that installs the methods.
return function(PopupSelect)
    --- Handles a pointer press inside the widget.
    --- @param px number Cursor X in root-local coordinates.
    --- @param py number Cursor Y in root-local coordinates.
    --- @param button string|nil "left" or "right".
    --- @return boolean handled True when the press was consumed.
    function PopupSelect:onDown(px, py, button)
        if not self.enabled or button == "right" then
            return false
        end

        if self.open then
            local x, y, w, h = self:listRect()
            if px >= x and px < x + w and py >= y and py < y + h then
                local trackX, trackY, trackH, thumbY, thumbH, travel = self:_scrollMetrics()
                if trackX ~= nil
                    and px >= trackX - 2 and px < trackX + 4
                    and py >= trackY and py < trackY + trackH then
                    self.scrollDragging = true
                    self.dragStartY = py
                    if travel ~= nil and travel > 0 and (py < thumbY or py >= thumbY + thumbH) then
                        local t = (py - trackY - thumbH * 0.5) / travel
                        self.scrollY = math.max(0, math.min(self._maxScroll, t * self._maxScroll))
                    end
                    self.dragStartScroll = self.scrollY
                    return true
                end
                local index = self:_indexAt(px, py, x, y)
                if index ~= nil and not self:_rowDisabled(index) then
                    self:_activateRow(index)
                    self:_playSound()
                    return true
                end
                return true
            end
        end

        if Widgets.Widget.isInside(self, px, py) then
            if self.open then
                self:close()
            else
                self:show()
            end
            return true
        end
        return false
    end

    --- Updates hover state for the current pointer position.
    --- @param px number Cursor X in root-local coordinates.
    --- @param py number Cursor Y in root-local coordinates.
    function PopupSelect:onHoverMove(px, py)
        if not self.open then
            self.highlight = 0
            return
        end
        local x, y = self:listRect()
        local index = self:_indexAt(px, py, x, y)
        self.highlight = index or 0
    end

    --- Clears the hovered row.
    function PopupSelect:onHoverEnd()
        self.highlight = 0
        Widgets.Widget.onHoverEnd(self)
    end

    --- Advances the field hover blend.
    --- @param now number Current time in seconds.
    --- @param dt number Seconds since the previous animation frame, 0..0.1.
    function PopupSelect:onAnimate(now, dt)
        local target = self._hover and self.enabled and 1 or 0
        self.hover = Widgets.approach(self.hover, target, 14, dt)
    end

    --- Scrolls the open list.
    --- @param delta number Wheel steps; positive follows the framework's down direction.
    --- @return boolean handled True while the popup is open.
    function PopupSelect:onWheel(delta)
        if not self.open or self._maxScroll <= 0 then
            return self.open
        end
        self.scrollY = math.max(
            0,
            math.min(self._maxScroll, self.scrollY + delta * 22)
        )
        return true
    end

    --- Continues a scrollbar drag.
    --- @param px number Cursor X in root-local coordinates.
    --- @param py number Cursor Y in root-local coordinates.
    function PopupSelect:onMove(px, py)
        if not self.scrollDragging then
            return
        end
        local _, _, _, _, _, travel = self:_scrollMetrics()
        if travel ~= nil and travel > 0 then
            self.scrollY = math.max(
                0,
                math.min(
                    self._maxScroll,
                    self.dragStartScroll + (py - self.dragStartY) * self._maxScroll / travel
                )
            )
        end
    end

    --- Ends a scrollbar drag.
    function PopupSelect:onUp()
        self.scrollDragging = false
    end
end
