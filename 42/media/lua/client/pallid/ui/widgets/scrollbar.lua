require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

-- A thumb shorter than this is hard to grab with the mouse.
local MIN_THUMB = 24
-- Shared thickness for every Pallid scrollbar. Containers read this instead of
-- hard-coding their own size, so tables, lists and panels look uniform.
local DEFAULT_SIZE = 10
--- Default thickness in pixels shared by every Pallid scroller.
Widgets.DEFAULT_SCROLLBAR_SIZE = DEFAULT_SIZE

--- Returns the clamped track inset for a bar.
--- @param bar PallidScrollBar Scrollbar whose margin is resolved.
--- @return number inset Pixels trimmed from every track edge.
local function insetOf(bar)
    local size = math.max(0, bar.vertical and bar.w or bar.h)
    local margin = math.max(0, bar.margin or 0)
    return math.min(margin, math.floor(size * 0.25))
end

--- Draggable scrollbar. `page` is the visible fraction (0..1), `value` is the
--- scroll position (0..1). Clicking the track pages toward the cursor; the
--- thumb can be dragged. The track is inset by `margin`, so the bar never
--- touches the panel border.
---
--- Both the track and the thumb are drawn as a single rounded rectangle. The
--- one-pixel outline is a second, inset rounded rectangle rather than
--- `roundedBorder`: the border helper strokes vector arcs, and on a 6-8 px
--- wide bar those arcs read as notches instead of a clean pill.
--- @class PallidScrollBar : PallidWidget
--- @field vertical boolean True for a vertical bar, false for horizontal.
--- @field value number Normalized scroll position, 0..1.
--- @field page number Visible fraction of the content, 0..1.
--- @field minThumb number Minimum thumb length in pixels.
--- @field margin number Gap between the track and the widget edge.
--- @field dragging boolean True while the thumb is being dragged.
--- @field grab number Grab offset inside the thumb, in pixels.
--- @field onChange fun(bar: PallidScrollBar, value: number)|nil
--- @field trackColor PallidColor Track fill.
--- @field trackBorder PallidColor Track outline.
--- @field thumbColor PallidColor Idle thumb fill.
--- @field thumbHoverColor PallidColor Hovered/dragged thumb fill.
local ScrollBar = Widgets.class("ScrollBar")

--- Creates a new `ScrollBar` instance.
--- @param vertical boolean True for a vertical bar, false for horizontal.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional appearance and behaviour.
--- @field opts.onChange fun(bar: PallidScrollBar, value: number)|nil Called when the value changes.
--- @field opts.minThumb number|nil Minimum thumb length, defaults to 24.
--- @field opts.margin number|nil Gap between the track and the widget edge, defaults to 2.
--- @return PallidScrollBar bar New scrollbar instance.
function ScrollBar.new(vertical, x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, ScrollBar)
    self:init(x, y, w, h)
    self.vertical = vertical
    self.value = 0
    self.page = 1
    self.minThumb = opts.minThumb or MIN_THUMB
    self.margin = opts.margin or 2
    self.onChange = opts.onChange
    self.dragging = false
    self.grab = 0

    self.trackColor = Pallid.UI.Color.surfaceMuted
    self.trackBorder = Pallid.UI.Color.border
    self.thumbColor = Pallid.UI.Color.primary
    self.thumbHoverColor = Pallid.UI.Color.primaryStrong
    return self
end

--- Factory shortcut for `ScrollBar.new`.
--- @param vertical boolean True for a vertical bar, false for horizontal.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional appearance and behaviour; see `ScrollBar.new`.
--- @return PallidScrollBar bar New scrollbar instance.
function Widgets.scrollBar(vertical, x, y, w, h, opts)
    return ScrollBar.new(vertical, x, y, w, h, opts)
end

--- Inner track length in pixels, after the margin.
--- @return number length Usable track length; at least one pixel.
function ScrollBar:trackLength()
    local inset = insetOf(self)
    if self.vertical then
        return math.max(1, self.h - inset * 2)
    end
    return math.max(1, self.w - inset * 2)
end

