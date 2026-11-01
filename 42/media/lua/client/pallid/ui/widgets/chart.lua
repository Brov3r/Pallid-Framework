require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/animation/track"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/tooltip"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local RECT_SHAPE = Pallid.UI.Shape.rect()

local DEFAULT_COLORS = {
    Pallid.UI.Color.primary,
    Pallid.UI.Color.secondary,
    Pallid.UI.Color.accent,
    Pallid.UI.Color.info,
    Pallid.UI.Color.warning,
    Pallid.UI.Color.success,
    Pallid.UI.Color.error,
    Pallid.UI.Color.primaryStrong,
}

local AXIS_GAP = 6
local AXIS_LEFT = 48
local LEGEND_HEIGHT = 22
local LEGEND_OVERFLOW_SPACE = 34

--- @param value any Value to check.
--- @return boolean finite True for a real, finite number.
local function isFinite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

--- Line, bar or sparkline chart with optional axes, grid, legend and tooltip.
---
--- `series` is an array of `{ name, values, color }`; `values` align with
--- `labels`. A sparkline turns axes, grid and legend off by default. The reveal
--- track draws the chart left-to-right (line/sparkline) or grows bars from the
--- baseline; update the widget once per frame so the track advances.
--- @class PallidChart : PallidWidget
--- @field mode string Chart mode: "line", "bar" or "sparkline".
--- @field series table[] Series definitions.
--- @field labels string[] X labels aligned with the values.
--- @field hoverIndex integer|nil Hovered point index, or nil.
--- @field maxDrawPoints integer|nil Per-series draw cap; nil auto, 0 unlimited.
--- @field reveal PallidAnimTrack Reveal animation track.
--- @field tooltip PallidTooltip Standard hover tooltip drawn by the root overlay.
--- @field tooltipEnabled boolean Whether hover builds the tooltip text.
local Chart = Widgets.class("Chart")

--- Creates a new `Chart` instance.
--- @param x number X coordinate.
--- @param y number Y coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Chart options.
--- @field opts.mode "line"|"bar"|"sparkline"|nil Defaults to "line".
--- @field opts.series table[]|nil `{ { name, values, color }, ... }`.
--- @field opts.labels string[]|nil X labels, aligned with values.
--- @field opts.axes boolean|nil Defaults to true; sparkline defaults to false.
--- @field opts.grid boolean|nil Defaults to true when axes are on.
--- @field opts.legend boolean|nil Defaults to true when more than one series is present.
--- @field opts.tooltip boolean|nil Defaults to true for line/bar, false for sparkline.
--- @field opts.min number|nil Explicit minimum value.
--- @field opts.max number|nil Explicit maximum value.
--- @field opts.includeZero boolean|nil Bar charts include zero by default.
--- @field opts.ticks integer|nil Horizontal grid lines. Defaults to 4.
--- @field opts.format function|string|nil Value formatter or `string.format` pattern.
--- @field opts.lineWidth number|nil Defaults to 2.
--- @field opts.showPoints boolean|nil True forces points, false hides them; nil auto for short lines.
--- @field opts.pointLimit integer|nil Max points for the automatic `showPoints`; defaults to 40.
--- @field opts.maxDrawPoints integer|nil Maximum points drawn per series. Nil uses an automatic plot-width cap; 0 disables the cap.
--- @field opts.animated boolean|nil Reveal animation. Defaults to true.
--- @field opts.background PallidColor|nil Background color.
--- @field opts.border PallidColor|nil Border color.
--- @field opts.gridColor PallidColor|nil Grid line color.
--- @field opts.axisColor PallidColor|nil Axis line color.
--- @field opts.radius number|nil Corner radius in pixels.
--- @field opts.fillInset number|nil Inset for the background fill; defaults to 1 when rounded.
--- @field opts.tooltipDelay number|nil Delay before the standard tooltip fades in; defaults to 0.12.
--- @return PallidChart New chart instance.
function Chart.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, Chart)
    self:init(x, y, w, h)

    self.mode = opts.mode or "line"
    local sparkline = self.mode == "sparkline"
    self.axes = opts.axes ~= nil and opts.axes or not sparkline
    self.grid = opts.grid ~= nil and opts.grid or (self.axes and not sparkline)
    self.legendExplicit = opts.legend
    self.legendEnabled = opts.legend == true
    self.tooltipEnabled = opts.tooltip ~= nil and opts.tooltip or (not sparkline)

    self.ticks = math.max(1, opts.ticks or 4)
    self.minOverride = opts.min
    self.maxOverride = opts.max
    self.includeZero = opts.includeZero
    if self.includeZero == nil then
        self.includeZero = self.mode == "bar"
    end
    self.valueFormat = opts.format
    self.lineWidth = opts.lineWidth or 2
    self.showPoints = opts.showPoints
    self.pointLimit = math.max(1, opts.pointLimit or 40)
    self.maxDrawPoints = opts.maxDrawPoints
    self._drawIndices = {}
    self._formatWarned = false
    self._legendOverflow = 0
    -- The chart uses the same hover tooltip widget as every other control; the
    -- root overlay paints it, including the native always-on-top host.
    self.tooltip = Widgets.Tooltip.new("", opts.tooltipDelay or 0.12)

    self.background = opts.background
    self.borderColor = opts.border
    self.radius = opts.radius or 4
    self.fillInset = opts.fillInset or (self.radius > 0 and 1 or 0)
    self.gridColor = opts.gridColor or Pallid.UI.Color.withAlpha(Pallid.UI.Color.border, 0.8)
    self.axisColor = opts.axisColor or Pallid.UI.Color.borderStrong
    self.hoverGuideColor = Pallid.UI.Color.withAlpha(Pallid.UI.Color.textMuted, 0.45)
    self.hoverSlotColor = Pallid.UI.Color.withAlpha(Pallid.UI.Color.textMuted, 0.1)

    self.axisStyle = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.textMuted,
        alignH = "right",
        alignV = "middle",
        ellipsis = "...",
    }
    self.xStyle = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.textMuted,
        alignH = "center",
        alignV = "top",
        maxWidth = 70,
        ellipsis = "...",
    }
    self.legendStyle = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.textMuted,
        alignH = "left",
        alignV = "middle",
    }

    self.series = {}
    self.labels = {}
    self.pointCount = 0
    self._values = {}
    self._tickStrings = {}
    self._tickYs = {}
    self._legendItems = {}
    self.hoverIndex = nil

    self.animated = opts.animated ~= false
    self.reveal = Pallid.UI.Anim.new({
        duration = 0.45,
        easing = Pallid.UI.Anim.ease.outCubic,
    })
    if not self.animated then
        self.reveal.value = 1
    end
    self:playIntro()

    self:setData(opts.series or {}, opts.labels)
    return self
