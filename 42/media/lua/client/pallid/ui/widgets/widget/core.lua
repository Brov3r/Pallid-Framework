require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/geometry"
require "pallid/ui/api/clip"
require "pallid/ui/animation/util"
require "pallid/ui/widgets/tooltip"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets or {}
Pallid.UI.Widgets = Widgets

local RECT_SHAPE = Pallid.UI.Shape.rect()

--- Base class for every Pallid UI widget.
---
--- Coordinates are relative to the parent widget. The root widget is the
--- window, so a root child at (10, 40) is drawn 10 px right and 40 px down from
--- the window's content origin.
---
--- The tree is retained: each widget keeps its children, and mouse events are
--- routed topmost-first. The widget that handled a press becomes the capture,
--- so dragging keeps working while the cursor leaves the widget.
---
--- This file holds the tree, lifecycle and drawing; input routing lives in
--- widget/input.lua and overlays in widget/overlay.lua.
--- @class PallidWidget
--- @field x number Offset X from the parent's origin.
--- @field y number Offset Y from the parent's origin.
--- @field w number Width in pixels; 0 marks a zero-sized layout container.
--- @field h number Height in pixels; 0 marks a zero-sized layout container.
--- @field visible boolean False hides the widget and its whole subtree.
--- @field enabled boolean False dims the widget and makes input hooks reject presses.
--- @field tooltip PallidTooltip|nil Lazily created hover tooltip.
--- @field children PallidWidget[]|nil Draw and hit-test order, bottom to top.
--- @field parent PallidWidget|nil Owner; nil marks the root of a tree.
--- @field overlay boolean|nil True paints the widget after its normal siblings.
local Widget = {}
Widget.__index = Widget
Widgets.Widget = Widget

--- Creates a subclass of `base` (the base class by default) and registers it as
--- `Widgets[name]`. The subclass must define its own `new`: the inherited one
--- would create an instance of the base class and return the wrong metatable.
--- @param name string Class name used as the registry key.
--- @param base table|nil Parent class; defaults to the base Widget.
--- @return table class New empty class table.
function Widgets.class(name, base)
    local class = setmetatable({}, { __index = base or Widget })
    class.__index = class
    class.className = name
    Widgets[name] = class
    return class
end

--- Shared field setup used by every `new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @return PallidWidget self The initialized widget.
function Widget:init(x, y, w, h)
    self.x = x or 0
    self.y = y or 0
    self.w = w or 0
    self.h = h or 0
    self.visible = true
    self.enabled = true
    self._ox = 0
    self._oy = 0
    self._lastNow = nil
    self._dt = 0
    return self
end

--- Creates a plain container widget.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @return PallidWidget New widget.
function Widget.new(x, y, w, h)
    local self = setmetatable({}, Widget)
    self:init(x, y, w, h)
    return self
end

--- Factory shortcut for `Widget.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @return PallidWidget New widget.
function Widgets.widget(x, y, w, h)
    return Widget.new(x, y, w, h)
end

