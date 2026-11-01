require "pallid/ui/internal"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

--- Normalises a modal button descriptor.
--- @param button string|table Button text or descriptor.
--- @return table button Internal button descriptor.
local function normaliseButton(button)
    if type(button) ~= "table" then
        button = { text = button }
    end
    local text = button.text
    if text == nil then
        text = button.label
    end
    if text == nil then
        text = ""
    elseif type(text) ~= "string" then
        text = tostring(text)
    end

    local lower = text:lower()
    local negative = button.negative == true or button.cancel == true
        or lower == "cancel" or lower == "close" or lower == "dismiss"
        or lower == "no" or lower == "отмена" or lower == "закрыть" or lower == "нет"
    local positive = button.positive == true or button.primary == true
    local primary = button.primary == true

    return {
        text         = text,
        icon         = button.icon,
        primary      = primary,
        positive     = positive,
        negative     = negative,
        danger       = button.danger == true,
        disabled     = button.disabled == true,
        closeOnClick = button.closeOnClick ~= false,
        onClick      = type(button.onClick) == "function" and button.onClick or nil,
        raw          = button,
    }
end

return normaliseButton
