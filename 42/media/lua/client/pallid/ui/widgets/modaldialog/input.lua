require "pallid/ui/internal"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Adds mouse/keyboard routing to the ModalDialog class.
--- @param Modal table PallidModalDialog class.
--- @return fun Augmenter that installs the methods.
return function(Modal)
    --- Handles a key press.
    --- @param key integer Keyboard.KEY_* value.
    function Modal:keyPress(key)
        if not self.visible then
            return
        end
        local root = self.root
        if key == Keyboard.KEY_ESCAPE and root ~= nil then
            if root.openPopup ~= nil then
                root.openPopup:close()
                return
            end
            if root.openPopover ~= nil then
                local content = root.openPopover.content
                if content ~= nil and content.onCancel ~= nil then
                    content:onCancel()
                else
                    root.openPopover:close()
                end
                return
            end
            if root.openMenu ~= nil then
                root.openMenu:close()
                return
            end
        end

        if key == Keyboard.KEY_RETURN then
            local index = self:_findButton("positive")
            if index ~= nil and not self.buttons[index].disabled then
                self:_activateButton(index)
            end
            return
        end
        if key == Keyboard.KEY_ESCAPE and self.allowEscape then
            local index = self:_findButton("negative")
            if index ~= nil and not self.buttons[index].disabled then
                self:_activateButton(index)
            else
                self:close()
            end
        end
    end

    --- Handles a mouse press.
    --- @param px number Cursor X.
    --- @param py number Cursor Y.
    --- @param button string|nil "left" or "right".
    function Modal:mouseDown(px, py, button)
        self._ox = 0
        self._oy = 0
        if not self.visible or button == "right" then
            return
        end
        local root = self.root
        if root ~= nil then
            if root.openMenu ~= nil then
                if not root.openMenu:routeDown(px, py) then
                    root.openMenu:close()
                    root.openMenu = nil
                end
                return
            end
            if root.openPopup ~= nil then
                local popup = root.openPopup
                popup._ox = popup._openOx or popup._ox
                popup._oy = popup._openOy or popup._oy
                if popup:isInside(px, py) then
                    local target = popup:findDown(px, py, popup._ox, popup._oy, button)
                    if target ~= nil then
                        self._capture = target
                        self._captureOx, self._captureOy = target._ox, target._oy
                    end
                else
                    popup:close()
                    root.openPopup = nil
                end
                return
            end
            if root.openPopover ~= nil then
                local popover = root.openPopover
                popover._ox = popover._openOx or popover._ox
                popover._oy = popover._openOy or popover._oy
                if popover:isInside(px, py) then
                    local target = popover:findDown(px, py, popover._ox, popover._oy, button) or popover
                    self._capture = target
                    self._captureOx, self._captureOy = target._ox, target._oy
                else
                    popover:close()
                    root.openPopover = nil
                end
                return
            end
        end

        if not Widgets.Widget.isInside(self, px, py) then
            if self.closeOnBackdrop then
                self:close()
            end
            return
        end

        local list = self.children
        if list ~= nil then
            for i = #list, 1, -1 do
                local hit = list[i]:findDown(px, py, self:originX(), self:originY(), button)
                if hit ~= nil then
                    if hit.acceptsFocus then
                        hit:focus()
                    end
                    self._capture = hit
                    self._captureOx, self._captureOy = hit._ox, hit._oy
                    return
                end
            end
        end

    end

    --- Handles a mouse release.
    --- @param px number Cursor X.
    --- @param py number Cursor Y.
    --- @param button string|nil "left" or "right".
    function Modal:mouseUp(px, py, button)
        if self.root ~= nil and self.root.openMenu ~= nil then
            self.root.openMenu:routeUp(px, py)
            return
        end
        local target = self._capture
        self._capture = nil
        if target ~= nil then
            target._ox = self._captureOx or target._ox
            target._oy = self._captureOy or target._oy
            target:onUp(px, py, button)
            self._captureOx, self._captureOy = nil, nil
        end
    end

    --- Handles mouse movement.
    --- @param px number Cursor X.
    --- @param py number Cursor Y.
    function Modal:mouseMove(px, py)
        self._ox = 0
        self._oy = 0
        local target = self._capture
        if target ~= nil then
            target._ox = self._captureOx or target._ox
            target._oy = self._captureOy or target._oy
            target:onMove(px, py)
            return
        end

        local root = self.root
        if root ~= nil and root.openMenu ~= nil then
            root.openMenu:routeMove(px, py)
            return
        end

        local hovered = nil
        local popup = root ~= nil and root.openPopup or nil
        if popup ~= nil then
            popup._ox = popup._openOx or popup._ox
            popup._oy = popup._openOy or popup._oy
            if popup:isInside(px, py) then
                hovered = popup:findHover(px, py, popup._ox, popup._oy) or popup
            end
        end
        if hovered == nil and root ~= nil and root.openPopover ~= nil then
            local popover = root.openPopover
            popover._ox = popover._openOx or popover._ox
            popover._oy = popover._openOy or popover._oy
            if popover:isInside(px, py) then
                hovered = popover:findHover(px, py, popover._ox, popover._oy) or popover
            end
        end

        if hovered == nil then
            local list = self.children
            if list ~= nil then
                for i = #list, 1, -1 do
                    local hit = list[i]:findHover(px, py, self:originX(), self:originY())
                    if hit ~= nil then
                        hovered = hit
                        break
                    end
                end
            end
        end

        if hovered ~= self._hovered then
            local previous = self._hovered
            if previous ~= nil then
                previous._hover = false
                previous:onHoverEnd()
            end
            self._hovered = hovered
            if hovered ~= nil then
                hovered._hover = true
                hovered:onHoverStart()
            end
        end
        if hovered ~= nil then
            hovered:onHoverMove(px, py)
        end
    end

    --- Handles a mouse-wheel event.
    --- @param px number Cursor X.
    --- @param py number Cursor Y.
    --- @param delta number Wheel steps.
    --- @return boolean handled True while the dialog is open.
    function Modal:mouseWheel(px, py, delta)
        if not self.visible then
            return false
        end
        local root = self.root
        if root ~= nil and root.openMenu ~= nil then
            root.openMenu:onWheel(delta)
            return true
        end
        local popup = root ~= nil and root.openPopup or nil
        if popup ~= nil and popup:isInside(px, py) then
            popup:onWheel(delta)
            return true
        end
        local popover = root ~= nil and root.openPopover or nil
        if popover ~= nil and popover:isInside(px, py) then
            local target = popover:findWheel(px, py, popover._ox, popover._oy)
            if target ~= nil then
                target:onWheel(delta)
            end
            return true
        end
        local list = self.children
        if list ~= nil then
            for i = #list, 1, -1 do
                local target = list[i]:findWheel(px, py, self:originX(), self:originY())
                if target ~= nil then
                    target:onWheel(delta)
                    return true
                end
            end
        end
        return true
    end
end
