require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/popover"
local Panel = require "pallid/ui/widgets/colorpicker/panel"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local Color = Pallid.UI.Color

local CHECK_A = Color.surfaceMuted
local CHECK_B = Color.background

--- @param color PallidColor Color to copy.
--- @return PallidColor copy Independent copy of the color.
local function copyColor(color)
    return { r = color.r or 0, g = color.g or 0, b = color.b or 0, a = color.a or 1 }
end

--- Small colour swatch that opens the picker panel in a popover.
--- @class PallidColorPicker : PallidWidget
--- @field color PallidColor Current color.
--- @field onChange fun(picker: PallidColorPicker, color: PallidColor)|nil
--- @field panel PallidColorPickerPanel|nil Lazily created picker panel.
--- @field popover PallidPopover|nil Popover that hosts the panel.
local ColorPicker = Widgets.class("ColorPicker")

--- Creates a new `ColorPicker` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Options.
--- @field opts.color PallidColor|nil Initial color.
--- @field opts.onChange fun(picker: PallidColorPicker, color: PallidColor)|nil Change callback.
--- @return PallidColorPicker picker New swatch.
function ColorPicker.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, ColorPicker)
    self:init(x, y, w, h)
    self.color = copyColor(opts.color or Color.primary)
    self.onChange = opts.onChange
    self.pressed = false
    self.borderColor = Color.border
    return self
end

--- Factory shortcut for `ColorPicker.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Options; see `ColorPicker.new`.
--- @return PallidColorPicker picker New swatch.
function Widgets.colorPicker(x, y, w, h, opts)
    return ColorPicker.new(x, y, w, h, opts)
end

--- Replaces the color and syncs an open panel.
--- @param color PallidColor New color.
--- @return PallidColorPicker self This swatch, for chaining.
function ColorPicker:setColor(color)
    self.color = copyColor(color)
    if self.panel ~= nil then
        self.panel:setColor(self.color)
    end
    return self
end

--- Returns the current color.
--- @return PallidColor color Copy of the current color.
function ColorPicker:getColor()
    return copyColor(self.color)
end

--- Opens the picker popover next to the swatch.
function ColorPicker:open()
    if self.panel == nil then
        self.panel = Panel.new(self.color, function(_, color)
            self.color = copyColor(color)
            if self.onChange ~= nil then
                self.onChange(self, self.color)
            end
        end)
        self.popover = Widgets.popover(self.panel, {
            width      = Panel.WIDTH,
            height     = Panel.HEIGHT,
            padding    = 0,
            background = Color.surfaceElevated,
            radius     = 6,
        })
        self.panel.onClose = function()
            self.panel:reset()
        end
    end
    self.panel:setColor(self.color)
    self.panel:reset()
    self.popover:show(self, "right")
end

--- Handles a pointer press inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean handled True when the press belongs to the swatch.
function ColorPicker:onDown(px, py)
    if not self.enabled then
        return false
    end
    self.pressed = true
    return true
end

--- Handles a pointer release.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function ColorPicker:onUp(px, py)
    local pressed = self.pressed
    self.pressed = false
    if pressed and self.enabled and self:isInside(px, py) then
        self:open()
    end
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the swatch is rendered into.
function ColorPicker:drawSelf(el)
    local x, y = self:originX(), self:originY()
    Pallid.UI.checker(el, x, y, self.w, self.h, 8, CHECK_A, CHECK_B)
    Pallid.UI.rect(el, x, y, self.w, self.h, self.color)
    local border = self._hover and Color.focusRing or self.borderColor
    Pallid.UI.border(el, x, y, self.w, self.h, 1, border)
end
