require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"
local OptionUtil = require "pallid/ui/widgets/internal/option_util"
local MenuItem = require "pallid/ui/widgets/menu/item"
local addLayoutMethods = require "pallid/ui/widgets/menu/layout"
local addDrawMethods = require "pallid/ui/widgets/menu/draw"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local PADDING = 4
local ITEM_HEIGHT = 22
local SEPARATOR_HEIGHT = 9
local ICON = 14
local GAP = 6
local DEFAULT_MIN_WIDTH = 160
local DEFAULT_MAX_WIDTH = 360
local DEFAULT_MAX_HEIGHT = 320
local SCROLL_STEP = 22
local ICON_DIR = "media/assets/ui/pallid/icons/"

--- Vertical dropdown menu. Shown as an overlay at root-local coordinates and
--- closed on an outside click. Use `Widgets.menuBar` for a persistent menu bar.
--- @class PallidMenu : PallidWidget
--- @field items PallidMenuItem[] Normalised items.
--- @field scrollY number Vertical scroll offset.
--- @field hover integer Hovered item index, or 0.
--- @field openSubmenu PallidMenu|nil Currently open child menu.
--- @field checkable boolean True toggles item.checked on a leaf click.
--- @field onCheck fun(menu: PallidMenu, index: integer, checked: boolean, item: PallidMenuItem)|nil Toggle callback.
--- @field passThroughOutside boolean True lets clicks outside close and reach the tree below.
--- @field maxHeight number Maximum menu height in pixels.
--- @field maxWidth number Maximum menu width in pixels.
local Menu = Widgets.class("Menu")
addLayoutMethods(Menu)
addDrawMethods(Menu)

--- Creates a new `Menu` instance.
--- @param items (string|table)[] Menu items; separators, submenus and actions are supported.
--- @param opts table|nil Appearance and behaviour.
--- @field opts.minWidth number|nil Minimum menu width, defaults to 160.
--- @field opts.maxWidth number|nil Maximum menu width, defaults to 360.
--- @field opts.maxHeight number|nil Maximum menu height, defaults to 320.
--- @field opts.itemHeight number|nil Row height, defaults to 22.
--- @field opts.submenuOffset number|nil Horizontal gap between a menu and its submenu, defaults to 5.
--- @field opts.font UIFont|string|nil Item font or a Pallid.UI.Fonts key.
--- @field opts.background PallidColor|nil Menu fill.
--- @field opts.border PallidColor|nil Menu border.
--- @field opts.hover PallidColor|nil Hovered row fill.
--- @field opts.text PallidColor|nil Item text colour.
--- @field opts.disabled PallidColor|nil Disabled item colour.
--- @field opts.shortcut PallidColor|nil Shortcut colour.
--- @field opts.danger PallidColor|nil Danger item colour.
--- @field opts.sound string|false|nil Click sound; false or "" silences it.
--- @field opts.checkable boolean|nil True toggles `item.checked` when a leaf item is clicked.
--- @field opts.reserveCheckSlot boolean|nil True keeps the tick column even when nothing is checked.
--- @field opts.onCheck fun(menu: PallidMenu, index: integer, checked: boolean, item: PallidMenuItem)|nil Called after a checkable item toggles.
--- @field opts.closeOnSelect boolean|nil False keeps the menu open after an action. Checkable menus default to false.
--- @field opts.passThroughOutside boolean|nil True lets an outside click close and continue.
--- @field opts.onOpen fun(menu: PallidMenu)|nil Called after the menu is shown.
--- @field opts.onClose fun(menu: PallidMenu)|nil Called after the menu or a submenu closes.
--- @return PallidMenu menu New menu instance.
function Menu.new(items, opts)
    opts = opts or {}
    local self = setmetatable({}, Menu)
    self:init(0, 0, 0, 0)

    self.minWidth = math.max(1, opts.minWidth or DEFAULT_MIN_WIDTH)
    self.maxWidth = math.max(self.minWidth, opts.maxWidth or DEFAULT_MAX_WIDTH)
    self.maxHeight = math.max(1, opts.maxHeight or DEFAULT_MAX_HEIGHT)
    self.itemHeight = math.max(12, opts.itemHeight or ITEM_HEIGHT)
    self.separatorHeight = opts.separatorHeight or SEPARATOR_HEIGHT
    self.padding = opts.padding or PADDING
    self.iconSize = opts.iconSize or ICON
    self.arrowSize = opts.arrowSize or 9
    self.gap = opts.gap or GAP
    self.submenuOffset = opts.submenuOffset or 5
    self.font = OptionUtil.resolveFont(opts.font)

    self.checkable = opts.checkable == true
    self.onCheck = opts.onCheck
    self.reserveCheckSlot = opts.reserveCheckSlot == true or self.checkable
    if opts.closeOnSelect == nil then
        self.closeOnSelect = not self.checkable
    else
        self.closeOnSelect = opts.closeOnSelect ~= false
    end
    self.passThroughOutside = opts.passThroughOutside == true

    self.visible = false
    self.scrollY = 0
    self._contentH = 0
    self._viewH = 0
    self._maxScroll = 0
    self.scrollDragging = false
    self.dragStartY = 0
    self.dragStartScroll = 0
    self.hover = 0
    self.openSubmenu = nil
    self.openSubmenuIndex = 0
    self.parentMenu = nil
    self.submenus = {}
    self.onOpen = opts.onOpen
    self.onClose = opts.onClose
    local sound = opts.sound
    if sound == nil then
        sound = "UISelectListItem"
    elseif sound == false or sound == "" then
        sound = nil
    end
    self.sound = sound

    self.style = {
        font = self.font,
        color = Pallid.UI.Color.textPrimary,
        alignH = "left",
        alignV = "middle",
        ellipsis = "...",
    }
    self.shortcutStyle = {
        font = self.font,
        color = Pallid.UI.Color.textMuted,
        alignH = "right",
        alignV = "middle",
        ellipsis = "...",
    }
    self._checkTexture = Pallid.UI.Textures.get(ICON_DIR .. "tick.png")
    self._arrowTexture = Pallid.UI.Textures.get(ICON_DIR .. "arrow-right-04.png")

    self.fill = Pallid.UI.Color.surface
    self.borderColor = Pallid.UI.Color.border
    self.hoverColor = Pallid.UI.Color.accentSoft
    self.separatorColor = Pallid.UI.Color.border
    self.textColor = Pallid.UI.Color.textPrimary
    self.disabledColor = Pallid.UI.Color.textDisabled
    self.shortcutColor = Pallid.UI.Color.textMuted
    self.dangerColor = Pallid.UI.Color.error
    self.checkColor = Pallid.UI.Color.textPrimary

    self:setColors({
        background = opts.background,
        border     = opts.border,
        hover      = opts.hover,
        separator  = opts.separator,
        text       = opts.text,
        disabled   = opts.disabled,
        shortcut   = opts.shortcut,
        danger     = opts.danger,
        check      = opts.check,
    })
    self:setItems(items)
    return self
