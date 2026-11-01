require "pallid/ui/internal"
require "pallid/ui/api/text"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

--- Adds measurement, positioning and scroll geometry to the Menu class.
--- @param Menu table PallidMenu class.
--- @return fun Augmenter that installs the methods.
return function(Menu)
    --- Measures item geometry, width, height and scroll range.
    function Menu:measure()
        local manager = getTextManager()
        local hasChecks = self.reserveCheckSlot == true
        local hasIcons = false
        local hasRightIcons = false
        local hasSubmenu = false
        local widest = self.minWidth
        local contentH = 0

        for i = 1, #self.items do
            local item = self.items[i]
            local height = item.separator and self.separatorHeight or self.itemHeight
            self._itemY = self._itemY or {}
            self._itemH = self._itemH or {}
            self._itemY[i] = contentH
            self._itemH[i] = height
            contentH = contentH + height

            if not item.separator then
                if item.checked then
                    hasChecks = true
                end
                if item.icon ~= nil then
                    hasIcons = true
                end
                if item.iconRight ~= nil then
                    hasRightIcons = true
                end
                if item.submenu ~= nil then
                    hasSubmenu = true
                end
            end
        end

        self._hasChecks = hasChecks
        self._hasIcons = hasIcons
        self._hasRightIcons = hasRightIcons
        self._hasSubmenu = hasSubmenu
        self._contentH = contentH

        local leftSlots = (hasChecks and (self.iconSize + self.gap) or 0)
            + (hasIcons and (self.iconSize + self.gap) or 0)
        local rightSlots = (hasRightIcons and (self.iconSize + self.gap) or 0)
            + (hasSubmenu and (self.arrowSize + self.gap) or 0)

        for i = 1, #self.items do
            local item = self.items[i]
            if item.separator then
                item._label = ""
                item._shortcutW = 0
            else
                local shortcutW = item.shortcut ~= nil
                    and manager:MeasureStringX(self.font, item.shortcut)
                    or 0
                item._shortcutW = shortcutW
                local natural = 16 + leftSlots + rightSlots
                    + manager:MeasureStringX(self.font, item.label)
                    + (shortcutW > 0 and (self.gap + shortcutW) or 0)
                if natural > widest then
                    widest = natural
                end
            end
        end

        self.w = math.max(self.minWidth, math.min(self.maxWidth, widest))
        self.h = math.max(
            self.itemHeight + self.padding * 2,
            math.min(self.maxHeight, self._contentH + self.padding * 2)
        )
        self:_updateViewport()

        for i = 1, #self.items do
            local item = self.items[i]
            if not item.separator then
                local shortcutW = item._shortcutW or 0
                local available = self.w - 16 - leftSlots - rightSlots
                    - (shortcutW > 0 and (self.gap + shortcutW) or 0)
                item._label = Pallid.UI.truncateText(item.label, self.font, math.max(0, available))
            end
        end
    end

    --- Recomputes the visible content height and scroll limit after a height change.
    function Menu:_updateViewport()
        self._viewH = math.max(0, self.h - self.padding * 2)
        self._maxScroll = math.max(0, self._contentH - self._viewH)
        self.scrollY = math.max(0, math.min(self.scrollY, self._maxScroll))
    end

    --- Positions the menu at root-local coordinates and clamps it to the root.
    --- @param root PallidWidget|nil Root that owns the menu.
    --- @param x number Root-local X.
    --- @param y number Root-local Y.
    --- @return PallidMenu self For chaining.
    function Menu:position(root, x, y)
        self:measure()
        self.root = root
        if root ~= nil and self.h > root.h - 4 then
            self.h = math.max(self.itemHeight + self.padding * 2, root.h - 4)
            self:_updateViewport()
        end

        x = math.floor(x or 0)
        y = math.floor(y or 0)
        if root ~= nil then
            local maxX = math.max(2, root.w - self.w - 2)
            local maxY = math.max(2, root.h - self.h - 2)
            x = math.max(2, math.min(x, maxX))
            y = math.max(2, math.min(y, maxY))
        else
            x = math.max(2, x)
            y = math.max(2, y)
        end

        self:_closeSubmenu()
        self.x = x
        self.y = y
        self.visible = true
        self.hover = 0
        self.scrollY = 0
        self.scrollDragging = false
        self._ox = 0
        self._oy = 0
        return self
    end

    --- Returns the scrollbar rectangle.
    --- @return number|nil x Scrollbar track X, or nil when scrolling is not needed.
    --- @return number|nil y Scrollbar track Y.
    --- @return number|nil h Scrollbar track height.
    function Menu:scrollbarRect()
        if self._maxScroll <= 0 or self.h <= self.padding * 2 + 6 then
            return nil
        end
        return self.x + self.w - 6,
            self.y + self.padding + 2,
            self.h - self.padding * 2 - 4
    end

    --- Computes scrollbar track and thumb geometry, or nil without scrolling.
    --- @return number|nil x Track X.
    --- @return number|nil y Track Y.
    --- @return number|nil h Track height.
    --- @return number|nil thumbY Thumb Y.
    --- @return number|nil thumbH Thumb height.
    --- @return number|nil travel Thumb travel in pixels.
    function Menu:_scrollMetrics()
        local trackX, trackY, trackH = self:scrollbarRect()
        if trackX == nil then
            return nil
        end
        local thumbH = math.min(
            trackH,
            math.max(12, trackH * self._viewH / math.max(1, self._contentH))
        )
        local travel = math.max(0, trackH - thumbH)
        local thumbY = trackY + (self._maxScroll > 0 and travel * self.scrollY / self._maxScroll or 0)
        return trackX, trackY, trackH, thumbY, thumbH, travel
    end

    --- Returns the item at the point.
    --- @param px number Cursor X in root-local coordinates.
    --- @param py number Cursor Y in root-local coordinates.
    --- @return integer index Item under the cursor, or 0.
    function Menu:itemAt(px, py)
        if not self:isInside(px, py) then
            return 0
        end
        local innerX = self.x + self.padding
        if px < innerX or px >= self.x + self.w - self.padding then
            return 0
        end
        local contentY = py - self.y - self.padding + self.scrollY
        for i = 1, #self.items do
            local top = self._itemY[i] or 0
            local bottom = top + (self._itemH[i] or self.itemHeight)
            if contentY >= top and contentY < bottom then
                return i
            end
        end
        return 0
    end

    --- Returns the rectangle of an item.
    --- @param index integer Item index.
    --- @return number x Root-local X.
    --- @return number y Root-local Y.
    --- @return number w Width.
    --- @return number h Height.
    function Menu:itemRect(index)
        return self.x + self.padding,
            self.y + self.padding + (self._itemY[index] or 0) - self.scrollY,
            self.w - self.padding * 2,
            self._itemH[index] or self.itemHeight
    end
end
