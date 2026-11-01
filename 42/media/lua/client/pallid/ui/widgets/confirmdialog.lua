require "pallid/ui/internal"
require "pallid/ui/widgets/modaldialog"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Confirmation dialog helper around ModalDialog. It owns the usual
--- confirm/cancel pair, handles Escape as cancel and forwards the result to a
--- single callback.
--- @class PallidConfirmDialog
--- @field dialog PallidModalDialog Wrapped modal.
--- @field onConfirm fun(dialog: PallidConfirmDialog)|nil Called when the positive button is used.
--- @field onCancel fun(dialog: PallidConfirmDialog)|nil Called for the negative button, Escape or an outside close.
local ConfirmDialog = {}
ConfirmDialog.__index = ConfirmDialog

--- Creates a new confirmation dialog.
--- @param opts table|nil Dialog content and callbacks.
--- @field opts.title string|nil Dialog title, defaults to "Confirm".
--- @field opts.message string|nil Body text.
--- @field opts.confirmText string|nil Positive button text, defaults to "OK".
--- @field opts.cancelText string|nil Negative button text, defaults to "Cancel".
--- @field opts.danger boolean|nil Styles the positive button as destructive.
--- @field opts.width number|nil Dialog width.
--- @field opts.autoSize boolean|nil True sizes the dialog to its content.
--- @field opts.onConfirm fun(dialog: PallidConfirmDialog)|nil Confirm callback.
--- @field opts.onCancel fun(dialog: PallidConfirmDialog)|nil Cancel callback.
--- @return PallidConfirmDialog confirm New confirmation dialog.
function ConfirmDialog.new(opts)
    opts = opts or {}
    local self = setmetatable({}, ConfirmDialog)
    self.onConfirm = opts.onConfirm
    self.onCancel = opts.onCancel

    local confirmText = opts.confirmText or Pallid.UI.translate("UI_Pallid_ModalOK", "OK")
    local cancelText = opts.cancelText or Pallid.UI.translate("UI_Pallid_ModalCancel", "Cancel")

    self.dialog = Widgets.modalDialog({
        title      = opts.title or Pallid.UI.translate("UI_Pallid_Confirm", "Confirm"),
        message    = opts.message or "",
        width      = opts.width,
        autoSize   = opts.autoSize ~= false,
        buttons    = {
            {
                text     = cancelText,
                negative = true,
            },
            {
                text     = confirmText,
                positive = true,
                danger   = opts.danger == true,
            },
        },
    })
    --- Maps the pressed modal button to a cancel or confirm callback.
    --- @param button table|nil Pressed button descriptor from the modal.
    self.dialog.onResult = function(button)
        if button ~= nil and button.negative then
            self:_cancel()
        elseif button ~= nil then
            self:_confirm()
        end
    end
    return self
end

--- Factory shortcut for `ConfirmDialog.new`.
--- @param opts table|nil Dialog content and callbacks.
--- @return PallidConfirmDialog confirm New confirmation dialog.
function Widgets.confirmDialog(opts)
    return ConfirmDialog.new(opts)
end

--- Opens the dialog on a root widget.
--- @param root PallidWidget Root that owns the modal.
--- @return PallidConfirmDialog self For chaining.
function ConfirmDialog:open(root)
    self.dialog:open(root)
    return self
end

--- Closes the dialog without firing a result callback.
--- @return PallidConfirmDialog self For chaining.
function ConfirmDialog:close()
    self.dialog:close()
    return self
end

--- Reports whether the wrapped dialog is currently visible.
--- @return boolean open True while the dialog is visible.
function ConfirmDialog:isOpen()
    return self.dialog:isOpen()
end

--- Fires the confirm callback when one is registered.
function ConfirmDialog:_confirm()
    if self.onConfirm ~= nil then
        self.onConfirm(self)
    end
end

--- Fires the cancel callback when one is registered.
function ConfirmDialog:_cancel()
    if self.onCancel ~= nil then
        self.onCancel(self)
    end
end

return ConfirmDialog
