require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/clip"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local RECT_SHAPE = Pallid.UI.Shape.rect()
local TAU = math.pi * 2

--- Placeholder skeleton for loading content: a set of rounded bars with an
--- optional moving highlight and a pulse. Nothing is allocated while drawing;
--- the pulse and shimmer phases are advanced in `onAnimate`.
--- @class PallidSkeleton : PallidWidget
--- @field lines integer Number of bars.
--- @field lineHeight number Height of one bar in pixels.
--- @field gap number Vertical gap between bars in pixels.
--- @field radius number Bar corner radius.
--- @field color PallidColor Bar colour (alpha is modulated by the pulse).
--- @field animated boolean True draws the shimmer and pulse.
--- @field phase number Shimmer position, 0..1.
local Skeleton = Widgets.class("Skeleton")

--- Creates a new `Skeleton` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Appearance.
--- @field opts.lines integer|nil Number of bars, defaults to 3.
--- @field opts.lineHeight number|nil Bar height; nil splits the height evenly.
--- @field opts.gap number|nil Gap between bars, defaults to 6.
--- @field opts.radius number|nil Bar radius, defaults to 4.
--- @field opts.color PallidColor|nil Bar colour, defaults to surfaceMuted.
--- @field opts.animated boolean|nil False keeps the bars static.
--- @return PallidSkeleton skeleton New skeleton placeholder.
function Skeleton.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, Skeleton)
    self:init(x, y, w or 0, h or 0)

    self.lines = math.max(1, math.floor(opts.lines or 3))
    self.gap = math.max(0, opts.gap or 6)
    self.lineHeight = math.max(
        2,
        math.floor(opts.lineHeight or ((h or 0) - self.gap * (self.lines - 1)) / self.lines)
    )
    self.radius = math.max(0, opts.radius or 4)
    self.animated = opts.animated ~= false
    self.phase = 0
    self.pulse = 1

    local color = opts.color or Pallid.UI.Color.surfaceMuted
    self.color = { r = color.r, g = color.g, b = color.b, a = color.a or 1 }
    self._baseAlpha = color.a or 1
    self._shimmer = { r = 1, g = 1, b = 1, a = 0.09 }
    return self
end

--- Factory shortcut for `Skeleton.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Appearance; see `Skeleton.new`.
--- @return PallidSkeleton skeleton New skeleton placeholder.
function Widgets.skeleton(x, y, w, h, opts)
    return Skeleton.new(x, y, w, h, opts)
end

--- Advances the shimmer and pulse. No tables are created.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function Skeleton:onAnimate(now, dt)
    if not self.animated then
        return
    end
    local phase = self.phase + dt * 0.35
    if phase >= 1 then
        phase = phase - math.floor(phase)
    end
    self.phase = phase
    self.pulse = 0.62 + 0.38 * (0.5 + 0.5 * math.sin(now * 2.4))
end

--- Returns the width of a skeleton bar. The last bar is shortened so the
--- placeholder reads as a paragraph.
--- @param index integer One-based bar index.
--- @return number width Bar width in pixels.
function Skeleton:_barWidth(index)
    if index == self.lines and self.lines > 1 then
        return math.max(1, self.w * 0.62)
    end
    return self.w
end

--- Paints the bars and the clipped shimmer.
--- @param el ISUIElement Host element the tree is rendered into.
function Skeleton:drawSelf(el)
    if self.w <= 0 or self.h <= 0 then
        return
    end
    local x, y = self:originX(), self:originY()
    local color = self.color
    local base = self._baseAlpha
    color.a = self.animated and base * self.pulse or base

    local barH = self.lineHeight
    local gap = self.gap
    local radius = self.radius
    for i = 1, self.lines do
        local barY = y + (i - 1) * (barH + gap)
        if barY >= y + self.h then
            break
        end
        local height = math.min(barH, y + self.h - barY)
        if height > 0 then
            Pallid.UI.roundedRect(el, x, barY, self:_barWidth(i), height, radius, self:shade(color))
        end
    end

    if not self.animated then
        return
    end

    local entered = Pallid.UI.clip(el, RECT_SHAPE, x, y, self.w, self.h)
    if not entered then
        return
    end

    local bandW = math.max(16, self.w * 0.28)
    local bandX = x - bandW + (self.w + bandW * 2) * self.phase
    local bandRight = bandX + bandW

    -- Clip the shimmer to every bar, not just to the widget box. Otherwise the
    -- band paints the gaps between bars and the empty tail of the shortened
    -- last bar, which reads as a clipped-out rectangle.
    for i = 1, self.lines do
        local barY = y + (i - 1) * (barH + gap)
        if barY >= y + self.h then
            break
        end
        local height = math.min(barH, y + self.h - barY)
        local barW = self:_barWidth(i)
        local left = bandX > x and bandX or x
        local right = bandRight < x + barW and bandRight or (x + barW)
        if height > 0 and right > left then
            local shimmerRadius = math.min(radius, (right - left) * 0.5)
            Pallid.UI.roundedRect(el, left, barY, right - left, height, shimmerRadius, self:shade(self._shimmer))
        end
    end

    Pallid.UI.clipEnd(el)
end
