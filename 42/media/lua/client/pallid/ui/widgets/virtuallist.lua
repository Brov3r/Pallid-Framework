require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/clip"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/scrollbar"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local RECT_SHAPE = Pallid.UI.Shape.rect()
local SCROLL_STEP = 3
local BAR = Widgets.DEFAULT_SCROLLBAR_SIZE or 10

--- Virtualised list leaf. Only the rows intersecting the viewport are drawn
--- and hit-tested; 10 000 rows cost the same as a dozen. Rows have no child
--- widgets: the caller paints each row through `opts.render`.
---
--- Uniform rows use arithmetic offsets. A function `rowHeight` switches to a
--- cached prefix-sum table, rebuilt by `refresh()` after any row size changes.
---
--- `state` passed to `render` is one table reused for every row and every
--- frame. Read it immediately and never retain it.
--- @class PallidVirtualList : PallidWidget
--- @field itemCount integer Number of rows.
--- @field rowHeight number|fun(index: integer): number Uniform height or resolver.
--- @field render fun(el: ISUIElement, index: integer, x: number, y: number, w: number, h: number, state: PallidVirtualRowState)|nil Row painter.
--- @field selectionMode "single"|"multi"|"none" Selection model.
--- @field onSelect fun(list: PallidVirtualList, index: integer)|nil Called after the selection changes.
--- @field selected integer|nil Selected row for "single"; nil when none.
--- @field scrollY number Current vertical scroll offset.
--- @field maxScroll number Maximum scroll offset.
--- @field viewW number Visible width excluding the scrollbar.
--- @field viewH number Visible height.
--- @field barV PallidScrollBar Vertical scrollbar child.
--- @field background PallidColor|nil Optional list fill.
--- @field borderColor PallidColor|nil Optional list outline.
--- @field rowHover PallidColor Hovered row fill.
--- @field rowSelected PallidColor Selected row fill.
local VirtualList = Widgets.class("VirtualList")

--- Mutable per-row state passed to `render`. One instance is reused per list.
--- @class PallidVirtualRowState
--- @field index integer One-based row index.
--- @field hovered boolean True when the cursor is over the row.
--- @field selected boolean True when the row is selected.

--- Creates a new `VirtualList` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil List content and behaviour.
--- @field opts.itemCount integer|nil Number of rows, defaults to 0.
--- @field opts.rowHeight number|fun(index: integer): number|nil Row height, defaults to 22.
--- @field opts.render fun(el: ISUIElement, index: integer, x: number, y: number, w: number, h: number, state: PallidVirtualRowState)|nil Row painter.
--- @field opts.selectionMode "single"|"multi"|"none"|nil Defaults to "single".
--- @field opts.onSelect fun(list: PallidVirtualList, index: integer)|nil Selection callback.
--- @field opts.background PallidColor|nil Optional fill.
--- @field opts.border PallidColor|nil Optional outline.
--- @field opts.radius number|nil Corner radius, defaults to 0.
--- @field opts.barSize number|nil Scrollbar thickness, defaults to 10.
--- @field opts.barGap number|nil Gap between the scrollbar and the edge; nil picks 3 or 5.
--- @return PallidVirtualList list New virtual list.
function VirtualList.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, VirtualList)
    self:init(x, y, w or 0, h or 0)

    self.itemCount = math.max(0, math.floor(opts.itemCount or 0))
    self.rowHeight = opts.rowHeight or 22
    self.render = opts.render
    self.selectionMode = opts.selectionMode or "single"
    if self.selectionMode ~= "single" and self.selectionMode ~= "multi"
        and self.selectionMode ~= "none" then
        Pallid.log("VirtualList: unknown selectionMode '" .. tostring(self.selectionMode) .. "'; using \"single\"")
        self.selectionMode = "single"
    end
    self.onSelect = opts.onSelect
    self.selected = nil
    self._selected = {}
    self._hoverIndex = 0
    self._state = { index = 0, hovered = false, selected = false }
    self._offsets = nil
    self._contentH = 0
    self._scrollPx = 0

    self.scrollY = 0
    self.maxScroll = 0
    self.viewW = self.w
    self.viewH = self.h
    self.barSize = math.max(1, math.floor(opts.barSize or BAR))
    self.barGap = opts.barGap
    self.background = opts.background
    self.borderColor = opts.border
    self.radius = opts.radius or 0
    self.rowHover = Pallid.UI.Color.accentSoft
    self.rowSelected = Pallid.UI.Color.primarySoft

    self.barV = Widgets.scrollBar(true, self.w - self.barSize, 0, self.barSize, self.h, { margin = 1 })
    self.barV.onChange = function(_, value)
        self.scrollY = value * (self.maxScroll or 0)
    end
    self.barV:setOverlay(true)
    self:add(self.barV)

    self:refresh()
    return self
end

