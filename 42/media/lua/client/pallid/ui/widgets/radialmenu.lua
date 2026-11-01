require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/animation/ease"
require "pallid/ui/animation/util"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local TAU = math.pi * 2
-- Sector 1 is centred on 12 o'clock; the ring itself starts half a step before.
local TOP_ANGLE = -math.pi * 0.5

local DEFAULT_INNER_RADIUS = 38
local DEFAULT_OUTER_RADIUS = 108
local DEFAULT_GAP          = 0.035
local DEFAULT_ICON_SIZE    = 20
local DEFAULT_SOUND        = "UIActivateButton"
local SHADOW_PAD           = 6
local LABEL_GAP            = 3
local TEXT_MARGIN          = 4
local MIN_LABEL_WIDTH      = 16
local TITLE_OFFSET         = 7
local OPEN_DURATION        = 0.14
local CLOSE_DURATION       = 0.11
local OPEN_SCALE           = 0.92
local HOVER_FADE           = 0.1
local ICON_OPTS            = { mode = "fit" }

-- Hover blending runs every frame, so this table is reused instead of
-- allocating a colour inside draw.
local HOVER_FILL = { r = 0, g = 0, b = 0, a = 1 }

local DEFAULT_BACKGROUND = Pallid.UI.Color.withAlpha(Pallid.UI.Color.surfaceElevated, 0.96)
local DEFAULT_SECTOR     = Pallid.UI.Color.surfaceMuted
local DEFAULT_HOVER      = Pallid.UI.Color.primarySoft
local DEFAULT_CENTER     = Pallid.UI.Color.surface

--- Defaults are cloned per instance, so mutating one menu's palette cannot
--- leak into another menu.
--- @param color PallidColor Colour to copy.
--- @return PallidColor copy Independent copy of the colour.
local function copyColor(color)
    return { r = color.r, g = color.g, b = color.b, a = color.a }
end

--- Keeps the menu centre far enough from the root edge for the whole ring,
--- shadow included, to stay reachable.
--- @param value number Requested centre coordinate.
--- @param size number Root size along the same axis; 0 when unknown.
--- @param pad number Minimum distance from the root edge.
--- @return number center Clamped centre coordinate.
local function clampCenter(value, size, pad)
    if size <= 0 then
        return value
    end
    if size <= pad * 2 then
        return size * 0.5
    end
    return math.max(pad, math.min(value, size - pad))
end

--- Radial command menu drawn above the tree through the root's `openPopup`.
---
--- The coordinates passed to `show` are the centre of the ring in root-local
--- space. Hit testing is radial, so `isInside` covers the disc only; the
--- rectangular bounds describe the popup for the overlay and native masking.
--- Sector angles, colours and label anchors are precomputed in `setSectors`,
--- so a frame only does arithmetic and draw calls. The palette is also read
--- there, so change colours before calling `setSectors` again.
--- @class PallidRadialMenu : PallidWidget
--- @field sectors table[] Sector descriptors shown around the ring.
--- @field innerRadius number Radius of the centre hub.
--- @field outerRadius number Outer radius of the ring.
--- @field gap number Empty wedge between sectors, radians.
--- @field background PallidColor Disc fill behind the sectors.
--- @field sectorColor PallidColor Default sector fill.
--- @field hoverColor PallidColor Default fill of the hovered sector.
--- @field labelColor PallidColor Sector label and icon tint.
--- @field centerColor PallidColor Centre hub fill.
--- @field disabledLabelColor PallidColor Tint for disabled sector labels.
--- @field title string Centre caption.
--- @field hint string Fallback caption under the title; the hovered sector label replaces it.
--- @field hover integer 1-based hovered sector, 0 when none.
--- @field sound string|nil Click sound name; nil silences the menu.
--- @field onSelect fun(radial: PallidRadialMenu, index: integer, sector: table)|nil Called after a sector is chosen.
--- @field onClose fun(radial: PallidRadialMenu)|nil Called whenever the menu closes.
local RadialMenu = Widgets.class("RadialMenu")

