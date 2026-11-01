require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/virtuallist"
local normaliseOption = require "pallid/ui/widgets/internal/option_item"
local OptionUtil = require "pallid/ui/widgets/internal/option_util"
local ValueField = require "pallid/ui/widgets/internal/value_field"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local ICON_SIZE = 14
local SIDE_PAD = 6
local ICON_GAP = 6

--- Selectable list built on VirtualList. It provides option normalisation,
--- default row painting, single/multi selection and keyboard navigation, while
--- still allowing a custom `render` when the caller needs full control.
--- @class PallidListBox : PallidWidget
--- @field items PallidOption[] Normalised items in caller order.
--- @field list PallidVirtualList Virtualised row renderer.
--- @field getLabel fun(item: PallidOption, index: integer): string|nil Label resolver.
--- @field onSelect fun(list: PallidListBox, index: integer, item: PallidOption)|nil Selection callback.
--- @field onActivate fun(list: PallidListBox, index: integer, item: PallidOption)|nil Enter/double-click callback.
--- @field render fun(el: ISUIElement, index: integer, x: number, y: number, w: number, h: number, state: PallidVirtualRowState, item: PallidOption, list: PallidListBox)|nil Custom row painter.
--- @field emptyText string|nil Text shown when the list has no items.
local ListBox = Widgets.class("ListBox")

--- Creates a new `ListBox` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Items and behaviour.
--- @field opts.items (string|table)[]|nil Initial items.
--- @field opts.rowHeight number|fun(index: integer): number|nil Row height, defaults to 22.
--- @field opts.selectionMode "single"|"multi"|"none"|nil Defaults to "single".
--- @field opts.getLabel fun(item: PallidOption, index: integer): string|nil Label resolver.
--- @field opts.onSelect fun(list: PallidListBox, index: integer, item: PallidOption)|nil Selection callback.
--- @field opts.onActivate fun(list: PallidListBox, index: integer, item: PallidOption)|nil Enter callback.
--- @field opts.render fun(el: ISUIElement, index: integer, x: number, y: number, w: number, h: number, state: PallidVirtualRowState, item: PallidOption, list: PallidListBox)|nil Custom row painter.
--- @field opts.emptyText string|nil Text shown when the list is empty.
--- @field opts.background PallidColor|nil List fill.
--- @field opts.border PallidColor|nil List outline.
--- @field opts.radius number|nil Corner radius, defaults to 4.
--- @field opts.barSize number|nil Scrollbar thickness.
--- @field opts.barGap number|nil Scrollbar gap.
--- @return PallidListBox box New list box.
function ListBox.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, ListBox)
    self:init(x, y, w or 0, h or 0)

    self.items = {}
    self.getLabel = opts.getLabel
    self.onSelect = opts.onSelect
    self.onActivate = opts.onActivate
    self.render = opts.render
    self.emptyText = opts.emptyText
    self.background = opts.background or Pallid.UI.Color.surface
    self.borderColor = opts.border or Pallid.UI.Color.border
    self.radius = opts.radius or 4
    self.rowHover = Pallid.UI.Color.accentSoft
    self.rowSelected = Pallid.UI.Color.primarySoft
    self.textColor = Pallid.UI.Color.text
    self.disabledColor = Pallid.UI.Color.textDisabled
    self.style = {
        font = Pallid.UI.Fonts.small,
        color = self.textColor,
        alignH = "left",
        alignV = "middle",
        ellipsis = "...",
    }

    local function rowRender(el, index, rowX, rowY, rowW, rowH, state)
        if self.render ~= nil then
            self.render(el, index, rowX, rowY, rowW, rowH, state, self.items[index], self)
        else
            self:_drawRow(el, index, rowX, rowY, rowW, rowH, state)
        end
    end

    self.list = Widgets.virtualList(0, 0, self.w, self.h, {
        itemCount     = 0,
        rowHeight     = opts.rowHeight or 22,
        selectionMode = opts.selectionMode or "single",
        background    = nil,
        border        = nil,
        barSize       = opts.barSize,
        barGap        = opts.barGap,
        render        = rowRender,
        onSelect      = function(_, index)
            self:_notifySelect(index)
        end,
    })
    self.list.acceptsFocus = true
    self.list.onKeyPress = function(_, key)
        return self:onKeyPress(key)
    end
    self:add(self.list)
    self.acceptsFocus = true

    self:setItems(opts.items, true)
    return self
