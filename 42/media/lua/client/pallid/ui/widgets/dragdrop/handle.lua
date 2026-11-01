require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local Color    = Pallid.UI.Color

local DEFAULT_SIZE = 18
local ICON_INSET   = 4
local ICON_GRIP    = "media/assets/ui/pallid/icons/menu-07.png"
local ICON_OPTS    = { mode = "fit" }

--- Grab handle for drag sources.
---
--- A press only arms the handle; the session starts after the pointer moves
--- `opts.threshold` pixels. That keeps a plain click from hiding rows or
--- flashing a ghost. The handle becomes the mouse capture, so it receives
--- `onMove`/`onUp` in root-local coordinates and keyboard focus for Esc.
--- @class PallidDragHandle : PallidWidget
--- @field size number Smaller side of the handle box; the icon is fitted inside it.
--- @field payload table|fun(handle: PallidDragHandle):table|nil Payload table or a factory called on drag start.
--- @field color PallidColor Outline color.
--- @field hoverColor PallidColor Hover outline color.
--- @field iconTexture Texture|nil Resolved grip texture.
--- @field iconName string|nil Registered grip icon name.
--- @field threshold number Pixels the pointer must move before a drag starts.
--- @field dragging boolean True once the session started.
--- @field onDragStart fun(payload: table, source: PallidDragHandle)|nil Called after the drag session starts.
--- @field onDragEnd fun(dropped: boolean, payload: table)|nil Called when the drag session ends.
--- @field onClick fun(handle: PallidDragHandle)|nil Called on a press without a drag.
local DragHandle = Widgets.class("DragHandle")

--- Creates a new `DragHandle` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param size number Grip box side in pixels.
--- @param opts table|nil Optional settings.
--- @field opts.payload table|fun(handle: PallidDragHandle):table|nil Payload or a factory.
--- @field opts.color PallidColor|nil Grip tint.
--- @field opts.hoverColor PallidColor|nil Grip tint while hovered or dragging.
--- @field opts.icon string|false|nil Icon name or texture path; false hides it.
--- @field opts.iconSize number|nil Explicit icon box; fitted inside the grip by default.
--- @field opts.width number|nil Handle width in pixels; defaults to the `size` argument.
--- @field opts.height number|nil Handle height in pixels; defaults to the `size` argument.
--- @field opts.plain boolean|nil True draws no grip background; use for a full card surface.
--- @field opts.hoverBorder PallidColor|nil Border drawn around a plain surface while hovered.
--- @field opts.threshold number|nil Drag threshold in pixels; defaults to 4.
--- @field opts.acceptsFocus boolean|nil Defaults to true; required for Esc.
--- @field opts.onDragStart fun(payload: table, source: PallidDragHandle)|nil Called after the drag session starts.
--- @field opts.onDragEnd fun(dropped: boolean, payload: table)|nil Called when the drag session ends.
--- @field opts.onClick fun(handle: PallidDragHandle)|nil Called on a press that never becomes a drag.
--- @return PallidDragHandle New drag handle.
function DragHandle.new(x, y, size, opts)
    opts = opts or {}
    size = math.max(1, math.floor(size or DEFAULT_SIZE))
    local w = math.max(1, math.floor(opts.width or size))
    local h = math.max(1, math.floor(opts.height or size))
    local self = setmetatable({}, DragHandle)
    self:init(x, y, w, h)

    self.size        = math.min(w, h)
    self.payload     = opts.payload
    self.color       = opts.color or Color.textMuted
    self.hoverColor  = opts.hoverColor or Color.primaryStrong
    self.onDragStart = opts.onDragStart
    self.onDragEnd   = opts.onDragEnd
    self.onClick     = opts.onClick
    self.threshold   = math.max(1, opts.threshold or 4)
    self.acceptsFocus = opts.acceptsFocus ~= false
    self.radius      = opts.radius == nil and 3 or opts.radius
    self.dragging    = false
    self._plain      = opts.plain == true
    self.hoverBorderColor = opts.hoverBorder or self.hoverColor

    self._hover      = false
    self._armed      = false
    self._started    = false
    self._pressX     = 0
    self._pressY     = 0
    self._bg         = Color.withAlpha(Color.primarySoft, 0.6)
    self._bgActive   = Color.withAlpha(Color.primary, 0.25)

    self.iconSize    = opts.iconSize
    self:setIcon(opts.icon == nil and ICON_GRIP or opts.icon)
    return self