--- Creates a radial menu.
--- @param sectors table[]|nil Each: { label?, icon?, color?, disabled? }.
--- @param opts table|nil Menu options.
--- @field opts.innerRadius number|nil Inner radius of the annulus. Defaults to 38.
--- @field opts.outerRadius number|nil Outer radius of the annulus. Defaults to 108.
--- @field opts.gap number|nil Empty wedge between sectors, radians. Defaults to 0.035.
--- @field opts.background PallidColor|nil Disc behind the sectors (also seen in the gaps).
--- @field opts.sector PallidColor|nil Default sector fill.
--- @field opts.hover PallidColor|nil Default hover fill.
--- @field opts.labelColor PallidColor|nil Sector label and icon tint.
--- @field opts.centerColor PallidColor|nil Centre disc fill.
--- @field opts.title string|nil Centre caption.
--- @field opts.hint string|nil Fallback caption under the title; the hovered sector label replaces it.
--- @field opts.font UIFont|string|nil Sector label font.
--- @field opts.titleFont UIFont|string|nil Centre caption font. Defaults to medium.
--- @field opts.iconSize number|nil Sector icon box. Defaults to 20.
--- @field opts.sound string|false|nil Click sound name; false or "" silences the menu.
--- @field opts.onSelect fun(radial: PallidRadialMenu, index: integer, sector: table)|nil Called after a sector is chosen.
--- @field opts.onClose fun(radial: PallidRadialMenu)|nil Called whenever the menu closes.
--- @return PallidRadialMenu menu Configured menu.
function RadialMenu.new(sectors, opts)
    opts = opts or {}

    local self = setmetatable({}, RadialMenu)
    self:init(0, 0, 0, 0)
    self.visible = false

    self.innerRadius = math.max(0, opts.innerRadius or DEFAULT_INNER_RADIUS)
    self.outerRadius = math.max(1, opts.outerRadius or DEFAULT_OUTER_RADIUS)
    if self.innerRadius >= self.outerRadius then
        self.innerRadius = self.outerRadius * 0.5
    end
    self.gap      = math.max(0, opts.gap or DEFAULT_GAP)
    -- An icon wider than the annulus would spill into the neighbour sectors.
    self.iconSize = math.max(0, math.min(
        opts.iconSize or DEFAULT_ICON_SIZE,
        self.outerRadius - self.innerRadius
    ))

    self.background   = opts.background or copyColor(DEFAULT_BACKGROUND)
    self.sectorColor  = opts.sector or copyColor(DEFAULT_SECTOR)
    self.hoverColor   = opts.hover or copyColor(DEFAULT_HOVER)
    self.labelColor   = opts.labelColor or Pallid.UI.Color.text
    self.centerColor  = opts.centerColor or copyColor(DEFAULT_CENTER)
    self.title        = opts.title or ""
    self.hint         = opts.hint or ""
    self.onSelect     = opts.onSelect
    self.onClose      = opts.onClose
    self.sound        = opts.sound
    if self.sound == nil then
        self.sound = DEFAULT_SOUND
    elseif self.sound == false or self.sound == "" then
        self.sound = nil
    end

    self.shadowColor        = Pallid.UI.Color.withAlpha(Pallid.UI.Color.black, 0.28)
    self.disabledLabelColor = Pallid.UI.Color.withAlpha(self.labelColor, 0.4)
    self.hintColor          = Pallid.UI.Color.withAlpha(self.labelColor, 0.62)

    local textWidth = math.max(0, (self.innerRadius - 8) * 2)
    self.titleStyle = {
        font     = opts.titleFont or Pallid.UI.Fonts.medium,
        color    = self.labelColor,
        alignH   = "center",
        alignV   = "middle",
        maxWidth = textWidth,
        ellipsis = "...",
    }
    self.hintStyle = {
        font     = opts.font or Pallid.UI.Fonts.small,
        color    = self.hintColor,
        alignH   = "center",
        alignV   = "middle",
        maxWidth = textWidth,
        ellipsis = "...",
    }
    self.labelStyle = {
        font     = opts.font or Pallid.UI.Fonts.small,
        color    = self.labelColor,
        alignH   = "center",
        alignV   = "middle",
        maxWidth = 0,
        ellipsis = "...",
    }

    self.root       = nil
    self.hover      = 0
    self._count     = 0
    self._step      = 0
    self._gap       = 0
    self._start     = TOP_ANGLE
    self._data      = {}
    self._pressed   = false
    self._openedAt  = 0
    self._animating = false
    self._closing   = false
    self._closingAt = 0
    self._lastFrame = nil

    self:setSectors(sectors)
    return self
