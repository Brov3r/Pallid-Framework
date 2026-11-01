require "pallid/ui/internal"
require "pallid/ui/animation/track"
require "pallid/ui/api/color"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Anim = Pallid.UI.Anim

--- Ready-made tracks for the common UI cases. Each one is a normal
--- PallidAnimTrack, so channels, loop and onComplete can still be changed
--- before the first play().
---
--- Names ending in "In" start at the pre-animation state, "Out" start at the
--- resting state and end hidden. Looping presets never finish on their own.

-- Entrance ------------------------------------------------------------------

--- Fades in from transparent to opaque.
--- @param duration number|nil Seconds per pass; nil uses the preset default.
--- @param delay number|nil Seconds before the first pass.
--- @param easing fun(t: number): number|nil
--- @return PallidAnimTrack New track prepared for this preset.
function Anim.fade(duration, delay, easing)
    return Anim.new({
        duration = duration,
        delay    = delay,
        easing   = easing or Anim.ease.outCubic,
        alpha    = { 0, 1 },
    })
end

--- Fades out to fully transparent.
--- @param duration number|nil Seconds per pass; nil uses the preset default.
--- @param delay number|nil Seconds before the first pass.
--- @return PallidAnimTrack New track prepared for this preset.
function Anim.fadeOut(duration, delay)
    return Anim.new({
        duration = duration,
        delay    = delay,
        easing   = Anim.ease.inCubic,
        alpha    = { 1, 0 },
    })
end

--- Fades in while growing slightly; overshoots with outBack.
--- @param duration number|nil Seconds per pass; nil uses the preset default.
--- @param delay number|nil Seconds before the first pass.
--- @return PallidAnimTrack New track prepared for this preset.
function Anim.pop(duration, delay)
    return Anim.new({
        duration = duration or 0.28,
        delay    = delay,
        easing   = Anim.ease.outBack,
        alpha    = { 0, 1 },
        scale    = { 0.85, 1 },
    })
end

--- Slightly grows and fades out.
--- @param duration number|nil Seconds per pass; nil uses the preset default.
--- @param delay number|nil Seconds before the first pass.
--- @return PallidAnimTrack New track prepared for this preset.
function Anim.popOut(duration, delay)
    return Anim.new({
        duration = duration or 0.2,
        delay    = delay,
        easing   = Anim.ease.inCubic,
        alpha    = { 1, 0 },
        scale    = { 1, 1.08 },
    })
end

--- Scales up from `fromScale` with a fade.
--- @param duration number|nil Seconds per pass; nil uses the preset default.
--- @param delay number|nil Seconds before the first pass.
--- @param fromScale number|nil Defaults to 0.6.
--- @return PallidAnimTrack New track prepared for this preset.
function Anim.zoomIn(duration, delay, fromScale)
    return Anim.new({
        duration = duration or 0.24,
        delay    = delay,
        easing   = Anim.ease.outCubic,
        alpha    = { 0, 1 },
        scale    = { fromScale or 0.6, 1 },
    })
end

--- Drops in from above with a slight overshoot.
--- @param duration number|nil Seconds per pass; nil uses the preset default.
--- @param delay number|nil Seconds before the first pass.
--- @param distance number|nil Start offset in pixels. Defaults to 16.
--- @return PallidAnimTrack New track prepared for this preset.
function Anim.dropIn(duration, delay, distance)
    return Anim.new({
        duration = duration or 0.35,
        delay    = delay,
        easing   = Anim.ease.outBack,
        alpha    = { 0, 1 },
        scale    = { 0.9, 1 },
        dy       = { -(distance or 16), 0 },
    })
end

--- Scales up with a bounce.
--- @param duration number|nil Seconds per pass; nil uses the preset default.
--- @param delay number|nil Seconds before the first pass.
--- @return PallidAnimTrack New track prepared for this preset.
function Anim.bounceIn(duration, delay)
    return Anim.new({
        duration = duration or 0.5,
        delay    = delay,
        easing   = Anim.ease.outBounce,
        alpha    = { 0, 1 },
        scale    = { 0.3, 1 },
    })
end

--- Fades in while straightening from a small rotation.
--- @param duration number|nil Seconds per pass; nil uses the preset default.
--- @param delay number|nil Seconds before the first pass.
--- @param degrees number|nil Start rotation. Defaults to 8.
--- @return PallidAnimTrack New track prepared for this preset.
function Anim.wobbleIn(duration, delay, degrees)
    local angle = degrees or 8
    return Anim.new({
        duration = duration or 0.4,
        delay    = delay,
        easing   = Anim.ease.outBack,
        alpha    = { 0, 1 },
        rotation = { -angle, 0 },
    })
end

--- Fades in while moving from (dx, dy) back to the resting position.
--- @param duration number|nil Seconds per pass; nil uses the preset default.
--- @param dx number|nil Horizontal start offset in pixels.
--- @param dy number|nil Vertical start offset in pixels.
--- @param delay number|nil Seconds before the first pass.
--- @return PallidAnimTrack New track prepared for this preset.
function Anim.slide(duration, dx, dy, delay)
    return Anim.new({
        duration = duration or 0.3,
        delay    = delay,
        easing   = Anim.ease.outCubic,
        alpha    = { 0, 1 },
        dx       = { dx or 0, 0 },
        dy       = { dy or 0, 0 },
    })
