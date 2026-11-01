require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/text"
require "pallid/ui/animation/track"
require "pallid/ui/widgets/tooltip/layout"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets or {}
Pallid.UI.Widgets = Widgets

local Layout = Pallid.UI.TooltipLayout

local PADDING        = Layout.PADDING
local MAX_WIDTH      = 280
local MAX_LINES      = 8
local LINE_SPACING   = 2
local SHOW_DURATION  = 0.10
local CLOSE_DURATION = 0.08
local DEFAULT_DELAY  = 0.12

local COLOR_TITLE     = Pallid.UI.Color.textPrimary
local COLOR_BODY      = Pallid.UI.Color.text
local COLOR_LABEL     = Pallid.UI.Color.textMuted
local COLOR_VALUE     = Pallid.UI.Color.textPrimary
local COLOR_SECTION   = Pallid.UI.Color.textMuted
local COLOR_FOOTER    = Pallid.UI.Color.textMuted
local COLOR_SEPARATOR = Pallid.UI.Color.border

--- One row of a rich tooltip.
--- @class PallidTooltipRow
--- @field icon string|false|nil Registered icon name or texture path; false draws nothing.
--- @field swatch PallidColor|nil Colour chip drawn instead of an icon.
--- @field label string|nil Primary text; ignored by a section row.
--- @field value string|number|nil Value aligned to the right edge.
--- @field labelColor PallidColor|nil Label colour override.
--- @field valueColor PallidColor|nil Value colour override.
--- @field section string|boolean|nil Section heading text, or true to use `label` as the heading.
--- @field separator boolean|nil Draws a divider above the row.

--- Hover tooltip with a short fade-in/slide and a faster fade-out. Owned by
--- the widget that called `setTooltip`; the root draws it after the tree so it
--- stays on top.
---
--- The body may be plain multiline text (`\n`) for backward compatibility. The
--- rich mode adds a title, rows with icons or colour swatches, section
--- headings, separators and a footer. Layout is cached until the content or the
--- maximum width changes, so drawing does not measure or allocate each frame.
--- @class PallidTooltip
--- @field text string Plain body text; an empty string has no body paragraph.
--- @field title string Title drawn above the body in a bold face.
--- @field rows PallidTooltipRow[] Rich rows owned by the tooltip, in draw order.
--- @field footer string Muted text drawn below a divider.
--- @field delay number Seconds before the fade starts.
--- @field maxWidth number Width cap in pixels, including padding.
--- @field maxLines integer Maximum wrapped lines for the plain body.
--- @field style PallidTextStyle Body text style.
--- @field titleStyle PallidTextStyle Title text style.
--- @field labelStyle PallidTextStyle Row label style.
--- @field valueStyle PallidTextStyle Right-aligned value style.
--- @field sectionStyle PallidTextStyle Section heading style.
--- @field footerStyle PallidTextStyle Footer style.
--- @field fill PallidColor Background color; its alpha follows the fade.
--- @field border PallidColor Border color; its alpha follows the fade.
--- @field track PallidAnimTrack Fade-in track driving alpha and the slide.
--- @field closeTrack PallidAnimTrack Fade-out track used by reset and clear.
--- @field started boolean True once the current fade-in has been started.
--- @field closing boolean True while the fade-out track is running.
--- @field dismissed boolean True when the tooltip was asked to hide.
local Tooltip = {}
Tooltip.__index = Tooltip
Widgets.Tooltip = Tooltip

