require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/animation/track"
require "pallid/ui/widgets/widget"
local normaliseStep = require "pallid/ui/widgets/stepper/step"
local addInputMethods = require "pallid/ui/widgets/stepper/input"
local addDrawMethods = require "pallid/ui/widgets/stepper/draw"
local OptionUtil = require "pallid/ui/widgets/internal/option_util"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local Textures = Pallid.UI.Textures

local DEFAULT_CIRCLE_SIZE = 28
local MIN_CIRCLE_SIZE = 6
local MAX_CIRCLE_SIZE = 64
local LABEL_GAP = 6
local DEFAULT_CONNECTOR = 2
local DEFAULT_LABEL_MIN_SLOT = 44
local LINE_ANIM_DURATION = 0.24
local ICON_DIR = "media/assets/ui/pallid/icons/"

--- Clamps a value into the given range, falling back to the minimum for non-numbers.
--- @param value number|nil Value to clamp.
--- @param min number Lower bound.
--- @param max number Upper bound.
--- @return number clamped Clamped value.
local function clampNumber(value, min, max)
    if type(value) ~= "number" or value ~= value then
        return min
    end
    return math.max(min, math.min(max, value))
end

--- Horizontal progress stepper: numbered/icon circles joined by lines, with
--- completed, current, future, error and disabled states.
---
--- Steps accept a plain string or a `PallidStep` table. A completed step shows
--- a check mark; the current and future steps show their icon when one is
--- provided, otherwise the step number. The stepper is display-only unless
--- `clickable` is enabled. Advancing past the last available step sets
--- `allComplete`, which renders every step that is not disabled or in error as
--- completed until the user selects a step or goes back. Connectors fill with
--- a short eased animation whenever the active or completed state changes.
--- @class PallidStepper : PallidWidget
--- @field steps PallidStep[] Parsed steps with label, icon and state fields.
--- @field current integer 1-based active step.
--- @field allComplete boolean True when the whole flow is finished; no step is active.
--- @field showLabels boolean True allows labels under the circles.
--- @field autoHideLabels boolean True hides labels when the slot is too narrow.
--- @field labelMinSlot number Minimum slot width before labels are auto-hidden.
--- @field clickable boolean True lets a click select a step.
--- @field connectorThickness number Connector line thickness in pixels.
--- @field hoverIndex integer|nil Step slot under the cursor when clickable.
--- @field onChange fun(stepper: PallidStepper, current: integer, previous: integer)|nil Called after the active step changes.
--- @field onComplete fun(stepper: PallidStepper)|nil Called when the flow becomes complete.
--- @field onStepClick fun(stepper: PallidStepper, index: integer, step: PallidStep)|nil Called after a clickable step is pressed.
--- @field pulse PallidAnimTrack|nil Pulse animation track, or nil.
--- @field transition PallidAnimTrack|nil Step transition track, or nil.
local Stepper = Widgets.class("Stepper")

-- Click handling and painting live in stepper/input.lua / stepper/draw.lua so
-- this file stays focused on state, layout and public setters.
addInputMethods(Stepper)
addDrawMethods(Stepper)

