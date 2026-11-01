require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/popover"
require "pallid/ui/widgets/button"
require "pallid/ui/widgets/picker_field"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local I = Pallid.UI._internal
local PickerField = Widgets.PickerField
local Color = Pallid.UI.Color

local ICON_CALENDAR = "media/assets/ui/pallid/icons/calendar.png"
local ICON_YEAR_BACK = "media/assets/ui/pallid/icons/arrow-double-left-05.png"
local ICON_MONTH_BACK = "media/assets/ui/pallid/icons/arrow-left-04.png"
local ICON_MONTH_NEXT = "media/assets/ui/pallid/icons/arrow-right-04.png"
local ICON_YEAR_NEXT = "media/assets/ui/pallid/icons/arrow-double-right-05.png"
local ICON_OPTS = { mode = "fit" }

-- Calendar body inside the popover, plus a footer with the Today shortcut.
local CAL_WIDTH = 280
local CAL_HEIGHT = 230
local CAL_PAD = 8
local CAL_HEADER_H = 24
local CAL_GAP = 4
local CAL_WEEK_H = 16
local CAL_COLS = 7
local CAL_ROWS = 6
local NAV_SIZE = 18
local NAV_GAP = 2
local NAV_ICON = 12
local POPOVER_WIDTH = CAL_WIDTH
local TODAY_GAP = 5
local TODAY_H = 24
local POPOVER_HEIGHT = CAL_HEIGHT + TODAY_GAP + TODAY_H + 8

local MONTH_KEYS = {
    "UI_Pallid_MonthJanuary",
    "UI_Pallid_MonthFebruary",
    "UI_Pallid_MonthMarch",
    "UI_Pallid_MonthApril",
    "UI_Pallid_MonthMay",
    "UI_Pallid_MonthJune",
    "UI_Pallid_MonthJuly",
    "UI_Pallid_MonthAugust",
    "UI_Pallid_MonthSeptember",
    "UI_Pallid_MonthOctober",
    "UI_Pallid_MonthNovember",
    "UI_Pallid_MonthDecember",
}

local MONTH_DEFAULTS = {
    "January", "February", "March",     "April",   "May",      "June",
    "July",    "August",   "September", "October", "November", "December",
}

local MONTH_SHORT_KEYS = {
    "UI_Pallid_MonthJanuaryShort",
    "UI_Pallid_MonthFebruaryShort",
    "UI_Pallid_MonthMarchShort",
    "UI_Pallid_MonthAprilShort",
    "UI_Pallid_MonthMayShort",
    "UI_Pallid_MonthJuneShort",
    "UI_Pallid_MonthJulyShort",
    "UI_Pallid_MonthAugustShort",
    "UI_Pallid_MonthSeptemberShort",
    "UI_Pallid_MonthOctoberShort",
    "UI_Pallid_MonthNovemberShort",
    "UI_Pallid_MonthDecemberShort",
}

local MONTH_SHORT_DEFAULTS = {
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
}

local WEEKDAY_KEYS = {
    "UI_Pallid_DayMo",
    "UI_Pallid_DayTu",
    "UI_Pallid_DayWe",
    "UI_Pallid_DayTh",
    "UI_Pallid_DayFr",
    "UI_Pallid_DaySa",
    "UI_Pallid_DaySu",
}

local WEEKDAY_DEFAULTS = { "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" }

-- Monday-first, matching the ISO column order used by the grid.
local MONTHS = {}
local MONTHS_SHORT = {}
local WEEKDAYS = {}

--- Refreshes localized month and weekday names. Called on picker creation
--- because this module can be loaded before the game's text database is ready.
local function localizeDateNames()
    for i = 1, 12 do
        MONTHS[i] = I.translate(MONTH_KEYS[i], MONTH_DEFAULTS[i])
        MONTHS_SHORT[i] = I.translate(MONTH_SHORT_KEYS[i], MONTH_SHORT_DEFAULTS[i])
    end
    for i = 1, 7 do
        WEEKDAYS[i] = I.translate(WEEKDAY_KEYS[i], WEEKDAY_DEFAULTS[i])
    end
end

localizeDateNames()

local DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

