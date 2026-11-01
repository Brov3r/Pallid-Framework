require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"
local normaliseOption = require "pallid/ui/widgets/internal/option_item"
local OptionUtil = require "pallid/ui/widgets/internal/option_util"
local addLayoutMethods = require "pallid/ui/widgets/breadcrumbs/layout"
local addDrawMethods = require "pallid/ui/widgets/breadcrumbs/draw"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local Textures = Pallid.UI.Textures

local DEFAULT_SEPARATOR = ""
local DEFAULT_SEPARATOR_ICON = "media/assets/ui/pallid/icons/arrow-right-04.png"
local DEFAULT_SEPARATOR_ICON_SIZE = 12
local DEFAULT_ELLIPSIS = "..."
local DEFAULT_ITEM_PADDING = 5
local DEFAULT_SEPARATOR_GAP = 4
local DEFAULT_ICON_SIZE = 14
local DEFAULT_ICON_GAP = 5
local MIN_ICON_SIZE = 6
local MAX_ICON_SIZE = 64
local MIN_DEFAULT_HEIGHT = 18
local HOVER_SPEED = 16

--- Clamps an optional number into a range, using the minimum for invalid input.
--- @param value number|nil Value to clamp.
--- @param min number Lower bound.
--- @param max number Upper bound.
--- @return number clamped Clamped value.
local function clampNumber(value, min, max)
    if type(value) ~= "number" or value ~= value then
        return min
    end
    return math.max(min, math.min(max, value))
end

--- Coerces an optional number to a finite non-negative value.
--- @param value number|nil Value to sanitise.
--- @param fallback number Value used for nil, NaN and non-numbers.
--- @return number resolved Non-negative finite value.
local function nonNegative(value, fallback)
    if type(value) ~= "number" or value ~= value then
        return fallback
    end
    return math.max(0, value)
end

--- Horizontal breadcrumb trail with icons, separators and middle collapsing.
---
--- The trail is controlled: clicking a crumb calls `onSelect` but does not
--- change `current` by itself. Call `setCurrent` from the callback to navigate.
--- The last crumb is current by default and is display-only unless
--- `clickableCurrent` is enabled. When the full trail does not fit, middle
--- crumbs are replaced with an ellipsis whose click calls `onOverflow`.
--- @class PallidBreadcrumbs : PallidWidget
--- @field items PallidOption[] Normalised crumbs in caller order.
--- @field current integer 1-based current crumb, or 0 when the list is empty.
--- @field separator string Text drawn between crumbs; empty uses the separator icon.
--- @field separatorIcon string|nil Path of the icon drawn between crumbs when `separator` is empty.
--- @field separatorIconSize number Icon separator size cap in pixels.
--- @field separatorGap number Pixels on each side of the separator.
--- @field itemPadding number Horizontal padding inside one crumb.
--- @field iconGap number Gap between a crumb icon and its label.
--- @field collapse boolean True collapses middle crumbs into an ellipsis.
--- @field ellipsis string Marker drawn in place of hidden crumbs.
--- @field clickableCurrent boolean True makes the current crumb interactive.
--- @field animated boolean True eases the hover highlight.
--- @field hover number Eased hover strength, 0..1.
--- @field hoverPart table|nil Layout part under the cursor.
--- @field font UIFont Resolved font used for crumbs and separators.
--- @field textColor PallidColor Colour of non-current crumbs.
--- @field currentColor PallidColor Colour of the current crumb.
--- @field hoverColor PallidColor Text colour at full hover.
--- @field hoverBackground PallidColor Hover plate colour, multiplied by hover.
--- @field separatorColor PallidColor Separator colour.
--- @field ellipsisColor PallidColor Ellipsis marker colour.
--- @field disabledColor PallidColor Colour of disabled crumbs.
--- @field onSelect fun(breadcrumbs: PallidBreadcrumbs, index: integer, item: PallidOption)|nil Click callback.
--- @field onOverflow fun(breadcrumbs: PallidBreadcrumbs, hiddenCount: integer)|nil Ellipsis click callback.
local Breadcrumbs = Widgets.class("Breadcrumbs")

-- Measurement and painting live in breadcrumbs/layout.lua and
-- breadcrumbs/draw.lua so this file stays focused on state, public API and input.
addLayoutMethods(Breadcrumbs)
addDrawMethods(Breadcrumbs)

