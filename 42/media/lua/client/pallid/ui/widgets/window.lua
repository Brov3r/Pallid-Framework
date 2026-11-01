require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/geometry"
require "pallid/ui/api/clip"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/button"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local RECT_SHAPE = Pallid.UI.Shape.rect()

local TITLE_HEIGHT = 26
local TITLE_PADDING = 8
local BUTTON = 22
local BUTTON_GAP = 4
local BUTTON_MARGIN = 8
local GRIP = 14
local GRIP_PADDING = 2
local TITLE_RADIUS = { tl = 4, tr = 4, br = 0, bl = 0 }

local ICON_DIR = "media/assets/ui/pallid/icons/"
local ICONS = {
    close    = "pallid_window_close",
    collapse = "pallid_window_collapse",
    expand   = "pallid_window_expand",
    pin      = "pallid_window_pin",
    pinActive = "pallid_window_pin_active",
    grip     = "pallid_window_grip",
}
Pallid.UI.Textures.registerIcon(ICONS.close, ICON_DIR .. "cross.png")
Pallid.UI.Textures.registerIcon(ICONS.collapse, ICON_DIR .. "minus.png")
Pallid.UI.Textures.registerIcon(ICONS.expand, ICON_DIR .. "plus.png")
Pallid.UI.Textures.registerIcon(ICONS.pin, ICON_DIR .. "pushpin.png")
Pallid.UI.Textures.registerIcon(ICONS.pinActive, ICON_DIR .. "anchor.png")
Pallid.UI.Textures.registerIcon(ICONS.grip, ICON_DIR .. "corner.png")

--- Floating panel with a title bar, coloured caption icons, a resize grip
--- and an optional content padding.
---
--- Pinning collapses the window to the title bar. While the cursor stays inside
--- the window (title or content) it expands, and it collapses again once the
--- cursor leaves. `collapsed` is an explicit state and does not expand on hover.
--- @class PallidWindow : PallidWidget
--- @field title string Window title shown on the left of the title bar.
--- @field collapsed boolean True collapses the window to the title bar.
--- @field pinned boolean True collapses to the title bar and expands on hover.
--- @field openT number Animated open amount, 0 (title only)..1 (full height).
--- @field padding number Content inset below the title bar, in pixels.
--- @field titleH number Title bar height in pixels.
--- @field closable boolean Draws the close button.
--- @field resizable boolean Allows resizing from the bottom-right grip.
--- @field minW number Minimum width while resizing.
--- @field minH number Minimum height while resizing.
--- @field closeColor PallidColor Close icon tint.
--- @field collapseColor PallidColor Collapse/expand icon tint.
--- @field pinColor PallidColor Pin icon tint while unpinned.
--- @field buttonActive PallidColor Pin icon tint while pinned.
--- @field gripColor PallidColor Resize grip tint.
--- @field closeButton PallidButton Close caption button.
--- @field collapseButton PallidButton Collapse/expand caption button.
--- @field pinButton PallidButton Pin caption button.
--- @field onClose fun(window: PallidWindow)|nil
--- @field onMoved fun(window: PallidWindow)|nil
--- @field onResized fun(window: PallidWindow)|nil
local Window = Widgets.class("Window")

--- @param window PallidWindow Window that owns the button.
--- @param iconName string Registered icon name.
--- @param iconColor PallidColor Icon tint.
--- @param onClick fun(button: PallidButton) Click handler.
--- @return PallidButton button Caption button bound to the window.
local function createCaptionButton(window, iconName, iconColor, onClick)
    local button = Widgets.button(0, 0, BUTTON, BUTTON, {
        icon = iconName,
        iconColor = iconColor,
        iconInset = 6,
        background = false,
        sound = false,
        onClick = onClick,
    })
    -- Drawn manually, so it is not in `children`. The parent link stops the
    -- base draw from treating it as a frame root and resetting the clip stack.
    button.parent = window
    return button
end

