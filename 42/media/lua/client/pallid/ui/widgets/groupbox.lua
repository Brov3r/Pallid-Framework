require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/geometry"
require "pallid/ui/api/clip"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local RECT_SHAPE = Pallid.UI.Shape.rect()
local PADDING = 10
local TITLE_HEIGHT = 18
-- The frame starts a little below the top edge: the title glyphs sit on that
-- line, so without this offset they would stick out above the widget bounds.
local FRAME_TOP = 7

--- Returns the clipped content rectangle in root-local coordinates.
--- @param group PallidGroupBox Group whose content area is measured.
--- @return number x Left edge of the content area.
--- @return number y Top edge of the content area.
--- @return number w Content width.
--- @return number h Content height.
local function contentRect(group)
    return group:originX() + PADDING,
        group:originY() + TITLE_HEIGHT,
        math.max(0, group.w - PADDING * 2),
        math.max(0, group.h - TITLE_HEIGHT - 1)
end

--- Frame around related widgets with the title sitting on the top border.
--- Children are positioned relative to the padded content area.
--- @class PallidGroupBox : PallidWidget
--- @field title string Title text drawn on the top border.
--- @field fill PallidColor|nil Optional frame fill; nil leaves the interior transparent.
--- @field borderColor PallidColor Frame border.
--- @field radius number Corner radius.
--- @field titleBackground PallidColor Patch drawn behind the title.
--- @field titleStyle PallidTextStyle Reused title text style.
local GroupBox = Widgets.class("GroupBox")

--- Creates a new `GroupBox` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param title string Title text drawn on the top border.
--- @param opts table|nil Optional appearance.
--- @field opts.background PallidColor|nil Optional frame fill; no fill by default.
--- @field opts.border PallidColor|nil Frame border.
--- @field opts.radius number|nil Corner radius, defaults to 6.
--- @field opts.titleBackground PallidColor|nil Patch behind the title.
--- @return PallidGroupBox group New group box instance.
function GroupBox.new(x, y, w, h, title, opts)
    opts = opts or {}
    local self = setmetatable({}, GroupBox)
    self:init(x, y, w, h)
    self.title = title or ""

    if opts.background ~= nil then
        local background = opts.background
        self.fill = { r = background.r, g = background.g, b = background.b, a = background.a }
    end
    local border = opts.border or Pallid.UI.Color.border
    self.borderColor = { r = border.r, g = border.g, b = border.b, a = border.a }
    self.radius = opts.radius or 6

    -- Opaque patch under the title so the border line is interrupted where the
    -- title sits, without a translucent box behind the glyphs.
    local titleBackground = opts.titleBackground or Pallid.UI.Color.surface
    self.titleBackground = { r = titleBackground.r, g = titleBackground.g, b = titleBackground.b, a = 1 }

    self.titleStyle = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.textMuted,
        alignH = "left",
        alignV = "middle",
    }
    return self
end

