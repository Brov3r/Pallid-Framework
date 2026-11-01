require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/clip"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/popover"
require "pallid/ui/widgets/label"
require "pallid/ui/widgets/button"
require "pallid/ui/widgets/picker_field"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local I = Pallid.UI._internal
local PickerField = Widgets.PickerField
local Color = Pallid.UI.Color

local ICON_CLOCK = "media/assets/ui/pallid/icons/clock.png"

-- Popover geometry: two columns, a preview line and a footer with buttons.
local POPOVER_WIDTH = 280
local POPOVER_HEIGHT = 260
local CONTENT_PAD = 8
local COL_GAP = 8
local COL_WIDTH = 128
local COL_X1 = CONTENT_PAD
local COL_X2 = CONTENT_PAD + COL_WIDTH + COL_GAP
local HEADER_Y = 8
local HEADER_H = 16
local LIST_Y = 28
local LIST_H = 160
local PREVIEW_Y = 196
local PREVIEW_H = 22
local BUTTON_Y = 224
local BUTTON_H = 28
local BUTTON_GAP = 4
local NOW_W = 90
local CANCEL_W = 83
local OK_W = 83
local CONTENT_WIDTH = POPOVER_WIDTH - CONTENT_PAD * 2
local ROW_HEIGHT = 20
local DEFAULT_STEP = 5
local STEP_CHOICES = { 1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30, 60 }
local RECT_SHAPE = Pallid.UI.Shape.rect()
local ICON_NOW = "media/assets/ui/pallid/icons/time.png"
local ICON_CANCEL = "media/assets/ui/pallid/icons/cross.png"
local ICON_OK = "media/assets/ui/pallid/icons/tick.png"

-- Hour captions are shared by every picker: rows must not format numbers while
-- drawing.
local HOUR_LABELS = {}
for i = 0, 23 do
    HOUR_LABELS[i + 1] = string.format("%02d", i)
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

--- Snaps a requested minute step to the nearest divisor of 60.
--- @param value number Requested step.
--- @return integer step Normalized step.
local function normalizeStep(value)
    value = clampInt(value or DEFAULT_STEP, 1, 60)
    local best = STEP_CHOICES[1]
    for i = 1, #STEP_CHOICES do
        if math.abs(STEP_CHOICES[i] - value) < math.abs(best - value) then
            best = STEP_CHOICES[i]
        end
    end
    return best
end

--- Reads the in-game clock. `getGameTime` is missing in a headless harness and
--- on the main menu, hence the pcall boundary.
--- @return integer|nil hour Hour value, or nil.
--- @return integer|nil minute Minute value, or nil.
local function readGameTime()
    local gameTime = getGameTime()
    if gameTime == nil then
        return nil
    end
    return gameTime:getHour(), gameTime:getMinutes()
end

--- @return integer|nil hour Hour value, or nil.
--- @return integer|nil minute Minute value, or nil.
local function readRealTime()
    local ok, now = pcall(os.date, "*t")
    if ok and type(now) == "table" then
        return now.hour, now.min
    end
    return nil
end

--- @return integer hour Hour value, or nil.
--- @return integer minute Minute value, or nil.
local function resolveTime()
    local ok, hour, minute = pcall(readGameTime)
    if ok and hour ~= nil and minute ~= nil then
        return hour, minute
    end

    local realHour, realMinute = readRealTime()
    if realHour ~= nil then
        return realHour, realMinute
    end

    return 0, 0
end

--- Scrollable one-column caption list used by the time picker. Rows are plain
--- strings, so the column owns hit testing and needs no child widgets or a
--- virtual-list dependency.
--- @class PallidTimeColumn : PallidWidget
--- @field labels string[] Row captions.
--- @field count integer Row count.
--- @field rowHeight number Row height in pixels.
--- @field selected integer 1-based selected row.
--- @field scrollY number Scroll offset in pixels.
--- @field hover integer 1-based hovered row, 0 when none.
local TimeColumn = Widgets.class("TimeColumn")

--- Creates a new `TimeColumn` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table Column options.
--- @field opts.labels string[] Row captions.
--- @field opts.count integer Row count.
--- @field opts.rowHeight number|nil Row height; defaults to 20.
--- @field opts.onSelect fun(index: integer)|nil Selection callback.
--- @return PallidTimeColumn column New column.
function TimeColumn.new(x, y, w, h, opts)
    local self = setmetatable({}, TimeColumn)
    self:init(x, y, w, h)
    self.labels = opts.labels
    self.count = opts.count
    self.rowHeight = opts.rowHeight or ROW_HEIGHT
    self.onSelect = opts.onSelect
    self.selected = 1
    self.scrollY = 0
    self.hover = 0

    self.selectedFill = Color.primarySoft
    self.hoverFill = Color.accentSoft
    self.textColor = Color.textMuted
    self.selectedText = Color.textPrimary
    self.trackColor = Color.border
    self.thumbColor = Color.textDisabled
    self.labelStyle = {
        font   = Pallid.UI.Fonts.small,
        color  = Color.textMuted,
        alignH = "center",
        alignV = "middle",
    }
    return self
