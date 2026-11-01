require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/geometry"
require "pallid/ui/api/text"
require "pallid/ui/animation/util"
require "pallid/ui/widgets/widget"
local OptionUtil = require "pallid/ui/widgets/internal/option_util"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local ROUND = 4
local RECT_SHAPE = Pallid.UI.Shape.rect()

--- Adds painting to the Breadcrumbs class.
--- @param Breadcrumbs table PallidBreadcrumbs class.
--- @return fun Augmenter that installs the methods.
return function(Breadcrumbs)
    --- Draws separators, hover plates, icons and labels from cached layout parts.
    --- @param el ISUIElement Host element.
    function Breadcrumbs:drawSelf(el)
        if self.w <= 0 or self.h <= 0 or #self._parts == 0 then
            return
        end

        local x, y = self:originX(), self:originY()
        -- Normal rows are measured to fit. The clip is a safety net for very
        -- narrow widgets where fixed padding alone exceeds the width.
        local entered = false
        if self._needsClip then
            entered = Pallid.UI.clip(el, RECT_SHAPE, x, y, self.w, self.h)
        end

        local parts = self._parts
        local style = self.style
        local baseColor = style.color
        local halfH = self.h * 0.5

        for i = 1, #parts do
            local part = parts[i]
            if part.kind == "separator" then
                local tint = self:shade(self.separatorColor)
                if part.icon ~= nil then
                    local iconSize = part.iconSize or self._separatorDrawSize
                    OptionUtil.drawIcon(
                        el,
                        part.icon,
                        x + part.x,
                        y + halfH - iconSize * 0.5,
                        iconSize,
                        tint
                    )
                else
                    local separatorStyle = self.separatorStyle
                    local color = separatorStyle.color
                    separatorStyle.color = tint
                    Pallid.UI.text(el, part.text, x + part.x, y + halfH, separatorStyle)
                    separatorStyle.color = color
                end
            else
                local active = part.kind == "item" and part.index == self.current
                local disabled = part.kind == "item" and part.item.disabled
                local interactive = self:_isPartInteractive(part)
                local hovered = interactive and self.hoverPart == part and self.hover > 0.01

                if hovered then
                    local plate = Pallid.UI.Anim.alpha(self.hoverBackground, self.hover)
                    Pallid.UI.roundedRect(
                        el,
                        x + part.x + 1,
                        y + 2,
                        math.max(1, part.w - 2),
                        math.max(1, self.h - 4),
                        ROUND,
                        self:shade(plate)
                    )
                end

                local tint
                if part.kind == "ellipsis" then
                    tint = self.ellipsisColor
                elseif disabled then
                    tint = self.disabledColor
                elseif active then
                    tint = self.currentColor
                else
                    tint = self.textColor
                end

                if hovered then
                    Pallid.UI.Anim.lerpColor(self._tint, tint, self.hoverColor, self.hover)
                    tint = self._tint
                end

                if part.kind == "item" and part.iconW > 0 then
                    OptionUtil.drawIcon(
                        el,
                        part.item,
                        x + part.x + self.itemPadding,
                        y + halfH - self.iconSize * 0.5,
                        self.iconSize,
                        self:shade(tint)
                    )
                end

                if part.textW > 0 then
                    style.color = self:shade(tint)
                    Pallid.UI.text(
                        el,
                        part.text,
                        x + part.x + self.itemPadding + (part.iconW or 0),
                        y + halfH,
                        style
                    )
                    style.color = baseColor
                end
            end
        end

        if entered then
            Pallid.UI.clipEnd(el)
        end
    end
end
