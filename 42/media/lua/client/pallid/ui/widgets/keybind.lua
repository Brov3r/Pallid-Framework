require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local I = Pallid.UI._internal

local PAD = 6
local ICON_GAP = 5
local CLEAR_SIZE = 18
local CLEAR_ICON = 14
local ICON_KEYBOARD = "media/assets/ui/pallid/icons/keyboard.png"
local ICON_CLEAR = "media/assets/ui/pallid/icons/cross.png"
local ICON_OPTS = { mode = "fit" }

-- The engine's Keyboard.getKeyName() calls glfwGetKeyName(), which returns the
-- name from the current OS layout (Keyboard.java:211). A German or Russian
-- layout would then bind/show "Z" where the physical key is "Y". Game controls
-- are physical, so the binding UI uses this fixed US-English table instead.
local KEY_NAMES = {}
local function name(key, text)
    KEY_NAMES[key] = text
end

name(Keyboard.KEY_ESCAPE, "Esc")
name(Keyboard.KEY_RETURN, "Enter")
name(Keyboard.KEY_TAB, "Tab")
name(Keyboard.KEY_BACK, "Backspace")
name(Keyboard.KEY_SPACE, "Space")
name(Keyboard.KEY_CAPITAL, "Caps Lock")
name(Keyboard.KEY_MINUS, "-")
name(Keyboard.KEY_EQUALS, "=")
name(Keyboard.KEY_LBRACKET, "[")
name(Keyboard.KEY_RBRACKET, "]")
name(Keyboard.KEY_SEMICOLON, ";")
name(Keyboard.KEY_APOSTROPHE, "'")
name(Keyboard.KEY_GRAVE, "`")
name(Keyboard.KEY_BACKSLASH, "\\")
name(Keyboard.KEY_COMMA, ",")
name(Keyboard.KEY_PERIOD, ".")
name(Keyboard.KEY_SLASH, "/")
name(Keyboard.KEY_UP, "Up")
name(Keyboard.KEY_DOWN, "Down")
name(Keyboard.KEY_LEFT, "Left")
name(Keyboard.KEY_RIGHT, "Right")
name(Keyboard.KEY_HOME, "Home")
name(Keyboard.KEY_END, "End")
name(Keyboard.KEY_PRIOR, "Page Up")
name(Keyboard.KEY_NEXT, "Page Down")
name(Keyboard.KEY_INSERT, "Insert")
name(Keyboard.KEY_DELETE, "Delete")
name(Keyboard.KEY_LSHIFT, "Shift")
name(Keyboard.KEY_RSHIFT, "Shift")
name(Keyboard.KEY_LCONTROL, "Ctrl")
name(Keyboard.KEY_RCONTROL, "Ctrl")
name(Keyboard.KEY_LMENU, "Alt")
name(Keyboard.KEY_RMENU, "Alt")
name(Keyboard.KEY_LWIN, "Win")
name(Keyboard.KEY_RWIN, "Win")

local LETTERS = {
    { Keyboard.KEY_A, "A" }, { Keyboard.KEY_B, "B" }, { Keyboard.KEY_C, "C" },
    { Keyboard.KEY_D, "D" }, { Keyboard.KEY_E, "E" }, { Keyboard.KEY_F, "F" },
    { Keyboard.KEY_G, "G" }, { Keyboard.KEY_H, "H" }, { Keyboard.KEY_I, "I" },
    { Keyboard.KEY_J, "J" }, { Keyboard.KEY_K, "K" }, { Keyboard.KEY_L, "L" },
    { Keyboard.KEY_M, "M" }, { Keyboard.KEY_N, "N" }, { Keyboard.KEY_O, "O" },
    { Keyboard.KEY_P, "P" }, { Keyboard.KEY_Q, "Q" }, { Keyboard.KEY_R, "R" },
    { Keyboard.KEY_S, "S" }, { Keyboard.KEY_T, "T" }, { Keyboard.KEY_U, "U" },
    { Keyboard.KEY_V, "V" }, { Keyboard.KEY_W, "W" }, { Keyboard.KEY_X, "X" },
    { Keyboard.KEY_Y, "Y" }, { Keyboard.KEY_Z, "Z" },
}
for i = 1, #LETTERS do
    name(LETTERS[i][1], LETTERS[i][2])