end

--- Creates a radial menu.
--- @param sectors table[]|nil Each: { label?, icon?, color?, disabled? }.
--- @param opts table|nil Menu options; see `RadialMenu.new`.
--- @return PallidRadialMenu menu Configured menu.
function Widgets.radialMenu(sectors, opts)
    return RadialMenu.new(sectors, opts)
end

--- Replaces the sectors and rebuilds every derived value: angles, per-sector
--- fill colours and label anchors. Sector tables themselves are not mutated.
--- @param sectors table[]|nil Each: { label?, icon?, color?, disabled? }.
--- @return PallidRadialMenu self This menu, for chaining.
function RadialMenu:setSectors(sectors)
    self.sectors = sectors or {}

    local count = #self.sectors
    local data = {}
    self._data = data
    self._count = count
    -- The highlight index refers to the old list; keeping it would highlight
    -- an unrelated sector after the list is replaced.
    self.hover = 0

    if count == 0 then
        self._step = 0
        self._gap = 0
        self._start = TOP_ANGLE
        self.labelStyle.maxWidth = 0
        return self
    end

    local step = TAU / count
    local gap = self.gap or DEFAULT_GAP
    if gap > step * 0.5 then
        gap = step * 0.5
    end
    local start = TOP_ANGLE - step * 0.5

    self._step = step
    self._gap = gap
    self._start = start

    -- Labels are laid out per sector: their width depends on how much room is
    -- left on the horizontal axis at the radius the label sits on.
    local midRadius = (self.innerRadius + self.outerRadius) * 0.5
    self.labelStyle.maxWidth = 0

    for i = 1, count do
        local sector = self.sectors[i]
        local label, icon, customColor
        if sector ~= nil then
            label       = sector.label
            icon        = sector.icon
            customColor = sector.color
        end

        local base = customColor or self.sectorColor
        local hoverColor
        if customColor ~= nil then
            -- A custom sector colour keeps its hue and only brightens.
            hoverColor = Pallid.UI.Color.lerp(base, Pallid.UI.Color.primaryStrong, 0.22)
        else
            hoverColor = self.hoverColor
        end
        local dim = Pallid.UI.Color.lerp(base, self.background, 0.7)
        -- Disabled sectors are not selectable but still answer the cursor, so
        -- hovering one never feels like something invisible blocks the wheel.
        local dimHover = Pallid.UI.Color.lerp(dim, base, 0.55)

        local texture, name
        if type(icon) == "string" then
            if string.find(icon, "/", 1, true) ~= nil then
                texture = Pallid.UI.Textures.get(icon)
            else
                name = icon
            end
        end

        local hasLabel = type(label) == "string" and label ~= ""
        local hasIcon  = self.iconSize > 0 and (texture ~= nil or name ~= nil)

        -- Sector i covers [start + (i-1)*step, start + i*step], so its centre
        -- is TOP_ANGLE + (i-1)*step and the icon/label block sits on that
        -- bisector, centred inside the annulus.
        local angle = TOP_ANGLE + (i - 1) * step
        local cosA, sinA = math.cos(angle), math.sin(angle)

        -- Text is axis-aligned, so on left/right sectors its box can cross the
        -- rim even when the angular chord fits: cap it by the axis room too.
        local labelW = 2 * midRadius * math.sin(step * 0.5) - 8
        local edgeRoom = self.outerRadius - math.abs(cosA) * midRadius - TEXT_MARGIN
        if edgeRoom * 2 < labelW then
            labelW = edgeRoom * 2
        end
        if labelW < MIN_LABEL_WIDTH then
            labelW = MIN_LABEL_WIDTH
        end

        data[i] = {
            a0       = start + (i - 1) * step + gap * 0.5,
            a1       = start + i * step - gap * 0.5,
            cos      = cosA,
            sin      = sinA,
            fill     = base,
            hover    = hoverColor,
            dim      = dim,
            dimHover = dimHover,
            texture  = texture,
            name     = name,
            hasIcon  = hasIcon,
            hasLabel = hasLabel,
            iconR    = midRadius,
            labelR   = midRadius,
            labelW   = labelW,
            h        = 0,
        }
    end

    return self
