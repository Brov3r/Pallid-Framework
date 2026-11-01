require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/menu"
local OptionUtil = require "pallid/ui/widgets/internal/option_util"
local MenuItem = require "pallid/ui/widgets/menu/item"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local Menu = Widgets.Menu

local PADDING = 0
local ITEM_PADDING = 10
local ICON = 14
local GAP = 6
local ARROW = 9
local DEFAULT_HEIGHT = 26
local ICON_DIR = "media/assets/ui/pallid/icons/"
local ICON_OPTS = { mode = "fit" }

--- Persistent horizontal menu bar. Top-level items can be actions or open a
--- vertical `Menu` dropdown. Unlike `Menu`, the bar lives in the widget tree and
--- only its dropdown is an overlay.
--- @class PallidMenuBar : PallidWidget
--- @field items PallidMenuItem[] Normalised top-level items.
--- @field openDropdown PallidMenu|nil Currently open dropdown.
--- @field activeIndex integer Index of the item owning the open dropdown, or 0.
--- @field hoverIndex integer Hovered item index, or 0.
local MenuBar = Widgets.class("MenuBar")

--- Creates a new `MenuBar` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param items (string|table)[] Top-level items.
--- @param opts table|nil Appearance and behaviour.
--- @field opts.height number|nil Bar height, defaults to 26.
--- @field opts.font UIFont|string|nil Font or a Pallid.UI.Fonts key.
--- @field opts.checkedMenu boolean|nil True reserves a check slot for top-level items.
--- @field opts.submenuOffset number|nil Gap from a dropdown to its submenu, defaults to 5.
--- @field opts.background PallidColor|nil Bar fill.
--- @field opts.border PallidColor|nil Bar border.
--- @field opts.hover PallidColor|nil Hovered item fill.
--- @field opts.active PallidColor|nil Active item fill.
--- @field opts.text PallidColor|nil Item text colour.
--- @field opts.disabled PallidColor|nil Disabled item colour.
--- @field opts.danger PallidColor|nil Danger item colour.
--- @field opts.sound string|false|nil Click sound; false or "" silences it.
--- @return PallidMenuBar bar New menu bar.
function MenuBar.new(x, y, items, opts)
    opts = opts or {}
    local self = setmetatable({}, MenuBar)
    self:init(x, y, 0, opts.height or DEFAULT_HEIGHT)

    self.height = opts.height or DEFAULT_HEIGHT
    self.font = OptionUtil.resolveFont(opts.font)
    self.checkedMenu = opts.checkedMenu == true
    self.submenuOffset = opts.submenuOffset or 5
    self.items = {}
    self.itemWidths = {}
    self.openDropdown = nil
    self.activeIndex = 0
    self.hoverIndex = 0
    self.pressedIndex = 0

    self.style = {
        font = self.font,
        color = Pallid.UI.Color.textPrimary,
        alignH = "left",
        alignV = "middle",
        ellipsis = "...",
    }
    self.fill = opts.background or Pallid.UI.Color.surfaceMuted
    self.borderColor = opts.border or Pallid.UI.Color.border
    self.hoverColor = opts.hover or Pallid.UI.Color.accentSoft
    self.activeColor = opts.active or Pallid.UI.Color.primarySoft
    self.textColor = opts.text or Pallid.UI.Color.textPrimary
    self.disabledColor = opts.disabled or Pallid.UI.Color.textDisabled
    self.dangerColor = opts.danger or Pallid.UI.Color.error
    local sound = opts.sound
    if sound == nil then
        sound = "UIActivateTab"
    elseif sound == false or sound == "" then
        sound = nil
    end
    self.sound = sound

    self._checkTexture = Pallid.UI.Textures.get(ICON_DIR .. "tick.png")
    self._arrowTexture = Pallid.UI.Textures.get(ICON_DIR .. "arrow-down-04.png")
    self._iconSize = opts.iconSize or ICON
    self._gap = opts.gap or GAP
    self._arrowSize = opts.arrowSize or ARROW

    self:setItems(items)
    return self
end