-- Month offsets of Sakamoto's day-of-week algorithm. Kept at module level so
-- the calendar never builds a table while drawing.
local DOW_OFFSETS = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }

-- Day captions are pre-rendered once: formatting 42 numbers every frame would
-- allocate a string per cell.
local DAY_LABELS = {}
for i = 1, 31 do
    DAY_LABELS[i] = tostring(i)
end

--- @param value number Value to process.
--- @param lo number Inclusive lower bound.
--- @param hi number Inclusive upper bound.
--- @return integer Clamped integer.
local function clampInt(value, lo, hi)
    value = math.floor(value)
    if value < lo then
        return lo
    end
    if value > hi then
        return hi
    end
    return value
end

--- @param year integer Year number.
--- @return boolean leap True for a leap year.
local function isLeapYear(year)
    return (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0
end

--- @param year integer Year number.
--- @param month integer 1..12
--- @return integer days Day count.
local function daysInMonth(year, month)
    if month == 2 and isLeapYear(year) then
        return 29
    end
    return DAYS_IN_MONTH[month] or 31
end

--- Sakamoto's algorithm, pure integer math. Returns 0 for Sunday and 6 for
--- Saturday, so game years far from the real calendar still work without
--- going through os.time.
--- @param year integer positive year.
--- @param month integer 1..12
--- @param day integer 1..31
--- @return integer dow Day of week, 0..6.
local function dayOfWeek(year, month, day)
    local y = year
    if month < 3 then
        y = y - 1
    end
    return (y + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400)
        + DOW_OFFSETS[month] + day) % 7
end

--- Reads the in-game date. B42 exposes a 0-based month and a 0-based `getDay`
--- plus the 1-based `getDayPlusOne` (GameTime.java:678-688), so the day is
--- taken from the plus-one getter whenever it exists.
--- @return integer|nil year Year value, or nil.
--- @return integer|nil month Month value, or nil.
--- @return integer|nil day Day value, or nil.
local function readGameDate()
    local gameTime = getGameTime()
    if gameTime == nil then
        return nil
    end

    local year = gameTime:getYear()
    local month = gameTime:getMonth() + 1

    local ok, plusOne = pcall(function()
        return gameTime:getDayPlusOne()
    end)
    local day
    if ok and plusOne ~= nil then
        day = plusOne
    else
        day = gameTime:getDay() + 1
    end

    return year, month, day
end

--- @return integer|nil year Year value, or nil.
--- @return integer|nil month Month value, or nil.
--- @return integer|nil day Day value, or nil.
local function readRealDate()
    local ok, today = pcall(os.date, "*t")
    if ok and type(today) == "table" then
        return today.year, today.month, today.day
    end
    return nil
end

--- Resolves the initial date. Game time is the default because the picker is
--- mostly used for in-game events; `gameTime = false` asks for the real date.
--- @param useGameTime boolean True uses the in-game clock.
--- @return integer year Year value, or nil.
--- @return integer month Month value, or nil.
--- @return integer day Day value, or nil.
local function resolveDate(useGameTime)
    if useGameTime then
        local ok, year, month, day = pcall(readGameDate)
        if ok and year ~= nil and month ~= nil and day ~= nil then
            return year, month, day
        end
    end

    local year, month, day = readRealDate()
    if year ~= nil then
        return year, month, day
    end

    -- Headless harnesses have neither getGameTime nor os.date; keep the field
    -- usable instead of erroring on construction.
    return 1993, 7, 1
end

--- Calendar body placed inside the picker popover.
---
--- Kept separate from `DatePicker` because it owns its own hit testing: the
--- month grid, the weekday header and the four navigation arrows are all
--- drawn and picked with plain math, so a month switch costs no allocation.
--- @class PallidDatePickerCalendar : PallidWidget
--- @field year integer Month view year.
--- @field month integer Month view month, 1-based.
--- @field selectedYear integer|nil Selected year, or nil when unset.
--- @field selectedMonth integer|nil Selected month, or nil when unset.
--- @field selectedDay integer|nil Selected day, or nil when unset.
--- @field todayYear integer|nil Today year, or nil.
--- @field todayMonth integer|nil Today month, or nil.
--- @field todayDay integer|nil Today day, or nil.
--- @field hoverNav integer 1..4 for an arrow, 0 for none.
--- @field hoverCell integer 1-based grid cell, 0 for none.
--- @field onSelect fun(calendar: PallidDatePickerCalendar, year: integer, month: integer, day: integer)|nil
local Calendar = Widgets.class("DatePickerCalendar")