end

local DIGITS = {
    { Keyboard.KEY_0, "0" }, { Keyboard.KEY_1, "1" }, { Keyboard.KEY_2, "2" },
    { Keyboard.KEY_3, "3" }, { Keyboard.KEY_4, "4" }, { Keyboard.KEY_5, "5" },
    { Keyboard.KEY_6, "6" }, { Keyboard.KEY_7, "7" }, { Keyboard.KEY_8, "8" },
    { Keyboard.KEY_9, "9" },
}
for i = 1, #DIGITS do
    name(DIGITS[i][1], DIGITS[i][2])
end

for i = 1, 12 do
    local key = Keyboard["KEY_F" .. i]
    if key ~= nil then
        name(key, "F" .. i)
    end
end

local NUMPAD = {
    [Keyboard.KEY_NUMPAD0] = "Num 0", [Keyboard.KEY_NUMPAD1] = "Num 1",
    [Keyboard.KEY_NUMPAD2] = "Num 2", [Keyboard.KEY_NUMPAD3] = "Num 3",
    [Keyboard.KEY_NUMPAD4] = "Num 4", [Keyboard.KEY_NUMPAD5] = "Num 5",
    [Keyboard.KEY_NUMPAD6] = "Num 6", [Keyboard.KEY_NUMPAD7] = "Num 7",
    [Keyboard.KEY_NUMPAD8] = "Num 8", [Keyboard.KEY_NUMPAD9] = "Num 9",
    [Keyboard.KEY_ADD] = "Num +", [Keyboard.KEY_SUBTRACT] = "Num -",
    [Keyboard.KEY_MULTIPLY] = "Num *", [Keyboard.KEY_DIVIDE] = "Num /",
    [Keyboard.KEY_DECIMAL] = "Num .", [Keyboard.KEY_NUMPADENTER] = "Num Enter",
}
for key, text in pairs(NUMPAD) do
    name(key, text)
end

--- Human-readable US-English name for a key code.
--- @param key integer|nil Key code, or nil to clear.
--- @return string text Key name or "Unbound".
local function keyName(key)
    if key == nil then
        return I.translate("UI_Pallid_Unbound", "Unbound")
    end
    local found = KEY_NAMES[key]
    if found ~= nil then
        return found
    end
    if getKeyName ~= nil then
        -- Fallback for exotic keys: strip the KEY_ prefix rather than showing
        -- the raw scancode. May follow the OS layout.
        local raw = getKeyName(key)
        if raw ~= nil and raw ~= "" then
            return raw
        end
    end
    return "Key " .. tostring(key)
end

Pallid.UI.keyName = keyName

--- @param button string|nil "left", "right" or "middle".
--- @return string text Localized mouse button name.
local function mouseName(button)
    if button == "right" then
        return I.translate("UI_Pallid_MouseRight", "Mouse Right")
    elseif button == "middle" then
        return I.translate("UI_Pallid_MouseMiddle", "Mouse Middle")
    end
    return I.translate("UI_Pallid_MouseLeft", "Mouse Left")
end

local MODIFIER_KEYS = {
    [Keyboard.KEY_LSHIFT] = "shift", [Keyboard.KEY_RSHIFT] = "shift",
    [Keyboard.KEY_LCONTROL] = "ctrl", [Keyboard.KEY_RCONTROL] = "ctrl",
    [Keyboard.KEY_LMENU] = "alt", [Keyboard.KEY_RMENU] = "alt",
    [Keyboard.KEY_LWIN] = "win", [Keyboard.KEY_RWIN] = "win",
}

