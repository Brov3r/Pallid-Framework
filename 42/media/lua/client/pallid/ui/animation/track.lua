require "pallid/ui/internal"
require "pallid/ui/animation/ease"
require "pallid/ui/animation/util"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Anim = Pallid.UI.Anim

local EMPTY = {}

--- Time-based track. One easing drives all configured channels, so a single
--- update computes up to five values with no allocations and no closures.
---
--- Channel ranges are plain number pairs supplied at construction; they are
--- copied out of the options table, which may be discarded afterwards.
--- @class PallidAnimTrack Time-based animation track driven by one easing.
--- @field value number Eased progress 0..1 (back/elastic may overshoot).
--- @field alpha number Current alpha.
--- @field scale number Current scale.
--- @field dx number Current X offset in pixels.
--- @field dy number Current Y offset in pixels.
--- @field rotation number Current rotation in degrees.
--- @field number number Numeric channel, valid when opts.value was supplied.
--- @field color PallidColor Table owned by the track, valid when opts.color was supplied.
--- @field duration number Seconds per pass.
--- @field delay number Seconds before the first pass.
--- @field speed number Multiplier on elapsed time.
--- @field easing fun(t: number): number Easing applied to every pass.
--- @field loop boolean|integer True for endless playback, a number for that many passes.
--- @field pingPong boolean Reverse direction on every other pass.
--- @field reverse boolean Play from 1 to 0 instead of 0 to 1.
--- @field startAt number|nil Absolute start time; nil while the track is stopped.
--- @field finished boolean True once the last pass has been reached.
--- @field done boolean True after onComplete has fired at least once.
--- @field onComplete fun(track: PallidAnimTrack)|nil Called once, when finished.
--- @field alphaFrom number|nil Channel start value, nil when the channel is unused.
--- @field alphaTo number|nil Channel end value, nil when the channel is unused.
--- @field scaleFrom number|nil Start scale for the tween.
--- @field scaleTo number|nil End scale for the tween.
--- @field dxFrom number|nil Start X offset for the tween.
--- @field dxTo number|nil End X offset for the tween.
--- @field dyFrom number|nil Start Y offset for the tween.
--- @field dyTo number|nil End Y offset for the tween.
--- @field rotationFrom number|nil Start rotation in radians.
--- @field rotationTo number|nil End rotation in radians.
--- @field numberFrom number|nil Start numeric value for the tween.
--- @field numberTo number|nil End numeric value for the tween.
--- @field colorFrom PallidColor|nil Source color, nil when the channel is unused.
--- @field colorTo PallidColor|nil Target color, nil when the channel is unused.
local Track = {}
Track.__index = Track
Anim.Track = Track

--- @class PallidAnimOpts Options accepted by Pallid.UI.Anim.new.
--- @field duration number|nil Seconds per pass. Defaults to 0.25; 0 is treated as 0.25.
--- @field delay number|nil Seconds before the first pass. Defaults to 0.
--- @field easing fun(t: number): number|nil Defaults to Anim.ease.outQuad.
--- @field loop boolean|integer|nil true loops forever, a number runs that many passes.
--- @field pingPong boolean|nil Reverse direction on every other pass.
--- @field reverse boolean|nil Play from 1 to 0 instead of 0 to 1.
--- @field speed number|nil Multiplier on elapsed time. Defaults to 1.
--- @field alpha number[]|nil {from, to} pair in 0..1.
--- @field scale number[]|nil {from, to} pair.
--- @field dx number[]|nil {from, to} pair in pixels.
--- @field dy number[]|nil {from, to} pair in pixels.
--- @field rotation number[]|nil {from, to} pair in degrees.
--- @field value number[]|nil {from, to} pair exposed as track.number.
--- @field color { from: PallidColor, to: PallidColor }|nil Exposed as track.color.
--- @field onComplete fun(track: PallidAnimTrack)|nil