end

--- Opens the menu with its centre at root-local (x, y). Any other popup on the
--- same root is closed first, so a second picker cannot stay clickable. The
--- centre is clamped so the whole ring stays inside the root.
--- @param root PallidWidget|nil Root that will own the popup.
--- @param x number Requested centre X in root-local coordinates.
--- @param y number Requested centre Y in root-local coordinates.
--- @return PallidRadialMenu self This menu, for chaining.
function RadialMenu:show(root, x, y)
    if root == nil then
        return self
    end
    if self._count == 0 then
        -- Opening an empty ring would register an invisible popup that blocks
        -- every click on the root.
        self:close()
        Pallid.log("RadialMenu:show ignored: no sectors configured")
        return self
    end

    -- Reopening while the fade-out runs must unregister the old popup first,
    -- otherwise the previous root keeps pointing at a menu it no longer owns.
    if self._closing then
        self:_finishClose()
    end

    if root.openPopup ~= nil and root.openPopup ~= self then
        root.openPopup:close()
    end
    -- A menu is drawn above popups and receives input first, which would hide
    -- and disable the radial until the menu is closed.
    if root.openMenu ~= nil then
        root.openMenu:close()
    end
    if root.openPopover ~= nil then
        root.openPopover:close()
    end
    if self.root ~= nil and self.root ~= root then
        -- Moving to another root closes instantly: an animated close would keep
        -- the old root pointing at a menu that is already being reassigned.
        if self.visible and not self._closing and self.onClose ~= nil then
            self.onClose(self)
        end
        self:_finishClose()
    end

    local pad = self.outerRadius + SHADOW_PAD
    local cx = clampCenter(x or 0, root.w or 0, pad)
    local cy = clampCenter(y or 0, root.h or 0, pad)

    self.root       = root
    self.parent     = root
    self.x          = cx - self.outerRadius
    self.y          = cy - self.outerRadius
    -- Cache the centre: draw and hit testing must agree even if `_ox/_oy` are
    -- rewritten by a later overlay pass.
    self._centerX   = cx
    self._centerY   = cy
    self.w          = self.outerRadius * 2
    self.h          = self.outerRadius * 2
    self.visible    = true
    self.hover      = 0
    self._pressed   = false
    self._ox        = 0
    self._oy        = 0
    self._openOx    = 0
    self._openOy    = 0
    self._openedAt  = Pallid.UI.Anim.now()
    self._animating = OPEN_DURATION > 0
    self._closing   = false
    self._closingAt = 0
    self._lastFrame = nil

    local data = self._data
    for i = 1, self._count do
        local entry = data[i]
        if entry ~= nil then
            entry.h = 0
        end
    end

    root.openPopup = self
    return self
end

--- Hides the menu and fires `onClose` once. The menu keeps drawing through a
--- short fade-out; input is swallowed until the animation ends.
--- @return PallidRadialMenu self This menu, for chaining.
function RadialMenu:close()
    if not self.visible or self._closing then
        return self
    end

    self.hover      = 0
    self._pressed   = false
    self._animating = false

    if self.onClose ~= nil then
        self.onClose(self)
    end

    if CLOSE_DURATION <= 0 then
        self:_finishClose()
        return self
    end

    self._closing   = true
    self._closingAt = Pallid.UI.Anim.now()
    return self
end

--- Removes the menu from the root after the fade-out or on an instant close.
function RadialMenu:_finishClose()
    self.visible    = false
    self._closing   = false
    self._animating = false
    self._pressed   = false
    self.hover      = 0

    local root = self.root
    if root ~= nil and root.openPopup == self then
        root.openPopup = nil
    end
    self.root   = nil
    self.parent = nil
