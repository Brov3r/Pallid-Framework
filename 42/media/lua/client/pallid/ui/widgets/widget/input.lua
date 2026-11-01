require "pallid/ui/widgets/widget/core"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widget = Pallid.UI.Widgets.Widget

--- Depth-first search, topmost child first. Stores `_ox/_oy` on every visited
--- widget so captured drags can keep using `originX()`.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this widget's parent.
--- @param oy number Origin Y of this widget's parent.
--- @param button string|nil "left" or "right".
--- @return PallidWidget|nil target Topmost widget that accepted the press.
function Widget:findDown(px, py, ox, oy, button)
    self._ox = ox
    self._oy = oy
    if not self.visible then
        return nil
    end

    local inside = self:isInside(px, py)
    if self.clipChildren == true and not inside then
        return nil
    end

    local list = self.children
    if list ~= nil then
        local cx, cy = self:originX(), self:originY()
        for i = #list, 1, -1 do
            local child = list[i]
            local chx, chy = cx + child.x, cy + child.y
            -- Zero-sized layout containers are traversed unconditionally: they
            -- have no box of their own, but their children do.
            if child.w <= 0 or child.h <= 0
                or (px >= chx and px < chx + child.w and py >= chy and py < chy + child.h) then
                local hit = child:findDown(px, py, cx, cy, button)
                if hit ~= nil then
                    return hit
                end
            end
        end
    end

    -- `hittable = false` disables only the widget itself; its children above
    -- still receive events while the cursor is inside the box.
    if inside and self.hittable ~= false and self:onDown(px, py, button) then
        return self
    end
    return nil
end

--- Like findDown, but returns the topmost hoverable widget instead of asking it
--- to accept a press.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this widget's parent.
--- @param oy number Origin Y of this widget's parent.
--- @return PallidWidget|nil hovered Topmost widget under the cursor.
function Widget:findHover(px, py, ox, oy)
    self._ox = ox
    self._oy = oy
    if not self.visible then
        return nil
    end

    local inside = self:isInside(px, py)
    if self.clipChildren == true and not inside then
        return nil
    end

    local list = self.children
    if list ~= nil then
        local cx, cy = self:originX(), self:originY()
        for i = #list, 1, -1 do
            local child = list[i]
            local chx, chy = cx + child.x, cy + child.y
            if child.w <= 0 or child.h <= 0
                or (px >= chx and px < chx + child.w and py >= chy and py < chy + child.h) then
                local hit = child:findHover(px, py, cx, cy)
                if hit ~= nil then
                    return hit
                end
            end
        end
    end

    if inside and self.hittable ~= false then
        return self
    end
    return nil
end

--- Finds the innermost widget that handles the wheel. Children are traversed
--- without a bounds pre-filter because a non-clipping parent may render them
--- outside its own box; clipping containers override this method anyway.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this widget's parent.
--- @param oy number Origin Y of this widget's parent.
--- @return PallidWidget|nil target Widget with an overridden onWheel, if any.
function Widget:findWheel(px, py, ox, oy)
    self._ox = ox
    self._oy = oy
    if not self.visible then
        return nil
    end

    local inside = self:isInside(px, py)
    if self.clipChildren == true and not inside then
        return nil
    end

    local list = self.children
    if list ~= nil then
        local cx, cy = self:originX(), self:originY()
        for i = #list, 1, -1 do
            local hit = list[i]:findWheel(px, py, cx, cy)
            if hit ~= nil then
                return hit
            end
        end
    end

    if inside and self.onWheel ~= Widget.onWheel then
        return self
    end
    return nil
end

--- Defaults: a widget ignores input unless it overrides these.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the press was consumed.
function Widget:onDown(px, py, button) -- luacheck: ignore
    return false
end

--- Called on the release that matches the press which captured the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Widget:onUp(px, py) -- luacheck: ignore
end

--- Called on every cursor move while the widget is the active capture.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Widget:onMove(px, py) -- luacheck: ignore
end

--- Handles a mouse-wheel event.
--- @param delta number Wheel steps; positive is up.
--- @return boolean handled True when the wheel was consumed.
function Widget:onWheel(delta) -- luacheck: ignore
    return false
end

