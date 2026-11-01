require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/geometry"
require "pallid/ui/api/clip"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/panel"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local RECT_SHAPE = Pallid.UI.Shape.rect()
local DIVIDER = 6

--- Two areas with a draggable divider. `orientation = "horizontal"` puts the
--- panes side by side, `"vertical"` stacks them.
--- @class PallidSplitPanel : PallidWidget
--- @field first PallidPanel First pane.
--- @field second PallidPanel Second pane.
--- @field orientation "horizontal"|"vertical" Divider orientation.
--- @field ratio number First pane share of the available space, 0..1.
--- @field minFirst number Minimum first pane size in pixels.
--- @field minSecond number Minimum second pane size in pixels.
--- @field divider number Divider thickness in pixels.
--- @field dragging boolean True while the divider is dragged.
--- @field dividerColor PallidColor Idle divider colour.
--- @field dividerHover PallidColor Hovered/dragged divider colour.
--- @field onChange fun(panel: PallidSplitPanel, ratio: number)|nil Called after a ratio change.
local SplitPanel = Widgets.class("SplitPanel")

--- Creates a new `SplitPanel` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional layout and behaviour settings.
--- @field opts.orientation "horizontal"|"vertical"|nil Divider orientation, defaults to "horizontal".
--- @field opts.ratio number|nil Initial first-pane ratio, defaults to 0.5.
--- @field opts.minFirst number|nil Minimum first pane size, defaults to 40.
--- @field opts.minSecond number|nil Minimum second pane size, defaults to 40.
--- @field opts.divider number|nil Divider thickness, defaults to 6.
--- @field opts.background PallidColor|nil Background passed to both panes.
--- @field opts.onChange fun(panel: PallidSplitPanel, ratio: number)|nil Called after a ratio change.
--- @return PallidSplitPanel panel New split panel instance.
function SplitPanel.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, SplitPanel)
    self:init(x, y, w, h)
    self.orientation = opts.orientation == "vertical" and "vertical" or "horizontal"
    self.ratio = opts.ratio or 0.5
    self.minFirst = math.max(0, opts.minFirst or 40)
    self.minSecond = math.max(0, opts.minSecond or 40)
    self.divider = math.max(0, opts.divider or DIVIDER)
    self.onChange = opts.onChange
    self.dragging = false

    self.first = Widgets.panel(0, 0, 0, 0, { background = opts.background })
    self.second = Widgets.panel(0, 0, 0, 0, { background = opts.background })
    self.first.parent = self
    self.second.parent = self

    self.dividerColor = Pallid.UI.Color.border
    self.dividerHover = Pallid.UI.Color.primary
    self._parts = { 0, 0 }
    return self
end

