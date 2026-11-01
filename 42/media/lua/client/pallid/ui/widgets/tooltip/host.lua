require "pallid/ui/internal"
require "pallid/ui/animation/util"
require "ISUI/ISUIElement"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

--- Native, always-on-top surface that paints Pallid tooltips above text boxes.
--- The tooltip instance owns its state; the host only asks it to draw and hides
--- itself once the fade-out reports `isClosed`.
--- @class PallidTooltipHostElement : ISUIElement
local TooltipHostElement = ISUIElement:derive("PallidTooltipHost")

--- Creates a new `TooltipHostElement` instance.
--- @return PallidTooltipHostElement element New hidden tooltip surface.
function TooltipHostElement:new()
    local o = ISUIElement:new(0, 0, getCore():getScreenWidth(), getCore():getScreenHeight())
    setmetatable(o, self)
    self.__index = self
    o.wantMouseEvents = false
    o.wantExtraMouseEvents = false
    o._tooltip = nil
    o.visible = false
    return o
end

--- Paints the current tooltip. A stale host hides itself so a missing root frame
--- cannot leave a tooltip floating over the game.
function TooltipHostElement:render()
    local tooltip = self._tooltip
    if tooltip == nil then
        return
    end
    local now = Pallid.UI.Anim.now()
    if now - (self._updatedAt or 0) > 0.25 then
        self._tooltip = nil
        self:setVisible(false)
        return
    end
    tooltip:draw(self, self._x or 0, self._y or 0, now, self._maxW, self._maxH)
    if tooltip:isClosed() then
        self._tooltip = nil
        self:setVisible(false)
    end
end

--- Global tooltip surface. Draw calls update it; it renders after native boxes.
--- @class PallidTooltipHost
local Host = { _element = nil }
Pallid.UI.TooltipHost = Host

--- Shows `tooltip` at screen coordinates. Called every frame while hovered.
--- @param tooltip PallidTooltip Tooltip to paint.
--- @param x number Anchor X in screen coordinates.
--- @param y number Anchor Y in screen coordinates.
--- @param now number Current time in seconds.
--- @param maxW number Right clamp bound.
--- @param maxH number Bottom clamp bound.
function Host.show(tooltip, x, y, now, maxW, maxH)
    local el = Host._element
    if el == nil then
        el = TooltipHostElement:new()
        Host._element = el
    end
    local wasVisible = el.visible
    local changed = el._tooltip ~= tooltip
    tooltip:show(now)
    el:setX(0)
    el:setY(0)
    el:setWidth(getCore():getScreenWidth())
    el:setHeight(getCore():getScreenHeight())
    el._tooltip = tooltip
    el._x = x
    el._y = y
    el._maxW = maxW
    el._maxH = maxH
    el._updatedAt = now
    if not el._added then
        el:addToUIManager()
        el:setAlwaysOnTop(true)
        el._added = true
    end
    if not wasVisible or changed then
        el:bringToTop()
    end
    el:setVisible(true)
end

--- Starts the fade-out of the current tooltip. The host keeps painting until
--- `Tooltip:isClosed` turns true; the next hover wakes the same tooltip again.
function Host.hide()
    local el = Host._element
    if el == nil or el._tooltip == nil then
        return
    end
    el._tooltip:beginClose()
    el._updatedAt = Pallid.UI.Anim.now()
end
