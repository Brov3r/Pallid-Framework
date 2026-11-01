require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/geometry"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/api/clip"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local RECT_SHAPE = Pallid.UI.Shape.rect()
local HEADER = 24
local PADDING = 8
local ARROW_ICON = "media/assets/ui/pallid/icons/arrow-right-04.png"

--- Returns the visible content rectangle for a section in root-local coordinates.
--- @param accordion PallidAccordion Accordion that owns the section.
--- @param section table Section entry with `_contentY` and `_visibleHeight`.
--- @return number x Left edge of the visible content.
--- @return number y Top edge of the visible content.
--- @return number w Content width after padding.
--- @return number h Visible content height.
local function contentRect(accordion, section)
    return accordion:originX() + PADDING,
        accordion:originY() + section._contentY,
        math.max(0, accordion.w - PADDING * 2),
        math.max(0, section._visibleHeight)
end

--- Stack of collapsible sections. Each section has a clickable header with an
--- arrow; the content height and alpha animate on open/close.
--- @class PallidAccordion : PallidWidget
--- @field sections table Section entries: { title, content?, height?, open? }.
--- @field headerHeight number Height of each clickable header.
--- @field onlyOne boolean True keeps at most one section open.
--- @field onChange fun(accordion: PallidAccordion, index: integer, open: boolean)|nil Called after a section is opened or closed.
--- @field hoverIndex integer Header under the cursor, 0 when none.
--- @field style PallidTextStyle Reused section title style.
--- @field arrowColor PallidColor Chevron icon tint.
--- @field arrowSize number Chevron icon box size in pixels.
local Accordion = Widgets.class("Accordion")

--- Creates a new `Accordion` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param sections table[] Each entry: { title, content, height?, open? }.
--- @param opts table|nil Optional behaviour.
--- @field opts.headerHeight number|nil Header height, defaults to 24.
--- @field opts.onlyOne boolean|nil Keeps at most one section open.
--- @field opts.onChange fun(accordion: PallidAccordion, index: integer, open: boolean)|nil Called after a section toggles.
--- @return PallidAccordion accordion New accordion instance.
function Accordion.new(x, y, w, sections, opts)
    opts = opts or {}
    local self = setmetatable({}, Accordion)
    self.sections = sections or {}
    self.headerHeight = opts.headerHeight or HEADER
    self.onlyOne = opts.onlyOne or false
    self.onChange = opts.onChange

    local total = 0
    for i = 1, #self.sections do
        local section = self.sections[i]
        section.openT = section.open and 1 or 0
        section.contentHeight = section.height or (section.content and section.content.h) or 0
        total = total + self.headerHeight + section.contentHeight * section.openT
        -- Section content is drawn manually by drawSelf, so it is not a tree
        -- child. Without a parent it would look like a frame root and reset the
        -- clip stack in the middle of the section's stencil.
        if section.content ~= nil then
            section.content.parent = self
        end
    end

    self:init(x, y, w, total)

    self.headerColor = Pallid.UI.Color.surfaceMuted
    self.headerHover = Pallid.UI.Color.accentSoft
    self.borderColor = Pallid.UI.Color.border
    self.arrowColor = Pallid.UI.Color.textMuted
    -- 14 px keeps the 2 px stroke of the source icon at the previous weight.
    self.arrowSize = math.max(10, math.min(14, self.headerHeight - 10))
    self._arrowTexture = Pallid.UI.Textures.get(ARROW_ICON)
    -- Reused rotation options for the chevron; never allocated inside draw.
    self._arrowOpts = { mode = "fit", rotation = 0 }
    self.style = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.text,
        alignH = "left",
        alignV = "middle",
    }
    self.hoverIndex = 0
    self:layout()
    return self
end

