require "pallid/ui/internal"
require "pallid/ui/api/textures"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Textures = Pallid.UI.Textures

--- One step definition.
--- @class PallidStep
--- @field label string Step label drawn under the circle.
--- @field icon string|Texture|nil Texture path, registered icon name, or Texture object.
--- @field iconRegion PallidTextureRegion|nil Atlas region when the icon is catalogued.
--- @field disabled boolean|nil Dims the step, ignores clicks and repeat.
--- @field error boolean|nil Draws the error palette regardless of progress state.
--- @field color PallidColor|nil Accent override for active/completed fill or future ring.
--- @field iconColor PallidColor|nil Content tint override for the icon or number.
--- @field labelColor PallidColor|nil Label tint override.

--- Normalises a step definition. Steps accept a plain string or a table with
--- `label`, `icon`, `disabled`, `error`, `color`, `iconColor` and `labelColor`.
--- @param step string|table Source step definition.
--- @return PallidStep entry Normalised step entry.
local function normaliseStep(step)
    local label, icon, disabled, error, color, iconColor, labelColor
    if type(step) == "string" then
        label = step
    elseif type(step) == "table" then
        label = step.label
        icon = step.icon
        disabled = step.disabled == true
        error = step.error == true
        color = type(step.color) == "table" and step.color or nil
        iconColor = type(step.iconColor) == "table" and step.iconColor or nil
        labelColor = type(step.labelColor) == "table" and step.labelColor or nil
    elseif step ~= nil then
        label = tostring(step)
    end

    if label == nil then
        label = ""
    elseif type(label) ~= "string" then
        label = tostring(label)
    end

    local entry = {
        label = label,
        iconName = nil,
        iconRegion = nil,
        iconTexture = nil,
        disabled = disabled == true,
        error = error == true,
        color = color,
        iconColor = iconColor,
        labelColor = labelColor,
    }
    if type(icon) == "string" then
        if string.find(icon, "/", 1, true) ~= nil then
            entry.iconRegion = Textures.getRegion(icon)
            if entry.iconRegion == nil then
                entry.iconTexture = Textures.get(icon)
            end
        else
            entry.iconName = icon
            entry.iconRegion = Textures.getIconRegion(icon)
        end
    elseif icon ~= nil then
        entry.iconTexture = icon
    end
    return entry
end

return normaliseStep