--- How long a modifier-only press waits for a normal key before it becomes a
--- binding of its own.
local MODIFIER_BIND_DELAY = 0.6

--- @param key integer Key code, or nil to clear.
--- @return boolean True when the key is currently held.
local function down(key)
    return Keyboard ~= nil and Keyboard.isKeyDown ~= nil and Keyboard.isKeyDown(key) == true
end

--- Reads the live modifier state.
--- @return boolean ctrl Ctrl modifier state.
--- @return boolean shift Shift modifier state.
--- @return boolean alt Alt modifier state.
--- @return boolean win Windows-key modifier state.
local function modifiers()
    return down(Keyboard.KEY_LCONTROL) or down(Keyboard.KEY_RCONTROL),
        down(Keyboard.KEY_LSHIFT) or down(Keyboard.KEY_RSHIFT),
        down(Keyboard.KEY_LMENU) or down(Keyboard.KEY_RMENU),
        down(Keyboard.KEY_LWIN) or down(Keyboard.KEY_RWIN)
end

--- @param pending table Mutable pending-modifier table.
local function resetPending(pending)
    pending.ctrl = false
    pending.shift = false
    pending.alt = false
    pending.win = false
end

-- Scratch fill so hover/listen easing does not allocate per frame.
local FILL = { r = 1, g = 1, b = 1, a = 1 }
local mixInto = Pallid.UI.Color.mixInto

--- Button-like field that captures the next key or mouse button and stores it
--- together with held modifiers. All keys are bindable, including Escape,
--- Backspace and Delete; the cross clears the binding (and cancels recording).
--- @class PallidKeybind : PallidWidget
--- @field key integer|nil Keyboard key code.
--- @field mouse string|nil "left", "right" or "middle" when a mouse button is bound.
--- @field ctrl boolean Current Ctrl state.
--- @field shift boolean Current Shift state.
--- @field alt boolean Current Alt state.
--- @field win boolean Current Windows-key state.
--- @field keyName string|nil Human readable key name.
--- @field listening boolean True while the widget captures keys.
--- @field onChange fun(keybind: PallidKeybind, key: integer|nil, text: string)|nil
--- @field onComboChange fun(keybind: PallidKeybind, combo: table)|nil
--- @field onValidate fun(combo: table): boolean|nil Return false to reject a capture.
local Keybind = Widgets.class("Keybind")