--- Factory shortcut for `VirtualList.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil List content and behaviour; see `VirtualList.new`.
--- @return PallidVirtualList list New virtual list.
function Widgets.virtualList(x, y, w, h, opts)
    return VirtualList.new(x, y, w, h, opts)
end

--- @param index integer One-based row index.
--- @return number height Row height in pixels, at least 1.
function VirtualList:_rowHeightAt(index)
    local source = self.rowHeight
    local height
    if type(source) == "function" then
        height = source(index)
    else
        height = source
    end
    if type(height) ~= "number" or height ~= height then
        return 1
    end
    return math.max(1, height)
end

--- Rebuilds the offset cache and the scroll range. Call after row heights or
--- the item count change; the cache is not rebuilt while drawing.
--- @return PallidVirtualList self For chaining.
function VirtualList:refresh()
    local count = self.itemCount
    local source = self.rowHeight
    if type(source) == "function" then
        local offsets = self._offsets
        if offsets == nil then
            offsets = {}
            self._offsets = offsets
        end
        local total = 0
        for i = 1, count do
            offsets[i] = total
            total = total + self:_rowHeightAt(i)
        end
        offsets[count + 1] = total
        self._contentH = total
    else
        self._offsets = nil
        self._contentH = count * self:_rowHeightAt(1)
    end
    self:sync()
    return self
end

--- Recomputes the viewport, scrollbar geometry and the clamped scroll offset.
function VirtualList:sync()
    local viewH = math.max(0, self.h)
    local contentH = self._contentH
    local gap = math.max(0, self.barGap or (math.min(self.w, self.h) < 80 and 3 or 5))
    local barFits = self.w > self.barSize + gap * 2 and viewH > gap * 2
    local needV = contentH > viewH and barFits

    self.viewW = math.max(0, needV and (self.w - self.barSize - gap) or self.w)
    self.viewH = viewH
    self.maxScroll = math.max(0, contentH - viewH)
    self.scrollY = math.max(0, math.min(self.maxScroll, self.scrollY))
    self._scrollPx = math.floor(self.scrollY + 0.5)

    self.barV:setEnabled(self.enabled)
    if needV then
        self.barV:setVisible(true)
        self.barV:setBounds(
            self.w - self.barSize - gap,
            gap,
            self.barSize,
            math.max(1, viewH - gap * 2)
        )
        self.barV.page = math.min(1, viewH / math.max(1, contentH))
        self.barV.value = self.maxScroll > 0 and self.scrollY / self.maxScroll or 0
    else
        self.barV:setVisible(false)
        self.barV.value = 0
        self.barV.page = 1
    end
end

--- Returns the content-space top offset of a row.
--- @param index integer One-based row index.
--- @return number y Offset in pixels from the content start.
function VirtualList:rowOffset(index)
    if self._offsets ~= nil then
        return self._offsets[index] or 0
    end
    return (index - 1) * self:_rowHeightAt(index)
end

--- Returns the first row index containing a content-space Y offset.
--- @param y number Content-space offset.
--- @return integer index One-based row index; clamped to the list.
function VirtualList:_indexAtOffset(y)
    local count = self.itemCount
    if count <= 0 then
        return 0
    end
    if y < 0 then
        return 1
    end
    if y >= self._contentH then
        return count
    end

    local offsets = self._offsets
    if offsets == nil then
        local height = self:_rowHeightAt(1)
        return math.min(count, math.floor(y / height) + 1)
    end

    local low, high = 1, count
    while low <= high do
        local middle = math.floor((low + high) * 0.5)
        local start = offsets[middle]
        local finish = offsets[middle + 1]
        if y < start then
            high = middle - 1
        elseif y >= finish then
            low = middle + 1
        else
            return middle
        end
    end
    return math.min(count, low)
end

--- Returns the visible row range and its Y position.
--- @param rowY number|nil Row Y offset to test instead of the scroll offset.
--- @return integer first First visible row, or 0 when the list is empty.
--- @return integer last Last visible row, or 0.
function VirtualList:_visibleRange(rowY)
    local count = self.itemCount
    if count <= 0 or self.viewH <= 0 then
        return 0, 0
    end
    local top = rowY or self._scrollPx
    local first = self:_indexAtOffset(top)
    local bottom = top + self.viewH
    local last = self:_indexAtOffset(bottom)
    -- The row containing `bottom` may start exactly at the viewport edge.
    while last > first and self:rowOffset(last) >= bottom do
        last = last - 1
    end
    if first < 1 then
        first = 1
    end
    if last < first then
        last = first
    end
    return first, math.min(count, last)
end

--- Sets the number of rows and rebuilds the offset cache.
--- @param count integer New row count.
--- @return PallidVirtualList self For chaining.
function VirtualList:setItemCount(count)
    self.itemCount = math.max(0, math.floor(count or 0))
    if self.selected ~= nil and self.selected > self.itemCount then
        self.selected = nil
    end
    self._hoverIndex = 0
    return self:refresh()
end

--- Scrolls to a content-space Y offset, clamped to the list range.
--- @param y number Offset in pixels from the content start.
--- @return PallidVirtualList self For chaining.
function VirtualList:scrollTo(y)
    self.scrollY = math.max(0, math.min(self.maxScroll, y or 0))
    self:sync()
    return self
end

--- Returns the current scroll offset.
--- @return number y Offset in pixels from the content start.
function VirtualList:getScroll()
    return self.scrollY
end

--- Replaces the selection.
--- @param index integer|nil One-based row index; nil clears it.
--- @param silent boolean|nil True skips `onSelect`.
--- @return PallidVirtualList self For chaining.
function VirtualList:setSelected(index, silent)
    if index ~= nil then
        index = math.floor(index)
        if index < 1 or index > self.itemCount then
            index = nil
        end
    end
    self.selected = index
    self._selected = {}
    if index ~= nil then
        self._selected[index] = true
    end
    if not silent and self.onSelect ~= nil then
        self.onSelect(self, index)
    end
    return self
end

--- @param index integer Row index.
--- @return boolean selected True when the row is selected.
function VirtualList:isSelected(index)
    if self.selectionMode == "multi" then
        return self._selected[index] == true
    end
    return self.selected == index
end

--- Returns the index of the row under a root-local Y coordinate.
--- @param py number Cursor Y in root-local coordinates.
--- @return integer index One-based row index, or 0 when outside the rows.
function VirtualList:indexAt(py)
    local localY = py - self:originY() + self._scrollPx
    if localY < 0 or localY >= self._contentH then
        return 0
    end
    return self:_indexAtOffset(localY)
end

--- Selects a row using the current selection mode.
--- @param index integer One-based row index.
--- @param additive boolean|nil True toggles a row in "multi" mode.
function VirtualList:_select(index, additive)
    if self.selectionMode == "none" or index <= 0 then
        return
    end
    if self.selectionMode == "multi" then
        if additive then
            self._selected[index] = not self._selected[index] or nil
            self.selected = self._selected[index] and index or nil
        else
            self._selected = {}
            self._selected[index] = true
            self.selected = index
        end
    else
        self.selected = index
    end
    if self.onSelect ~= nil then
        self.onSelect(self, index)
    end
end

--- Handles a pointer press on a row.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the press landed inside the list.
function VirtualList:onDown(px, py, button)
    if not self.enabled then
        return false
    end
    if button == "right" then
        return true
    end
    local index = self:indexAt(py)
    if index == 0 then
        return true
    end
    local additive = self.selectionMode == "multi" and Keyboard ~= nil
        and Keyboard.isKeyDown ~= nil
        and (Keyboard.isKeyDown(Keyboard.KEY_LCONTROL) or Keyboard.isKeyDown(Keyboard.KEY_RCONTROL))
    self:_select(index, additive)
    return true
end

--- Tracks the hovered row.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function VirtualList:onHoverMove(px, py)
    self._hoverIndex = self:indexAt(py)
end

--- Clears the hovered row.
function VirtualList:onHoverEnd()
    self._hoverIndex = 0
    Widgets.Widget.onHoverEnd(self)
end

--- Scrolls the list with the wheel.
--- @param delta number Wheel steps; positive scrolls down.
--- @return boolean handled True when the list could scroll.
function VirtualList:onWheel(delta)
    if not self.enabled or self.maxScroll <= 0 then
        return false
    end
    self.scrollY = math.max(0, math.min(self.maxScroll, self.scrollY + delta * self:_rowHeightAt(1) * SCROLL_STEP))
    return true
end

--- Paints the visible rows and the idle chrome.
--- @param el ISUIElement Host element the tree is rendered into.
function VirtualList:drawSelf(el)
    self:sync()
    if self.w <= 0 or self.h <= 0 then
        return
    end
    local x, y = self:originX(), self:originY()

    if self.background ~= nil then
        Pallid.UI.roundedRect(el, x, y, self.w, self.h, self.radius, self:shade(self.background))
    end
    if self.borderColor ~= nil then
        Pallid.UI.roundedBorder(el, x, y, self.w, self.h, self.radius, 1, self:shade(self.borderColor))
    end

    local viewW = self.viewW
    local viewH = self.viewH
    if viewW <= 0 or viewH <= 0 then
        return
    end

    local render = self.render
    if render == nil then
        return
    end

    local entered = Pallid.UI.clip(el, RECT_SHAPE, x, y, viewW, viewH)
    if not entered then
        return
    end

    local scrollPx = self._scrollPx
    local state = self._state
    local first, last = self:_visibleRange()
    for i = first, last do
        local rowY = y + self:rowOffset(i) - scrollPx
        local rowH = self:_rowHeightAt(i)
        if rowY + rowH > y and rowY < y + viewH then
            state.index = i
            state.hovered = i == self._hoverIndex
            state.selected = self:isSelected(i)
            render(el, i, x, rowY, viewW, rowH, state)
        end
    end

    Pallid.UI.clipEnd(el)
end
