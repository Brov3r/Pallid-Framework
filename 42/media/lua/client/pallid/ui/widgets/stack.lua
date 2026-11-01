require "pallid/ui/internal"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Invisible z-order container. Children keep their own bounds; the first child
--- is drawn first, so later children sit on top (for example an icon over a
--- picture). Unlike a panel it has no visuals and never moves or resizes its
--- children.
--- @class PallidStack : PallidWidget
local Stack = Widgets.class("Stack")

--- Creates a new `Stack` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @return PallidStack stack New stack container.
function Stack.new(x, y, w, h)
    local self = setmetatable({}, Stack)
    self:init(x, y, w, h)
    return self
end

--- Factory shortcut for `Stack.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @return PallidStack stack New stack container.
function Widgets.stack(x, y, w, h)
    return Stack.new(x, y, w, h)
end