--- Creates a new `Keybind` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Initial binding and appearance.
--- @field opts.key integer|nil Keyboard key code.
--- @field opts.mouse string|nil "left", "right" or "middle".
--- @field opts.ctrl boolean|nil Initial Ctrl state.
--- @field opts.shift boolean|nil Initial Shift state.
--- @field opts.alt boolean|nil Initial Alt state.
--- @field opts.win boolean|nil Initial Windows-key state.
--- @field opts.icon string|false|nil Icon name or texture path; false hides it.
--- @field opts.onChange fun(keybind: PallidKeybind, key: integer|nil, text: string)|nil
--- @field opts.onComboChange fun(keybind: PallidKeybind, combo: table)|nil
--- @field opts.onValidate fun(combo: table): boolean|nil Return false to reject a capture.
--- @return PallidKeybind keybind New keybind field.
function Keybind.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, Keybind)
    self:init(x, y, w, h)
    self.acceptsFocus = true
    self.listening = false
    self.onChange = opts.onChange
    self.onComboChange = opts.onComboChange
    self.onValidate = opts.onValidate
    self.key = nil
    self.mouse = nil
    self.ctrl = false
    self.shift = false
    self.alt = false
    self.win = false
    self.keyName = nil
    self._pending = { ctrl = false, shift = false, alt = false, win = false }
    self._pendingSince = nil
    self._listenMask = nil
    self._listenLabel = I.translate("UI_Pallid_PressKey", "Press a key...")
    self._label = I.translate("UI_Pallid_Unbound", "Unbound")

    self.iconName = nil
    self.iconTexture = nil
    local icon = opts.icon
    if icon == nil then
        icon = ICON_KEYBOARD
    end
    self:setIcon(icon)
    self.clearTexture = Pallid.UI.Textures.get(ICON_CLEAR)

    self.hover = 0
    self.listenT = 0
    self._clearVisible = false

    self.fill = Pallid.UI.Color.surface
    self.hoverFill = Pallid.UI.Color.accentSoft
    self.listenFill = Pallid.UI.Color.primarySoft
    self.borderColor = Pallid.UI.Color.border
    self.accent = Pallid.UI.Color.primaryStrong
    self.textColor = Pallid.UI.Color.textPrimary
    self.mutedColor = Pallid.UI.Color.textMuted
    self.iconColor = Pallid.UI.Color.textMuted

    self.style = {
        font     = Pallid.UI.Fonts.small,
        color    = self.textColor,
        alignH   = "center",
        alignV   = "middle",
        ellipsis = "...",
    }

    if opts.mouse ~= nil then
        self:setMouseCombo(opts.mouse, opts.ctrl, opts.shift, opts.alt, opts.win, true)
    elseif opts.key ~= nil or opts.ctrl or opts.shift or opts.alt or opts.win then
        self:setCombo(opts.key, opts.ctrl, opts.shift, opts.alt, opts.win, true)
    end
    self:_refreshClear()
    return self
end

