require "pallid/ui/internal"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local ICON_OPTS = { mode = "fit" }

--- Shared helpers for RadioGroup, ToggleGroup and SegmentedControl.
--- @class PallidOptionUtil
local OptionUtil = {}

--- Resolves a font option that may be a UIFont or a Pallid.UI.Fonts key.
--- @param font UIFont|string|nil Font or a Pallid.UI.Fonts key.
--- @return UIFont resolved UIFont instance.
function OptionUtil.resolveFont(font)
    if type(font) == "string" then
        return Pallid.UI.Fonts[font] or Pallid.UI.Fonts.small
    end
    return font or Pallid.UI.Fonts.small
end

--- Draws one normalised option icon.
--- @param el ISUIElement Host element.
--- @param item PallidOption Option to draw.
--- @param x number Left edge of the icon box.
--- @param y number Top edge of the icon box.
--- @param size number Icon box size in pixels.
--- @param tint PallidColor Icon tint.
function OptionUtil.drawIcon(el, item, x, y, size, tint)
    if item.iconRegion ~= nil then
        Pallid.UI.textureRegion(el, item.iconRegion, x, y, size, size, tint, ICON_OPTS)
    elseif item.iconTexture ~= nil then
        Pallid.UI.texture(el, item.iconTexture, x, y, size, size, tint, ICON_OPTS)
    elseif item.iconName ~= nil then
        Pallid.UI.icon(el, item.iconName, x, y, size, tint)
    end
end

return OptionUtil
