require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"
local normaliseOption = require "pallid/ui/widgets/internal/option_item"
local OptionUtil = require "pallid/ui/widgets/internal/option_util"
local addInputMethods = require "pallid/ui/widgets/popup_select/input"
local addDrawMethods = require "pallid/ui/widgets/popup_select/draw"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local Textures = Pallid.UI.Textures

local ITEM_HEIGHT = 22
local LIST_GAP = 2
local ROUND = 3
local CHECK = 12
local CHECK_GAP = 6
local ICON = 14
local ICON_GAP = 6
local SIDE_PAD = 8
local RIGHT_PAD = 8
local DEFAULT_MAX_HEIGHT = 220
local SCROLL_STEP = 22
local ARROW_SIZE = 9
local ICON_DIR = "media/assets/ui/pallid/icons/"
local ICON_OPTS = { mode = "fit" }
local RECT_SHAPE = Pallid.UI.Shape.rect()

--- Shared base for Dropdown and MultiSelect. Handles the popup list geometry,
--- scrolling, clipping, row rendering, options, opening/closing and mouse input.
--- Subclasses provide the field content and selection model.
--- @class PallidPopupSelect : PallidWidget
--- @field options (string|table)[] Raw options in caller order.
--- @field items PallidOption[] Normalised options.
--- @field open boolean True while the popup is open.
--- @field highlight integer Hovered popup row, or 0.
--- @field scrollY number Popup scroll offset.
--- @field maxHeight number Maximum popup height.
--- @field itemHeight number Popup row height.
--- @field onOpen fun(select: PallidPopupSelect)|nil Called after opening.
--- @field onClose fun(select: PallidPopupSelect)|nil Called after closing.
local PopupSelect = Widgets.class("PopupSelect")
addInputMethods(PopupSelect)
addDrawMethods(PopupSelect)

--- Initialises shared popup-select state. Subclasses must seed their selection
--- fields before calling this method.
--- @param options (string|table)[] Option definitions.
--- @param opts table|nil Shared options.
function PopupSelect:_initPopupSelect(options, opts)
    opts = opts or {}

    self.options = {}
    self.items = {}
    self.open = false
    self.highlight = 0
    self.scrollY = 0
    self.scrollDragging = false
    self.dragStartY = 0
    self.dragStartScroll = 0
    self.hover = 0
    self.acceptsFocus = false
    self.maxHeight = opts.maxHeight or DEFAULT_MAX_HEIGHT
    self.itemHeight = opts.itemHeight or ITEM_HEIGHT
    self.listGap = opts.listGap or LIST_GAP
    self.arrowSize = opts.arrowSize or ARROW_SIZE
    self.onOpen = opts.onOpen
    self.onClose = opts.onClose

    local sound = opts.sound
    if sound == nil then
        sound = "UISelectListItem"
    elseif sound == false or sound == "" then
        sound = nil
    end
    self.sound = sound

    self.style = {
        font = OptionUtil.resolveFont(opts.font),
        color = Pallid.UI.Color.text,
        alignH = "left",
        alignV = "middle",
        ellipsis = "...",
    }

    self.fill = Pallid.UI.Color.surface
    self.hoverFill = Pallid.UI.Color.accentSoft
    self.listFill = Pallid.UI.Color.surface
    self.borderColor = Pallid.UI.Color.border
    self.highlightColor = Pallid.UI.Color.primarySoft
    self.arrowColor = Pallid.UI.Color.textMuted
    self.markerFill = Pallid.UI.Color.surface
    self.markerBorder = Pallid.UI.Color.border
    self.checkColor = Pallid.UI.Color.primaryStrong

    self._arrowTexture = Textures.get(ICON_DIR .. "arrow-down-04.png")
    self._checkTexture = Textures.get(ICON_DIR .. "tick.png")
    self._hasIcons = false
    self._visibleCount = 0
    self._maxScroll = 0
    self._textOffset = SIDE_PAD + CHECK + CHECK_GAP
    self._popupMaxWidth = 0
    self._popupLabels = {}

    self:setOptions(options)
end

--- Replaces the option list. Selection is clamped by the subclass hook.
--- @param options (string|table)[]|nil New options; nil clears the list.
--- @return PallidPopupSelect self For chaining.
function PopupSelect:setOptions(options)
    if options ~= nil and type(options) ~= "table" then
        Pallid.log("PopupSelect:setOptions expects a table of options")
        options = {}
    end
    if self.open then
        self:close()
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
    self:_clampSelection()
    self:_layoutPopup()
    self:_refreshFieldLayout()
    return self