--- Factory shortcut for `SplitPanel.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional settings; see `SplitPanel.new`.
--- @return PallidSplitPanel panel New split panel instance.
function Widgets.splitPanel(x, y, w, h, opts)
    return SplitPanel.new(x, y, w, h, opts)
end

--- `first` and `second` are owned panels, not tree children; forward the
--- lifecycle so registries inside them (drop zones) stay in sync.
function SplitPanel:onAttach()
    if self.first ~= nil then
        self.first:_notifyAttached()
    end
    if self.second ~= nil then
        self.second:_notifyAttached()
    end
end

--- Cleans up when the widget is detached from the tree.
function SplitPanel:onDetach()
    if self.first ~= nil then
        self.first:_notifyDetached()
    end
    if self.second ~= nil then
        self.second:_notifyDetached()
    end
end

local function clampRatio(self)
    local horizontal = self.orientation == "horizontal"
    local total = math.max(0, horizontal and self.w or self.h)
    local space = math.max(0, total - math.max(0, self.divider))
    if space <= 0 then
        self.ratio = 0
        return
    end

    local ratio = math.max(0, math.min(1, self.ratio or 0.5))
    local minFirst = math.max(0, math.min(self.minFirst or 0, space))
    local minSecond = math.max(0, math.min(self.minSecond or 0, space))

    local first = math.max(space * ratio, minFirst)
    first = math.min(first, space - minSecond)
    first = math.max(0, math.min(space, first))
    self.ratio = first / space
end

--- @param pane PallidPanel Pane whose local bounds are tested.
--- @param lx number Cursor X relative to the split panel.
--- @param ly number Cursor Y relative to the split panel.
--- @return boolean inside True when the point is inside the pane bounds.
local function paneContains(pane, lx, ly)
    return lx >= pane.x and lx < pane.x + pane.w
        and ly >= pane.y and ly < pane.y + pane.h
end

--- Recomputes both pane rectangles into `_parts` and the child bounds.
function SplitPanel:sync()
    clampRatio(self)
    local horizontal = self.orientation == "horizontal"
    local total = math.max(0, horizontal and self.w or self.h)
    local divider = math.max(0, self.divider)
    local space = math.max(0, total - divider)
    local firstSize = math.floor(space * self.ratio)
    local secondSize = math.max(0, space - firstSize)

    if horizontal then
        self.first:setBounds(0, 0, firstSize, self.h)
        self.second:setBounds(firstSize + divider, 0, secondSize, self.h)
        self._parts[1] = firstSize
        self._parts[2] = secondSize
    else
        self.first:setBounds(0, 0, self.w, firstSize)
        self.second:setBounds(0, firstSize + divider, self.w, secondSize)
        self._parts[1] = firstSize
        self._parts[2] = secondSize
    end
end

--- Returns the divider rectangle in root-local coordinates.
--- @return number x Left edge of the divider.
--- @return number y Top edge of the divider.
--- @return number w Divider width.
--- @return number h Divider height.
function SplitPanel:dividerRect()
    local horizontal = self.orientation == "horizontal"
    if horizontal then
        return self:originX() + self._parts[1], self:originY(), self.divider, self.h
    end
    return self:originX(), self:originY() + self._parts[1], self.w, self.divider
end

--- Returns true when the point is on the divider.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean onDivider True when the cursor is within the divider hit area.
function SplitPanel:isOnDivider(px, py)
    local x, y, w, h = self:dividerRect()
    return px >= x - 2 and px <= x + w + 2 and py >= y - 2 and py <= y + h + 2
end

--- Handles a pointer press inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the divider accepted the press.
function SplitPanel:onDown(px, py, button)
    if not self.enabled or not self:isOnDivider(px, py) then
        return false
    end
    -- A right click must not start a drag.
    if button == "right" then
        return true
    end
    self.dragging = true
    return true
end

--- Sets the first-pane ratio and clamps it to the configured minimums.
--- @param ratio number New first-pane share, 0..1.
--- @return PallidSplitPanel self For chaining.
function SplitPanel:setRatio(ratio)
    self.ratio = ratio
    self:sync()
    if self.onChange ~= nil then
        self.onChange(self, self.ratio)
    end
    return self
end

--- Handles pointer movement.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function SplitPanel:onMove(px, py)
    if not self.dragging then
        return
    end
    local horizontal = self.orientation == "horizontal"
    local total = horizontal and self.w or self.h
    local position = (horizontal and (px - self:originX()) or (py - self:originY())) - self.divider * 0.5
    local space = math.max(1, total - self.divider)
    self.ratio = position / space
    self:sync()
    if self.onChange ~= nil then
        self.onChange(self, self.ratio)
    end
end

--- Handles a pointer release.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function SplitPanel:onUp(px, py)
    self.dragging = false
end

--- Panes are drawn manually and are not in `children`, so the base traversal
--- would never reach them.
--- @param now number Current time in seconds.
function SplitPanel:updateAnimations(now)
    if not self.visible then
        return
    end
    self:sync()
    Widgets.Widget.updateAnimations(self, now)
    self.first:updateAnimations(now)
    self.second:updateAnimations(now)
end

--- Shows or hides the native input boxes.
--- @param visible boolean False hides native boxes in both panes.
function SplitPanel:setNativeVisible(visible)
    self.first:setNativeVisible(visible)
    self.second:setNativeVisible(visible)
end

--- Unfocuses every native text box in the subtree.
function SplitPanel:blurNative()
    self.first:blurNative()
    self.second:blurNative()
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the tree is rendered into.
function SplitPanel:drawSelf(el)
    self:sync()
end

--- Paints every visible child in order.
--- @param el ISUIElement Host element the tree is rendered into.
function SplitPanel:drawChildren(el)
    local x, y = self:originX(), self:originY()

    local entered = Pallid.UI.clip(el, RECT_SHAPE, x, y, self.first.w, self.first.h)
    self.first:draw(el, x, y)
    if entered then
        Pallid.UI.clipEnd(el)
    end

    -- `draw` takes the parent origin and adds the widget's own x/y, so pass
    -- the panel origin here, not the already-offset pane origin.
    local secondX = x + self.second.x
    local secondY = y + self.second.y
    entered = Pallid.UI.clip(el, RECT_SHAPE, secondX, secondY, self.second.w, self.second.h)
    self.second:draw(el, x, y)
    if entered then
        Pallid.UI.clipEnd(el)
    end

    local dx, dy, dw, dh = self:dividerRect()
    local color = (self.dragging or self._hover) and self.dividerHover or self.dividerColor
    Pallid.UI.rect(el, dx, dy, dw, dh, self:shade(color))

    -- Grip dots make the divider discoverable.
    local gripColor = Pallid.UI.Color.textMuted
    local midX, midY = dx + dw * 0.5, dy + dh * 0.5
    if self.orientation == "horizontal" then
        for i = -1, 1 do
            Pallid.UI.circle(el, midX, midY + i * 6, 1.5, gripColor)
        end
    else
        for i = -1, 1 do
            Pallid.UI.circle(el, midX + i * 6, midY, 1.5, gripColor)
        end
    end
end

--- Advances the widget state for the current frame.
--- @param now number Current game-tick time in seconds.
function SplitPanel:update(now)
    if not self.visible then
        return
    end
    self:sync()
    -- Base update owns onUpdate, overlays and dead-child cleanup.
    Widgets.Widget.update(self, now)
    self.first:update(now)
    self.second:update(now)
end

--- Finds the child that handles a press at the given point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this split panel's parent.
--- @param oy number Origin Y of this split panel's parent.
--- @param button string|nil "left" or "right".
--- @return PallidWidget|nil target Widget that accepted the press.
function SplitPanel:findDown(px, py, ox, oy, button)
    self._ox = ox
    self._oy = oy
    if not self.visible or not self:isInside(px, py) then
        return nil
    end
    self:sync()
    if not self.enabled then
        return self
    end

    if self:isOnDivider(px, py) then
        if self:onDown(px, py, button) then
            return self
        end
        return nil
    end

    local lx, ly = px - self:originX(), py - self:originY()
    if paneContains(self.first, lx, ly) then
        local hit = self.first:findDown(px, py, self:originX(), self:originY(), button)
        if hit ~= nil then
            return hit
        end
    end
    if paneContains(self.second, lx, ly) then
        return self.second:findDown(px, py, self:originX(), self:originY(), button)
    end
    return nil
end

--- Finds the child that handles hover at the given point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this split panel's parent.
--- @param oy number Origin Y of this split panel's parent.
--- @return PallidWidget|nil hovered Widget under the cursor.
function SplitPanel:findHover(px, py, ox, oy)
    self._ox = ox
    self._oy = oy
    if not self.visible or not self:isInside(px, py) then
        return nil
    end
    self:sync()
    if not self.enabled then
        return self
    end

    if self:isOnDivider(px, py) then
        return self
    end

    local lx, ly = px - self:originX(), py - self:originY()
    if paneContains(self.first, lx, ly) then
        local hit = self.first:findHover(px, py, self:originX(), self:originY())
        if hit ~= nil then
            return hit
        end
    end
    if paneContains(self.second, lx, ly) then
        local hit = self.second:findHover(px, py, self:originX(), self:originY())
        if hit ~= nil then
            return hit
        end
    end
    return self
end

--- Finds the child that handles a wheel event at the given point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this split panel's parent.
--- @param oy number Origin Y of this split panel's parent.
--- @return PallidWidget|nil target Widget that handles the wheel, if any.
function SplitPanel:findWheel(px, py, ox, oy)
    self._ox = ox
    self._oy = oy
    if not self.visible or not self.enabled or not self:isInside(px, py) then
        return nil
    end
    self:sync()

    local lx, ly = px - self:originX(), py - self:originY()
    if paneContains(self.first, lx, ly) then
        local hit = self.first:findWheel(px, py, self:originX(), self:originY())
        if hit ~= nil then
            return hit
        end
    end
    if paneContains(self.second, lx, ly) then
        return self.second:findWheel(px, py, self:originX(), self:originY())
    end
    return nil
end
