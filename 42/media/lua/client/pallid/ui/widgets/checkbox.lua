require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local TRACK_HEIGHT = 22
local TRACK_WIDTH = 44
local KNOB_MARGIN = 3
local LABEL_GAP = 8
local DEFAULT_SOUND = "UIToggleTickBox"
local BOX_RADIUS = 4
local ICON_DIR = "media/assets/ui/pallid/icons/"
local ICON_OPTS = { mode = "fit" }

--- Checkbox with two visual variants. The default is the horizontal pill
--- switch; `variant = "box"` draws a square with a tick. Tri-state mode adds a
--- nil "indeterminate" value, drawn as a horizontal dash in the box variant.
---
--- `checked` remains the boolean compatibility field: it is true only when the
--- state is true, and `setChecked` keeps its old meaning.
--- @class PallidCheckbox : PallidWidget
--- @field state boolean|nil Current tri-state value; nil only in tri-state mode.
--- @field checked boolean Compatibility mirror: true when `state` is true.
--- @field variant "switch"|"box" Visual variant.
--- @field tristate boolean True cycles true -> false -> nil -> true.
--- @field label string|nil Optional text to the right of the control.
--- @field onChange fun(checkbox: PallidCheckbox, state: boolean|nil)|nil State callback.
--- @field knob number Animated switch knob position, 0..1.
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
--- @field opts.checked boolean|nil Initial boolean state.
--- @field opts.state boolean|nil Initial tri-state value (takes precedence over `checked`).
--- @field opts.tristate boolean|nil True enables the nil indeterminate state.
--- @field opts.variant "switch"|"box"|nil Visual variant, defaults to "switch".
--- @field opts.label string|nil Text drawn to the right of the control.
--- @field opts.onChange fun(checkbox: PallidCheckbox, state: boolean|nil)|nil State callback.
--- @field opts.sound string|false|nil Sound name; false or "" silences it.
--- @field opts.width number|nil Switch width, defaults to 44; the box variant uses its height.
--- @field opts.height number|nil Switch height, defaults to 22.
--- @field opts.flat boolean|nil Uses a plain rect track instead of rounded chrome.
--- @field opts.border boolean|nil False skips the track border; defaults to true.
--- @return PallidCheckbox checkbox New checkbox instance.
function Checkbox.new(x, y, opts)
    opts = opts or {}
    local self = setmetatable({}, Checkbox)

    local trackH = math.max(2, opts.height or TRACK_HEIGHT)
    self.variant = opts.variant == "box" and "box" or "switch"
    local trackW = self.variant == "box" and trackH or math.max(trackH, opts.width or TRACK_WIDTH)
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
    self.tristate = opts.tristate == true

    local state
    if opts.state ~= nil then
        state = opts.state == true
    elseif opts.checked ~= nil then
        state = opts.checked == true
    else
        state = false
    end
    if not self.tristate then
        state = state == true
    end
    self.state = state
    self.checked = state == true

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
    self.knob = state == true and 1 or (state == nil and 0.5 or 0)
    self.pressed = false

    self.offFill = Pallid.UI.Color.surfaceElevated
    -- A touch brighter than primarySoft so the active track reads clearly
    -- without the glare of the full primary accent.
    self.onFill = Pallid.UI.Color.lerp(Pallid.UI.Color.primarySoft, Pallid.UI.Color.primary, 0.22)
    self.trackBorder = Pallid.UI.Color.border
    self.knobColor = Pallid.UI.Color.textPrimary
    self.fill = { r = 0, g = 0, b = 0, a = 1 }
    self._textCache = {}
    self._tickTexture = Pallid.UI.Textures.get(ICON_DIR .. "tick.png")
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

--- Changes the state and optionally notifies `onChange`. A nil state is only
--- accepted in tri-state mode; otherwise it is normalised to false.
--- @param state boolean|nil New state.
--- @param silent boolean|nil True skips the callback.
--- @return PallidCheckbox self For chaining.
function Checkbox:setState(state, silent)
    if state == true then
        state = true
    elseif state == false then
        state = false
    else
        state = nil
    end
    if not self.tristate then
        state = state == true
    end
    if self.state == state then
        return self
    end
    self.state = state
    self.checked = state == true
    if not silent and self.onChange ~= nil then
        self.onChange(self, state)
    end
    return self
end

--- Returns the current tri-state value.
--- @return boolean|nil state True, false, or nil for indeterminate.
function Checkbox:getState()
    return self.state
end

--- Compatibility setter for boolean callers.
--- @param checked boolean New boolean state.
--- @param silent boolean|nil True skips the callback.
--- @return PallidCheckbox self For chaining.
function Checkbox:setChecked(checked, silent)
    return self:setState(checked == true, silent)
end

--- Advances the state. Tri-state cycles true -> false -> nil -> true; boolean
--- mode toggles true and false.
function Checkbox:_cycleState()
    local state = self.state
    if self.tristate then
        if state == true then
            self:setState(false)
        elseif state == false then
            self:setState(nil)
        else
            self:setState(true)
        end
    else
        self:setState(state ~= true)
    end
end

--- Eases the knob travel. Per-frame so the switch does not step at the tick.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function Checkbox:onAnimate(now, dt)
    local target = self.state == true and 1 or (self.state == nil and 0.5 or 0)
    self.knob = Widgets.approach(self.knob, target, 16, dt)
end

--- Starts a press; the state changes only after release inside the control.
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

    self:_cycleState()
    if self.sound ~= nil and getSoundManager ~= nil then
        local manager = getSoundManager()
        if manager ~= nil then
            manager:playUISound(self.sound)
        end
    end
end

--- Draws the box variant: square chrome, tick or indeterminate dash.
--- @param el ISUIElement Host element the tree is rendered into.
--- @param x number Absolute X of the control.
--- @param y number Absolute Y of the control.
function Checkbox:_drawBox(el, x, y)
    local size = self.trackH
    local state = self.state

    if state == true then
        Pallid.UI.roundedRect(el, x, y, size, size, BOX_RADIUS, self:shade(self.onFill))
    else
        Pallid.UI.roundedRect(el, x, y, size, size, BOX_RADIUS, self:shade(self.offFill))
    end
    if self.border then
        Pallid.UI.roundedBorder(el, x, y, size, size, BOX_RADIUS, 1, self:shade(self.trackBorder))
    end

    if state == true then
        local inset = 3
        if self._tickTexture ~= nil then
            Pallid.UI.texture(
                el,
                self._tickTexture,
                x + inset,
                y + inset,
                size - inset * 2,
                size - inset * 2,
                self:shade(self.knobColor),
                ICON_OPTS
            )
        end
    elseif state == nil then
        local dashW = math.max(2, size - 8)
        Pallid.UI.rect(el, x + (size - dashW) * 0.5, y + size * 0.5 - 1, dashW, 2, self:shade(self.trackBorder))
    end

    if self.label ~= nil then
        local style = self.style
        local base = style.color
        style.color = self:shade(base)
        Pallid.UI.textPrepared(
            el,
            Pallid.UI.prepareText(self.label, style, self._textCache),
            x + size + LABEL_GAP,
            y + size * 0.5,
            style
        )
        style.color = base
    end
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the tree is rendered into.
function Checkbox:drawSelf(el)
    local x, y = self:originX(), self:originY()
    if self.variant == "box" then
        self:_drawBox(el, x, y)
        return
    end

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