end

--- Recomputes popup labels and text offsets.
function PopupSelect:_layoutPopup()
    local markerSlot = CHECK + CHECK_GAP
    local iconSlot = self._hasIcons and (ICON + ICON_GAP) or 0
    self._textOffset = SIDE_PAD + markerSlot + iconSlot
    self._popupMaxWidth = math.max(0, self.w - self._textOffset - RIGHT_PAD)

    self._popupLabels = {}
    for i = 1, #self.items do
        self._popupLabels[i] = Pallid.UI.truncateText(
            self.items[i].label,
            self.style.font,
            self._popupMaxWidth
        )
    end
    self:_updateScrollMetrics()
end

--- Recomputes popup height and scroll range from maxHeight and row count.
function PopupSelect:_updateScrollMetrics()
    local count = #self.items
    local maxRows = math.max(1, math.floor((self.maxHeight - 2) / self.itemHeight))
    local visible = math.min(count, maxRows)
    self._visibleCount = visible
    self._maxScroll = math.max(0, (count - visible) * self.itemHeight)
    self.scrollY = math.max(0, math.min(self.scrollY, self._maxScroll))
end

--- Returns the option-list rectangle.
--- @return number x Popup left.
--- @return number y Popup top.
--- @return number w Popup width.
--- @return number h Popup height.
function PopupSelect:listRect()
    self:_updateScrollMetrics()
    local count = #self.items
    local visible = math.max(0, self._visibleCount)
    local height = visible * self.itemHeight + 2
    local x = self:originX()
    local y = self:originY() + self.h + self.listGap
    local root = self:getRoot()

    if root ~= nil then
        local maxHeight = math.max(self.itemHeight + 2, root.h - 4)
        if height > maxHeight then
            height = maxHeight
            visible = math.max(1, math.floor((height - 2) / self.itemHeight))
            height = visible * self.itemHeight + 2
            self._visibleCount = visible
            self._maxScroll = math.max(0, (count - visible) * self.itemHeight)
            self.scrollY = math.max(0, math.min(self.scrollY, self._maxScroll))
        end
        if y + height > root.h - 2 then
            y = self:originY() - height - self.listGap
        end
        x = math.max(2, math.min(x, math.max(2, root.w - self.w - 2)))
        y = math.max(2, math.min(y, math.max(2, root.h - height - 2)))
    else
        x = math.max(2, x)
        y = math.max(2, y)
    end
    return x, y, self.w, height
end

--- Returns true when the point lies inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return boolean inside True when the cursor is over the field or open list.
function PopupSelect:isInside(px, py)
    if Widgets.Widget.isInside(self, px, py) then
        return true
    end
    if not self.open then
        return false
    end
    local x, y, w, h = self:listRect()
    return px >= x and px < x + w and py >= y and py < y + h
end

--- Shows the popup list.
--- @return PallidPopupSelect self For chaining.
function PopupSelect:show()
    if self.open or #self.items == 0 then
        return self
    end
    self.open = true
    self.highlight = self:_initialHighlight()
    self.scrollY = 0
    self.scrollDragging = false
    self._openOx = self._ox or 0
    self._openOy = self._oy or 0
    local root = self:getRoot()
    if root ~= nil then
        if root.openPopup ~= nil and root.openPopup ~= self then
            root.openPopup:close()
        end
        root.openPopup = self
    end
    self:_playSound()
    if self.onOpen ~= nil then
        self.onOpen(self)
    end
    return self
end

--- Closes the popup list.
--- @return PallidPopupSelect self For chaining.
function PopupSelect:close()
    if not self.open then
        return self
    end
    self.open = false
    self.highlight = 0
    self.scrollDragging = false
    local root = self:getRoot()
    if root ~= nil and root.openPopup == self then
        root.openPopup = nil
    end
    if self.onClose ~= nil then
        self.onClose(self)
    end
    return self
end

--- @return integer index Initial highlighted row.
function PopupSelect:_initialHighlight()
    return 0
end

--- @param index integer Candidate row.
--- @return boolean valid True for a real row index.
function PopupSelect:_validIndex(index)
    if type(index) ~= "number" or index ~= index or math.floor(index) ~= index then
        return false
    end
    return index >= 1 and index <= #self.items
end

--- @param index integer Row index.
--- @return boolean checked True when the row is selected.
function PopupSelect:_isRowChecked(index)
    return false
end

--- Replaces the field content layout after option/font/size changes.
function PopupSelect:_refreshFieldLayout()
end

