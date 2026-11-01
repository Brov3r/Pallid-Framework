require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/inputtext"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local INPUT_HEIGHT = 24
local CHIP_HEIGHT = 20
local CHIP_GAP = 4
local CHIP_PAD = 6
local CLOSE_W = 14
local ROW_GAP = 4
local MAX_TAG_WIDTH = 180

--- Tag editor: a text field on the first row and removable chips below it.
--- Enter adds the typed tag, the close cross removes one, and Backspace on an
--- empty field removes the last tag. Chips that do not fit are replaced by a
--- `+N` counter. Validation rejects a tag before it enters the list.
--- @class PallidTagInput : PallidWidget
--- @field tags string[] Current tags in insertion order.
--- @field maxTags integer Maximum tag count; 0 means unlimited.
--- @field validateTag fun(tag: string): boolean|nil Optional per-tag validator.
--- @field onChange fun(input: PallidTagInput, tags: string[])|nil Called after the tag list changes.
--- @field input PallidInputText Text field for the next tag.
--- @field filterText string Current field text.
local TagInput = Widgets.class("TagInput")

--- Creates a new `TagInput` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number|nil Height in pixels; nil or 0 fits one input row and one chip row.
--- @param opts table|nil Content and behaviour.
--- @field opts.tags string[]|nil Initial tags.
--- @field opts.maxTags integer|nil Maximum tag count; 0 or nil is unlimited.
--- @field opts.placeholder string|nil Text field placeholder.
--- @field opts.validate fun(tag: string): boolean|nil Rejects a tag when it returns false.
--- @field opts.onChange fun(input: PallidTagInput, tags: string[])|nil Tag list callback.
--- @field opts.inputHeight number|nil Text field height, defaults to 24.
--- @return PallidTagInput input New tag editor.
function TagInput.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, TagInput)
    self:init(x, y, w or 0, h or 0)

    self.tags = {}
    local initial = opts.tags
    if type(initial) == "table" then
        for i = 1, #initial do
            local tag = tostring(initial[i])
            if tag ~= "" then
                self.tags[#self.tags + 1] = tag
            end
        end
    end
    self.maxTags = math.max(0, math.floor(opts.maxTags or 0))
    if self.maxTags > 0 and #self.tags > self.maxTags then
        for i = #self.tags, self.maxTags + 1, -1 do
            table.remove(self.tags, i)
        end
    end
    self.validateTag = opts.validate
    self.onChange = opts.onChange
    self.inputHeight = math.max(16, opts.inputHeight or INPUT_HEIGHT)
    self.filterText = ""
    self._chipX = {}
    self._chipY = {}
    self._chipW = {}
    self._chipLabel = {}
    self._visibleCount = 0
    self._hiddenCount = 0
    self._hiddenLabel = nil
    self._pollBack = false

    self.style = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.textPrimary,
        alignH = "left",
        alignV = "middle",
        ellipsis = "...",
    }
    self.chipStyle = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.textPrimary,
        alignH = "left",
        alignV = "middle",
        ellipsis = "...",
    }
    self.chipFill = Pallid.UI.Color.surfaceMuted
    self.chipBorder = Pallid.UI.Color.border
    self.closeColor = Pallid.UI.Color.textMuted

    if self.h <= 0 then
        self.h = self.inputHeight + ROW_GAP + CHIP_HEIGHT
    end

    local input = Widgets.inputText(0, 0, self.w, self.inputHeight, {
        placeholder = opts.placeholder,
        background = Pallid.UI.Color.surface,
        border = Pallid.UI.Color.border,
        radius = 4,
        paddingX = 7,
        paddingY = 2,
        onSubmit = function()
            self:_addFromField()
        end,
        onChange = function(_, text)
            self.filterText = text
        end,
        onKeyPress = function(_, key)
            return self:_onFieldKey(key)
        end,
    })
    self.input = input
    self:add(input)
    self:_layoutTags()
    return self
end