end

--- Plays the configured click sound.
function RadialMenu:_playSound()
    if self.sound ~= nil and getSoundManager ~= nil then
        getSoundManager():playUISound(self.sound)
    end
end

--- Returns true while the popup is open.
--- @return boolean open True while the menu is visible and not fading out.
function RadialMenu:isOpen()
    return self.visible and not self._closing
end

--- Returns the hovered item.
--- @return integer|nil index 1-based index of the hovered sector.
--- @return table|nil sector Hovered sector; disabled sectors count as not hovered.
function RadialMenu:getHovered()
    local index = self.hover
    if index == nil or index < 1 or index > self._count then
        return nil, nil
    end
    local sector = self.sectors[index]
    if sector == nil or sector.disabled then
        return nil, nil
    end
    return index, sector
end

--- Radial hit test. The widget occupies the disc, not its bounding box, so a
--- click in a corner of `listRect` counts as an outside click.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean inside True when the point lies on the visible disc.
function RadialMenu:isInside(px, py)
    return self.visible and self:_insideDisc(px, py)
end

--- Tests whether a point lies inside the outer hit radius of the disc.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean inside True when the point lies inside the outer radius.
function RadialMenu:_insideDisc(px, py)
    local dx = px - self._centerX
    local dy = py - self._centerY
    local radius = self.outerRadius
    return dx * dx + dy * dy <= radius * radius
end

--- Maps a pointer to a sector. Returns 0 for a gap, the exact centre or the
--- outside, because none of those may be selected.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return integer index 1-based sector, or 0 when nothing selectable is under the pointer.
function RadialMenu:_sectorAt(px, py)
    local count = self._count
    if count == 0 or not self:_insideDisc(px, py) then
        return 0
    end

    local dx = px - self._centerX
    local dy = py - self._centerY
    local distSq = dx * dx + dy * dy
    -- Direction selects the sector from the centre outwards; only the exact
    -- centre has no direction. The hub is not a dead zone.
    if distSq < 0.0001 then
        return 0
    end

    local angle = math.atan2(dy, dx) - self._start
    angle = angle % TAU
    -- Guard against a runtime where `%` on negatives is truncated, not floored.
    if angle < 0 then
        angle = angle + TAU
    end
    local step = self._step
    local index = math.floor(angle / step) + 1
    if index < 1 then
        index = 1
    elseif index > count then
        index = count
    end

    local within = angle - (index - 1) * step
    local halfGap = self._gap * 0.5
    if within < halfGap or within > step - halfGap then
        return 0
    end
    return index
end

--- A press inside the disc always belongs to the menu. The root closes the
--- popup on a click outside `isInside`, so this only sees presses on the disc.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left", "right", or nil for left.
--- @return boolean handled True when the menu consumed the press.
function RadialMenu:onDown(px, py, button)
    if not self.visible then
        return false
    end

    if self._closing then
        -- Swallow input while fading out so the root cannot unregister the
        -- menu in the middle of its close animation.
        return true
    end

    if not self:_insideDisc(px, py) then
        self:close()
        return true
    end

    if button == "right" then
        -- A right click cancels the menu and never selects a sector.
        self:close()
        return true
    end

    self._pressed = true
    self.hover = self:_sectorAt(px, py)
    return true
end

--- Selection happens on release. A release over a disabled sector or a gap
--- leaves the menu open, a release outside the disc closes it without
--- selecting.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function RadialMenu:onUp(px, py)
    local pressed = self._pressed
    self._pressed = false
    if not pressed or self._closing then
        return
    end

    if not self:_insideDisc(px, py) then
        self:close()
        return
    end

    local index = self:_sectorAt(px, py)
    if index == 0 then
        return
    end
    local sector = self.sectors[index]
    if sector == nil or sector.disabled then
        return
    end

    self:_playSound()
    self:close()
    if self.onSelect ~= nil then
        self.onSelect(self, index, sector)
    end
end

--- Updates hover state for the current pointer position.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function RadialMenu:onHoverMove(px, py)
    if self._closing then
        return
    end
    self.hover = self:_sectorAt(px, py)
