require "pallid/ui/internal"
require "pallid/ui/widgets/menu"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local Menu = Widgets.Menu

--- Context menu opened by a right click. It uses the vertical `Menu` layout
--- and is closed by a left click outside; an outside right click closes it and
--- continues routing to the widget under the cursor.
--- @class PallidContextMenu : PallidMenu
--- @field isContextMenu boolean Marker used by the input router.
local ContextMenu = Widgets.class("ContextMenu", Menu)

--- Creates a new `ContextMenu` instance.
--- @param items (string|table)[] Menu items.
--- @param opts table|nil Appearance and behaviour; see `Menu.new`.
--- @return PallidContextMenu menu New context menu.
function ContextMenu.new(items, opts)
    opts = opts or {}
    local self = Menu.new(items, opts)
    setmetatable(self, ContextMenu)
    self.isContextMenu = true
    return self
end

--- Factory shortcut for `ContextMenu.new`.
--- @param items (string|table)[] Menu items.
--- @param opts table|nil Appearance and behaviour.
--- @return PallidContextMenu menu New context menu.
function Widgets.contextMenu(items, opts)
    return ContextMenu.new(items, opts)
end
