require "pallid/ui/internal"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Invisible container that lays children out in a row with equal spacing.
--- Children with a `weight` (for example Spacer) share the leftover width;
--- fixed children keep their own width and always get the full inner height.
---
--- The box does not size itself from its children: pass the width through
--- `new`/`setBounds` and call `layout()` after changing a child's size. Hidden
--- children still occupy their slot. If fixed children do not fit, they keep
--- their own width and may overflow the box.
--- @class PallidHBox : PallidWidget
--- @field padding number Inner inset on every side in pixels.
--- @field spacing number Gap between neighbouring children in pixels.
local HBox = Widgets.class("HBox")

--- Creates a new `HBox` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels; the space distributed between children.
--- @param h number Height in pixels; children are stretched to the inner height.
--- @param opts table|nil Optional layout metrics.
--- @field opts.padding number|nil Inner inset, defaults to 0.
--- @field opts.spacing number|nil Gap between children, defaults to 4.
--- @return PallidHBox box New horizontal layout box.
function HBox.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, HBox)
    self:init(x, y, w, h)
    self.padding = opts.padding or 0
    self.spacing = opts.spacing or 4
    return self
end

--- Factory shortcut for `HBox.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional layout metrics; see `HBox.new`.
--- @return PallidHBox box New horizontal layout box.
function Widgets.hbox(x, y, w, h, opts)
    return HBox.new(x, y, w, h, opts)
end

--- Adds a child and re-runs the layout.
--- @param child PallidWidget Widget to attach.
--- @return PallidWidget child The same widget, for chaining.
function HBox:add(child)
    Widgets.Widget.add(self, child)
    self:layout()
    return child
end

--- Detaches a child and re-runs the layout so the freed space is reclaimed.
--- @param child PallidWidget Widget to detach.
function HBox:remove(child)
    Widgets.Widget.remove(self, child)
    self:layout()
end

--- Resizes the box and re-runs the layout.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidHBox self For chaining.
function HBox:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:layout()
    return self
end

--- Places children from left to right: fixed widths first, then the leftover
--- width split between weighted children. Call it after changing a child size.
function HBox:layout()
    local list = self.children
    if list == nil then
        return
    end

    local padding = self.padding
    local spacing = self.spacing
    local available = self.w - padding * 2
    local fixed = 0
    local weights = 0

    for i = 1, #list do
        local child = list[i]
        if child.weight ~= nil then
            weights = weights + child.weight
        else
            fixed = fixed + child.w
        end
    end

    local leftover = math.max(0, available - fixed - spacing * math.max(0, #list - 1))
    local cursor = padding
    local height = self.h - padding * 2

    for i = 1, #list do
        local child = list[i]
        local width
        if child.weight ~= nil then
            width = weights > 0 and leftover * child.weight / weights or 0
        else
            width = child.w
        end
        child:setBounds(cursor, padding, width, height)
        cursor = cursor + width + spacing
    end
end
