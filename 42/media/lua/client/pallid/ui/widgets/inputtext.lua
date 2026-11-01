require "pallid/ui/internal"
require "pallid/ui/widgets/input"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Single-line text field backed by the game's ISTextEntryBox.
---
--- Supports input templates (`pattern`), password masking (`masked`), native
--- placeholders and optional rounded chrome. See `PallidInputBase.initInput`
--- for the full option list.
--- @class PallidInputText : PallidInputBase
local InputText = Widgets.class("InputText", Widgets.InputBase)

--- Creates a new `InputText` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional settings.
--- @field opts.text string|nil Initial value.
--- @field opts.placeholder string|nil Placeholder shown while the value is empty.
--- @field opts.placeholderColor PallidColor|nil Placeholder RGB tint; the engine forces alpha 1.
--- @field opts.textColor PallidColor|nil Text tint.
--- @field opts.font UIFont|string|nil Font or a key from Pallid.UI.Fonts.
--- @field opts.maxLength integer|nil Input cap; 0 keeps the engine default (2000).
--- @field opts.pattern string|nil Input template such as `##-##-###` or `xx-xx-xxx`.
--- @field opts.masked boolean|nil Native password masking with `*`.
--- @field opts.mask boolean|string|nil Deprecated password alias; the string value is ignored.
--- @field opts.numeric boolean|nil Digits, one dot and an optional leading minus.
--- @field opts.decimals integer|nil Fractional digit limit when `numeric` is on.
--- @field opts.allowNegative boolean|nil Allows a leading minus with `numeric`.
--- @field opts.onlyText boolean|nil Native filter for ASCII letters only.
--- @field opts.forceUpperCase boolean|nil Native upper-case conversion.
--- @field opts.clearButton boolean|nil Shows the native clear button.
--- @field opts.selectable boolean|nil Allows selecting text; defaults to true.
--- @field opts.readOnly boolean|nil Select-only value: no native caret; drag to select.
--- @field opts.rounded boolean|nil Rounded chrome with the default radius.
--- @field opts.radius number|table|nil Corner radius; a number or {tl,tr,br,bl}.
--- @field opts.paddingX number|nil Horizontal text padding; defaults to 7.
--- @field opts.paddingY number|nil Vertical text padding; defaults to 4.
--- @field opts.padding number|nil Deprecated shorthand applying the same padding on both axes.
--- @field opts.background PallidColor|false|nil Field fill; false disables it.
--- @field opts.border PallidColor|false|nil Field border; false disables it.
--- @field opts.borderWidth number|nil Border thickness; defaults to 1.
--- @field opts.transparent boolean|nil Draws no widget or native chrome.
--- @field opts.onChange fun(input: PallidInputBase, text: string, raw: string)|nil Called after the value changes.
--- @field opts.onSubmit fun(input: PallidInputBase, text: string, raw: string)|nil Called when Enter is pressed.
--- @return PallidInputText input New single-line field.
function InputText.new(x, y, w, h, opts)
    local self = setmetatable({}, InputText)
    self:initInput(x, y, w, h, opts)
    return self
end

--- Factory shortcut for `InputText.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional settings.
--- @return PallidInputText input New single-line field.
function Widgets.inputText(x, y, w, h, opts)
    return InputText.new(x, y, w, h, opts)
end