--- Factory shortcut for `GroupBox.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param title string Title text drawn on the top border.
--- @param opts table|nil Optional appearance; see `GroupBox.new`.
--- @return PallidGroupBox group New group box instance.
function Widgets.groupBox(x, y, w, h, title, opts)
    return GroupBox.new(x, y, w, h, title, opts)
end

--- Children live inside the padded frame, below the title line.
--- @param el ISUIElement Host element the tree is rendered into.
function GroupBox:drawChildren(el)
    local list = self.children
    if list == nil then
        return
    end
    local cx, cy, cw, ch = contentRect(self)
    if cw <= 0 or ch <= 0 then
        return
    end
    local entered = Pallid.UI.clip(el, RECT_SHAPE, cx, cy, cw, ch)
    for i = 1, #list do
        local child = list[i]
        if child.overlay ~= true then
            child:draw(el, cx, cy)
        end
    end
    if (self._overlayCount or 0) > 0 then
        for i = 1, #list do
            local child = list[i]
            if child.overlay == true then
                child:draw(el, cx, cy)
            end
        end
    end
    if entered then
        Pallid.UI.clipEnd(el)
    end
end

--- Finds the child that handles a press at the given point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this group's parent.
--- @param oy number Origin Y of this group's parent.
--- @param button string|nil "left" or "right".
--- @return PallidWidget|nil target Widget that accepted the press.
function GroupBox:findDown(px, py, ox, oy, button)
    self._ox = ox
    self._oy = oy
    if not self.visible or not self:isInside(px, py) then
        return nil
    end
    if not self.enabled then
        return self
    end
    local cx, cy, cw, ch = contentRect(self)
    if px < cx or px >= cx + cw or py < cy or py >= cy + ch then
        return nil
    end

    local list = self.children
    if list ~= nil then
        for i = #list, 1, -1 do
            local hit = list[i]:findDown(px, py, cx, cy, button)
            if hit ~= nil then
                return hit
            end
        end
    end
    return nil
end

--- Finds the child that handles hover at the given point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this group's parent.
--- @param oy number Origin Y of this group's parent.
--- @return PallidWidget|nil hovered Widget under the cursor.
function GroupBox:findHover(px, py, ox, oy)
    self._ox = ox
    self._oy = oy
    if not self.visible or not self:isInside(px, py) then
        return nil
    end
    if not self.enabled then
        return self
    end

    local cx, cy, cw, ch = contentRect(self)
    if px >= cx and px < cx + cw and py >= cy and py < cy + ch then
        local list = self.children
        if list ~= nil then
            for i = #list, 1, -1 do
                local hit = list[i]:findHover(px, py, cx, cy)
                if hit ~= nil then
                    return hit
                end
            end
        end
    end

    return self
end

--- Finds the child that handles a wheel event at the given point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this group's parent.
--- @param oy number Origin Y of this group's parent.
--- @return PallidWidget|nil target Widget that handles the wheel, if any.
function GroupBox:findWheel(px, py, ox, oy)
    self._ox = ox
    self._oy = oy
    if not self.visible or not self.enabled or not self:isInside(px, py) then
        return nil
    end
    local cx, cy, cw, ch = contentRect(self)
    if px < cx or px >= cx + cw or py < cy or py >= cy + ch then
        return nil
    end
    local list = self.children
    if list ~= nil then
        for i = #list, 1, -1 do
            local hit = list[i]:findWheel(px, py, cx, cy)
            if hit ~= nil then
                return hit
            end
        end
    end
    return nil
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the tree is rendered into.
function GroupBox:drawSelf(el)
    local x, y = self:originX(), self:originY()
    local frameY = y + FRAME_TOP
    local frameH = math.max(0, self.h - FRAME_TOP)
    if self.fill ~= nil then
        Pallid.UI.roundedRect(el, x, frameY, self.w, frameH, self.radius, self:shade(self.fill))
    end
    Pallid.UI.roundedBorder(el, x, frameY, self.w, frameH, self.radius, 1, self:shade(self.borderColor, 2))

    if self.title == "" then
        return
    end

    local font = self.titleStyle.font
    local maxTitleWidth = math.max(0, self.w - PADDING * 2)
    local title = Pallid.UI.truncateText(self.title, font, maxTitleWidth)
    if title == "" then
        return
    end
    local textWidth = getTextManager():MeasureStringX(font, title)
    local titleX = x + PADDING

    -- Erase the border segment behind the title, then draw the title on the
    -- line: the border looks interrupted exactly where the text is. The patch
    -- is clamped to the frame so a long title cannot paint outside it.
    local patchX = math.max(x, titleX - 6)
    local patchW = math.min(x + self.w - patchX, textWidth + 12)
    if patchW > 0 then
        Pallid.UI.rect(el, patchX, frameY - FRAME_TOP + 1, patchW, FRAME_TOP * 2 - 2,
            self:shade(self.titleBackground))
    end

    local base = self.titleStyle.color
    self.titleStyle.color = self:shade(base)
    Pallid.UI.text(el, title, titleX, frameY, self.titleStyle)
    self.titleStyle.color = base
end