end

--- Moves out by (dx, dy) while fading.
--- @param duration number|nil Seconds per pass; nil uses the preset default.
--- @param dx number|nil Horizontal start offset in pixels.
--- @param dy number|nil Vertical start offset in pixels.
--- @param delay number|nil Seconds before the first pass.
--- @return PallidAnimTrack New track prepared for this preset.
function Anim.slideOut(duration, dx, dy, delay)
    return Anim.new({
        duration = duration or 0.22,
        delay    = delay,
        easing   = Anim.ease.inCubic,
        alpha    = { 1, 0 },
        dx       = { 0, dx or 0 },
        dy       = { 0, dy or 0 },
    })
end

-- Looping -------------------------------------------------------------------

--- Looping breathing alpha. Never finishes on its own.
--- @param duration number|nil Seconds for one direction.
--- @param minAlpha number|nil Lowest alpha. Defaults to 0.4.
--- @return PallidAnimTrack New track prepared for this preset.
function Anim.pulse(duration, minAlpha)
    return Anim.new({
        duration = duration or 0.9,
        easing   = Anim.ease.inOutSine,
        loop     = true,
        pingPong = true,
        alpha    = { 1, minAlpha or 0.4 },
    })
end

--- Looping scale breathing.
--- @param duration number|nil Seconds for one direction.
--- @param maxScale number|nil Peak scale. Defaults to 1.05.
--- @return PallidAnimTrack New track prepared for this preset.
function Anim.breathe(duration, maxScale)
    return Anim.new({
        duration = duration or 1.2,
        easing   = Anim.ease.inOutSine,
        loop     = true,
        pingPong = true,
        scale    = { 1, maxScale or 1.05 },
    })
end

--- Looping on/off blink.
--- @param duration number|nil Seconds for one direction.
--- @param minAlpha number|nil Lowest alpha. Defaults to 0.
--- @return PallidAnimTrack New track prepared for this preset.
function Anim.blink(duration, minAlpha)
    return Anim.new({
        duration = duration or 0.5,
        easing   = Anim.ease.inQuad,
        loop     = true,
        pingPong = true,
        alpha    = { 1, minAlpha or 0 },
    })
end

--- Looping steady rotation in degrees.
--- @param duration number|nil Seconds per full turn.
--- @return PallidAnimTrack New track prepared for this preset.
function Anim.spin(duration)
    return Anim.new({
        duration = duration or 4,
        easing   = Anim.ease.linear,
        loop     = true,
        rotation = { 0, 360 },
    })
end

--- Looping left/right rotation around the center.
--- @param duration number|nil Seconds for one direction.
--- @param degrees number|nil Amplitude. Defaults to 4.
--- @return PallidAnimTrack New track prepared for this preset.
function Anim.wobble(duration, degrees)
    local angle = degrees or 4
    return Anim.new({
        duration = duration or 0.35,
        easing   = Anim.ease.inOutSine,
        loop     = true,
        pingPong = true,
        rotation = { -angle, angle },
    })
end

--- Looping vertical drift.
--- @param duration number|nil Seconds for one direction.
--- @param distance number|nil Distance in pixels. Defaults to 4.
--- @return PallidAnimTrack New track prepared for this preset.
function Anim.float(duration, distance)
    local offset = distance or 4
    return Anim.new({
        duration = duration or 1.4,
        easing   = Anim.ease.inOutSine,
        loop     = true,
        pingPong = true,
        dy       = { 0, -offset },
    })
end

--- Looping color interpolation between two colors.
--- @param duration number|nil Seconds for one direction.
--- @param from PallidColor|nil Defaults to Color.accent.
--- @param to PallidColor|nil Defaults to Color.white.
--- @return PallidAnimTrack New track prepared for this preset.
function Anim.colorPulse(duration, from, to)
    return Anim.new({
        duration = duration or 1.1,
        easing   = Anim.ease.inOutSine,
        loop     = true,
        pingPong = true,
        color    = {
            from = from or Pallid.UI.Color.accent,
            to   = to or Pallid.UI.Color.white,
        },
    })
end

-- Attention ----------------------------------------------------------------

--- Horizontal shake that ends where it started.
--- With the default 4 swings the track runs 8 half-passes and then finishes.
--- @param amplitude number|nil Pixels. Defaults to 4.
--- @param swings number|nil Full left-right swings. Defaults to 4.
--- @param swingTime number|nil Seconds per half-pass. Defaults to 0.06.
--- @return PallidAnimTrack New track prepared for this preset.
function Anim.shake(amplitude, swings, swingTime)
    return Anim.new({
        duration = swingTime or 0.06,
        easing   = Anim.ease.linear,
        loop     = (swings or 4) * 2,
        pingPong = true,
        dx       = { 0, amplitude or 4 },
    })
end
