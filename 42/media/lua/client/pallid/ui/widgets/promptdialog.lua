require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/widgets/modaldialog"
require "pallid/ui/widgets/inputtext"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Prompt dialog helper: a modal with one text field and confirm/cancel
--- buttons. Validation can keep the dialog open; the field border turns red on
--- rejection.
--- @class PallidPromptDialog
--- @field dialog PallidModalDialog Wrapped modal.
--- @field input PallidInputText Text field shown in the dialog body.
--- @field validate fun(value: string): boolean,string|nil|nil Optional validator.
--- @field onSubmit fun(prompt: PallidPromptDialog, value: string)|nil Called with a valid value.
--- @field onCancel fun(prompt: PallidPromptDialog)|nil Called when the prompt is cancelled.
local PromptDialog = {}
PromptDialog.__index = PromptDialog

--- Creates a new prompt dialog.
--- @param opts table|nil Prompt content and callbacks.
--- @field opts.title string|nil Dialog title, defaults to "Prompt".
--- @field opts.message string|nil Body text.
--- @field opts.value string|nil Initial field value.
--- @field opts.placeholder string|nil Field placeholder.
--- @field opts.masked boolean|nil Masks the input as a password.
--- @field opts.confirmText string|nil Positive button text, defaults to "OK".
--- @field opts.cancelText string|nil Negative button text, defaults to "Cancel".
--- @field opts.width number|nil Dialog width.
--- @field opts.validate fun(value: string): boolean,string|nil|nil Validator; false keeps the dialog open.
--- @field opts.onSubmit fun(prompt: PallidPromptDialog, value: string)|nil Submit callback.
--- @field opts.onCancel fun(prompt: PallidPromptDialog)|nil Cancel callback.
--- @return PallidPromptDialog prompt New prompt dialog.
function PromptDialog.new(opts)
    opts = opts or {}
    local self = setmetatable({}, PromptDialog)
    self.validate = opts.validate
    self.onSubmit = opts.onSubmit
    self.onCancel = opts.onCancel
    self._submitted = false
    self.placeholder = opts.placeholder

    self.input = Widgets.inputText(0, 0, math.max(80, (opts.width or 420) - 32), 26, {
        text        = opts.value or "",
        placeholder = opts.placeholder,
        masked      = opts.masked == true,
        background  = Pallid.UI.Color.surface,
        border      = Pallid.UI.Color.border,
        radius      = 4,
        onSubmit    = function()
            self:_submit()
        end,
    })

    self.dialog = Widgets.modalDialog({
        title         = opts.title or Pallid.UI.translate("UI_Pallid_Prompt", "Prompt"),
        message       = opts.message or "",
        width         = opts.width,
        autoSize      = true,
        content       = self.input,
        contentHeight = 26,
        buttons       = {
            {
                text     = opts.cancelText or Pallid.UI.translate("UI_Pallid_ModalCancel", "Cancel"),
                negative = true,
            },
            {
                text         = opts.confirmText or Pallid.UI.translate("UI_Pallid_ModalOK", "OK"),
                positive     = true,
                closeOnClick = false,
                onClick      = function()
                    self:_submit()
                end,
            },
        },
    })
    --- Reports a cancelled prompt through the cancel callback.
    --- @param button table|nil Pressed button descriptor.
    self.dialog.onResult = function(button)
        if button ~= nil and button.negative then
            self:_cancel()
        end
    end
    return self
end

--- Factory shortcut for `PromptDialog.new`.
--- @param opts table|nil Prompt content and callbacks.
--- @return PallidPromptDialog prompt New prompt dialog.
function Widgets.promptDialog(opts)
    return PromptDialog.new(opts)
end

--- Opens the prompt and focuses the field.
--- @param root PallidWidget Root that owns the modal.
--- @return PallidPromptDialog self For chaining.
function PromptDialog:open(root)
    self._submitted = false
    self.input.borderColor = Pallid.UI.Color.border
    self.input:setPlaceholder(self.placeholder)
    self.dialog:open(root)
    self.input:focus()
    return self
end

--- Closes the prompt without firing a result callback.
--- @return PallidPromptDialog self For chaining.
function PromptDialog:close()
    self.dialog:close()
    return self
end

--- Returns true while the prompt is visible.
--- @return boolean open True while the prompt is visible.
function PromptDialog:isOpen()
    return self.dialog:isOpen()
end

--- Returns the current field text.
--- @return string value Current field text.
function PromptDialog:getValue()
    return self.input:getText()
end

--- Replaces the field text.
--- @param value string|nil New text.
--- @return PallidPromptDialog self For chaining.
function PromptDialog:setValue(value)
    self.input:setText(value or "", true)
    return self
end

--- Validates and submits the current value.
function PromptDialog:_submit()
    if self._submitted then
        return
    end
    local value = self.input:getText()
    if self.validate ~= nil then
        local ok, message = self.validate(value)
        if ok ~= true then
            self.input.borderColor = Pallid.UI.Color.error
            if type(message) == "string" and message ~= "" then
                self.input:setPlaceholder(message)
            end
            return
        end
    end

    self._submitted = true
    self.input.borderColor = Pallid.UI.Color.border
    self.dialog:close()
    if self.onSubmit ~= nil then
        self.onSubmit(self, value)
    end
end

--- Invokes the cancel callback without firing a result.
function PromptDialog:_cancel()
    if self.onCancel ~= nil then
        self.onCancel(self)
    end
end

return PromptDialog
