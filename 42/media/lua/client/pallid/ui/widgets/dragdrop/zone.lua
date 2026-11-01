require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local Color    = Pallid.UI.Color

--- Highlighting target for a drag payload. Zones register while attached and
--- unregister on detach; Kahlua has no weak tables, so this explicit lifecycle
--- is what keeps the process-wide registry bounded.
---
--- A zone that rejects a payload does not block an accepting zone below it.
---@class PallidDropZone : PallidWidget
--- @field accepts fun(payload: table, source: PallidWidget|nil, px: number, py: number): boolean|nil
--- @field onDrop fun(payload: table, source: PallidWidget|nil, px: number, py: number)|nil
--- @field onDragEnter fun(payload: table, source: PallidWidget|nil, px: number, py: number)|nil
--- @field onDragMove fun(payload: table, source: PallidWidget|nil, px: number, py: number)|nil
--- @field onDragLeave fun(payload: table, source: PallidWidget|nil)|nil
--- @field color PallidColor Outline color.
--- @field invalidColor PallidColor Outline color for an invalid drop.
--- @field alwaysOutline boolean True draws the outline without a drag.
--- @field silent boolean True disables all painting (used by embedded drop areas).
--- @field priority number|nil Higher wins over registration order.
--- @field _dragOver boolean True while a payload hovers over the zone.
--- @field _dragValid boolean True when the hovering payload is accepted.
local DropZone = Widgets.class("DropZone")

--- Creates a new `DropZone` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Drop zone options.
--- @field opts.accepts fun(payload: table, source: PallidWidget|nil, px: number, py: number): boolean|nil Defaults to accepting everything.
--- @field opts.onDrop fun(payload: table, source: PallidWidget|nil, px: number, py: number)|nil
--- @field opts.onDragEnter fun(payload: table, source: PallidWidget|nil, px: number, py: number)|nil
--- @field opts.onDragMove fun(payload: table, source: PallidWidget|nil, px: number, py: number)|nil
--- @field opts.onDragLeave fun(payload: table, source: PallidWidget|nil)|nil
--- @field opts.color PallidColor|nil Valid highlight. Defaults to Color.accent.
--- @field opts.invalidColor PallidColor|nil Defaults to Color.danger.
--- @field opts.background PallidColor|nil Idle fill.
--- @field opts.border PallidColor|nil Idle border.
--- @field opts.radius number|nil Defaults to 4.
--- @field opts.alwaysOutline boolean|nil Draw the idle outline even without a drag.
--- @field opts.silent boolean|nil Disable all painting.
--- @field opts.priority number|nil Higher priority wins when zones overlap.
--- @return PallidDropZone New drop zone.
function DropZone.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, DropZone)
    self:init(x, y, w, h)

    self.accepts       = opts.accepts
    self.onDrop        = opts.onDrop
    self.onDragEnter   = opts.onDragEnter
    self.onDragMove    = opts.onDragMove
    self.onDragLeave   = opts.onDragLeave
    self.color         = opts.color or Color.accent
    self.invalidColor  = opts.invalidColor or Color.danger
    self.background    = opts.background
    self.border        = opts.border
    self.radius        = opts.radius == nil and 4 or opts.radius
    self.alwaysOutline = opts.alwaysOutline == true
    self.silent        = opts.silent == true
    self.priority      = opts.priority
    self._dragOver     = false
    self._dragValid    = false

    -- Precompute every derived colour once; draw calls never allocate.
    self._idleBorder  = Color.withAlpha(self.border or self.color, 0.45)
    self._validFill   = Color.withAlpha(self.color, 0.16)
    self._invalidFill = Color.withAlpha(self.invalidColor, 0.14)
    return self
end

--- Factory shortcut for `DropZone.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Options; see `DropZone.new`.
--- @return PallidDropZone New drop zone.
function Widgets.dropZone(x, y, w, h, opts)
    return DropZone.new(x, y, w, h, opts)
end

--- Registers the zone once it becomes reachable from a root.
function DropZone:onAttach()
    if Pallid.UI.DragDrop ~= nil then
        Pallid.UI.DragDrop._registerZone(self)
    end
end

--- Releases the registry slot when the subtree is removed or re-parented.
function DropZone:onDetach()
    if Pallid.UI.DragDrop ~= nil then
        Pallid.UI.DragDrop._unregisterZone(self)
    end
end

--- @param payload table Drag payload.
--- @param source PallidWidget|nil Widget that owns the drag.
--- @param px number Root-local pointer X.
--- @param py number Root-local pointer Y.
--- @return boolean accepted True when the drop was accepted.
function DropZone:_accept(payload, source, px, py)
    local accepts = self.accepts
    if accepts == nil then
        return true
    end
    if type(accepts) == "function" then
        return accepts(payload, source, px, py) ~= false
    end
    return accepts ~= false
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element used for drawing.
function DropZone:drawSelf(el)
    if self.silent then
        return
    end

    local x, y = self:originX(), self:originY()
    local radius = self.radius
    local fill = self.background

    if fill ~= nil then
        if radius > 0 then
            Pallid.UI.roundedRect(el, x, y, self.w, self.h, radius, self:shade(fill))
        else
            Pallid.UI.rect(el, x, y, self.w, self.h, self:shade(fill))
        end
    end

    local outline
    if self._dragOver then
        local tint = self._dragValid and self.color or self.invalidColor
        fill = self._dragValid and self._validFill or self._invalidFill
        outline = tint
        if radius > 0 then
            Pallid.UI.roundedRect(el, x, y, self.w, self.h, radius, self:shade(fill))
        else
            Pallid.UI.rect(el, x, y, self.w, self.h, self:shade(fill))
        end
    elseif self.border ~= nil then
        outline = self.border
    elseif self.alwaysOutline then
        outline = self._idleBorder
    end

    if outline ~= nil then
        if radius > 0 then
            Pallid.UI.roundedBorder(el, x, y, self.w, self.h, radius, 1, self:shade(outline))
        else
            Pallid.UI.border(el, x, y, self.w, self.h, 1, self:shade(outline))
        end
    end
end

return DropZone
