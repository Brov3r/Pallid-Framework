require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/clip"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/table"
require "pallid/ui/widgets/dragdrop"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets   = Pallid.UI.Widgets
local Color     = Pallid.UI.Color
local DragDrop  = Pallid.UI.DragDrop

local RECT_SHAPE   = Pallid.UI.Shape.rect()
local ICON_GRIP    = "media/assets/ui/pallid/icons/menu-07.png"
local GRIP_OPTS    = { mode = "fit" }
local DEFAULT_LEAD = 22

--- Table-based list whose rows can be reordered by dragging the grip gutter.
---
--- Reusing `PallidTable` keeps columns, header sorting, column resizing,
--- selection and both scrollbars; this class only adds the lead gutter, the
--- drag session, the insertion indicator and list-to-list transfers.
---
--- Rows are ordinary table rows and must be unique objects (selection and the
--- drag payload use identity, exactly like `PallidTable`). Duplicate *values*
--- are fine, duplicate references are not.
---
--- Without `dragSelect` the whole row is a drag surface: a press keeps an
--- existing multi-selection so the block can be dragged and collapses it on
--- release when the pointer did not move. With `dragSelect` the body keeps the
--- table's range-selection gesture and only the grip gutter starts a drag.
---
--- `onReorder(list, rows, from, to)` reports 1-based block positions; an
--- external insert into this list reports `from = 0`.
--- @class PallidReorderableList : PallidTable
--- @field dragKind string Payload kind; defaults to "reorder".
--- @field dragGroup string Lists exchange rows only within the same group.
--- @field clearSortOnDrag boolean Clear the active sort when a drag starts.
--- @field handleTexture Texture|nil Resolved grip texture.
--- @field handleName string|nil Registered grip icon name.
--- @field insertionColor PallidColor Insertion line colour.
--- @field dragRowFill PallidColor Overlay over the rows currently being dragged.
--- @field onReorder fun(list: PallidReorderableList, rows: table[], from: integer, to: integer)|nil Called after rows move; `from` 0 means an external insert.
--- @field onTransferIn fun(list: PallidReorderableList, rows: table[], index: integer, source: PallidReorderableList|nil)|nil Called when rows arrive from another list.
--- @field onTransferOut fun(list: PallidReorderableList, rows: table[], target: PallidReorderableList|nil)|nil Called when this list's rows are dropped elsewhere.
local ReorderableList = Widgets.class("ReorderableList", Widgets.Table)

