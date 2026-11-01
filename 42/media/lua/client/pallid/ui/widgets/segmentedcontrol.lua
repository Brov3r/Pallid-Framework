require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"
local normaliseOption = require "pallid/ui/widgets/internal/option_item"
local OptionUtil = require "pallid/ui/widgets/internal/option_util"
local addDrawMethods = require "pallid/ui/widgets/segmentedcontrol/draw"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local DEFAULT_SOUND = "UIActivateTab"
local SEGMENT_PAD = 8
local ICON_SIZE = 14
local ICON_GAP = 5
local HOVER_SPEED = 16
local THUMB_SPEED = 18

--- Row of joined buttons with exactly one active segment. The active thumb
--- slides between segments and the labels are truncated to fit their slots.
--- Input is pointer-only for now.
--- @class PallidSegmentedControl : PallidWidget
--- @field options (string|table)[] Raw options in caller order.
--- @field items PallidOption[] Normalised options used for drawing and callbacks.
--- @field selected integer 1-based active segment, or 0 when none is active.
--- @field thumb number Eased thumb position; may be fractional while sliding.
--- @field thumbTarget integer Target segment for the sliding thumb.
--- @field onChange fun(control: PallidSegmentedControl, index: integer, label: string|nil, item: PallidOption|nil)|nil Selection callback.
--- @field hoverIndex integer Hovered segment, or 0.
--- @field hover number Eased hover strength, 0..1.
local Segmented = Widgets.class("SegmentedControl")

-- Painting lives in segmentedcontrol/draw.lua so this file stays focused on
-- state, layout and input.
addDrawMethods(Segmented)

--- Creates a new `Segmented` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param options (string|table)[] Segment labels or `{ label, value, icon, disabled }` tables.
--- @param opts table|nil Appearance and behaviour.
--- @field opts.selected integer|nil Initial 1-based segment, defaults to the first enabled one.
--- @field opts.onChange fun(control: PallidSegmentedControl, index: integer, label: string|nil, item: PallidOption|nil)|nil Selection callback.
--- @field opts.sound string|false|nil Sound name; false or "" silences it.
--- @field opts.animated boolean|nil False snaps the thumb instead of sliding it.
--- @field opts.font UIFont|string|nil Label font or a Pallid.UI.Fonts key.
--- @return PallidSegmentedControl control New segmented control.
function Segmented.new(x, y, w, h, options, opts)
    opts = opts or {}
    local self = setmetatable({}, Segmented)
    self:init(x, y, w, h)

    self.options = {}
    self.items = {}
    self._labelTexts = {}
    self._labelWidths = {}
    self._hasIcons = false
    self.iconGap = ICON_GAP
    self.selected = 0
    self.thumb = 0
    self.thumbTarget = 0
    self.animated = opts.animated ~= false
    self.hoverIndex = 0
    self.hover = 0
    self.onChange = opts.onChange

    local sound = opts.sound
    if sound == nil then
        sound = DEFAULT_SOUND
    elseif sound == false or sound == "" then
        sound = nil
    end
    self.sound = sound

    self.trackColor = Pallid.UI.Color.surfaceMuted
    self.trackBorder = Pallid.UI.Color.border
    self.activeColor = Pallid.UI.Color.primaryStrong
    self.hoverColor = Pallid.UI.Color.accentSoft
    self._customActiveText = false

    self.style = {
        font = OptionUtil.resolveFont(opts.font),
        color = Pallid.UI.Color.textMuted,
        alignH = "left",
        alignV = "middle",
        ellipsis = "...",
    }
    self.activeStyle = {
        font = self.style.font,
        color = Pallid.UI.Color.contrastText(self.activeColor),
        alignH = "left",
        alignV = "middle",
        ellipsis = "...",
    }

    self:setOptions(options)
    if opts.selected ~= nil
        and self:_validIndex(opts.selected)
        and not self.items[opts.selected].disabled then
        self:setSelected(opts.selected, true)
    end
    self.thumb = self.selected
    self.thumbTarget = self.selected
    return self
end