end

--- Factory shortcut for `DragHandle.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param size number Grip box side in pixels.
--- @param opts table|nil Options; see `DragHandle.new`.
--- @return PallidDragHandle New drag handle.
function Widgets.dragHandle(x, y, size, opts)
    return DragHandle.new(x, y, size, opts)
end

--- Accepts a registered icon name, a texture path containing a slash, or
--- false to hide the icon.
--- @param icon string|false|nil Icon name, texture path or false.
--- @return PallidDragHandle self This handle, for chaining.
function DragHandle:setIcon(icon)
    self.iconTexture, self.iconName = Pallid.UI.Textures.resolve(icon)
    return self
end

--- Resolves the payload, calling the factory form and rejecting non-tables.
--- @return table|nil payload Drag payload, or nil.
function DragHandle:_resolvePayload()
    local payload = self.payload
    if type(payload) == "function" then
        payload = payload(self)
    end
    if type(payload) ~= "table" then
        return nil
    end
    return payload
end

--- Returns true while a drag is in progress.
--- @return boolean dragging True while a drag session started by this handle is active.
function DragHandle:isDragging()
    return self.dragging and Pallid.UI.DragDrop.isActive(self)
end

--- Updates the widget bounds.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @return PallidDragHandle self This handle, for chaining.
function DragHandle:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self.size = math.min(w, h)
    return self
end

--- Clears the armed and dragging state without starting a session.
function DragHandle:_disarm()
    self._armed = false
    self._started = false
    self.dragging = false
end

--- Starts a drag session and fires the start callback when the threshold was reached.
--- @param px number Root-local pointer X.
--- @param py number Root-local pointer Y.
--- @return boolean started True when the session started.
function DragHandle:_start(px, py)
    local payload = self:_resolvePayload()
    if payload == nil then
        return false
    end
    local root = self:getRoot()
    if root == nil then
        return false
    end
    if not Pallid.UI.DragDrop.start(payload, self, root, px, py) then
        return false
    end

    self._started = true
    self.dragging = true
    if self.onDragStart ~= nil then
        self.onDragStart(payload, self)
    end
    return true
end

--- Handles a pointer press inside the widget.
--- @param px number Root-local pointer X.
--- @param py number Root-local pointer Y.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the event was handled.
function DragHandle:onDown(px, py, button)
    if not self.enabled then
        return false
    end

    local DragDrop = Pallid.UI.DragDrop
    if DragDrop.isActive(self) then
        -- A non-left press cancels the drag instead of opening a menu under it.
        if button ~= nil and button ~= "left" then
            DragDrop.cancel()
        end
        return true
    end

    if button ~= nil and button ~= "left" then
        return false
    end

    self._armed = true
    self._started = false
    self._pressX, self._pressY = px or 0, py or 0
    self:focus()
    return true
end

--- Handles pointer movement.
--- @param px number Root-local pointer X.
--- @param py number Root-local pointer Y.
function DragHandle:onMove(px, py)
    local DragDrop = Pallid.UI.DragDrop
    if not self._armed then
        if DragDrop.isActive(self) then
            DragDrop.move(px, py)
        end
        return
    end

    if not self._started then
        local dx, dy = px - self._pressX, py - self._pressY
        if dx * dx + dy * dy < self.threshold * self.threshold then
            return
        end
        if not self:_start(px, py) then
            self:_disarm()
            self:blur()
            return
        end
        return
    end

    DragDrop.move(px, py)
end

--- Handles a pointer release.
--- @param px number Root-local pointer X.
--- @param py number Root-local pointer Y.
function DragHandle:onUp(px, py)
    local DragDrop = Pallid.UI.DragDrop
    if DragDrop.isActive(self) then
        DragDrop.drop(px, py)
        return
    end
    if self._armed then
        self:_disarm()
        self:blur()
        if self.onClick ~= nil then
            self.onClick(self)
        end
    end
end

--- Esc reaches the handle because it owns the focus while armed or dragging.
--- @param key integer Keyboard.KEY_* value.
--- @return boolean handled True when the handle consumed the key.
function DragHandle:onKeyPress(key)
    if Keyboard == nil or key ~= Keyboard.KEY_ESCAPE then
        return false
    end
    local DragDrop = Pallid.UI.DragDrop
    if DragDrop.isActive(self) then
        DragDrop.cancel()
        return true
    end
    if self._armed then
        self:_disarm()
        self:blur()
        return true
    end
    return false
end

--- Losing focus while capturing must not leave a ghost behind.
function DragHandle:onBlur()
    if Pallid.UI.DragDrop.isActive(self) then
        Pallid.UI.DragDrop.cancel()
    end
    self:_disarm()
end

--- Safety net for a release lost outside the window: cancel once the left
--- button is no longer physically down.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous tick.
function DragHandle:onUpdate(now, dt) -- luacheck: ignore
    local DragDrop = Pallid.UI.DragDrop
    if not DragDrop.isActive(self) and not self._armed then
        return
    end
    if Mouse == nil or Mouse.isButtonDown == nil then
        return
    end
    -- Button 0 is the left mouse button (zombie.input.Mouse).
    if not Mouse.isButtonDown(0) then
        if DragDrop.isActive(self) then
            DragDrop.cancel()
        end
        self:_disarm()
        self:blur()
    end
end

--- DragDrop notifies the source once the session is fully cleaned up.
--- @param dropped boolean True when the payload was dropped.
--- @param payload table Payload that was dragged.
function DragHandle:_onDragFinished(dropped, payload)
    self:_disarm()
    self:releaseCapture()
    self:blur()
    if self.onDragEnd ~= nil then
        self.onDragEnd(dropped, payload)
    end
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element used for drawing.
function DragHandle:drawSelf(el)
    local x, y = self:originX(), self:originY()
    local size = math.min(self.w, self.h, self.size)
    if size <= 0 then
        return
    end
    local active = Pallid.UI.DragDrop.isActive(self)

    if self._plain then
        -- A full-card surface has no grip background; the hover affordance is
        -- an outline around the whole card so the content stays readable.
        if self._hover or active then
            local outline = active and self.hoverColor or self.hoverBorderColor
            if self.radius > 0 then
                Pallid.UI.roundedBorder(el, x, y, self.w, self.h, self.radius, 1, self:shade(outline))
            else
                Pallid.UI.border(el, x, y, self.w, self.h, 1, self:shade(outline))
            end
        end
    elseif self._hover or active then
        local background = active and self._bgActive or self._bg
        if self.radius > 0 then
            Pallid.UI.roundedRect(el, x, y, size, size, self.radius, self:shade(background))
        else
            Pallid.UI.rect(el, x, y, size, size, self:shade(background))
        end
    end

    local color = self.color
    if self._hover or active then
        color = self.hoverColor
    end
    color = self:shade(color)

    local iconSize = self.iconSize
    if iconSize == nil then
        iconSize = math.max(4, size - ICON_INSET * 2)
    else
        iconSize = math.max(1, math.min(iconSize, size))
    end
    local ix = x + (size - iconSize) * 0.5
    local iy = y + (size - iconSize) * 0.5

    if self.iconTexture ~= nil then
        Pallid.UI.texture(el, self.iconTexture, ix, iy, iconSize, iconSize, color, ICON_OPTS)
    elseif self.iconName ~= nil then
        Pallid.UI.icon(el, self.iconName, ix, iy, iconSize, color)
    end
end

--- Marks the widget as hovered.
function DragHandle:onHoverStart()
    if not self.enabled then
        return
    end
    self._hover = true
end

--- Clears hover state when the pointer leaves.
function DragHandle:onHoverEnd()
    self._hover = false
    Widgets.Widget.onHoverEnd(self)
end

return DragHandle
