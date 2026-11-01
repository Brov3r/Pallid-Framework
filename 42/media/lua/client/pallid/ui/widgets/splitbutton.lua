require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/button"
require "pallid/ui/widgets/menu"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local ICON_DIR = "media/assets/ui/pallid/icons/"
local ICON_OPTS = { mode = "fit" }
local DEFAULT_ARROW = 24

--- Button with a split arrow that opens a Menu. The left part behaves exactly
--- like a normal button; the right part opens the attached menu below itself.
--- @class PallidSplitButton : PallidWidget
--- @field button PallidButton Main action button child.
--- @field menu PallidMenu Attached menu, shown by the arrow.
--- @field arrowWidth number Width of the arrow segment in pixels.
--- @field onClick fun(split: PallidSplitButton, button: PallidButton)|nil Called after the main button is clicked.
--- @field onArrowClick fun(split: PallidSplitButton, menu: PallidMenu)|nil Called after the menu opens.
local SplitButton = Widgets.class("SplitButton")

--- Creates a new `SplitButton` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Content and menu settings.
--- @field opts.text string|nil Main button label.
--- @field opts.icon string|nil Main button icon.
--- @field opts.items (string|table)[]|nil Menu items.
--- @field opts.menuOptions table|nil Extra options forwarded to the Menu.
--- @field opts.onClick fun(split: PallidSplitButton, button: PallidButton)|nil Main button callback.
--- @field opts.onArrowClick fun(split: PallidSplitButton, menu: PallidMenu)|nil Called after the menu opens.
--- @field opts.arrowWidth number|nil Arrow width, defaults to 24.
--- @field opts.radius number|nil Corner radius, defaults to 4.
--- @field opts.sound string|false|nil Main button sound.
--- @return PallidSplitButton split New split button.
function SplitButton.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, SplitButton)
    self:init(x, y, w or 0, h or 0)

    self.arrowWidth = math.max(12, opts.arrowWidth or DEFAULT_ARROW)
    self.onClick = opts.onClick
    self.onArrowClick = opts.onArrowClick
    self.radius = opts.radius or 4
    self._hoverArrow = false
    self._arrowTexture = Pallid.UI.Textures.get(ICON_DIR .. "arrow-down-04.png")

    self.button = Widgets.button(0, 0, math.max(1, self.w - self.arrowWidth), self.h, {
        text    = opts.text,
        icon    = opts.icon,
        radius  = { tl = self.radius, tr = 0, br = 0, bl = self.radius },
        sound   = opts.sound,
        onClick = function(button)
            if self.onClick ~= nil then
                self.onClick(self, button)
            end
        end,
    })
    self:add(self.button)

    self.menuOptions = opts.menuOptions
    self.menu = Widgets.menu(opts.items or {}, opts.menuOptions)
    return self
end

--- Factory shortcut for `SplitButton.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Content and menu settings; see `SplitButton.new`.
--- @return PallidSplitButton split New split button.
function Widgets.splitButton(x, y, w, h, opts)
    return SplitButton.new(x, y, w, h, opts)
end

--- Updates the widget bounds and the child button width.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidSplitButton self For chaining.
function SplitButton:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    if self.button ~= nil then
        self.button:setBounds(0, 0, math.max(1, w - self.arrowWidth), h)
    end
    return self
end

--- Replaces the menu items.
--- @param items (string|table)[]|nil New items.
--- @return PallidSplitButton self For chaining.
function SplitButton:setItems(items)
    self.menu:setItems(items)
    return self
end

--- Replaces the main button label.
--- @param text string New label.
--- @return PallidSplitButton self For chaining.
function SplitButton:setText(text)
    self.button:setText(text)
    return self
end

--- Opens the attached menu below the arrow.
--- @return PallidMenu|nil menu Open menu, or nil when the split button is detached.
function SplitButton:showMenu()
    local root = self:getRoot()
    if root == nil then
        return nil
    end
    local menu = self.menu
    local x = self:originX() + self.w - menu.w
    local y = self:originY() + self.h + 2
    menu:show(root, x, y)
    if self.onArrowClick ~= nil then
        self.onArrowClick(self, menu)
    end
    return menu
end

--- Enables or disables both the main button and the arrow.
--- @param enabled boolean New state.
--- @return PallidSplitButton self For chaining.
function SplitButton:setEnabled(enabled)
    Widgets.Widget.setEnabled(self, enabled)
    self.button:setEnabled(enabled)
    if not enabled and self.menu.visible then
        self.menu:close()
    end
    return self
end

--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean handled True when the arrow segment was pressed.
function SplitButton:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end
    local arrowX = self:originX() + self.w - self.arrowWidth
    if px < arrowX then
        return false
    end
    self:showMenu()
    return true
end

--- Tracks whether the cursor is over the arrow segment.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function SplitButton:onHoverMove(px, py)
    self._hoverArrow = px >= self:originX() + self.w - self.arrowWidth
end

--- Clears the arrow hover.
function SplitButton:onHoverEnd()
    self._hoverArrow = false
    Widgets.Widget.onHoverEnd(self)
end

--- Closes the menu when the split button leaves the tree.
function SplitButton:onDetach()
    if self.menu.visible then
        self.menu:close()
    end
end

--- Paints the arrow segment. The main button paints its own left half.
--- @param el ISUIElement Host element the tree is rendered into.
function SplitButton:drawSelf(el)
    local x, y = self:originX(), self:originY()
    local ax = x + self.w - self.arrowWidth
    local radius = self.radius
    local fill = self._hoverArrow and Pallid.UI.Color.accentSoft or Pallid.UI.Color.surface

    Pallid.UI.roundedRect(
        el,
        ax,
        y,
        self.arrowWidth,
        self.h,
        { tl = 0, tr = radius, br = radius, bl = 0 },
        self:shade(fill)
    )
    Pallid.UI.roundedBorder(
        el,
        ax,
        y,
        self.arrowWidth,
        self.h,
        { tl = 0, tr = radius, br = radius, bl = 0 },
        1,
        self:shade(Pallid.UI.Color.border)
    )
    Pallid.UI.rect(el, ax, y + 2, 1, self.h - 4, self:shade(Pallid.UI.Color.border))

    if self._arrowTexture ~= nil then
        local size = 10
        Pallid.UI.texture(
            el,
            self._arrowTexture,
            ax + (self.arrowWidth - size) * 0.5,
            y + (self.h - size) * 0.5,
            size,
            size,
            self:shade(Pallid.UI.Color.textMuted),
            ICON_OPTS
        )
    end
end