--- Creates a new `Stepper` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels; 0 auto-grows to the row height.
--- @param steps (string|table)[] Strings or `{ label, icon }` step tables.
--- @param opts table|nil Optional layout, colours and behaviour.
--- @field opts.current number|nil Initial 1-based active step, defaults to 1.
--- @field opts.complete boolean|nil True starts in the all-completed state.
--- @field opts.circleSize number|nil Diameter cap, defaults to 28 and clamps to 6..64.
--- @field opts.showLabels boolean|nil True allows labels; defaults to true.
--- @field opts.autoHideLabels boolean|nil False keeps labels even in narrow slots.
--- @field opts.labelMinSlot number|nil Slot width below which labels hide, defaults to 44.
--- @field opts.connectorThickness number|nil Connector thickness, defaults to 2.
--- @field opts.clickable boolean|nil True enables step selection by click.
--- @field opts.font UIFont|string|nil Label font or a Pallid.UI.Fonts key.
--- @field opts.numberFont UIFont|string|nil Number font; defaults to the size-based font.
--- @field opts.activeColor PallidColor|nil Active circle colour, defaults to primaryStrong.
--- @field opts.completedColor PallidColor|nil Completed circle colour, defaults to success.
--- @field opts.futureFill PallidColor|nil Future circle fill, defaults to surfaceMuted.
--- @field opts.futureBorder PallidColor|nil Future ring colour, defaults to border.
--- @field opts.lineColor PallidColor|nil Incomplete connector colour.
--- @field opts.completedLineColor PallidColor|nil Completed connector colour.
--- @field opts.activeLabelColor PallidColor|nil Active label colour.
--- @field opts.completedLabelColor PallidColor|nil Completed label colour.
--- @field opts.futureLabelColor PallidColor|nil Future label colour.
--- @field opts.futureContentColor PallidColor|nil Future icon/number colour; defaults to future label.
--- @field opts.errorColor PallidColor|nil Error circle and label colour.
--- @field opts.hoverColor PallidColor|nil Hover ring colour.
--- @field opts.animated boolean|nil Pulsing halo and pop on step change, defaults to true.
--- @field opts.onChange fun(stepper: PallidStepper, current: integer, previous: integer)|nil Called after the active step changes.
--- @field opts.onComplete fun(stepper: PallidStepper)|nil Called when advancing past the last available step.
--- @field opts.onStepClick fun(stepper: PallidStepper, index: integer, step: PallidStep)|nil Called after a clickable step is pressed.
--- @return PallidStepper stepper New stepper instance.
function Stepper.new(x, y, w, h, steps, opts)
    opts = opts or {}
    local self = setmetatable({}, Stepper)
    self:init(x, y, w, h)

    self.circleSize = clampNumber(opts.circleSize or DEFAULT_CIRCLE_SIZE, MIN_CIRCLE_SIZE, MAX_CIRCLE_SIZE)
    self.showLabels = opts.showLabels ~= false
    self.autoHideLabels = opts.autoHideLabels ~= false
    self.labelMinSlot = math.max(0, opts.labelMinSlot or DEFAULT_LABEL_MIN_SLOT)
    self.connectorThickness = math.max(1, math.floor((opts.connectorThickness or DEFAULT_CONNECTOR) + 0.5))
    self.clickable = opts.clickable == true
    self.onStepClick = opts.onStepClick
    self.onChange = opts.onChange
    self.onComplete = opts.onComplete
    self.current = 1
    self.allComplete = false
    self.hoverIndex = nil
    self._autoHeight = (h or 0) <= 0

    self.activeColor = opts.activeColor or Pallid.UI.Color.primaryStrong
    self.completedColor = opts.completedColor or Pallid.UI.Color.success
    self.futureFill = opts.futureFill or Pallid.UI.Color.surfaceMuted
    self.futureBorder = opts.futureBorder or Pallid.UI.Color.border
    self.lineColor = opts.lineColor or Pallid.UI.Color.border
    self.completedLineColor = opts.completedLineColor
        or Pallid.UI.Color.withAlpha(self.completedColor, 0.55)
    self.errorColor = opts.errorColor or Pallid.UI.Color.error
    self.hoverColor = opts.hoverColor or Pallid.UI.Color.borderStrong
    self.activeContentColor = Pallid.UI.Color.contrastText(self.activeColor)
    self.completedContentColor = Pallid.UI.Color.contrastText(self.completedColor)
    self.errorContentColor = Pallid.UI.Color.contrastText(self.errorColor)
    self.activeLabelColor = opts.activeLabelColor or Pallid.UI.Color.textPrimary
    self.completedLabelColor = opts.completedLabelColor or Pallid.UI.Color.textMuted
    self.futureLabelColor = opts.futureLabelColor or Pallid.UI.Color.textMuted
    self.futureContentColor = opts.futureContentColor or self.futureLabelColor

    self.labelStyle = {
        font = OptionUtil.resolveFont(opts.font),
        color = Pallid.UI.Color.textMuted,
        alignH = "center",
        alignV = "top",
        ellipsis = "...",
    }
    self.numberStyle = {
        font = OptionUtil.resolveFont(opts.numberFont or opts.font),
        color = Pallid.UI.Color.textPrimary,
        alignH = "center",
        alignV = "middle",
        bold = true,
    }
    self._customNumberFont = opts.numberFont ~= nil or opts.font ~= nil
    self._checkRegion = Textures.getRegion(ICON_DIR .. "tick.png")
    self._checkTexture = self._checkRegion == nil and Textures.get(ICON_DIR .. "tick.png") or nil

    self.animated = opts.animated ~= false
    if self.animated then
        self:_createTracks()
        self.pulse:play()
    end

    self.steps = {}
    self._numbers = {}
    self:setSteps(steps, true)
    self:setCurrent(opts.current or 1, true)
    if opts.complete == true then
        self:setComplete(true, true)
    end
    return self
