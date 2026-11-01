require "pallid/ui/internal"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Invisible container that stacks children vertically with equal spacing.
--- Children with a `weight` (for example Spacer) share the leftover height;
--- fixed children keep their own height and always get the full inner width.
---
--- The box does not size itself from its children: pass the height through
--- `new`/`setBounds` and call `layout()` after changing a child's size. Hidden
--- children still occupy their slot. If fixed children do not fit, they keep
--- their own height and may overflow the box.
--- @class PallidVBox : PallidWidget
--- @field padding number Inner inset on every side in pixels.
--- @field spacing number Gap between neighbouring children in pixels.
local VBox = Widgets.class("VBox")

--- Creates a new `VBox` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels; children are stretched to the inner width.
--- @param h number Height in pixels; the space distributed between children.
--- @param opts table|nil Optional layout metrics.
--- @field opts.padding number|nil Inner inset, defaults to 0.
--- @field opts.spacing number|nil Gap between children, defaults to 4.
--- @return PallidVBox box New vertical layout box.
function VBox.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, VBox)
    self:init(x, y, w, h)
    self.padding = opts.padding or 0
    self.spacing = opts.spacing or 4
    return self
end

--- Factory shortcut for `VBox.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional layout metrics; see `VBox.new`.
--- @return PallidVBox box New vertical layout box.
function Widgets.vbox(x, y, w, h, opts)
    return VBox.new(x, y, w, h, opts)
end

--- Adds a child and re-runs the layout.
--- @param child PallidWidget Widget to attach.
--- @return PallidWidget child The same widget, for chaining.
function VBox:add(child)
    Widgets.Widget.add(self, child)
    self:layout()
    return child
end

--- Detaches a child and re-runs the layout so the freed space is reclaimed.
--- @param child PallidWidget Widget to detach.
function VBox:remove(child)
    Widgets.Widget.remove(self, child)
    self:layout()
end

--- Resizes the box and re-runs the layout.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidVBox self For chaining.
function VBox:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:layout()
    return self
end

--- Places children from top to bottom: fixed heights first, then the leftover
--- height split between weighted children. Call it after changing a child size.
function VBox:layout()
    local list = self.children
    if list == nil then
        return
    end

    local padding = self.padding
    local spacing = self.spacing
    local available = self.h - padding * 2
    local fixed = 0
    local weights = 0

    for i = 1, #list do
        local child = list[i]
        if child.weight ~= nil then
            weights = weights + child.weight
        else
            fixed = fixed + child.h
        end
    end

    local leftover = math.max(0, available - fixed - spacing * math.max(0, #list - 1))
    local cursor = padding
    local width = self.w - padding * 2

    for i = 1, #list do
        local child = list[i]
        local height
        if child.weight ~= nil then
            height = weights > 0 and leftover * child.weight / weights or 0
        else
            height = child.h
        end
        child:setBounds(padding, cursor, width, height)
        cursor = cursor + height + spacing
    end
end
