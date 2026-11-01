require "pallid/ui/internal"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Single-content container that pins a widget to an alignment or stretches it
--- to the available box. It is the layout equivalent of CSS "fill" and is
--- useful for centring a dialog body, pinning a footer row or stretching one
--- child over a resizable panel.
---
--- Only one content widget is owned at a time; adding another replaces it.
--- @class PallidAnchor : PallidWidget
--- @field content PallidWidget|nil Current content widget.
--- @field padding number Inner inset on every side in pixels.
--- @field fillX boolean True stretches the content to the inner width.
--- @field fillY boolean True stretches the content to the inner height.
--- @field alignH "left"|"center"|"right" Horizontal placement when not filling.
--- @field alignV "top"|"middle"|"bottom" Vertical placement when not filling.
--- @field autoSize boolean True grows the container to a non-filled content size.
local Anchor = Widgets.class("Anchor")

--- Creates a new `Anchor` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Layout and content settings.
--- @field opts.content PallidWidget|nil Initial content widget.
--- @field opts.padding number|nil Inner inset, defaults to 0.
--- @field opts.fillX boolean|nil Stretch the content horizontally.
--- @field opts.fillY boolean|nil Stretch the content vertically.
--- @field opts.alignH "left"|"center"|"right"|nil Horizontal placement.
--- @field opts.alignV "top"|"middle"|"bottom"|nil Vertical placement.
--- @field opts.autoSize boolean|nil Grow both axes to the content.
--- @return PallidAnchor anchor New anchor container.
function Anchor.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, Anchor)
    self:init(x, y, w or 0, h or 0)
    self.padding = math.max(0, opts.padding or 0)
    self.fillX = opts.fillX == true
    self.fillY = opts.fillY == true
    self.alignH = opts.alignH or "left"
    self.alignV = opts.alignV or "top"
    self.autoSize = opts.autoSize == true
    self.content = nil
    if opts.content ~= nil then
        self:setContent(opts.content)
    end
    return self
end

--- Factory shortcut for `Anchor.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Layout and content settings; see `Anchor.new`.
--- @return PallidAnchor anchor New anchor container.
function Widgets.anchor(x, y, w, h, opts)
    return Anchor.new(x, y, w, h, opts)
end

--- Replaces the content widget. Passing nil removes it.
--- @param content PallidWidget|nil New content widget.
--- @return PallidWidget|nil content The installed content.
function Anchor:setContent(content)
    if self.content ~= nil then
        Widgets.Widget.remove(self, self.content)
        self.content = nil
    end
    if content ~= nil then
        Widgets.Widget.add(self, content)
        self.content = content
    end
    self:layout()
    return content
end

--- Adds a child. Anchor owns exactly one content widget, so this replaces the
--- previous one and returns the new child for chaining.
--- @param child PallidWidget Widget to attach.
--- @return PallidWidget child The same widget.
function Anchor:add(child)
    self:setContent(child)
    return child
end

--- Removes the content when it is the current one.
--- @param child PallidWidget Widget to detach.
function Anchor:remove(child)
    Widgets.Widget.remove(self, child)
    if self.content == child then
        self.content = nil
    end
    self:layout()
end

--- Resizes the container and re-runs the layout.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidAnchor self For chaining.
function Anchor:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:layout()
    return self
end

--- @param content PallidWidget Content to measure.
--- @return number width Content width in pixels.
--- @return number height Content height in pixels.
function Anchor:_contentSize(content)
    local width, height = content:preferredSize(nil, nil)
    if width <= 0 then
        width = content.w
    end
    if height <= 0 then
        height = content.h
    end
    return width, height
end

--- Positions the content according to the fill/alignment settings.
function Anchor:layout()
    local content = self.content
    if content == nil then
        return
    end
    local padding = self.padding
    local innerW = math.max(0, self.w - padding * 2)
    local innerH = math.max(0, self.h - padding * 2)
    local width, height = self:_contentSize(content)

    if self.fillX then
        width = innerW
    end
    if self.fillY then
        height = innerH
    end

    local x = padding
    if not self.fillX then
        if self.alignH == "center" then
            x = padding + (innerW - width) * 0.5
        elseif self.alignH == "right" then
            x = padding + innerW - width
        end
    end

    local y = padding
    if not self.fillY then
        if self.alignV == "middle" then
            y = padding + (innerH - height) * 0.5
        elseif self.alignV == "bottom" then
            y = padding + innerH - height
        end
    end

    if self.autoSize then
        if not self.fillX then
            self.w = padding * 2 + width
            x = padding
        end
        if not self.fillY then
            self.h = padding * 2 + height
            y = padding
        end
    end

    content:setBounds(x, y, width, height)
end

--- Returns the preferred container size.
--- @param maxW number|nil Available width.
--- @param maxH number|nil Available height.
--- @return number width Preferred width in pixels.
--- @return number height Preferred height in pixels.
function Anchor:preferredSize(maxW, maxH)
    if self.content == nil then
        return self.padding * 2, self.padding * 2
    end
    local width, height = self:_contentSize(self.content)
    if self.fillX then
        width = maxW or self.w
    else
        width = width + self.padding * 2
        if maxW ~= nil and width > maxW then
            width = maxW
        end
    end
    if self.fillY then
        height = maxH or self.h
    else
        height = height + self.padding * 2
    end
    return width, height
end
