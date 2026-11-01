require "pallid/ui/internal"
require "pallid/ui/api/textures"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Textures = Pallid.UI.Textures
local ICON_OPTS = { mode = "fit" }

--- Normalised menu item used by Menu, ContextMenu and MenuBar.
--- @class PallidMenuItem
--- @field label string Visible item text.
--- @field icon string|Texture|nil Leading icon source.
--- @field iconRight string|Texture|nil Icon before the right-side shortcut.
--- @field shortcut string|nil Shortcut text drawn on the right.
--- @field submenu table[]|nil Child items for a submenu.
--- @field onClick fun(item: PallidMenuItem, menu: PallidWidget)|nil Click callback.
--- @field separator boolean True draws a separator line instead of a row.
--- @field disabled boolean True disables the item.
--- @field checked boolean True draws the selected tick.
--- @field checkable boolean True toggles when a checkable menu is open.
--- @field danger boolean True uses the danger palette.
--- @field color PallidColor|nil Label colour override.
--- @field iconColor PallidColor|nil Icon colour override.
--- @field raw string|table|nil Original item.
local MenuItem = {}

--- Normalises one menu item.
--- @param item string|table|nil Source item.
--- @return PallidMenuItem item Normalised item.
function MenuItem.normalise(item)
    if type(item) ~= "table" then
        item = { label = item }
    end

    local label = item.label
    if label == nil then
        label = item.text
    end
    if label == nil then
        label = ""
    elseif type(label) ~= "string" then
        label = tostring(label)
    end

    local shortcut = item.shortcut
    if shortcut ~= nil and type(shortcut) ~= "string" then
        shortcut = tostring(shortcut)
    end

    return {
        label     = label,
        icon      = item.icon,
        iconRight = item.iconRight,
        shortcut  = shortcut,
        submenu   = type(item.submenu) == "table" and item.submenu or nil,
        onClick   = type(item.onClick) == "function" and item.onClick or nil,
        separator = item.separator == true,
        disabled  = item.disabled == true,
        checked   = item.checked == true,
        checkable = item.checkable == true or item.checked ~= nil,
        danger    = item.danger == true,
        color     = type(item.color) == "table" and item.color or nil,
        iconColor = type(item.iconColor) == "table" and item.iconColor or nil,
        raw       = item,
    }
end

--- Normalises a list of menu items.
--- @param items (string|table)[]|nil Source items.
--- @return PallidMenuItem[] items Normalised items.
function MenuItem.normaliseList(items)
    local result = {}
    if type(items) ~= "table" then
        return result
    end
    for i = 1, #items do
        result[i] = MenuItem.normalise(items[i])
    end
    return result
end

--- Draws a menu icon from a path, registered icon or Texture.
--- @param el ISUIElement Host element.
--- @param icon string|Texture|nil Icon source.
--- @param x number Left edge.
--- @param y number Top edge.
--- @param size number Icon box size.
--- @param tint PallidColor|nil Tint.
--- @return boolean drawn True when an icon was painted.
function MenuItem.drawIcon(el, icon, x, y, size, tint)
    if icon == nil then
        return false
    end
    if type(icon) == "string" then
        if string.find(icon, "/", 1, true) ~= nil then
            local texture = Textures.get(icon)
            if texture ~= nil then
                Pallid.UI.texture(el, texture, x, y, size, size, tint, ICON_OPTS)
            end
        else
            Pallid.UI.icon(el, icon, x, y, size, tint)
        end
    else
        Pallid.UI.texture(el, icon, x, y, size, size, tint, ICON_OPTS)
    end
    return true
end

return MenuItem