--- Creates a new `Calendar` instance.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @return PallidDatePickerCalendar calendar New calendar.
function Calendar.new(w, h)
    local self = setmetatable({}, Calendar)
    self:init(0, 0, w, h)
    localizeDateNames()

    self.year = 1993
    self.month = 7
    self.selectedYear = 1993
    self.selectedMonth = 7
    self.selectedDay = 1
    self.todayYear = nil
    self.todayMonth = nil
    self.todayDay = nil

    self.hoverNav = 0
    self.hoverCell = 0

    self.titleStyle = {
        font    = Pallid.UI.Fonts.small,
        color   = Color.textPrimary,
        alignH  = "center",
        alignV  = "middle",
        bold    = true,
    }
    self.weekStyle = {
        font    = Pallid.UI.Fonts.small,
        color   = Color.textDisabled,
        alignH  = "center",
        alignV  = "middle",
    }
    self.dayStyle = {
        font    = Pallid.UI.Fonts.small,
        color   = Color.textMuted,
        alignH  = "center",
        alignV  = "middle",
    }
    self.navColor = Color.textMuted
    self.selectedFill = Color.primarySoft
    self.hoverFill = Color.withAlpha(Color.accentSoft, 0.8)
    self.navHoverFill = Color.withAlpha(Color.primarySoft, 0.9)
    self.todayColor = Color.primaryStrong
    self.adjacentColor = Color.withAlpha(Color.textDisabled, 0.45)

    self.navTextures = {
        Pallid.UI.Textures.get(ICON_YEAR_BACK),
        Pallid.UI.Textures.get(ICON_MONTH_BACK),
        Pallid.UI.Textures.get(ICON_MONTH_NEXT),
        Pallid.UI.Textures.get(ICON_YEAR_NEXT),
    }

    self:_layout()
    self:_refresh()
    return self
end

--- Updates the widget bounds.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @return PallidDatePickerCalendar self This calendar, for chaining.
function Calendar:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:_layout()
    return self
end

--- Recomputes the grid metrics. Only called on resize, never per frame.
function Calendar:_layout()
    local colW = math.max(1, math.floor((self.w - CAL_PAD * 2) / CAL_COLS))
    local gridW = colW * CAL_COLS
    local gridTop = CAL_PAD + CAL_HEADER_H + CAL_GAP + CAL_WEEK_H

    self._colW = colW
    self._gridX = math.floor((self.w - gridW) * 0.5)
    self._gridY = gridTop
    self._rowH = math.max(1, math.floor((self.h - CAL_PAD - gridTop) / CAL_ROWS))
    self._headY = CAL_PAD
    self._headH = CAL_HEADER_H
    self._weekY = CAL_PAD + CAL_HEADER_H + CAL_GAP

    self._navY = CAL_PAD + math.floor((CAL_HEADER_H - NAV_SIZE) * 0.5)
    self._navYearBackX = CAL_PAD
    self._navMonthBackX = CAL_PAD + NAV_SIZE + NAV_GAP
    self._navMonthNextX = self.w - CAL_PAD - NAV_SIZE * 2 - NAV_GAP
    self._navYearNextX = self.w - CAL_PAD - NAV_SIZE
end

--- Caches everything derived from the visible month.
function Calendar:_refresh()
    self._days = daysInMonth(self.year, self.month)
    -- dayOfWeek() is Sunday-based; the grid is Monday-based.
    self._firstCol = (dayOfWeek(self.year, self.month, 1) + 6) % 7
    self._title = MONTHS[self.month] .. " " .. tostring(self.year)

    local prevMonth = self.month - 1
    local prevYear = self.year
    if prevMonth < 1 then
        prevMonth = 12
        prevYear = self.year - 1
    end
    local nextMonth = self.month + 1
    local nextYear = self.year
    if nextMonth > 12 then
        nextMonth = 1
        nextYear = self.year + 1
    end
    self._prevYear, self._prevMonth = prevYear, prevMonth
    self._nextYear, self._nextMonth = nextYear, nextMonth
    self._prevDays = daysInMonth(prevYear, prevMonth)