--- Factory shortcut for `TagInput.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number|nil Height in pixels; nil or 0 fits one input row and one chip row.
--- @param opts table|nil Content and behaviour; see `TagInput.new`.
--- @return PallidTagInput input New tag editor.
function Widgets.tagInput(x, y, w, h, opts)
    return TagInput.new(x, y, w, h, opts)
end

--- Replaces every tag.
--- @param tags string[]|nil New tags; nil clears the list.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidTagInput self For chaining.
function TagInput:setTags(tags, silent)
    self.tags = {}
    if type(tags) == "table" then
        for i = 1, #tags do
            local tag = tostring(tags[i])
            if tag ~= "" and (self.maxTags == 0 or #self.tags < self.maxTags) then
                self.tags[#self.tags + 1] = tag
            end
        end
    end
    self:_layoutTags()
    if not silent and self.onChange ~= nil then
        self.onChange(self, self.tags)
    end
    return self
end

--- Returns the current tags.
--- @return string[] tags Live tag list in insertion order.
function TagInput:getTags()
    return self.tags
end

--- Adds a tag if it passes validation and the limit.
--- @param tag string|nil Tag text.
--- @param silent boolean|nil True skips `onChange`.
--- @return boolean added True when the tag entered the list.
function TagInput:addTag(tag, silent)
    if tag == nil then
        return false
    end
    tag = string.gsub(tostring(tag), "^%s+", "")
    tag = string.gsub(tag, "%s+$", "")
    if tag == "" then
        return false
    end
    if self.maxTags > 0 and #self.tags >= self.maxTags then
        return false
    end
    if self.validateTag ~= nil and self.validateTag(tag) == false then
        return false
    end
    for i = 1, #self.tags do
        if self.tags[i] == tag then
            return false
        end
    end
    self.tags[#self.tags + 1] = tag
    self:_layoutTags()
    if not silent and self.onChange ~= nil then
        self.onChange(self, self.tags)
    end
    return true
end

--- Removes a tag by index.
--- @param index integer One-based tag index.
--- @param silent boolean|nil True skips `onChange`.
--- @return boolean removed True when a tag was removed.
function TagInput:removeTag(index, silent)
    if self.tags[index] == nil then
        return false
    end
    table.remove(self.tags, index)
    self:_layoutTags()
    if not silent and self.onChange ~= nil then
        self.onChange(self, self.tags)
    end
    return true
end

--- Reads the field and adds its text as a tag.
function TagInput:_addFromField()
    local input = self.input
    if input == nil then
        return
    end
    local text = input:getText()
    if self:addTag(text) then
        input:setText("", true)
        self.filterText = ""
    end
end

--- Handles the empty-field Backspace shortcut.
--- @param key integer Keyboard.KEY_* value.
--- @return boolean handled True when a tag was removed.
function TagInput:_onFieldKey(key)
    if Keyboard ~= nil and key == Keyboard.KEY_BACK and self.input ~= nil
        and self.input:getText() == "" and #self.tags > 0 then
        self:removeTag(#self.tags)
        return true
    end
    return false
end

--- Polls Backspace while the native field owns text entry. The game suppresses
--- `Events.OnKeyPressed` for the whole text-entry period, so an edge on the raw
--- key state is the reliable way to remove the last tag from an empty field.
--- @param now number Current game-tick time in seconds.
--- @param dt number Seconds since the previous tick, 0..0.1.
function TagInput:onUpdate(now, dt)
    local keyboard = Keyboard
    if keyboard == nil or keyboard.isKeyDown == nil or self.input == nil then
        return
    end
    local back = keyboard.isKeyDown(keyboard.KEY_BACK)
    if back and not self._pollBack and self.input:getText() == "" and #self.tags > 0 then
        self:removeTag(#self.tags)
    end
    self._pollBack = back
end

--- Recomputes chip positions, wrapping rows and reserving the `+N` counter.
function TagInput:_layoutTags()
    local chips = self._chipX
    for i = #chips, 1, -1 do
        self._chipX[i] = nil
        self._chipY[i] = nil
        self._chipW[i] = nil
        self._chipLabel[i] = nil
    end
    self._visibleCount = 0
    self._hiddenCount = 0
    self._hiddenLabel = nil

    local total = #self.tags
    if total == 0 or self.w <= 0 then
        return
    end

    local manager = getTextManager()
    local font = self.chipStyle.font
    local innerW = math.max(0, self.w - 2)
    local maxChipW = math.min(innerW, MAX_TAG_WIDTH)
    local x = 2
    local y = self.inputHeight + ROW_GAP
    local bottom = self.h

    for i = 1, total do
        local label = self.tags[i]
        local textW = manager:MeasureStringX(font, label)
        local chipW = math.min(maxChipW, textW + CHIP_PAD * 2 + CLOSE_W)
        if x + chipW > innerW + 2 and x > 2 then
            x = 2
            y = y + CHIP_HEIGHT + CHIP_GAP
        end
        if y + CHIP_HEIGHT > bottom then
            self._hiddenCount = total - (i - 1)
            break
        end
        self._chipX[i] = x
        self._chipY[i] = y
        self._chipW[i] = chipW
        self._chipLabel[i] = Pallid.UI.truncateText(label, font, math.max(0, chipW - CHIP_PAD * 2 - CLOSE_W))
        self._visibleCount = i
        x = x + chipW + CHIP_GAP
    end

    -- Reserve room for the counter by dropping trailing chips until it fits.
    while self._hiddenCount > 0 and self._visibleCount > 0 do
        local visible = self._visibleCount
        local chipX = self._chipX[visible]
        local chipY = self._chipY[visible]
        local counterW = manager:MeasureStringX(font, "+" .. self._hiddenCount) + CHIP_PAD * 2
        local counterX = chipX
        local counterY = chipY
        if counterX + counterW > innerW + 2 then
            counterX = 2
            counterY = chipY + CHIP_HEIGHT + CHIP_GAP
        end
        if counterY + CHIP_HEIGHT <= bottom then
            break
        end
        self._chipX[visible] = nil
        self._chipY[visible] = nil
        self._chipW[visible] = nil
        self._chipLabel[visible] = nil
        self._visibleCount = visible - 1
        self._hiddenCount = self._hiddenCount + 1
    end
    if self._hiddenCount > 0 then
        self._hiddenLabel = "+" .. self._hiddenCount
    end
end

--- Updates the widget bounds and the chip layout.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidTagInput self For chaining.
function TagInput:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    if self.input ~= nil then
        self.input:setBounds(0, 0, w, self.inputHeight)
    end
    self:_layoutTags()
    return self
end

--- Handles a press on a chip close cross.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the press was consumed.
function TagInput:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end
    local x, y = self:originX(), self:originY()
    local localX = px - x
    local localY = py - y
    for i = 1, self._visibleCount do
        local chipX = self._chipX[i]
        local chipY = self._chipY[i]
        local chipW = self._chipW[i]
        if chipX ~= nil and localX >= chipX + chipW - CLOSE_W - CHIP_PAD
            and localX < chipX + chipW
            and localY >= chipY and localY < chipY + CHIP_HEIGHT then
            self:removeTag(i)
            return true
        end
    end
    return self:isInside(px, py)
end

--- Draws the chip row and the overflow counter.
--- @param el ISUIElement Host element the tree is rendered into.
function TagInput:drawSelf(el)
    local x, y = self:originX(), self:originY()
    local style = self.chipStyle

    for i = 1, self._visibleCount do
        local chipX = self._chipX[i]
        local chipY = self._chipY[i]
        local chipW = self._chipW[i]
        if chipX ~= nil then
            local ax = x + chipX
            local ay = y + chipY
            Pallid.UI.roundedRect(el, ax, ay, chipW, CHIP_HEIGHT, CHIP_HEIGHT * 0.5, self:shade(self.chipFill))
            Pallid.UI.roundedBorder(el, ax, ay, chipW, CHIP_HEIGHT, CHIP_HEIGHT * 0.5, 1, self:shade(self.chipBorder))

            style.color = self:shade(Pallid.UI.Color.textPrimary)
            style.maxWidth = math.max(0, chipW - CHIP_PAD * 2 - CLOSE_W)
            Pallid.UI.text(el, self._chipLabel[i] or "", ax + CHIP_PAD, ay + CHIP_HEIGHT * 0.5, style)
            style.maxWidth = nil

            local closeX = ax + chipW - CHIP_PAD - 5
            local closeY = ay + CHIP_HEIGHT * 0.5
            local color = self:shade(self.closeColor)
            Pallid.UI.line(el, closeX - 3, closeY - 3, closeX + 3, closeY + 3, 1, color)
            Pallid.UI.line(el, closeX - 3, closeY + 3, closeX + 3, closeY - 3, 1, color)
        end
    end

    if self._hiddenCount > 0 then
        local label = self._hiddenLabel or ""
        local manager = getTextManager()
        local width = manager:MeasureStringX(style.font, label) + CHIP_PAD * 2
        local innerW = math.max(0, self.w - 2)
        local chipX = 2
        local chipY = self.inputHeight + ROW_GAP
        if self._visibleCount > 0 then
            local last = self._visibleCount
            chipX = self._chipX[last] + self._chipW[last] + CHIP_GAP
            chipY = self._chipY[last]
            if chipX + width > innerW + 2 then
                chipX = 2
                chipY = chipY + CHIP_HEIGHT + CHIP_GAP
            end
        end
        if chipY + CHIP_HEIGHT <= self.h then
            local ax = x + chipX
            local ay = y + chipY
            Pallid.UI.roundedRect(el, ax, ay, width, CHIP_HEIGHT, CHIP_HEIGHT * 0.5, self:shade(self.chipBorder))
            style.color = self:shade(Pallid.UI.Color.textMuted)
            Pallid.UI.text(el, label, ax + CHIP_PAD, ay + CHIP_HEIGHT * 0.5, style)
        end
    end
end
