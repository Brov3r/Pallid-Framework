require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/inputtext"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local ICON_DIR = "media/assets/ui/pallid/icons/"
local ICON_OPTS = { mode = "fit" }
local ICON_SIZE = 12
local LEFT_PAD = 22
local RIGHT_INSET = 20

--- Search field: a single-line input with a leading magnifier, an optional clear
--- button and an optional debounced `onSearch` callback.
---
--- It is an InputText subclass, so masks, patterns, focus and native text entry
--- behave exactly like every other Pallid input.
--- @class PallidSearchField : PallidInputText
--- @field onSearch fun(field: PallidSearchField, text: string)|nil Debounced search callback.
--- @field debounce number Seconds of inactivity before `onSearch` fires; 0 fires on each change.
--- @field showClear boolean True draws the clear button while text is not empty.
--- @field _searchTimer number Remaining debounce time in seconds.
--- @field _pendingText string Text waiting for the debounce to expire.
local SearchField = Widgets.class("SearchField", Widgets.InputText)

--- Creates a new `SearchField` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Search and input settings.
--- @field opts.placeholder string|nil Placeholder text.
--- @field opts.text string|nil Initial value.
--- @field opts.debounce number|nil Debounce in seconds, defaults to 0.
--- @field opts.onSearch fun(field: PallidSearchField, text: string)|nil Search callback.
--- @field opts.onChange fun(input: PallidInputBase, text: string, raw: string)|nil Change callback.
--- @field opts.showClear boolean|nil False hides the clear button.
--- @field opts.font UIFont|string|nil Font or a Pallid.UI.Fonts key.
--- @return PallidSearchField field New search field.
function SearchField.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, SearchField)
    local inputOpts = {}
    for key, value in pairs(opts) do
        inputOpts[key] = value
    end
    inputOpts.paddingX = LEFT_PAD
    inputOpts.paddingY = opts.paddingY or 2
    self:initInput(x, y, w or 0, h or 0, inputOpts)

    -- Keep the search callbacks separate from the raw input change callback.
    self.onSearch = opts.onSearch
    self.debounce = math.max(0, opts.debounce or 0)
    self.showClear = opts.showClear ~= false
    self._searchTimer = 0
    self._pendingText = self:getText()
    self._lastSearchText = self._pendingText
    self.rightInset = self.showClear and RIGHT_INSET or 4
    self._searchTexture = Pallid.UI.Textures.get(ICON_DIR .. "search.png")
    self._clearTexture = Pallid.UI.Textures.get(ICON_DIR .. "cross.png")
    return self
end

--- Factory shortcut for `SearchField.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Search and input settings; see `SearchField.new`.
--- @return PallidSearchField field New search field.
function Widgets.searchField(x, y, w, h, opts)
    return SearchField.new(x, y, w, h, opts)
end

--- Returns the clear button zone in root-local coordinates.
--- @return number zoneX Clear-zone left edge in root-local coordinates.
--- @return number zoneY Clear-zone top edge.
--- @return number zoneW Clear-zone width.
--- @return number zoneH Clear-zone height.
function SearchField:clearRect()
    return self:originX() + self.w - RIGHT_INSET, self:originY() + 2, RIGHT_INSET - 2, self.h - 4
end

--- Returns true when a point lies on the visible clear button.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean inside True when the point is on the clear button.
function SearchField:_isOverClear(px, py)
    if not self.showClear or self:getText() == "" then
        return false
    end
    local x, y, w, h = self:clearRect()
    return px >= x and px < x + w and py >= y and py < y + h
end

--- Clears the field and notifies the normal input callback.
--- @return PallidSearchField self For chaining.
function SearchField:clear()
    self:setText("")
    if self.box ~= nil then
        self.box:focus()
    end
    return self
end

--- Handles the clear button before the native field receives the click.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the click was consumed.
function SearchField:onDown(px, py, button)
    if button ~= "right" and self:_isOverClear(px, py) then
        self:clear()
        return true
    end
    return Widgets.InputText.onDown(self, px, py, button)
end

--- Advances the debounce timer after the normal input update.
--- @param now number Current game-tick time in seconds.
--- @param dt number Seconds since the previous tick, 0..0.1.
function SearchField:onUpdate(now, dt)
    Widgets.InputBase.onUpdate(self, now, dt)

    local text = self:getText()
    if text ~= self._pendingText then
        self._pendingText = text
        self._searchTimer = self.debounce
        if self.debounce <= 0 then
            self:_emitSearch(text)
        end
        return
    end
    if self._searchTimer > 0 then
        self._searchTimer = math.max(0, self._searchTimer - dt)
        if self._searchTimer <= 0 then
            self:_emitSearch(self._pendingText)
        end
    end
end

--- Reports the search text to `onSearch` when it changed.
--- @param text string Text to report to `onSearch`.
function SearchField:_emitSearch(text)
    if text == self._lastSearchText then
        return
    end
    self._lastSearchText = text
    if self.onSearch ~= nil then
        self.onSearch(self, text)
    end
end

--- Paints the input chrome, the search icon and the clear button.
--- @param el ISUIElement Host element the tree is rendered into.
function SearchField:drawSelf(el)
    Widgets.InputBase.drawSelf(self, el)

    local x, y = self:originX(), self:originY()
    local iconY = y + (self.h - ICON_SIZE) * 0.5
    if self._searchTexture ~= nil then
        Pallid.UI.texture(
            el,
            self._searchTexture,
            x + 6,
            iconY,
            ICON_SIZE,
            ICON_SIZE,
            self:shade(Pallid.UI.Color.textMuted),
            ICON_OPTS
        )
    end

    if self.showClear and self:getText() ~= "" and self._clearTexture ~= nil then
        local zoneX, zoneY, zoneW, zoneH = self:clearRect()
        Pallid.UI.texture(
            el,
            self._clearTexture,
            zoneX + (zoneW - ICON_SIZE) * 0.5,
            zoneY + (zoneH - ICON_SIZE) * 0.5,
            ICON_SIZE,
            ICON_SIZE,
            self:shade(Pallid.UI.Color.textMuted),
            ICON_OPTS
        )
    end
end

--- Returns the preferred search-field size.
--- @param maxW number|nil Available width.
--- @param maxH number|nil Available height.
--- @return number width Preferred width in pixels.
--- @return number height Preferred height in pixels.
function SearchField:preferredSize(maxW, maxH)
    local width = maxW or math.max(160, self.w)
    return width, math.max(22, self.h)
end