end

--- Sets the visible calendar page.
--- @param year integer Year number.
--- @param month integer 1-based.
--- @return PallidDatePickerCalendar self This calendar, for chaining.
function Calendar:setView(year, month)
    self.year = math.max(1, math.floor(year))
    self.month = clampInt(month, 1, 12)
    self:_refresh()
    return self
end

--- Sets the selected date.
--- @param year integer Selected year.
--- @param month integer 1-based.
--- @param day integer Selected day.
--- @return PallidDatePickerCalendar self This calendar, for chaining.
function Calendar:setSelected(year, month, day)
    local selectedYear = math.max(1, math.floor(year or self.selectedYear or 1))
    local selectedMonth = clampInt(month or self.selectedMonth or 1, 1, 12)
    self.selectedYear = selectedYear
    self.selectedMonth = selectedMonth
    self.selectedDay = clampInt(day or self.selectedDay or 1, 1,
        daysInMonth(selectedYear, selectedMonth))
    return self
end

--- Sets the fallback today date.
--- @param year integer Today year.
--- @param month integer 1-based.
--- @param day integer Today day.
--- @return PallidDatePickerCalendar self This calendar, for chaining.
function Calendar:setToday(year, month, day)
    local todayYear = math.max(1, math.floor(year or self.year))
    local todayMonth = clampInt(month or self.month, 1, 12)
    self.todayYear = todayYear
    self.todayMonth = todayMonth
    self.todayDay = clampInt(day or 1, 1, daysInMonth(todayYear, todayMonth))
    return self
end

--- @param delta integer Wheel delta in steps.
function Calendar:_stepMonth(delta)
    local month = self.month + delta
    local year = self.year
    if month < 1 then
        month = 12
        year = math.max(1, year - 1)
    elseif month > 12 then
        month = 1
        year = year + 1
    end
    self:setView(year, month)
end

--- @param year integer Year number.
--- @param month integer Month number, 1-based.
--- @param day integer Day number, 1-based.
--- @return boolean selected True when the date matches the selection.
function Calendar:_isSelectedDate(year, month, day)
    return self.selectedYear == year
        and self.selectedMonth == month
        and self.selectedDay == day
end

--- @param year integer Year number.
--- @param month integer Month number, 1-based.
--- @param day integer Day number, 1-based.
--- @return boolean today True when the date matches today.
function Calendar:_isTodayDate(year, month, day)
    return self.todayYear == year
        and self.todayMonth == month
        and self.todayDay == day
end

--- @param px number Pointer X in local coordinates.
--- @param py number Pointer Y in local coordinates.
--- @return integer nav 1..4 for an arrow, 0 otherwise.
function Calendar:_hitNav(px, py)
    local x = px - self:originX()
    local y = py - self:originY()
    if y < self._navY or y >= self._navY + NAV_SIZE then
        return 0
    end
    if x >= self._navYearBackX and x < self._navYearBackX + NAV_SIZE then
        return 1
    end
    if x >= self._navMonthBackX and x < self._navMonthBackX + NAV_SIZE then
        return 2
    end
    if x >= self._navMonthNextX and x < self._navMonthNextX + NAV_SIZE then
        return 3
    end
    if x >= self._navYearNextX and x < self._navYearNextX + NAV_SIZE then
        return 4
    end
    return 0
end

--- @param px number Pointer X in local coordinates.
--- @param py number Pointer Y in local coordinates.
--- @return integer cell 1-based grid cell, 0 outside the grid.
function Calendar:_cellAt(px, py)
    local x = px - self:originX() - self._gridX
    local y = py - self:originY() - self._gridY
    if x < 0 or y < 0 then
        return 0
    end

    local col = math.floor(x / self._colW) + 1
    local row = math.floor(y / self._rowH) + 1
    if col < 1 or col > CAL_COLS or row < 1 or row > CAL_ROWS then
        return 0
    end
    return (row - 1) * CAL_COLS + col
end