--- Creates a new `Breadcrumbs` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels; content wider than this is collapsed.
--- @param h number|nil Row height; zero/nil uses a font-based default.
--- @param items (string|table)[] Crumbs or `{ label, value, icon, disabled }` tables.
--- @param opts table|nil Appearance and behaviour.
--- @field opts.current integer|nil Initial 1-based current crumb; defaults to the last one.
--- @field opts.separator string|nil Text between crumbs; empty uses `separatorIcon`.
--- @field opts.separatorIcon string|nil Separator icon path; defaults to arrow-right-04.
--- @field opts.separatorIconSize number|nil Icon separator size cap, defaults to 12.
--- @field opts.separatorGap number|nil Pixels around the separator, defaults to 4.
--- @field opts.itemPadding number|nil Horizontal padding inside a crumb, defaults to 5.
--- @field opts.iconSize number|nil Icon size cap in pixels, defaults to 14.
--- @field opts.iconGap number|nil Icon/label gap in pixels, defaults to 5.
--- @field opts.font UIFont|string|nil Crumb font or a Pallid.UI.Fonts key.
--- @field opts.collapse boolean|nil False keeps every crumb and truncates labels.
--- @field opts.ellipsis string|nil Marker for hidden crumbs, defaults to "...".
--- @field opts.clickableCurrent boolean|nil True makes the current crumb clickable.
--- @field opts.animated boolean|nil False snaps the hover highlight.
--- @field opts.textColor PallidColor|nil Colour of non-current crumbs.
--- @field opts.currentColor PallidColor|nil Colour of the current crumb.
--- @field opts.hoverColor PallidColor|nil Text colour at full hover.
--- @field opts.hoverBackground PallidColor|nil Hover plate colour.
--- @field opts.separatorColor PallidColor|nil Separator colour.
--- @field opts.ellipsisColor PallidColor|nil Ellipsis marker colour.
--- @field opts.disabledColor PallidColor|nil Colour of disabled crumbs.
--- @field opts.onSelect fun(breadcrumbs: PallidBreadcrumbs, index: integer, item: PallidOption)|nil Called with the clicked crumb index and its item.
--- @field opts.onOverflow fun(breadcrumbs: PallidBreadcrumbs, hiddenCount: integer)|nil Called with the number of hidden crumbs.
--- @return PallidBreadcrumbs breadcrumbs New breadcrumb trail.
function Breadcrumbs.new(x, y, w, h, items, opts)
    opts = opts or {}
    local self = setmetatable({}, Breadcrumbs)

    self.font = OptionUtil.resolveFont(opts.font)
    self.separator = type(opts.separator) == "string" and opts.separator or DEFAULT_SEPARATOR
    self.separatorGap = nonNegative(opts.separatorGap, DEFAULT_SEPARATOR_GAP)
    self.separatorIconSize = clampNumber(
        opts.separatorIconSize or DEFAULT_SEPARATOR_ICON_SIZE,
        MIN_ICON_SIZE,
        MAX_ICON_SIZE
    )
    self.itemPadding = nonNegative(opts.itemPadding, DEFAULT_ITEM_PADDING)
    self.iconGap = nonNegative(opts.iconGap, DEFAULT_ICON_GAP)
    self._iconSizeBase = clampNumber(opts.iconSize or DEFAULT_ICON_SIZE, MIN_ICON_SIZE, MAX_ICON_SIZE)
    self.iconSize = self._iconSizeBase
    self.collapse = opts.collapse ~= false
    self.ellipsis = type(opts.ellipsis) == "string" and opts.ellipsis or DEFAULT_ELLIPSIS
    self.clickableCurrent = opts.clickableCurrent == true
    self.animated = opts.animated ~= false
    self.onSelect = opts.onSelect
    self.onOverflow = opts.onOverflow
    self.hover = 0
    self.hoverPart = nil
    self._pressedPart = nil

    self._defaultHeight = math.max(
        MIN_DEFAULT_HEIGHT,
        getTextManager():MeasureStringY(self.font, "Ag") + 8,
        self._iconSizeBase + 6
    )
    local height = h
    if height == nil or height <= 0 then
        height = self._defaultHeight
    end
    self:init(x, y, w, height)

    self.textColor = opts.textColor or Pallid.UI.Color.textMuted
    self.currentColor = opts.currentColor or Pallid.UI.Color.textPrimary
    self.hoverColor = opts.hoverColor or Pallid.UI.Color.textPrimary
    self.hoverBackground = opts.hoverBackground or Pallid.UI.Color.primarySoft
    self.separatorColor = opts.separatorColor or Pallid.UI.Color.textDisabled
    self.ellipsisColor = opts.ellipsisColor or Pallid.UI.Color.textMuted
    self.disabledColor = opts.disabledColor or Pallid.UI.Color.textDisabled

    self.style = {
        font = self.font,
        color = self.textColor,
        alignH = "left",
        alignV = "middle",
    }
    self.separatorStyle = {
        font = self.font,
        color = self.separatorColor,
        alignH = "left",
        alignV = "middle",
    }
    -- Scratch colour for the eased hover tint. It is written in place so draw
    -- never allocates a table per crumb.
    self._tint = { r = self.textColor.r, g = self.textColor.g, b = self.textColor.b, a = self.textColor.a or 1 }

    self.current = nil
    self._parts = {}
    self._collapsed = false
    self._hiddenCount = 0
    self._needsClip = false
    self.sepW = 0
    self.ellipsisW = 0
    self._separatorDrawSize = self.separatorIconSize

    local separatorIcon = opts.separatorIcon
    if separatorIcon == nil then
        separatorIcon = DEFAULT_SEPARATOR_ICON
    end
    self:_applySeparatorIcon(separatorIcon)

    self:setItems(items)
    if opts.current ~= nil then
        self:setCurrent(opts.current)
    end
    return self
