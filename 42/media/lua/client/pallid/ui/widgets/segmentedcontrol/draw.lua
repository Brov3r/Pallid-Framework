require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/widgets/widget"
local OptionUtil = require "pallid/ui/widgets/internal/option_util"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local ROUND = 4
local INNER_ROUND = 3

--- Adds painting to the SegmentedControl class.
--- @param Segmented table PallidSegmentedControl class.
--- @return fun Augmenter that installs the methods.
return function(Segmented)
    --- Draws the track, dividers, hover, sliding thumb and labels.
    --- @param el ISUIElement Host element.
    function Segmented:drawSelf(el)
        if self.w <= 0 or self.h <= 0 then
            return
        end

        local x, y = self:originX(), self:originY()
        local count = #self.items

        Pallid.UI.roundedRect(el, x, y, self.w, self.h, ROUND, self:shade(self.trackColor))
        Pallid.UI.roundedBorder(el, x, y, self.w, self.h, ROUND, 1, self:shade(self.trackBorder))
        if count == 0 then
            return
        end

        local segmentW = self.w / count

        -- Dividers sit under the thumb so the active plate hides them cleanly.
        if self.h > 10 then
            for i = 2, count do
                Pallid.UI.rect(
                    el,
                    x + (i - 1) * segmentW,
                    y + 4,
                    1,
                    self.h - 8,
                    self:shade(self.trackBorder)
                )
            end
        end

        local canHover = self.enabled and self.hover > 0.01
        if canHover and self.hoverIndex > 0 and self.hoverIndex ~= self.selected then
            local item = self.items[self.hoverIndex]
            if item ~= nil and not item.disabled then
                local sx = x + (self.hoverIndex - 1) * segmentW
                local fill = Pallid.UI.Anim.alpha(self.hoverColor, self.hover)
                Pallid.UI.roundedRect(
                    el,
                    sx + 1,
                    y + 1,
                    segmentW - 2,
                    self.h - 2,
                    INNER_ROUND,
                    self:shade(fill)
                )
            end
        end

        if self.selected > 0 then
            local pos = self.thumb
            if pos < 1 then
                pos = 1
            elseif pos > count then
                pos = count
            end
            local tx = x + (pos - 1) * segmentW
            Pallid.UI.roundedRect(
                el,
                tx + 1,
                y + 1,
                segmentW - 2,
                self.h - 2,
                INNER_ROUND,
                self:shade(self.activeColor)
            )
        end

        local iconSize = self.iconSize or 14
        local iconGap = self.iconGap or 5
        for i = 1, count do
            local item = self.items[i]
            local active = i == self.selected
            local style = active and self.activeStyle or self.style
            local text = self._labelTexts[i] or ""
            local labelWidth = self._labelWidths[i] or 0
            local iconWidth = item.hasIcon and iconSize or 0
            local gap = iconWidth > 0 and labelWidth > 0 and iconGap or 0
            local groupWidth = iconWidth + gap + labelWidth
            local sx = x + (i - 1) * segmentW
            local gx = sx + (segmentW - groupWidth) * 0.5
            local disabled = item.disabled
            local base = style.color
            local tint = disabled and Pallid.UI.Color.textDisabled or base

            if iconWidth > 0 then
                OptionUtil.drawIcon(
                    el,
                    item,
                    gx,
                    y + self.h * 0.5 - iconSize * 0.5,
                    iconSize,
                    self:shade(tint)
                )
            end
            if labelWidth > 0 then
                style.color = self:shade(tint)
                Pallid.UI.text(el, text, gx + iconWidth + gap, y + self.h * 0.5, style)
                style.color = base
            end
        end
    end
end
