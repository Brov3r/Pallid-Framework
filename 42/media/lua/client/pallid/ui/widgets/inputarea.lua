require "pallid/ui/internal"
require "pallid/ui/widgets/input"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local I = Pallid.UI._internal

--- Multi-line text area backed by the game's ISTextEntryBox.
---
--- Input patterns are single-line only; `pattern` is ignored here with a log.
--- Native wrapping is visual and does not change the logical value. See
--- `PallidInputBase.initInput` for shared options.
--- @class PallidInputArea : PallidInputBase
local InputArea = Widgets.class("InputArea", Widgets.InputBase)

--- Creates a new `InputArea` instance.
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
--- @field opts.maxLines integer|nil Maximum line count; defaults to 1000.
--- @field opts.wrap boolean|nil Wrap long lines; defaults to true.
--- @field opts.onlyText boolean|nil Native filter for ASCII letters only.
--- @field opts.forceUpperCase boolean|nil Native upper-case conversion.
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
--- @field opts.onChange fun(input: PallidInputBase, text: string, raw: string)|nil Called after the text changes.
--- @field opts.onSubmit fun(input: PallidInputBase, text: string, raw: string)|nil Called when the text is submitted.
--- @return PallidInputArea input New multiline field.
function InputArea.new(x, y, w, h, opts)
    opts = I.copyTable(opts)
    opts.multiline = true
    local self = setmetatable({}, InputArea)
    self:initInput(x, y, w, h, opts)
    return self
end

--- Factory shortcut for `InputArea.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional settings.
--- @return PallidInputArea input New multiline field.
function Widgets.inputArea(x, y, w, h, opts)
    return InputArea.new(x, y, w, h, opts)
end
