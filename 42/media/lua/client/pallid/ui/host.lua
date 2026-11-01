require "ISUI/ISUIElement"
require "pallid/ui/internal"
require "pallid/ui/animation/util"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

--- Full-screen ISUIElement that owns one Pallid widget tree. Subclasses keep
--- application state (demo pages, performance counters) and reuse the whole
--- frame/input lifecycle from here.
---
--- The host forwards mouse input only while a widget consumes it. A
--- full-screen element with `wantMouseEvents` would swallow every move in the
--- world, so consumption is decided by the tree handlers instead.
--- @class PallidUIHost : ISUIElement
--- @field root PallidWidget|nil Widget tree; nil before the first setRoot or after shutdown.
--- @field animNow number Last timestamp passed to updateAnimations, in seconds.
--- @field rightDown boolean True between a right press and its matching release.
--- @field onFrame fun(elapsedMs: number)|nil Called after the overlay pass with UI milliseconds.
local Host = ISUIElement:derive("PallidUIHost")
Pallid.UI.Host = Host

--- Creates a new host element.
--- @param opts table|nil Host configuration.
--- @field opts.width number|nil Element width; defaults to the screen width.
--- @field opts.height number|nil Element height; defaults to the screen height.
--- @field opts.onFrame fun(elapsedMs: number)|nil Called after each rendered frame.
--- @return PallidUIHost host The new, empty host element.
function Host:new(opts)
    opts = opts or {}
    local width = opts.width or getCore():getScreenWidth()
    local height = opts.height or getCore():getScreenHeight()
    local o = ISUIElement:new(0, 0, width, height)
    setmetatable(o, self)
    self.__index = self

    o.wantMouseEvents = false
    o.wantExtraMouseEvents = false
    o.root = nil
    o.animNow = 0
    o.rightDown = false
    o.onFrame = opts.onFrame
    return o
end

--- Installs the widget tree rendered by this host.
--- @param root PallidWidget|nil Topmost widget; nil detaches the tree.
--- @return PallidUIHost self For chaining.
function Host:setRoot(root)
    self.root = root
    return self
end

--- Forwards a key press to the tree so the focused widget can react.
--- @param key integer Keyboard.KEY_* value.
--- @return boolean handled True when a widget consumed the key.
function Host:keyPressed(key)
    local root = self.root
    if root == nil then
        return false
    end
    return root:keyPress(key)
end

--- Game-tick logic pass (about 10 Hz).
function Host:update()
    local root = self.root
    if root == nil then
        return
    end
    self.animNow = Pallid.UI.Anim.now()
    root:update(self.animNow)
end

--- Hides native text boxes together with the host.
--- @param visible boolean New visibility of the host element.
function Host:setVisible(visible)
    ISUIElement.setVisible(self, visible)
    if not visible and self.root ~= nil then
        self.root:setNativeVisible(false)
        self.root:blurNative()
    end
end

--- Draws one frame: hide stale native boxes, advance animations, paint the
--- tree and its overlays, then report the UI cost to `onFrame`.
function Host:render()
    local root = self.root
    if root == nil then
        return
    end

    local startMs = getTimestampMs()
    self.animNow = startMs * 0.001
    root:setNativeVisible(false)
    root:updateAnimations(self.animNow)
    root:draw(self, 0, 0)
    root:drawOverlay(self, self.animNow, 0, 0)
    if self.onFrame ~= nil then
        self.onFrame(getTimestampMs() - startMs)
    end
end

--- Stops rendering and releases the tree. Safe to call twice.
function Host:shutdown()
    local root = self.root
    if root ~= nil then
        root:setNativeVisible(false)
        root:blurNative()
    end
    self.root = nil
    self:removeFromUIManager()
end

--- Returns the cursor X position in host-local pixels.
--- @return number x Cursor X in host-local pixels.
function Host:mouseX()
    return self:getMouseX()
end

--- Returns the cursor Y position in host-local pixels.
--- @return number y Cursor Y in host-local pixels.
function Host:mouseY()
    return self:getMouseY()
end

--- Dispatches a left button press to the root widget.
--- @param x number Cursor X in host-local pixels.
--- @param y number Cursor Y in host-local pixels.
--- @return boolean handled True when a widget consumed the press.
function Host:onMouseDown(x, y)
    local root = self.root
    if root == nil then
        return false
    end
    return root:mouseDown(self:mouseX(), self:mouseY(), "left")
end

--- Dispatches a left button release to the root widget.
--- @param x number Cursor X in host-local pixels.
--- @param y number Cursor Y in host-local pixels.
--- @return boolean handled True when the active capture received the release.
function Host:onMouseUp(x, y)
    local root = self.root
    if root == nil then
        return false
    end
    return root:mouseUp(self:mouseX(), self:mouseY(), "left")
end

--- Dispatches a right button press to the root widget and remembers the result.
--- @param x number Cursor X in host-local pixels.
--- @param y number Cursor Y in host-local pixels.
--- @return boolean handled True when a widget consumed the press.
function Host:onRightMouseDown(x, y)
    local root = self.root
    if root == nil then
        return false
    end
    local handled = root:mouseDown(self:mouseX(), self:mouseY(), "right")
    self.rightDown = handled
    return handled
end

--- Dispatches a right button release and clears the pending right press flag.
--- @param x number Cursor X in host-local pixels.
--- @param y number Cursor Y in host-local pixels.
--- @return boolean handled True when the active capture or the pending right press consumed the release.
function Host:onRightMouseUp(x, y)
    local root = self.root
    local handled = self.rightDown
    self.rightDown = false
    if root == nil then
        return handled
    end
    return root:mouseUp(self:mouseX(), self:mouseY(), "right") or handled
end

--- Dispatches cursor movement to the root widget.
--- @param dx number Cursor movement X in pixels.
--- @param dy number Cursor movement Y in pixels.
--- @return boolean handled True when a widget is hovered inside the tree.
function Host:onMouseMove(dx, dy)
    local root = self.root
    if root == nil then
        return false
    end
    return root:mouseMove(self:mouseX(), self:mouseY())
end

--- Dispatches a mouse wheel step to the root widget.
--- @param del number Wheel steps; positive is up.
--- @return boolean handled True when the tree consumed the wheel.
function Host:onMouseWheel(del)
    local root = self.root
    if root == nil then
        return false
    end
    return root:mouseWheel(self:mouseX(), self:mouseY(), del)
end
