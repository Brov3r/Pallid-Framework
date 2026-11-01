require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/clip"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local I = Pallid.UI._internal
local INNER_RADIUS = 2
local FALLBACK_OPTS = { mode = "fit" }

--- Adds the frame, viewport and 2D fallback drawing to the model class.
--- @param Model3D table PallidModel3D class.
--- @return fun Augmenter that installs the methods.
return function(Model3D)
    --- Viewport rect in host-local coordinates: the widget minus the frame inset
    --- and the footer strip, so the native never covers the hint. The box is
    --- snapped to whole pixels because UI3DModel casts its position to int.
    --- @return number x X coordinate.
    --- @return number y Y coordinate.
    --- @return number w Width in pixels.
    --- @return number h Height in pixels.
    function Model3D:_viewport()
        local inset = self.inset
        local footer = (self.label ~= nil and self.footerHeight > 0) and self.footerHeight or 0
        local w = self.w - inset * 2
        local h = self.h - inset * 2 - footer
        if w < 1 then
            w = 1
        end
        if h < 1 then
            h = 1
        end
        return I.snapBox(self:originX() + inset, self:originY() + inset, w, h)
    end

    --- Wraps the fallback caption once per width change. The result is reused by
    --- every frame; calling TextManager.WrapText during render would allocate.
    --- @param maxWidth number Available width in pixels.
    --- @return string[] lines Cached lines.
    --- @return number lineHeight Cached line height.
    function Model3D:_fallbackLinesFor(maxWidth)
        if self._fallbackLines ~= nil
            and self._fallbackWidth == maxWidth
            and self._fallbackCachedText == self.fallbackText then
            return self._fallbackLines, self._fallbackLineHeight
        end

        local lines = Pallid.UI.wrapText(self.fallbackText, self.fallbackStyle.font, maxWidth, nil)
        if lines == nil or #lines == 0 then
            lines = { self.fallbackText }
        end
        self._fallbackLines = lines
        self._fallbackLineHeight = self.textHeight
        self._fallbackWidth = maxWidth
        self._fallbackCachedText = self.fallbackText
        return lines, self._fallbackLineHeight
    end

    --- Returns the footer text truncated to the current width. Cached because
    --- text truncation allocates a new string.
    --- @param maxWidth number Available width in pixels.
    --- @return string text Footer text truncated to the width.
    function Model3D:_footerTextFor(maxWidth)
        if self._footerText ~= nil
            and self._footerWidth == maxWidth
            and self._footerCachedLabel == self.label then
            return self._footerText
        end
        local text = Pallid.UI.truncateText(self.label or "", self.footerStyle.font, maxWidth)
        self._footerText = text
        self._footerWidth = maxWidth
        self._footerCachedLabel = self.label
        return text
    end

    --- Two-dimensional placeholder: an icon and/or a caption. Never a mock 3D
    --- render, because UI3DModel cannot draw items or vehicles.
    --- @param el ISUIElement Host element used for drawing.
    --- @param x number X coordinate.
    --- @param y number Y coordinate.
    --- @param w number Width in pixels.
    --- @param h number Height in pixels.
    function Model3D:_drawFallback(el, x, y, w, h)
        local centerX = x + w * 0.5
        local centerY = y + h * 0.5
        local iconSize = math.min(w, h) * 0.5
        local hasIcon = false
        local iconY = centerY - iconSize * 0.5 - 8

        if self.fallbackTexture ~= nil then
            hasIcon = Pallid.UI.texture(
                el, self.fallbackTexture,
                centerX - iconSize * 0.5, iconY, iconSize, iconSize,
                nil, FALLBACK_OPTS
            )
        elseif self.fallbackIconName ~= nil then
            hasIcon = Pallid.UI.icon(el, self.fallbackIconName, centerX - iconSize * 0.5, iconY, iconSize)
        elseif self.item ~= nil then
            local itemSize = math.min(w, h) * 0.55
            hasIcon = Pallid.UI.itemIcon(
                el, self.item,
                centerX - itemSize * 0.5, centerY - itemSize * 0.5 - 6,
                itemSize, itemSize, 1
            )
        end

        local maxWidth = w - 8
        if maxWidth > 0 and self.fallbackText ~= "" then
            local lines, lineHeight = self:_fallbackLinesFor(maxWidth)
            local totalHeight = lineHeight * #lines
            local top
            if hasIcon then
                top = y + h - 4 - totalHeight
            else
                top = y + (h - totalHeight) * 0.5
            end

            local style = self.fallbackStyle
            style.wrap = false
            style.maxWidth = 0
            style.alignV = "top"
            for i = 1, #lines do
                Pallid.UI.text(el, lines[i], centerX, top + (i - 1) * lineHeight, style)
            end
        end
    end

    --- Paints the widget into the host element.
    --- @param el ISUIElement Host element used for drawing.
    function Model3D:drawSelf(el)
        local x, y = self:originX(), self:originY()

        Pallid.UI.roundedRect(el, x, y, self.w, self.h, self.radius, self:shade(Pallid.UI.Color.panel))

        local vx, vy, vw, vh = self:_viewport()
        Pallid.UI.roundedRect(el, vx, vy, vw, vh, INNER_RADIUS, self:shade(Pallid.UI.Color.background))

        -- The native model covers the viewport exactly, so the inner border is
        -- drawn one pixel outside it and stays visible. Outer border comes after
        -- the viewport so a zero inset cannot paint over it.
        if self.inset >= 1 then
            Pallid.UI.roundedBorder(
                el, vx - 1, vy - 1, vw + 2, vh + 2, INNER_RADIUS + 1, 1,
                self:shade(Pallid.UI.Color.panelBorder)
            )
        end
        Pallid.UI.roundedBorder(el, x, y, self.w, self.h, self.radius, 1, self:shade(Pallid.UI.Color.panelBorder))

        -- UI3DModel is a deferred always-on-top element and cannot be clipped by
        -- the Pallid stencil. Show it only when the whole viewport is inside the
        -- active software clip; otherwise the model would paint over a scrollbar
        -- or outside its window.
        local cx, cy, cw, ch = Pallid.UI.clipRect()
        local fullyVisible = true
        if cx ~= nil then
            fullyVisible = cw > 0 and ch > 0
                and vx >= cx and vy >= cy
                and vx + vw <= cx + cw and vy + vh <= cy + ch
        end
        local clippedOut = Pallid.UI.isClippedOut(vx, vy, vw, vh)
        local hasSource = self:_hasSource()
        local contextAvailable = self:_nativeContextAvailable()

        if hasSource and fullyVisible and contextAvailable then
            local model = self.model or self:_ensureNative()
            if model ~= nil then
                self:_positionNative(el, vx, vy, vw, vh)
            elseif not clippedOut then
                self:_drawFallback(el, vx, vy, vw, vh)
            end
        else
            if self.model ~= nil then
                self:_hideNative()
            end
            if (not hasSource or not contextAvailable) and not clippedOut then
                self:_drawFallback(el, vx, vy, vw, vh)
            end
        end

        if self.label ~= nil and self.footerHeight > 0 then
            local maxWidth = self.w - self.inset * 2
            local footerY = y + self.h - self.inset - self.footerHeight * 0.5
            if maxWidth > 0 and footerY >= vy + vh then
                local style = self.footerStyle
                style.maxWidth = 0
                Pallid.UI.text(el, self:_footerTextFor(maxWidth), x + self.w * 0.5, footerY, style)
            end
        end
    end
end