--- Factory shortcut for `Segmented.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param options (string|table)[] Segment labels or tables.
--- @param opts table|nil Appearance and behaviour.
--- @return PallidSegmentedControl control New segmented control.
function Widgets.segmentedControl(x, y, w, h, options, opts)
    return Segmented.new(x, y, w, h, options, opts)
end

--- @param index integer Candidate segment index.
--- @return boolean valid True when index is an integer inside the list.
function Segmented:_validIndex(index)
    if type(index) ~= "number" or index ~= index or math.floor(index) ~= index then
        return false
    end
    return index >= 1 and index <= #self.items
end

--- Finds the first enabled segment at or after `start`, wrapping once.
--- @param start integer Starting 1-based index.
--- @return integer index Enabled segment index, or 0 when none.
function Segmented:_firstEnabledFrom(start)
    local count = #self.items
    if count == 0 then
        return 0
    end
    if start < 1 or start > count then
        start = 1
    end
    for offset = 0, count - 1 do
        local index = (start - 1 + offset) % count + 1
        if not self.items[index].disabled then
            return index
        end
    end
    return 0
end

--- Replaces options and clamps the active segment silently.
--- @param options (string|table)[]|nil New segments; nil clears the list.
--- @return PallidSegmentedControl self For chaining.
function Segmented:setOptions(options)
    if options ~= nil and type(options) ~= "table" then
        Pallid.log("SegmentedControl:setOptions expects a table of options")
        options = {}
    end

    self.options = {}
    self.items = {}
    self._hasIcons = false
    local list = options or {}
    for i = 1, #list do
        self.options[i] = list[i]
        self.items[i] = normaliseOption(list[i])
        if self.items[i].hasIcon then
            self._hasIcons = true
        end
    end

    self.hoverIndex = 0
    self.hover = 0
    self:_clampSelection()
    self.thumb = self.selected
    self.thumbTarget = self.selected
    self:_measureItems()
    return self
end

--- Keeps the active segment valid when the list or its disabled flags change.
function Segmented:_clampSelection()
    local count = #self.items
    if count == 0 then
        self.selected = 0
        return
    end
    if self:_validIndex(self.selected) and not self.items[self.selected].disabled then
        return
    end

    local start = 1
    if type(self.selected) == "number" and self.selected == self.selected then
        start = math.floor(self.selected)
    end
    self.selected = self:_firstEnabledFrom(start)
end

--- Pre-truncates labels so drawing never allocates strings or measures text.
function Segmented:_measureItems()
    local count = #self.items
    local segmentW = count > 0 and self.w / count or 0
    local iconSize = math.max(6, math.min(ICON_SIZE, self.h - 6))
    self.iconSize = iconSize
    local iconArea = self._hasIcons and (iconSize + ICON_GAP) or 0
    local maxWidth = math.max(0, segmentW - SEGMENT_PAD - iconArea)

    self._labelTexts = {}
    self._labelWidths = {}
    for i = 1, count do
        local text = Pallid.UI.truncateText(self.items[i].label, self.style.font, maxWidth)
        self._labelTexts[i] = text
        self._labelWidths[i] = getTextManager():MeasureStringX(self.style.font, text)
    end
end

--- Updates the widget bounds.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidSegmentedControl self For chaining.
function Segmented:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:_measureItems()
    return self
end

--- Replaces the label font on normal and active segments.
--- @param font UIFont|string|nil New font, or nil to keep the current one.
--- @return PallidSegmentedControl self For chaining.
function Segmented:setFont(font)
    if font ~= nil then
        local resolved = OptionUtil.resolveFont(font)
        self.style.font = resolved
        self.activeStyle.font = resolved
        self:_measureItems()
    end
    return self
end

--- Enables or disables the sliding thumb.
--- @param animate boolean True animates selection changes.
--- @return PallidSegmentedControl self For chaining.
function Segmented:setAnimated(animate)
    self.animated = animate == true
    if not self.animated then
        self.thumb = self.thumbTarget
    end
    return self
end

--- Replaces palette colours.
--- @param colors table Keys: `track`, `trackBorder`, `active`, `activeText`, `hover`, `text`.
--- @return PallidSegmentedControl self For chaining.
function Segmented:setColors(colors)
    colors = colors or {}
    if colors.track ~= nil then
        self.trackColor = colors.track
    end
    if colors.trackBorder ~= nil then
        self.trackBorder = colors.trackBorder
    end
    if colors.active ~= nil then
        self.activeColor = colors.active
        if not self._customActiveText then
            self.activeStyle.color = Pallid.UI.Color.contrastText(self.activeColor)
        end
    end
    if colors.activeText ~= nil then
        self.activeStyle.color = colors.activeText
        self._customActiveText = true
    end
    if colors.hover ~= nil then
        self.hoverColor = colors.hover
    end
    if colors.text ~= nil then
        self.style.color = colors.text
    end
    return self
end

--- Enables or disables the widget.
--- @param enabled boolean True enables the control and its input.
--- @return PallidSegmentedControl self For chaining.
function Segmented:setEnabled(enabled)
    Widgets.Widget.setEnabled(self, enabled)
    if not enabled then
        self.hoverIndex = 0
        self.hover = 0
    end
    return self
end

--- Selects a segment. Invalid indexes and disabled segments are ignored.
--- @param index integer New 1-based segment.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidSegmentedControl self For chaining.
function Segmented:setSelected(index, silent)
    if not self:_validIndex(index) then
        Pallid.log("SegmentedControl:setSelected expects an index inside the option list")
        return self
    end
    if self.items[index].disabled or index == self.selected then
        return self
    end

    self.selected = index
    self.thumbTarget = index
    if not self.animated then
        self.thumb = index
    end
    if not silent and self.onChange ~= nil then
        local item = self.items[index]
        self.onChange(self, index, item.label, item)
    end
    return self
end

--- Clears the active segment.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidSegmentedControl self For chaining.
function Segmented:clearSelection(silent)
    if self.selected == 0 then
        return self
    end
    self.selected = 0
    self.thumbTarget = 0
    if not self.animated then
        self.thumb = 0
    end
    if not silent and self.onChange ~= nil then
        self.onChange(self, 0, nil, nil)
    end
    return self
end

--- Returns the selected item.
--- @return integer index Active 1-based segment, or 0 when none is active.
function Segmented:getSelected()
    return self.selected
end

--- Returns true when the item is selected.
--- @param index integer Segment index.
--- @return boolean selected True when the segment is active.
function Segmented:isSelected(index)
    return self.selected == index
end

--- Returns the selected option.
--- @return string|nil label Active segment label, or nil.
function Segmented:getSelectedOption()
    local item = self.items[self.selected]
    return item ~= nil and item.label or nil
end

--- Returns the selected item.
--- @return PallidOption|nil item Active segment descriptor, or nil.
function Segmented:getSelectedItem()
    return self.items[self.selected]
end

--- Returns the absolute horizontal bounds of one segment.
--- @param index integer 1-based segment index.
--- @return number x Absolute left edge, or the control origin when invalid.
--- @return number w Segment width, or 0 when invalid.
function Segmented:segmentRect(index)
    local count = #self.items
    if count == 0 or not self:_validIndex(index) then
        return self:originX(), 0
    end
    local segmentW = self.w / count
    return self:originX() + (index - 1) * segmentW, segmentW
end

--- @param px number Cursor X in root-local coordinates.
--- @return integer|nil index Segment under the cursor, or nil outside.
function Segmented:_indexAt(px)
    local count = #self.items
    if count == 0 or self.w <= 0 then
        return nil
    end
    local localX = px - self:originX()
    if localX < 0 or localX >= self.w then
        return nil
    end
    local index = math.floor(localX / (self.w / count)) + 1
    if index < 1 then
        return 1
    elseif index > count then
        return count
    end
    return index
end

--- Handles a pointer press inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when a segment consumed the press.
function Segmented:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end
    local index = self:_indexAt(px)
    if index == nil then
        return false
    end
    if self.items[index].disabled then
        return true
    end

    local changed = index ~= self.selected
    self:setSelected(index)
    if changed and self.sound ~= nil and getSoundManager ~= nil then
        getSoundManager():playUISound(self.sound)
    end
    return true
end

--- Updates hover state for the current pointer position.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Segmented:onHoverMove(px, py)
    if not self.enabled then
        self.hoverIndex = 0
        return
    end
    local index = self:_indexAt(px) or 0
    if index ~= self.hoverIndex then
        self.hover = 0
    end
    self.hoverIndex = index
end

--- Clears the hovered segment.
function Segmented:onHoverEnd()
    self.hoverIndex = 0
    Widgets.Widget.onHoverEnd(self)
end

--- Eases the hover highlight and the sliding thumb. Per-frame so they do not
--- step at the game tick.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function Segmented:onAnimate(now, dt)
    local item = self.items[self.hoverIndex]
    local target = self._hover and self.enabled and item ~= nil and not item.disabled and 1 or 0
    self.hover = Widgets.approach(self.hover, target, HOVER_SPEED, dt)

    if not self.animated then
        self.thumb = self.thumbTarget
        return
    end
    self.thumb = Widgets.approach(self.thumb, self.thumbTarget, THUMB_SPEED, dt)
    if math.abs(self.thumb - self.thumbTarget) < 0.002 then
        self.thumb = self.thumbTarget
    end
end


