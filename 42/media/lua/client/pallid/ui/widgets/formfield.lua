require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local DEFAULT_CONTROL_HEIGHT = 26
local DEFAULT_GAP = 4
local REQUIRED_SUFFIX = " *"

--- Form row: a label above an arbitrary control, with a hint or an error line
--- below it. The control is an ordinary widget (usually InputText, ComboBox or
--- TagInput) and is laid out to the row's full inner width.
---
--- The row height can be omitted: it is then derived from the label line, the
--- control height and the footer line. When a height is supplied the control
--- absorbs the remaining space, so a form can stretch its fields uniformly.
--- @class PallidFormField : PallidWidget
--- @field label string|nil Text drawn above the control.
--- @field hint string|nil Helper text drawn below the control while valid.
--- @field required boolean True adds a required marker and an empty-value check.
--- @field control PallidWidget|nil Controlled widget, added as a child.
--- @field error string|nil Current error message; nil means valid.
--- @field padding number Inner inset on every side in pixels.
--- @field gap number Gap between the label, control and footer lines.
--- @field labelStyle PallidTextStyle Reused label style.
--- @field hintStyle PallidTextStyle Reused hint/error style.
local FormField = Widgets.class("FormField")

--- Creates a new `FormField` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number|nil Height in pixels; nil or 0 derives it from the content.
--- @param opts table|nil Content and validation settings.
--- @field opts.label string|nil Text above the control.
--- @field opts.control PallidWidget|nil Widget placed in the middle row.
--- @field opts.hint string|nil Helper text below the control.
--- @field opts.validate fun(value: any, field: PallidFormField)|boolean,string|nil Validator; a string return is the error message.
--- @field opts.getValue fun(field: PallidFormField, control: PallidWidget|nil)|any|nil Custom value reader.
--- @field opts.required boolean|nil Adds the required marker and an empty-value check.
--- @field opts.controlHeight number|nil Fallback control height when the control has none.
--- @field opts.padding number|nil Inner inset, defaults to 0.
--- @field opts.gap number|nil Gap between rows, defaults to 4.
--- @return PallidFormField field New form field.
function FormField.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, FormField)
    self:init(x, y, w, h)

    self.label = opts.label
    if self.label ~= nil and self.label ~= "" and opts.required then
        self.label = self.label .. REQUIRED_SUFFIX
    end
    self.hint = opts.hint
    self.required = opts.required == true
    self.validateFn = opts.validate
    self.getValueFn = opts.getValue
    self.control = opts.control
    self.controlHeight = opts.controlHeight or DEFAULT_CONTROL_HEIGHT
    self.padding = math.max(0, opts.padding or 0)
    self.gap = math.max(0, opts.gap or DEFAULT_GAP)
    self.error = nil

    self.labelStyle = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.textMuted,
        alignH = "left",
        alignV = "top",
    }
    self.hintStyle = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.textMuted,
        alignH = "left",
        alignV = "top",
    }

    if self.control ~= nil then
        self:add(self.control)
    end
    self._heightAuto = self.h <= 0
    self:_layout()
    return self
end

