require "pallid/ui/widgets/widget/core"
require "pallid/ui/api/clip"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widget = Pallid.UI.Widgets.Widget

--- Hides or shows native child elements (text boxes). Call with false before
--- drawing a frame so only the elements actually drawn stay visible.
--- @param visible boolean False hides every registered native box.
function Widget:setNativeVisible(visible)
    local list = self.children
    if list ~= nil then
        for i = 1, #list do
            list[i]:setNativeVisible(visible)
        end
    end

    local modal = self.modal
    if modal ~= nil then
        modal:setNativeVisible(visible)
    end
    local popover = self.openPopover
    if popover ~= nil then
        popover:setNativeVisible(visible)
    end
    local menu = self.openMenu
    if menu ~= nil then
        menu:setNativeVisible(visible)
    end
end

--- Unfocuses every native text box in the subtree.
function Widget:blurNative()
    local list = self.children
    if list ~= nil then
        for i = 1, #list do
            list[i]:blurNative()
        end
    end

    local modal = self.modal
    if modal ~= nil then
        modal:blurNative()
    end
    local popover = self.openPopover
    if popover ~= nil then
        popover:blurNative()
    end
    local menu = self.openMenu
    if menu ~= nil then
        menu:blurNative()
    end
end

--- Registers a native text box on the root, so overlays can mask it later in
--- the frame. Called by `Input:drawSelf`; native boxes are not tree children.
--- @param native PallidInputBase Native text box owned by a widget.
function Widget:registerNative(native)
    if self._nativeList == nil then
        self._nativeList = {}
    end
    local list = self._nativeList
    list[#list + 1] = native
end

--- Removes a widget from the root's native registry. Widgets that own a native
--- element must call this when they leave the tree: the registry is a plain Lua
--- table and would otherwise keep the detached widget reachable.
--- @param native PallidWidget Native owner previously passed to `registerNative`.
function Widget:unregisterNative(native)
    local list = self._nativeList
    if list == nil then
        return
    end
    for i = #list, 1, -1 do
        if list[i] == native then
            table.remove(list, i)
            return
        end
    end
end

--- Hides registered native boxes that intersect an overlay rectangle, except
--- boxes that belong to the overlay itself. Coordinates are root-local.
--- @param overlay PallidWidget Overlay whose own subtree is kept visible.
--- @param x number Rectangle left in root-local coordinates.
--- @param y number Rectangle top in root-local coordinates.
--- @param w number Rectangle width in pixels.
--- @param h number Rectangle height in pixels.
function Widget:maskNative(overlay, x, y, w, h)
    local list = self._nativeList
    if list ~= nil then
        for i = 1, #list do
            list[i]:maskNative(overlay, x, y, w, h)
        end
    end
end

--- Hides every registered native box outside the overlay's subtree. Used by
--- the modal backdrop, which covers the whole root.
--- @param overlay PallidWidget Overlay whose own subtree is kept visible.
function Widget:maskNativeExcept(overlay)
    local list = self._nativeList
    if list ~= nil then
        for i = 1, #list do
            list[i]:maskNativeExcept(overlay)
        end
    end
end

--- Draws the tooltip of a hovered widget, if it has one. Shared by the tree and
--- the modal branch so both keep the same fade-in animation. Tooltips paint on
--- the native always-on-top host so they stay above native text boxes.
--- @param root PallidWidget Root that owns the cursor position.
--- @param el ISUIElement Host element the overlays are rendered into.
--- @param now number Current time in seconds.
--- @param ox number Origin X that `draw` used.
--- @param oy number Origin Y that `draw` used.
--- @param hovered PallidWidget|nil Widget under the cursor.
local function drawTooltip(root, el, now, ox, oy, hovered)
    local host = Pallid.UI.TooltipHost
    if hovered == nil or hovered.visible == false
        or hovered.tooltip == nil or hovered.tooltip:isEmpty()
        or root.mouseX == nil then
        if host ~= nil then
            host.hide()
        end
        return
    end
    if host ~= nil and host.show ~= nil then
        host.show(
            hovered.tooltip,
            root.mouseX + ox + 14,
            root.mouseY + oy + 12,
            now,
            ox + root.w,
            oy + root.h
        )
        return
    end
    hovered.tooltip:show(now)
    hovered.tooltip:draw(el, root.mouseX + ox + 14, root.mouseY + oy + 12,
        now, ox + root.w, oy + root.h)
end

--- Draws the active drag ghost above every overlay layer. The drag module is
--- looked up at call time: requiring it here would create a require cycle with
--- the widget root, and the ghost is optional for trees that never drag.
--- @param root PallidWidget Root that owns the drag session.
--- @param el ISUIElement Host element.
--- @param ox number Root origin X.
--- @param oy number Root origin Y.
local function drawDragGhost(root, el, ox, oy)
    local drag = Pallid.UI.DragDrop
    if drag == nil or drag.drawGhost == nil then
        return
    end
    drag.drawGhost(root, el, ox, oy)
end

--- Draws every overlay the root owns and then the tooltip of the hovered
--- widget. Call after `draw`.
--- @param el ISUIElement Host element the overlays are rendered into.
--- @param now number Current time in seconds.
--- @param ox number|nil Origin X that `draw` used, when the tree does not start at 0.
--- @param oy number|nil Origin Y that `draw` used.
function Widget:drawOverlay(el, now, ox, oy)
    ox = ox or 0
    oy = oy or 0

    -- Overlays are outside the tree's clips. Drop any software clip left by the
    -- tree so tooltips and menus are never culled by a stale rectangle.
    if Pallid.UI.resetClip ~= nil then
        Pallid.UI.resetClip(el)
    end

    local modal = self.modal
    if modal ~= nil then
        modal:drawModal(el, ox, oy, self.w, self.h)

        -- Popups/menus/popovers opened from modal content are still overlays and
        -- must paint above the dialog, exactly as they do above the normal tree.
        local modalPopover = self.openPopover
        if modalPopover ~= nil then
            modalPopover:draw(el, modalPopover._ox or ox, modalPopover._oy or oy)
        end
        local modalPopup = self.openPopup
        if modalPopup ~= nil then
            modalPopup:draw(el, modalPopup._ox or ox, modalPopup._oy or oy)
            modalPopup:drawPopup(el)
        end
        local modalMenu = self.openMenu
        if modalMenu ~= nil then
            modalMenu:draw(el, modalMenu._ox or 0, modalMenu._oy or 0)
        end

        -- The dim covers everything, so only inputs inside the dialog remain.
        self:maskNativeExcept(modal)
        drawDragGhost(self, el, ox, oy)
        drawTooltip(self, el, now, ox, oy, modal._hovered)
        return
    end

    local popover = self.openPopover
    if popover ~= nil then
        popover:draw(el, popover._ox or ox, popover._oy or oy)
    end

    local popup = self.openPopup
    if popup ~= nil then
        popup:draw(el, popup._ox or ox, popup._oy or oy)
        popup:drawPopup(el)
    end

    local menu = self.openMenu
    if menu ~= nil then
        menu:draw(el, menu._ox or 0, menu._oy or 0)
    end

    -- Native text boxes are always-on-top UIManager elements, so they would
    -- draw over the overlays above. Hide only the ones the overlay covers.
    local openMenu = self.openMenu
    while openMenu ~= nil do
        self:maskNative(openMenu, openMenu:originX(), openMenu:originY(), openMenu.w, openMenu.h)
        openMenu = openMenu.openSubmenu
    end
    if popup ~= nil then
        local px, py, pw, ph = popup:listRect()
        self:maskNative(popup, px, py, pw, ph)
    end
    if popover ~= nil then
        self:maskNative(popover, popover:originX(), popover:originY(), popover.w, popover.h)
    end

    drawDragGhost(self, el, ox, oy)
    drawTooltip(self, el, now, ox, oy, self.hovered)
end
