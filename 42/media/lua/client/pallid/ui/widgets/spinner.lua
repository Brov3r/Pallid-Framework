require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local TAU = math.pi * 2

--- Indeterminate loading spinner. The arc phase advances in `onAnimate`, so the
--- rotation is frame-rate independent and costs one number per frame. There is
--- no fractional progress value: use ProgressBar for determinate work.
--- @class PallidSpinner : PallidWidget
--- @field size number Outer diameter in pixels.
--- @field thickness number Ring thickness in pixels.
--- @field color PallidColor Arc colour.
--- @field track PallidColor|nil Full-circle track colour; nil draws no track.
--- @field speed number Turns per second.
--- @field arc number Visible arc fraction, 0.05..1.
--- @field phase number Current rotation, 0..1.
local Spinner = Widgets.class("Spinner")

--- Creates a new `Spinner` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param size number Outer diameter in pixels.
--- @param opts table|nil Appearance and motion.
--- @field opts.thickness number|nil Ring thickness, defaults to 12% of the size.
--- @field opts.color PallidColor|nil Arc colour, defaults to the primary accent.
--- @field opts.track PallidColor|nil Track colour; nil draws no track.
--- @field opts.speed number|nil Turns per second, defaults to 1.1.
--- @field opts.arc number|nil Visible arc fraction, defaults to 0.3.
--- @return PallidSpinner spinner New spinner.
function Spinner.new(x, y, size, opts)
    opts = opts or {}
    local self = setmetatable({}, Spinner)
    size = math.max(4, size or 16)
    self:init(x, y, size, size)
    self.size = size
    self.thickness = math.max(1, opts.thickness or math.max(2, math.floor(size * 0.12)))
    self.color = opts.color or Pallid.UI.Color.primary
    self.track = opts.track
    self.speed = opts.speed or 1.1
    self.arc = math.max(0.05, math.min(1, opts.arc or 0.3))
    self.phase = 0
    return self
end

--- Factory shortcut for `Spinner.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param size number Outer diameter in pixels.
--- @param opts table|nil Appearance and motion; see `Spinner.new`.
--- @return PallidSpinner spinner New spinner.
function Widgets.spinner(x, y, size, opts)
    return Spinner.new(x, y, size, opts)
end

--- Advances the rotation phase. No tables are created.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function Spinner:onAnimate(now, dt)
    local phase = self.phase + self.speed * dt
    if phase >= 1 then
        phase = phase - math.floor(phase)
    end
    self.phase = phase
end

--- Paints the track and the rotating arc.
--- @param el ISUIElement Host element the tree is rendered into.
function Spinner:drawSelf(el)
    local x, y = self:originX(), self:originY()
    local radius = self.size * 0.5
    local cx = x + radius
    local cy = y + radius
    local innerRadius = math.max(1, radius - self.thickness * 0.5)

    if self.track ~= nil then
        Pallid.UI.ring(el, cx, cy, innerRadius, self.thickness, self:shade(self.track), 0, TAU)
    end

    local startAngle = self.phase * TAU
    Pallid.UI.ring(
        el,
        cx,
        cy,
        innerRadius,
        self.thickness,
        self:shade(self.color),
        startAngle,
        startAngle + self.arc * TAU
    )
end