--- Factory shortcut for `MenuBar.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param items (string|table)[] Top-level items.
--- @param opts table|nil Appearance and behaviour.
--- @return PallidMenuBar bar New menu bar.
function Widgets.menuBar(x, y, items, opts)
    return MenuBar.new(x, y, items, opts)
end

--- Replaces the top-level items and closes any open dropdown.
--- @param items (string|table)[]|nil New items; nil clears the bar.
--- @return PallidMenuBar self For chaining.
function MenuBar:setItems(items)
    if items ~= nil and type(items) ~= "table" then
        Pallid.log("MenuBar:setItems expects a table of items")
        items = {}
    end
    self:closeDropdown()
    self._dropdowns = {}
    self.pressedIndex = 0
    self.hoverIndex = 0
    self.items = MenuItem.normaliseList(items)
    self:measure()
    return self
end

--- Recomputes item widths and the bar width.
function MenuBar:measure()
    local manager = getTextManager()
    local total = PADDING * 2
    local hasChecks = self.checkedMenu
    if not hasChecks then
        for i = 1, #self.items do
            if self.items[i].checked then
                hasChecks = true
                break
            end
        end
    end
    self._hasChecks = hasChecks

    for i = 1, #self.items do
        local item = self.items[i]
        local iconSlot = item.icon ~= nil and (self._iconSize + self._gap) or 0
        local checkSlot = hasChecks and (self._iconSize + self._gap) or 0
        local arrowSlot = item.submenu ~= nil and (self._arrowSize + self._gap) or 0
        local width = ITEM_PADDING * 2 + checkSlot + iconSlot + arrowSlot
            + manager:MeasureStringX(self.font, item.label)
        self.itemWidths[i] = width
        total = total + width
    end

    self.w = total
    self.h = self.height
end

--- Returns the rectangle of an item.
--- @param index integer Item index.
--- @return number x Root-local X.
--- @return number y Root-local Y.
--- @return number w Width.
--- @return number h Height.
function MenuBar:itemRect(index)
    local x = self:originX() + PADDING
    for i = 1, index - 1 do
        x = x + (self.itemWidths[i] or 0)
    end
    return x, self:originY(), self.itemWidths[index] or 0, self.h
end

--- Returns the item at the point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return integer index Item under the cursor, or 0.
function MenuBar:itemAt(px, py)
    if not self.visible or not self.enabled then
        return 0
    end
    if py < self:originY() or py >= self:originY() + self.h then
        return 0
    end
    for i = 1, #self.items do
        local x, _, w = self:itemRect(i)
        if px >= x and px < x + w then
            return i
        end
    end
    return 0
end

--- Opens the dropdown of one top-level item.
--- @param index integer Item index.
--- @return PallidMenu|nil menu Opened dropdown, or nil.
function MenuBar:openAt(index)
    local item = self.items[index]
    if item == nil or item.submenu == nil or item.disabled then
        return nil
    end
    if self.openDropdown ~= nil and self.activeIndex == index then
        self:closeDropdown()
        return nil
    end

    self:closeDropdown()
    local checkable = false
    for i = 1, #item.submenu do
        local child = item.submenu[i]
        if type(child) == "table" and (child.checked ~= nil or child.checkable == true) then
            checkable = true
            break
        end
    end

    local x, _, itemW = self:itemRect(index)
    local menu = self._dropdowns and self._dropdowns[index]
    if menu == nil then
        menu = Menu.new(item.submenu, {
            minWidth      = math.max(160, itemW),
            submenuOffset = self.submenuOffset,
            font          = self.font,
            background    = Pallid.UI.Color.surface,
            border        = self.borderColor,
            hover         = self.hoverColor,
            text          = self.textColor,
            disabled      = self.disabledColor,
            danger        = self.dangerColor,
            sound         = self.sound == nil and false or "UISelectListItem",
            checkable     = checkable,
            closeOnSelect = true,
            passThroughOutside = true,
        })
        self._dropdowns = self._dropdowns or {}
        self._dropdowns[index] = menu
    else
        menu:setItems(item.submenu)
    end
    menu.checkable = checkable
    menu.reserveCheckSlot = checkable
    menu.closeOnSelect = true
    menu:measure()

    local root = self:getRoot()
    menu.onClose = function()
        if self.activeIndex == index then
            self.activeIndex = 0
        end
        if self.openDropdown == menu then
            self.openDropdown = nil
        end
        self.hoverIndex = 0
    end
    menu:show(root, x, self:originY() + self.h)
    self.openDropdown = menu
    self.activeIndex = index
    return menu
end

--- Plays the configured click sound.
function MenuBar:_playSound()
    if self.sound ~= nil and getSoundManager ~= nil then
        getSoundManager():playUISound(self.sound)
    end
end

--- Closes the current dropdown, if any.
--- @return PallidMenuBar self For chaining.
function MenuBar:closeDropdown()
    local menu = self.openDropdown
    self.openDropdown = nil
    self.activeIndex = 0
    self.hoverIndex = 0
    if menu ~= nil then
        menu:close()
    end
    return self
end

--- Handles a pointer press inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the bar consumed the press.
function MenuBar:onDown(px, py, button)
    if not self.enabled then
        return false
    end
    local index = self:itemAt(px, py)
    if index == 0 then
        return false
    end
    if button == "right" then
        self.pressedIndex = 0
        return true
    end

    local item = self.items[index]
    if item.disabled then
        self.pressedIndex = 0
        return true
    end
    self.hoverIndex = index
    if item.submenu ~= nil then
        self.pressedIndex = 0
        self:_playSound()
        self:openAt(index)
    else
        self.pressedIndex = index
    end
    return true
end

--- Completes a menu-bar action click.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function MenuBar:onUp(px, py)
    local index = self.pressedIndex
    self.pressedIndex = 0
    if index == 0 or not self.enabled or self:itemAt(px, py) ~= index then
        return
    end
    local item = self.items[index]
    if item ~= nil and not item.disabled and item.submenu == nil and item.onClick ~= nil then
        self:_playSound()
        item.onClick(item, self)
    end
end

--- Updates hover state for the current pointer position.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function MenuBar:onHoverMove(px, py)
    self.hoverIndex = self:itemAt(px, py)
end

--- Clears the hovered item.
function MenuBar:onHoverEnd()
    self.hoverIndex = 0
    Widgets.Widget.onHoverEnd(self)
end

--- Enables or disables the widget.
--- @param enabled boolean True enables the bar and its dropdowns.
--- @return PallidMenuBar self For chaining.
function MenuBar:setEnabled(enabled)
    Widgets.Widget.setEnabled(self, enabled)
    if not enabled then
        self.hoverIndex = 0
        self:closeDropdown()
    end
    return self
end

--- Replaces the bar font.
--- @param font UIFont|string|nil New font, or nil to keep the current one.
--- @return PallidMenuBar self For chaining.
function MenuBar:setFont(font)
    if font ~= nil then
        self.font = OptionUtil.resolveFont(font)
        self.style.font = self.font
        self:measure()
    end
    return self
end

--- Replaces the bar palette.
--- @param colors table Keys: `background`, `border`, `hover`, `active`, `text`, `disabled`, `danger`.
--- @return PallidMenuBar self For chaining.
function MenuBar:setColors(colors)
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
    if colors.active ~= nil then
        self.activeColor = colors.active
    end
    if colors.text ~= nil then
        self.textColor = colors.text
        self.style.color = colors.text
    end
    if colors.disabled ~= nil then
        self.disabledColor = colors.disabled
    end
    if colors.danger ~= nil then
        self.dangerColor = colors.danger
    end
    return self
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element.
function MenuBar:drawSelf(el)
    if self.w <= 0 or self.h <= 0 then
        return
    end

    local x, y = self:originX(), self:originY()
    Pallid.UI.roundedRect(el, x, y, self.w, self.h, 4, self:shade(self.fill))
    Pallid.UI.roundedBorder(el, x, y, self.w, self.h, 4, 1, self:shade(self.borderColor))

    local iconSize = self._iconSize
    local gap = self._gap
    local arrowSize = self._arrowSize

    for i = 1, #self.items do
        local item = self.items[i]
        local ix, iy, iw, ih = self:itemRect(i)
        local disabled = item.disabled
        local active = self.activeIndex == i
        local hover = (self.hoverIndex == i or self.pressedIndex == i) and not disabled

        if active or hover then
            local fill = active and self.activeColor or self.hoverColor
            -- Fill the whole item cell, not an inset copy, so the bar does not
            -- show a dark seam at the selected boundary.
            Pallid.UI.roundedRect(el, ix, iy + 1, iw, ih - 2, 3, self:shade(fill))
        end

        local baseColor = disabled and self.disabledColor
            or item.color
            or (item.danger and self.dangerColor)
            or self.textColor
        local iconTint = disabled and self.disabledColor
            or item.iconColor
            or (item.danger and self.dangerColor)
            or self.textColor
        local left = ix + ITEM_PADDING

        if self._hasChecks then
            if item.checked and self._checkTexture ~= nil then
                Pallid.UI.texture(
                    el,
                    self._checkTexture,
                    left,
                    iy + (ih - iconSize) * 0.5,
                    iconSize,
                    iconSize,
                    self:shade(iconTint),
                    ICON_OPTS
                )
            end
            left = left + iconSize + gap
        end

        if item.icon ~= nil then
            MenuItem.drawIcon(
                el,
                item.icon,
                left,
                iy + (ih - iconSize) * 0.5,
                iconSize,
                self:shade(iconTint)
            )
            left = left + iconSize + gap
        end

        local right = ix + iw - ITEM_PADDING
        if item.submenu ~= nil then
            if self._arrowTexture ~= nil then
                Pallid.UI.texture(
                    el,
                    self._arrowTexture,
                    right - arrowSize,
                    iy + (ih - arrowSize) * 0.5,
                    arrowSize,
                    arrowSize,
                    self:shade(iconTint),
                    ICON_OPTS
                )
            end
            right = right - arrowSize - gap
        end

        local base = self.style.color
        self.style.color = self:shade(baseColor)
        self.style.maxWidth = math.max(0, right - left)
        Pallid.UI.text(el, item.label, left, iy + ih * 0.5, self.style)
        self.style.color = base
        self.style.maxWidth = nil
    end
end
