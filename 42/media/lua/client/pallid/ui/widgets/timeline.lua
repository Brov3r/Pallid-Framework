require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/virtuallist"
local ValueField = require "pallid/ui/widgets/internal/value_field"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local ROW_HEIGHT = 46
local LINE_X = 12
local DOT_RADIUS = 4

--- Vertical activity timeline. Entries are plain tables with `title`, optional
--- `text`, `time` and `color`; rows are virtualised by a ListBox-style internal
--- list, so a long history scrolls without building a child per row.
--- @class PallidTimeline : PallidWidget
--- @field entries table[] Normalised timeline entries.
--- @field list PallidVirtualList Row renderer.
--- @field rowHeight number|fun(index: integer): number Default row height.
--- @field onSelect fun(timeline: PallidTimeline, index: integer, entry: table)|nil Row click callback.
--- @field lineColor PallidColor Connector line colour.
--- @field markerColor PallidColor Default marker colour.
local Timeline = Widgets.class("Timeline")

--- Creates a new `Timeline` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Entries and appearance.
--- @field opts.entries table[]|nil Initial entries: `{ title, text?, time?, color? }`.
--- @field opts.rowHeight number|fun(index: integer): number|nil Row height, defaults to 46.
--- @field opts.background PallidColor|nil Panel fill.
--- @field opts.border PallidColor|nil Panel outline.
--- @field opts.radius number|nil Corner radius, defaults to 4.
--- @field opts.lineColor PallidColor|nil Connector colour.
--- @field opts.markerColor PallidColor|nil Default marker colour.
--- @field opts.onSelect fun(timeline: PallidTimeline, index: integer, entry: table)|nil Row click callback.
--- @return PallidTimeline timeline New timeline.
function Timeline.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, Timeline)
    self:init(x, y, w or 0, h or 0)

    self.entries = {}
    self.rowHeight = opts.rowHeight or ROW_HEIGHT
    self.background = opts.background or Pallid.UI.Color.surface
    self.borderColor = opts.border or Pallid.UI.Color.border
    self.radius = opts.radius or 4
    self.lineColor = opts.lineColor or Pallid.UI.Color.border
    self.markerColor = opts.markerColor or Pallid.UI.Color.primary
    self.onSelect = opts.onSelect
    self.rowHover = Pallid.UI.Color.accentSoft
    self.rowSelected = Pallid.UI.Color.primarySoft
    self._selected = nil

    self.titleStyle = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.textPrimary,
        alignH = "left",
        alignV = "middle",
        ellipsis = "...",
    }
    self.textStyle = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.textMuted,
        alignH = "left",
        alignV = "middle",
        ellipsis = "...",
    }
    self.timeStyle = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.textMuted,
        alignH = "right",
        alignV = "middle",
        ellipsis = "...",
    }

    self.list = Widgets.virtualList(0, 0, self.w, self.h, {
        itemCount     = 0,
        rowHeight     = self.rowHeight,
        selectionMode = "single",
        onSelect      = function(_, index)
            self._selected = index
            if self.onSelect ~= nil then
                self.onSelect(self, index, self.entries[index])
            end
        end,
        render        = function(el, index, rowX, rowY, rowW, rowH, state)
            self:_drawRow(el, index, rowX, rowY, rowW, rowH, state)
        end,
    })
    self:add(self.list)

    self:setEntries(opts.entries)
    return self
end