end

--- The root routes a captured drag to `onMove`, not `onHoverMove`; keeping the
--- highlight live while the button is held needs both.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function RadialMenu:onMove(px, py)
    if self._closing then
        return
    end
    self.hover = self:_sectorAt(px, py)
end

--- Clears the highlight when the cursor leaves the disc.
function RadialMenu:onHoverEnd()
    self.hover = 0
    Widgets.Widget.onHoverEnd(self)
end

--- Escape cancels the menu without selecting a sector. The root routes key
--- presses to an open popup only when it overrides `onKeyPress`.
--- @param key integer Keyboard.KEY_* value.
--- @return boolean handled True when the key closed the menu.
function RadialMenu:onKeyPress(key)
    if Keyboard ~= nil and key == Keyboard.KEY_ESCAPE then
        self:close()
        return true
    end
    return false
end

--- Swallows the wheel so world zoom does not react under the open menu.
--- @param delta number Wheel steps; positive is up.
--- @return boolean handled True to swallow the wheel.
function RadialMenu:onWheel(delta) -- luacheck: ignore
    return true
end

--- Bounding box used by the root to mask native text boxes under the popup.
--- The drawn shadow extends past the disc, so the box includes it.
--- @return number x Left edge in root-local coordinates.
--- @return number y Top edge in root-local coordinates.
--- @return number w Width including the shadow pad.
--- @return number h Height including the shadow pad.
function RadialMenu:listRect()
    local x, y = self:originX(), self:originY()
    return x - SHADOW_PAD, y - SHADOW_PAD,
        self.w + SHADOW_PAD * 2, self.h + SHADOW_PAD * 2
end

--- The root calls this after `draw`; the whole menu is already painted in
--- `drawSelf`, so this hook stays empty.
--- @param el ISUIElement Host element the menu is rendered into.
function RadialMenu:drawPopup(el) -- luacheck: ignore
end