--- Factory shortcut for `Keybind.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Options; see `Keybind.new`.
--- @return PallidKeybind keybind New keybind field.
function Widgets.keybind(x, y, w, h, opts)
    return Keybind.new(x, y, w, h, opts)
end

--- Accepts a registered icon name, a texture path containing a slash, or
--- false to hide the icon.
--- @param icon string|false|nil Icon name, texture path or false.
--- @return PallidKeybind self This field, for chaining.
function Keybind:setIcon(icon)
    self.iconTexture, self.iconName = Pallid.UI.Textures.resolve(icon)
    return self
end

--- Returns true when a key is assigned.
--- @return boolean bound True when a key, mouse button or modifier is set.
function Keybind:isBound()
    return self.key ~= nil
        or self.mouse ~= nil
        or self.ctrl
        or self.shift
        or self.alt
        or self.win
end

--- Returns true while the widget captures keys.
--- @return boolean listening True while the field is capturing input.
function Keybind:isListening()
    return self.listening
end

--- Focus is accepted only while recording. Without this, binding a mouse
--- button with the left click would let the root refocus the field after the
--- capture ended, and it would swallow keys while idle.
function Keybind:focus()
    if self.listening then
        Widgets.Widget.focus(self)
    end
end

--- Formats the assigned key combination.
--- @return string text Human-readable combo, or the localized "Unbound".
function Keybind:comboText()
    local parts = {}
    if self.ctrl then
        parts[#parts + 1] = "Ctrl"
    end
    if self.alt then
        parts[#parts + 1] = "Alt"
    end
    if self.shift then
        parts[#parts + 1] = "Shift"
    end
    if self.win then
        parts[#parts + 1] = "Win"
    end
    if self.mouse ~= nil then
        parts[#parts + 1] = mouseName(self.mouse)
    elseif self.key ~= nil then
        parts[#parts + 1] = keyName(self.key)
    end
    if #parts == 0 then
        return I.translate("UI_Pallid_Unbound", "Unbound")
    end
    return table.concat(parts, "+")
end

--- Assigns a key.
--- @param key integer|nil Key code, or nil to clear.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidKeybind self This field, for chaining.
function Keybind:setKey(key, silent)
    return self:setCombo(key, false, false, false, false, silent)
end

--- Assigns a key combination.
--- @param key integer|nil Key code, or nil to clear.
--- @param ctrl boolean|nil Ctrl modifier state.
--- @param shift boolean|nil Shift modifier state.
--- @param alt boolean|nil Alt modifier state.
--- @param win boolean|nil Windows-key modifier state.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidKeybind self This field, for chaining.
function Keybind:setCombo(key, ctrl, shift, alt, win, silent)
    return self:_apply(key, nil, ctrl, shift, alt, win, silent)
end

--- Assigns a mouse combination.
--- @param mouse string|nil "left", "right" or "middle".
--- @param ctrl boolean|nil Ctrl modifier state.
--- @param shift boolean|nil Shift modifier state.
--- @param alt boolean|nil Alt modifier state.
--- @param win boolean|nil Windows-key modifier state.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidKeybind self This field, for chaining.
function Keybind:setMouseCombo(mouse, ctrl, shift, alt, win, silent)
    local normalized = nil
    if mouse == "right" or mouse == "middle" then
        normalized = mouse
    elseif mouse ~= nil then
        normalized = "left"
    end
    return self:_apply(nil, normalized, ctrl, shift, alt, win, silent)
end

--- Clears the current binding.
--- @return PallidKeybind self This field, for chaining.
function Keybind:clear()
    return self:_apply(nil, nil, false, false, false, false, false)
end

--- @param key integer|nil Key code, or nil to clear.
--- @param mouse string|nil Mouse button, or nil to clear.
--- @param ctrl boolean|nil Ctrl modifier state.
--- @param shift boolean|nil Shift modifier state.
--- @param alt boolean|nil Alt modifier state.
--- @param win boolean|nil Windows-key modifier state.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidKeybind self This field, for chaining.
function Keybind:_apply(key, mouse, ctrl, shift, alt, win, silent)
    self.key = key
    self.mouse = mouse
    self.ctrl = ctrl == true
    self.shift = shift == true
    self.alt = alt == true
    self.win = win == true
    self.keyName = key ~= nil and keyName(key) or nil
    self._label = self:comboText()
    self._listenMask = nil
    self:_refreshClear()
    if not silent then
        if self.onChange ~= nil then
            self.onChange(self, key, self._label)
        end
        if self.onComboChange ~= nil then
            self.onComboChange(self, self:getCombo())
        end
    end
    return self
end

--- Returns the key combination.
--- @return table combo { key, mouse, ctrl, shift, alt, win }
function Keybind:getCombo()
    return {
        key   = self.key,
        mouse = self.mouse,
        ctrl  = self.ctrl,
        shift = self.shift,
        alt   = self.alt,
        win   = self.win,
    }
end

--- Returns the assigned key code.
--- @return integer|nil key Current keyboard key code.
function Keybind:getKey()
    return self.key
end

--- Returns the assigned mouse button.
--- @return string|nil mouse Current mouse button, "left", "right" or "middle".
function Keybind:getMouse()
    return self.mouse
end

--- Returns the display name of a key code.
--- @return string|nil name Current key name.
function Keybind:getKeyName()
    return self.keyName
end

--- @return number x Clear-icon X inside the field.
--- @return number y Clear-icon Y inside the field.
function Keybind:_clearRect()
    return self.w - PAD - CLEAR_SIZE, math.floor((self.h - CLEAR_SIZE) * 0.5)
end

--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean hit True when the cursor is over the clear icon.
function Keybind:_clearHit(px, py)
    if not self._clearVisible then
        return false
    end
    local x, y = self:_clearRect()
    x = x + self:originX()
    y = y + self:originY()
    return px >= x and px < x + CLEAR_SIZE and py >= y and py < y + CLEAR_SIZE
end

--- Keeps the cross visible while recording (as a cancel control) and while a
--- binding exists (as a clear control).
function Keybind:_refreshClear()
    self._clearVisible = self.listening or self:isBound()
end

--- @param combo table Candidate combo.
--- @return boolean accepted True when `onValidate` allows the combo.
function Keybind:_validate(combo)
    return self.onValidate == nil or self.onValidate(combo) ~= false
end

--- @param mouse string "left" or "right".
function Keybind:_finishMouse(mouse)
    local ctrl, shift, alt, win = modifiers()
    local pending = self._pending
    ctrl = ctrl or pending.ctrl
    shift = shift or pending.shift
    alt = alt or pending.alt
    win = win or pending.win

    local combo = { key = nil, mouse = mouse, ctrl = ctrl, shift = shift, alt = alt, win = win }
    if not self:_validate(combo) then
        resetPending(pending)
        self._pendingSince = nil
        return
    end

    self.listening = false
    self._pendingSince = nil
    resetPending(pending)
    self:_apply(nil, mouse, ctrl, shift, alt, win, false)
    self:blur()
end

--- @param key integer Keyboard key code.
function Keybind:_finishKey(key)
    local ctrl, shift, alt, win = modifiers()
    local pending = self._pending
    ctrl = ctrl or pending.ctrl
    shift = shift or pending.shift
    alt = alt or pending.alt
    win = win or pending.win

    local combo = { key = key, mouse = nil, ctrl = ctrl, shift = shift, alt = alt, win = win }
    if not self:_validate(combo) then
        resetPending(pending)
        self._pendingSince = nil
        return
    end

    self.listening = false
    self._pendingSince = nil
    resetPending(pending)
    self:_apply(key, nil, ctrl, shift, alt, win, false)
    self:blur()
end

--- Handles a pointer press inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the field consumed the press.
function Keybind:onDown(px, py, button)
    if not self.enabled then
        return false
    end
    button = button or "left"

    -- The cross cancels recording or clears the binding, and must not become a
    -- mouse binding itself.
    if button == "left" and self:_clearHit(px, py) then
        if self.listening then
            self.listening = false
            self:blur()
        else
            self:clear()
        end
        return true
    end

    if self.listening then
        if button == "left" or button == "right" or button == "middle" then
            self:_finishMouse(button)
            return true
        end
        return false
    end

    if button ~= "left" then
        return false
    end

    self.listening = true
    resetPending(self._pending)
    self._pendingSince = nil
    self._listenMask = nil
    self:focus()
    self:_refreshClear()
    return true
end

--- Stops recording and drops any pending modifiers.
function Keybind:onBlur()
    self.listening = false
    self._pendingSince = nil
    resetPending(self._pending)
    self._listenMask = nil
    self:_refreshClear()
end

--- Commits a modifier-only binding after a short grace period, so Ctrl+S can
--- still be captured as a combination while a lone Ctrl becomes a binding.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous update, 0..0.1.
function Keybind:onUpdate(now, dt) -- luacheck: ignore
    if not self.listening or self._pendingSince == nil then
        return
    end
    if now - self._pendingSince < MODIFIER_BIND_DELAY then
        return
    end
    local pending = self._pending
    self._pendingSince = nil
    if not (pending.ctrl or pending.shift or pending.alt or pending.win) then
        return
    end

    local combo = {
        key   = nil,
        mouse = nil,
        ctrl  = pending.ctrl,
        shift = pending.shift,
        alt   = pending.alt,
        win   = pending.win,
    }
    if not self:_validate(combo) then
        resetPending(pending)
        return
    end

    self.listening = false
    resetPending(pending)
    self:_apply(nil, nil, combo.ctrl, combo.shift, combo.alt, combo.win, false)
    self:blur()
end

--- Rebinds the live modifier label only when the modifier mask changes.
function Keybind:_refreshListenLabel()
    local ctrl, shift, alt, win = modifiers()
    local pending = self._pending
    ctrl = ctrl or pending.ctrl
    shift = shift or pending.shift
    alt = alt or pending.alt
    win = win or pending.win

    local mask = 0
    if ctrl then mask = mask + 1 end
    if shift then mask = mask + 2 end
    if alt then mask = mask + 4 end
    if win then mask = mask + 8 end
    if mask == self._listenMask then
        return
    end
    self._listenMask = mask

    if mask == 0 then
        self._listenLabel = I.translate("UI_Pallid_PressKey", "Press a key...")
        return
    end

    local parts = {}
    if ctrl then parts[#parts + 1] = "Ctrl" end
    if alt then parts[#parts + 1] = "Alt" end
    if shift then parts[#parts + 1] = "Shift" end
    if win then parts[#parts + 1] = "Win" end
    local template = I.translate("UI_Pallid_PressKeyCombo", "Press key...")
    self._listenLabel = template .. " (" .. table.concat(parts, "+") .. ")"
end

--- Handles a key press.
--- @param key integer Keyboard.KEY_* code.
function Keybind:onKeyPress(key)
    if not self.listening then
        return
    end

    -- A modifier on its own is a valid binding, but wait briefly so a normal
    -- key pressed at the same time becomes the real binding.
    local flag = MODIFIER_KEYS[key]
    if flag ~= nil then
        self._pending[flag] = true
        self._pendingSince = Pallid.UI.Anim.now()
        return
    end

    self:_finishKey(key)
end

--- Advances the eased transitions for the current frame.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function Keybind:onAnimate(now, dt)
    self.hover = Widgets.approach(self.hover, self._hover and 1 or 0, 14, dt)
    self.listenT = Widgets.approach(self.listenT, self.listening and 1 or 0, 16, dt)
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the field is rendered into.
function Keybind:drawSelf(el)
    local x, y = self:originX(), self:originY()

    mixInto(FILL, self.fill, self.hoverFill, self.hover)
    mixInto(FILL, FILL, self.listenFill, self.listenT)

    -- Same corner fix as the other fields: keep the AA fill inside the border.
    Pallid.UI.roundedRect(el, x + 1, y + 1, self.w - 2, self.h - 2, 2, self:shade(FILL))
    Pallid.UI.roundedBorder(
        el, x, y, self.w, self.h, 3, self.listening and 2 or 1,
        self:shade(self.listening and self.accent or self.borderColor)
    )

    local iconSize = self.h - 10
    local left = PAD
    if iconSize > 0 and (self.iconTexture ~= nil or self.iconName ~= nil) then
        local iconY = y + (self.h - iconSize) * 0.5
        local tint = self:shade(self.iconColor)
        if self.iconTexture ~= nil then
            Pallid.UI.texture(el, self.iconTexture, x + PAD, iconY, iconSize, iconSize, tint, ICON_OPTS)
        else
            Pallid.UI.icon(el, self.iconName, x + PAD, iconY, iconSize, tint)
        end
        left = PAD + iconSize + ICON_GAP
    end

    if self._clearVisible and self.clearTexture ~= nil then
        local cx, cy = self:_clearRect()
        local iconX = x + cx + (CLEAR_SIZE - CLEAR_ICON) * 0.5
        local iconY = y + cy + (CLEAR_SIZE - CLEAR_ICON) * 0.5
        Pallid.UI.texture(el, self.clearTexture, iconX, iconY,
            CLEAR_ICON, CLEAR_ICON, self:shade(self.mutedColor), ICON_OPTS)
    end

    local right = PAD
    if self._clearVisible then
        right = right + CLEAR_SIZE + 2
    end
    local textW = math.max(0, self.w - left - right)
    self.style.maxWidth = textW

    local label
    if self.listening then
        self:_refreshListenLabel()
        label = self._listenLabel
    else
        label = self._label
    end

    local bound = self:isBound()
    self.style.color = self:shade((not bound and not self.listening) and self.mutedColor or self.textColor)
    Pallid.UI.text(el, label, x + left + textW * 0.5, y + self.h * 0.5, self.style)
    self.style.color = self.textColor
end
