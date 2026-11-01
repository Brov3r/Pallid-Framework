require "pallid/ui/internal"
require "pallid/ui/api/text"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local MIN_ICON_SIZE = 6
-- Leave one spare pixel so anti-aliased icon edges are never flushed against
-- the widget boundary and later clipped by a stencil.
local SAFE_INSET = 1
-- Marker used inside layout index lists. Real crumb indexes start at 1.
local ELLIPSIS = 0

--- Measures the rendered pixel width of a text string in a font.
--- @param font UIFont Game font used for measuring.
--- @param text string Text to measure.
--- @return number width Width in pixels.
local function textWidth(font, text)
    return getTextManager():MeasureStringX(font, text)
end

--- Adds measurement and layout to the Breadcrumbs class.
--- @param Breadcrumbs table PallidBreadcrumbs class.
--- @return fun Augmenter that installs the methods.
return function(Breadcrumbs)
    --- Builds a layout part list from a sequence of crumb indexes. The ELLIPSIS
    --- marker (0) inserts the collapsed marker. Returns the parts and total width.
    --- @param indices integer[] Crumb indexes and ELLIPSIS markers in draw order.
    --- @param maxTextW number|nil Maximum label width per item; nil keeps natural text.
    --- @return table[] parts Layout parts in draw order.
    --- @return number total Total width in pixels.
    function Breadcrumbs:_compose(indices, maxTextW)
        local parts = {}
        local cursor = 0
        for position = 1, #indices do
            if position > 1 and self.sepW > 0 then
                local separatorX = cursor + self.separatorGap
                local usesIcon = self.separator == "" and self._separatorIcon ~= nil
                parts[#parts + 1] = {
                    kind     = "separator",
                    x        = separatorX,
                    w        = self.sepW,
                    text     = self.separator,
                    icon     = usesIcon and self._separatorIcon or nil,
                    iconSize = usesIcon and self._separatorDrawSize or nil,
                }
                cursor = separatorX + self.sepW + self.separatorGap
            end

            local index = indices[position]
            local part
            if index == ELLIPSIS then
                local width = self.itemPadding * 2 + self.ellipsisW
                part = {
                    kind  = "ellipsis",
                    x     = cursor,
                    w     = width,
                    text  = self.ellipsis,
                    textW = self.ellipsisW,
                }
            else
                local item = self.items[index]
                local label = item.label
                if maxTextW ~= nil then
                    label = Pallid.UI.truncateText(label, self.font, maxTextW)
                end
                local labelW = textWidth(self.font, label)
                local iconW = item.hasIcon and (self.iconSize + self.iconGap) or 0
                local width = self.itemPadding * 2 + iconW + labelW
                part = {
                    kind   = "item",
                    index  = index,
                    item   = item,
                    x      = cursor,
                    w      = width,
                    text   = label,
                    textW  = labelW,
                    iconW  = iconW,
                }
            end

            parts[#parts + 1] = part
            cursor = cursor + part.w
        end
        return parts, cursor
    end

    --- Computes the label budget used when a row must be truncated instead of
    --- collapsed. The fixed part covers padding, icons, ellipsis text and
    --- separators; the remainder is split evenly between visible entries.
    --- @param indices integer[] Crumb indexes and ELLIPSIS markers in draw order.
    --- @return number maxTextW Maximum label width in pixels, at least zero.
    function Breadcrumbs:_maxTextWidth(indices)
        local fixed = 0
        local slots = 0
        for i = 1, #indices do
            local index = indices[i]
            slots = slots + 1
            fixed = fixed + self.itemPadding * 2
            if index == ELLIPSIS then
                fixed = fixed + self.ellipsisW
            else
                local item = self.items[index]
                if item.hasIcon then
                    fixed = fixed + self.iconSize + self.iconGap
                end
            end
        end
        if slots > 1 and self.sepW > 0 then
            fixed = fixed + (slots - 1) * (self.sepW + self.separatorGap * 2)
        end
        local available = self.w - fixed - SAFE_INSET
        if available <= 0 then
            return 0
        end
        return math.floor(available / slots)
    end

    --- Truncates labels until the measured row fits. Re-measuring after
    --- truncation catches font kerning and suffix rounding that can push the
    --- nominal budget a few pixels over the widget width.
    --- @param indices integer[] Crumb indexes and ELLIPSIS markers in draw order.
    --- @return table[] parts Layout parts in draw order.
    --- @return number total Total width in pixels.
    function Breadcrumbs:_composeTruncated(indices)
        local maxTextW = self:_maxTextWidth(indices)
        local parts, total = self:_compose(indices, maxTextW)
        while total > self.w and maxTextW > 0 do
            local step = math.max(1, math.ceil((total - self.w) / #indices))
            maxTextW = math.max(0, maxTextW - step)
            parts, total = self:_compose(indices, maxTextW)
        end
        return parts, total
    end

    --- Measures the visible row and caches layout parts. Called only when
    --- bounds, items, font, separator, ellipsis or collapsing change, never per
    --- frame.
    function Breadcrumbs:_layout()
        self._parts = {}
        self._collapsed = false
        self._hiddenCount = 0
        self._needsClip = false
        self.hoverPart = nil
        self.hover = 0
        self._pressedPart = nil

        local count = #self.items
        if count == 0 or self.w <= 0 then
            return
        end

        -- The icon shrinks with a short row so it can never exceed the widget.
        self.iconSize = math.min(self._iconSizeBase, math.max(MIN_ICON_SIZE, self.h - 4))
        if self.separator ~= "" then
            self.sepW = textWidth(self.font, self.separator)
        elseif self._separatorIcon ~= nil then
            self._separatorDrawSize = math.min(
                self.separatorIconSize,
                math.max(MIN_ICON_SIZE, self.h - 8)
            )
            self.sepW = self._separatorDrawSize
        else
            self.sepW = 0
        end
        self.ellipsisW = textWidth(self.font, self.ellipsis)

        local allIndices = {}
        for i = 1, count do
            allIndices[i] = i
        end

        local parts, total = self:_compose(allIndices, nil)
        if total <= self.w then
            self._parts = parts
            return
        end

        if self.collapse and count >= 3 then
            -- Keep the first crumb, the ellipsis and as many trailing crumbs
            -- as fit naturally. Adding a crumb is monotonic, so the loop can
            -- stop at the first overflow.
            local bestParts
            for tailStart = count, 3, -1 do
                local indices = { 1, ELLIPSIS }
                for i = tailStart, count do
                    indices[#indices + 1] = i
                end
                local candidate, candidateWidth = self:_compose(indices, nil)
                if candidateWidth <= self.w then
                    bestParts = candidate
                else
                    break
                end
            end
            if bestParts ~= nil then
                self._parts = bestParts
                self._collapsed = true
                -- Visible crumbs are the head, the ellipsis and the visible tail.
                local visibleTail = 0
                for i = 1, #bestParts do
                    if bestParts[i].kind == "item" and bestParts[i].index ~= 1 then
                        visibleTail = visibleTail + 1
                    end
                end
                self._hiddenCount = count - 1 - visibleTail
                return
            end

            local indices = { 1, ELLIPSIS, count }
            local truncated, truncatedWidth = self:_composeTruncated(indices)
            self._parts = truncated
            self._collapsed = true
            self._hiddenCount = count - 2
            self._needsClip = truncatedWidth > self.w + 0.5
            return
        end

        local truncated, truncatedWidth = self:_composeTruncated(allIndices)
        self._parts = truncated
        self._needsClip = truncatedWidth > self.w + 0.5
    end
end