end

--- Factory shortcut for `ListBox.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Items and behaviour; see `ListBox.new`.
--- @return PallidListBox box New list box.
function Widgets.listBox(x, y, w, h, opts)
    return ListBox.new(x, y, w, h, opts)
end

--- Replaces the items and clears the selection.
--- @param items (string|table)[]|nil New items.
--- @param silent boolean|nil True skips `onSelect`.
--- @return PallidListBox self For chaining.
function ListBox:setItems(items, silent)
    local source = type(items) == "table" and items or {}
    self.items = {}
    for i = 1, #source do
        self.items[i] = normaliseOption(source[i])
    end
    self.list:setItemCount(#self.items)
    self.list:setSelected(nil, true)
    if not silent and self.onSelect ~= nil then
        self.onSelect(self, nil, nil)
    end
    return self
end

--- Returns the current item list.
--- @return PallidOption[] items Normalised items.
function ListBox:getItems()
    return self.items
end

--- Replaces one item and refreshes the label cache downstream.
--- @param index integer One-based item index.
--- @param item string|table New item definition.
--- @return PallidListBox self For chaining.
function ListBox:setItem(index, item)
    if index >= 1 and index <= #self.items then
        self.items[index] = normaliseOption(item)
    end
    return self
end

--- Selects a row.
--- @param index integer|nil One-based item index; nil clears the selection.
--- @param silent boolean|nil True skips `onSelect`.
--- @return PallidListBox self For chaining.
function ListBox:setSelected(index, silent)
    self.list:setSelected(index, silent)
    return self
end

--- @return integer|nil index Selected index, or nil.
function ListBox:getSelected()
    return self.list.selected
end

--- @return PallidOption|nil item Selected item, or nil.
function ListBox:getSelectedItem()
    local index = self.list.selected
    return index ~= nil and self.items[index] or nil
end

--- @param index integer One-based item index.
--- @return PallidOption|nil item Item at the index.
function ListBox:getItem(index)
    return self.items[index]
end

--- Scrolls a row into view.
--- @param index integer One-based item index.
--- @return PallidListBox self For chaining.
function ListBox:scrollToItem(index)
    if self.items[index] == nil then
        return self
    end
    local top = self.list:rowOffset(index)
    local bottom = top + self.list:_rowHeightAt(index)
    local scroll = self.list:getScroll()
    if top < scroll then
        self.list:scrollTo(top)
    elseif bottom > scroll + self.list.viewH then
        self.list:scrollTo(bottom - self.list.viewH)
    end
    return self
end

--- @param index integer|nil Selected index.
function ListBox:_notifySelect(index)
    if self.onSelect ~= nil then
        self.onSelect(self, index, index ~= nil and self.items[index] or nil)
    end
end

--- Draws the default row: fill, icon and ellipsised label.
--- @param el ISUIElement Host element.
--- @param index integer One-based item index.
--- @param x number Row left.
--- @param y number Row top.
--- @param w number Row width.
--- @param h number Row height.
--- @param state PallidVirtualRowState Reused row state.
function ListBox:_drawRow(el, index, x, y, w, h, state)
    local item = self.items[index]
    if item == nil then
        return
    end
    if state.selected then
        Pallid.UI.rect(el, x, y, w, h, self:shade(self.rowSelected))
    elseif state.hovered and not item.disabled then
        Pallid.UI.rect(el, x, y, w, h, self:shade(self.rowHover))
    end

    local textX = x + SIDE_PAD
    if item.hasIcon then
        OptionUtil.drawIcon(
            el,
            item,
            textX,
            y + (h - ICON_SIZE) * 0.5,
            ICON_SIZE,
            self:shade(item.disabled and self.disabledColor or self.textColor)
        )
        textX = textX + ICON_SIZE + ICON_GAP
    end

    local label = item.label
    if self.getLabel ~= nil then
        label = self.getLabel(item, index) or label
    end
    local style = self.style
    style.color = self:shade(item.disabled and self.disabledColor or self.textColor)
    style.maxWidth = math.max(0, x + w - textX - SIDE_PAD)
    Pallid.UI.text(el, label, textX, y + h * 0.5, style)
    style.maxWidth = nil
end

--- Keyboard navigation: Up/Down/Home/End move the selection, Enter activates
--- the current row.
--- @param key integer Keyboard.KEY_* value.
--- @return boolean handled True when the list consumed the key.
function ListBox:onKeyPress(key)
    if Keyboard == nil or not self.enabled then
        return false
    end
    local count = #self.items
    if count == 0 then
        return false
    end
    if key == Keyboard.KEY_UP or key == Keyboard.KEY_DOWN then
        if self.list.selectionMode == "none" then
            return true
        end
        local index = self.list.selected or 0
        if index == 0 then
            index = key == Keyboard.KEY_UP and 1 or 1
        elseif key == Keyboard.KEY_UP then
            index = math.max(1, index - 1)
        else
            index = math.min(count, index + 1)
        end
        self.list:setSelected(index)
        self:scrollToItem(index)
        return true
    end
    if key == Keyboard.KEY_HOME or key == Keyboard.KEY_END then
        if self.list.selectionMode == "none" then
            return true
        end
        local index = key == Keyboard.KEY_HOME and 1 or count
        self.list:setSelected(index)
        self:scrollToItem(index)
        return true
    end
    if key == Keyboard.KEY_RETURN or key == Keyboard.KEY_NUMPADENTER then
        local index = self.list.selected
        if index ~= nil and self.onActivate ~= nil then
            self.onActivate(self, index, self.items[index])
        end
        return true
    end
    return false
end

--- Updates the child list bounds and selection geometry.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidListBox self For chaining.
function ListBox:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    ValueField.resizeChild(self, w, h)
    return self
end

--- Enables or disables the list.
--- @param enabled boolean New state.
--- @return PallidListBox self For chaining.
function ListBox:setEnabled(enabled)
    Widgets.Widget.setEnabled(self, enabled)
    self.list:setEnabled(enabled)
    return self
end

--- Paints the list chrome and the empty-state text.
--- @param el ISUIElement Host element the tree is rendered into.
function ListBox:drawSelf(el)
    local x, y = self:originX(), self:originY()
    Pallid.UI.roundedRect(el, x, y, self.w, self.h, self.radius, self:shade(self.background))
    Pallid.UI.roundedBorder(el, x, y, self.w, self.h, self.radius, 1, self:shade(self.borderColor))
    if #self.items == 0 and self.emptyText ~= nil and self.emptyText ~= "" then
        local style = self.style
        style.color = self:shade(Pallid.UI.Color.textMuted)
        style.alignH = "center"
        style.maxWidth = math.max(0, self.w - 16)
        Pallid.UI.text(el, self.emptyText, x + self.w * 0.5, y + self.h * 0.5, style)
        style.alignH = "left"
        style.maxWidth = nil
    end
end

--- Returns the preferred size.
--- @param maxW number|nil Available width.
--- @param maxH number|nil Available height.
--- @return number width Preferred width.
--- @return number height Preferred height.
function ListBox:preferredSize(maxW, maxH)
    local height = maxH or self.h
    return maxW or math.max(160, self.w), height
end
