require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local TRACK_HEIGHT = 22
local TRACK_WIDTH = 44
local KNOB_MARGIN = 3
local LABEL_GAP = 8
local DEFAULT_SOUND = "UIToggleTickBox"

--- Horizontal pill switch. The track is a rounded rectangle with radius h/2 and
--- the knob slides between the two ends with an eased value.
--- @class PallidCheckbox : PallidWidget
--- @field checked boolean Current switch state.
--- @field label string|nil Optional text to the right of the switch.
--- @field onChange fun(checkbox: PallidCheckbox, checked: boolean)|nil State callback.
--- @field knob number Animated knob position, 0..1.
--- @field pressed boolean True between a left press and its release.
--- @field trackW number Switch track width.
--- @field trackH number Switch track height.
--- @field flat boolean True draws a plain rect track for dense layouts.
--- @field border boolean False skips the track border.
--- @field sound string|nil UI sound played on a completed click.
--- @field trackBorder PallidColor Switch track outline.
local Checkbox = Widgets.class("Checkbox")

--- Creates a new `Checkbox` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param opts table|nil Checkbox content and behaviour.
--- @field opts.checked boolean|nil Initial state.
--- @field opts.label string|nil Text drawn to the right of the switch.
--- @field opts.onChange fun(checkbox: PallidCheckbox, checked: boolean)|nil State callback.
--- @field opts.sound string|false|nil Sound name; false or "" silences it.
--- @field opts.width number|nil Switch width, defaults to 44.
--- @field opts.height number|nil Switch height, defaults to 22.
--- @field opts.flat boolean|nil Uses a plain rect track instead of rounded chrome.
--- @field opts.border boolean|nil False skips the track border; defaults to true.
--- @return PallidCheckbox checkbox New checkbox instance.
function Checkbox.new(x, y, opts)
    opts = opts or {}
    local self = setmetatable({}, Checkbox)

    local trackH = math.max(2, opts.height or TRACK_HEIGHT)
    local trackW = math.max(trackH, opts.width or TRACK_WIDTH)
    local label = opts.label
    if label == "" then
        label = nil
    end
    self.label = label
    self.style = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.text,
        alignH = "left",
        alignV = "middle",
    }
    local labelWidth = 0
    if self.label ~= nil then
        labelWidth = LABEL_GAP + getTextManager():MeasureStringX(self.style.font, self.label)
    end

    self:init(x, y, trackW + labelWidth, trackH)
    self.trackW = trackW
    self.trackH = trackH
    self.checked = opts.checked or false
    self.flat = opts.flat == true
    self.border = opts.border ~= false
    self.onChange = opts.onChange
    local sound = opts.sound
    if sound == nil then
        sound = DEFAULT_SOUND
    elseif sound == false or sound == "" then
        sound = nil
    end
    self.sound = sound
    self.knob = self.checked and 1 or 0
    self.pressed = false

    self.offFill = Pallid.UI.Color.surfaceElevated
    -- A touch brighter than primarySoft so the active track reads clearly
    -- without the glare of the full primary accent.
    self.onFill = Pallid.UI.Color.lerp(Pallid.UI.Color.primarySoft, Pallid.UI.Color.primary, 0.22)
    self.trackBorder = Pallid.UI.Color.border
    self.knobColor = Pallid.UI.Color.textPrimary
    self.fill = { r = 0, g = 0, b = 0, a = 1 }
    self._textCache = {}
    return self
end

--- Factory shortcut for `Checkbox.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param opts table|nil Checkbox settings; see `Checkbox.new`.
--- @return PallidCheckbox checkbox New checkbox instance.
function Widgets.checkbox(x, y, opts)
    return Checkbox.new(x, y, opts)
end

--- Changes the checked state and optionally notifies `onChange`.
--- @param checked boolean New state.
--- @param silent boolean|nil True skips the callback.
--- @return PallidCheckbox self For chaining.
function Checkbox:setChecked(checked, silent)
    if self.checked == checked then
        return self
    end
    self.checked = checked
    if not silent and self.onChange ~= nil then
        self.onChange(self, checked)
    end
    return self
end

--- Eases the knob travel. Per-frame so the switch does not step at the tick.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function Checkbox:onAnimate(now, dt)
    self.knob = Widgets.approach(self.knob, self.checked and 1 or 0, 16, dt)
end

--- Starts a press; the state changes only after release inside the switch.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the press was accepted.
function Checkbox:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end
    self.pressed = true
    return true
end

--- Completes a click and plays the optional sound.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Checkbox:onUp(px, py)
    local pressed = self.pressed
    self.pressed = false
    if not pressed or not self.enabled or not self:isInside(px, py) then
        return
    end

    self:setChecked(not self.checked)
    if self.sound ~= nil and getSoundManager ~= nil then
        local manager = getSoundManager()
        if manager ~= nil then
            manager:playUISound(self.sound)
        end
    end
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the tree is rendered into.
function Checkbox:drawSelf(el)
    local x, y = self:originX(), self:originY()
    local trackW, trackH = self.trackW, self.trackH
    local radius = trackH * 0.5

    self.fill.r = self.offFill.r + (self.onFill.r - self.offFill.r) * self.knob
    self.fill.g = self.offFill.g + (self.onFill.g - self.offFill.g) * self.knob
    self.fill.b = self.offFill.b + (self.onFill.b - self.offFill.b) * self.knob
    self.fill.a = 1

    if self.flat then
        Pallid.UI.rect(el, x, y, trackW, trackH, self:shade(self.fill))
        if self.border then
            Pallid.UI.border(el, x, y, trackW, trackH, 1, self:shade(self.trackBorder))
        end
    else
        Pallid.UI.roundedRect(el, x, y, trackW, trackH, radius, self:shade(self.fill))
        if self.border then
            Pallid.UI.roundedBorder(el, x, y, trackW, trackH, radius, 1, self:shade(self.trackBorder))
        end
    end

    local knobRadius = radius - KNOB_MARGIN
    local travel = trackW - trackH
    local knobX = x + radius + travel * self.knob
    Pallid.UI.circle(el, knobX, y + radius, knobRadius, self:shade(self.knobColor))

    if self.label ~= nil then
        local base = self.style.color
        self.style.color = self:shade(base)
        Pallid.UI.textPrepared(
            el,
            Pallid.UI.prepareText(self.label, self.style, self._textCache),
            x + trackW + LABEL_GAP,
            y + trackH * 0.5,
            self.style
        )
        self.style.color = base
    end
end
