Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

--- Adds native-box visibility and overlay helpers to the input class.
--- @param Input table PallidInputBase class.
--- @return fun Augmenter that installs the methods.
return function(Input)
    --- @param input PallidWidget Widget to test.
    --- @param overlay PallidWidget Overlay being checked.
    --- @return boolean inside True when `input` belongs to the overlay's subtree.
    local function isInsideOverlay(input, overlay)
        local node = input
        while node ~= nil do
            if node == overlay then
                return true
            end
            node = node.parent
        end
        return false
    end

    --- Shows or hides the native input boxes.
    --- @param visible boolean False hides the native box until the next draw.
    function Input:setNativeVisible(visible)
        if self.box ~= nil then
            self.box:setVisible(visible)
        end
    end

    --- Unfocuses this widget's native box without requiring a live root.
    function Input:blurNative()
        local root = self:getRoot()
        if root ~= nil and root.focused == self then
            root.focused = nil
        end
        if self.box ~= nil and self.box:isFocused() then
            self.box:unfocus()
        end
    end

    --- Hides the native box when an overlay rectangle covers it. The overlay's own
    --- inputs stay visible so forms inside a popover or modal still work.
    --- @param overlay PallidWidget Overlay whose subtree stays visible.
    --- @param x number Rectangle left in root-local coordinates.
    --- @param y number Rectangle top in root-local coordinates.
    --- @param w number Rectangle width in pixels.
    --- @param h number Rectangle height in pixels.
    function Input:maskNative(overlay, x, y, w, h)
        if self.box == nil or isInsideOverlay(self, overlay) then
            return
        end
        local bx, by = self._nativeLocalX, self._nativeLocalY
        local bw = self._nativeW or self.w
        local bh = self._nativeH or self.h
        if bx == nil or by == nil then
            return
        end
        if bx < x + w and bx + bw > x and by < y + h and by + bh > y then
            self.box:setVisible(false)
        end
    end

    --- Hides the native box unless it belongs to the overlay's subtree.
    --- @param overlay PallidWidget Overlay whose subtree stays visible.
    function Input:maskNativeExcept(overlay)
        if self.box ~= nil and not isInsideOverlay(self, overlay) then
            self.box:setVisible(false)
        end
    end

    --- Hides and blurs the native box when the input leaves the tree. Detached
    --- editors are recreated by composite widgets such as QueryBuilder, and a
    --- focused native box would otherwise stay always-on-top over the new row.
    function Input:onDetach()
        if self.box ~= nil then
            if self.box:isFocused() then
                self.box:unfocus()
            end
            self.box:setVisible(false)
        end
        local root = self._nativeRoot
        if root ~= nil then
            if root.focused == self then
                root.focused = nil
            end
            if root.unregisterNative ~= nil then
                root:unregisterNative(self)
            end
            self._nativeRoot = nil
        end
    end
end