--- Creates a new `Tooltip` instance.
--- @param text string|nil Tooltip body; an empty string starts empty.
--- @param delay number|nil Seconds before the fade starts; defaults to 0.12.
--- @return PallidTooltip tooltip New tooltip instance.
function Tooltip.new(text, delay)
    local self = setmetatable({}, Tooltip)
    self.text = text or ""
    self.title = ""
    self.rows = {}
    self.footer = ""
    self.delay = delay ~= nil and math.max(0, delay) or DEFAULT_DELAY
    self.maxWidth = MAX_WIDTH
    self.maxLines = MAX_LINES

    self.dismissed = false
    self.closing = false
    self.started = false
    self._closed = false
    self._clearOnClose = false

    self._dirty = true
    self._layoutWidth = -1
    self._items = {}
    self._itemCount = 0
    self._boxW = 0
    self._boxH = 0
    self._contentW = 0

    self.style = {
        font        = Pallid.UI.Fonts.small,
        color       = COLOR_BODY,
        maxWidth    = MAX_WIDTH - PADDING * 2,
        wrap        = true,
        maxLines    = MAX_LINES,
        lineSpacing = LINE_SPACING,
    }
    self.titleStyle = {
        font        = Pallid.UI.Fonts.small,
        color       = COLOR_TITLE,
        bold        = true,
        maxWidth    = MAX_WIDTH - PADDING * 2,
        wrap        = true,
        maxLines    = 2,
        lineSpacing = LINE_SPACING,
    }
    self.labelStyle = {
        font     = Pallid.UI.Fonts.small,
        color    = COLOR_LABEL,
        alignH   = "left",
        alignV   = "middle",
        maxWidth = 0,
    }
    self.valueStyle = {
        font   = Pallid.UI.Fonts.small,
        color  = COLOR_VALUE,
        alignH = "right",
        alignV = "middle",
    }
    self.sectionStyle = {
        font     = Pallid.UI.Fonts.small,
        color    = COLOR_SECTION,
        bold     = true,
        maxWidth = 0,
    }
    self.footerStyle = {
        font        = Pallid.UI.Fonts.small,
        color       = COLOR_FOOTER,
        maxWidth    = MAX_WIDTH - PADDING * 2,
        wrap        = true,
        maxLines    = 2,
        lineSpacing = LINE_SPACING,
    }

    self.fill = {
        r = Pallid.UI.Color.surfaceElevated.r,
        g = Pallid.UI.Color.surfaceElevated.g,
        b = Pallid.UI.Color.surfaceElevated.b,
        a = 0.98,
    }
    self.border = Pallid.UI.Color.border

    -- The fade-out is a second track: a short hover can be dismissed mid-fade
    -- without snapping the tooltip back to full opacity.
    self.track = Pallid.UI.Anim.new({
        duration = SHOW_DURATION,
        easing   = Pallid.UI.Anim.ease.outCubic,
        alpha    = { 0, 1 },
        dy       = { 4, 0 },
    })
    self.closeTrack = Pallid.UI.Anim.new({
        duration = CLOSE_DURATION,
        easing   = Pallid.UI.Anim.ease.outCubic,
        alpha    = { 1, 0 },
        dy       = { 0, -3 },
    })
    return self
end

--- Marks the cached layout as stale.
function Tooltip:_invalidate()
    self._dirty = true
end

--- Drops the content of a dismissed tooltip after its fade-out.
function Tooltip:_wipe()
    self.title = ""
    self.text = ""
    self.rows = {}
    self.footer = ""
    self._clearOnClose = false
    self:_invalidate()
end

--- Cancels a fade-out so the next `show` replays the fade-in.
function Tooltip:_wake()
    self.dismissed = false
    self.closing = false
    self._closed = false
    self._clearOnClose = false
    self.started = false
    self.closeTrack:stop()
end

--- Marks newly assigned content as active and replays the fade after a close.
function Tooltip:_prepareContent()
    if self._closed or self.closing or self.dismissed then
        self:_wake()
    end
    self.dismissed = false
    self._clearOnClose = false
end

--- Returns true when the widget has content.
--- @return boolean hasContent True when there is anything to paint.
function Tooltip:hasContent()
    return self.title ~= "" or self.text ~= "" or self.footer ~= "" or #self.rows > 0
end

--- True when the tooltip has no title, body, rows or footer. A tooltip that is
--- fading out still has content, so the host keeps painting it until the fade
--- finishes.
--- @return boolean empty True when the tooltip has no content.
function Tooltip:isEmpty()
    return not self:hasContent()
end

--- True once a fade-out has finished; the host hides itself then.
--- @return boolean closed True when the tooltip was closed.
function Tooltip:isClosed()
    return self._closed
end

--- Replaces the plain body text. An empty string hides the tooltip when it has
--- no rich content; use `clear` to hide a rich tooltip explicitly.
--- @param text string|nil New body text; may contain `\n`.
--- @return PallidTooltip self For chaining.
function Tooltip:setText(text)
    text = text or ""
    if text == "" then
        if self.title == "" and #self.rows == 0 and self.footer == "" then
            return self:clear()
        end
        self.text = ""
        self:_invalidate()
        return self
    end

    self:_prepareContent()
    self.text = text
    self:_invalidate()
    return self