end

--- Factory shortcut for `Stepper.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels; 0 auto-grows to the row height.
--- @param steps (string|table)[] Strings or `{ label, icon }` step tables.
--- @param opts table|nil Optional layout, colours and behaviour.
--- @return PallidStepper stepper New stepper instance.
function Widgets.stepper(x, y, w, h, steps, opts)
    return Stepper.new(x, y, w, h, steps, opts)
end

--- Creates the pulse and transition tracks once.
function Stepper:_createTracks()
    if self.pulse == nil then
        self.pulse = Pallid.UI.Anim.new({
            duration = 1.6,
            easing = Pallid.UI.Anim.ease.inOutSine,
            loop = true,
            pingPong = true,
            alpha = { 1, 0.35 },
        })
    end
    if self.transition == nil then
        self.transition = Pallid.UI.Anim.new({
            duration = 0.28,
            easing = Pallid.UI.Anim.ease.outBack,
            scale = { 0.78, 1 },
        })
    end
end

--- Enables or disables the pulse, pop and connector fill animations. Turning
--- them off snaps every connector to its target state.
--- @param animate boolean True enables animations.
--- @return PallidStepper self For chaining.
function Stepper:setAnimated(animate)
    self.animated = animate == true
    if self.animated then
        self:_createTracks()
        self.pulse:play()
    else
        if self.pulse ~= nil then
            self.pulse:stop()
        end
        if self.transition ~= nil then
            self.transition:stop()
        end
        for i = 1, #self._lineTarget do
            self._lineProgress[i] = self._lineTarget[i]
            self._lineStart[i] = self._lineTarget[i]
            self._lineElapsed[i] = LINE_ANIM_DURATION
        end
    end
    return self
end

--- Replaces the step list. The active index is clamped to the new count and
--- the completed state is cleared, because the old flow no longer applies.
--- @param steps (string|table)[]|nil Strings or step tables; nil clears the list.
--- @param silent boolean|nil True skips the `onChange` callback on a clamp.
--- @return PallidStepper self For chaining.
function Stepper:setSteps(steps, silent)
    if steps ~= nil and type(steps) ~= "table" then
        Pallid.log("Stepper:setSteps expects a table of steps")
        steps = {}
    end

    self.steps = {}
    self._numbers = {}
    self.allComplete = false
    self.hoverIndex = nil
    local list = steps or {}
    for i = 1, #list do
        self.steps[i] = normaliseStep(list[i])
        self._numbers[i] = tostring(i)
    end

    local previous = self.current
    local count = #self.steps
    if count == 0 then
        self.current = 1
    else
        self.current = clampNumber(self.current, 1, count)
    end
    self:_rebuildConnectors()
    self:_layout()
    if self.current ~= previous and not silent and self.onChange ~= nil then
        self.onChange(self, self.current, previous)
    end
    return self
end

--- Sets the active step and clears the completed state. Non-number and NaN
--- values are ignored.
--- @param index number New 1-based active step; clamped to the list.
--- @param silent boolean|nil True skips the transition and `onChange`.
--- @return PallidStepper self For chaining.
function Stepper:setCurrent(index, silent)
    local count = #self.steps
    if count == 0 then
        return self
    end
    if type(index) ~= "number" or index ~= index then
        Pallid.log("Stepper:setCurrent expects a finite number")
        return self
    end

    local previous = self.current
    local current = clampNumber(math.floor(index), 1, count)
    local wasComplete = self.allComplete
    if current ~= previous or wasComplete then
        self.current = current
        self.allComplete = false
        self:_syncConnectors(not silent)
        if not silent then
            if self.animated and self.transition ~= nil then
                self.transition:play()
            end
            if current ~= previous and self.onChange ~= nil then
                self.onChange(self, current, previous)
            end
        end
    end
    return self
end

--- Marks the whole flow as finished or reopens it. Completing moves the active
--- index to the last available step, so going back shows that step as active.
--- @param done boolean True marks every step that is not disabled or in error as completed.
--- @param silent boolean|nil True skips the transition and `onComplete`.
--- @return PallidStepper self For chaining.
function Stepper:setComplete(done, silent)
    local want = done == true
    if #self.steps == 0 or want == self.allComplete then
        return self
    end

    if want then
        local last = self:_findEnabled(#self.steps + 1, -1)
        if last == nil then
            return self
        end
        self.current = last
    end
    self.allComplete = want
    self:_syncConnectors(not silent)

    if not silent then
        if self.animated and self.transition ~= nil then
            self.transition:play()
        end
        if want and self.onComplete ~= nil then
            self.onComplete(self)
        end
    end
    return self
end

--- Returns true when the text satisfies the mask.
--- @return boolean complete True when the whole flow is finished.
function Stepper:isComplete()
    return self.allComplete
end

--- Returns the completed fraction for one connector.
--- @param index integer Connector index, 1 between steps 1 and 2.
--- @return number target 1 when the connector is completed, otherwise 0.
function Stepper:_connectorTarget(index)
    if self.allComplete or index < self.current then
        return 1
    end
    return 0
end

--- Rebuilds the connector animation buffers after the step count changes.
function Stepper:_rebuildConnectors()
    self._lineProgress = {}
    self._lineStart = {}
    self._lineTarget = {}
    self._lineElapsed = {}
    for i = 1, math.max(0, #self.steps - 1) do
        local target = self:_connectorTarget(i)
        self._lineProgress[i] = target
        self._lineStart[i] = target
        self._lineTarget[i] = target
        self._lineElapsed[i] = LINE_ANIM_DURATION
    end
end

--- Retargets the connectors after a state change. Animated connectors start
--- from their current fraction, so rapid clicks never snap backwards.
--- @param animate boolean True animates changed connectors.
function Stepper:_syncConnectors(animate)
    local instant = not animate or not self.animated
    for i = 1, #self._lineTarget do
        local target = self:_connectorTarget(i)
        if target ~= self._lineTarget[i] then
            self._lineTarget[i] = target
            if instant then
                self._lineProgress[i] = target
                self._lineStart[i] = target
                self._lineElapsed[i] = LINE_ANIM_DURATION
            else
                self._lineStart[i] = self._lineProgress[i]
                self._lineElapsed[i] = 0
            end
        end
    end
end

--- Advances connector fill animations. Every connector keeps its own elapsed
--- time, so retargeting one line does not restart the others.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function Stepper:_updateConnectors(dt)
    local ease = Pallid.UI.Anim.ease.outCubic
    for i = 1, #self._lineTarget do
        local start, target = self._lineStart[i], self._lineTarget[i]
        local elapsed = self._lineElapsed[i]
        if start ~= target and elapsed < LINE_ANIM_DURATION then
            elapsed = math.min(LINE_ANIM_DURATION, elapsed + dt)
            self._lineElapsed[i] = elapsed
            if elapsed >= LINE_ANIM_DURATION then
                self._lineProgress[i] = target
            else
                local t = ease(elapsed / LINE_ANIM_DURATION)
                self._lineProgress[i] = start + (target - start) * t
            end
        end
    end
end

--- Advances the pulse, pop and connector animations. Per-frame so the glow and
--- line fill do not step at the game tick.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function Stepper:onAnimate(now, dt)
    if not self.animated then
        return
    end
    if self.pulse ~= nil then
        self.pulse:update(now)
    end
    if self.transition ~= nil then
        self.transition:update(now)
    end
    self:_updateConnectors(dt)
end

--- Returns the current step.
--- @return integer current One-based active step.
function Stepper:getCurrent()
    return self.current
end

--- Returns the number of steps.
--- @return integer count Number of steps.
function Stepper:getStepCount()
    return #self.steps
end

--- Returns true for the first step.
--- @return boolean first True when the first step is active.
function Stepper:isFirst()
    return self.current <= 1
end

--- Returns true for the last step.
--- @return boolean last True when no enabled step remains after the active one.
function Stepper:isLast()
    return self.allComplete or self:_findEnabled(self.current, 1) == nil
end

--- Finds the next selectable step in one direction, skipping disabled steps.
--- @param from integer Starting 1-based index.
--- @param direction integer 1 for forward, -1 for backward.
--- @return integer|nil index Selectable step index, or nil when none remain.
function Stepper:_findEnabled(from, direction)
    local count = #self.steps
    local index = from + direction
    while index >= 1 and index <= count do
        if not self.steps[index].disabled then
            return index
        end
        index = index + direction
    end
    return nil
end

--- Moves to the next enabled step, skipping disabled ones. Advancing past the
--- last available step marks the whole flow as complete.
--- @return PallidStepper self For chaining.
function Stepper:next()
    if self.allComplete then
        return self
    end
    local target = self:_findEnabled(self.current, 1)
    if target ~= nil then
        return self:setCurrent(target)
    end
    return self:setComplete(true)
end

--- Reopens a completed flow on its last step, or moves to the previous enabled
--- step otherwise.
--- @return PallidStepper self For chaining.
function Stepper:previous()
    if self.allComplete then
        return self:setComplete(false)
    end
    local target = self:_findEnabled(self.current, -1)
    if target ~= nil then
        self:setCurrent(target)
    end
    return self
end

--- Shows or hides labels. Auto-height is recalculated.
--- @param show boolean True allows labels.
--- @return PallidStepper self For chaining.
function Stepper:setShowLabels(show)
    self.showLabels = show == true
    self:_layout()
    return self
end

--- Changes the circle diameter and recalculates layout.
--- @param size number New diameter, clamped to 6..64.
--- @return PallidStepper self For chaining.
function Stepper:setCircleSize(size)
    if type(size) ~= "number" or size ~= size then
        Pallid.log("Stepper:setCircleSize expects a finite number")
        return self
    end
    self.circleSize = clampNumber(size, MIN_CIRCLE_SIZE, MAX_CIRCLE_SIZE)
    self:_layout()
    return self
end

--- Replaces the label and number fonts.
--- @param font UIFont|string|nil New label font, or nil to keep it.
--- @param numberFont UIFont|string|nil New number font; nil inherits `font`.
--- @return PallidStepper self For chaining.
function Stepper:setFont(font, numberFont)
    if font ~= nil then
        self.labelStyle.font = OptionUtil.resolveFont(font)
    end
    if numberFont ~= nil then
        self.numberStyle.font = OptionUtil.resolveFont(numberFont)
        self._customNumberFont = true
    elseif font ~= nil then
        self.numberStyle.font = self.labelStyle.font
        self._customNumberFont = true
    end
    self:_layout()
    return self
end

--- Replaces palette colours and refreshes the derived contrast/line colours.
--- @param colors table Palette overrides keyed as `active`, `completed`, `futureFill`, `futureBorder`, `line`, `completedLine`, `activeLabel`, `completedLabel`, `futureLabel`, `futureContent`, `error`, `hover`.
--- @return PallidStepper self For chaining.
function Stepper:setColors(colors)
    colors = colors or {}
    if colors.active ~= nil then
        self.activeColor = colors.active
        self.activeContentColor = Pallid.UI.Color.contrastText(self.activeColor)
    end
    if colors.completed ~= nil then
        self.completedColor = colors.completed
        self.completedContentColor = Pallid.UI.Color.contrastText(self.completedColor)
        if colors.completedLine == nil then
            self.completedLineColor = Pallid.UI.Color.withAlpha(self.completedColor, 0.55)
        end
    end
    if colors.completedLine ~= nil then
        self.completedLineColor = colors.completedLine
    end
    if colors.futureFill ~= nil then
        self.futureFill = colors.futureFill
    end
    if colors.futureBorder ~= nil then
        self.futureBorder = colors.futureBorder
    end
    if colors.line ~= nil then
        self.lineColor = colors.line
    end
    if colors.activeLabel ~= nil then
        self.activeLabelColor = colors.activeLabel
    end
    if colors.completedLabel ~= nil then
        self.completedLabelColor = colors.completedLabel
    end
    if colors.futureLabel ~= nil then
        self.futureLabelColor = colors.futureLabel
        if colors.futureContent == nil then
            self.futureContentColor = self.futureLabelColor
        end
    end
    if colors.futureContent ~= nil then
        self.futureContentColor = colors.futureContent
    end
    if colors.error ~= nil then
        self.errorColor = colors.error
        self.errorContentColor = Pallid.UI.Color.contrastText(self.errorColor)
    end
    if colors.hover ~= nil then
        self.hoverColor = colors.hover
    end
    return self
end

--- Updates the widget bounds.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels; 0 re-enables auto-height.
--- @return PallidStepper self For chaining.
function Stepper:setBounds(x, y, w, h)
    self._autoHeight = (h or 0) <= 0
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:_layout()
    return self
end

--- Computes slot width, radius, auto-height and vertical placement once per
--- geometry change instead of every frame.
function Stepper:_layout()
    local count = #self.steps
    self._slotW = count > 0 and self.w / count or 0

    local labelsAllowed = self.showLabels
        and (not self.autoHideLabels or self._slotW >= self.labelMinSlot)
    self._hasLabels = false
    if labelsAllowed then
        for i = 1, count do
            if self.steps[i].label ~= "" then
                self._hasLabels = true
                break
            end
        end
    end

    local labelH = self._hasLabels
        and (getTextManager():MeasureStringY(self.labelStyle.font, "Ag") + 2)
        or 0
    if self._autoHeight then
        self.h = math.max(1, math.floor(
            self.circleSize + (self._hasLabels and (LABEL_GAP + labelH) or 0) + 0.5
        ))
    end

    local maxRadius = self.circleSize * 0.5
    if self._slotW > 0 then
        maxRadius = math.min(maxRadius, self._slotW * 0.38)
    end
    if self._hasLabels then
        maxRadius = math.min(maxRadius, math.max(4, (self.h - labelH - LABEL_GAP) * 0.5))
    end
    self._radius = math.max(3, maxRadius)

    local blockH = self._radius * 2
    if self._hasLabels then
        blockH = blockH + LABEL_GAP + labelH
    end
    local top = math.max(0, (self.h - blockH) * 0.5)
    self._cy = top + self._radius
    self._labelY = top + self._radius * 2 + LABEL_GAP
    self.labelStyle.maxWidth = math.max(10, self._slotW - 6)

    if not self._customNumberFont then
        self.numberStyle.font = self._radius >= 16 and Pallid.UI.Fonts.medium or Pallid.UI.Fonts.small
    end
end