end

--- Factory shortcut for `Menu.new`.
--- @param items (string|table)[] Menu items.
--- @param opts table|nil Appearance and behaviour.
--- @return PallidMenu menu New menu instance.
function Widgets.menu(items, opts)
    return Menu.new(items, opts)
end

--- Replaces every menu item and invalidates cached submenus.
--- @param items (string|table)[]|nil New items; nil clears the menu.
--- @return PallidMenu self For chaining.
function Menu:setItems(items)
    if items ~= nil and type(items) ~= "table" then
        Pallid.log("Menu:setItems expects a table of items")
        items = {}
    end
    self:_closeSubmenu()
    self.items = MenuItem.normaliseList(items)
    self.submenus = {}
    self.hover = 0
    self.scrollY = 0
    self:measure()
    return self
end

--- Returns true when the menu item is checked.
--- @param index integer Item index.
--- @return boolean checked True when the item is checked.
function Menu:isChecked(index)
    local item = self.items[index]
    return item ~= nil and item.checked == true
end

--- Returns every checked item index in ascending order.
--- @return integer[] indexes Checked 1-based indexes.
function Menu:getChecked()
    local result = {}
    for i = 1, #self.items do
        if self.items[i].checked then
            result[#result + 1] = i
        end
    end
    return result
end

--- Changes the checked state of one item. This is also useful for restoring
--- state after a menu was rebuilt.
--- @param index integer Item index.
--- @param checked boolean New state.
--- @param silent boolean|nil True skips `onCheck`.
--- @return PallidMenu self For chaining.
function Menu:setChecked(index, checked, silent)
    local item = self.items[index]
    if item == nil or item.separator then
        return self
    end
    checked = checked == true
    if item.checked == checked then
        return self
    end

    item.checked = checked
    if type(item.raw) == "table" then
        item.raw.checked = checked
    end
    if not self.reserveCheckSlot then
        self:measure()
    end
    if not silent and self.onCheck ~= nil then
        self.onCheck(self, index, checked, item)
    end
    return self
end

--- Toggles one checkable item.
--- @param index integer Item index.
function Menu:_toggleChecked(index)
    local item = self.items[index]
    if item == nil or item.separator or item.disabled then
        return
    end
    self:setChecked(index, not item.checked)
end

--- Replaces item colours and derived palettes.
--- @param colors table Keys: `background`, `border`, `hover`, `separator`, `text`, `disabled`, `shortcut`, `danger`, `check`.
--- @return PallidMenu self For chaining.
function Menu:setColors(colors)
    colors = colors or {}
    if colors.background ~= nil then
        self.fill = colors.background
    end
    if colors.border ~= nil then
        self.borderColor = colors.border
    end
    if colors.hover ~= nil then
        self.hoverColor = colors.hover
    end
    if colors.separator ~= nil then
        self.separatorColor = colors.separator
    end
    if colors.text ~= nil then
        self.textColor = colors.text
        self.style.color = colors.text
    end
    if colors.disabled ~= nil then
        self.disabledColor = colors.disabled
    end
    if colors.shortcut ~= nil then
        self.shortcutColor = colors.shortcut
        self.shortcutStyle.color = colors.shortcut
    end
    if colors.danger ~= nil then
        self.dangerColor = colors.danger
    end
    if colors.check ~= nil then
        self.checkColor = colors.check
    end
    return self
end

--- Replaces the item font.
--- @param font UIFont|string|nil New font, or nil to keep the current one.
--- @return PallidMenu self For chaining.
function Menu:setFont(font)
    if font ~= nil then
        self.font = OptionUtil.resolveFont(font)
        self.style.font = self.font
        self.shortcutStyle.font = self.font
        self:measure()
    end
    return self
end

--- Shows the menu at root-local coordinates.
--- @param root PallidWidget Root that owns the menu.
--- @param x number Root-local X.
--- @param y number Root-local Y.
--- @return PallidMenu self For chaining.
function Menu:show(root, x, y)
    if root == nil then
        Pallid.log("Menu:show requires a root widget")
        return self
    end
    if root.openMenu ~= nil and root.openMenu ~= self then
        root.openMenu:close()
    end
    self.parent = root
    self:position(root, x, y)
    root.openMenu = self
    if self.onOpen ~= nil then
        self.onOpen(self)
    end
    return self
end

--- Closes this menu and every open submenu.
--- @return PallidMenu self For chaining.
function Menu:close()
    local root = self.root
    self:_closeTree()
    if root ~= nil and root.openMenu == self then
        root.openMenu = nil
    end
    if self.onClose ~= nil then
        self.onClose(self)
    end
    return self
end

--- Plays the configured click sound.
function Menu:_playSound()
    if self.sound ~= nil and getSoundManager ~= nil then
        getSoundManager():playUISound(self.sound)
    end
end

--- Closes the whole chain, including the top-level menu that owns this submenu.
--- @return PallidMenu self For chaining.
function Menu:closeChain()
    local top = self
    while top.parentMenu ~= nil do
        top = top.parentMenu
    end
    top:close()
    return self
end

--- Closes the open submenu, recursively.
function Menu:_closeSubmenu()
    local submenu = self.openSubmenu
    self.openSubmenu = nil
    self.openSubmenuIndex = 0
    if submenu ~= nil then
        submenu:_closeTree()
    end
end

--- Clears all visible state without firing callbacks.
function Menu:_closeTree()
    local submenu = self.openSubmenu
    self.openSubmenu = nil
    self.openSubmenuIndex = 0
    if submenu ~= nil then
        submenu:_closeTree()
    end
    self.visible = false
    self.hover = 0
    self.scrollY = 0
    self.scrollDragging = false
    self.root = nil
    self.parentMenu = nil
end

--- Returns true when the point lies inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean inside True when the point is inside the menu.
function Menu:isInside(px, py)
    return self.visible
        and px >= self.x and px < self.x + self.w
        and py >= self.y and py < self.y + self.h
end

--- Opens the submenu attached to one item and positions it beside the parent.
--- @param index integer Parent item index.
--- @return PallidMenu|nil submenu Opened submenu, or nil.
function Menu:openAt(index)
    local item = self.items[index]
    if item == nil or item.submenu == nil then
        return nil
    end

    local submenu = self.submenus[index]
    if submenu ~= nil and self.openSubmenu == submenu and self.openSubmenuIndex == index then
        return submenu
    end
    if submenu == nil then
        submenu = Menu.new(item.submenu, {
            minWidth          = self.w,
            maxWidth          = self.maxWidth,
            maxHeight         = self.maxHeight,
            itemHeight        = self.itemHeight,
            font              = self.font,
            background        = self.fill,
            border            = self.borderColor,
            hover             = self.hoverColor,
            separator         = self.separatorColor,
            text              = self.textColor,
            disabled          = self.disabledColor,
            shortcut          = self.shortcutColor,
            danger            = self.dangerColor,
            check             = self.checkColor,
            sound             = self.sound == nil and false or self.sound,
            closeOnSelect     = self.closeOnSelect,
            passThroughOutside = self.passThroughOutside,
        })
        self.submenus[index] = submenu
    else
        submenu:setItems(item.submenu)
    end

    local x, y, w = self:itemRect(index)
    local offset = self.submenuOffset or 5
    local sx = x + w + offset
    if self.root ~= nil and sx + submenu.w > self.root.w - 2 then
        sx = x - submenu.w - offset
    end
    local sy = y
    if self.root ~= nil and sy + submenu.h > self.root.h - 2 then
        sy = math.max(2, self.root.h - submenu.h - 2)
    end

    if self.openSubmenu ~= nil and self.openSubmenu ~= submenu then
        self.openSubmenu:_closeTree()
    end
    submenu.root = self.root
    submenu.parent = nil
    submenu.parentMenu = self
    submenu:position(self.root, sx, sy)
    self.openSubmenu = submenu
    self.openSubmenuIndex = index
    return submenu
end

--- Routes a pointer press to the item under the cursor.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean handled True when the menu consumed the press.
function Menu:routeDown(px, py)
    if not self.visible or not self.enabled then
        return false
    end
    if self.openSubmenu ~= nil and self.openSubmenu.visible then
        if self.openSubmenu:isInside(px, py) then
            return self.openSubmenu:routeDown(px, py)
        end
    end
    if not self:isInside(px, py) then
        return false
    end

    local trackX, trackY, trackH, thumbY, thumbH, travel = self:_scrollMetrics()
    if trackX ~= nil
        and px >= trackX - 2 and px < trackX + 4
        and py >= trackY and py < trackY + trackH then
        self.scrollDragging = true
        self.dragStartY = py
        if travel ~= nil and travel > 0 and (py < thumbY or py >= thumbY + thumbH) then
            local t = (py - trackY - thumbH * 0.5) / travel
            self.scrollY = math.max(0, math.min(self._maxScroll, t * self._maxScroll))
        end
        self.dragStartScroll = self.scrollY
        return true
    end

    local index = self:itemAt(px, py)
    if index == 0 then
        return true
    end

    local item = self.items[index]
    if item.separator or item.disabled then
        return true
    end
    if item.submenu ~= nil then
        self:_playSound()
        self:openAt(index)
        return true
    end

    local toggled = self.checkable and item.checkable
    if toggled then
        self:_toggleChecked(index)
    end
    self:_playSound()
    -- A checkable row stays open so several flags can be changed in one pass.
    if self.closeOnSelect and not toggled then
        self:closeChain()
    end
    if item.onClick ~= nil then
        item.onClick(item, self)
    end
    return true
end

--- Returns true while the cursor is in the gap between the parent item and
--- its submenu. Crossing that gap must not close the submenu.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean bridge True when the point is in the parent/submenu gap.
function Menu:_isSubmenuBridge(px, py)
    local submenu = self.openSubmenu
    if submenu == nil or not submenu.visible or self.openSubmenuIndex == 0 then
        return false
    end

    local parentX, parentY, parentW, parentH = self:itemRect(self.openSubmenuIndex)
    local subX, subY, subW, subH = submenu.x, submenu.y, submenu.w, submenu.h
    local left, right
    if subX >= parentX + parentW then
        left = parentX + parentW
        right = subX
    elseif subX + subW <= parentX then
        left = subX + subW
        right = parentX
    else
        return false
    end

    local top = math.min(parentY, subY)
    local bottom = math.max(parentY + parentH, subY + subH)
    return px >= left and px <= right and py >= top and py <= bottom
end

--- Routes pointer movement to the hovered item.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Menu:routeMove(px, py)
    if not self.visible or not self.enabled then
        return
    end
    if self.scrollDragging then
        local _, _, _, _, _, travel = self:_scrollMetrics()
        if travel ~= nil and travel > 0 then
            self.scrollY = math.max(
                0,
                math.min(
                    self._maxScroll,
                    self.dragStartScroll + (py - self.dragStartY) * self._maxScroll / travel
                )
            )
        end
        return
    end
    if self.openSubmenu ~= nil and self.openSubmenu.visible
        and self.openSubmenu:isInside(px, py) then
        self.openSubmenu:routeMove(px, py)
        return
    end
    if self:_isSubmenuBridge(px, py) then
        return
    end

    local index = self:itemAt(px, py)
    self.hover = index
    local item = self.items[index]
    if item ~= nil and item.submenu ~= nil and not item.separator and not item.disabled then
        self:openAt(index)
    else
        self:_closeSubmenu()
    end
end

--- Ends a scrollbar drag.
--- @param px number Pointer X in local coordinates.
--- @param py number Pointer Y in local coordinates.
function Menu:routeUp(px, py)
    self.scrollDragging = false
end

--- Scrolls the menu by wheel steps. Positive delta follows the framework
--- convention and scrolls down.
--- @param delta number Wheel steps.
--- @return boolean handled True while the menu is open.
function Menu:onWheel(delta)
    if not self.visible then
        return false
    end
    if self._maxScroll > 0 then
        self.scrollY = math.max(
            0,
            math.min(self._maxScroll, self.scrollY + delta * SCROLL_STEP)
        )
    end
    return true
end

--- Moves the keyboard highlight and keeps the row inside the viewport.
--- @param index integer One-based item index; 0 clears the highlight.
function Menu:_ensureHoverVisible(index)
    if index <= 0 then
        self.hover = 0
        return
    end
    self.hover = index
    local top = self._itemY and self._itemY[index] or 0
    local height = self._itemH and self._itemH[index] or self.itemHeight
    local viewTop = self.scrollY
    local viewBottom = viewTop + (self._viewH or self.h)
    if top < viewTop then
        self.scrollY = top
    elseif top + height > viewBottom then
        self.scrollY = top + height - (self._viewH or self.h)
    end
    self.scrollY = math.max(0, math.min(self._maxScroll or 0, self.scrollY))
end

--- @param index integer Candidate item index.
--- @return boolean activatable True for a real, enabled, non-separator row.
function Menu:_isActivatable(index)
    local item = self.items[index]
    return item ~= nil and not item.separator and not item.disabled
end

--- Finds the next activatable item in a direction.
--- @param from integer Starting index; 0 starts from the edge.
--- @param step integer 1 for down, -1 for up.
--- @return integer index Activatable index, or 0 when none exists.
function Menu:_nextActivatable(from, step)
    local count = #self.items
    local index = from
    for _ = 1, count do
        index = index + step
        if index < 1 or index > count then
            return 0
        end
        if self:_isActivatable(index) then
            return index
        end
    end
    return 0
end

--- Activates an item exactly like a mouse click.
--- @param index integer One-based item index.
--- @return boolean handled True when the item was activated.
function Menu:_activateItem(index)
    local item = self.items[index]
    if item == nil or item.separator or item.disabled then
        return true
    end
    if item.submenu ~= nil then
        self:_playSound()
        self:openAt(index)
        return true
    end

    local toggled = self.checkable and item.checkable
    if toggled then
        self:_toggleChecked(index)
    end
    self:_playSound()
    if self.closeOnSelect and not toggled then
        self:closeChain()
    end
    if item.onClick ~= nil then
        item.onClick(item, self)
    end
    return true
end

--- Keyboard navigation for an open menu. Up/Down skip separators and disabled
--- rows, Enter activates or opens a submenu, and Escape closes the whole chain.
--- @param key integer Keyboard.KEY_* value.
--- @return boolean handled True when the menu consumed the key.
function Menu:onKeyPress(key)
    if not self.visible or not self.enabled or Keyboard == nil then
        return false
    end

    local submenu = self.openSubmenu
    if submenu ~= nil and submenu.visible then
        if key == Keyboard.KEY_ESCAPE then
            self:closeChain()
            return true
        end
        if submenu:onKeyPress(key) then
            return true
        end
    end

    if key == Keyboard.KEY_UP or key == Keyboard.KEY_DOWN then
        local step = key == Keyboard.KEY_UP and -1 or 1
        local from = self.hover
        if from <= 0 then
            from = step > 0 and 0 or (#self.items + 1)
        end
        local index = self:_nextActivatable(from, step)
        if index == 0 and from ~= 0 then
            -- Clamp at the edge instead of wrapping around.
            index = self.hover
        end
        if index ~= 0 then
            self:_ensureHoverVisible(index)
        end
        return true
    end

    if key == Keyboard.KEY_RETURN or key == Keyboard.KEY_NUMPADENTER then
        if self.hover <= 0 then
            local first = self:_nextActivatable(0, 1)
            if first == 0 then
                return true
            end
            self:_ensureHoverVisible(first)
        end
        return self:_activateItem(self.hover)
    end

    if key == Keyboard.KEY_ESCAPE then
        self:closeChain()
        return true
    end
    return false
end