--- Factory shortcut for `FormField.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number|nil Height in pixels; nil or 0 derives it from the content.
--- @param opts table|nil Content and validation settings; see `FormField.new`.
--- @return PallidFormField field New form field.
function Widgets.formField(x, y, w, h, opts)
    return FormField.new(x, y, w, h, opts)
end

--- @return number lineH Height of one font line in pixels.
function FormField:_lineHeight()
    if self._lineH == nil then
        self._lineH = getTextManager():MeasureStringY(self.labelStyle.font, "Ag")
    end
    return self._lineH
end

--- @return boolean hasLabel True when a label line is reserved.
function FormField:_hasLabel()
    return self.label ~= nil and self.label ~= ""
end

--- @return boolean hasFooter True when a hint or error line is reserved.
function FormField:_hasFooter()
    return (self.hint ~= nil and self.hint ~= "") or self.error ~= nil or self.required
end

--- Resolves the row layout and positions the control.
function FormField:_layout()
    local padding = self.padding
    local gap = self.gap
    local lineH = self:_lineHeight()
    local hasLabel = self:_hasLabel()
    local hasFooter = self:_hasFooter()
    local labelH = hasLabel and lineH or 0
    local footerH = hasFooter and lineH or 0
    local gaps = (hasLabel and gap or 0) + (hasFooter and gap or 0)

    local controlH = self.control ~= nil and self.control.h or 0
    if controlH <= 0 then
        controlH = self.controlHeight
    end

    if self._heightAuto then
        self.h = padding * 2 + labelH + footerH + gaps + controlH
    else
        controlH = math.max(1, self.h - padding * 2 - labelH - footerH - gaps)
    end

    self._labelH = labelH
    self._footerH = footerH
    self._controlY = padding + labelH + (hasLabel and gap or 0)
    self._controlH = controlH
    self._innerW = math.max(0, self.w - padding * 2)
    self._footerY = self.h - padding - lineH

    if self.control ~= nil then
        self.control:setBounds(padding, self._controlY, self._innerW, controlH)
    end
end

--- Updates the widget bounds and re-runs the row layout.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels; 0 derives it from the content.
--- @return PallidFormField self For chaining.
function FormField:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self._heightAuto = h == nil or h <= 0
    self:_layout()
    return self
end

--- Replaces the helper text.
--- @param hint string|nil New helper text.
--- @return PallidFormField self For chaining.
function FormField:setHint(hint)
    self.hint = hint
    self:_layout()
    return self
end

--- Shows an error message. Passing nil or an empty string clears the error;
--- an empty string keeps the red frame without the message line.
--- @param message string|nil Error text.
--- @return PallidFormField self For chaining.
function FormField:setError(message)
    if message == nil or message == "" then
        self.error = message == "" and "" or nil
    else
        self.error = tostring(message)
    end
    self:_layout()
    return self
end

--- Clears the current error.
--- @return PallidFormField self For chaining.
function FormField:clearError()
    self.error = nil
    self:_layout()
    return self
end

--- Returns the control value. Uses `opts.getValue` when supplied, otherwise
--- the control's `getValue`/`getText`, and finally nil.
--- @return any value Current control value.
function FormField:getValue()
    if self.getValueFn ~= nil then
        return self.getValueFn(self, self.control)
    end
    local control = self.control
    if control == nil then
        return nil
    end
    if control.getValue ~= nil then
        return control:getValue()
    end
    if control.getText ~= nil then
        return control:getText()
    end
    return nil
end

--- @param value any Value to test.
--- @return boolean empty True for nil, an empty string or an empty table.
local function isEmpty(value)
    if value == nil then
        return true
    end
    if type(value) == "string" then
        return value == ""
    end
    if type(value) == "table" then
        return #value == 0
    end
    return false
end

--- Validates the field and updates the error state. A validator may return
--- true for success, false for a generic error, or false plus a message.
--- @return boolean valid True when the field passed validation.
function FormField:validate()
    local value = self:getValue()
    if self.required and isEmpty(value) then
        self:setError(Pallid.UI.translate("UI_Pallid_Required", "This field is required"))
        return false
    end

    if self.validateFn == nil then
        self:clearError()
        return true
    end

    local ok, message = self.validateFn(value, self)
    if ok == true then
        self:clearError()
        return true
    end
    if type(message) == "string" and message ~= "" then
        self:setError(message)
    else
        self:setError(Pallid.UI.translate("UI_Pallid_Invalid", "Invalid value"))
    end
    return false
end

--- Paints the label and the hint/error line.
--- @param el ISUIElement Host element the tree is rendered into.
function FormField:drawSelf(el)
    local x, y = self:originX(), self:originY()
    local padding = self.padding

    if self:_hasLabel() then
        self.labelStyle.color = self:shade(Pallid.UI.Color.textMuted)
        Pallid.UI.text(el, self.label, x + padding, y + padding, self.labelStyle)
    end

    local footer = self.error
    if footer == nil or footer == "" then
        footer = self.hint
    end
    if footer ~= nil and footer ~= "" then
        self.hintStyle.color = self:shade(
            self.error ~= nil and Pallid.UI.Color.error or Pallid.UI.Color.textMuted
        )
        Pallid.UI.text(el, footer, x + padding, y + self._footerY, self.hintStyle)
    end
end

--- Draws the control and then its validation frame above it.
--- @param el ISUIElement Host element the tree is rendered into.
function FormField:drawChildren(el)
    Widgets.Widget.drawChildren(self, el)
    if self.error == nil then
        return
    end
    local x = self:originX() + self.padding
    local y = self:originY() + self._controlY
    Pallid.UI.roundedBorder(
        el,
        x - 2,
        y - 2,
        self._innerW + 4,
        self._controlH + 4,
        5,
        1,
        self:shade(Pallid.UI.Color.error)
    )
end
