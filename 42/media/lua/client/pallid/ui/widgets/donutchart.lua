require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local TAU = math.pi * 2

local PALETTE = {
    Pallid.UI.Color.primary,
    Pallid.UI.Color.info,
    Pallid.UI.Color.warning,
    Pallid.UI.Color.success,
    Pallid.UI.Color.error,
    Pallid.UI.Color.primaryStrong,
}

--- Ring/donut chart for part-to-whole values. Segments are plain tables with
--- `label`, `value` and an optional `color`; the chart renders a centre label
--- and an optional legend without allocating per frame.
--- @class PallidDonutChart : PallidWidget
--- @field segments table[] Segment records in caller order.
--- @field thickness number Ring thickness in pixels.
--- @field startAngle number Start angle in degrees.
--- @field showLegend boolean True draws the legend column.
--- @field animated boolean True eases the reveal animation.
--- @field reveal number Current reveal amount, 0..1.
--- @field hoverIndex integer Hovered segment index, or 0.
--- @field tooltip PallidTooltip|nil Segment hover tooltip created lazily by the base widget.
--- @field onSelect fun(chart: PallidDonutChart, index: integer, segment: table)|nil Segment click callback.
local DonutChart = Widgets.class("DonutChart")

--- Creates a new `DonutChart` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Data and appearance.
--- @field opts.segments table[]|nil Segment records: `{ label, value, color? }`.
--- @field opts.thickness number|nil Ring thickness, defaults to 18% of the radius.
--- @field opts.startAngle number|nil Start angle in degrees, defaults to -90.
--- @field opts.track PallidColor|nil Track colour behind the segments.
--- @field opts.showLegend boolean|nil True draws the legend, defaults to true.
--- @field opts.animated boolean|nil True eases the reveal, defaults to true.
--- @field opts.centerText string|nil Large centre text.
--- @field opts.centerSubtext string|nil Small centre text under the value.
--- @field opts.format string|fun(value: number): string|nil Value formatter for the legend and total.
--- @field opts.onSelect fun(chart: PallidDonutChart, index: integer, segment: table)|nil Click callback.
--- @return PallidDonutChart chart New donut chart.
function DonutChart.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, DonutChart)
    self:init(x, y, w or 0, h or 0)

    self.segments = type(opts.segments) == "table" and opts.segments or {}
    self.thickness = math.max(4, opts.thickness or 26)
    self.startAngle = opts.startAngle or -90
    self.track = opts.track
    self.showLegend = opts.showLegend ~= false
    self.animated = opts.animated ~= false
    self.reveal = self.animated and 0 or 1
    self.hoverIndex = 0
    self.onSelect = opts.onSelect
    self.centerText = opts.centerText
    self.centerSubtext = opts.centerSubtext
    self.format = opts.format or "%.0f"
    self.legendGap = 12
    self.legendW = 120

    self.valueStyle = {
        font = Pallid.UI.Fonts.large,
        color = Pallid.UI.Color.textPrimary,
        alignH = "center",
        alignV = "middle",
    }
    self.subStyle = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.textMuted,
        alignH = "center",
        alignV = "middle",
    }
    self.legendStyle = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.text,
        alignH = "left",
        alignV = "middle",
        ellipsis = "...",
    }
    self._cx, self._cy, self._outer = 0, 0, 0
    self._valueTexts = {}
    self:_refreshTexts()
    self:setTooltip("", opts.tooltipDelay or 0.05)
    return self
end

