require "pallid/ui/internal"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/tooltip/core"
require "pallid/ui/widgets/tooltip/layout"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local Tooltip = Widgets.Tooltip
local Layout = Pallid.UI.TooltipLayout

local PADDING     = Layout.PADDING
local ICON_SIZE   = Layout.ICON_SIZE
local SWATCH_SIZE = Layout.SWATCH_SIZE
local OFFSET      = 6
local ROUND       = 4
local ICON_OPTS   = { mode = "fit" }

local COLOR_TITLE     = Pallid.UI.Color.textPrimary
local COLOR_BODY      = Pallid.UI.Color.text
local COLOR_LABEL     = Pallid.UI.Color.textMuted
local COLOR_VALUE     = Pallid.UI.Color.textPrimary
local COLOR_SECTION   = Pallid.UI.Color.textMuted
local COLOR_FOOTER    = Pallid.UI.Color.textMuted
local COLOR_SEPARATOR = Pallid.UI.Color.border

--- Draws the tooltip near (x, y), clamped to the surface size. The body is
--- measured with the same wrapping rules as Pallid.UI.text, so explicit `\n`
--- and auto-wrap produce the same box that is drawn.
--- @param el ISUIElement Host element the tree is rendered into.
--- @param x number Anchor X in root-local coordinates.
--- @param y number Anchor Y in root-local coordinates.
--- @param now number Current time in seconds.
--- @param boundsW number|nil Width of the surface used for clamping.
--- @param boundsH number|nil Height of the surface used for clamping.
function Tooltip:draw(el, x, y, now, boundsW, boundsH)
    if not self:hasContent() then
        return
    end
    if self._closed then
        -- A direct draw after a completed fade means the host asked for the
        -- tooltip again; replay the fade instead of staying hidden.
        self:_wake()
    end

    -- A direct caller bypasses the shared host, so treat the first frame as a
    -- show. The host path calls `show` itself every frame.
    if not self.started and not self.closing then
        self:show(now)
        if not self.started then
            return
        end
    end

    local alpha, dy
    if self.closing then
        local close = self.closeTrack:update(now)
        alpha = self.track.alpha * close.alpha
        dy = self.track.dy + close.dy
        if close.finished then
            self.closing = false
            self._closed = true
            if self._clearOnClose then
                self:_wipe()
            end
            return
        end
    else
        local show = self.track:update(now)
        alpha = show.alpha
        dy = show.dy
    end
    if alpha <= 0.01 then
        return
    end

    self:_ensureLayout()
    local boxW = self._boxW
    local boxH = self._boxH
    if boxW <= 0 or boxH <= 0 then
        return
    end

    local drawX = x + OFFSET
    local drawY = y + OFFSET + dy
    if boundsW ~= nil then
        if drawX + boxW > boundsW - 2 then
            drawX = x - boxW - OFFSET
        end
        -- A box wider than the surface still has to start inside it.
        drawX = math.max(2, math.min(drawX, boundsW - boxW - 2))
    end
    if boundsH ~= nil then
        if drawY + boxH > boundsH - 2 then
            drawY = y - boxH - OFFSET
        end
        drawY = math.max(2, math.min(drawY, boundsH - boxH - 2))
    end

    -- Anim.alpha returns a shared scratch table: consume each result before the
    -- next call and never keep it across frames.
    Pallid.UI.roundedRect(el, drawX, drawY, boxW, boxH, ROUND,
        Pallid.UI.Anim.alpha(self.fill, alpha))
    Pallid.UI.roundedBorder(el, drawX, drawY, boxW, boxH, ROUND, 1,
        Pallid.UI.Anim.alpha(self.border, alpha))

    local left = drawX + PADDING
    local top = drawY + PADDING
    local contentW = self._contentW
    local items = self._items

    for i = 1, self._itemCount do
        local item = items[i]
        local kind = item.kind

        if kind == "title" then
            local style = self.titleStyle
            style.color = Pallid.UI.Anim.alpha(COLOR_TITLE, alpha)
            Pallid.UI.text(el, self.title, left, top + item.y, style)
            style.color = COLOR_TITLE
        elseif kind == "body" then
            local style = self.style
            style.color = Pallid.UI.Anim.alpha(COLOR_BODY, alpha)
            Pallid.UI.text(el, self.text, left, top + item.y, style)
            style.color = COLOR_BODY
        elseif kind == "section" then
            local style = self.sectionStyle
            style.color = Pallid.UI.Anim.alpha(COLOR_SECTION, alpha)
            Pallid.UI.text(el, item.text, left, top + item.y, style)
            style.color = COLOR_SECTION
        elseif kind == "separator" then
            Pallid.UI.rect(el, left, top + item.y, contentW, 1,
                Pallid.UI.Anim.alpha(COLOR_SEPARATOR, alpha))
        elseif kind == "footer" then
            local style = self.footerStyle
            style.color = Pallid.UI.Anim.alpha(COLOR_FOOTER, alpha)
            Pallid.UI.text(el, self.footer, left, top + item.y, style)
            style.color = COLOR_FOOTER
        else
            local centerY = top + item.y + item.h * 0.5

            if item.icon then
                local texture, name = Pallid.UI.Textures.resolve(item.icon)
                local tint = Pallid.UI.Anim.alpha(Pallid.UI.Color.white, alpha)
                local iconY = centerY - ICON_SIZE * 0.5
                if texture ~= nil then
                    Pallid.UI.texture(el, texture, left, iconY, ICON_SIZE, ICON_SIZE, tint, ICON_OPTS)
                elseif name ~= nil then
                    Pallid.UI.icon(el, name, left, iconY, ICON_SIZE, tint)
                end
            elseif item.swatch ~= nil then
                Pallid.UI.roundedRect(el, left, centerY - SWATCH_SIZE * 0.5,
                    SWATCH_SIZE, SWATCH_SIZE, 2, Pallid.UI.Anim.alpha(item.swatch, alpha))
            end

            local labelStyle = self.labelStyle
            labelStyle.color = Pallid.UI.Anim.alpha(item.labelColor or COLOR_LABEL, alpha)
            Pallid.UI.text(el, item.label, left + item.leftW, centerY, labelStyle)
            labelStyle.color = COLOR_LABEL

            if item.value ~= nil and item.value ~= "" then
                local valueStyle = self.valueStyle
                valueStyle.color = Pallid.UI.Anim.alpha(item.valueColor or COLOR_VALUE, alpha)
                Pallid.UI.text(el, item.value, left + contentW, centerY, valueStyle)
                valueStyle.color = COLOR_VALUE
            end
        end
    end
end