--- Factory shortcut for `Timeline.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Entries and appearance; see `Timeline.new`.
--- @return PallidTimeline timeline New timeline.
function Widgets.timeline(x, y, w, h, opts)
    return Timeline.new(x, y, w, h, opts)
end

--- Converts a string or table into the internal entry shape.
--- @param entry table|string Source entry.
--- @return table entry Normalised entry.
local function normaliseEntry(entry)
    if type(entry) ~= "table" then
        return { title = tostring(entry), text = "", time = "", color = nil }
    end
    return {
        title = entry.title or entry.label or "",
        text  = entry.text or "",
        time  = entry.time or "",
        color = entry.color,
        raw   = entry,
    }
end

--- Replaces every entry.
--- @param entries table[]|nil New entries.
--- @return PallidTimeline self For chaining.
function Timeline:setEntries(entries)
    self.entries = {}
    if type(entries) == "table" then
        for i = 1, #entries do
            self.entries[i] = normaliseEntry(entries[i])
        end
    end
    self.list:setItemCount(#self.entries)
    self.list:setSelected(nil, true)
    self._selected = nil
    return self
end

--- Appends one entry.
--- @param entry table|string Entry to append.
--- @return PallidTimeline self For chaining.
function Timeline:addEntry(entry)
    self.entries[#self.entries + 1] = normaliseEntry(entry)
    self.list:setItemCount(#self.entries)
    return self
end

--- Scrolls to an entry.
--- @param index integer One-based entry index.
--- @return PallidTimeline self For chaining.
function Timeline:scrollToEntry(index)
    local top = self.list:rowOffset(index)
    self.list:scrollTo(top)
    return self
end

--- Paints one row: highlight, marker, title, time and text.
--- @param el ISUIElement Host element.
--- @param index integer One-based entry index.
--- @param x number Row left.
--- @param y number Row top.
--- @param w number Row width.
--- @param h number Row height.
--- @param state PallidVirtualRowState Reused row state.
function Timeline:_drawRow(el, index, x, y, w, h, state)
    local entry = self.entries[index]
    if entry == nil then
        return
    end
    if self._selected == index then
        Pallid.UI.rect(el, x, y, w, h, self:shade(self.rowSelected))
    elseif state.hovered then
        Pallid.UI.rect(el, x, y, w, h, self:shade(self.rowHover))
    end

    local centerX = x + LINE_X
    Pallid.UI.line(el, centerX, y, centerX, y + h, 1, self:shade(self.lineColor))
    Pallid.UI.circle(el, centerX, y + 16, DOT_RADIUS, self:shade(entry.color or self.markerColor))

    local titleX = centerX + 12
    local titleW = math.max(0, w - (titleX - x) - 64)
    local title = self.titleStyle
    title.color = self:shade(Pallid.UI.Color.textPrimary)
    title.maxWidth = titleW
    Pallid.UI.text(el, entry.title, titleX, y + 12, title)
    title.maxWidth = nil

    if entry.time ~= "" then
        local time = self.timeStyle
        time.color = self:shade(Pallid.UI.Color.textMuted)
        time.maxWidth = 58
        Pallid.UI.text(el, entry.time, x + w - 6, y + 12, time)
        time.maxWidth = nil
    end

    if entry.text ~= "" then
        local text = self.textStyle
        text.color = self:shade(Pallid.UI.Color.textMuted)
        text.maxWidth = math.max(0, w - (titleX - x) - 10)
        Pallid.UI.text(el, entry.text, titleX, y + 29, text)
        text.maxWidth = nil
    end
end

--- Paints the timeline chrome and the empty state.
--- @param el ISUIElement Host element the tree is rendered into.
function Timeline:drawSelf(el)
    local x, y = self:originX(), self:originY()
    Pallid.UI.roundedRect(el, x, y, self.w, self.h, self.radius, self:shade(self.background))
    Pallid.UI.roundedBorder(el, x, y, self.w, self.h, self.radius, 1, self:shade(self.borderColor))
    if #self.entries == 0 then
        local style = self.textStyle
        style.color = self:shade(Pallid.UI.Color.textMuted)
        style.alignH = "center"
        style.maxWidth = math.max(0, self.w - 16)
        Pallid.UI.text(el, Pallid.UI.translate("UI_Pallid_NoItems", "No entries"), x + self.w * 0.5, y + self.h * 0.5, style)
        style.alignH = "left"
        style.maxWidth = nil
    end
end

--- Resizes the timeline and the internal list.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidTimeline self For chaining.
function Timeline:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    ValueField.resizeChild(self, w, h)
    return self
end