--- Root entry points. The window calls these with widget-local mouse coords.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" (default) or "right".
--- @return boolean handled True when a widget consumed the press.
function Widget:mouseDown(px, py, button)
    button = button or "left"
    self._ox, self._oy = 0, 0

    -- A capture owns the pointer until its matching release. Without this
    -- guard a lost mouse-up (alt-tab, release outside the window) leaves a drag
    -- or a keybind recording orphaned, and the next press overwrites it.
    -- Different buttons are still delivered: keybind captures the right button
    -- while listening, and a drag cancels itself on a non-left press.
    if self.capture ~= nil and self.modal == nil then
        if button ~= (self.captureButton or "left") then
            self.capture:onDown(px, py, button)
        end
        return true
    end

    local modal = self.modal
    if modal ~= nil then
        -- The modal owns input. A capture from the page below (for example a
        -- drag that opened the dialog) must not survive and swallow presses
        -- after the dialog closes.
        self.capture = nil
        self.captureButton = nil
        self.captureOx, self.captureOy = nil, nil
        modal:mouseDown(px, py, button)
        return true
    end

    local menu = self.openMenu
    if menu ~= nil then
        if menu:routeDown(px, py) then
            return true
        end
        -- A right click always closes and continues so a context menu can open
        -- on the row under the cursor in one press. Menu-bar dropdowns also
        -- continue on a left click, so the clicked control stays usable.
        local passThrough = button == "right" or menu.passThroughOutside == true
        menu:close()
        self.openMenu = nil
        if not passThrough then
            return true
        end
    end

    -- Overlays win over the tree: an open popup must stay clickable even when
    -- later siblings overlap it.
    local popup = self.openPopup
    if popup ~= nil then
        popup._ox = popup._openOx or popup._ox
        popup._oy = popup._openOy or popup._oy
        if popup:isInside(px, py) then
            local target = popup:findDown(px, py, popup._ox, popup._oy, button)
            if target ~= nil then
                self.capture = target
                self.captureButton = button
                self.captureOx, self.captureOy = target._ox, target._oy
            end
            -- Consume everything that landed on the popup, padding included,
            -- so the press cannot reach a widget drawn underneath it.
            return true
        end
        popup:close()
        self.openPopup = nil
        return true
    end

    local popover = self.openPopover
    if popover ~= nil then
        popover._ox = popover._openOx or popover._ox
        popover._oy = popover._openOy or popover._oy
        if popover:isInside(px, py) then
            local target = popover:findDown(px, py, popover._ox, popover._oy, button) or popover
            if button == "left" and self.focused ~= nil and target ~= self.focused and target.acceptsFocus ~= true then
                -- Clicking the picker field, for example, must drop focus from
                -- the hex input so typing goes to the game again.
                self.focused:blur()
            end
            self.capture = target
            self.captureButton = button
            self.captureOx, self.captureOy = target._ox, target._oy
            return true
        end
        popover:close()
        self.openPopover = nil
        return true
    end

    local target = self:findDown(px, py, 0, 0, button)

    if button == "left" and target ~= self.focused then
        if self.focused ~= nil then
            self.focused:blur()
        end
        if target ~= nil and target.acceptsFocus then
            target:focus()
        end
    end

    if button == "left" then
        self.capture = target
        self.captureButton = target ~= nil and button or nil
        if target ~= nil then
            self.captureOx, self.captureOy = target._ox, target._oy
        else
            self.captureOx, self.captureOy = nil, nil
        end
    end
    return target ~= nil
end

--- Handles a mouse release.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil Button being released; nil means "left".
--- @return boolean handled True when an active capture received the release.
function Widget:mouseUp(px, py, button)
    if self.modal ~= nil then
        self.modal:mouseUp(px, py, button)
        return true
    end
    local menu = self.openMenu
    if menu ~= nil then
        menu:routeUp(px, py)
        self.capture = nil
        self.captureButton = nil
        self.captureOx, self.captureOy = nil, nil
        return true
    end

    local target = self.capture
    if target == nil then
        return false
    end
    -- Releasing another button must not abort a drag started with the first
    -- one; only the button that set the capture may end it.
    if (button or "left") ~= (self.captureButton or "left") then
        return false
    end

    self.capture = nil
    self.captureButton = nil
    -- Draw may have overwritten the input-space origin; restore it so onUp
    -- works in the same coordinates as onMove.
    target._ox = self.captureOx or target._ox
    target._oy = self.captureOy or target._oy
    target:onUp(px, py)
    self.captureOx, self.captureOy = nil, nil
    return true
end

--- Handles mouse movement.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean handled True when the move was consumed by a capture or hovered widget.
function Widget:mouseMove(px, py)
    self.mouseX = px
    self.mouseY = py

    if self.modal ~= nil then
        self.modal:mouseMove(px, py)
        return true
    end

    local menu = self.openMenu
    if menu ~= nil then
        menu:routeMove(px, py)
        return true
    end

    local target = self.capture
    if target ~= nil then
        target._ox = self.captureOx or target._ox
        target._oy = self.captureOy or target._oy
        target:onMove(px, py)
        return true
    end

    local hovered = nil

    local popup = self.openPopup
    if popup ~= nil then
        popup._ox = popup._openOx or popup._ox
        popup._oy = popup._openOy or popup._oy
        if popup:isInside(px, py) then
            hovered = popup:findHover(px, py, popup._ox, popup._oy) or popup
        end
    end

    if hovered == nil then
        local popover = self.openPopover
        if popover ~= nil then
            popover._ox = popover._openOx or popover._ox
            popover._oy = popover._openOy or popover._oy
            if popover:isInside(px, py) then
                hovered = popover:findHover(px, py, popover._ox, popover._oy) or popover
            end
        end
    end

    if hovered == nil then
        hovered = self:findHover(px, py, 0, 0)
    end

    if hovered ~= self.hovered then
        local previous = self.hovered
        if previous ~= nil then
            previous._hover = false
            previous:onHoverEnd()
        end
        self.hovered = hovered
        if hovered ~= nil then
            hovered._hover = true
            hovered:onHoverStart()
        end
    end
    if hovered ~= nil then
        hovered:onHoverMove(px, py)
    end
    return hovered ~= nil
