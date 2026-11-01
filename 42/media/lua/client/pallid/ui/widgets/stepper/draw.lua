require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local LINE_GAP = 2
local ICON_OPTS = { mode = "fit" }

--- Adds the painting methods to the Stepper class.
--- @param Stepper table PallidStepper class.
--- @return fun Augmenter that installs the methods.
return function(Stepper)
    --- Draws a step icon when it has one.
    --- @param el ISUIElement Host element.
    --- @param step PallidStep Step to draw.
    --- @param cx number Circle centre X.
    --- @param cy number Circle centre Y.
    --- @param radius number Circle radius.
    --- @param tint PallidColor Icon tint.
    --- @return boolean drawn True when an icon was painted.
    function Stepper:_drawStepContent(el, step, cx, cy, radius, tint)
        local size = radius * 0.95
        if step.iconRegion ~= nil then
            Pallid.UI.textureRegion(el, step.iconRegion, cx - size * 0.5, cy - size * 0.5, size, size, tint, ICON_OPTS)
            return true
        end
        if step.iconTexture ~= nil then
            Pallid.UI.texture(el, step.iconTexture, cx - size * 0.5, cy - size * 0.5, size, size, tint, ICON_OPTS)
            return true
        end
        if step.iconName ~= nil then
            Pallid.UI.icon(el, step.iconName, cx - size * 0.5, cy - size * 0.5, size, tint)
            return true
        end
        return false
    end

    --- Draws the icon or the step number inside a circle.
    --- @param el ISUIElement Host element.
    --- @param step PallidStep Step to draw.
    --- @param index integer One-based step index used for the number fallback.
    --- @param cx number Circle centre X.
    --- @param cy number Circle centre Y.
    --- @param radius number Circle radius.
    --- @param tint PallidColor Content tint.
    function Stepper:_drawStepBody(el, step, index, cx, cy, radius, tint)
        if self:_drawStepContent(el, step, cx, cy, radius, tint) then
            return
        end
        local base = self.numberStyle.color
        self.numberStyle.color = tint
        Pallid.UI.text(el, self._numbers[index], cx, cy, self.numberStyle)
        self.numberStyle.color = base
    end

    --- Draws the check mark for a completed step.
    --- @param el ISUIElement Host element.
    --- @param cx number Circle centre X.
    --- @param cy number Circle centre Y.
    --- @param radius number Circle radius.
    --- @param tint PallidColor Check tint.
    function Stepper:_drawCheck(el, cx, cy, radius, tint)
        local size = radius * 0.95
        if self._checkRegion ~= nil then
            Pallid.UI.textureRegion(el, self._checkRegion, cx - size * 0.5, cy - size * 0.5, size, size, tint, ICON_OPTS)
            return
        end
        if self._checkTexture == nil then
            return
        end
        Pallid.UI.texture(el, self._checkTexture, cx - size * 0.5, cy - size * 0.5, size, size, tint, ICON_OPTS)
    end

    --- Paints the connectors and every step. When `allComplete` is set, all
    --- available steps show a check mark and no step is highlighted as active.
    --- @param el ISUIElement Host element.
    function Stepper:drawSelf(el)
        local count = #self.steps
        if count == 0 or self.w <= 0 or self.h <= 0 then
            return
        end

        local ox, oy = self:originX(), self:originY()
        local slotW = self._slotW
        local radius = self._radius
        local cy = oy + self._cy
        local complete = self.allComplete
        local pulse = 1
        if self.animated and self.pulse ~= nil then
            pulse = self.pulse.alpha
        end
        local activeScale = 1
        if self.animated and self.transition ~= nil and self.transition:isPlaying() then
            activeScale = self.transition.scale
        end

        -- Connectors go under the circles so their ends are hidden by the fill.
        -- The completed colour is revealed left-to-right by an animated
        -- fraction, so advancing a step fills the line instead of snapping it.
        local lineThickness = self.connectorThickness
        for i = 2, count do
            local x1 = ox + slotW * (i - 1.5) + radius + LINE_GAP
            local x2 = ox + slotW * (i - 0.5) - radius - LINE_GAP
            if x2 > x1 then
                local progress = self._lineProgress[i - 1] or (complete and 1 or 0)
                local fillX = x1 + (x2 - x1) * progress
                if fillX - x1 > 0.5 then
                    Pallid.UI.line(el, x1, cy, fillX, cy, lineThickness, self.completedLineColor)
                end
                if x2 - fillX > 0.5 then
                    Pallid.UI.line(el, fillX, cy, x2, cy, lineThickness, self.lineColor)
                end
            end
        end

        for i = 1, count do
            local step = self.steps[i]
            local cx = ox + slotW * (i - 0.5)
            local disabled = step.disabled
            local error = not disabled and step.error
            local completed = not disabled and not error and (complete or i < self.current)
            local active = not disabled and not error and not complete and i == self.current
            local activeRadius = radius * activeScale

            if self.clickable and self.enabled and self.hoverIndex == i and not disabled then
                Pallid.UI.ring(el, cx, cy, radius + 2, 1, self.hoverColor)
            end

            if error then
                Pallid.UI.circle(el, cx, cy, radius, self.errorColor)
            elseif disabled then
                Pallid.UI.circle(el, cx, cy, radius, self.futureFill)
                Pallid.UI.ring(el, cx, cy, radius, 1, self.futureBorder)
            elseif active then
                local fill = step.color or self.activeColor
                Pallid.UI.circle(
                    el,
                    cx,
                    cy,
                    activeRadius + 3,
                    Pallid.UI.Anim.alpha(fill, 0.22 * pulse)
                )
                Pallid.UI.circle(el, cx, cy, activeRadius, fill)
            elseif completed then
                Pallid.UI.circle(el, cx, cy, radius, step.color or self.completedColor)
            else
                Pallid.UI.circle(el, cx, cy, radius, self.futureFill)
                Pallid.UI.ring(el, cx, cy, radius, 1, step.color or self.futureBorder)
            end

            if completed then
                local fill = step.color or self.completedColor
                self:_drawCheck(el, cx, cy, radius, step.iconColor or Pallid.UI.Color.contrastText(fill))
            elseif error then
                self:_drawStepBody(el, step, i, cx, cy, radius, step.iconColor or self.errorContentColor)
            elseif disabled then
                self:_drawStepBody(el, step, i, cx, cy, radius, Pallid.UI.Color.textDisabled)
            elseif active then
                local fill = step.color or self.activeColor
                local content = step.iconColor or Pallid.UI.Color.contrastText(fill)
                self:_drawStepBody(el, step, i, cx, cy, activeRadius, content)
            else
                local content = step.iconColor or self.futureContentColor
                self:_drawStepBody(el, step, i, cx, cy, radius, content)
            end

            if self._hasLabels and step.label ~= "" then
                local color
                if step.labelColor ~= nil then
                    color = step.labelColor
                elseif error then
                    color = self.errorColor
                elseif disabled then
                    color = Pallid.UI.Color.textDisabled
                elseif completed then
                    color = self.completedLabelColor
                elseif active then
                    color = self.activeLabelColor
                else
                    color = self.futureLabelColor
                end
                local base = self.labelStyle.color
                self.labelStyle.color = color
                Pallid.UI.text(el, step.label, cx, oy + self._labelY, self.labelStyle)
                self.labelStyle.color = base
            end
        end
    end
end
