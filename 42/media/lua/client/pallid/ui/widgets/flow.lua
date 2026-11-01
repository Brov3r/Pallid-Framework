require "pallid/ui/internal"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Wrapping layout container. Children keep their own sizes and flow left to
--- right; a child that does not fit starts a new row. Unlike VBox/HBox this
--- container never stretches its children, which makes it suitable for chips,
--- tags, badges, cards and responsive button groups.
---
--- The box width is the wrap limit. With `autoHeight` (also implied when the
--- height is omitted) the box grows to fit every row.
--- @class PallidFlow : PallidWidget
--- @field padding number Inner inset on every side in pixels.
--- @field gapX number Horizontal gap between children in pixels.
--- @field gapY number Vertical gap between rows in pixels.
--- @field align "start"|"center"|"end" Horizontal placement of each row.
--- @field autoHeight boolean True fits the box height to its rows.
--- @field preferredHeight number|nil Cached content height from the last layout.
local Flow = Widgets.class("Flow")

--- Creates a new `Flow` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels; the wrap limit.
--- @param h number|nil Height in pixels; nil or 0 grows to the content.
--- @param opts table|nil Layout metrics.
--- @field opts.padding number|nil Inner inset, defaults to 0.
--- @field opts.gapX number|nil Horizontal child gap, defaults to 4.
--- @field opts.gapY number|nil Row gap, defaults to 4.
--- @field opts.align "start"|"center"|"end"|nil Row placement, defaults to "start".
--- @field opts.autoHeight boolean|nil True fits the height to the content.
--- @return PallidFlow flow New flow container.
function Flow.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, Flow)
    self:init(x, y, w or 0, h or 0)
    self.padding = math.max(0, opts.padding or 0)
    self.gapX = math.max(0, opts.gapX or 4)
    self.gapY = math.max(0, opts.gapY or 4)
    self.align = opts.align or "start"
    self.autoHeight = (h == nil or h <= 0) or opts.autoHeight == true
    self.preferredHeight = self.h
    return self
end

--- Factory shortcut for `Flow.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number|nil Height in pixels; nil or 0 grows to the content.
--- @param opts table|nil Layout metrics; see `Flow.new`.
--- @return PallidFlow flow New flow container.
function Widgets.flow(x, y, w, h, opts)
    return Flow.new(x, y, w, h, opts)
end

--- Adds a child and re-runs the layout.
--- @param child PallidWidget Widget to attach.
--- @return PallidWidget child The same widget, for chaining.
function Flow:add(child)
    Widgets.Widget.add(self, child)
    self:layout()
    return child
end

--- Detaches a child and re-runs the layout.
--- @param child PallidWidget Widget to detach.
function Flow:remove(child)
    Widgets.Widget.remove(self, child)
    self:layout()
end

--- Resizes the flow and re-runs the layout.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels; 0 keeps the automatic height.
--- @return PallidFlow self For chaining.
function Flow:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    if h == nil or h <= 0 then
        self.autoHeight = true
    end
    self:layout()
    return self
end

--- @param child PallidWidget Child to measure.
--- @param maxW number Available inner width.
--- @return number width Child width in pixels.
--- @return number height Child height in pixels.
function Flow:_childSize(child, maxW)
    local width, height = child:preferredSize(maxW, nil)
    if width <= 0 then
        width = child.w
    end
    if height <= 0 then
        height = child.h
    end
    return width, height
end

--- Places children in wrapping rows. Child bounds are not stretched; only the
--- row origin follows `align`.
function Flow:layout()
    local list = self.children
    if list == nil then
        if self.autoHeight then
            self.h = self.padding * 2
            self.preferredHeight = self.h
        end
        return
    end

    local padding = self.padding
    local gapX = self.gapX
    local gapY = self.gapY
    local innerW = math.max(0, self.w - padding * 2)
    local count = #list
    local index = 1
    local cursorY = padding

    while index <= count do
        local rowStart = index
        local rowWidth = 0
        local rowHeight = 0

        while index <= count do
            local child = list[index]
            local width, height = self:_childSize(child, innerW)
            local advance = rowWidth > 0 and (gapX + width) or width
            if rowWidth > 0 and rowWidth + advance > innerW then
                break
            end
            rowWidth = rowWidth + advance
            if height > rowHeight then
                rowHeight = height
            end
            index = index + 1
        end

        local rowX = padding
        if self.align == "center" then
            rowX = padding + math.max(0, innerW - rowWidth) * 0.5
        elseif self.align == "end" then
            rowX = padding + math.max(0, innerW - rowWidth)
        end

        for i = rowStart, index - 1 do
            local child = list[i]
            local width, height = self:_childSize(child, innerW)
            child:setBounds(rowX, cursorY, width, height)
            rowX = rowX + width + gapX
        end

        cursorY = cursorY + rowHeight + gapY
    end

    local contentH
    if count == 0 then
        contentH = padding * 2
    else
        contentH = cursorY - gapY + padding
    end
    self.preferredHeight = contentH
    if self.autoHeight then
        self.h = self.preferredHeight
    end
end

--- Returns the height the current children need at the current width.
--- @param maxW number|nil Available width; nil uses the current width.
--- @param maxH number|nil Available height; unused.
--- @return number width Preferred width in pixels.
--- @return number height Preferred content height in pixels.
function Flow:preferredSize(maxW, maxH)
    local width = maxW or self.w
    local innerW = math.max(0, width - self.padding * 2)
    local list = self.children or {}
    local rowWidth = 0
    local rowHeight = 0
    local total = self.padding * 2
    for i = 1, #list do
        local child = list[i]
        local childW, childH = self:_childSize(child, innerW)
        local advance = rowWidth > 0 and (self.gapX + childW) or childW
        if rowWidth > 0 and rowWidth + advance > innerW then
            total = total + rowHeight + self.gapY
            rowWidth = childW
            rowHeight = childH
        else
            rowWidth = rowWidth + advance
            if childH > rowHeight then
                rowHeight = childH
            end
        end
    end
    if rowWidth > 0 then
        total = total + rowHeight
    end
    return width, total
end
