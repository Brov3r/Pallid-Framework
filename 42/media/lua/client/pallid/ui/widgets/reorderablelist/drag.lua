require "pallid/ui/internal"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/dragdrop"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets  = Pallid.UI.Widgets
local DragDrop = Pallid.UI.DragDrop
local I        = Pallid.UI._internal

local ReorderableList = Widgets.ReorderableList

--- Arms a drag from a row or its grip. The row is selected if it was not part
--- of the current selection; a selected row keeps the whole selection so one
--- press moves the block.
--- @param row table Row record.
--- @param index integer One-based view index.
--- @param px number Root-local pointer X.
--- @param py number Root-local pointer Y.
--- @return boolean armed True when the drag handle is armed.
function ReorderableList:_armDrag(row, index, px, py)
    if row == nil or row.disabled == true then
        return false
    end
    if self.selectionMode ~= "none" and not self:isRowSelected(row) then
        self:_clearSelection()
        self:setRowSelected(row, true, true)
        self.selectionAnchor = row
        if self.onChange ~= nil then
            self.onChange(self)
        end
    end
    self._armedRow = row
    self._armedIndex = index
    self._pressX, self._pressY = px, py
    self._pointerX, self._pointerY = px, py
    self._dragStarted = false
    self:focus()
    return true
end

