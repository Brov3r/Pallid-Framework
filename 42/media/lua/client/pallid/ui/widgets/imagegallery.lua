require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/scrollbar"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local RECT_SHAPE = Pallid.UI.Shape.rect()
local BAR = Widgets.DEFAULT_SCROLLBAR_SIZE or 10
local ICON_OPTS = { mode = "fit" }

--- Scrollable image gallery with thumbnail cells, selection and keyboard
--- navigation. Items are plain tables with `source`, optional `caption` and
--- optional `value`; source may be a texture path, a registered icon name or a
--- Texture object.
--- @class PallidImageGallery : PallidWidget
--- @field items table[] Normalised items.
--- @field cellW number Cell width in pixels.
--- @field cellH number Cell height in pixels.
--- @field gap number Gap between cells.
--- @field columns integer Resolved column count.
--- @field selectionMode "single"|"multi"|"none" Selection model.
--- @field onSelect fun(gallery: PallidImageGallery, index: integer, item: table)|nil Selection callback.
--- @field onActivate fun(gallery: PallidImageGallery, index: integer, item: table)|nil Double-click/Enter callback.
--- @field scrollY number Vertical scroll offset.
--- @field maxScroll number Maximum scroll offset.
--- @field barV PallidScrollBar Vertical scrollbar child.
local ImageGallery = Widgets.class("ImageGallery")

--- Creates a new `ImageGallery` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Items and appearance.
--- @field opts.items table[]|nil Initial items.
--- @field opts.cellW number|nil Cell width, defaults to 96.
--- @field opts.cellH number|nil Cell height, defaults to 96.
--- @field opts.gap number|nil Cell gap, defaults to 8.
--- @field opts.padding number|nil Inner inset, defaults to 4.
--- @field opts.columns number|nil Forced column count.
--- @field opts.selectionMode "single"|"multi"|"none"|nil Defaults to "single".
--- @field opts.showCaptions boolean|nil True reserves one caption line per cell.
--- @field opts.background PallidColor|nil Gallery fill.
--- @field opts.border PallidColor|nil Gallery outline.
--- @field opts.radius number|nil Gallery radius, defaults to 4.
--- @field opts.emptyText string|nil Text shown when empty.
--- @field opts.onSelect fun(gallery: PallidImageGallery, index: integer, item: table)|nil Selection callback.
--- @field opts.onActivate fun(gallery: PallidImageGallery, index: integer, item: table)|nil Activation callback.
--- @return PallidImageGallery gallery New image gallery.
function ImageGallery.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, ImageGallery)
    self:init(x, y, w or 0, h or 0)

    self.items = {}
    self.cellW = math.max(32, opts.cellW or 96)
    self.cellH = math.max(32, opts.cellH or 96)
    self.gap = math.max(0, opts.gap or 8)
    self.padding = math.max(0, opts.padding or 4)
    self.forcedColumns = opts.columns
    self.selectionMode = opts.selectionMode or "single"
    if self.selectionMode ~= "single" and self.selectionMode ~= "multi"
        and self.selectionMode ~= "none" then
        self.selectionMode = "single"
    end
    self.showCaptions = opts.showCaptions ~= false
    self.background = opts.background or Pallid.UI.Color.surface
    self.borderColor = opts.border or Pallid.UI.Color.border
    self.radius = opts.radius or 4
    self.emptyText = opts.emptyText
    self.onSelect = opts.onSelect
    self.onActivate = opts.onActivate

    self.cellFill = Pallid.UI.Color.surfaceMuted
    self.cellHover = Pallid.UI.Color.accentSoft
    self.cellSelected = Pallid.UI.Color.primarySoft
    self.captionColor = Pallid.UI.Color.textMuted
    self.captionStyle = {
        font = Pallid.UI.Fonts.small,
        color = self.captionColor,
        alignH = "center",
        alignV = "middle",
        ellipsis = "...",
    }

    self.selected = nil
    self._selected = {}
    self._hoverIndex = 0
    self.columns = 1
    self.scrollY = 0
    self.maxScroll = 0
    self.viewW = self.w
    self.viewH = self.h
    self._contentH = 0
    self._scrollPx = 0
    self.barSize = math.max(1, math.floor(opts.barSize or BAR))
    self.barGap = opts.barGap
    self._lastClickMs = nil
    self._lastClickIndex = 0
    self.acceptsFocus = true

    self.barV = Widgets.scrollBar(true, self.w - self.barSize, 0, self.barSize, self.h, { margin = 1 })
    self.barV.onChange = function(_, value)
        self.scrollY = value * (self.maxScroll or 0)
    end
    self.barV:setOverlay(true)
    self:add(self.barV)

    self:setItems(opts.items)
    return self