--- Adds a child to the end of the draw and hit-test order. Re-adding an existing
--- child moves it to the top instead of duplicating it in two lists.
--- @param child PallidWidget Widget to attach.
--- @return PallidWidget child The same widget, for chaining.
function Widget:add(child)
    if child == self then
        error("Widget:add: a widget cannot be its own child")
    end
    -- A cycle would make draw, update and getRoot recurse forever.
    local node = self
    while node ~= nil do
        if node == child then
            error("Widget:add: adding an ancestor would create a cycle")
        end
        node = node.parent
    end

    local previous = child.parent
    if previous ~= nil then
        previous:remove(child)
    end

    local list = self.children
    if list == nil then
        list = {}
        self.children = list
    end
    child.parent = self
    list[#list + 1] = child
    if child.overlay == true then
        self._overlayCount = (self._overlayCount or 0) + 1
    end
    child:_notifyAttached()
    return child
end

--- Detaches a direct child. Removing a widget that is not a child is a no-op.
--- @param child PallidWidget Widget to detach.
function Widget:remove(child)
    local list = self.children
    if list == nil then
        return
    end
    for i = #list, 1, -1 do
        if list[i] == child then
            table.remove(list, i)
            child.parent = nil
            if child.overlay == true and (self._overlayCount or 0) > 0 then
                self._overlayCount = self._overlayCount - 1
            end
            child:_notifyDetached()
            return
        end
    end
end

--- Called after the widget and its subtree become reachable from a root.
--- Widgets that keep external registries override this instead of polling the
--- tree. The default is a no-op.
function Widget:onAttach() -- luacheck: ignore
end

--- Called after the widget and its subtree leave the tree. Widgets that keep
--- external registries must release them here: Kahlua does not implement weak
--- tables, so `__mode` is ignored and a registry never shrinks on its own.
function Widget:onDetach() -- luacheck: ignore
end

function Widget:_notifyAttached()
    self:onAttach()
    local list = self.children
    if list ~= nil then
        for i = 1, #list do
            list[i]:_notifyAttached()
        end
    end
end

function Widget:_notifyDetached()
    self:onDetach()
    local list = self.children
    if list ~= nil then
        for i = 1, #list do
            list[i]:_notifyDetached()
        end
    end
end

--- Paints the widget after its normal siblings, regardless of insertion order.
--- The flag is safe to change while attached; the parent's overlay counter is
--- kept in sync so containers without overlays skip the extra pass.
--- @param overlay boolean True to draw in the overlay pass.
--- @return PallidWidget self For chaining.
function Widget:setOverlay(overlay)
    overlay = overlay and true or false
    if (self.overlay == true) == overlay then
        return self
    end
    self.overlay = overlay
    local parent = self.parent
    if parent ~= nil then
        local count = parent._overlayCount or 0
        count = overlay and (count + 1) or (count - 1)
        parent._overlayCount = count > 0 and count or 0
    end
    return self
end

--- Moves and resizes the widget without touching its children.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidWidget self For chaining.
function Widget:setBounds(x, y, w, h)
    self.x = x
    self.y = y
    self.w = w
    self.h = h
    return self
end

--- Shows or hides the widget.
--- @param visible boolean True shows the widget, false hides the whole subtree.
--- @return PallidWidget self For chaining.
function Widget:setVisible(visible)
    self.visible = visible
    return self
end

--- Enables or disables the widget.
--- @param enabled boolean False dims the widget and makes input hooks reject presses.
--- @return PallidWidget self For chaining.
function Widget:setEnabled(enabled)
    self.enabled = enabled
    return self
end

--- Attaches a hover tooltip. Accepts plain body text or a ready PallidTooltip
--- for rich content (title, icon rows, sections, footer). A string replaces
--- any rich content and switches the tooltip back to plain text.
--- @param text string|PallidTooltip Tooltip body or a prepared tooltip.
--- @param delay number|nil Seconds before the fade starts. Defaults to 0.12;
---                         when the tooltip already exists this value is kept
---                         unless a new delay is passed.
--- @return PallidWidget self For chaining.
function Widget:setTooltip(text, delay)
    if type(text) == "table" and text.draw ~= nil then
        self.tooltip = text
        if delay ~= nil then
            text.delay = math.max(0, delay)
        end
        return self
    end

    local tooltip = self.tooltip
    if tooltip == nil then
        self.tooltip = Widgets.Tooltip.new(text, delay)
        return self
    end
    if tooltip.title ~= "" or #tooltip.rows > 0 or tooltip.footer ~= "" then
        tooltip:setTitle("")
        tooltip:setRows(nil)
        tooltip:setFooter("")
    end
    tooltip:setText(text)
    if delay ~= nil then
        tooltip.delay = math.max(0, delay)
    end
    return self
end

--- Absolute X of the widget inside the window.
--- @return number Absolute X in root-local coordinates.
function Widget:originX()
    return self._ox + self.x
end

--- Absolute Y of the widget inside the window.
--- @return number Absolute Y in root-local coordinates.
function Widget:originY()
    return self._oy + self.y
end

--- Returns true when the point lies inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean inside True when the point is inside the widget's box.
function Widget:isInside(px, py)
    local x = self:originX()
    local y = self:originY()
    return px >= x and px < x + self.w and py >= y and py < y + self.h
end

--- True when the widget clips drawing to its own box. Containers override this
--- when their visible area is smaller than their bounds (a scroll viewport).
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean clipped True when the point falls outside the painted area.
function Widget:clipsPoint(px, py)
    return self.clipChildren == true and not self:isInside(px, py)
end

--- True when the point can reach the widget after every ancestor applies its
--- visibility and clipping. External hit tests (drag targets, drop zones) need
--- this because they cannot walk the tree with `findDown`: an inactive tab page
--- or a scrolled-out row is still `visible = true` for its own widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean visible True when the point is inside the painted subtree.
function Widget:isPointVisible(px, py)
    local node = self
    while node ~= nil do
        if not node.visible then
            return false
        end
        if node:clipsPoint(px, py) then
            return false
        end
        node = node.parent
    end
    return true
end

--- True when the widget's bounding box touches the active software clip.
--- Used to skip off-screen children before their draw code runs. Widgets with
--- `cullable = false` are always drawn; zero-sized layout containers are
--- traversed so their children can still be culled individually.
--- @return boolean visible False only when the box cannot intersect the clip.
function Widget:isInActiveClip()
    if self.cullable == false or self.w <= 0 or self.h <= 0 then
        return true
    end
    local cx, cy, cw, ch = Pallid.UI.clipRect()
    if cx == nil then
        return true
    end
    -- An empty clip hides everything; treating its origin as a corner would
    -- report every widget to the left of it as visible.
    if cw <= 0 or ch <= 0 then
        return false
    end
    local x, y = self:originX(), self:originY()
    return not (x >= cx + cw or y >= cy + ch or x + self.w <= cx or y + self.h <= cy)
end

--- Draw entry point. Stores the parent origin, then draws self and children.
--- @param el ISUIElement Host element the tree is rendered into.
--- @param ox number Parent origin X inside `el`.
--- @param oy number Parent origin Y inside `el`.
function Widget:draw(el, ox, oy)
    -- A root starts a frame: drop any software clip left by an interrupted
    -- frame before the first rectangle is pushed. The element is passed so the
    -- recorded stencil depth is reset too; otherwise a later clipEnd would pop
    -- a level that no longer exists.
    if self.parent == nil and Pallid.UI.resetClip ~= nil then
        Pallid.UI.resetClip(el)
    end

    self._ox = ox
    self._oy = oy
    if not self.visible then
        return
    end
    self:drawSelf(el)
    self:drawChildren(el)
end

--- Override to paint the widget itself.
--- @param el ISUIElement Host element the tree is rendered into.
function Widget:drawSelf(el) -- luacheck: ignore
end

--- Draws one child after applying the parent's active clip test.
--- @param el ISUIElement Host element the tree is rendered into.
--- @param child PallidWidget Child to draw.
--- @param cx number Parent origin X inside `el`.
--- @param cy number Parent origin Y inside `el`.
--- @param clipX number|nil Active clip left, nil when no clip is active.
--- @param clipY number|nil Active clip top.
--- @param clipX2 number|nil Active clip right edge.
--- @param clipY2 number|nil Active clip bottom edge.
local function drawChild(el, child, cx, cy, clipX, clipY, clipX2, clipY2)
    child._ox, child._oy = cx, cy
    if clipX ~= nil and child.cullable ~= false and child.w > 0 and child.h > 0 then
        local px, py = child:originX(), child:originY()
        if px >= clipX2 or py >= clipY2 or px + child.w <= clipX or py + child.h <= clipY then
            return
        end
    end
    child:draw(el, cx, cy)
end

--- Draws children. Clipping is opt-in (`clipChildren = true`) because deeply
--- nested stencils are expensive and can misbehave when a clip is fully
--- off-screen; the containers that can overflow (Window, ScrollPanel, Table,
--- GroupBox, SplitPanel, Accordion) clip explicitly.
---
--- Children marked `overlay` are painted after all normal siblings, so banners
--- stay above content added later without reordering the tree.
--- @param el ISUIElement Host element the tree is rendered into.
function Widget:drawChildren(el)
    local list = self.children
    if list == nil then
        return
    end
    local cx, cy = self:originX(), self:originY()

    local entered = false
    if self.clipChildren == true then
        entered = Pallid.UI.clip(el, RECT_SHAPE, cx, cy, self.w, self.h)
    end

    -- Read the clip once and inline the visibility test: thousands of children
    -- should not each call clipRect() and isInActiveClip().
    local clipX, clipY, clipW, clipH = Pallid.UI.clipRect()
    local clipX2, clipY2
    if clipX ~= nil then
        clipX2, clipY2 = clipX + clipW, clipY + clipH
    end

    for i = 1, #list do
        local child = list[i]
        if child.visible and child.overlay ~= true then
            drawChild(el, child, cx, cy, clipX, clipY, clipX2, clipY2)
        end
    end

    -- Overlay children are a separate pass. Most containers have none, so the
    -- counter keeps the common path to a single loop.
    if (self._overlayCount or 0) > 0 then
        for i = 1, #list do
            local child = list[i]
            if child.visible and child.overlay == true then
                drawChild(el, child, cx, cy, clipX, clipY, clipX2, clipY2)
            end
        end
    end

    if entered then
        Pallid.UI.clipEnd(el)
    end
end

--- Advances `_lastNow` and returns a clamped delta in seconds.
local MAX_DT = 0.1

--- Clamps a raw time delta so one long stall cannot make an exponential
--- approach jump in a single step.
--- @param dt number Raw delta in seconds.
--- @return number Safe delta in seconds, 0..MAX_DT.
local function safeDt(dt)
    if dt < 0 then
        return 0
    end
    if dt > MAX_DT then
        return MAX_DT
    end
    return dt
end

--- Time since the previous call, used by onUpdate. Kept in its own slot so the
--- game-tick update and the render-driven animation do not steal each other's
--- timestamps.
--- @param now number Current time in seconds.
--- @return number dt Seconds since the previous call, 0..0.1.
function Widget:delta(now)
    local last = self._lastNow
    self._lastNow = now
    if last == nil then
        return 0
    end
    return safeDt(now - last)
end

--- Time since the previous animation frame. Same clamping as delta, separate
--- timestamp, because updateAnimations runs once per rendered frame.
--- @param now number Current time in seconds.
--- @return number dt Seconds since the previous frame, 0..0.1.
function Widget:animDelta(now)
    local last = self._lastAnimNow
    self._lastAnimNow = now
    if last == nil then
        return 0
    end
    return safeDt(now - last)
end

--- Updates animations and children. Override `onUpdate` instead of this.
--- @param now number Current game-tick time in seconds.
function Widget:update(now)
    if self.parent == nil and Pallid.UI.resetClip ~= nil then
        Pallid.UI.resetClip()
    end
    if not self.visible then
        return
    end
    -- Static widgets (no onUpdate override) do not need delta/exp work.
    -- The page.onUpdate closures and animated widgets still get their dt.
    local updateHandler = self.onUpdate
    if updateHandler ~= Widget.onUpdate then
        self._dt = self:delta(now)
        updateHandler(self, now, self._dt)
    end
    local list = self.children
    if list ~= nil then
        for i = 1, #list do
            list[i]:update(now)
        end
        -- Widgets may mark themselves dead while updating (toasts). Remove them
        -- after the loop so the iteration cannot skip a sibling.
        for i = #list, 1, -1 do
            local child = list[i]
            if child._dead then
                table.remove(list, i)
                child.parent = nil
            end
        end
    end

    -- Overlays are owned by the root and are not in `children`; without this
    -- their animations (for example a checkbox inside a modal) would freeze.
    local modal = self.modal
    if modal ~= nil then
        modal:update(now)
    end
    local popover = self.openPopover
    if popover ~= nil then
        popover:update(now)
    end
    local menu = self.openMenu
    if menu ~= nil then
        menu:update(now)
    end
end

--- Called on the game tick (about 10 Hz) for logic: timers, retries and input
--- bookkeeping. Visual state belongs in onAnimate.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous tick, 0..0.1.
function Widget:onUpdate(now, dt) -- luacheck: ignore
end

--- Called once per rendered frame, before the widget is drawn. Override it to
--- advance time-based visual state (tracks, approach smoothing). Anything that
--- fires events or changes structure belongs in onUpdate, which runs on the game
--- tick.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function Widget:onAnimate(now, dt) -- luacheck: ignore
end

--- Advances animation state for this widget and everything it owns. Hosts call
--- it from render, once per frame, and keep update() on the game tick.
--- @param now number Current time in seconds.
function Widget:updateAnimations(now)
    if not self.visible then
        return
    end

    local handler = self.onAnimate
    if handler ~= Widget.onAnimate then
        handler(self, now, self:animDelta(now))
    end

    local list = self.children
    if list ~= nil then
        for i = 1, #list do
            list[i]:updateAnimations(now)
        end
    end

    -- Overlays are owned by the root and are not in `children`, exactly as in
    -- update(); without this a fade inside a modal would still run at tick rate.
    local modal = self.modal
    if modal ~= nil then
        modal:updateAnimations(now)
    end
    local popover = self.openPopover
    if popover ~= nil then
        popover:updateAnimations(now)
    end
    local menu = self.openMenu
    if menu ~= nil then
        menu:updateAnimations(now)
    end
end

--- Frame-rate independent exponential approach with a dead zone.
--- @param current number Current value.
--- @param target number Value to approach.
--- @param speed number Higher is faster.
--- @param dt number Time step in seconds.
--- @return number Next value, or `target` once inside the dead zone.
function Widgets.approach(current, target, speed, dt)
    if dt <= 0 then
        return current
    end
    local nextValue = current + (target - current) * (1 - math.exp(-speed * dt))
    if math.abs(target - nextValue) < 0.001 then
        return target
    end
    return nextValue
end

local DISABLED_ALPHA = 0.4

--- Returns `color` dimmed while the widget is disabled. The result lives in a
--- per-widget scratch slot, so pass it straight to a draw call. Use two slots
--- when a single call needs two dimmed colors at once.
--- @param color PallidColor Source color; returned unchanged while enabled.
--- @param slot integer|nil Scratch slot, defaults to 1.
--- @return PallidColor Dimmed color owned by the widget.
function Widget:shade(color, slot)
    if self.enabled then
        return color
    end
    local scratch = self._shadeScratch
    if scratch == nil then
        scratch = {}
        self._shadeScratch = scratch
    end
    local index = slot or 1
    local out = scratch[index]
    if out == nil then
        out = { r = 1, g = 1, b = 1, a = 1 }
        scratch[index] = out
    end
    out.r = color.r or 1
    out.g = color.g or 1
    out.b = color.b or 1
    out.a = (color.a or 1) * DISABLED_ALPHA
    return out
end
