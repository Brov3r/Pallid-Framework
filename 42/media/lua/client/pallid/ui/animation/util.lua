require "pallid/ui/internal"
require "pallid/ui/animation/ease"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local I = Pallid.UI._internal
local Anim = Pallid.UI.Anim
local sin, cos = math.sin, math.cos

--- Current time in seconds. Every call crosses into Java, so read it once per
--- frame and pass the value to track:update(now).
--- @return number Current time in seconds.
function Anim.now()
    return getTimestampMs() * 0.001
end

--- Linearly interpolates two numbers.
--- @param a number Alpha multiplier, 0..1.
--- @param b number Blue component, 0..1.
--- @param t number Interpolation factor, 0..1.
--- @return number Interpolated value.
function Anim.lerp(a, b, t)
    return a + (b - a) * t
end

--- Clamps a value into the inclusive range [lo, hi]. Kept as a public alias of
--- the shared UI helper so existing callers keep working.
--- @param value number Value to clamp.
--- @param lo number Lower bound.
--- @param hi number Upper bound.
--- @return number Computed value.
Anim.clamp = I.clamp
local clamp = Anim.clamp

--- Writes the interpolation of two colors into `out`, so callers can keep one
--- table per tween and never allocate during a frame.
--- @param out PallidColor Destination table.
--- @param a PallidColor Color at t = 0.
--- @param b PallidColor Color at t = 1.
--- @param t number Interpolation factor, 0..1.
function Anim.lerpColor(out, a, b, t)
    out.r = clamp(a.r + (b.r - a.r) * t, 0, 1)
    out.g = clamp(a.g + (b.g - a.g) * t, 0, 1)
    out.b = clamp(a.b + (b.b - a.b) * t, 0, 1)
    out.a = clamp(a.a + (b.a - a.a) * t, 0, 1)
end

local ALPHA_SCRATCH = { r = 1, g = 1, b = 1, a = 1 }

--- Returns `color` with its alpha multiplied by `a`, clamped to 0..1.
--- The returned table is shared and overwritten on the next call: pass it
--- directly to a draw call, never store it.
--- @param color PallidColor|nil Base color; nil means white.
--- @param a number Alpha multiplier, 0..1.
--- @return PallidColor Shared scratch table holding the tinted color.
function Anim.alpha(color, a)
    ALPHA_SCRATCH.r = color and color.r or 1
    ALPHA_SCRATCH.g = color and color.g or 1
    ALPHA_SCRATCH.b = color and color.b or 1
    ALPHA_SCRATCH.a = clamp((color and color.a or 1) * (a or 1), 0, 1)
    return ALPHA_SCRATCH
end

--- Scales a box around its center without allocating anything.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param scale number Scale multiplier.
--- @return number x X coordinate.
--- @return number y Y coordinate.
--- @return number w Width in pixels.
--- @return number h Height in pixels.
function Anim.scaleRect(x, y, w, h, scale)
    local grownW = w * scale
    local grownH = h * scale
    return x + (w - grownW) * 0.5, y + (h - grownH) * 0.5, grownW, grownH
end

local TAU = math.pi * 2

--- Time-based shake offset. Stateless, so any track can drive it. The
--- Anim.shake preset is a different function.
--- @param time number Seconds.
--- @param amplitude number Maximum offset in pixels.
--- @param frequency number|nil Oscillations per second. Defaults to 18.
--- @return number dx Horizontal offset.
--- @return number dy Vertical offset.
function Anim.shakeOffset(time, amplitude, frequency)
    local phase = time * (frequency or 18) * TAU
    return sin(phase) * amplitude, cos(phase * 1.37) * amplitude
end

--- Delay for a staggered list: item 1 starts immediately, item 2 after `step`.
--- @param index integer 1-based item index.
--- @param step number Seconds between items.
--- @return number delay Delay in seconds.
function Anim.stagger(index, step)
    return (index - 1) * step
end