--- Creates a new `Window` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels when fully open.
--- @param opts table|nil Optional appearance and callbacks.
--- @field opts.title string|nil Window title; defaults to "Window".
--- @field opts.closable boolean|nil Draws the close button; defaults to true.
--- @field opts.resizable boolean|nil Allows resizing from the grip; defaults to true.
--- @field opts.pinned boolean|nil Starts pinned (title bar only, expands on hover).
--- @field opts.collapsed boolean|nil Starts collapsed to the title bar.
--- @field opts.padding number|nil Content inset below the title bar; defaults to 4.
--- @field opts.onClose fun(window: PallidWindow)|nil Called after the close button hides the window.
--- @field opts.onMoved fun(window: PallidWindow)|nil Called while the window is dragged.
--- @field opts.onResized fun(window: PallidWindow)|nil Called while the window is resized.
--- @return PallidWindow window New window instance.
function Window.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, Window)
    self:init(x, y, w, h)

    self.title = opts.title or "Window"
    self.closable = opts.closable ~= false
    self.resizable = opts.resizable ~= false
    self.collapsed = opts.collapsed or false
    self.pinned = opts.pinned or false
    self.openT = (opts.collapsed or opts.pinned) and 0 or 1
    self.padding = opts.padding or 4
    self.onClose = opts.onClose
    self.onMoved = opts.onMoved
    self.onResized = opts.onResized
    self.dragging = false
    self.resizing = false
    self.titleH = TITLE_HEIGHT
    self.minW = 120
    self.minH = 80

    self.fill = Pallid.UI.Color.surface
    self.titleFill = Pallid.UI.Color.surfaceMuted
    self.titleFillHover = Pallid.UI.Color.accentSoft
    self.borderColor = Pallid.UI.Color.border
    self.titleColor = Pallid.UI.Color.textPrimary
    self.closeColor = Pallid.UI.Color.error
    self.collapseColor = Pallid.UI.Color.warning
    self.pinColor = Pallid.UI.Color.primary
    self.buttonActive = Pallid.UI.Color.primaryStrong
    self.gripColor = Pallid.UI.Color.textMuted
    self.style = {
        font = Pallid.UI.Fonts.small,
        color = self.titleColor,
        alignH = "left",
        alignV = "middle",
    }

    self.closeButton = createCaptionButton(self, ICONS.close, self.closeColor, function()
        self:close()
    end)

    self.collapseButton = createCaptionButton(self, self:isOpen() and ICONS.collapse or ICONS.expand,
        self.collapseColor, function()
            self:toggleCollapsed()
        end)

    self.pinButton = createCaptionButton(self, ICONS.pin, self.pinColor, function()
        self:togglePinned()
    end)

    return self
end

