require "pallid/ui/internal"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Invisible fixed-column grid. Cells are laid out row-major; `cellW`/`cellH`
--- can force a size, otherwise the grid divides its own box evenly. Forced
--- cells may overflow the box: the grid does not clip.
--- @class PallidGrid : PallidWidget
--- @field columns integer Number of columns; clamped to at least 1.
--- @field padding number Inner inset on every side in pixels.
--- @field gap number Gap between cells in both axes.
--- @field cellW number|nil Forced cell width; nil divides the box.
--- @field cellH number|nil Forced cell height; nil divides the box.
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
    local rows = math.ceil(#list / columns)
    local padding = self.padding
    local gap = self.gap

    local cellW = self.cellW or ((self.w - padding * 2 - gap * (columns - 1)) / columns)
    local cellH = self.cellH or ((self.h - padding * 2 - gap * math.max(0, rows - 1)) / math.max(1, rows))

    for i = 1, #list do
        local column = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        list[i]:setBounds(
            padding + column * (cellW + gap),
            padding + row * (cellH + gap),
            cellW,
            cellH
        )
    end
end