--- Creates a new `ReorderableList` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param columns PallidTableColumn[] Column descriptors.
--- @param rows table[] Row records; must be unique tables.
--- @param opts table|nil Table options plus the list-specific fields below.
--- @field opts.leadWidth number|nil Grip gutter width; defaults to 22.
--- @field opts.handleIcon string|false|nil Grip icon; defaults to menu-07.png.
--- @field opts.handleSize number|nil Grip icon box; defaults to 14.
--- @field opts.handleColor PallidColor|nil Idle grip tint.
--- @field opts.handleHoverColor PallidColor|nil Hovered grip tint.
--- @field opts.dragKind string|nil Payload kind; defaults to "reorder".
--- @field opts.dragGroup string|nil Exchange group; defaults to "default".
--- @field opts.dragLabel fun(row: table): string|nil Ghost label resolver.
--- @field opts.labelKey string|nil Row key used for the ghost label; defaults to "name".
--- @field opts.iconKey string|nil Row key used for the ghost icon; defaults to "icon".
--- @field opts.dragIcon fun(row: table): string|Texture|nil Ghost icon resolver.
--- @field opts.dragThreshold number|nil Drag threshold in pixels; defaults to 4.
--- @field opts.clearSortOnDrag boolean|nil Defaults to true.
--- @field opts.autoScrollEdge number|nil Edge zone in pixels; defaults to 24.
--- @field opts.autoScrollSpeed number|nil Pixels per second; defaults to 420.
--- @field opts.insertionColor PallidColor|nil Defaults to Color.accent.
--- @field opts.onReorder fun(list: PallidReorderableList, rows: table[], from: integer, to: integer)|nil Called after rows move; `from` 0 means an external insert.
--- @field opts.onTransferIn fun(list: PallidReorderableList, rows: table[], index: integer, source: PallidReorderableList|nil)|nil Called when rows arrive from another list.
--- @field opts.onTransferOut fun(list: PallidReorderableList, rows: table[], target: PallidReorderableList|nil)|nil Called when this list's rows are dropped elsewhere.
--- @return PallidReorderableList New reorderable list.
function ReorderableList.new(x, y, w, h, columns, rows, opts)
    opts = opts or {}

    -- Copy the options before applying defaults: the caller keeps its table and
    -- the table constructor reads the effective values in one place.
    local o = {}
    for key, value in pairs(opts) do
        o[key] = value
    end
    if o.leadWidth == nil then
        o.leadWidth = DEFAULT_LEAD
    end
    if o.selectionMode == nil then
        o.selectionMode = "multi"
    end
    if o.rowHeight == nil then
        o.rowHeight = 28
    end
    if o.headerHeight == nil then
        o.headerHeight = 26
    end

    local self = setmetatable(Widgets.Table.new(x, y, w, h, columns, rows, o), ReorderableList)

    self.dragKind        = o.dragKind or "reorder"
    self.dragGroup       = o.dragGroup or "default"
    self.dragLabel       = o.dragLabel
    self.labelKey        = o.labelKey or "name"
    self.iconKey         = o.iconKey or "icon"
    self.dragIcon        = o.dragIcon
    self.clearSortOnDrag = o.clearSortOnDrag ~= false
    self.dragThreshold   = math.max(1, o.dragThreshold or 4)
    self.autoScrollEdge  = math.max(0, o.autoScrollEdge or 24)
    self.autoScrollSpeed = math.max(0, o.autoScrollSpeed or 420)
    self.insertionColor  = o.insertionColor or Color.accent
    self.dragRowFill     = Color.withAlpha(self.insertionColor, 0.14)
    self.handleSize      = math.max(6, o.handleSize or 14)
    self.handleColor     = o.handleColor or Color.textMuted
    self.handleHoverColor = o.handleHoverColor or Color.primaryStrong
    self.handleDisabledColor = Color.textDisabled
    local handleIcon = o.handleIcon
    if handleIcon == nil then
        handleIcon = ICON_GRIP
    end
    self.handleTexture, self.handleName = Pallid.UI.Textures.resolve(handleIcon)
    self.onReorder       = o.onReorder
    self.onTransferIn    = o.onTransferIn
    self.onTransferOut   = o.onTransferOut

    self._armedRow     = nil
    self._armedIndex   = 0
    self._armedCollapse = false
    self._pressX       = 0
    self._pressY       = 0
    self._pointerX     = nil
    self._pointerY     = nil
    self._pointerInside = false
    self._dragStarted  = false
    self._dragging     = false
    self._dragData     = nil
    self._dragRows     = nil
    self._dragInsert   = -1
    self._externalData = nil

    self.acceptsFocus  = true

    -- A silent zone covers the body and lets other lists drop rows here. It is
    -- never painted and never takes part in hover/click routing; only DragDrop
    -- queries it.
    self._dropArea = Widgets.dropZone(0, 0, 1, 1, {
        silent = true,
        hittable = false,
        accepts = function(payload)
            local data = payload ~= nil and payload.dragData or nil
            return data ~= nil
                and data.list ~= self
                and data.kind == self.dragKind
                and data.group == self.dragGroup
                and not data.transferred
                and self.enabled
                and (self.sortKey == nil or self.clearSortOnDrag)
        end,
        onDragEnter = function(payload, source, px, py)
            self:_externalEnter(payload ~= nil and payload.dragData or nil, px, py)
        end,
        onDragMove = function(payload, source, px, py)
            self:_externalMove(payload ~= nil and payload.dragData or nil, px, py)
        end,
        onDragLeave = function(payload)
            self:_externalLeave(payload ~= nil and payload.dragData or nil)
        end,
        onDrop = function(payload, source, px, py)
            self:_insertExternal(payload ~= nil and payload.dragData or nil, px, py)
        end,
    })
    self:add(self._dropArea)
    self:syncBars()
    return self
end