--- Factory shortcut for `Window.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels when fully open.
--- @param opts table|nil Optional appearance and callbacks; see `Window.new`.
--- @return PallidWindow window New window instance.
function Widgets.window(x, y, w, h, opts)
    return Window.new(x, y, w, h, opts)
end

--- Height actually drawn, driven by the animated `openT`. Both collapsing and
--- pinning animate through the same value.
--- @return number height Drawn height in pixels.
function Window:effectiveHeight()
    return self.titleH + (self.h - self.titleH) * self.openT
end

--- Returns true while the popup is open.
--- @return boolean open True when the content is at least half visible.
function Window:isOpen()
    return self:effectiveHeight() > self.titleH + 0.5
end

--- Returns true when the point lies inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean inside True when the point is inside the drawn box.
function Window:isInside(px, py)
    local x, y = self:originX(), self:originY()
    return px >= x and px < x + self.w and py >= y and py < y + self:effectiveHeight()
end

--- Size available to children below the title bar, excluding the padding.
--- Children are positioned relative to the padded content origin, so a child at
--- (0, 0) sits in the top-left inner corner.
--- @return number w Inner width in pixels.
--- @return number h Inner height in pixels.
function Window:contentSize()
    local p = self.padding
    return math.max(0, self.w - p * 2), math.max(0, self.h - self.titleH - p * 2)
end

--- Hides the window and calls `onClose`.
function Window:close()
    self:setVisible(false)
    if self.onClose ~= nil then
        self.onClose(self)
    end
end

--- Toggles the explicit collapsed state. Pinned windows ignore it.
function Window:toggleCollapsed()
    if self.pinned then
        return
    end
    self.collapsed = not self.collapsed
end

--- Toggles pinning. Unpinning snaps the window fully open.
function Window:togglePinned()
    self.pinned = not self.pinned
    if not self.pinned then
        self.openT = self.collapsed and 0 or 1
    end
end

--- Absolute content rectangle (padding applied) for the current animated height.
--- @param window PallidWindow Window to measure.
--- @return number x Left coordinate in root-local space.
--- @return number y Top coordinate in root-local space.
--- @return number w Width in pixels.
--- @return number h Height in pixels.
local function contentBox(window)
    local p = window.padding
    return window:originX() + p,
        window:originY() + window.titleH + p,
        math.max(0, window.w - p * 2),
        math.max(0, window:effectiveHeight() - window.titleH - p * 2)
end

--- X of a caption button, right to left: close, collapse, pin.
--- @param window PallidWindow Window that owns the button.
--- @param kind string "close", "collapse" or "pin".
--- @return number x Left coordinate of the button box.
local function buttonX(window, kind)
    local right = window:originX() + window.w - BUTTON_MARGIN
    if kind == "close" then
        return right - BUTTON
    end
    if window.closable then
        right = right - BUTTON - BUTTON_GAP
    end
    if kind == "collapse" then
        return right - BUTTON
    end
    return right - BUTTON - BUTTON_GAP - BUTTON
end

--- @param window PallidWindow Window that owns the buttons.
--- @param zone string|nil Caption zone.
--- @return PallidButton|nil button Caption button for the zone, if any.
local function captionButton(window, zone)
    if zone == "close" then
        return window.closeButton
    end
    if zone == "collapse" then
        return window.collapseButton
    end
    if zone == "pin" then
        return window.pinButton
    end
    return nil
end

--- Positions the caption buttons and syncs their state from the window.
function Window:layoutCaptionButtons()
    local localY = (self.titleH - BUTTON) * 0.5
    local ox = self:originX()

    self.closeButton:setBounds(buttonX(self, "close") - ox, localY, BUTTON, BUTTON)
    self.collapseButton:setBounds(buttonX(self, "collapse") - ox, localY, BUTTON, BUTTON)
    self.pinButton:setBounds(buttonX(self, "pin") - ox, localY, BUTTON, BUTTON)

    self.closeButton.visible = self.closable
    self.closeButton.enabled = self.enabled
    -- Collapsing has no meaning while pinned: hover already expands the window.
    self.collapseButton.enabled = self.enabled and not self.pinned
    self.pinButton.enabled = self.enabled

    -- Icon tints follow the window fields, so replacing a color table at
    -- runtime is reflected on the next frame.
    self.closeButton.iconColor = self.closeColor
    self.collapseButton.iconColor = self.collapseColor
    self.pinButton.iconColor = self.pinned and self.buttonActive or self.pinColor

    self.pinButton:setIcon(self.pinned and ICONS.pinActive or ICONS.pin)

    -- A pinned window has no explicit collapse/expand state, so its collapse
    -- glyph must stay frozen. Otherwise hover-driven openT would flip it.
    if not self.pinned then
        -- Half-open threshold: a brief hover must not flip the glyph on the first
        -- frame of the pin animation. Plus means "will expand", minus "will collapse".
        local iconName = self.openT >= 0.5 and ICONS.collapse or ICONS.expand
        if self.collapseButton.icon ~= iconName then
            self.collapseButton:setIcon(iconName)
        end
    end
end

--- Returns the drop zone under the point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return string|nil zone "title", "body", "resize", "close", "collapse" or "pin".
function Window:hitZone(px, py)
    local x, y = self:originX(), self:originY()
    local height = self:effectiveHeight()
    if px < x or px >= x + self.w or py < y or py >= y + height then
        return nil
    end

    if py < y + self.titleH then
        if self.closable then
            local bx = buttonX(self, "close")
            if px >= bx and px < bx + BUTTON then
                return "close"
            end
        end
        local bx = buttonX(self, "collapse")
        if px >= bx and px < bx + BUTTON then
            return "collapse"
        end
        bx = buttonX(self, "pin")
        if px >= bx and px < bx + BUTTON then
            return "pin"
        end
        return "title"
    end

    -- A pinned window is only a title bar; resizing it while it floats open
    -- under the cursor would be confusing.
    if self.resizable and not self.pinned and self:isOpen() then
        if px >= x + self.w - GRIP and py >= y + height - GRIP then
            return "resize"
        end
    end
    return "body"
end

--- Zone under the cursor, or nil when the cursor is outside the window. Reads
--- the root's last mouse position because the window stops being the hovered
--- widget as soon as the cursor moves into its content.
--- @return string|nil zone Current pointer zone, or nil when outside.
function Window:pointerZone()
    local root = self:getRoot()
    if root == nil or root.mouseX == nil or root.mouseY == nil then
        return nil
    end
    if not self:isInside(root.mouseX, root.mouseY) then
        return nil
    end
    return self:hitZone(root.mouseX, root.mouseY)
end

--- Moves the window to the end of its parent's child list.
function Window:bringToTop()
    local parent = self.parent
    if parent == nil then
        return
    end
    parent:remove(self)
    parent:add(self)
end

--- Handles a pointer press inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the press was consumed.
function Window:onDown(px, py, button)
    local zone = self:hitZone(px, py)
    if zone == nil then
        return false
    end

    self:bringToTop()

    -- Right-click never closes, collapses, pins, drags or resizes, but it must
    -- not fall through to a window below.
    if button == "right" then
        return true
    end

    if zone == "close" then
        self:close()
        return true
    end
    if zone == "collapse" then
        if not self.pinned then
            self:toggleCollapsed()
        end
        return true
    end
    if zone == "pin" then
        self:togglePinned()
        return true
    end
    if zone == "title" then
        self.dragging = true
        self.dragOffsetX = self:originX() - px
        self.dragOffsetY = self:originY() - py
        return true
    end
    if zone == "resize" then
        self.resizing = true
        self.resizeStartX = px
        self.resizeStartY = py
        self.resizeStartW = self.w
        self.resizeStartH = self.h
        return true
    end
    return false
end

--- Handles pointer movement.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Window:onMove(px, py)
    if self.dragging then
        self.x = px + self.dragOffsetX - self._ox
        self.y = py + self.dragOffsetY - self._oy
        if self.onMoved ~= nil then
            self.onMoved(self)
        end
    elseif self.resizing then
        self.w = math.max(self.minW, self.resizeStartW + (px - self.resizeStartX))
        self.h = math.max(self.minH, self.resizeStartH + (py - self.resizeStartY))
        if self.onResized ~= nil then
            self.onResized(self)
        end
    end
end

--- Handles a pointer release.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Window:onUp(px, py)
    self.dragging = false
    self.resizing = false
end

--- Advances the open/collapse animation. Runs per rendered frame so the window
--- slides smoothly. A pinned window stays open while the cursor is anywhere
--- inside its drawn box, including the content.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function Window:onAnimate(now, dt)
    local inside = self:pointerZone() ~= nil
    local target
    if self.pinned then
        -- Pinning owns the open state: hover expands even if the window was
        -- explicitly collapsed before the pin was applied.
        target = inside and 1 or 0
    else
        target = self.collapsed and 0 or 1
    end
    self.openT = Widgets.approach(self.openT, target, 14, dt)
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the tree is rendered into.
function Window:drawSelf(el)
    local x, y = self:originX(), self:originY()
    local height = self:effectiveHeight()
    local titleH = self.titleH
    local zone = self:pointerZone()

    Pallid.UI.roundedRect(el, x, y, self.w, height, 4, self:shade(self.fill))
    Pallid.UI.roundedBorder(el, x, y, self.w, height, 4, 1, self:shade(self.borderColor, 2))

    local titleFill = zone == "title" and self.titleFillHover or self.titleFill
    Pallid.UI.roundedRect(el, x, y, self.w, titleH, TITLE_RADIUS, self:shade(titleFill))

    -- The title never runs under the caption buttons.
    local titleLeft = x + TITLE_PADDING
    local maxTitleWidth = buttonX(self, "pin") - 6 - titleLeft
    if self.title ~= "" and maxTitleWidth > 0 then
        self.style.maxWidth = maxTitleWidth
        local base = self.style.color
        self.style.color = self:shade(base)
        Pallid.UI.text(el, self.title, titleLeft, y + titleH * 0.5, self.style)
        self.style.color = base
    end

    self:layoutCaptionButtons()
    if self.closable then
        self.closeButton:draw(el, x, y)
    end
    self.collapseButton:draw(el, x, y)
    self.pinButton:draw(el, x, y)
end

--- The grip is drawn after the content so the children cannot cover it.
--- @param window PallidWindow Window that owns the grip.
--- @param el ISUIElement Host element the tree is rendered into.
local function drawGrip(window, el)
    if not window.resizable or window.pinned or not window:isOpen() then
        return
    end
    local gx = window:originX() + window.w - GRIP
    local gy = window:originY() + window:effectiveHeight() - GRIP
    Pallid.UI.icon(el, ICONS.grip, gx + GRIP_PADDING, gy + GRIP_PADDING,
        GRIP - GRIP_PADDING * 2, window:shade(window.gripColor, 3))
end

--- Content starts below the title bar, inside the padding, and is clipped to the
--- visible height.
--- @param el ISUIElement Host element the tree is rendered into.
function Window:drawChildren(el)
    if not self:isOpen() then
        return
    end
    local list = self.children
    if list ~= nil then
        local cx, cy, cw, ch = contentBox(self)
        if cw > 0 and ch > 0 then
            local entered = Pallid.UI.clip(el, RECT_SHAPE, cx, cy, cw, ch)
            for i = 1, #list do
                local child = list[i]
                if child.overlay ~= true then
                    child:draw(el, cx, cy)
                end
            end
            if (self._overlayCount or 0) > 0 then
                for i = 1, #list do
                    local child = list[i]
                    if child.overlay == true then
                        child:draw(el, cx, cy)
                    end
                end
            end
            if entered then
                Pallid.UI.clipEnd(el)
            end
        end
    end
    drawGrip(self, el)
end

--- Advances the window and the caption buttons. The buttons are not tree
--- children, so they need explicit forwarding.
--- @param now number Current game-tick time in seconds.
function Window:update(now)
    if not self.visible then
        return
    end
    Widgets.Widget.update(self, now)
    self.closeButton:update(now)
    self.collapseButton:update(now)
    self.pinButton:update(now)
end

--- Advances the open animation, the content and the caption buttons.
--- @param now number Current time in seconds.
function Window:updateAnimations(now)
    if not self.visible then
        return
    end
    Widgets.Widget.updateAnimations(self, now)
    self.closeButton:updateAnimations(now)
    self.collapseButton:updateAnimations(now)
    self.pinButton:updateAnimations(now)
end

--- Finds the child that handles a press at the given point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this window's parent.
--- @param oy number Origin Y of this window's parent.
--- @param button string|nil "left" or "right".
--- @return PallidWidget|nil target Topmost widget that accepted the press.
function Window:findDown(px, py, ox, oy, button)
    self._ox = ox
    self._oy = oy
    if not self.visible then
        return nil
    end

    local zone = self:hitZone(px, py)
    if zone == "close" or zone == "collapse" or zone == "pin" then
        self:bringToTop()
        self:layoutCaptionButtons()
        local btn = captionButton(self, zone)
        if btn ~= nil and btn.visible then
            local hit = btn:findDown(px, py, self:originX(), self:originY(), button)
            if hit ~= nil then
                return hit
            end
        end
        -- Right-click or a disabled button: consume without acting.
        return self
    end

    if zone == "title" or zone == "resize" then
        if self:onDown(px, py, button) then
            return self
        end
        return nil
    end

    if self:isOpen() then
        local list = self.children
        if list ~= nil then
            local cx, cy, cw, ch = contentBox(self)
            if cw > 0 and ch > 0 and px >= cx and px < cx + cw and py >= cy and py < cy + ch then
                for i = #list, 1, -1 do
                    local hit = list[i]:findDown(px, py, cx, cy, button)
                    if hit ~= nil then
                        return hit
                    end
                end
            end
        end
    end

    if zone ~= nil then
        return self
    end
    return nil
end

--- Finds the child that handles hover at the given point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this window's parent.
--- @param oy number Origin Y of this window's parent.
--- @return PallidWidget|nil hovered Topmost widget under the cursor.
function Window:findHover(px, py, ox, oy)
    self._ox = ox
    self._oy = oy
    if not self.visible then
        return nil
    end

    local zone = self:hitZone(px, py)
    if zone == nil then
        return nil
    end

    if zone == "close" or zone == "collapse" or zone == "pin" then
        self:layoutCaptionButtons()
        local btn = captionButton(self, zone)
        if btn ~= nil and btn.visible then
            local hit = btn:findHover(px, py, self:originX(), self:originY())
            if hit ~= nil then
                return hit
            end
        end
        return self
    end

    if self:isOpen() then
        local list = self.children
        if list ~= nil then
            local cx, cy, cw, ch = contentBox(self)
            if cw > 0 and ch > 0 and px >= cx and px < cx + cw and py >= cy and py < cy + ch then
                for i = #list, 1, -1 do
                    local hit = list[i]:findHover(px, py, cx, cy)
                    if hit ~= nil then
                        return hit
                    end
                end
            end
        end
    end

    return self
end

--- Finds the child that handles a wheel event at the given point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this window's parent.
--- @param oy number Origin Y of this window's parent.
--- @return PallidWidget|nil target Widget that handles the wheel, if any.
function Window:findWheel(px, py, ox, oy)
    self._ox = ox
    self._oy = oy
    if not self.visible or not self:isOpen() then
        return nil
    end
    local list = self.children
    if list == nil then
        return nil
    end
    local cx, cy, cw, ch = contentBox(self)
    if cw <= 0 or ch <= 0 then
        return nil
    end
    if px < cx or px >= cx + cw or py < cy or py >= cy + ch then
        return nil
    end
    for i = #list, 1, -1 do
        local hit = list[i]:findWheel(px, py, cx, cy)
        if hit ~= nil then
            return hit
        end
    end
    return nil
end
