require "pallid/ui/internal"
require "pallid/ui/api/textures"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Textures = Pallid.UI.Textures

--- One option accepted by RadioGroup, ToggleGroup and SegmentedControl.
--- A plain string is treated as both label and value.
--- @class PallidOption
--- @field label string Visible option text.
--- @field value string|number|boolean|table|nil Caller value; defaults to the label.
--- @field raw string|table|number|boolean|nil Original option passed by the caller.
--- @field disabled boolean True when the option cannot be selected.
--- @field iconName string|nil Registered icon name.
--- @field iconTexture Texture|nil Resolved individual texture, used as a fallback.
--- @field iconRegion PallidTextureRegion|nil Atlas region for built-in icons.
--- @field hasIcon boolean True when an icon slot should be reserved.

--- Normalises one option definition.
--- @param option string|table|number|boolean Source option.
--- @return PallidOption item Normalised option entry.
local function normaliseOption(option)
    local label, value, icon, disabled
    if type(option) == "table" then
        label = option.label
        if label == nil then
            label = option.text
        end
        if label == nil then
            label = option.value
        end
        value = option.value
        icon = option.icon
        disabled = option.disabled == true
    else
        label = option
        value = option
    end

    if label == nil then
        label = ""
    elseif type(label) ~= "string" then
        label = tostring(label)
    end
    if value == nil and type(option) ~= "table" then
        value = label
    end

    local item = {
        label        = label,
        value        = value,
        raw          = option,
        disabled     = disabled == true,
        iconName     = nil,
        iconTexture  = nil,
        iconRegion   = nil,
        hasIcon      = icon ~= nil,
    }
    if type(icon) == "string" then
        if string.find(icon, "/", 1, true) ~= nil then
            item.iconRegion = Textures.getRegion(icon)
            if item.iconRegion == nil then
                item.iconTexture = Textures.get(icon)
            end
        else
            item.iconName = icon
            item.iconRegion = Textures.getIconRegion(icon)
            -- Keep the individual lookup as a fallback for third-party icons.
            if item.iconRegion == nil then
                item.iconTexture = Textures.getIcon(icon)
            end
        end
    elseif icon ~= nil then
        item.iconTexture = icon
    end
    return item
end

return normaliseOption