end

--- @return number maxScroll Highest valid scroll offset.
function TimeColumn:_maxScroll()
    return math.max(0, self.count * self.rowHeight - self.h)
end

--- Scrolls the viewport to the row.
--- @param value number Requested scroll offset.
--- @return PallidTimeColumn self This column, for chaining.
function TimeColumn:scrollTo(value)
    self.scrollY = math.max(0, math.min(value or 0, self:_maxScroll()))
    return self
end

--- Sets the selected item.
--- @param index integer 1-based row.
--- @param notify boolean|nil True to fire `onSelect`.
--- @return PallidTimeColumn self This column, for chaining.
function TimeColumn:setSelected(index, notify)
    index = clampInt(index or 1, 1, self.count)
    self.selected = index
    if notify and self.onSelect ~= nil then
        self.onSelect(index)
    end
    return self
end

--- @param py number Cursor Y in root-local coordinates.
--- @return integer index 1-based row, or 0 outside.
function TimeColumn:_indexAt(py)
    local y = py - self:originY() + self.scrollY
    if y < 0 then
        return 0
    end
    local index = math.floor(y / self.rowHeight) + 1
    if index < 1 or index > self.count then
        return 0
    end
    return index
end

--- Handles a pointer press inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the press belongs to the column.
function TimeColumn:onDown(px, py, button)
    if button == "right" then
        return false
    end
    local index = self:_indexAt(py)
    if index > 0 then
        self:setSelected(index, true)
    end
    return true
end

--- Handles a mouse-wheel event.
--- @param delta number Wheel steps; positive is up.
--- @return boolean handled Always true.
function TimeColumn:onWheel(delta)
    self:scrollTo(self.scrollY + delta * self.rowHeight * 3)
    return true
end

--- Updates hover state for the current pointer position.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function TimeColumn:onHoverMove(px, py)
    self.hover = self:_indexAt(py)
end

--- Clears hover state when the pointer leaves.
function TimeColumn:onHoverEnd()
    self.hover = 0
    Widgets.Widget.onHoverEnd(self)
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the column is rendered into.
function TimeColumn:drawSelf(el)
    local x, y = self:originX(), self:originY()
    local rowHeight = self.rowHeight
    local maxScroll = self:_maxScroll()

    local first = math.max(1, math.floor(self.scrollY / rowHeight) + 1)
    local last = math.min(self.count,
        math.floor((self.scrollY + self.h - 1) / rowHeight) + 1)

    local clipped = Pallid.UI.clip(el, RECT_SHAPE, x, y, self.w, self.h)
    local style = self.labelStyle
    for i = first, last do
        local rowY = y + (i - 1) * rowHeight - self.scrollY
        if i == self.selected then
            Pallid.UI.rect(el, x, rowY, self.w, rowHeight, self.selectedFill)
            style.color = self.selectedText
        else
            if i == self.hover then
                Pallid.UI.rect(el, x, rowY, self.w, rowHeight, self.hoverFill)
            end
            style.color = self.textColor
        end
        Pallid.UI.text(el, self.labels[i], x + self.w * 0.5,
            rowY + rowHeight * 0.5, style)
    end
    style.color = self.textColor
    if clipped then
        Pallid.UI.clipEnd(el)
    end

    if maxScroll > 0 then
        local trackX = x + self.w - 3
        local contentH = self.count * rowHeight
        local thumbH = math.max(12, math.floor(self.h * self.h / contentH))
        local thumbY = y + math.floor((self.scrollY / maxScroll) * (self.h - thumbH))
        Pallid.UI.rect(el, trackX, y, 2, self.h, self.trackColor)
        Pallid.UI.rect(el, trackX, thumbY, 2, thumbH, self.thumbColor)
    end
end

--- Compact time field with a clock icon. Opens a two-column popover: hours on
--- the left, minutes on the right, a preview and Now/Cancel/OK buttons.
--- @class PallidTimePicker : PallidPickerField
--- @field hour integer 0..23
--- @field minute integer 0..59, a multiple of `step`.
--- @field step integer Minute step; always a divisor of 60.
--- @field popover PallidPopover|nil Created on first open.
--- @field hourList PallidTimeColumn|nil Hour column, or nil.
--- @field minuteList PallidTimeColumn|nil Minute column, or nil.
--- @field preview PallidLabel|nil Time preview label, or nil.
--- @field onChange fun(picker: PallidTimePicker, hour: integer, minute: integer)|nil
local TimePicker = Widgets.class("TimePicker", PickerField)