end

--- Factory shortcut for `Chart.new`.
--- @param x number X coordinate.
--- @param y number Y coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional settings.
--- @return PallidChart New chart instance.
function Widgets.chart(x, y, w, h, opts)
    return Chart.new(x, y, w, h, opts)
end

--- Replaces the chart data.
--- @param series table[] Series definitions.
--- @param labels string[]|nil X labels, or nil to clear.
--- @param opts table|nil `{ animate = false }` shows new data without replaying the reveal.
--- @return PallidChart self The same instance, for chaining.
function Chart:setData(series, labels, opts)
    opts = opts or {}
    self.series = type(series) == "table" and series or {}
    self.labels = type(labels) == "table" and labels or {}

    self._values = {}
    local maxPoints = 0
    for i = 1, #self.series do
        local entry = self.series[i]
        local values = type(entry) == "table" and entry.values or {}
        if type(values) ~= "table" then
            values = {}
        end
        local count = #values
        local copy = {}
        for j = 1, count do
            local value = tonumber(values[j])
            if isFinite(value) then
                copy[j] = value
            end
        end
        self._values[i] = copy
        if count > maxPoints then
            maxPoints = count
        end
    end
    self.pointCount = math.max(maxPoints, #self.labels)

    if self.legendExplicit == nil then
        self.legendEnabled = #self.series > 1
    end
    self.hoverIndex = nil
    if self.tooltip ~= nil then
        self.tooltip:clear()
    end
    self:_layout()
    if opts.animate == false then
        self.reveal:stop()
        self.reveal.value = 1
        self.reveal.finished = true
    else
        self:playIntro()
    end
    return self
end

--- Replaces the chart series.
--- @param series table[] Series definitions.
--- @param labels string[]|nil X labels, or nil to clear.
--- @return PallidChart self The same instance, for chaining.
function Chart:setSeries(series, labels)
    return self:setData(series, labels)
end

--- Starts the intro reveal animation.
--- @return PallidChart self The same instance, for chaining.
function Chart:playIntro()
    if self.animated then
        self.reveal:play()
    end
    return self
end

--- Advances the reveal track. Per-frame so the chart animates smoothly.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function Chart:onAnimate(now, dt)
    if self.animated and self.reveal:isPlaying() then
        self.reveal:update(now)
    end
end

--- Sets the chart mode.
--- @param mode "line"|"bar"|"sparkline" Chart mode.
--- @return PallidChart self The same instance, for chaining.
function Chart:setMode(mode)
    if mode ~= "line" and mode ~= "bar" and mode ~= "sparkline" then
        Pallid.log("Chart:setMode: unknown mode '" .. tostring(mode) .. "'")
        return self
    end
    self.mode = mode
    self:_layout()
    return self
end

--- Shows or hides the axes.
--- @param axes boolean Whether to draw axes.
--- @return PallidChart self The same instance, for chaining.
function Chart:setAxes(axes)
    self.axes = axes and true or false
    self:_layout()
    return self
end

--- Shows or hides the grid.
--- @param grid boolean Whether to draw the grid.
--- @return PallidChart self The same instance, for chaining.
function Chart:setGrid(grid)
    self.grid = grid and true or false
    return self
end

--- Shows or hides the legend.
--- @param legend boolean Whether to draw the legend.
--- @return PallidChart self The same instance, for chaining.
function Chart:setLegend(legend)
    self.legendExplicit = legend and true or false
    self.legendEnabled = self.legendExplicit
    self:_layout()
    return self
end

--- Enables or disables the tooltip.
--- @param tooltip boolean Whether to enable the hover tooltip.
--- @return PallidChart self The same instance, for chaining.
function Chart:setTooltip(tooltip)
    self.tooltipEnabled = tooltip and true or false
    if not self.tooltipEnabled then
        self.hoverIndex = nil
        if self.tooltip ~= nil then
            self.tooltip:clear()
        end
    end
    return self
end

--- Sets the number of grid lines.
--- @param ticks integer Number of horizontal grid lines.
--- @return PallidChart self The same instance, for chaining.
function Chart:setTicks(ticks)
    self.ticks = math.max(1, math.floor(ticks or self.ticks))
    self:_layout()
    return self
end

--- Sets the value range.
--- @param min number|nil Explicit minimum, or nil for auto.
--- @param max number|nil Explicit maximum, or nil for auto.
--- @return PallidChart self The same instance, for chaining.
function Chart:setRange(min, max)
    self.minOverride = isFinite(min) and min or nil
    self.maxOverride = isFinite(max) and max or nil
    self:_layout()
    return self
end

--- Sets the chart colors.
--- @param background PallidColor|nil Background color, or nil to keep.
--- @param border PallidColor|nil Border color, or nil to keep.
--- @param gridColor PallidColor|nil Grid line color, or nil to keep.
--- @param axisColor PallidColor|nil Axis line color, or nil to keep.
--- @return PallidChart self The same instance, for chaining.
function Chart:setColors(background, border, gridColor, axisColor)
    if background ~= nil then self.background = background end
    if border ~= nil then self.borderColor = border end
    if gridColor ~= nil then self.gridColor = gridColor end
    if axisColor ~= nil then self.axisColor = axisColor end
    return self
end

--- Sets the series line width.
--- @param width number Width in pixels.
--- @return PallidChart self The same instance, for chaining.
function Chart:setLineWidth(width)
    self.lineWidth = math.max(1, width or self.lineWidth)
    return self
end

--- Overrides point visibility.
--- @param show boolean|nil Nil restores the automatic short-series rule.
--- @return PallidChart self The same instance, for chaining.
function Chart:setShowPoints(show)
    self.showPoints = show
    return self
end

--- Enables or disables the animation.
--- @param animated boolean Whether to animate the change.
--- @return PallidChart self The same instance, for chaining.
function Chart:setAnimated(animated)
    self.animated = animated and true or false
    if self.animated then
        self:playIntro()
    else
        self.reveal:stop()
        self.reveal.value = 1
        self.reveal.finished = true
    end
    return self
end

--- Rebuilds the layout after the caller mutated data or series in place.
--- @return PallidChart self The same instance, for chaining.
function Chart:refresh()
    self:_layout()
    return self
end

--- Updates the widget bounds.
--- @param x number X coordinate.
--- @param y number Y coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @return PallidChart self The same instance, for chaining.
function Chart:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:_layout()
    return self
end

function Chart:_warnFormat()
    if not self._formatWarned then
        self._formatWarned = true
        Pallid.log("Chart: value formatter failed; falling back to a plain number")
    end
end

--- Formats a value for display.
--- @param value number Value to format.
--- @return string Formatted value.
function Chart:formatValue(value)
    if not isFinite(value) then
        return tostring(value)
    end
    local formatter = self.valueFormat
    if type(formatter) == "function" then
        local ok, result = pcall(formatter, value)
        if ok and result ~= nil then
            return tostring(result)
        end
        if not ok then
            self:_warnFormat()
        end
        return string.format("%.0f", value)
    end
    if type(formatter) == "string" then
        local ok, result = pcall(string.format, formatter, value)
        if ok then
            return tostring(result)
        end
        self:_warnFormat()
        return string.format("%.0f", value)
    end
    return string.format("%.0f", value)
end

--- @param index integer Point index.
--- @return string Label for the point.
function Chart:_xLabel(index)
    local label = self.labels[index]
    if label ~= nil then
        return tostring(label)
    end
    return tostring(index)
end

--- @param index integer Series index.
--- @return string name Display name for a series.
function Chart:_seriesName(index)
    local entry = self.series[index]
    if type(entry) == "table" and entry.name ~= nil then
        return tostring(entry.name)
    end
    return "Series " .. index
end

--- @param index integer Series index.
--- @return PallidColor color Series colour, falling back to the default palette.
function Chart:_seriesColor(index)
    local entry = self.series[index]
    if type(entry) == "table" and type(entry.color) == "table" then
        return entry.color
    end
    return DEFAULT_COLORS[(index - 1) % #DEFAULT_COLORS + 1]
end

function Chart:_layout()
    local legend = self.legendEnabled and (#self.series > 1 or self.legendExplicit == true)
    -- A legend on a very short chart would cover the plot.
    if legend and self.h < 60 then
        legend = false
    end
    local right = 10
    local top = legend and LEGEND_HEIGHT or 8
    local bottom = 4
    if self.axes then
        bottom = self.labels[1] ~= nil and 24 or 16
    end
    if self.w < 80 then
        right = 4
    end
    if self.h < 60 then
        top = math.min(top, 4)
        bottom = math.min(bottom, 4)
    end

    local minValue = isFinite(self.minOverride) and self.minOverride or nil
    local maxValue = isFinite(self.maxOverride) and self.maxOverride or nil
    if minValue == nil or maxValue == nil then
        local lo, hi
        for i = 1, #self._values do
            local values = self._values[i]
            for j = 1, #values do
                local value = values[j]
                if value ~= nil then
                    if lo == nil or value < lo then
                        lo = value
                    end
                    if hi == nil or value > hi then
                        hi = value
                    end
                end
            end
        end
        lo = lo or 0
        hi = hi or 1
        if self.includeZero then
            lo = math.min(lo, 0)
            hi = math.max(hi, 0)
        end
        if minValue == nil then
            minValue = lo
        end
        if maxValue == nil then
            maxValue = hi
        end
    end
    if maxValue <= minValue then
        -- A flat or single-value series must not sit on the bottom edge.
        local pad = math.max(1, math.abs(minValue) * 0.1)
        minValue = minValue - pad
        maxValue = maxValue + pad
    end
    self.minValue = minValue
    self.maxValue = maxValue

    for i = 0, self.ticks do
        local value = maxValue - (maxValue - minValue) * (i / self.ticks)
        self._tickStrings[i + 1] = self:formatValue(value)
    end

    -- The left margin grows with the widest tick label, so a large number is
    -- not cut by the widget clip and does not spill into the next chart.
    local left = self.axes and AXIS_LEFT or 2
    if self.axes then
        local widest = 0
        for i = 1, #self._tickStrings do
            local width = getTextManager():MeasureStringX(self.axisStyle.font, self._tickStrings[i])
            if width > widest then
                widest = width
            end
        end
        left = math.max(left, widest + AXIS_GAP + 2)
    end
    if self.w < 80 then
        left = math.min(left, 8)
    end
    if left > self.w * 0.4 then
        left = math.floor(self.w * 0.4)
    end
    left = math.max(1, left)
    self.axisStyle.maxWidth = math.max(0, left - AXIS_GAP - 2)

    self._plotX = left
    self._plotY = top
    self._plotW = math.max(1, self.w - left - right)
    self._plotH = math.max(1, self.h - top - bottom)
    for i = 0, self.ticks do
        self._tickYs[i + 1] = self._plotY + (self._plotH * i / self.ticks)
    end

    self._xLabelIndices = {}
    if self.axes and self.labels[1] ~= nil and self.pointCount > 0 then
        local maxLabels = math.max(1, math.floor(self._plotW / 70))
        local stride = math.max(1, math.ceil(self.pointCount / maxLabels))
        for i = 1, self.pointCount, stride do
            self._xLabelIndices[#self._xLabelIndices + 1] = i
        end
        -- Shrink labels to their slot so neighbours do not overlap.
        self.xStyle.maxWidth = math.max(16, math.min(70, math.floor(self._plotW / maxLabels) - 4))
    end

    self._legendItems = {}
    self._legendOverflow = 0
    if legend then
        local cursor = self._plotX
        local maxX = self.w - 4
        for i = 1, #self.series do
            local name = self:_seriesName(i)
            local width = getTextManager():MeasureStringX(self.legendStyle.font, name)
            local need = 12 + width
            -- Reserve a little room for the "+N" overflow item.
            local limit = i == #self.series and maxX or (maxX - LEGEND_OVERFLOW_SPACE)
            if cursor + need > limit then
                self._legendOverflow = #self.series - i + 1
                break
            end
            self._legendItems[#self._legendItems + 1] = {
                name = name,
                color = self:_seriesColor(i),
                x = cursor,
                w = need,
            }
            cursor = cursor + need + 14
        end
    end

    self:_buildDrawIndices()
end

--- Precomputes the sampled point indexes used by drawing. The full data stays
--- intact for hover and tooltips; only the number of draw calls is reduced.
function Chart:_buildDrawIndices()
    local count = self.pointCount or 0
    local indices = self._drawIndices
    for i = #indices, 1, -1 do
        indices[i] = nil
    end
    if count <= 0 then
        return
    end
    if count <= 2 then
        for i = 1, count do
            indices[i] = i
        end
        return
    end

    local automatic = math.min(384, math.max(2, math.floor((self._plotW or 1) + 0.5)))
    local limit = self.maxDrawPoints
    if limit == nil then
        limit = automatic
    elseif type(limit) ~= "number" or limit ~= limit or limit <= 0 then
        limit = count
    else
        limit = math.floor(limit)
    end
    if limit >= count then
        for i = 1, count do
            indices[i] = i
        end
        return
    end
    limit = math.max(2, limit)

    -- One representative per bucket, chosen by its deviation from the straight
    -- line between bucket endpoints across every series. A plain stride can
    -- hide spikes; this keeps the shape and still caps draw calls.
    local segments = limit - 1
    indices[1] = 1
    local previous = 1
    for k = 1, segments - 1 do
        local start = math.floor((k - 1) * (count - 1) / segments) + 1
        local finish = math.floor(k * (count - 1) / segments) + 1
        if start <= previous then
            start = previous + 1
        end
        if start > count then
            start = count
        end
        if finish < start then
            finish = start
        end
        if finish > count then
            finish = count
        end

        local best = start
        local bestDeviation = -1
        for index = start, finish do
            local deviation = 0
            local t = (index - start) / math.max(1, finish - start)
            for s = 1, #self._values do
                local values = self._values[s]
                local first, last, value = values[start], values[finish], values[index]
                if first ~= nil and last ~= nil and value ~= nil then
                    local expected = first + (last - first) * t
                    local delta = math.abs(value - expected)
                    if delta > deviation then
                        deviation = delta
                    end
                end
            end
            if deviation > bestDeviation then
                bestDeviation = deviation
                best = index
            end
        end
        if best <= previous then
            best = math.min(count, previous + 1)
        end
        indices[k + 1] = best
        previous = best
    end
    indices[limit] = count
end

--- @param index integer Point index.
--- @return number x X coordinate.
function Chart:_xAt(index)
    local count = math.max(1, self.pointCount or 0)
    if count == 1 then
        return self._plotX + self._plotW * 0.5
    end
    if self.mode == "bar" then
        return self._plotX + (index - 0.5) * (self._plotW / count)
    end
    return self._plotX + (index - 1) * (self._plotW / (count - 1))
end

--- @param value number Value to map.
--- @return number y Y coordinate.
function Chart:_yAt(value)
    local span = self.maxValue - self.minValue
    if span <= 0 then
        span = 1
    end
    return self._plotY + self._plotH - ((value - self.minValue) / span) * self._plotH
end

--- Updates hover state for the current pointer position.
--- @param px number Pointer X in local coordinates.
--- @param py number Pointer Y in local coordinates.
function Chart:onHoverMove(px, py)
    if not self.tooltipEnabled or self.pointCount <= 0 then
        self.hoverIndex = nil
        if self.tooltip ~= nil then
            self.tooltip:clear()
        end
        return
    end
    local x = px - self:originX()
    local y = py - self:originY()
    if x < self._plotX or x > self._plotX + self._plotW or y < self._plotY or y > self._plotY + self._plotH then
        -- Leaving the plot (into the axes, legend or padding) must hide the
        -- tooltip instead of freezing the last hovered point.
        self.hoverIndex = nil
        if self.tooltip ~= nil then
            self.tooltip:clear()
        end
        return
    end

    local index
    if self.mode == "bar" then
        index = math.floor((x - self._plotX) / math.max(1, self._plotW / math.max(1, self.pointCount))) + 1
    elseif self.pointCount <= 1 then
        index = 1
    else
        local step = self._plotW / (self.pointCount - 1)
        index = math.floor((x - self._plotX) / step + 0.5) + 1
    end
    index = math.max(1, math.min(self.pointCount, index))
    if index ~= self.hoverIndex then
        self.hoverIndex = index
        self:_buildTooltip(index)
    end
end

--- Clears hover state when the pointer leaves.
function Chart:onHoverEnd()
    self.hoverIndex = nil
    if self.tooltip ~= nil then
        self.tooltip:clear()
    end
    Widgets.Widget.onHoverEnd(self)
end

--- Builds rich tooltip rows: the X label is the title and every series gets a
--- colour swatch, its name and the formatted value for that point.
--- @param index integer Point index under the cursor.
function Chart:_buildTooltip(index)
    if not self.tooltipEnabled or self.tooltip == nil then
        return
    end

    local tooltip = self.tooltip
    tooltip:setTitle(self:_xLabel(index))

    local rows = {}
    for i = 1, #self.series do
        local values = self._values[i]
        local value = values and values[index] or nil
        if value ~= nil then
            rows[#rows + 1] = {
                swatch = self:_seriesColor(i),
                label  = self:_seriesName(i),
                value  = self:formatValue(value),
            }
        end
    end
    tooltip:setRows(rows)
end

--- Draws text with the widget's disabled shade applied, then restores the
--- shared style colour.
--- @param el ISUIElement Host element used for drawing.
--- @param text string Text to process.
--- @param x number X coordinate.
--- @param y number Y coordinate.
--- @param style PallidTextStyle Text style.
function Chart:_text(el, text, x, y, style)
    local base = style.color
    style.color = self:shade(base)
    Pallid.UI.text(el, text, x, y, style)
    style.color = base
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element used for drawing.
function Chart:drawSelf(el)
    local x, y = self:originX(), self:originY()
    if self.w <= 0 or self.h <= 0 then
        return
    end

    -- Charts often sit next to each other in dashboards. Clip every primitive
    -- (axis labels, points, legend, tooltip) to the widget box so a label or a
    -- hovering tooltip cannot paint over the neighbour.
    local entered = Pallid.UI.clip(el, RECT_SHAPE, x, y, self.w, self.h)

    if self.background ~= nil then
        local inset = self.fillInset or 0
        local radius = self.radius
        if inset > 0 and type(radius) == "number" then
            radius = math.max(0, radius - inset)
        end
        if radius ~= nil and radius ~= 0 then
            Pallid.UI.roundedRect(
                el, x + inset, y + inset, self.w - inset * 2, self.h - inset * 2,
                radius, self:shade(self.background)
            )
        else
            Pallid.UI.rect(el, x + inset, y + inset, self.w - inset * 2, self.h - inset * 2,
                self:shade(self.background))
        end
    end
    if self.borderColor ~= nil then
        if self.radius ~= nil and self.radius ~= 0 then
            Pallid.UI.roundedBorder(el, x, y, self.w, self.h, self.radius, 1, self:shade(self.borderColor))
        else
            Pallid.UI.border(el, x, y, self.w, self.h, 1, self:shade(self.borderColor))
        end
    end

    local plotX, plotY = x + self._plotX, y + self._plotY
    local plotW, plotH = self._plotW, self._plotH
    local progress = self.animated and self.reveal.value or 1

    if self.grid then
        for i = 1, #self._tickYs do
            local lineY = plotY + (self._tickYs[i] - self._plotY)
            Pallid.UI.line(el, plotX, lineY, plotX + plotW, lineY, 1, self:shade(self.gridColor))
        end
    end

    if self.axes then
        Pallid.UI.line(el, plotX, plotY, plotX, plotY + plotH, 1, self:shade(self.axisColor))
        Pallid.UI.line(el, plotX, plotY + plotH, plotX + plotW, plotY + plotH, 1, self:shade(self.axisColor))
        for i = 1, #self._tickStrings do
            local lineY = plotY + (self._tickYs[i] - self._plotY)
            if (self.axisStyle.maxWidth or 0) > 0 then
                self:_text(el, self._tickStrings[i], plotX - AXIS_GAP, lineY, self.axisStyle)
            end
        end

        local baseAlign = self.xStyle.alignH
        for i = 1, #self._xLabelIndices do
            local index = self._xLabelIndices[i]
            local labelX = x + self:_xAt(index)
            self.xStyle.alignH = "center"
            -- Keep the first and last visible labels inside the plot instead
            -- of letting their halves spill past the widget edge.
            if self.mode ~= "bar" and index == 1 and #self._xLabelIndices > 1 then
                labelX = plotX
                self.xStyle.alignH = "left"
            elseif self.mode ~= "bar" and index == self.pointCount and #self._xLabelIndices > 1 then
                labelX = plotX + plotW
                self.xStyle.alignH = "right"
            end
            self:_text(el, self:_xLabel(index), labelX, plotY + plotH + 5, self.xStyle)
        end
        self.xStyle.alignH = baseAlign
    end

    if self.hoverIndex ~= nil and self.mode == "bar" and self.pointCount > 0 then
        local slotW = plotW / self.pointCount
        Pallid.UI.rect(
            el,
            plotX + (self.hoverIndex - 1) * slotW,
            plotY,
            slotW,
            plotH,
            self:shade(self.hoverSlotColor)
        )
    end

    local showPoints = self.showPoints
    if showPoints == nil then
        showPoints = self.mode == "line" and self.pointCount <= self.pointLimit
    end

    if self.mode == "bar" then
        self:_drawBars(el, plotX, plotY, plotW, plotH, progress)
    else
        self:_drawLines(el, plotX, plotY, plotW, plotH, progress, showPoints)
    end

    if self.hoverIndex ~= nil then
        self:_drawHover(el, plotX, plotY, plotW, plotH)
    end

    if #self._legendItems > 0 then
        local legendY = y + 4
        for i = 1, #self._legendItems do
            local item = self._legendItems[i]
            Pallid.UI.rect(el, x + item.x, legendY + 3, 8, 8, self:shade(item.color))
            self:_text(el, item.name, x + item.x + 12, legendY + 7, self.legendStyle)
        end
    end
    if self._legendOverflow > 0 then
        local more = "+" .. self._legendOverflow
        local width = getTextManager():MeasureStringX(self.legendStyle.font, more)
        self:_text(el, more, x + self.w - 4 - width, y + 4 + 7, self.legendStyle)
    end

    if entered then
        Pallid.UI.clipEnd(el)
    end
end
--- @param el ISUIElement Host element used for drawing.
--- @param plotX number Plot area X coordinate.
--- @param plotY number Plot area Y coordinate.
--- @param plotW number Plot area width in pixels.
--- @param plotH number Plot area height in pixels.
--- @param progress number Reveal progress in the 0..1 range.
--- @param showPoints boolean Point visibility override.
function Chart:_drawLines(el, plotX, plotY, plotW, plotH, progress, showPoints) -- luacheck: ignore
    local indices = self._drawIndices
    local drawCount = #indices
    if drawCount <= 0 then
        return
    end

    local limit = math.max(0, drawCount - 1) * progress
    for s = 1, #self._values do
        local values = self._values[s]
        local color = self:shade(self:_seriesColor(s))

        for k = 2, drawCount do
            local i1, i2 = indices[k - 1], indices[k]
            local a, b = values[i1], values[i2]
            if a ~= nil and b ~= nil then
                local t = limit - (k - 2)
                if t > 0 then
                    if t > 1 then
                        t = 1
                    end
                    local x1 = plotX + (self:_xAt(i1) - self._plotX)
                    local y1 = plotY + (self:_yAt(a) - self._plotY)
                    local x2 = plotX + (self:_xAt(i2) - self._plotX)
                    local y2 = plotY + (self:_yAt(b) - self._plotY)
                    if t < 1 then
                        x2 = x1 + (x2 - x1) * t
                        y2 = y1 + (y2 - y1) * t
                    end
                    Pallid.UI.line(el, x1, y1, x2, y2, self.lineWidth, color)
                end
            end
        end

        if showPoints and progress > 0 then
            for k = 1, drawCount do
                local index = indices[k]
                local value = values[index]
                if value ~= nil and (k - 1) <= limit + 0.0001 then
                    local px = plotX + (self:_xAt(index) - self._plotX)
                    local py = plotY + (self:_yAt(value) - self._plotY)
                    Pallid.UI.circle(el, px, py, math.max(2, self.lineWidth), color)
                end
            end
        end
    end
end

--- Draws the hover guide and point markers for line/sparkline charts.
--- @param el ISUIElement Host element used for drawing.
--- @param plotX number Plot area X coordinate.
--- @param plotY number Plot area Y coordinate.
--- @param plotW number Plot area width in pixels.
--- @param plotH number Plot area height in pixels.
function Chart:_drawHover(el, plotX, plotY, plotW, plotH)
    local index = self.hoverIndex
    if index == nil or self.mode == "bar" then
        return
    end

    local hx = plotX + (self:_xAt(index) - self._plotX)
    Pallid.UI.line(el, hx, plotY, hx, plotY + plotH, 1, self:shade(self.hoverGuideColor))

    local ringColor = self:shade(self.background or Pallid.UI.Color.surface)
    for s = 1, #self._values do
        local values = self._values[s]
        local value = values and values[index] or nil
        if value ~= nil then
            local hy = plotY + (self:_yAt(value) - self._plotY)
            Pallid.UI.circle(el, hx, hy, self.lineWidth + 3, ringColor)
            Pallid.UI.circle(el, hx, hy, self.lineWidth + 1, self:shade(self:_seriesColor(s)))
        end
    end
end

--- @param el ISUIElement Host element used for drawing.
--- @param plotX number Plot area X coordinate.
--- @param plotY number Plot area Y coordinate.
--- @param plotW number Plot area width in pixels.
--- @param plotH number Plot area height in pixels.
--- @param progress number Reveal progress in the 0..1 range.
function Chart:_drawBars(el, plotX, plotY, plotW, plotH, progress)
    local count = self.pointCount
    local buckets = #self._drawIndices
    if count <= 0 or buckets <= 0 then
        return
    end
    local groups = math.max(1, #self._values)
    local slotW = plotW / count
    local bucketSize = count / buckets
    local baseValue = self.minValue <= 0 and 0 or self.minValue
    local baseY = plotY + (self:_yAt(baseValue) - self._plotY)

    for s = 1, #self._values do
        local values = self._values[s]
        local color = self:shade(self:_seriesColor(s))
        for k = 1, buckets do
            local first = math.floor((k - 1) * bucketSize) + 1
            local last = math.min(count, math.floor(k * bucketSize))
            if last < first then
                last = first
            end

            -- Keep the extreme of the bucket so decimation does not hide spikes.
            local value = nil
            local strongest = -1
            for i = first, last do
                local candidate = values[i]
                if candidate ~= nil then
                    local strength = math.abs(candidate - baseValue)
                    if strength > strongest then
                        strongest = strength
                        value = candidate
                    end
                end
            end

            if value ~= nil then
                local targetY = plotY + (self:_yAt(value) - self._plotY)
                local barY = baseY + (targetY - baseY) * progress
                local top = math.min(baseY, barY)
                local height = math.abs(baseY - barY)
                if height > 0 then
                    local span = last - first + 1
                    local barW = math.max(1, (slotW * span * 0.72) / groups)
                    local centerX = plotX + (((first + last) * 0.5) - 0.5) * slotW
                    local barX = centerX - (barW * groups) * 0.5 + (s - 1) * barW
                    if barW < 4 then
                        -- A rounded quad costs several draw calls; sub-4px bars
                        -- are visually identical as plain rects.
                        Pallid.UI.rect(el, barX, top, barW, height, color)
                    else
                        Pallid.UI.roundedRect(
                            el, barX, top, barW, height, math.min(2, barW * 0.5), color
                        )
                    end
                end
            end
        end
    end
end
