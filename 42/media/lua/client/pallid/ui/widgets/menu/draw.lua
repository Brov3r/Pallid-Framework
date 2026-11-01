require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/api/clip"
require "pallid/ui/widgets/widget"
local MenuItem = require "pallid/ui/widgets/menu/item"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local RECT_SHAPE = Pallid.UI.Shape.rect()
local ICON_OPTS = { mode = "fit" }
local LEFT_PAD = 8
local RIGHT_PAD = 6

--- Adds painting to the Menu class.
--- @param Menu table PallidMenu class.
--- @return fun Augmenter that installs the methods.
return function(Menu)
    --- Paints the widget and its children.
    --- @param el ISUIElement Host element.
    --- @param ox number Offset X from the window origin.
    --- @param oy number Offset Y from the window origin.
    function Menu:draw(el, ox, oy)
        if not self.visible then
            return
        end

        local x, y, w, h = self.x, self.y, self.w, self.h
        local padding = self.padding
        local iconSize = self.iconSize
        local arrowSize = self.arrowSize or 9
        local gap = self.gap

        Pallid.UI.roundedRect(el, x, y, w, h, 4, self:shade(self.fill))
        Pallid.UI.roundedBorder(el, x, y, w, h, 4, 1, self:shade(self.borderColor))

        local innerX = x + padding
        local innerY = y + padding
        local innerW = w - padding * 2
        local innerH = h - padding * 2
        local clipped = innerW > 0 and innerH > 0
            and Pallid.UI.clip(el, RECT_SHAPE, innerX, innerY, innerW, innerH)

        if clipped then
            for i = 1, #self.items do
                local item = self.items[i]
                local ix, iy, iw, ih = self:itemRect(i)
                if iy + ih > innerY and iy < innerY + innerH then
                    if item.separator then
                        Pallid.UI.rect(
                            el,
                            ix + 4,
                            iy + math.floor(ih * 0.5),
                            math.max(0, iw - 8),
                            1,
                            self:shade(self.separatorColor)
                        )
                    else
                        if i == self.hover and not item.disabled then
                            Pallid.UI.roundedRect(el, ix, iy, iw, ih, 3, self:shade(self.hoverColor))
                        end

                        local left = ix + LEFT_PAD
                        local baseColor = item.disabled and self.disabledColor
                            or item.color
                            or (item.danger and self.dangerColor)
                            or self.textColor
                        local iconTint = item.disabled and self.disabledColor
                            or item.iconColor
                            or (item.danger and self.dangerColor)
                            or self.textColor

                        if self._hasChecks then
                            if item.checked and self._checkTexture ~= nil then
                                local tint = item.disabled and self.disabledColor
                                    or (item.danger and self.dangerColor)
                                    or self.checkColor
                                Pallid.UI.texture(
                                    el,
                                    self._checkTexture,
                                    left,
                                    iy + (ih - iconSize) * 0.5,
                                    iconSize,
                                    iconSize,
                                    self:shade(tint),
                                    ICON_OPTS
                                )
                            end
                            left = left + iconSize + gap
                        end

                        if self._hasIcons then
                            MenuItem.drawIcon(
                                el,
                                item.icon,
                                left,
                                iy + (ih - iconSize) * 0.5,
                                iconSize,
                                self:shade(iconTint)
                            )
                            left = left + iconSize + gap
                        end

                        local right = ix + iw - RIGHT_PAD
                        if self._hasSubmenu then
                            if item.submenu ~= nil and self._arrowTexture ~= nil then
                                Pallid.UI.texture(
                                    el,
                                    self._arrowTexture,
                                    right - arrowSize,
                                    iy + (ih - arrowSize) * 0.5,
                                    arrowSize,
                                    arrowSize,
                                    self:shade(iconTint),
                                    ICON_OPTS
                                )
                            end
                            right = right - arrowSize - gap
                        end

                        if self._hasRightIcons then
                            MenuItem.drawIcon(
                                el,
                                item.iconRight,
                                right - iconSize,
                                iy + (ih - iconSize) * 0.5,
                                iconSize,
                                self:shade(iconTint)
                            )
                            right = right - iconSize - gap
                        end

                        local labelRight = right
                        if item.shortcut ~= nil then
                            labelRight = labelRight - (item._shortcutW or 0) - gap
                        end
                        local base = self.style.color
                        self.style.color = self:shade(baseColor)
                        self.style.maxWidth = math.max(0, labelRight - left)
                        Pallid.UI.text(
                            el,
                            item._label or item.label,
                            left,
                            iy + ih * 0.5,
                            self.style
                        )
                        self.style.color = base
                        self.style.maxWidth = nil

                        if item.shortcut ~= nil then
                            local shortcutColor = item.disabled and self.disabledColor
                                or (item.danger and self.dangerColor)
                                or self.shortcutColor
                            self.shortcutStyle.color = self:shade(shortcutColor)
                            Pallid.UI.text(el, item.shortcut, right, iy + ih * 0.5, self.shortcutStyle)
                        end
                    end
                end
            end
            Pallid.UI.clipEnd(el)
        end

        local trackX, trackY, trackH, thumbY, thumbH = self:_scrollMetrics()
        if trackX ~= nil then
            Pallid.UI.roundedRect(el, trackX, trackY, 2, trackH, 1, self:shade(self.separatorColor))
            Pallid.UI.roundedRect(el, trackX - 1, thumbY, 4, thumbH, 2, self:shade(self.textColor))
        end

        if self.openSubmenu ~= nil and self.openSubmenu.visible then
            self.openSubmenu:draw(el, ox, oy)
        end
    end
end
