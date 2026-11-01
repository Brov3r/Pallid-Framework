require "pallid/ui/internal"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local PI = math.pi
local cos, sin = math.cos, math.sin
local sqrt = math.sqrt

Pallid.UI.Anim = Pallid.UI.Anim or {}
local Anim = Pallid.UI.Anim

--- Easing functions. Every entry takes normalized time 0..1 and returns an
--- eased value; back/elastic intentionally overshoot outside 0..1.
--- The table is a plain function map: Ease.outCubic(t), Ease.inOutSine(t), ...
--- @class PallidAnimEase Table of easing functions keyed by name.
local Ease = {}
Anim.ease = Ease

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function linear(t)
    return t
end
Ease.linear = linear

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function inQuad(t)
    return t * t
end
Ease.inQuad = inQuad

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function outQuad(t)
    return t * (2 - t)
end
Ease.outQuad = outQuad

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function inOutQuad(t)
    if t < 0.5 then
        return 2 * t * t
    end
    local f = -2 * t + 2
    return 1 - f * f * 0.5
end
Ease.inOutQuad = inOutQuad

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function inCubic(t)
    return t * t * t
end
Ease.inCubic = inCubic

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function outCubic(t)
    local f = 1 - t
    return 1 - f * f * f
end
Ease.outCubic = outCubic

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function inOutCubic(t)
    if t < 0.5 then
        return 4 * t * t * t
    end
    local f = -2 * t + 2
    return 1 - f * f * f * 0.5
end
Ease.inOutCubic = inOutCubic

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function inQuart(t)
    return t * t * t * t
end
Ease.inQuart = inQuart

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function outQuart(t)
    local f = 1 - t
    return 1 - f * f * f * f
end
Ease.outQuart = outQuart

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function inOutQuart(t)
    if t < 0.5 then
        return 8 * t * t * t * t
    end
    local f = -2 * t + 2
    return 1 - f * f * f * f * 0.5
end
Ease.inOutQuart = inOutQuart

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function inSine(t)
    return 1 - cos(t * PI * 0.5)
end
Ease.inSine = inSine

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function outSine(t)
    return sin(t * PI * 0.5)
end
Ease.outSine = outSine

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function inOutSine(t)
    return -(cos(PI * t) - 1) * 0.5
end
Ease.inOutSine = inOutSine

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function inExpo(t)
    if t <= 0 then
        return 0
    end
    return 2 ^ (10 * t - 10)
end
Ease.inExpo = inExpo

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function outExpo(t)
    if t >= 1 then
        return 1
    end
    return 1 - 2 ^ (-10 * t)
end
Ease.outExpo = outExpo

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function inOutExpo(t)
    if t <= 0 then
        return 0
    end
    if t >= 1 then
        return 1
    end
    if t < 0.5 then
        return 2 ^ (20 * t - 10) * 0.5
    end
    return (2 - 2 ^ (-20 * t + 10)) * 0.5
end
Ease.inOutExpo = inOutExpo

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function inCirc(t)
    return 1 - sqrt(1 - t * t)
end
Ease.inCirc = inCirc

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function outCirc(t)
    local f = t - 1
    return sqrt(1 - f * f)
end
Ease.outCirc = outCirc

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function inOutCirc(t)
    if t < 0.5 then
        return (1 - sqrt(1 - 4 * t * t)) * 0.5
    end
    local f = -2 * t + 2
    return (sqrt(1 - f * f) + 1) * 0.5
end
Ease.inOutCirc = inOutCirc

local BACK = 1.70158
local BACK2 = BACK * 1.525

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function inBack(t)
    local c3 = BACK + 1
    return c3 * t * t * t - BACK * t * t
end
Ease.inBack = inBack

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function outBack(t)
    local f = t - 1
    local c3 = BACK + 1
    return 1 + c3 * f * f * f + BACK * f * f
end
Ease.outBack = outBack

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function inOutBack(t)
    if t < 0.5 then
        local f = 2 * t
        return f * f * ((BACK2 + 1) * f - BACK2) * 0.5
    end
    local f = 2 * t - 2
    return (f * f * ((BACK2 + 1) * f + BACK2) + 2) * 0.5
end
Ease.inOutBack = inOutBack

local ELASTIC = PI * 2 / 3

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function inElastic(t)
    if t <= 0 then
        return 0
    end
    if t >= 1 then
        return 1
    end
    return -2 ^ (10 * t - 10) * sin((10 * t - 10.75) * ELASTIC)
end
Ease.inElastic = inElastic

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function outElastic(t)
    if t <= 0 then
        return 0
    end
    if t >= 1 then
        return 1
    end
    return 2 ^ (-10 * t) * sin((10 * t - 0.75) * ELASTIC) + 1
end
Ease.outElastic = outElastic

local BOUNCE_N = 7.5625
local BOUNCE_D = 2.75

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function outBounce(t)
    if t < 1 / BOUNCE_D then
        return BOUNCE_N * t * t
    end
    if t < 2 / BOUNCE_D then
        local f = t - 1.5 / BOUNCE_D
        return BOUNCE_N * f * f + 0.75
    end
    if t < 2.5 / BOUNCE_D then
        local f = t - 2.25 / BOUNCE_D
        return BOUNCE_N * f * f + 0.9375
    end
    local f = t - 2.625 / BOUNCE_D
    return BOUNCE_N * f * f + 0.984375
end
Ease.outBounce = outBounce

--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function inBounce(t)
    return 1 - outBounce(1 - t)
end
Ease.inBounce = inBounce

--- Hermite smoothstep: zero slope at both ends.
--- @param t number Normalized time, 0..1.
--- @return number Eased value for the normalized time.
local function smoothstep(t)
    return t * t * (3 - 2 * t)
end
Ease.smoothstep = smoothstep