--- Resolves a grid cell to a full date, including adjacent-month days.
--- @param cell integer 1-based grid cell.
--- @return integer|nil year Year value, or nil.
--- @return integer|nil month Month value, or nil.
--- @return integer|nil day Day value, or nil.
function Calendar:_dateForCell(cell)
    local day = cell - self._firstCol
    if day < 1 then
        if self._prevYear < 1 then
            return nil, nil, nil
        end
        return self._prevYear, self._prevMonth, self._prevDays + day
    elseif day > self._days then
        return self._nextYear, self._nextMonth, day - self._days
    end
    return self.year, self.month, day
end

--- Handles a pointer press inside the widget.
--- @param px number Pointer X in local coordinates.
--- @param py number Pointer Y in local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the calendar consumed the press.
function Calendar:onDown(px, py, button)
    if button == "right" then
        return false
    end

    local nav = self:_hitNav(px, py)
    if nav == 1 then
        self:setView(self.year - 1, self.month)
        return true
    elseif nav == 2 then
        self:_stepMonth(-1)
        return true
    elseif nav == 3 then
        self:_stepMonth(1)
        return true
    elseif nav == 4 then
        self:setView(self.year + 1, self.month)
        return true
    end

    local cell = self:_cellAt(px, py)
    if cell == 0 then
        return false
    end
    local year, month, day = self:_dateForCell(cell)
    if year == nil then
        return false
    end

    if year ~= self.year or month ~= self.month then
        self:setView(year, month)
    end
    self:setSelected(year, month, day)
    if self.onSelect ~= nil then
        self.onSelect(self, year, month, day)
    end
    return true
end

--- Updates hover state for the current pointer position.
--- @param px number Pointer X in local coordinates.
--- @param py number Pointer Y in local coordinates.
function Calendar:onHoverMove(px, py)
    local nav = self:_hitNav(px, py)
    if nav ~= 0 then
        self.hoverNav = nav
        self.hoverCell = 0
    else
        self.hoverNav = 0
        self.hoverCell = self:_cellAt(px, py)
    end
end

--- Clears hover state when the pointer leaves.
function Calendar:onHoverEnd()
    self.hoverNav = 0
    self.hoverCell = 0
    Widgets.Widget.onHoverEnd(self)
end

--- @param el ISUIElement Host element.
--- @param texture Texture|nil Icon texture.
--- @param cx number Icon centre X.
--- @param cy number Icon centre Y.
--- @param color PallidColor Icon tint.
local function drawNavIcon(el, texture, cx, cy, color)
    if texture == nil then
        return
    end
    local half = NAV_ICON * 0.5
    Pallid.UI.texture(el, texture, math.floor(cx - half), math.floor(cy - half),
        NAV_ICON, NAV_ICON, color, ICON_OPTS)
end

