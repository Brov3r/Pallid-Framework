require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/geometry"
require "pallid/ui/api/clip"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/panel"
require "pallid/ui/widgets/scrollbar"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local RECT_SHAPE = Pallid.UI.Shape.rect()
local BAR_SIZE = Widgets.DEFAULT_SCROLLBAR_SIZE or 10
local WHEEL_STEP = 28

--- True when a child can affect the visible viewport.
--- Zero-sized layout containers are always visited so their children update.
--- @param child PallidWidget Child positioned in content-local coordinates.
--- @param left number Viewport left in content-local coordinates.
--- @param top number Viewport top in content-local coordinates.
--- @param right number Viewport right in content-local coordinates.
--- @param bottom number Viewport bottom in content-local coordinates.
--- @return boolean visible True when the child should be updated.
local function touchesViewport(child, left, top, right, bottom)
    if child.w <= 0 or child.h <= 0 then
        return true
    end
    return child.x + child.w > left and child.x < right
        and child.y + child.h > top and child.y < bottom
end

--- Scrollable container. `content` is a Panel the caller fills; it is clipped
--- to the viewport and offset by the scroll position. Bars are ordinary
--- ScrollBar children and only appear when the content is larger than the
--- viewport.
---
--- The viewport is recomputed until it is stable: a vertical bar narrows the
--- content area, which may require a horizontal bar, which in turn shortens
--- the content area and may require the vertical bar. Resolving this in a
--- single pass used to leave the viewport one bar wider than the real,
--- clipped rectangle; scrolling then moved content outside the stale clip.
--- @class PallidScrollPanel : PallidPanel
--- @field content PallidPanel Scrolled content container.
--- @field scrollX number Horizontal scroll offset in pixels.
--- @field scrollY number Vertical scroll offset in pixels.
--- @field verticalEnabled boolean Whether a vertical bar may appear.
--- @field horizontalEnabled boolean Whether a horizontal bar may appear.
--- @field barV PallidScrollBar Vertical scrollbar child.
--- @field barH PallidScrollBar Horizontal scrollbar child.
--- @field viewW number Visible viewport width after bar gutters.
--- @field viewH number Visible viewport height after bar gutters.
local ScrollPanel = Widgets.class("ScrollPanel", Widgets.Panel)

--- Creates a new `ScrollPanel` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional appearance and scrolling settings.
--- @field opts.background PallidColor|nil Panel fill.
--- @field opts.border PallidColor|nil Panel border.
--- @field opts.radius number|nil Corner radius.
--- @field opts.vertical boolean|nil Enables the vertical bar, defaults to true.
--- @field opts.horizontal boolean|nil Enables the horizontal bar, defaults to false.
--- @field opts.barSize number|nil Bar thickness, defaults to 10.
--- @field opts.barGap number|nil Gap between bars and the panel edge.
--- @field opts.wheelStep number|nil Pixels per wheel notch, defaults to 28.
--- @field opts.contentW number|nil Initial content width.
--- @field opts.contentH number|nil Initial content height.
--- @return PallidScrollPanel panel New scroll panel instance.
function ScrollPanel.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable(Widgets.Panel.new(x, y, w, h, opts), ScrollPanel)

    self.verticalEnabled = opts.vertical ~= false
    self.horizontalEnabled = opts.horizontal or false
    self.barSize = opts.barSize or BAR_SIZE
    self.barGap = opts.barGap
    self.wheelStep = opts.wheelStep or WHEEL_STEP
    self.scrollX = 0
    self.scrollY = 0
    self.viewW = w
    self.viewH = h

    self.content = Widgets.panel(0, 0, opts.contentW or 0, opts.contentH or 0)
    self.content.parent = self

    self.maxX = 0
    self.maxY = 0

    self.barV = Widgets.scrollBar(true, w - self.barSize, 0, self.barSize, h, {
        onChange = function(_, value)
            self.scrollY = value * (self.maxY or 0)
        end,
    })
    self.barH = Widgets.scrollBar(false, 0, h - self.barSize, w, self.barSize, {
        onChange = function(_, value)
            self.scrollX = value * (self.maxX or 0)
        end,
    })
    self:add(self.barV)
    self:add(self.barH)

    return self
end