--- Creates a new `TimePicker` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Picker options.
--- @field opts.value table|nil `{ hour, minute }`; overrides the default.
--- @field opts.minuteStep integer|nil Snapped to a divisor of 60. Defaults to 5.
--- @field opts.icon string|false|nil Icon name or texture path; false hides it.
--- @field opts.onChange fun(picker: PallidTimePicker, hour: integer, minute: integer)|nil
--- @field opts.radius number|nil Defaults to 4.
--- @return PallidTimePicker picker New time picker.
function TimePicker.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, TimePicker)

    local icon = opts.icon
    if icon == nil then
        icon = ICON_CLOCK
    end
    self:_initField(x, y, w, h, {
        radius   = opts.radius,
        icon     = icon,
        onChange = opts.onChange,
    })

    self.onChange = opts.onChange
    self.step = normalizeStep(opts.minuteStep or DEFAULT_STEP)
    self.minuteCount = math.floor(60 / self.step)

    local hour, minute = resolveTime()
    local value = opts.value
    if value ~= nil then
        hour = value.hour or hour
        minute = value.minute or minute
    end

    self.hour = clampInt(hour, 0, 23)
    self.minute = self:_snapMinute(minute)
    self._notifiedHour = self.hour
    self._notifiedMinute = self.minute
    self._openHour = self.hour
    self._openMinute = self.minute
    self._cancelOnClose = false

    self._minuteLabels = {}
    for i = 1, self.minuteCount do
        self._minuteLabels[i] = string.format("%02d", (i - 1) * self.step)
    end

    self:_refreshText()
    return self
end