end

--- Factory shortcut for `Breadcrumbs.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number|nil Row height; zero/nil uses a font-based default.
--- @param items (string|table)[] Crumbs.
--- @param opts table|nil Appearance and behaviour.
--- @return PallidBreadcrumbs breadcrumbs New breadcrumb trail.
function Widgets.breadcrumbs(x, y, w, h, items, opts)
    return Breadcrumbs.new(x, y, w, h, items, opts)
end

--- Replaces the crumbs. The current index is clamped to the new list; an empty
--- list clears it. The hover state is dropped because layout parts are rebuilt.
--- @param items (string|table)[]|nil New crumbs; nil clears the list.
--- @return PallidBreadcrumbs self For chaining.
function Breadcrumbs:setItems(items)
    if items ~= nil and type(items) ~= "table" then
        Pallid.log("Breadcrumbs:setItems expects a table of crumbs")
        items = {}
    end

    self.items = {}
    local list = items or {}
    for i = 1, #list do
        self.items[i] = normaliseOption(list[i])
    end

    self.hoverPart = nil
    self.hover = 0
    self._pressedPart = nil
    self:_clampCurrent()
    self:_layout()
    return self
end

--- Keeps the current index inside the current crumb list.
function Breadcrumbs:_clampCurrent()
    local count = #self.items
    if count == 0 then
        self.current = 0
        return
    end
    if type(self.current) ~= "number" or self.current ~= self.current then
        self.current = count
        return
    end
    self.current = clampNumber(math.floor(self.current), 1, count)
end

--- Returns the crumbs as `PallidOption` entries in caller order.
--- @return PallidOption[] items Normalised crumb entries.
function Breadcrumbs:getItems()
    return self.items
end

--- Returns one crumb by index.
--- @param index integer 1-based crumb index.
--- @return PallidOption|nil item Crumb entry, or nil when the index is invalid.
function Breadcrumbs:getItem(index)
    return self.items[index]
end

--- Sets the current crumb without invoking any callback. The value is clamped
--- to the list; an empty list clears it.
--- @param index integer New 1-based current crumb.
--- @return PallidBreadcrumbs self For chaining.
function Breadcrumbs:setCurrent(index)
    local count = #self.items
    if count == 0 then
        self.current = 0
        return self
    end
    if type(index) ~= "number" or index ~= index then
        Pallid.log("Breadcrumbs:setCurrent expects a finite number")
        return self
    end
    self.current = clampNumber(math.floor(index), 1, count)
    return self
end

--- Returns the current crumb index.
--- @return integer current 1-based current crumb, or 0 when empty.
function Breadcrumbs:getCurrent()
    return self.current
end

--- Returns true when middle crumbs are hidden behind the ellipsis.
--- @return boolean collapsed True when at least one crumb is collapsed.
function Breadcrumbs:isCollapsed()
    return self._collapsed
end

--- Returns how many crumbs the current ellipsis replaced.
--- @return integer count Hidden crumb count; 0 when nothing is collapsed.
function Breadcrumbs:getHiddenCount()
    return self._hiddenCount
end

--- Replaces the separator text. An empty string switches back to the separator
--- icon when one is configured.
--- @param separator string New separator text.
--- @return PallidBreadcrumbs self For chaining.
function Breadcrumbs:setSeparator(separator)
    if type(separator) ~= "string" then
        Pallid.log("Breadcrumbs:setSeparator expects a string")
        return self
    end
    self.separator = separator
    self:_layout()
    return self
end

--- Resolves one separator icon path and caches its texture. Invalid and empty
--- paths clear the icon without reserving any width.
--- @param icon string|false|nil Icon path, or false/nil to disable it.
function Breadcrumbs:_applySeparatorIcon(icon)
    if type(icon) ~= "string" or icon == "" then
        self.separatorIcon = nil
        self._separatorIcon = nil
        return
    end

    self.separatorIcon = icon
    local region = Textures.getRegion(icon)
    if region ~= nil then
        self._separatorIcon = {
            hasIcon    = true,
            iconRegion = region,
        }
        return
    end
    local texture = Textures.get(icon)
    if texture == nil then
        self._separatorIcon = nil
        return
    end
    self._separatorIcon = {
        hasIcon     = true,
        iconTexture = texture,
    }
end

--- Replaces the separator icon. The icon is drawn only while `separator` is
--- empty; a non-empty separator text takes precedence.
--- @param icon string|nil New icon path; nil or "" disables the icon.
--- @return PallidBreadcrumbs self For chaining.
function Breadcrumbs:setSeparatorIcon(icon)
    if icon ~= nil and icon ~= false and type(icon) ~= "string" then
        Pallid.log("Breadcrumbs:setSeparatorIcon expects a texture path or nil")
        return self
    end
    self:_applySeparatorIcon(icon)
    self:_layout()
    return self
end

--- Replaces the marker used for hidden crumbs.
--- @param marker string New ellipsis text.
--- @return PallidBreadcrumbs self For chaining.
function Breadcrumbs:setEllipsis(marker)
    if type(marker) ~= "string" then
        Pallid.log("Breadcrumbs:setEllipsis expects a string")
        return self
    end
    self.ellipsis = marker
    self:_layout()
    return self
end

--- Enables or disables middle collapsing.
--- @param collapse boolean True collapses middle crumbs when the trail overflows.
--- @return PallidBreadcrumbs self For chaining.
function Breadcrumbs:setCollapsed(collapse)
    self.collapse = collapse == true
    self:_layout()
    return self
end

--- Enables or disables hover easing.
--- @param animate boolean True eases the hover highlight; false snaps it.
--- @return PallidBreadcrumbs self For chaining.
function Breadcrumbs:setAnimated(animate)
    self.animated = animate == true
    if not self.animated then
        self.hover = self:_isPartInteractive(self.hoverPart) and 1 or 0
    end
    return self
end

--- Enables or disables clicks on the current crumb.
--- @param clickable boolean True makes the current crumb interactive.
--- @return PallidBreadcrumbs self For chaining.
function Breadcrumbs:setClickableCurrent(clickable)
    self.clickableCurrent = clickable == true
    if not self.clickableCurrent then
        self._pressedPart = nil
    end
    return self
end

--- Replaces the crumb and separator font.
--- @param font UIFont|string|nil New font, or nil to keep the current one.
--- @return PallidBreadcrumbs self For chaining.
function Breadcrumbs:setFont(font)
    if font ~= nil then
        local resolved = OptionUtil.resolveFont(font)
        self.font = resolved
        self.style.font = resolved
        self.separatorStyle.font = resolved
        self._defaultHeight = math.max(
            MIN_DEFAULT_HEIGHT,
            getTextManager():MeasureStringY(self.font, "Ag") + 8,
            self._iconSizeBase + 6
        )
        self:_layout()
    end
    return self
end

--- Replaces palette colours. Omitted keys keep their current value.
--- @param colors table Keys: `text`, `current`, `hover`, `hoverBackground`, `separator`, `ellipsis`, `disabled`.
--- @return PallidBreadcrumbs self For chaining.
function Breadcrumbs:setColors(colors)
    colors = colors or {}
    if colors.text ~= nil then
        self.textColor = colors.text
        self.style.color = colors.text
    end
    if colors.current ~= nil then
        self.currentColor = colors.current
    end
    if colors.hover ~= nil then
        self.hoverColor = colors.hover
    end
    if colors.hoverBackground ~= nil then
        self.hoverBackground = colors.hoverBackground
    end
    if colors.separator ~= nil then
        self.separatorColor = colors.separator
        self.separatorStyle.color = colors.separator
    end
    if colors.ellipsis ~= nil then
        self.ellipsisColor = colors.ellipsis
    end
    if colors.disabled ~= nil then
        self.disabledColor = colors.disabled
    end
    return self
end

--- Enables or disables the widget. Disabling drops hover and press state.
--- @param enabled boolean True enables interaction and restores full opacity.
--- @return PallidBreadcrumbs self For chaining.
function Breadcrumbs:setEnabled(enabled)
    Widgets.Widget.setEnabled(self, enabled)
    if not enabled then
        self.hoverPart = nil
        self.hover = 0
        self._pressedPart = nil
    end
    return self
end

--- Updates the widget bounds. A zero/nil height uses the font-based default.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number|nil New height; zero/nil uses the default row height.
--- @return PallidBreadcrumbs self For chaining.
function Breadcrumbs:setBounds(x, y, w, h)
    local height = h
    if height == nil or height <= 0 then
        height = self._defaultHeight
    end
    Widgets.Widget.setBounds(self, x, y, w, height)
    self:_layout()
    return self
end

--- Eases the hover highlight. Per-frame so it does not step at the game tick.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function Breadcrumbs:onAnimate(now, dt)
    local target = 0
    if self:_isPartInteractive(self.hoverPart) then
        target = 1
    end
    if not self.animated then
        self.hover = target
        return
    end
    self.hover = Widgets.approach(self.hover, target, HOVER_SPEED, dt)
end

--- Returns true when a layout part accepts a click.
--- @param part table|nil Layout part to test.
--- @return boolean interactive True when the part is enabled and clickable.
function Breadcrumbs:_isPartInteractive(part)
    if part == nil or not self.enabled then
        return false
    end
    if part.kind == "ellipsis" then
        return self.onOverflow ~= nil
    end
    if part.kind ~= "item" then
        return false
    end
    if part.index == self.current and not self.clickableCurrent then
        return false
    end
    return not part.item.disabled
end

--- Finds the clickable layout part under the cursor. Separator parts are
--- skipped because they are decoration only.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return table|nil part Layout part under the cursor.
function Breadcrumbs:_partAt(px, py)
    local localX = px - self:originX()
    local localY = py - self:originY()
    if localX < 0 or localY < 0 or localX >= self.w or localY >= self.h then
        return nil
    end
    local parts = self._parts
    for i = 1, #parts do
        local part = parts[i]
        if part.kind ~= "separator" and localX >= part.x and localX < part.x + part.w then
            return part
        end
    end
    return nil
end

--- Tracks the interactive part under the cursor and restarts the hover ease
--- when it changes.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Breadcrumbs:onHoverMove(px, py)
    local part = self:_partAt(px, py)
    if not self:_isPartInteractive(part) then
        part = nil
    end
    if part ~= self.hoverPart then
        self.hover = 0
    end
    self.hoverPart = part
end

--- Clears the hovered crumb and resets the tooltip fade.
function Breadcrumbs:onHoverEnd()
    self.hoverPart = nil
    Widgets.Widget.onHoverEnd(self)
end

--- Handles a pointer press on a clickable crumb or the ellipsis.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when a crumb accepted the press.
function Breadcrumbs:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end
    local part = self:_partAt(px, py)
    if not self:_isPartInteractive(part) then
        return false
    end
    self._pressedPart = part
    return true
end

--- Fires the callback when the release matches the pressed crumb.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Breadcrumbs:onUp(px, py)
    local pressed = self._pressedPart
    self._pressedPart = nil
    if pressed == nil or not self.enabled or not self:isInside(px, py) then
        return
    end
    if self:_partAt(px, py) ~= pressed then
        return
    end

    if pressed.kind == "ellipsis" then
        if self.onOverflow ~= nil then
            self.onOverflow(self, self._hiddenCount)
        end
        return
    end
    if self.onSelect ~= nil then
        self.onSelect(self, pressed.index, pressed.item)
    end
end