--- Factory shortcut for `ScrollPanel.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional settings; see `ScrollPanel.new`.
--- @return PallidScrollPanel panel New scroll panel instance.
function Widgets.scrollPanel(x, y, w, h, opts)
    return ScrollPanel.new(x, y, w, h, opts)
end

--- Sets the scrollable content size.
--- @param w number New content width in pixels.
--- @param h number New content height in pixels.
--- @return PallidScrollPanel self For chaining.
function ScrollPanel:setContentSize(w, h)
    self.content.w = math.max(0, w or 0)
    self.content.h = math.max(0, h or 0)
    self:sync()
    return self
end

--- Returns the current scroll offsets.
--- @return number x Horizontal offset in pixels.
--- @return number y Vertical offset in pixels.
function ScrollPanel:getScroll()
    return self.scrollX, self.scrollY
end

--- Scrolls to the given offsets, clamped to the content range.
--- @param x number Horizontal offset in pixels.
--- @param y number Vertical offset in pixels.
--- @param silent boolean|nil True skips updating scrollbar values.
--- @return PallidScrollPanel self For chaining.
function ScrollPanel:scrollTo(x, y, silent)
    self:sync()
    self.scrollX = math.max(0, math.min(self.maxX or 0, x or 0))
    self.scrollY = math.max(0, math.min(self.maxY or 0, y or 0))
    if not silent then
        if self.barV.visible then
            self.barV.value = self.maxY > 0 and self.scrollY / self.maxY or 0
        end
        if self.barH.visible then
            self.barH.value = self.maxX > 0 and self.scrollX / self.maxX or 0
        end
    end
    return self
end

--- Recomputes bar visibility, page sizes and scroll offsets. Called once per
--- draw and before wheel handling, so the layout is always current.
function ScrollPanel:sync()
    local content = self.content
    local width, height = math.max(0, self.w), math.max(0, self.h)
    local barSize = math.max(1, self.barSize or BAR_SIZE)

    -- The panel is synced from draw, update, updateAnimations and input paths.
    -- Skip the whole bar layout when none of its inputs changed.
    if self._syncContent == content
        and self._syncW == width
        and self._syncH == height
        and self._syncContentW == content.w
        and self._syncContentH == content.h
        and self._syncBarSize == barSize
        and self._syncBarGap == self.barGap
        and self._syncVertical == self.verticalEnabled
        and self._syncHorizontal == self.horizontalEnabled
        and self._syncScrollX == self.scrollX
        and self._syncScrollY == self.scrollY then
        return
    end

    self._syncContent = content
    self._syncW = width
    self._syncH = height
    self._syncContentW = content.w
    self._syncContentH = content.h
    self._syncBarSize = barSize
    self._syncBarGap = self.barGap

    local gap = self.barGap or (math.min(self.w, self.h) < 80 and 3 or 5)
    self._barGap = gap

    local needV, needH
    local viewW, viewH
    for _ = 1, 3 do
        needV = self.verticalEnabled and content.h > height
        viewW = width - (needV and (barSize + gap) or 0)
        needH = self.horizontalEnabled and content.w > viewW
        viewH = height - (needH and (barSize + gap) or 0)
        -- A shorter viewport can make the vertical bar necessary after all.
        local nextV = self.verticalEnabled and content.h > viewH
        local nextH = self.horizontalEnabled and content.w > width - (nextV and (barSize + gap) or 0)
        if nextV == needV and nextH == needH then
            break
        end
        needV, needH = nextV, nextH
    end

    -- Recompute the final viewport from the settled bar set.
    viewW = math.max(0, width - (needV and (barSize + gap) or 0))
    viewH = math.max(0, height - (needH and (barSize + gap) or 0))

    self.viewW = viewW
    self.viewH = viewH

    if needV then
        self.barV:setVisible(true)
        self.barV:setBounds(
            math.max(0, width - barSize - gap),
            math.max(0, gap),
            barSize,
            math.max(1, height - gap * 2 - (needH and (barSize + gap) or 0))
        )
        self.barV.page = math.max(0, math.min(1, viewH / math.max(1, content.h)))
    else
        self.barV:setVisible(false)
        self.barV.value = 0
    end

    if needH then
        self.barH:setVisible(true)
        self.barH:setBounds(
            math.max(0, gap),
            math.max(0, height - barSize - gap),
            math.max(1, width - gap * 2 - (needV and (barSize + gap) or 0)),
            barSize
        )
        self.barH.page = math.max(0, math.min(1, viewW / math.max(1, content.w)))
    else
        self.barH:setVisible(false)
        self.barH.value = 0
    end

    local maxY = math.max(0, content.h - viewH)
    self.maxY = maxY
    self.scrollY = math.max(0, math.min(maxY, self.scrollY))
    if needV then
        self.barV.value = maxY > 0 and self.scrollY / maxY or 0
    end

    local maxX = math.max(0, content.w - viewW)
    self.maxX = maxX
    self.scrollX = math.max(0, math.min(maxX, self.scrollX))
    if needH then
        self.barH.value = maxX > 0 and self.scrollX / maxX or 0
    end

    self._syncVertical = self.verticalEnabled
    self._syncHorizontal = self.horizontalEnabled
    self._syncScrollX = self.scrollX
    self._syncScrollY = self.scrollY
end

--- `content` is owned but not in `children`, so lifecycle notifications from the
--- base traversal would never reach widgets inside it.
function ScrollPanel:onAttach()
    if self.content ~= nil then
        self.content:_notifyAttached()
    end
end

--- Cleans up when the widget is detached from the tree.
function ScrollPanel:onDetach()
    if self.content ~= nil then
        self.content:_notifyDetached()
    end
end

--- Shows or hides the native input boxes.
--- @param visible boolean False hides native boxes in the content and bars.
function ScrollPanel:setNativeVisible(visible)
    self.content:setNativeVisible(visible)
    local list = self.children
    if list ~= nil then
        for i = 1, #list do
            list[i]:setNativeVisible(visible)
        end
    end
end

--- Unfocuses every native text box in the subtree.
function ScrollPanel:blurNative()
    self.content:blurNative()
    local list = self.children
    if list ~= nil then
        for i = 1, #list do
            list[i]:blurNative()
        end
    end
end

--- Paints the widget and its children.
--- @param el ISUIElement Host element the tree is rendered into.
--- @param ox number Origin X of this panel's parent.
--- @param oy number Origin Y of this panel's parent.
function ScrollPanel:draw(el, ox, oy)
    if self.parent == nil and Pallid.UI.resetClip ~= nil then
        Pallid.UI.resetClip(el)
    end
    self._ox = ox
    self._oy = oy
    if not self.visible then
        return
    end

    self:sync()
    self:drawSelf(el)

    local cx, cy = self:originX(), self:originY()
    if self.viewW > 0 and self.viewH > 0 then
        local entered = Pallid.UI.clip(el, RECT_SHAPE, cx, cy, self.viewW, self.viewH)
        self.content:draw(el, cx - self.scrollX, cy - self.scrollY)
        if entered then
            Pallid.UI.clipEnd(el)
        end
    end

    local list = self.children
    if list ~= nil then
        for i = 1, #list do
            list[i]:draw(el, cx, cy)
        end
    end
end

--- Advances the widget state for the current frame.
--- @param now number Current game-tick time in seconds.
function ScrollPanel:update(now)
    if not self.visible then
        return
    end
    self:sync()

    -- Update only the content children intersecting the viewport. Updating
    -- every child in a 4 000-row list costs 10+ ms per frame even when only a
    -- fraction is visible.
    local content = self.content
    content._dt = content:delta(now)
    content:onUpdate(now, content._dt)
    local list = content.children
    if list ~= nil then
        local left, top = self.scrollX, self.scrollY
        local right, bottom = left + self.viewW, top + self.viewH
        for i = 1, #list do
            local child = list[i]
            if child.visible and touchesViewport(child, left, top, right, bottom) then
                child:update(now)
            end
        end
        for i = #list, 1, -1 do
            local child = list[i]
            if child._dead then
                table.remove(list, i)
                child.parent = nil
            end
        end
    end

    -- Base update owns onUpdate, bar children, overlays and dead-child cleanup.
    Widgets.Widget.update(self, now)
end

--- Content is drawn manually and is not in `children`, so the base traversal
--- would skip it. The visible-only filter mirrors `update`: animating four
--- thousand off-screen rows costs more than it is worth.
--- @param now number Current time in seconds.
function ScrollPanel:updateAnimations(now)
    if not self.visible then
        return
    end
    self:sync()
    Widgets.Widget.updateAnimations(self, now)

    local content = self.content
    local animate = content.onAnimate
    if animate ~= nil and animate ~= Widgets.Widget.onAnimate then
        animate(content, now, content:animDelta(now))
    end

    local list = content.children
    if list ~= nil then
        local left, top = self.scrollX, self.scrollY
        local right, bottom = left + self.viewW, top + self.viewH
        for i = 1, #list do
            local child = list[i]
            if child.visible and touchesViewport(child, left, top, right, bottom) then
                child:updateAnimations(now)
            end
        end
    end
end

--- The content is clipped to the viewport, not to the panel box: a point over
--- the scrollbar gutter or outside the viewport cannot reach a child even when
--- the child's own rectangle covers it.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean clipped True when the point is outside the painted viewport.
function ScrollPanel:clipsPoint(px, py)
    if self.clipChildren == true and not self:isInside(px, py) then
        return true
    end
    local x, y = self:originX(), self:originY()
    return px < x or px >= x + self.viewW or py < y or py >= y + self.viewH
end

--- Finds the child that handles a press at the given point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this panel's parent.
--- @param oy number Origin Y of this panel's parent.
--- @param button string|nil "left" or "right".
--- @return PallidWidget|nil target Widget that accepted the press.
function ScrollPanel:findDown(px, py, ox, oy, button)
    self._ox = ox
    self._oy = oy
    if not self.visible then
        return nil
    end
    self:sync()

    local cx, cy = self:originX(), self:originY()
    local list = self.children
    if list ~= nil then
        for i = #list, 1, -1 do
            local hit = list[i]:findDown(px, py, cx, cy, button)
            if hit ~= nil then
                return hit
            end
        end
    end

    if px >= cx and px < cx + self.viewW and py >= cy and py < cy + self.viewH then
        return self.content:findDown(px, py, cx - self.scrollX, cy - self.scrollY, button)
    end
    return nil
end

--- Finds the child that handles hover at the given point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this panel's parent.
--- @param oy number Origin Y of this panel's parent.
--- @return PallidWidget|nil hovered Widget under the cursor.
function ScrollPanel:findHover(px, py, ox, oy)
    self._ox = ox
    self._oy = oy
    if not self.visible then
        return nil
    end
    self:sync()

    local cx, cy = self:originX(), self:originY()
    local list = self.children
    if list ~= nil then
        for i = #list, 1, -1 do
            local hit = list[i]:findHover(px, py, cx, cy)
            if hit ~= nil then
                return hit
            end
        end
    end

    if px >= cx and px < cx + self.viewW and py >= cy and py < cy + self.viewH then
        local hit = self.content:findHover(px, py, cx - self.scrollX, cy - self.scrollY)
        if hit ~= nil then
            return hit
        end
    end

    if self:isInside(px, py) then
        return self
    end
    return nil
end

--- Finds the child that handles a wheel event at the given point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this panel's parent.
--- @param oy number Origin Y of this panel's parent.
--- @return PallidWidget|nil target Widget that handles the wheel.
function ScrollPanel:findWheel(px, py, ox, oy)
    self._ox = ox
    self._oy = oy
    if not self.visible then
        return nil
    end

    self:sync()
    local cx, cy = self:originX(), self:originY()
    local inView = px >= cx and px < cx + self.viewW
        and py >= cy and py < cy + self.viewH

    -- The content is owned manually and is not in `children`. It must be asked
    -- first: otherwise a nested ScrollPanel, Table or TreeView with its own
    -- scrollbar never receives the wheel because the outer panel claims it.
    if inView then
        local hit = self.content:findWheel(px, py, cx - self.scrollX, cy - self.scrollY)
        if hit ~= nil then
            return hit
        end
    end

    local canV = self.verticalEnabled and self.content.h > self.viewH
    local canH = self.horizontalEnabled and self.content.w > self.viewW
    if (canV or canH) and self:isInside(px, py) then
        return self
    end
    return nil
end

--- Wheel scrolls vertically; holding Shift (or the horizontal-only panel)
--- scrolls horizontally.
--- @param delta number Wheel steps; positive scrolls up.
--- @return boolean handled True when the panel scrolled.
function ScrollPanel:onWheel(delta)
    self:sync()

    local horizontal = self.horizontalEnabled and self.content.w > self.viewW
    local vertical = self.verticalEnabled and self.content.h > self.viewH
    local shift = Keyboard ~= nil and Keyboard.isKeyDown ~= nil
        and (Keyboard.isKeyDown(Keyboard.KEY_LSHIFT) or Keyboard.isKeyDown(Keyboard.KEY_RSHIFT))

    if horizontal and (shift or not vertical) then
        self.scrollX = math.max(0, math.min(self.maxX, self.scrollX + delta * self.wheelStep))
        return true
    end
    if vertical then
        self.scrollY = math.max(0, math.min(self.maxY, self.scrollY + delta * self.wheelStep))
        return true
    end
    return false
end