--- @param rows table[] Rows being dragged.
--- @return string label Drag ghost label.
--- @return string|Texture|nil icon Icon value, or nil.
--- @return PallidColor|nil color Color value, or nil.
function ReorderableList:_dragSummary(rows)
    local function textOf(row)
        local value = self.dragLabel ~= nil and self.dragLabel(row) or row[self.labelKey]
        if type(value) == "table" then
            value = value.text or value.label
        end
        return value ~= nil and tostring(value) or ""
    end

    local label = textOf(rows[1])
    if #rows > 1 then
        -- Translation values must not contain format specifiers: PZ's
        -- Translator validates them before Lua can format the string.
        local suffix = I.translate("UI_Pallid_DragMore", "+") .. tostring(#rows - 1)
        label = label ~= "" and (label .. " " .. suffix) or suffix
    end

    local icon = rows[1][self.iconKey]
    if icon == nil and self.dragIcon ~= nil then
        icon = self.dragIcon(rows[1])
    end
    return label, icon, rows[1].color
end

--- @param px number Root-local pointer X.
--- @param py number Root-local pointer Y.
--- @return boolean started True when the drag started.
function ReorderableList:_startDrag(px, py)
    if self.sortKey ~= nil then
        if not self.clearSortOnDrag then
            return false
        end
        -- A manual order is only meaningful while the view is unsorted.
        self.sortKey = nil
        self.sortAsc = true
        self:refreshView()
    end

    local rows = self:_selectedRows()
    if #rows == 0 and self._armedRow ~= nil then
        rows[1] = self._armedRow
    end
    if #rows == 0 then
        return false
    end

    local set = {}
    for i = 1, #rows do
        set[rows[i]] = true
    end

    local data = {
        kind        = self.dragKind,
        group       = self.dragGroup,
        list        = self,
        rows        = rows,
        from        = self:viewIndexOf(rows[1]),
        transferred = false,
    }
    self._dragData = data
    self._dragRows = set
    self._dragInsert = -1
    self._pointerX, self._pointerY = px, py

    local label, icon, color = self:_dragSummary(rows)
    local payload = {
        label    = label,
        icon     = icon,
        color    = color,
        kind     = self.dragKind,
        iconSize = math.max(10, self.rowHeight - 12),
        dragData = data,
        onDragMove = function(mx, my)
            self:_onDragMove(data, mx, my)
        end,
        onDrop = function(mx, my)
            return self:_onDrop(data, mx, my)
        end,
        onCancel = function()
            self:_onCancelDrag(data)
        end,
        onDragEnd = function(dropped)
            self:_onDragEnd(data, dropped)
        end,
    }

    local root = self:getRoot()
    if root == nil or not DragDrop.start(payload, self, root, px, py) then
        self._dragData = nil
        self._dragRows = nil
        return false
    end

    self._dragging = true
    return true
end

--- @param data table Drag data.
--- @param px number Pointer X in local coordinates.
--- @param py number Pointer Y in local coordinates.
function ReorderableList:_onDragMove(data, px, py)
    if data ~= self._dragData then
        return
    end
    self._pointerX, self._pointerY = px, py
    self:_updateInsertion(py)
end

--- @param px number Pointer X in local coordinates.
--- @param py number Pointer Y in local coordinates.
--- @return boolean inside True when the pointer is over the painted body.
function ReorderableList:_isInsideBody(px, py)
    local headerH = self._headerH or self.headerHeight
    local x, y = self:originX(), self:originY()
    return self.visible and self.enabled
        and px >= x and px < x + self.viewW
        and py >= y + headerH and py < y + headerH + self.viewH
        and self:isPointVisible(px, py)
end

--- @param py number Root-local pointer Y.
function ReorderableList:_updateInsertion(py)
    self._pointerInside = self._pointerX ~= nil and self:_isInsideBody(self._pointerX, py)
    if not self._pointerInside then
        self._dragInsert = -1
        return
    end
    local headerH = self._headerH or self.headerHeight
    local y = py - (self:originY() + headerH) + self.scrollY
    local k = math.floor(y / self.rowHeight + 0.5)
    local count = #self.view
    if k < 0 then
        k = 0
    elseif k > count then
        k = count
    end
    self._dragInsert = k
end

--- @param dt number Seconds since the previous frame.
--- @param py number Root-local pointer Y.
function ReorderableList:_autoScroll(dt, py)
    local edge = self.autoScrollEdge
    if edge <= 0 or dt <= 0 then
        return
    end
    local top = self:originY() + (self._headerH or self.headerHeight)
    local bottom = top + self.viewH
    if py < top + edge then
        local strength = math.min(1, (top + edge - py) / edge)
        self.scrollY = math.max(0, self.scrollY - self.autoScrollSpeed * strength * dt)
    elseif py > bottom - edge then
        local strength = math.min(1, (py - (bottom - edge)) / edge)
        self.scrollY = math.min(self.maxScrollY or 0, self.scrollY + self.autoScrollSpeed * strength * dt)
    end
end

--- @param data table Drag data.
--- @param px number Pointer X in local coordinates.
--- @param py number Pointer Y in local coordinates.
--- @return boolean consumed True when the drop was applied inside this list.
function ReorderableList:_onDrop(data, px, py)
    if data ~= self._dragData then
        return false
    end
    if not self:_isInsideBody(px, py) then
        -- Cross-list transfer: the target list detects the hover in its own
        -- onAnimate, so the source can hand the rows over even when the
        -- target's internal drop zone is not reached by the zone hit test.
        local target = data.previewList
        if target ~= nil and target ~= self and target._insertExternal ~= nil
            and target:_insertExternal(data, px, py) then
            return true
        end
        return false
    end
    self:_updateInsertion(py)
    local k = self._dragInsert
    if k < 0 then
        return false
    end

    local set = self._dragRows
    local remainingBefore = 0
    for i = 1, k do
        if not set[self.view[i]] then
            remainingBefore = remainingBefore + 1
        end
    end

    local rest = {}
    local rows = self.rows
    for i = 1, #rows do
        if not set[rows[i]] then
            rest[#rest + 1] = rows[i]
        end
    end

    local out = {}
    for i = 1, remainingBefore do
        out[#out + 1] = rest[i]
    end
    for i = 1, #data.rows do
        out[#out + 1] = data.rows[i]
    end
    for i = remainingBefore + 1, #rest do
        out[#out + 1] = rest[i]
    end
    local changed = false
    for i = 1, #out do
        if out[i] ~= rows[i] then
            changed = true
            break
        end
    end
    self:_replaceRows(out)

    self:_clearSelection()
    for i = 1, #data.rows do
        self.selected[data.rows[i]] = true
    end
    self.selectionAnchor = data.rows[1]

    self._dragInsert = -1
    self._pointerInside = false
    self:refreshView()
    if self.onChange ~= nil then
        self.onChange(self)
    end
    if changed and self.onReorder ~= nil then
        self.onReorder(self.rows, data.from, remainingBefore + 1)
    end
    return true
end

--- @param data table Drag data.
function ReorderableList:_onCancelDrag(data)
    if data ~= self._dragData then
        return
    end
    self._dragInsert = -1
    self._pointerInside = false
end

--- @param data table Drag data.
--- @param dropped boolean True when the drag was dropped.
function ReorderableList:_onDragEnd(data, dropped) -- luacheck: ignore
    if data ~= self._dragData then
        return
    end
    if data.transferred then
        -- The target already stored the rows; remove them from this list by
        -- identity, not by index, so a concurrent reorder could not shift them.
        local set = {}
        for i = 1, #data.rows do
            set[data.rows[i]] = true
        end
        local out = {}
        local rows = self.rows
        for i = 1, #rows do
            if not set[rows[i]] then
                out[#out + 1] = rows[i]
            end
        end
        self:_replaceRows(out)
        self:_clearSelection()
        self:refreshView()
        if self.onChange ~= nil then
            self.onChange(self)
        end
        if self.onTransferOut ~= nil then
            self.onTransferOut(self, data.rows, data.target)
        end
    end

    self._dragging = false
    self._dragStarted = false
    self._armedRow = nil
    self._armedIndex = 0
    self._armedCollapse = false
    self._dragData = nil
    self._dragRows = nil
    self._dragInsert = -1
    self._pointerInside = false
    self._pointerX, self._pointerY = nil, nil
    data.previewList = nil
end

return ReorderableList
