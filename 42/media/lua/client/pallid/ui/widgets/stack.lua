require "pallid/ui/internal"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Invisible z-order container. Children keep their own bounds; the first child
--- is drawn first, so later children sit on top (for example an icon over a
--- picture).
---
--- With `fill` every child is stretched to the padded box, which turns Stack
--- into a simple overlay layer. With `autoSize` the container grows to the
--- furthest child extent.
--- @class PallidStack : PallidWidget
--- @field padding number Inner inset used by `fill` and `autoSize`.
--- @field fill boolean True stretches every child to the padded box.
--- @field autoSize boolean True grows the container to its children.
local Stack = Widgets.class("Stack")

--- Creates a new `Stack` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional overlay behaviour.
--- @field opts.padding number|nil Inner inset, defaults to 0.
--- @field opts.fill boolean|nil True stretches every child to the padded box.
--- @field opts.autoSize boolean|nil True grows the container to its children.
--- @return PallidStack stack New stack container.
function Stack.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, Stack)
    self:init(x, y, w, h)
    self.padding = math.max(0, opts.padding or 0)
    self.fill = opts.fill == true
    self.autoSize = opts.autoSize == true
    return self
end

--- Factory shortcut for `Stack.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional overlay behaviour; see `Stack.new`.
--- @return PallidStack stack New stack container.
function Widgets.stack(x, y, w, h, opts)
    return Stack.new(x, y, w, h, opts)
end

--- Adds a child and applies the stack layout.
--- @param child PallidWidget Widget to attach.
--- @return PallidWidget child The same widget, for chaining.
function Stack:add(child)
    Widgets.Widget.add(self, child)
    self:layout()
    return child
end

--- Detaches a child and refreshes an auto-sized box.
--- @param child PallidWidget Widget to detach.
function Stack:remove(child)
    Widgets.Widget.remove(self, child)
    self:layout()
end

--- Resizes the stack and re-runs the layout.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidStack self For chaining.
function Stack:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:layout()
    return self
end

--- Applies fill or auto-size behaviour to the children.
function Stack:layout()
    local list = self.children
    if list == nil then
        return
    end
    local padding = self.padding

    if self.fill then
        local width = math.max(0, self.w - padding * 2)
        local height = math.max(0, self.h - padding * 2)
        for i = 1, #list do
            list[i]:setBounds(padding, padding, width, height)
        end
    end

    if self.autoSize then
        local maxX, maxY = 0, 0
        for i = 1, #list do
            local child = list[i]
            local x = child.x + child.w
            local y = child.y + child.h
            if x > maxX then
                maxX = x
            end
            if y > maxY then
                maxY = y
            end
        end
        self.w = maxX + padding
        self.h = maxY + padding
    end
end