--- @param el ISUIElement Host element used for drawing.
function Calendar:_drawNav(el)
    local color = self:shade(self.navColor)
    local ox = self:originX()
    local oy = self:originY()
    local cy = oy + self._navY + NAV_SIZE * 0.5
    local pill = self:shade(self.navHoverFill, 2)
    local textures = self.navTextures

    local bx = ox + self._navYearBackX
    if self.hoverNav == 1 then
        Pallid.UI.roundedRect(el, bx, oy + self._navY, NAV_SIZE, NAV_SIZE, 3, pill)
    end
    drawNavIcon(el, textures[1], bx + NAV_SIZE * 0.5, cy, color)

    bx = ox + self._navMonthBackX
    if self.hoverNav == 2 then
        Pallid.UI.roundedRect(el, bx, oy + self._navY, NAV_SIZE, NAV_SIZE, 3, pill)
    end
    drawNavIcon(el, textures[2], bx + NAV_SIZE * 0.5, cy, color)

    bx = ox + self._navMonthNextX
    if self.hoverNav == 3 then
        Pallid.UI.roundedRect(el, bx, oy + self._navY, NAV_SIZE, NAV_SIZE, 3, pill)
    end
    drawNavIcon(el, textures[3], bx + NAV_SIZE * 0.5, cy, color)

    bx = ox + self._navYearNextX
    if self.hoverNav == 4 then
        Pallid.UI.roundedRect(el, bx, oy + self._navY, NAV_SIZE, NAV_SIZE, 3, pill)
    end
    drawNavIcon(el, textures[4], bx + NAV_SIZE * 0.5, cy, color)
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element used for drawing.
function Calendar:drawSelf(el)
    local ox, oy = self:originX(), self:originY()

    local title = self.titleStyle
    local titleBase = title.color
    title.color = self:shade(titleBase)
    Pallid.UI.text(el, self._title, ox + self.w * 0.5, oy + self._headY + self._headH * 0.5, title)
    title.color = titleBase

    self:_drawNav(el)

    local week = self.weekStyle
    local weekBase = week.color
    week.color = self:shade(weekBase)
    local weekCy = oy + self._weekY + CAL_WEEK_H * 0.5
    for col = 1, CAL_COLS do
        Pallid.UI.text(el, WEEKDAYS[col], ox + self._gridX + (col - 0.5) * self._colW, weekCy, week)
    end
    week.color = weekBase

    local dayStyle = self.dayStyle
    local dayBase = dayStyle.color
    local cellW = self._colW - 4
    local cellH = self._rowH - 4

    for row = 1, CAL_ROWS do
        for col = 1, CAL_COLS do
            local cell = (row - 1) * CAL_COLS + col
            local year, month, day = self:_dateForCell(cell)
            if year ~= nil then
                local inMonth = year == self.year and month == self.month
                local cx = ox + self._gridX + (col - 0.5) * self._colW
                local cy = oy + self._gridY + (row - 0.5) * self._rowH
                local x = math.floor(cx - cellW * 0.5)
                local y = math.floor(cy - cellH * 0.5)

                if self:_isSelectedDate(year, month, day) then
                    Pallid.UI.roundedRect(el, x, y, cellW, cellH, 4, self:shade(self.selectedFill))
                    dayStyle.color = self:shade(Color.textPrimary, 2)
                else
                    if cell == self.hoverCell then
                        Pallid.UI.roundedRect(el, x, y, cellW, cellH, 4, self:shade(self.hoverFill, 2))
                    end
                    if self:_isTodayDate(year, month, day) then
                        Pallid.UI.roundedBorder(el, x, y, cellW, cellH, 4, 1, self:shade(self.todayColor, 3))
                    end
                    if inMonth then
                        dayStyle.color = self:shade(dayBase)
                    else
                        dayStyle.color = self:shade(self.adjacentColor)
                    end
                end

                Pallid.UI.text(el, DAY_LABELS[day], cx, cy, dayStyle)
            end
        end
    end
    dayStyle.color = dayBase
end

--- Compact date field with a calendar icon. Opens a month grid with year and
--- month navigation plus a Today shortcut.
--- @class PallidDatePicker : PallidPickerField
--- @field year integer Displayed year.
--- @field month integer 1-based.
--- @field day integer 1-based.
--- @field calendar PallidDatePickerCalendar|nil Created on first open.
--- @field popover PallidPopover|nil Created on first open.
--- @field onChange fun(picker: PallidDatePicker, year: integer, month: integer, day: integer)|nil
local DatePicker = Widgets.class("DatePicker", PickerField)

--- Creates a new `DatePicker` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Picker options.
--- @field opts.value table|nil `{ year, month, day }`, 1-based; overrides the default.
--- @field opts.gameTime boolean|nil Defaults to true; false forces the real date.
--- @field opts.icon string|false|nil Icon name or texture path; false hides it.
--- @field opts.onChange fun(picker: PallidDatePicker, year: integer, month: integer, day: integer)|nil
--- @field opts.radius number|nil Defaults to 4.
--- @return PallidDatePicker picker New date picker.
function DatePicker.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, DatePicker)

    local icon = opts.icon
    if icon == nil then
        icon = ICON_CALENDAR
    end
    self:_initField(x, y, w, h, {
        radius   = opts.radius,
        icon     = icon,
        onChange = opts.onChange,
    })

    self.useGameTime = opts.gameTime ~= false
    self.onChange = opts.onChange
    localizeDateNames()
    self._dateFormat = I.translate("UI_Pallid_DateFieldFormat", "$month $day, $year")

    local year, month, day = resolveDate(self.useGameTime)
    local value = opts.value
    if value ~= nil then
        year = value.year or year
        month = value.month or month
        day = value.day or day
    end

    self.year = math.max(1, math.floor(year))
    self.month = clampInt(month, 1, 12)
    self.day = clampInt(day, 1, daysInMonth(self.year, self.month))

    self:_refreshText()
    return self
