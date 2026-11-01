require "pallid/ui/internal"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Invisible container that stacks children vertically with equal spacing.
--- Children with a `weight` (for example Spacer) share the leftover height;
--- fixed children keep their own height and always get the full inner width.
---
--- Layout is opt-in and explicit: the box does not size itself from its
--- children unless `autoSize`/`autoWidth`/`autoHeight` is requested, and it
--- does not re-run after a child changes size unless `layout()` is called.
--- Hidden children still occupy their slot. If fixed children do not fit, they
--- keep their own height and may overflow the box.
--- @class PallidVBox : PallidWidget
--- @field padding number Inner inset on every side in pixels.
--- @field spacing number Gap between neighbouring children in pixels.
--- @field align "stretch"|"start"|"center"|"end" Cross-axis child placement.
--- @field autoWidth boolean True shrinks/grows the box width to the widest child.
--- @field autoHeight boolean True shrinks/grows the box height to its content.
local VBox = Widgets.class("VBox")

--- Creates a new `VBox` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels; children are stretched to the inner width.
--- @param h number Height in pixels; the space distributed between children.
--- @param opts table|nil Optional layout metrics.
--- @field opts.padding number|nil Inner inset, defaults to 0.
--- @field opts.spacing number|nil Gap between children, defaults to 4.
--- @field opts.align "stretch"|"start"|"center"|"end"|nil Cross-axis placement,
---                     defaults to "stretch".
--- @field opts.autoSize boolean|nil True fits both axes to the children.
--- @field opts.autoWidth boolean|nil True fits only the width to the widest child.
--- @field opts.autoHeight boolean|nil True fits only the height to the children.
--- @return PallidVBox box New vertical layout box.
function VBox.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, VBox)
    self:init(x, y, w, h)
    self.padding = opts.padding or 0
    self.spacing = opts.spacing or 4
    self.align = opts.align or "stretch"
    local auto = opts.autoSize == true
    self.autoWidth = auto or opts.autoWidth == true
    self.autoHeight = auto or opts.autoHeight == true
    return self
end

--- Factory shortcut for `VBox.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional layout metrics; see `VBox.new`.
--- @return PallidVBox box New vertical layout box.
function Widgets.vbox(x, y, w, h, opts)
    return VBox.new(x, y, w, h, opts)
end

--- Adds a child and re-runs the layout.
--- @param child PallidWidget Widget to attach.
--- @return PallidWidget child The same widget, for chaining.
function VBox:add(child)
    Widgets.Widget.add(self, child)
    self:layout()
    return child
end

--- Detaches a child and re-runs the layout so the freed space is reclaimed.
--- @param child PallidWidget Widget to detach.
function VBox:remove(child)
    Widgets.Widget.remove(self, child)
    self:layout()
end

--- Resizes the box and re-runs the layout.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidVBox self For chaining.
function VBox:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:layout()
    return self
end

--- Places children from top to bottom: fixed heights first, then the leftover
--- height split between weighted children. Call it after changing a child size.
---
--- With `autoWidth`/`autoHeight` the box size is derived from the children
--- first. The cross-axis position follows `align`; the main-axis size still
--- comes from `weight` (children without a weight keep their own height).
function VBox:layout()
    local list = self.children
    if list == nil then
        return
    end

    local padding = self.padding
    local spacing = self.spacing
    local count = #list
    local gaps = spacing * math.max(0, count - 1)

    -- Auto sizing is computed from the children's current sizes before any
    -- child is stretched; otherwise the stretched size would feed back into the
    -- next layout pass.
    if self.autoWidth then
        local widest = 0
        for i = 1, count do
            local child = list[i]
            if child.w > widest then
                widest = child.w
            end
        end
        self.w = padding * 2 + widest
    end
    if self.autoHeight then
        local content = 0
        for i = 1, count do
            content = content + list[i].h
        end
        self.h = padding * 2 + content + gaps
    end

    local available = self.h - padding * 2
    local fixed = 0
    local weights = 0

    for i = 1, count do
        local child = list[i]
        if child.weight ~= nil then
            weights = weights + child.weight
        else
            fixed = fixed + child.h
        end
    end

    local leftover = math.max(0, available - fixed - gaps)
    local cursor = padding
    local width = math.max(0, self.w - padding * 2)
    local align = self.align

    for i = 1, count do
        local child = list[i]
        local height
        if child.weight ~= nil then
            height = weights > 0 and leftover * child.weight / weights or 0
        else
            height = child.h
        end

        local childW = width
        local childX = padding
        if align ~= "stretch" then
            childW = math.min(math.max(0, child.w), width)
            if align == "center" then
                childX = padding + (width - childW) * 0.5
            elseif align == "end" then
                childX = padding + width - childW
            end
        end

        child:setBounds(childX, cursor, childW, height)
        cursor = cursor + height + spacing
    end
end