--- Applies a row click. Implemented by the selection model.
--- @param index integer Row index.
function PopupSelect:_activateRow(index)
end

--- Clamps selection after options change.
function PopupSelect:_clampSelection()
end

--- @param index integer Row index.
--- @return boolean disabled True when the row cannot be activated.
function PopupSelect:_rowDisabled(index)
    local item = self.items[index]
    return item == nil or item.disabled
end

--- @param px number Pointer X in local coordinates.
--- @param py number Pointer Y in local coordinates.
--- @param x number Option-list X coordinate.
--- @param y number Option-list Y coordinate.
--- @return integer|nil index Row under the cursor.
function PopupSelect:_indexAt(px, py, x, y)
    if not self.open then
        return nil
    end
    if px < x or px >= x + self.w or py < y + 1 or py >= y + 1 + self._visibleCount * self.itemHeight then
        return nil
    end
    local contentY = py - (y + 1) + self.scrollY
    local index = math.floor(contentY / self.itemHeight) + 1
    if index < 1 or index > #self.items then
        return nil
    end
    return index
end

--- Returns the scrollbar rectangle.
--- @return number|nil x Scrollbar track X, or nil when scrolling is not needed.
--- @return number|nil y Scrollbar track Y.
--- @return number|nil h Scrollbar track height.
function PopupSelect:scrollbarRect()
    if self._maxScroll <= 0 then
        return nil
    end
    local x, y, w, h = self:listRect()
    return x + w - 6, y + 3, h - 6
end

--- @return number|nil x Track X.
--- @return number|nil y Track Y.
--- @return number|nil h Track height.
--- @return number|nil thumbY Thumb Y.
--- @return number|nil thumbH Thumb height.
--- @return number|nil travel Thumb travel in pixels.
function PopupSelect:_scrollMetrics()
    local trackX, trackY, trackH = self:scrollbarRect()
    if trackX == nil then
        return nil
    end
    local thumbH = math.min(
        trackH,
        math.max(12, trackH * self._visibleCount * self.itemHeight
            / math.max(1, self._visibleCount * self.itemHeight + self._maxScroll))
    )
    local travel = math.max(0, trackH - thumbH)
    local thumbY = trackY + (self._maxScroll > 0 and travel * self.scrollY / self._maxScroll or 0)
    return trackX, trackY, trackH, thumbY, thumbH, travel
end

--- Plays the configured click sound.
function PopupSelect:_playSound()
    if self.sound ~= nil and getSoundManager ~= nil then
        getSoundManager():playUISound(self.sound)
    end
end

--- Enables or disables the widget.
--- @param enabled boolean True enables the control and its popup.
--- @return PallidPopupSelect self For chaining.
function PopupSelect:setEnabled(enabled)
    Widgets.Widget.setEnabled(self, enabled)
    if not enabled then
        self:close()
    end
    return self
end

--- Updates the widget bounds.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidPopupSelect self For chaining.
function PopupSelect:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:_layoutPopup()
    self:_refreshFieldLayout()
    return self
end

--- Replaces the font and refreshes popup labels and field content.
--- @param font UIFont|string|nil New font, or nil to keep it.
--- @return PallidPopupSelect self For chaining.
function PopupSelect:setFont(font)
    if font ~= nil then
        self.style.font = OptionUtil.resolveFont(font)
        self:_layoutPopup()
        self:_refreshFieldLayout()
    end
    return self
end

--- Replaces shared popup colours.
--- @param colors table Keys: `fill`, `hoverFill`, `listFill`, `border`, `highlight`, `arrow`, `markerFill`, `markerBorder`, `check`, `text`.
--- @return PallidPopupSelect self For chaining.
function PopupSelect:setColors(colors)
    colors = colors or {}
    if colors.fill ~= nil then
        self.fill = colors.fill
    end
    if colors.hoverFill ~= nil then
        self.hoverFill = colors.hoverFill
    end
    if colors.listFill ~= nil then
        self.listFill = colors.listFill
    end
    if colors.border ~= nil then
        self.borderColor = colors.border
    end
    if colors.highlight ~= nil then
        self.highlightColor = colors.highlight
    end
    if colors.arrow ~= nil then
        self.arrowColor = colors.arrow
    end
    if colors.markerFill ~= nil then
        self.markerFill = colors.markerFill
    end
    if colors.markerBorder ~= nil then
        self.markerBorder = colors.markerBorder
    end
    if colors.check ~= nil then
        self.checkColor = colors.check
    end
    if colors.text ~= nil then
        self.style.color = colors.text
    end
    return self
end