--- Draws the shadow, sectors, icons, labels and the centre caption.
--- @param el ISUIElement Host element the menu is rendered into.
function RadialMenu:drawSelf(el)
    local count = self._count
    if not self.visible or count == 0 then
        return
    end

    local radius = self.outerRadius
    local cx = self._centerX or (self:originX() + radius)
    local cy = self._centerY or (self:originY() + radius)
    local now = Pallid.UI.Anim.now()

    -- openPopup widgets are not visited by Widget:update, so every animation is
    -- derived from the wall clock here instead of a track that would freeze.
    local scale = 1
    if self._closing then
        local elapsed = now - self._closingAt
        if elapsed < 0 then
            elapsed = 0
        end
        if elapsed >= CLOSE_DURATION then
            self:_finishClose()
            return
        end
        local t = elapsed / CLOSE_DURATION
        scale = 1 - (1 - OPEN_SCALE) * Pallid.UI.Anim.ease.outCubic(t)
    elseif self._animating then
        local elapsed = now - self._openedAt
        if elapsed < 0 then
            elapsed = 0
        end
        if elapsed >= OPEN_DURATION then
            self._animating = false
        else
            local t = elapsed / OPEN_DURATION
            scale = OPEN_SCALE + (1 - OPEN_SCALE) * Pallid.UI.Anim.ease.outCubic(t)
        end
    end

    -- The highlight fades instead of jumping between sectors. The popup is not
    -- updated, so the step is taken from the draw clock.
    local dt = 0
    if self._lastFrame ~= nil then
        dt = now - self._lastFrame
        if dt < 0 or dt > 0.1 then
            dt = 0
        end
    end
    self._lastFrame = now
    local fadeStep = HOVER_FADE > 0 and math.min(1, dt / HOVER_FADE) or 1

    local outer = radius * scale
    local inner = self.innerRadius * scale

    Pallid.UI.circle(el, cx, cy, outer + SHADOW_PAD, self.shadowColor)
    Pallid.UI.circle(el, cx, cy, outer, self.background)

    local data = self._data
    local sectors = self.sectors
    local hover = self.hover

    -- Pies are painted to the centre, then the centre disc covers the hub,
    -- which is cheaper than building an annular polygon per sector.
    for i = 1, count do
        local sector = sectors[i]
        if sector ~= nil then
            local entry = data[i]
            local target = (i == hover) and 1 or 0
            entry.h = entry.h + (target - entry.h) * fadeStep

            local from = sector.disabled and entry.dim or entry.fill
            local to = sector.disabled and entry.dimHover or entry.hover
            local fill = from
            if entry.h > 0.001 then
                local h = entry.h
                HOVER_FILL.r = from.r + (to.r - from.r) * h
                HOVER_FILL.g = from.g + (to.g - from.g) * h
                HOVER_FILL.b = from.b + (to.b - from.b) * h
                HOVER_FILL.a = from.a + (to.a - from.a) * h
                fill = HOVER_FILL
            end
            Pallid.UI.circle(el, cx, cy, outer, fill, entry.a0, entry.a1)
        end
    end

    if inner > 0 then
        Pallid.UI.circle(el, cx, cy, inner, self.centerColor)
    end

    local iconSize = self.iconSize
    local halfIcon = iconSize * 0.5
    local labelStyle = self.labelStyle
    local textHeight = 0
    if getTextManager ~= nil then
        textHeight = getTextManager():getFontHeight(labelStyle.font)
    end
    local blockHeight = iconSize + LABEL_GAP + textHeight

    for i = 1, count do
        local sector = sectors[i]
        if sector ~= nil then
            local entry = data[i]
            local tint = sector.disabled and self.disabledLabelColor or self.labelColor
            local anchorR = entry.iconR * scale
            local ax = cx + entry.cos * anchorR
            local ay = cy + entry.sin * anchorR

            if entry.hasIcon and iconSize > 0 then
                -- The icon sits on top of the label and the pair is centred on
                -- the sector's mid radius.
                local iy = entry.hasLabel and (ay - blockHeight * 0.5) or (ay - halfIcon)
                local ix = ax - halfIcon
                if entry.texture ~= nil then
                    Pallid.UI.texture(el, entry.texture, ix, iy, iconSize, iconSize, tint, ICON_OPTS)
                elseif entry.name ~= nil then
                    Pallid.UI.icon(el, entry.name, ix, iy, iconSize, tint)
                end
            end

            if entry.hasLabel then
                local label = sector.label
                if type(label) == "string" and label ~= "" then
                    labelStyle.color = tint
                    labelStyle.maxWidth = entry.labelW
                    local labelY = ay
                    if entry.hasIcon and iconSize > 0 then
                        labelY = ay - blockHeight * 0.5 + iconSize + LABEL_GAP
                        labelStyle.alignV = "top"
                    else
                        labelStyle.alignV = "middle"
                    end
                    Pallid.UI.text(el, label, ax, labelY, labelStyle)
                end
            end
        end
    end

    -- The style is shared, so leave it with the normal tint for the next frame.
    labelStyle.color = self.labelColor
    labelStyle.maxWidth = 0
    labelStyle.alignV = "middle"

    -- The hovered sector label replaces the static hint under the caption.
    local hint = self.hint
    local hovered = sectors[hover]
    if hovered ~= nil and type(hovered.label) == "string" and hovered.label ~= "" then
        hint = hovered.label
    end

    local hasTitle = self.title ~= ""
    local hasHint = hint ~= ""
    if hasTitle then
        -- Shrink a long caption to the hub instead of truncating it to
        -- "Comma...", which reads badly in the middle of the wheel.
        local style = self.titleStyle
        local maxW = style.maxWidth or 0
        local titleScale = 1
        if maxW > 0 and getTextManager ~= nil then
            local natural = getTextManager():MeasureStringX(style.font, self.title)
            if natural > maxW then
                titleScale = maxW / natural
            end
        end
        style.scale = titleScale < 1 and titleScale or nil
        Pallid.UI.text(el, self.title, cx, hasHint and (cy - TITLE_OFFSET) or cy, style)
        style.scale = nil
    end
    if hasHint then
        Pallid.UI.text(el, hint, cx, hasTitle and (cy + TITLE_OFFSET) or cy, self.hintStyle)
    end
end