--- Factory shortcut for `DonutChart.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Data and appearance; see `DonutChart.new`.
--- @return PallidDonutChart chart New donut chart.
function Widgets.donutChart(x, y, w, h, opts)
    return DonutChart.new(x, y, w, h, opts)
end

--- Replaces the segments.
--- @param segments table[]|nil New segments.
--- @return PallidDonutChart self For chaining.
function DonutChart:setSegments(segments)
    self.segments = type(segments) == "table" and segments or {}
    self.reveal = self.animated and 0 or 1
    self.hoverIndex = 0
    if self.tooltip ~= nil then
        self.tooltip:clear()
    end
    self:_refreshTexts()
    return self
end

--- Recomputes the cached legend value strings.
function DonutChart:_refreshTexts()
    for i = #self._valueTexts, 1, -1 do
        self._valueTexts[i] = nil
    end
    for i = 1, #self.segments do
        self._valueTexts[i] = self:formatValue(tonumber(self.segments[i].value) or 0)
    end
end

--- Replaces the value formatter and refreshes the cached text.
--- @param format string|fun(value: number): string New formatter.
--- @return PallidDonutChart self For chaining.
function DonutChart:setFormat(format)
    self.format = format or "%.0f"
    self:_refreshTexts()
    return self
end

--- Sums the positive values of every segment.
--- @return number total Sum of all segment values.
function DonutChart:getTotal()
    local total = 0
    for i = 1, #self.segments do
        local value = tonumber(self.segments[i].value) or 0
        if value > 0 then
            total = total + value
        end
    end
    return total
end

--- Formats a value with the configured format string or function.
--- @param value number Value to format.
--- @return string text Formatted value.
function DonutChart:formatValue(value)
    if type(self.format) == "function" then
        return tostring(self.format(value))
    end
    return string.format(self.format, value)
end

--- Computes the ring geometry for the current bounds.
function DonutChart:_measure()
    local x, y = self:originX(), self:originY()
    local legendW = (self.showLegend and self.w >= 220) and math.min(self.legendW, self.w * 0.4) or 0
    local chartW = math.max(0, self.w - legendW - (legendW > 0 and self.legendGap or 0))
    local outer = math.max(0, math.min(chartW, self.h) * 0.5 - 2)
    self._cx = x + chartW * 0.5
    self._cy = y + self.h * 0.5
    self._outer = outer
    self._legendX = x + chartW + self.legendGap
    self._legendW = legendW
    self._chartW = chartW
end

--- Returns the segment under a point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return integer index Segment index, or 0.
function DonutChart:segmentAt(px, py)
    self:_measure()
    local dx = px - self._cx
    local dy = py - self._cy
    local outer = self._outer
    local inner = math.max(0, outer - self.thickness)
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < inner or distance > outer then
        return 0
    end
    local total = self:getTotal()
    if total <= 0 then
        return 0
    end

    local angle = math.atan2(dy, dx) - math.rad(self.startAngle)
    while angle < 0 do
        angle = angle + TAU
    end
    while angle >= TAU do
        angle = angle - TAU
    end
    local cursor = 0
    for i = 1, #self.segments do
        local value = tonumber(self.segments[i].value) or 0
        if value > 0 then
            cursor = cursor + value / total * TAU
            if angle < cursor then
                return i
            end
        end
    end
    return 0
end

--- Eases the reveal animation.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function DonutChart:onAnimate(now, dt)
    if self.animated and self.reveal < 1 then
        self.reveal = Widgets.approach(self.reveal, 1, 8, dt)
    end
end

--- Updates the tooltip for the hovered segment.
--- @param index integer Segment index, or 0 to clear the tooltip.
function DonutChart:_updateTooltip(index)
    local tooltip = self.tooltip
    if tooltip == nil then
        return
    end
    if index <= 0 or self.segments[index] == nil then
        tooltip:clear()
        return
    end
    local segment = self.segments[index]
    local value = tonumber(segment.value) or 0
    local total = self:getTotal()
    local percent = total > 0 and math.floor(value / total * 100 + 0.5) or 0
    local label = segment.label or ("Segment " .. index)
    local color = segment.color or PALETTE[(index - 1) % #PALETTE + 1]
    tooltip:setTitle("")
    tooltip:setRows({
        {
            swatch = color,
            label  = label,
            value  = string.format("%s (%d%%)", self:formatValue(value), percent),
        },
    })
end

--- Tracks the hovered segment and updates its tooltip.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function DonutChart:onHoverMove(px, py)
    local index = self:segmentAt(px, py)
    if index == self.hoverIndex then
        return
    end
    self.hoverIndex = index
    self:_updateTooltip(index)
end

--- Clears the hovered segment and its tooltip.
function DonutChart:onHoverEnd()
    self.hoverIndex = 0
    self:_updateTooltip(0)
    Widgets.Widget.onHoverEnd(self)
end

--- Selects a segment on click.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when a segment was clicked.
function DonutChart:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end
    local index = self:segmentAt(px, py)
    if index > 0 and self.onSelect ~= nil then
        self.onSelect(self, index, self.segments[index])
    end
    return index > 0
end

--- Draws the ring, centre labels and legend.
--- @param el ISUIElement Host element the tree is rendered into.
function DonutChart:drawSelf(el)
    if self.w <= 0 or self.h <= 0 then
        return
    end
    self:_measure()
    local cx, cy, outer = self._cx, self._cy, self._outer
    if outer <= 0 then
        return
    end
    local baseThickness = math.min(self.thickness, math.max(2, outer * 0.9))
    local inner = math.max(0, outer - baseThickness)

    if self.track ~= nil then
        Pallid.UI.ring(el, cx, cy, outer, baseThickness, self:shade(self.track), 0, TAU)
    end

    local total = self:getTotal()
    if total <= 0 then
        return
    end
    local cursor = math.rad(self.startAngle)
    local reveal = self.reveal
    for i = 1, #self.segments do
        local segment = self.segments[i]
        local value = tonumber(segment.value) or 0
        if value > 0 then
            local span = value / total * TAU * reveal
            local color = segment.color or PALETTE[(i - 1) % #PALETTE + 1]
            local thickness = baseThickness
            if i == self.hoverIndex then
                thickness = math.min(baseThickness + 2, outer)
            end
            Pallid.UI.ring(el, cx, cy, outer, thickness, self:shade(color), cursor, cursor + span)
            cursor = cursor + span
        end
    end

    -- A soft inner disc keeps the ring readable on busy panels.
    if inner > 1 then
        Pallid.UI.circle(el, cx, cy, inner, self:shade(Pallid.UI.Color.surface))
    end

    if self.centerText ~= nil and self.centerText ~= "" then
        self.valueStyle.color = self:shade(Pallid.UI.Color.textPrimary)
        Pallid.UI.text(el, self.centerText, cx, cy - (self.centerSubtext ~= nil and 7 or 0), self.valueStyle)
    end
    if self.centerSubtext ~= nil and self.centerSubtext ~= "" then
        self.subStyle.color = self:shade(Pallid.UI.Color.textMuted)
        Pallid.UI.text(el, self.centerSubtext, cx, cy + 11, self.subStyle)
    end

    if self._legendW > 0 then
        local rowH = 18
        local maxRows = math.max(1, math.floor(self.h / rowH))
        local count = math.min(#self.segments, maxRows)
        local startY = self:originY() + (self.h - count * rowH) * 0.5
        local style = self.legendStyle
        for i = 1, count do
            local segment = self.segments[i]
            local rowY = startY + (i - 1) * rowH
            local color = segment.color or PALETTE[(i - 1) % #PALETTE + 1]
            Pallid.UI.roundedRect(el, self._legendX, rowY + 5, 8, 8, 4, self:shade(color))
            style.color = self:shade(Pallid.UI.Color.text)
            style.maxWidth = math.max(0, self._legendW - 60)
            local label = segment.label or ""
            Pallid.UI.text(el, label, self._legendX + 14, rowY + rowH * 0.5, style)
            style.color = self:shade(Pallid.UI.Color.textMuted)
            style.alignH = "right"
            style.maxWidth = 48
            Pallid.UI.text(el, self._valueTexts[i] or "",
                self:originX() + self.w, rowY + rowH * 0.5, style)
            style.alignH = "left"
        end
        style.maxWidth = nil
    end
end