end

--- Factory shortcut for `DatePicker.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Options; see `DatePicker.new`.
--- @return PallidDatePicker picker New date picker.
function Widgets.datePicker(x, y, w, h, opts)
    return DatePicker.new(x, y, w, h, opts)
end

--- Rebuilds the field caption. Called only when the date changes.
function DatePicker:_refreshText()
    local text = self._dateFormat
    text = text:gsub("%$month", MONTHS_SHORT[self.month])
    text = text:gsub("%$day", DAY_LABELS[self.day])
    text = text:gsub("%$year", tostring(self.year))
    self._text = text
end

--- Returns the selected date.
--- @return integer year Year value, or nil.
--- @return integer month 1-based.
--- @return integer day 1-based.
function DatePicker:getDate()
    return self.year, self.month, self.day
end

--- Sets the selected date.
--- @param year integer Selected year.
--- @param month integer 1-based.
--- @param day integer Selected day.
--- @return PallidDatePicker self This picker, for chaining.
function DatePicker:setDate(year, month, day)
    local nextYear = math.max(1, math.floor(year or self.year))
    local nextMonth = clampInt(month or self.month, 1, 12)
    local nextDay = clampInt(day or self.day, 1, daysInMonth(nextYear, nextMonth))

    self.year = nextYear
    self.month = nextMonth
    self.day = nextDay
    self:_refreshText()

    if self.calendar ~= nil then
        self.calendar:setSelected(nextYear, nextMonth, nextDay)
        self.calendar:setView(nextYear, nextMonth)
    end

    return self
end

--- Builds the popover lazily so a picker that is never opened costs no
--- calendar and no popover.
function DatePicker:_ensurePopover()
    if self.popover ~= nil then
        return
    end

    local content = Widgets.widget(0, 0, POPOVER_WIDTH, POPOVER_HEIGHT)

    local calendar = Calendar.new(CAL_WIDTH, CAL_HEIGHT)
    calendar.onSelect = function(_, year, month, day)
        self:_select(year, month, day)
    end
    content:add(calendar)

    local todayButton = Widgets.button(8, CAL_HEIGHT + TODAY_GAP,
        POPOVER_WIDTH - 16, TODAY_H, {
            text      = I.translate("UI_Pallid_Today", "Today"),
            icon      = ICON_CALENDAR,
            iconInset = 8,
            onClick   = function()
                self:_selectToday()
            end,
        })
    content:add(todayButton)

    self.calendar = calendar
    self.popover = Widgets.popover(content, {
        width      = POPOVER_WIDTH,
        height     = POPOVER_HEIGHT,
        padding    = 0,
        background = Color.surfaceElevated,
        radius     = 6,
    })
end

--- @param year integer Year number.
--- @param month integer Month number, 1-based.
--- @param day integer Day number, 1-based.
function DatePicker:_select(year, month, day)
    self.year = year
    self.month = month
    self.day = day
    self:_refreshText()

    if self.onChange ~= nil then
        self.onChange(self, year, month, day)
    end

    self:close()
end

--- Selects the current date and closes.
function DatePicker:_selectToday()
    local year, month, day = resolveDate(self.useGameTime)
    self:_select(year, month, day)
end

--- Opens the calendar below the field.
--- @return PallidDatePicker self This picker, for chaining.
function DatePicker:open()
    if not self.enabled then
        return self
    end

    self:_ensurePopover()

    -- Refresh today on every open: the game clock moves while the UI lives.
    local todayYear, todayMonth, todayDay = resolveDate(self.useGameTime)
    self.calendar:setToday(todayYear, todayMonth, todayDay)
    self.calendar:setSelected(self.year, self.month, self.day)
    self.calendar:setView(self.year, self.month)
    self.popover:show(self, "bottom")

    return self
end