--- Creates a track. Nothing is allocated after this call.
--- @param opts PallidAnimOpts|nil Track options; copied and may be discarded.
--- @return PallidAnimTrack New track.
function Anim.new(opts)
    opts = opts or EMPTY

    local self = setmetatable({}, Track)

    self.duration = opts.duration or 0.25
    if self.duration <= 0 then
        self.duration = 0.25
    end
    self.delay = opts.delay or 0
    self.speed = opts.speed or 1
    self.easing = opts.easing or Anim.ease.outQuad
    self.loop = opts.loop or false
    self.pingPong = opts.pingPong or false
    self.reverse = opts.reverse or false
    self.onComplete = opts.onComplete

    self.value = 0
    self.finished = false
    self.done = false
    self.startAt = nil

    self.alpha = 1
    self.scale = 1
    self.dx = 0
    self.dy = 0
    self.rotation = 0

    local alpha = opts.alpha
    if alpha ~= nil then
        self.alphaFrom, self.alphaTo = alpha[1] or 1, alpha[2] or 1
        self.alpha = self.alphaFrom
    end
    local scale = opts.scale
    if scale ~= nil then
        self.scaleFrom, self.scaleTo = scale[1] or 1, scale[2] or 1
        self.scale = self.scaleFrom
    end
    local dx = opts.dx
    if dx ~= nil then
        self.dxFrom, self.dxTo = dx[1] or 0, dx[2] or 0
        self.dx = self.dxFrom
    end
    local dy = opts.dy
    if dy ~= nil then
        self.dyFrom, self.dyTo = dy[1] or 0, dy[2] or 0
        self.dy = self.dyFrom
    end
    local rotation = opts.rotation
    if rotation ~= nil then
        self.rotationFrom, self.rotationTo = rotation[1] or 0, rotation[2] or 0
        self.rotation = self.rotationFrom
    end

    local value = opts.value
    if value ~= nil then
        self.numberFrom, self.numberTo = value[1] or 0, value[2] or 0
        self.number = self.numberFrom
    end

    local color = opts.color
    if color ~= nil and color.from ~= nil and color.to ~= nil then
        self.colorFrom, self.colorTo = color.from, color.to
        local from = color.from
        self.color = {
            r = from.r or 1,
            g = from.g or 1,
            b = from.b or 1,
            a = from.a or 1,
        }
    end

    return self
end

--- Writes every configured channel for a 0..1 eased progress value.
--- @param progress number Eased progress, 0..1.
function Track:_apply(progress)
    if self.alphaFrom ~= nil then
        self.alpha = self.alphaFrom + (self.alphaTo - self.alphaFrom) * progress
    end
    if self.scaleFrom ~= nil then
        self.scale = self.scaleFrom + (self.scaleTo - self.scaleFrom) * progress
    end
    if self.dxFrom ~= nil then
        self.dx = self.dxFrom + (self.dxTo - self.dxFrom) * progress
    end
    if self.dyFrom ~= nil then
        self.dy = self.dyFrom + (self.dyTo - self.dyFrom) * progress
    end
    if self.rotationFrom ~= nil then
        self.rotation = self.rotationFrom + (self.rotationTo - self.rotationFrom) * progress
    end
    if self.numberFrom ~= nil then
        self.number = self.numberFrom + (self.numberTo - self.numberFrom) * progress
    end
    if self.colorFrom ~= nil then
        Anim.lerpColor(self.color, self.colorFrom, self.colorTo, progress)
    end
end

--- Starts the track. Safe to call again to restart.
--- @param now number|nil Seconds from Anim.now().
--- @return PallidAnimTrack self The same instance, for chaining.
function Track:play(now)
    self.startAt = (now or Anim.now()) + self.delay
    self.done = false
    self.finished = false
    -- A reversed track starts from the end of the curve, so the first frame
    -- between play() and update() already shows the correct state.
    local start = self.reverse and 1 or 0
    self.value = start
    self:_apply(start)
    return self
end

--- Freezes the track where it is.
function Track:stop()
    self.startAt = nil
end

--- Returns true while the track is running.
--- @return boolean True while the track is started and not finished.
function Track:isPlaying()
    return self.startAt ~= nil and not self.finished
end

--- Recomputes the channels for the given time. Pass the frame timestamp once
--- per render pass; without it every call reads the Java clock.
--- @param now number|nil Current time in seconds; nil reads the clock.
--- @return PallidAnimTrack self The same instance, for chaining.
function Track:update(now)
    if self.startAt == nil then
        return self
    end

    local elapsed = ((now or Anim.now()) - self.startAt) * self.speed
    local t = 0
    if elapsed > 0 then
        t = elapsed / self.duration
    end

    local limit
    if self.loop == true then
        limit = nil
    elseif self.loop then
        limit = self.loop
    else
        limit = self.pingPong and 2 or 1
    end

    local finished = false
    if limit ~= nil and t >= limit then
        t = limit
        finished = true
    end

    local phase
    if self.pingPong then
        local cycle = t % 2
        phase = cycle <= 1 and cycle or 2 - cycle
    elseif finished then
        phase = 1
    else
        phase = t % 1
    end

    if self.reverse then
        phase = 1 - phase
    end

    local value = self.easing(phase)
    self.value = value
    self:_apply(value)

    if finished then
        self.finished = true
        if not self.done then
            self.done = true
            if self.onComplete ~= nil then
                self.onComplete(self)
            end
        end
    else
        self.finished = false
    end

    return self
end