end

--- Handles a mouse-wheel event.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param delta number Wheel steps; positive is up.
--- @return boolean handled True when a widget consumed the wheel.
function Widget:mouseWheel(px, py, delta)
    self.mouseX = px
    self.mouseY = py

    if self.modal ~= nil then
        self.modal:mouseWheel(px, py, delta)
        return true
    end
    local menu = self.openMenu
    if menu ~= nil then
        menu:onWheel(delta)
        return true
    end

    -- A popover is drawn above the tree, so route the wheel to it first.
    local popover = self.openPopover
    if popover ~= nil then
        popover._ox = popover._openOx or popover._ox
        popover._oy = popover._openOy or popover._oy
        if popover:isInside(px, py) then
            local target = popover:findWheel(px, py, popover._ox, popover._oy)
            if target ~= nil then
                return target:onWheel(delta)
            end
            -- Consume the wheel even over the popover padding, otherwise the
            -- world zoom reacts under the open popover.
            return true
        end
    end

    local popup = self.openPopup
    if popup ~= nil and popup:isInside(px, py) then
        popup._ox = popup._openOx or popup._ox
        popup._oy = popup._openOy or popup._oy
        popup:onWheel(delta)
        return true
    end

    local target = self:findWheel(px, py, 0, 0)
    if target == nil then
        return false
    end
    return target:onWheel(delta)
end

--- Called when the cursor enters the widget.
function Widget:onHoverStart() -- luacheck: ignore
end

--- Called every frame while the widget is hovered, with the current cursor.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Widget:onHoverMove(px, py) -- luacheck: ignore
end

--- Called when the cursor leaves the widget; drops the tooltip fade so the next
--- hover plays it again.
function Widget:onHoverEnd() -- luacheck: ignore
    if self.tooltip ~= nil then
        self.tooltip:reset()
    end
end

--- Drops the mouse capture if this widget owns it. Used when a drag or a
--- recording ends without a matching release (lost mouse-up, watchdog cancel).
function Widget:releaseCapture()
    local root = self:getRoot()
    if root ~= nil and root.capture == self then
        root.capture = nil
        root.captureButton = nil
        root.captureOx, root.captureOy = nil, nil
    end
end

--- Returns the root node.
--- @return PallidWidget root Topmost widget of the tree this one belongs to.
function Widget:getRoot()
    local node = self
    while node.parent ~= nil do
        node = node.parent
    end
    return node
end

--- Gives keyboard focus to the widget, blurring the previous owner. Calling it
--- on the widget that already owns focus is a no-op.
function Widget:focus()
    local root = self:getRoot()
    if root.focused == self then
        return
    end
    if root.focused ~= nil then
        root.focused:onBlur()
    end
    root.focused = self
    self:onFocus()
end

--- Releases focus.
--- @return boolean hadFocus True when the widget owned the keyboard focus.
function Widget:blur()
    local root = self:getRoot()
    if root.focused == self then
        root.focused = nil
        self:onBlur()
        return true
    end
    return false
end

--- Called when the widget receives keyboard focus.
function Widget:onFocus() -- luacheck: ignore
end

--- Called when the widget loses keyboard focus.
function Widget:onBlur() -- luacheck: ignore
end

--- Routes a key press to the focused widget, if any.
--- @param key integer Keyboard.KEY_* value.
--- @return boolean handled True when a widget consumed the key.
function Widget:keyPress(key)
    local modal = self.modal
    if modal ~= nil then
        modal:keyPress(key)
        return true
    end

    -- An open popup may want to handle keys itself (Escape to cancel).
    local popup = self.openPopup
    if popup ~= nil and popup.onKeyPress ~= nil
        and popup.onKeyPress ~= Widget.onKeyPress
        and popup:onKeyPress(key) then
        return true
    end

    -- Escape closes an open popover (color/date pickers) even while a native
    -- text field owns the focus.
    local popover = self.openPopover
    if popover ~= nil and Keyboard ~= nil and key == Keyboard.KEY_ESCAPE then
        -- Content may expose onCancel, so Enter-like pickers can revert the
        -- value instead of committing it on close.
        local content = popover.content
        if content ~= nil and content.onCancel ~= nil then
            content:onCancel()
        else
            popover:close()
        end
        return true
    end

    local target = self.focused
    if target ~= nil and target.visible then
        target:onKeyPress(key)
        return true
    end
    return false
end

--- Override to handle a key press while the widget owns the focus.
--- @param key integer Keyboard.KEY_* value.
function Widget:onKeyPress(key) -- luacheck: ignore
end