end

--- Sets the title drawn above the body in a bold face.
--- @param title string|nil Title text; nil or an empty string removes it.
--- @return PallidTooltip self For chaining.
function Tooltip:setTitle(title)
    self:_prepareContent()
    self.title = title or ""
    self:_invalidate()
    return self
end

--- Replaces all rich rows. Rows are copied, so the caller may reuse its table.
--- @param rows PallidTooltipRow[]|nil Rows in draw order; nil removes every row.
--- @return PallidTooltip self For chaining.
function Tooltip:setRows(rows)
    self:_prepareContent()
    local list = {}
    if type(rows) == "table" then
        for i = 1, #rows do
            list[i] = Layout.copyRow(rows[i])
        end
    end
    self.rows = list
    self:_invalidate()
    return self
end

--- Appends one rich row.
--- @param row PallidTooltipRow Row to append; copied before it is stored.
--- @return PallidTooltip self For chaining.
function Tooltip:addRow(row)
    self:_prepareContent()
    self.rows[#self.rows + 1] = Layout.copyRow(row)
    self:_invalidate()
    return self
end

--- Sets the muted footer drawn below a divider.
--- @param footer string|nil Footer text; nil or an empty string removes it.
--- @return PallidTooltip self For chaining.
function Tooltip:setFooter(footer)
    self:_prepareContent()
    self.footer = footer or ""
    self:_invalidate()
    return self
end

--- Sets the width cap, including padding. Narrow caps truncate labels and wrap
--- the body, title and footer.
--- @param width number|nil Width in pixels; defaults to 280.
--- @return PallidTooltip self For chaining.
function Tooltip:setMaxWidth(width)
    self.maxWidth = math.max(60, width or MAX_WIDTH)
    self:_invalidate()
    return self
end

--- Sets how many wrapped lines the plain body may use.
--- @param lines integer|nil Maximum line count; defaults to 8.
--- @return PallidTooltip self For chaining.
function Tooltip:setMaxLines(lines)
    self.maxLines = math.max(1, lines or MAX_LINES)
    self.style.maxLines = self.maxLines
    self:_invalidate()
    return self
end

--- Hides the tooltip with a fade-out and drops its content afterwards. Use this
--- instead of `setText("")` for rich tooltips. Hiding a tooltip that never
--- appeared drops the content immediately.
--- @return PallidTooltip self For chaining.
function Tooltip:clear()
    if not self:hasContent() then
        self.dismissed = true
        self:beginClose()
        return self
    end
    self._clearOnClose = true
    self.dismissed = true
    self:beginClose()
    return self
end

--- Shows the tooltip and starts the fade-in. Safe to call every frame while
--- hovered: a running fade is left alone, while a dismissed tooltip is woken.
--- @param now number|nil Current time in seconds; nil reads the clock.
--- @return PallidTooltip self For chaining.
function Tooltip:show(now)
    if self._closed or self.closing or self.dismissed then
        if not self:hasContent() or self._clearOnClose then
            return self
        end
        self:_wake()
    end
    if not self.started then
        self.started = true
        self.track.delay = self.delay
        self.track:play(now)
    end
    return self
end

--- Starts the fade-out. Repeated calls are ignored, so the root may hide the
--- host every frame without restarting the animation.
--- @param now number|nil Current time in seconds; nil reads the clock.
--- @return PallidTooltip self For chaining.
function Tooltip:beginClose(now)
    if self.closing or self._closed then
        return self
    end
    if not self.started then
        self._closed = true
        self.dismissed = true
        if self._clearOnClose then
            self:_wipe()
        end
        return self
    end
    self.started = false
    self.closing = true
    self.dismissed = true
    self.closeTrack:play(now)
    return self
end

--- Hides the tooltip but keeps its content, so hovering again replays the
--- fade-in with the same content. Called by `Widget:onHoverEnd`.
--- @return PallidTooltip self For chaining.
function Tooltip:reset()
    return self:beginClose()
end

--- Rebuilds the cached layout when the content or width changed.
function Tooltip:_ensureLayout()
    if not self._dirty and self._layoutWidth == self.maxWidth then
        return
    end
    self._dirty = false
    self._layoutWidth = self.maxWidth
    Layout.build(self)
end
