require "pallid/ui/internal"
require "pallid/ui/api/text"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local PADDING       = 8
local MIN_WIDTH     = 60
local MAX_WIDTH     = 280
local ICON_SIZE     = 14
local ICON_GAP      = 6
local SWATCH_SIZE   = 8
local COLUMN_GAP    = 16
local BLOCK_GAP     = 4
local ROW_GAP       = 2
local SECTION_GAP   = 6
local SEPARATOR_GAP = 5

--- Cached measurement and layout for PallidTooltip. Kept apart from the widget
--- so the hot draw path stores plain items and never measures per frame.
--- @class PallidTooltipLayout
--- @field PADDING number Inner padding around every block.
--- @field ICON_SIZE number Row icon box in pixels.
--- @field SWATCH_SIZE number Colour swatch box in pixels.
local Layout = {
    PADDING     = PADDING,
    ICON_SIZE   = ICON_SIZE,
    SWATCH_SIZE = SWATCH_SIZE,
}
Pallid.UI.TooltipLayout = Layout

--- Measures a single line with the tooltip font.
--- @param text string|nil Text to measure.
--- @param font UIFont Font used for the line.
--- @return number width Width in pixels; 0 for an empty string.
local function measureLine(text, font)
    if text == nil or text == "" then
        return 0
    end
    return getTextManager():MeasureStringX(font, text)
end

--- Copies a caller-supplied row so later edits do not change a live tooltip.
--- @param row PallidTooltipRow|nil Source row.
--- @return PallidTooltipRow copy Internal row owned by the tooltip.
function Layout.copyRow(row)
    local out = {}
    if type(row) ~= "table" then
        return out
    end
    out.icon       = row.icon
    out.swatch     = row.swatch
    out.label      = row.label
    out.value      = row.value
    out.labelColor = row.labelColor
    out.valueColor = row.valueColor
    out.section    = row.section
    out.separator  = row.separator
    return out
end

--- Builds the layout of one tooltip and writes it back to the instance.
--- @param tip PallidTooltip Tooltip whose content and styles are read.
function Layout.build(tip)
    local contentMax = math.max(20, tip.maxWidth - PADDING * 2)
    local lineH = math.max(10, getTextManager():MeasureStringY(tip.style.font, "Ag"))

    -- First pass: the widest natural line decides the box width.
    tip.titleStyle.maxWidth = contentMax
    local titleW = 0
    if tip.title ~= "" then
        titleW = Pallid.UI.measureText(tip.title, tip.titleStyle)
    end

    tip.style.maxWidth = contentMax
    local bodyW = 0
    if tip.text ~= "" then
        bodyW = Pallid.UI.measureText(tip.text, tip.style)
    end

    tip.footerStyle.maxWidth = contentMax
    local footerW = 0
    if tip.footer ~= "" then
        footerW = Pallid.UI.measureText(tip.footer, tip.footerStyle)
    end

    local natural = math.max(titleW, bodyW, footerW)
    for i = 1, #tip.rows do
        local row = tip.rows[i]
        local width = 0
        if row.section ~= nil and row.section ~= false then
            local text = type(row.section) == "string" and row.section or (row.label or "")
            width = measureLine(text, tip.sectionStyle.font)
        elseif row.label ~= nil or row.value ~= nil or row.icon or row.swatch ~= nil then
            local leftW = 0
            if row.icon then
                leftW = ICON_SIZE + ICON_GAP
            elseif row.swatch ~= nil then
                leftW = SWATCH_SIZE + ICON_GAP
            end
            width = leftW + measureLine(tostring(row.label or ""), tip.labelStyle.font)
            if row.value ~= nil then
                width = width + COLUMN_GAP + measureLine(tostring(row.value), tip.valueStyle.font)
            end
        end
        if width > natural then
            natural = width
        end
    end

    local boxW = math.ceil(natural) + PADDING * 2
    boxW = math.max(MIN_WIDTH, math.min(boxW, tip.maxWidth))
    local contentW = boxW - PADDING * 2

    -- Second pass: heights and truncation at the final width.
    local items = tip._items
    local count = 0
    local y = 0

    if tip.title ~= "" then
        tip.titleStyle.maxWidth = contentW
        local _, height = Pallid.UI.measureText(tip.title, tip.titleStyle)
        count = count + 1
        items[count] = { kind = "title", y = y, h = height }
        y = y + height + BLOCK_GAP
    end

    if tip.text ~= "" then
        tip.style.maxWidth = contentW
        local _, height = Pallid.UI.measureText(tip.text, tip.style)
        count = count + 1
        items[count] = { kind = "body", y = y, h = height }
        y = y + height + BLOCK_GAP
    end

    for i = 1, #tip.rows do
        local row = tip.rows[i]
        if row.separator then
            count = count + 1
            items[count] = { kind = "separator", y = y + SEPARATOR_GAP, h = 1 }
            y = y + SEPARATOR_GAP * 2 + 1
        end

        if row.section ~= nil and row.section ~= false then
            local text = type(row.section) == "string" and row.section or (row.label or "")
            text = Pallid.UI.truncateText(text, tip.sectionStyle.font, contentW)
            count = count + 1
            items[count] = { kind = "section", text = text, y = y, h = lineH }
            y = y + lineH + SECTION_GAP
        elseif row.label ~= nil or row.value ~= nil or row.icon or row.swatch ~= nil then
            local leftW = 0
            if row.icon then
                leftW = ICON_SIZE + ICON_GAP
            elseif row.swatch ~= nil then
                leftW = SWATCH_SIZE + ICON_GAP
            end

            local value = row.value
            local valueW = 0
            if value ~= nil then
                value = tostring(value)
                value = Pallid.UI.truncateText(value, tip.valueStyle.font,
                    math.max(24, contentW - leftW - 32))
                valueW = measureLine(value, tip.valueStyle.font)
            end

            local label = tostring(row.label or "")
            local labelMax = contentW - leftW
            if valueW > 0 then
                labelMax = labelMax - COLUMN_GAP - valueW
            end
            if labelMax <= 0 then
                label = ""
            elseif label ~= "" then
                label = Pallid.UI.truncateText(label, tip.labelStyle.font, labelMax)
            end

            local rowH = math.max(lineH, leftW > 0 and ICON_SIZE or 0) + ROW_GAP
            count = count + 1
            items[count] = {
                kind       = "row",
                y          = y,
                h          = rowH,
                label      = label,
                value      = value,
                icon       = row.icon,
                swatch     = row.swatch,
                labelColor = row.labelColor,
                valueColor = row.valueColor,
                leftW      = leftW,
            }
            y = y + rowH
        end
    end

    if tip.footer ~= "" then
        if count > 0 then
            count = count + 1
            items[count] = { kind = "separator", y = y + SEPARATOR_GAP, h = 1 }
            y = y + SEPARATOR_GAP * 2 + 1
        end
        tip.footerStyle.maxWidth = contentW
        local _, height = Pallid.UI.measureText(tip.footer, tip.footerStyle)
        count = count + 1
        items[count] = { kind = "footer", y = y, h = height }
        y = y + height
    end

    tip._itemCount = count
    tip._contentW = contentW
    tip._boxW = boxW
    tip._boxH = math.ceil(y) + PADDING * 2
end