--- Factory shortcut for `TimePicker.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Options; see `TimePicker.new`.
--- @return PallidTimePicker picker New time picker.
function Widgets.timePicker(x, y, w, h, opts)
    return TimePicker.new(x, y, w, h, opts)
end

--- Rounds a minute to the configured step and keeps it inside 0..59.
--- @param minute number Minute number to snap.
--- @return integer minute Snapped minute.
function TimePicker:_snapMinute(minute)
    local step = self.step
    local snapped = math.floor((minute or 0) / step + 0.5) * step
    if snapped < 0 then
        return 0
    end
    if snapped > 59 then
        snapped = snapped - step
    end
    if snapped < 0 then
        return 0
    end
    return snapped
end

--- Rebuilds the field caption and the popover preview.
function TimePicker:_refreshText()
    self._text = string.format("%02d:%02d", self.hour, self.minute)
    if self.preview ~= nil then
        self.preview:setText(self._text)
    end
end

--- Returns the selected time.
--- @return integer hour Hour value, or nil.
--- @return integer minute Minute value, or nil.
function TimePicker:getTime()
    return self.hour, self.minute
end

--- Sets the time.
--- @param hour integer Hour number.
--- @param minute integer Rounded to `step`.
--- @return PallidTimePicker self This picker, for chaining.
function TimePicker:setTime(hour, minute)
    self.hour = clampInt(hour or self.hour, 0, 23)
    self.minute = self:_snapMinute(minute or self.minute)
    -- A programmatic set is already applied, so the next commit must not report
    -- it as a user change.
    self._notifiedHour = self.hour
    self._notifiedMinute = self.minute
    self:_refreshText()
    self:_syncLists()
    return self
end

--- @param hour integer Selected hour.
function TimePicker:_onHour(hour)
    self.hour = clampInt(hour, 0, 23)
    self:_refreshText()
end

--- @param minute integer Selected minute.
function TimePicker:_onMinute(minute)
    self.minute = self:_snapMinute(minute)
    self:_refreshText()
end

--- Fires `onChange` only when the values really differ from the last reported
--- pair. Called on OK and on every popover close so an outside click applies
--- the visible selection.
function TimePicker:_commit()
    if self.hour == self._notifiedHour and self.minute == self._notifiedMinute then
        return
    end
    self._notifiedHour = self.hour
    self._notifiedMinute = self.minute
    if self.onChange ~= nil then
        self.onChange(self, self.hour, self.minute)
    end
end

function TimePicker:_confirm()
    self:_commit()
    self:close()
end

--- Reverts to the value captured on open and closes without committing.
function TimePicker:_cancel()
    self.hour = self._openHour
    self.minute = self._openMinute
    self:_refreshText()
    self:_syncLists()
    self._cancelOnClose = true
    self:close()
end

--- Puts both columns on the current value and centres the selected row.
function TimePicker:_syncLists()
    if self.hourList == nil then
        return
    end

    local hourIndex = self.hour + 1
    self.hourList:setSelected(hourIndex, false)
    self.hourList:scrollTo((hourIndex - 1) * ROW_HEIGHT - (LIST_H - ROW_HEIGHT) * 0.5)

    local minuteIndex = math.floor(self.minute / self.step + 0.5) + 1
    if minuteIndex < 1 then
        minuteIndex = 1
    elseif minuteIndex > self.minuteCount then
        minuteIndex = self.minuteCount
    end
    self.minuteList:setSelected(minuteIndex, false)
    self.minuteList:scrollTo((minuteIndex - 1) * ROW_HEIGHT - (LIST_H - ROW_HEIGHT) * 0.5)
end

--- Builds the popover lazily so a picker that is never opened costs no columns
--- and no buttons.
function TimePicker:_ensurePopover()
    if self.popover ~= nil then
        return
    end

    local content = Widgets.widget(0, 0, POPOVER_WIDTH, POPOVER_HEIGHT)
    content.onClose = function()
        if self._cancelOnClose then
            self._cancelOnClose = false
        else
            self:_commit()
        end
    end
    -- The root calls this when Escape closes the popover, so Esc cancels.
    content.onCancel = function()
        self:_cancel()
    end

    local headerStyle = {
        font   = Pallid.UI.Fonts.small,
        color  = Color.textMuted,
        alignH = "center",
        alignV = "middle",
    }

    local hourList = TimeColumn.new(COL_X1, LIST_Y, COL_WIDTH, LIST_H, {
        labels   = HOUR_LABELS,
        count    = 24,
        rowHeight = ROW_HEIGHT,
        onSelect = function(index)
            self:_onHour(index - 1)
        end,
    })

    local minuteList = TimeColumn.new(COL_X2, LIST_Y, COL_WIDTH, LIST_H, {
        labels   = self._minuteLabels,
        count    = self.minuteCount,
        rowHeight = ROW_HEIGHT,
        onSelect = function(index)
            self:_onMinute((index - 1) * self.step)
        end,
    })

    local preview = Widgets.label("", CONTENT_PAD, PREVIEW_Y, CONTENT_WIDTH, PREVIEW_H, {
        style = {
            font  = Pallid.UI.Fonts.medium,
            color = Color.textPrimary,
        },
        alignH = "center",
    })

    local nowButton = Widgets.button(CONTENT_PAD, BUTTON_Y, NOW_W, BUTTON_H, {
        text      = I.translate("UI_Pallid_Now", "Now"),
        icon      = ICON_NOW,
        iconInset = 12,
        onClick   = function()
            local hour, minute = resolveTime()
            self:_onHour(hour)
            self:_onMinute(minute)
            self:_syncLists()
        end,
    })
    local cancelButton = Widgets.button(CONTENT_PAD + NOW_W + BUTTON_GAP, BUTTON_Y,
        CANCEL_W, BUTTON_H, {
            text      = I.translate("UI_Pallid_ModalCancel", "Cancel"),
            icon      = ICON_CANCEL,
            iconInset = 12,
            onClick   = function()
                self:_cancel()
            end,
        })
    local okButton = Widgets.button(CONTENT_PAD + NOW_W + BUTTON_GAP + CANCEL_W + BUTTON_GAP,
        BUTTON_Y, OK_W, BUTTON_H, {
            text      = I.translate("UI_Pallid_ModalOK", "OK"),
            icon      = ICON_OK,
            iconInset = 12,
            onClick   = function()
                self:_confirm()
            end,
        })

    content:add(Widgets.label(I.translate("UI_Pallid_Hour", "Hour"),
        COL_X1, HEADER_Y, COL_WIDTH, HEADER_H, {
            style  = headerStyle,
            alignH = "center",
        }))
    content:add(Widgets.label(I.translate("UI_Pallid_Minute", "Minute"),
        COL_X2, HEADER_Y, COL_WIDTH, HEADER_H, {
            style  = headerStyle,
            alignH = "center",
        }))
    content:add(hourList)
    content:add(minuteList)
    content:add(preview)
    content:add(nowButton)
    content:add(cancelButton)
    content:add(okButton)

    self.hourList = hourList
    self.minuteList = minuteList
    self.preview = preview
    self.popover = Widgets.popover(content, {
        width      = POPOVER_WIDTH,
        height     = POPOVER_HEIGHT,
        padding    = 0,
        background = Color.surfaceElevated,
        radius     = 6,
    })
end

--- Opens the picker below the field.
--- @return PallidTimePicker self This picker, for chaining.
function TimePicker:open()
    if not self.enabled then
        return self
    end

    self:_ensurePopover()
    self:_syncLists()
    self.preview:setText(self._text)
    self._notifiedHour = self.hour
    self._notifiedMinute = self.minute
    self._openHour = self.hour
    self._openMinute = self.minute
    self._cancelOnClose = false
    self.popover:show(self, "bottom")

    return self
end
