require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"
local OptionUtil = require "pallid/ui/widgets/internal/option_util"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local ROUND = 3
local CHECK = 12
local CHECK_GAP = 6
local ICON = 14
local ICON_GAP = 6
local SIDE_PAD = 8
local RIGHT_PAD = 8
local ICON_OPTS = { mode = "fit" }
local RECT_SHAPE = Pallid.UI.Shape.rect()

--- Adds field and popup painting to the PopupSelect class.
--- @param PopupSelect table PallidPopupSelect class.
--- @return fun Augmenter that installs the methods.
return function(PopupSelect)
    --- Draws the closed field.
    --- @param el ISUIElement Host element.
    function PopupSelect:drawSelf(el)
        local x, y = self:originX(), self:originY()
        local fill = self:shade(self.fill)
        if self.hover > 0 then
            local mixed = Pallid.UI.Anim.alpha(self.hoverFill, self.hover)
            fill = self:shade(mixed, 2)
        end
        Pallid.UI.roundedRect(el, x, y, self.w, self.h, ROUND, fill)
        Pallid.UI.roundedBorder(el, x, y, self.w, self.h, ROUND, 1, self:shade(self.borderColor, 2))

        self:_drawFieldContent(el, x, y)
        if self._arrowTexture ~= nil then
            Pallid.UI.texture(
                el,
                self._arrowTexture,
                x + self.w - 6 - self.arrowSize,
                y + (self.h - self.arrowSize) * 0.5,
                self.arrowSize,
                self.arrowSize,
                self:shade(self.arrowColor),
                ICON_OPTS
            )
        end
    end

    --- Draws the open popup list and scrollbar.
    --- @param el ISUIElement Host element.
    function PopupSelect:drawPopup(el)
        if not self.open or #self.items == 0 then
            return
        end
        local x, y, w, h = self:listRect()
        Pallid.UI.roundedRect(el, x, y, w, h, ROUND, self:shade(self.listFill))
        Pallid.UI.roundedBorder(el, x, y, w, h, ROUND, 1, self:shade(self.borderColor, 2))

        local innerX = x + 1
        local innerY = y + 1
        local innerW = w - 2
        local innerH = h - 2
        local clipped = innerW > 0 and innerH > 0
            and Pallid.UI.clip(el, RECT_SHAPE, innerX, innerY, innerW, innerH)

        if clipped then
            local first = math.floor(self.scrollY / self.itemHeight) + 1
            local last = math.min(#self.items, first + self._visibleCount + 1)
            local markerX = x + SIDE_PAD
            for i = first, last do
                local item = self.items[i]
                local rowY = y + 1 + (i - 1) * self.itemHeight - self.scrollY
                if rowY + self.itemHeight > innerY and rowY < innerY + innerH then
                    if i == self.highlight and not item.disabled then
                        Pallid.UI.rect(
                            el,
                            x + 1,
                            rowY,
                            w - 2,
                            self.itemHeight,
                            self:shade(self.highlightColor)
                        )
                    end

                    local markerY = rowY + (self.itemHeight - CHECK) * 0.5
                    self:_drawListMarker(el, item, i, markerX, markerY)

                    local iconX = markerX + CHECK + CHECK_GAP
                    if self._hasIcons then
                        OptionUtil.drawIcon(
                            el,
                            item,
                            iconX,
                            rowY + (self.itemHeight - ICON) * 0.5,
                            ICON,
                            self:shade(item.disabled and Pallid.UI.Color.textDisabled or self.style.color)
                        )
                    end

                    local base = self.style.color
                    self.style.color = self:shade(
                        item.disabled and Pallid.UI.Color.textDisabled or base
                    )
                    self.style.maxWidth = self._popupMaxWidth
                    Pallid.UI.text(
                        el,
                        self._popupLabels[i] or "",
                        x + self._textOffset,
                        rowY + self.itemHeight * 0.5,
                        self.style
                    )
                    self.style.color = base
                    self.style.maxWidth = nil
                end
            end
            Pallid.UI.clipEnd(el)
        end

        local trackX, trackY, trackH, thumbY, thumbH = self:_scrollMetrics()
        if trackX ~= nil then
            Pallid.UI.roundedRect(el, trackX, trackY, 2, trackH, 1, self:shade(self.borderColor))
            Pallid.UI.roundedRect(el, trackX - 1, thumbY, 4, thumbH, 2, self:shade(self.style.color))
        end
    end

    --- Draws the subclass-specific field content. Called inside the field chrome.
    --- @param el ISUIElement Host element.
    --- @param x number Field left.
    --- @param y number Field top.
    function PopupSelect:_drawFieldContent(el, x, y) -- luacheck: ignore
    end

    --- Draws a row marker. Subclasses draw a tick or checkbox.
    --- @param el ISUIElement Host element.
    --- @param item PallidOption Row item.
    --- @param index integer Row index.
    --- @param x number Marker left.
    --- @param y number Marker top.
    function PopupSelect:_drawListMarker(el, item, index, x, y) -- luacheck: ignore
    end
end