end

--- Factory shortcut for `ImageGallery.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Items and appearance; see `ImageGallery.new`.
--- @return PallidImageGallery gallery New image gallery.
function Widgets.imageGallery(x, y, w, h, opts)
    return ImageGallery.new(x, y, w, h, opts)
end

--- @param source string|Texture|nil Image source.
--- @return PallidTextureRegion|nil region Atlas region.
--- @return Texture|nil texture Individual texture.
local function resolveSource(source)
    if source == nil then
        return nil, nil
    end
    if type(source) == "string" then
        if string.find(source, "/", 1, true) ~= nil then
            local region = Pallid.UI.Textures.getRegion(source)
            return region, region == nil and Pallid.UI.Textures.get(source) or nil
        end
        local region = Pallid.UI.Textures.getIconRegion(source)
        if region ~= nil then
            return region, nil
        end
        if Pallid.UI.Textures.hasIcon(source) then
            return nil, Pallid.UI.Textures.getIcon(source)
        end
        return nil, Pallid.UI.Textures.get(source)
    end
    return nil, source
end

--- Replaces the items.
--- @param items table[]|nil New items.
--- @return PallidImageGallery self For chaining.
function ImageGallery:setItems(items)
    self.items = {}
    local source = type(items) == "table" and items or {}
    for i = 1, #source do
        local entry = source[i]
        if type(entry) ~= "table" then
            entry = { source = entry, caption = "" }
        end
        local region, texture = resolveSource(entry.source)
        self.items[i] = {
            source  = entry.source,
            caption = entry.caption or entry.label or "",
            value   = entry.value,
            region  = region,
            texture = texture,
            raw     = entry,
        }
    end
    self.selected = nil
    self._selected = {}
    self._hoverIndex = 0
    self.scrollY = 0
    self:refresh()
    return self
end

--- Returns the items.
--- @return table[] items Normalised items.
function ImageGallery:getItems()
    return self.items
end

--- Recomputes the grid, scroll range and scrollbar.
--- @return PallidImageGallery self For chaining.
function ImageGallery:refresh()
    local contentW = math.max(0, self.w - self.barSize - self:_barGap())
    local columns = self.forcedColumns
    if columns == nil then
        columns = math.max(1, math.floor((contentW + self.gap) / (self.cellW + self.gap)))
    end
    self.columns = math.max(1, columns)
    self.viewW = contentW
    self.viewH = math.max(0, self.h)
    local count = #self.items
    local rows = math.ceil(count / self.columns)
    self._contentH = rows > 0 and (self.padding * 2 + rows * self.cellH + (rows - 1) * self.gap) or 0
    self.maxScroll = math.max(0, self._contentH - self.viewH)
    self.scrollY = math.max(0, math.min(self.maxScroll, self.scrollY))
    self._scrollPx = math.floor(self.scrollY + 0.5)

    self.barV:setEnabled(self.enabled)
    if self._contentH > self.viewH and contentW > 0 then
        local gap = self:_barGap()
        self.barV:setVisible(true)
        self.barV:setBounds(
            self.w - self.barSize - gap,
            gap,
            self.barSize,
            math.max(1, self.h - gap * 2)
        )
        self.barV.page = math.min(1, self.viewH / math.max(1, self._contentH))
        self.barV.value = self.maxScroll > 0 and self.scrollY / self.maxScroll or 0
    else
        self.barV:setVisible(false)
        self.barV.value = 0
        self.barV.page = 1
    end
    return self
end

--- @return number gap Adaptive scrollbar gap.
function ImageGallery:_barGap()
    if self.barGap ~= nil then
        return self.barGap
    end
    return math.min(self.w, self.h) < 80 and 3 or 5
end

--- @param index integer One-based item index.
--- @return number x Cell left in root-local coordinates.
--- @return number y Cell top in root-local coordinates.
function ImageGallery:cellRect(index)
    local column = (index - 1) % self.columns
    local row = math.floor((index - 1) / self.columns)
    return self:originX() + self.padding + column * (self.cellW + self.gap),
        self:originY() + self.padding + row * (self.cellH + self.gap) - self._scrollPx
end

--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return integer index One-based item index, or 0.
function ImageGallery:itemAt(px, py)
    if px < self:originX() or px >= self:originX() + self.viewW
        or py < self:originY() or py >= self:originY() + self.viewH then
        return 0
    end
    local contentX = px - self:originX() + self._scrollPx * 0
    local contentY = py - self:originY() + self._scrollPx
    local localX = contentX - self.padding
    local localY = contentY - self.padding
    if localX < 0 or localY < 0 then
        return 0
    end
    local column = math.floor(localX / (self.cellW + self.gap))
    local row = math.floor(localY / (self.cellH + self.gap))
    if column < 0 or column >= self.columns or row < 0 then
        return 0
    end
    if localX - column * (self.cellW + self.gap) > self.cellW
        or localY - row * (self.cellH + self.gap) > self.cellH then
        return 0
    end
    local index = row * self.columns + column + 1
    return self.items[index] ~= nil and index or 0
end

--- @param index integer One-based item index.
--- @return boolean selected True when selected.
function ImageGallery:isSelected(index)
    if self.selectionMode == "multi" then
        return self._selected[index] == true
    end
    return self.selected == index
end

--- Selects an item.
--- @param index integer|nil Item index; nil clears.
--- @param silent boolean|nil True skips `onSelect`.
--- @return PallidImageGallery self For chaining.
function ImageGallery:setSelected(index, silent)
    if index ~= nil and self.items[index] == nil then
        index = nil
    end
    self.selected = index
    self._selected = {}
    if index ~= nil then
        self._selected[index] = true
    end
    if not silent and self.onSelect ~= nil then
        self.onSelect(self, index, index ~= nil and self.items[index] or nil)
    end
    return self
end

--- @return integer|nil index Selected item index.
function ImageGallery:getSelected()
    return self.selected
end

--- Scrolls to an item.
--- @param index integer One-based item index.
--- @return PallidImageGallery self For chaining.
function ImageGallery:scrollToItem(index)
    if self.items[index] == nil then
        return self
    end
    local row = math.floor((index - 1) / self.columns)
    local top = self.padding + row * (self.cellH + self.gap)
    local bottom = top + self.cellH
    if top < self.scrollY then
        self.scrollY = top
    elseif bottom > self.scrollY + self.viewH then
        self.scrollY = bottom - self.viewH
    end
    self.scrollY = math.max(0, math.min(self.maxScroll, self.scrollY))
    self:refresh()
    return self
end

--- Handles a click on a cell.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when accepted.
function ImageGallery:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end
    local index = self:itemAt(px, py)
    if index == 0 then
        return true
    end
    local additive = self.selectionMode == "multi" and Keyboard ~= nil and Keyboard.isKeyDown ~= nil
        and (Keyboard.isKeyDown(Keyboard.KEY_LCONTROL) or Keyboard.isKeyDown(Keyboard.KEY_RCONTROL))
    if self.selectionMode == "multi" and additive then
        self._selected[index] = not self._selected[index] or nil
        self.selected = self._selected[index] and index or nil
        if self.onSelect ~= nil then
            self.onSelect(self, index, self.items[index])
        end
    else
        self:setSelected(index)
    end

    local now = getTimestampMs ~= nil and getTimestampMs() or 0
    local isDouble = now > 0 and self._lastClickMs ~= nil
        and self._lastClickIndex == index and (now - self._lastClickMs) <= 400
    self._lastClickMs = now
    self._lastClickIndex = isDouble and 0 or index
    if isDouble and self.onActivate ~= nil then
        self.onActivate(self, index, self.items[index])
    end
    return true
end

--- Tracks the hovered cell.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function ImageGallery:onHoverMove(px, py)
    self._hoverIndex = self:itemAt(px, py)
end

--- Clears hover.
function ImageGallery:onHoverEnd()
    self._hoverIndex = 0
    Widgets.Widget.onHoverEnd(self)
end

--- Scrolls the gallery.
--- @param delta number Wheel steps; positive scrolls down.
--- @return boolean handled True when consumed.
function ImageGallery:onWheel(delta)
    if not self.enabled or self.maxScroll <= 0 then
        return false
    end
    self.scrollY = math.max(0, math.min(self.maxScroll, self.scrollY + delta * self.cellH))
    return true
end

--- Keyboard navigation.
--- @param key integer Keyboard.KEY_* value.
--- @return boolean handled True when consumed.
function ImageGallery:onKeyPress(key)
    if Keyboard == nil or #self.items == 0 then
        return false
    end
    local index = self.selected or 1
    if key == Keyboard.KEY_LEFT then
        index = math.max(1, index - 1)
    elseif key == Keyboard.KEY_RIGHT then
        index = math.min(#self.items, index + 1)
    elseif key == Keyboard.KEY_UP then
        index = math.max(1, index - self.columns)
    elseif key == Keyboard.KEY_DOWN then
        index = math.min(#self.items, index + self.columns)
    elseif key == Keyboard.KEY_HOME then
        index = 1
    elseif key == Keyboard.KEY_END then
        index = #self.items
    elseif key == Keyboard.KEY_RETURN or key == Keyboard.KEY_NUMPADENTER then
        if self.onActivate ~= nil then
            self.onActivate(self, index, self.items[index])
        end
        return true
    else
        return false
    end
    self:setSelected(index)
    self:scrollToItem(index)
    return true
end

--- Paints the grid and visible cells.
--- @param el ISUIElement Host element the tree is rendered into.
function ImageGallery:drawSelf(el)
    self:refresh()
    local x, y = self:originX(), self:originY()
    Pallid.UI.roundedRect(el, x, y, self.w, self.h, self.radius, self:shade(self.background))
    Pallid.UI.roundedBorder(el, x, y, self.w, self.h, self.radius, 1, self:shade(self.borderColor))

    if #self.items == 0 then
        if self.emptyText ~= nil and self.emptyText ~= "" then
            local style = self.captionStyle
            style.color = self:shade(Pallid.UI.Color.textMuted)
            style.maxWidth = math.max(0, self.w - 16)
            Pallid.UI.text(el, self.emptyText, x + self.w * 0.5, y + self.h * 0.5, style)
            style.maxWidth = nil
        end
        return
    end

    local entered = Pallid.UI.clip(el, RECT_SHAPE, x, y, self.viewW, self.viewH)
    if not entered then
        return
    end

    local captionH = self.showCaptions and 16 or 0
    local imageH = math.max(1, self.cellH - captionH - 4)
    local stride = self.cellH + self.gap
    local firstRow = math.max(0, math.floor((self._scrollPx - self.padding) / stride))
    local lastRow = math.floor((self._scrollPx + self.viewH - self.padding) / stride)
    if lastRow < firstRow then
        lastRow = firstRow
    end
    local first = firstRow * self.columns + 1
    local last = math.min(#self.items, (lastRow + 1) * self.columns)
    for i = first, last do
        local cellX, cellY = self:cellRect(i)
        if cellY + self.cellH > y and cellY < y + self.viewH then
            local hovered = i == self._hoverIndex
            local selected = self:isSelected(i)
            if selected then
                Pallid.UI.roundedRect(el, cellX, cellY, self.cellW, self.cellH, 4, self:shade(self.cellSelected))
            elseif hovered then
                Pallid.UI.roundedRect(el, cellX, cellY, self.cellW, self.cellH, 4, self:shade(self.cellHover))
            else
                Pallid.UI.roundedRect(el, cellX, cellY, self.cellW, self.cellH, 4, self:shade(self.cellFill))
            end
            Pallid.UI.roundedBorder(el, cellX, cellY, self.cellW, self.cellH, 4, 1, self:shade(self.borderColor))

            local item = self.items[i]
            local imageY = cellY + 2
            local imageW = self.cellW - 4
            if item.region ~= nil then
                Pallid.UI.textureRegion(el, item.region, cellX + 2, imageY, imageW, imageH, nil, ICON_OPTS)
            elseif item.texture ~= nil then
                Pallid.UI.texture(el, item.texture, cellX + 2, imageY, imageW, imageH, nil, ICON_OPTS)
            end

            if self.showCaptions and item.caption ~= "" then
                local style = self.captionStyle
                style.maxWidth = self.cellW - 8
                style.color = self:shade(self.captionColor)
                Pallid.UI.text(el, item.caption, cellX + self.cellW * 0.5,
                    cellY + self.cellH - captionH * 0.5 - 2, style)
                style.maxWidth = nil
            end
        end
    end

    Pallid.UI.clipEnd(el)
end

--- Resizes the gallery.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidImageGallery self For chaining.
function ImageGallery:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:refresh()
    return self
end

--- Enables or disables the gallery.
--- @param enabled boolean New state.
--- @return PallidImageGallery self For chaining.
function ImageGallery:setEnabled(enabled)
    Widgets.Widget.setEnabled(self, enabled)
    self.barV:setEnabled(enabled)
    return self
end
