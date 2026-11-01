require "pallid/ui/internal"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Adds click, hover and enable handling to the Stepper class.
--- @param Stepper table PallidStepper class.
--- @return fun Augmenter that installs the methods.
return function(Stepper)
    --- Returns the step slot under root-local coordinates.
    --- @param px number Cursor X in root-local coordinates.
    --- @param py number Cursor Y in root-local coordinates.
    --- @return integer|nil index One-based step slot, or nil outside.
    function Stepper:_stepAt(px, py)
        local count = #self.steps
        if count == 0 or self._slotW <= 0 or self.w <= 0 or self.h <= 0 then
            return nil
        end
        local lx = px - self:originX()
        local ly = py - self:originY()
        if lx < 0 or lx >= self.w or ly < 0 or ly >= self.h then
            return nil
        end
        local index = math.floor(lx / self._slotW) + 1
        if index < 1 then
            return 1
        elseif index > count then
            return count
        end
        return index
    end

    --- Enables or disables step selection by click.
    --- @param clickable boolean True lets a click select a step.
    --- @return PallidStepper self For chaining.
    function Stepper:setClickable(clickable)
        self.clickable = clickable == true
        if not self.clickable then
            self.hoverIndex = nil
        end
        return self
    end

    --- Selects a step when clickable. Disabled steps consume the click but do
    --- not change the active index or call `onStepClick`.
    --- @param px number Cursor X in root-local coordinates.
    --- @param py number Cursor Y in root-local coordinates.
    --- @param button string|nil "left" or "right".
    --- @return boolean handled True when a step slot consumed the press.
    function Stepper:onDown(px, py, button)
        if not self.clickable or not self.enabled or button == "right" then
            return false
        end
        local index = self:_stepAt(px, py)
        if index == nil then
            return false
        end

        local step = self.steps[index]
        if step.disabled then
            return true
        end
        -- Clicking a step also reopens it after the whole flow was completed.
        self:setCurrent(index)
        if self.onStepClick ~= nil then
            self.onStepClick(self, index, step)
        end
        return true
    end

    --- Tracks the clickable step under the cursor.
    --- @param px number Cursor X in root-local coordinates.
    --- @param py number Cursor Y in root-local coordinates.
    function Stepper:onHoverMove(px, py)
        if not self.clickable or not self.enabled then
            self.hoverIndex = nil
            return
        end
        self.hoverIndex = self:_stepAt(px, py)
    end

    --- Clears the hovered step.
    function Stepper:onHoverEnd()
        self.hoverIndex = nil
        Widgets.Widget.onHoverEnd(self)
    end

    --- Enables or disables the widget.
    --- @param enabled boolean True enables the stepper and its clicks.
    --- @return PallidStepper self For chaining.
    function Stepper:setEnabled(enabled)
        Widgets.Widget.setEnabled(self, enabled)
        if not enabled then
            self.hoverIndex = nil
        end
        return self
    end
end