--- Factory shortcut for `Accordion.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param sections table[] Section entries; see `Accordion.new`.
--- @param opts table|nil Optional behaviour; see `Accordion.new`.
--- @return PallidAccordion accordion New accordion instance.
function Widgets.accordion(x, y, w, sections, opts)
    return Accordion.new(x, y, w, sections, opts)
end

--- Section contents are owned outside `children`; forward the lifecycle so
--- registries inside them (drop zones) stay in sync.
function Accordion:onAttach()
    for i = 1, #self.sections do
        local content = self.sections[i].content
        if content ~= nil then
            content:_notifyAttached()
        end
    end
end

--- Cleans up when the widget is detached from the tree.
function Accordion:onDetach()
    for i = 1, #self.sections do
        local content = self.sections[i].content
        if content ~= nil then
            content:_notifyDetached()
        end
    end
end

--- Places sections and updates the total height.
function Accordion:layout()
    local y = 0
    local padding = PADDING
    local innerWidth = self.w - padding * 2

    for i = 1, #self.sections do
        local section = self.sections[i]
        if section.height == nil and section.content ~= nil then
            section.contentHeight = section.content.h
        end
        section._headerY = y
        y = y + self.headerHeight

        local visible = section.contentHeight * section.openT
        section._contentY = y
        section._visibleHeight = visible
        if section.content ~= nil then
            section.content:setBounds(padding, section._contentY, innerWidth, section.contentHeight)
        end
        y = y + visible
    end

    self.h = math.ceil(y)
end

--- Opens or closes a section.
--- @param index integer One-based section index.
--- @param open boolean New open state.
--- @param silent boolean|nil True skips the `onChange` callback.
--- @return PallidAccordion self For chaining.
function Accordion:setOpen(index, open, silent)
    local section = self.sections[index]
    if section == nil or section.open == open then
        return self
    end
    section.open = open
    if open and self.onlyOne then
        for i = 1, #self.sections do
            if i ~= index then
                self.sections[i].open = false
            end
        end
    end
    if not silent and self.onChange ~= nil then
        self.onChange(self, index, open)
    end
    return self
end

--- Eases the section open/close animation and re-lays out only while something
--- is moving. Per-frame so the reveal is smooth; a settled accordion costs
--- nothing here.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function Accordion:onAnimate(now, dt)
    local moving = false
    for i = 1, #self.sections do
        local section = self.sections[i]
        local target = section.open and 1 or 0
        if section.openT ~= target then
            section.openT = Widgets.approach(section.openT, target, 14, dt)
            -- The stencil is truncated to whole pixels, so an animation that
            -- stops at 0.99 reveals one final pixel on a later frame. Snap the
            -- remaining sub-pixel distance now.
            if section.contentHeight > 0
                and math.abs(target - section.openT) * section.contentHeight < 1 then
                section.openT = target
            end
            moving = true
        end
    end
    if moving then
        self:layout()
    end
end

--- Propagates the tick to section contents and refreshes the layout after
--- non-animated changes (content swapped, size changed).
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous tick, 0..0.1.
function Accordion:onUpdate(now, dt)
    for i = 1, #self.sections do
        local section = self.sections[i]
        if section.content ~= nil and (section.open or section.openT > 0) then
            section.content:update(now)
        end
    end
    self:layout()
end

--- Section content is drawn manually and is not in `children`, so animations
--- inside a section need explicit forwarding. The base call keeps the
--- accordion's own `onAnimate` (the openT easing) alive. Closed sections are
--- skipped: they are not drawn, and their `openT` is already settled at zero.
--- @param now number Current time in seconds.
function Accordion:updateAnimations(now)
    if not self.visible then
        return
    end
    Widgets.Widget.updateAnimations(self, now)
    for i = 1, #self.sections do
        local section = self.sections[i]
        if section.content ~= nil and section.openT > 0 then
            section.content:updateAnimations(now)
        end
    end
end

--- Handles a pointer press inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the header consumed the press.
function Accordion:onDown(px, py, button)
    if not self.enabled then
        return false
    end
    -- A right click on a header must not toggle the section.
    if button == "right" then
        return true
    end
    local localY = py - self:originY()
    for i = 1, #self.sections do
        local section = self.sections[i]
        if localY >= section._headerY and localY < section._headerY + self.headerHeight then
            self:setOpen(i, not section.open)
            return true
        end
    end
    return false
end

--- Updates the hovered header from the cursor position.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Accordion:onHoverMove(px, py)
    local localY = py - self:originY()
    self.hoverIndex = 0
    for i = 1, #self.sections do
        local section = self.sections[i]
        if localY >= section._headerY and localY < section._headerY + self.headerHeight then
            self.hoverIndex = i
            return
        end
    end
end

--- Clears hover state when the pointer leaves.
function Accordion:onHoverEnd()
    self.hoverIndex = 0
    Widgets.Widget.onHoverEnd(self)
end

--- Shows or hides the native input boxes.
--- @param visible boolean False hides native boxes in every section.
function Accordion:setNativeVisible(visible)
    for i = 1, #self.sections do
        local content = self.sections[i].content
        if content ~= nil then
            content:setNativeVisible(visible)
        end
    end
end

--- Unfocuses every native text box in the subtree.
function Accordion:blurNative()
    for i = 1, #self.sections do
        local content = self.sections[i].content
        if content ~= nil then
            content:blurNative()
        end
    end
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the tree is rendered into.
function Accordion:drawSelf(el)
    local x, y = self:originX(), self:originY()

    for i = 1, #self.sections do
        local section = self.sections[i]
        local headerY = y + section._headerY

        local headerColor = i == self.hoverIndex and self.headerHover or self.headerColor
        Pallid.UI.rect(el, x, headerY, self.w, self.headerHeight, self:shade(headerColor))
        Pallid.UI.rect(el, x, headerY + self.headerHeight - 1, self.w, 1, self:shade(self.borderColor))

        local arrowX = x + 12
        local arrowY = headerY + self.headerHeight * 0.5
        local arrowSize = self.arrowSize
        local arrowOpts = self._arrowOpts
        -- One arrow rotated by the eased amount keeps the glyph continuous
        -- instead of swapping two textures mid-motion.
        arrowOpts.rotation = 90 * section.openT
        Pallid.UI.texture(
            el,
            self._arrowTexture,
            arrowX - arrowSize * 0.5,
            arrowY - arrowSize * 0.5,
            arrowSize,
            arrowSize,
            self:shade(self.arrowColor),
            arrowOpts
        )

        local base = self.style.color
        local baseMaxWidth = self.style.maxWidth
        self.style.color = self:shade(base)
        self.style.maxWidth = math.max(0, self.w - 24 - PADDING)
        Pallid.UI.text(el, section.title, x + 24, headerY + self.headerHeight * 0.5, self.style)
        self.style.maxWidth = baseMaxWidth
        self.style.color = base

        if section.openT > 0.001 and section.content ~= nil then
            local contentX, contentY, contentW, contentH = contentRect(self, section)
            local visible = math.ceil(contentH)
            if contentW > 0 and visible > 0 then
                local entered = Pallid.UI.clip(el, RECT_SHAPE, contentX, contentY, contentW, visible)
                section.content:draw(el, x, y)
                if entered then
                    Pallid.UI.clipEnd(el)
                end
            end
        end
    end
end

--- Finds the child that handles a press at the given point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this accordion's parent.
--- @param oy number Origin Y of this accordion's parent.
--- @param button string|nil "left" or "right".
--- @return PallidWidget|nil target Widget that accepted the press.
function Accordion:findDown(px, py, ox, oy, button)
    self._ox = ox
    self._oy = oy
    if not self.visible or not self:isInside(px, py) then
        return nil
    end
    if not self.enabled then
        return self
    end

    local localY = py - self:originY()
    for i = 1, #self.sections do
        local section = self.sections[i]
        if localY >= section._headerY and localY < section._headerY + self.headerHeight then
            if self:onDown(px, py, button) then
                return self
            end
            return nil
        end
        if section.openT > 0.5 and section.content ~= nil then
            local cx, cy, cw, ch = contentRect(self, section)
            if px >= cx and px < cx + cw and py >= cy and py < cy + ch then
                local hit = section.content:findDown(px, py, self:originX(), self:originY(), button)
                if hit ~= nil then
                    return hit
                end
            end
        end
    end
    return nil
end

--- Finds the child that handles hover at the given point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this accordion's parent.
--- @param oy number Origin Y of this accordion's parent.
--- @return PallidWidget|nil hovered Widget under the cursor.
function Accordion:findHover(px, py, ox, oy)
    self._ox = ox
    self._oy = oy
    if not self.visible or not self:isInside(px, py) then
        return nil
    end
    if not self.enabled then
        return self
    end

    local localY = py - self:originY()
    for i = 1, #self.sections do
        local section = self.sections[i]
        if localY >= section._headerY and localY < section._headerY + self.headerHeight then
            return self
        end
        if section.openT > 0.5 and section.content ~= nil then
            local cx, cy, cw, ch = contentRect(self, section)
            if px >= cx and px < cx + cw and py >= cy and py < cy + ch then
                local hit = section.content:findHover(px, py, self:originX(), self:originY())
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
--- @param ox number Origin X of this accordion's parent.
--- @param oy number Origin Y of this accordion's parent.
--- @return PallidWidget|nil target Widget that handles the wheel, if any.
function Accordion:findWheel(px, py, ox, oy)
    self._ox = ox
    self._oy = oy
    if not self.visible or not self.enabled or not self:isInside(px, py) then
        return nil
    end
    for i = 1, #self.sections do
        local section = self.sections[i]
        if section.content ~= nil then
            local cx, cy, cw, ch = contentRect(self, section)
            if px >= cx and px < cx + cw and py >= cy and py < cy + ch then
                local hit = section.content:findWheel(px, py, self:originX(), self:originY())
                if hit ~= nil then
                    return hit
                end
            end
        end
    end
    return nil
end
