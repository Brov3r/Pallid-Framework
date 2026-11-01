require "pallid/ui/internal"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Invisible flexible gap. In a VBox/HBox it takes the leftover space in
--- proportion to `weight`, pushing the neighbours apart.
--- @class PallidSpacer : PallidWidget
--- @field weight number Relative share of the leftover space; clamped to >= 0.
local Spacer = Widgets.class("Spacer")

--- Creates a new `Spacer` instance.
--- @param weight number|nil Relative share of the leftover space, defaults to 1.
--- @return PallidSpacer spacer New spacer instance.
function Spacer.new(weight)
    local self = setmetatable({}, Spacer)
    self:init(0, 0, 0, 0)
    self.weight = math.max(0, weight or 1)
    -- The spacer is invisible and must never block hover after a layout pass.
    self.hittable = false
    return self
end

--- Factory shortcut for `Spacer.new`.
--- @param weight number|nil Relative share of the leftover space, defaults to 1.
--- @return PallidSpacer spacer New spacer instance.
function Widgets.spacer(weight)
    return Spacer.new(weight)
end
