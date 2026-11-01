require "pallid/ui/internal"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Invisible fixed-column grid. Cells are laid out row-major; `cellW`/`cellH`
--- can force a size, otherwise the grid divides its own box evenly. Forced
--- cells may overflow the box: the grid does not clip.
---
--- Cell content is stretched to the cell by default. `alignH`/`alignV` place a
--- child at its own size instead. `autoSize` (or the per-axis flags) fits the
--- grid to its cells and children; without it the caller owns the box size.
--- @class PallidGrid : PallidWidget
--- @field columns integer Number of columns; clamped to at least 1.
--- @field padding number Inner inset on every side in pixels.
--- @field gap number Gap between cells in both axes.
--- @field cellW number|nil Forced cell width; nil divides the box.
--- @field cellH number|nil Forced cell height; nil divides the box.
--- @field alignH "stretch"|"start"|"center"|"end" Horizontal child placement.
--- @field alignV "stretch"|"start"|"center"|"end" Vertical child placement.
--- @field autoWidth boolean True fits the grid width to its cells.
--- @field autoHeight boolean True fits the grid height to its cells.
local Grid = Widgets.class("Grid")

--- Creates a new `Grid` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param columns integer Column count; values below 1 are clamped to 1.
--- @param opts table|nil Optional layout metrics.
--- @field opts.padding number|nil Inner inset, defaults to 0.
--- @field opts.gap number|nil Gap between cells in both axes, defaults to 4.
--- @field opts.cellW number|nil Forced cell width.
--- @field opts.cellH number|nil Forced cell height.
--- @field opts.align "stretch"|"start"|"center"|"end"|nil Placement on both axes,
---                     defaults to "stretch".
--- @field opts.alignH "stretch"|"start"|"center"|"end"|nil Horizontal placement.
--- @field opts.alignV "stretch"|"start"|"center"|"end"|nil Vertical placement.
--- @field opts.autoSize boolean|nil True fits both axes to the cells.
--- @field opts.autoWidth boolean|nil True fits only the width.
--- @field opts.autoHeight boolean|nil True fits only the height.
--- @return PallidGrid grid New grid container.
function Grid.new(x, y, w, h, columns, opts)
    opts = opts or {}
    local self = setmetatable({}, Grid)
    self:init(x, y, w, h)
    self.columns = math.max(1, math.floor(columns or 1))
    self.padding = opts.padding or 0
    self.gap = opts.gap or 4
    self.cellW = opts.cellW
    self.cellH = opts.cellH
    local align = opts.align or "stretch"
    self.alignH = opts.alignH or align
    self.alignV = opts.alignV or align
    local auto = opts.autoSize == true
    self.autoWidth = auto or opts.autoWidth == true
    self.autoHeight = auto or opts.autoHeight == true
    return self
end

--- Factory shortcut for `Grid.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param columns integer Column count.
--- @param opts table|nil Optional layout metrics; see `Grid.new`.
--- @return PallidGrid grid New grid container.
function Widgets.grid(x, y, w, h, columns, opts)
    return Grid.new(x, y, w, h, columns, opts)
end

--- Adds a child and re-runs the layout.
--- @param child PallidWidget Widget to attach.
--- @return PallidWidget child The same widget, for chaining.
function Grid:add(child)
    Widgets.Widget.add(self, child)
    self:layout()
    return child
end

--- Detaches a child and re-runs the layout so the cells reflow.
--- @param child PallidWidget Widget to detach.
function Grid:remove(child)
    Widgets.Widget.remove(self, child)
    self:layout()
end

--- Resizes the grid and re-runs the layout.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidGrid self For chaining.
function Grid:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:layout()
    return self
end

--- Places children row-major. The column count is re-clamped here because the
--- field is public and may be changed directly after construction.
function Grid:layout()
    local list = self.children
    if list == nil then
        return
    end

    local columns = math.max(1, math.floor(self.columns or 1))
    local count = #list
    local rows = math.ceil(count / columns)
    local padding = self.padding
    local gap = self.gap

    -- Natural cell size is measured before any child is stretched. `cellW` and
    -- `cellH` take precedence; otherwise the largest child defines it.
    if self.autoWidth or self.autoHeight then
        local naturalW, naturalH = 0, 0
        for i = 1, count do
            local child = list[i]
            if child.w > naturalW then
                naturalW = child.w
            end
            if child.h > naturalH then
                naturalH = child.h
            end
        end
        if self.autoWidth then
            local cellsW = self.cellW or naturalW
            self.w = padding * 2 + columns * cellsW + gap * math.max(0, columns - 1)
        end
        if self.autoHeight then
            local cellsH = self.cellH or naturalH
            self.h = padding * 2 + rows * cellsH + gap * math.max(0, rows - 1)
        end
    end

    local cellW = self.cellW or ((self.w - padding * 2 - gap * (columns - 1)) / columns)
    local cellH = self.cellH or ((self.h - padding * 2 - gap * math.max(0, rows - 1)) / math.max(1, rows))

    local alignH = self.alignH
    local alignV = self.alignV

    for i = 1, count do
        local column = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        local cellX = padding + column * (cellW + gap)
        local cellY = padding + row * (cellH + gap)
        local child = list[i]

        local childW, childX = cellW, cellX
        if alignH ~= "stretch" then
            childW = math.min(math.max(0, child.w), cellW)
            if alignH == "center" then
                childX = cellX + (cellW - childW) * 0.5
            elseif alignH == "end" then
                childX = cellX + cellW - childW
            end
        end

        local childH, childY = cellH, cellY
        if alignV ~= "stretch" then
            childH = math.min(math.max(0, child.h), cellH)
            if alignV == "center" then
                childY = cellY + (cellH - childH) * 0.5
            elseif alignV == "end" then
                childY = cellY + cellH - childH
            end
        end

        child:setBounds(childX, childY, childW, childH)
    end
end
