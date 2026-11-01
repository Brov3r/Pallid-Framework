require "pallid/ui/internal"
require "pallid/ui/widgets/button"
require "pallid/ui/widgets/inputtext"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local I = Pallid.UI._internal

local ICON_DIR = "media/assets/ui/pallid/icons/"
local ICON_SHOW = ICON_DIR .. "visible.png"
local ICON_HIDE = ICON_DIR .. "invisible.png"
local BUTTON_SIZE = 24
local BUTTON_INSET = 4

--- Password preset over `PallidInputText`. Masking itself lives in the base
--- input; this class adds an optional eye button that toggles the mask.
---
--- The mask glyph is always `*` because the engine exposes no custom one.
--- Prefer `Widgets.inputText` with `opts.masked = true` in new code.
--- @class PallidInputPassword : PallidInputText
--- @field revealButton PallidButton|nil Optional show/hide button.
local InputPassword = Widgets.class("InputPassword", Widgets.InputText)

--- Creates the optional show/hide button and reserves room for it on the right.
function InputPassword:_createRevealButton()
    local size = math.max(12, math.min(BUTTON_SIZE, self.h - 4))
    local button
    button = Widgets.button(0, 0, size, size, {
        icon       = ICON_SHOW,
        background = false,
        iconInset  = 3,
        iconColor  = Pallid.UI.Color.textMuted,
        sound      = false,
        onClick    = function()
            self:setMasked(not self:isMasked())
        end,
    })
    self.revealButton = button
    self:add(button)
    self:_layoutRevealButton()
    self:_syncRevealButton()
end

--- Keeps the eye button in the right-hand padding after a resize.
function InputPassword:_layoutRevealButton()
    local button = self.revealButton
    if button == nil then
        return
    end
    local size = button.w
    local inset = self.paddingX or BUTTON_INSET
    button:setBounds(
        self.w - size - inset,
        math.floor((self.h - size) * 0.5),
        size,
        size
    )
    self.rightInset = size + inset + 2
end

--- Keeps the eye icon and tooltip in sync with the current mask state.
function InputPassword:_syncRevealButton()
    local button = self.revealButton
    if button == nil then
        return
    end
    local masked = self:isMasked()
    button:setIcon(masked and ICON_SHOW or ICON_HIDE)
    button:setTooltip(masked and "Show password" or "Hide password")
end

--- Creates a new `InputPassword` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Same options as `InputText.new`; `masked` is forced on.
--- @field opts.revealButton boolean|nil Shows the eye toggle; defaults to true.
--- @return PallidInputPassword input New masked single-line field.
function InputPassword.new(x, y, w, h, opts)
    opts = I.copyTable(opts)
    opts.masked = true
    local self = setmetatable({}, InputPassword)
    self:initInput(x, y, w, h, opts)
    if opts.revealButton ~= false then
        self:_createRevealButton()
    end
    return self
end

--- Moves and resizes the field and keeps the eye button on the right edge.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @return PallidInputPassword self For chaining.
function InputPassword:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:_layoutRevealButton()
    return self
end

--- Toggles native masking and updates the eye button.
--- @param masked boolean True hides the value.
--- @return PallidInputPassword self For chaining.
function InputPassword:setMasked(masked)
    Widgets.InputBase.setMasked(self, masked)
    self:_syncRevealButton()
    return self
end

--- Enables or disables the field and its eye button together.
--- @param enabled boolean True enables editing and the reveal toggle.
--- @return PallidInputPassword self For chaining.
function InputPassword:setEnabled(enabled)
    Widgets.InputBase.setEnabled(self, enabled)
    if self.revealButton ~= nil then
        self.revealButton:setEnabled(enabled)
    end
    return self
end

--- Factory shortcut for `InputPassword.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Same options as `InputText.new`; `masked` is forced on.
--- @return PallidInputPassword input New masked single-line field.
function Widgets.inputPassword(x, y, w, h, opts)
    return InputPassword.new(x, y, w, h, opts)
end