--- Factory shortcut for `ReorderableList.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param columns PallidTableColumn[] Column descriptors.
--- @param rows table[] Row records; must be unique tables.
--- @param opts table|nil Options; see `ReorderableList.new`.
--- @return PallidReorderableList New reorderable list.
function Widgets.reorderableList(x, y, w, h, columns, rows, opts)
    return ReorderableList.new(x, y, w, h, columns, rows, opts)
end

--- Keeps the silent drop area aligned with the viewport after every layout.
function ReorderableList:syncBars()
    Widgets.Table.syncBars(self)
    local area = self._dropArea
    if area ~= nil then
        area:setBounds(0, math.min(self.headerHeight, self.h), self.viewW, self.viewH)
        -- The zone is never drawn or hit-tested by the table traversal, so its
        -- cached origin must be refreshed here; otherwise zoneAt compares the
        -- viewport rect against root coordinates and never finds it.
        area._ox = self:originX()
        area._oy = self:originY()
    end
end

--- Replaces the list rows.
--- @param rows table[]|nil New rows.
--- @return PallidReorderableList self The same instance, for chaining.
function ReorderableList:setRows(rows)
    if DragDrop.isActive(self) then
        DragDrop.cancel()
    end
    self._armedRow = nil
    self._dragStarted = false
    self._armedCollapse = false
    self._dragging = false
    self._dragData = nil
    self._dragRows = nil
    self._dragInsert = -1
    self._externalData = nil
    self._pointerInside = false
    self._pointerX, self._pointerY = nil, nil
    Widgets.Table.setRows(self, rows)
    return self
end

--- Appends one row.
--- @param row table Row record.
--- @return PallidReorderableList self The same instance, for chaining.
function ReorderableList:addRow(row)
    if type(row) ~= "table" then
        return self
    end
    if DragDrop.isActive(self) then
        DragDrop.cancel()
    end
    self.rows[#self.rows + 1] = row
    self:refreshView()
    return self
end

--- Removes a row by identity or by 1-based index.
--- @param rowOrIndex table|integer Row table or its index.
--- @return table|nil removed Removed row, or nil.
function ReorderableList:removeRow(rowOrIndex)
    if DragDrop.isActive(self) then
        DragDrop.cancel()
    end
    local index
    if type(rowOrIndex) == "number" then
        index = math.floor(rowOrIndex)
    else
        for i = 1, #self.rows do
            if self.rows[i] == rowOrIndex then
                index = i
                break
            end
        end
    end
    if index == nil or index < 1 or index > #self.rows then
        return nil
    end
    local removed = table.remove(self.rows, index)
    self.selected[removed] = nil
    self:refreshView()
    return removed
end

--- Moves a row programmatically.
--- @param from integer 1-based source index.
--- @param to integer 1-based destination index.
--- @return PallidReorderableList self The same instance, for chaining.
function ReorderableList:moveRow(from, to)
    from = math.floor(from or 0)
    to = math.floor(to or 0)
    local count = #self.rows
    if from < 1 or from > count or to < 1 or to > count or from == to then
        return self
    end
    if DragDrop.isActive(self) then
        DragDrop.cancel()
    end
    local row = table.remove(self.rows, from)
    table.insert(self.rows, to, row)
    self:refreshView()
    if self.onReorder ~= nil then
        self.onReorder(self.rows, from, to)
    end
    return self
end

--- Scrolls the minimum amount needed to show a row. Index is 1-based.
--- @param index integer Item index.
--- @return PallidReorderableList self The same instance, for chaining.
function ReorderableList:scrollToRow(index)
    self:syncBars()
    index = math.floor(index or 0)
    if index < 1 or index > #self.view then
        return self
    end
    local top = (index - 1) * self.rowHeight
    if top < self.scrollY then
        self.scrollY = top
    elseif top + self.rowHeight > self.scrollY + self.viewH then
        self.scrollY = top + self.rowHeight - self.viewH
    end
    self.scrollY = math.max(0, math.min(self.maxScrollY, self.scrollY))
    return self
end

--- Returns the view index of a row.
--- @param row table Row table.
--- @return integer index 1-based index in `view`, or 0 when absent.
function ReorderableList:viewIndexOf(row)
    local view = self.view
    for i = 1, #view do
        if view[i] == row then
            return i
        end
    end
    return 0
end

--- Replaces the contents of `self.rows` in place so callers keep their array.
--- @param out table[] Destination row list.
function ReorderableList:_replaceRows(out)
    local rows = self.rows
    for i = #rows, 1, -1 do
        rows[i] = nil
    end
    for i = 1, #out do
        rows[i] = out[i]
    end
end

--- Collects the selected, enabled rows in view order.
--- @return table[] rows Selected rows in view order.
function ReorderableList:_selectedRows()
    local result = {}
    local view = self.view
    for i = 1, #view do
        local row = view[i]
        if self.selected[row] and row.disabled ~= true then
            result[#result + 1] = row
        end
    end
    return result
end

--- Disabled rows are data, not draggable or selectable entries.
--- @param row table Row record.
--- @return boolean selectable True when the item can be selected.
function ReorderableList:canSelectRow(row)
    return row ~= nil and row.disabled ~= true
end

--- Paints the grip gutter row. Called by Table inside the body clip.
--- @param el ISUIElement Host element.
--- @param rowY number Absolute row top.
--- @param rowHeight number Row height.
--- @param index integer One-based view index.
--- @param row table Row record.
function ReorderableList:drawRowLead(el, rowY, rowHeight, index, row)
    local lead = self.leadWidth or 0
    if lead <= 0 then
        return
    end
    local x = self:originX() - self.scrollX
    local hover = self.hoverRow == index and self.hoverX ~= nil
    if hover then
        local px = self.hoverX - x
        if px >= 0 and px < lead then
            local hoverFill = self.selected[row] and self.rowSelected or self.rowHover
            Pallid.UI.rect(el, x, rowY, lead, rowHeight, self:shade(hoverFill))
        end
    end

    local size = math.min(self.handleSize, math.max(1, rowHeight - 6), math.max(1, lead - 6))
    if size <= 0 then
        return
    end

    local dimmed = row.disabled == true
        or (self._dragRows ~= nil and self._dragRows[row] == true)
    local color = dimmed and self.handleDisabledColor or self.handleColor
    if hover and not dimmed then
        color = self.handleHoverColor
    end

    local ix = x + (lead - size) * 0.5
    local iy = rowY + (rowHeight - size) * 0.5
    if self.handleTexture ~= nil then
        Pallid.UI.texture(el, self.handleTexture, ix, iy, size, size, self:shade(color), GRIP_OPTS)
    elseif self.handleName ~= nil then
        Pallid.UI.icon(el, self.handleName, ix, iy, size, self:shade(color))
    end
end

--- Draws the table and then the drag overlay (dimmed rows and insertion line).
--- @param el ISUIElement Host element.
function ReorderableList:drawSelf(el)
    -- Keep the external preview fresh even if a host renders without running
    -- updateAnimations; the source list ignores this path.
    self:_trackExternalPreview()
    Widgets.Table.drawSelf(self, el)
    self:_drawDragOverlay(el)
end

--- Draws the dim fill over dragged rows and the insertion line.
--- @param el ISUIElement Host element.
function ReorderableList:_drawDragOverlay(el)
    local hasDim = self._dragging and self._dragRows ~= nil
    local showLine = self._dragInsert >= 0 and self._pointerInside
    if not hasDim and not showLine then
        return
    end

    local x, y = self:originX(), self:originY()
    local headerH = self._headerH or self.headerHeight
    local bodyY = y + headerH
    local viewH = self.viewH
    if self.viewW <= 0 or viewH <= 0 then
        return
    end
    local entered = Pallid.UI.clip(el, RECT_SHAPE, x, bodyY, self.viewW, viewH)
    if not entered then
        return
    end

    if hasDim then
        local rowH = self.rowHeight
        local view = self.view
        for i = 1, #view do
            if self._dragRows[view[i]] then
                local rowY = bodyY + (i - 1) * rowH - self.scrollY
                local top = math.max(rowY, bodyY)
                local bottom = math.min(rowY + rowH, bodyY + viewH)
                if bottom > top then
                    Pallid.UI.rect(el, x, top, self.viewW, bottom - top, self.dragRowFill)
                end
            end
        end
    end

    if showLine then
        local lineY = bodyY + self._dragInsert * self.rowHeight - self.scrollY
        if lineY >= bodyY - 1 and lineY <= bodyY + viewH then
            Pallid.UI.rect(el, x, lineY - 1, self.viewW, 2, self.insertionColor)
        end
    end

    Pallid.UI.clipEnd(el)
end

-- Drag, insertion and cross-list transfer live in separate mixins so this file
-- stays focused on the table contract and drawing.
require "pallid/ui/widgets/reorderablelist/transfer"
require "pallid/ui/widgets/reorderablelist/drag"
require "pallid/ui/widgets/reorderablelist/input"

return ReorderableList