--- Returns the thumb length for the current visible fraction.
--- @return number length Thumb length in pixels, clamped to the track.
function ScrollBar:thumbLength()
    local track = self:trackLength()
    local page = math.max(0, math.min(1, self.page or 1))
    local length = page * track
    local minThumb = math.max(0, self.minThumb or MIN_THUMB)
    if length < minThumb then
        length = minThumb
    end
    if length > track then
        length = track
    end
    return length
end

--- Returns the thumb offset along the track.
--- @return number offset Offset in pixels from the track start.
function ScrollBar:thumbOffset()
    local value = math.max(0, math.min(1, self.value or 0))
    return value * (self:trackLength() - self:thumbLength())
end

--- Returns the thumb rectangle in root-local coordinates.
--- @return number x Left edge of the thumb.
--- @return number y Top edge of the thumb.
--- @return number w Thumb width.
--- @return number h Thumb height.
function ScrollBar:thumbRect()
    local inset = insetOf(self)
    local length = self:thumbLength()
    local offset = self:thumbOffset()
    local x, y = self:originX(), self:originY()
    if self.vertical then
        return x + inset, y + inset + offset, self.w - inset * 2, length
    end
    return x + inset + offset, y + inset, length, self.h - inset * 2
end

--- Sets the normalized scroll position.
--- @param value number New position, clamped to 0..1.
--- @return PallidScrollBar self For chaining.
function ScrollBar:setValue(value)
    if value < 0 then
        value = 0
    elseif value > 1 then
        value = 1
    end
    if value == self.value then
        return self
    end
    self.value = value
    if self.onChange ~= nil then
        self.onChange(self, value)
    end
    return self
end

--- Scrolls the thumb so its center follows the cursor.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function ScrollBar:scrollToPoint(px, py)
    local space = self:trackLength() - self:thumbLength()
    if space <= 0 then
        self:setValue(0)
        return
    end

    local inset = insetOf(self)
    local position
    if self.vertical then
        position = py - self:originY() - inset - self.grab
    else
        position = px - self:originX() - inset - self.grab
    end
    self:setValue(position / space)
end

--- Starts a thumb drag or pages the track toward the cursor.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the press was accepted.
function ScrollBar:onDown(px, py, button)
    if not self.enabled then
        return false
    end
    -- A right click must not start a drag; consume it so it cannot fall
    -- through to the row context menu.
    if button == "right" then
        return true
    end
    if self:trackLength() - self:thumbLength() <= 0 then
        return false
    end

    local tx, ty, tw, th = self:thumbRect()
    local onThumb = px >= tx and px < tx + tw and py >= ty and py < ty + th

    if onThumb then
        self.grab = (self.vertical and (py - ty) or (px - tx))
    else
        self.grab = self:thumbLength() * 0.5
        self:scrollToPoint(px, py)
    end

    self.dragging = true
    return true
end

--- Moves the thumb while a drag is active.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function ScrollBar:onMove(px, py)
    if self.dragging then
        self:scrollToPoint(px, py)
    end
end

--- Finishes a drag.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function ScrollBar:onUp(px, py)
    self.dragging = false
end

--- Replaces the thumb colour.
--- @param color PallidColor New thumb colour.
--- @return PallidScrollBar self For chaining.
function ScrollBar:setThumbColor(color)
    self.thumbColor = color
    return self
end

--- Draws a pill-shaped track with a one-pixel inset outline and the thumb.
--- @param el ISUIElement Host element the tree is rendered into.
function ScrollBar:drawSelf(el)
    -- Resolve the inset once; drawing and hit-testing must use the same value.
    local inset = insetOf(self)
    local x, y = self:originX(), self:originY()
    local w = self.w - inset * 2
    local h = self.h - inset * 2
    if w <= 0 or h <= 0 then
        return
    end
    local radius = math.min(w, h) * 0.5

    Pallid.UI.roundedRect(el, x + inset, y + inset, w, h, radius, self:shade(self.trackBorder))
    if w > 3 and h > 3 then
        Pallid.UI.roundedRect(el, x + inset + 1, y + inset + 1, w - 2, h - 2, radius - 1, self:shade(self.trackColor))
    end

    local tx, ty, tw, th = self:thumbRect()
    local source = (self.dragging or self._hover) and self.thumbHoverColor or self.thumbColor
    Pallid.UI.roundedRect(el, tx, ty, tw, th, math.min(tw, th) * 0.5, self:shade(source))
end
