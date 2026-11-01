require "pallid/ui/internal"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local ReorderableList = Widgets.ReorderableList

--- Called by the embedded drop area when another list's drag enters this body.
--- A sorted target drops its sort so the insertion index and the visible order
--- agree; the previous order is not restored after the transfer.
--- @param data table|nil Drag data from the source list.
--- @param px number Root-local pointer X.
--- @param py number Root-local pointer Y.
function ReorderableList:_externalEnter(data, px, py)
    if data == nil or data.list == self or data.transferred then
        return
    end
    if self.sortKey ~= nil then
        if not self.clearSortOnDrag then
            return
        end
        self.sortKey = nil
        self.sortAsc = true
        self:refreshView()
    end
    self._externalData = data
    self._pointerX, self._pointerY = px, py
    self:_updateInsertion(py)
    data.previewList = self
end

--- Updates the insertion preview while a foreign drag is over this list.
--- @param data table|nil Drag data from the source list.
--- @param px number Root-local pointer X.
--- @param py number Root-local pointer Y.
function ReorderableList:_externalMove(data, px, py)
    if data == nil or data ~= self._externalData then
        return
    end
    self._pointerX, self._pointerY = px, py
    self:_updateInsertion(py)
end

--- Clears the insertion preview when a foreign drag leaves this list.
--- @param data table|nil Drag data from the source list.
function ReorderableList:_externalLeave(data)
    if data ~= nil and data.previewList == self then
        data.previewList = nil
    end
    if data ~= self._externalData then
        return
    end
    self._externalData = nil
    self._dragInsert = -1
    self._pointerInside = false
end

--- Inserts rows dragged from another list at the pointer position.
--- @param data table|nil Drag data from the source list.
--- @param px number Root-local pointer X.
--- @param py number Root-local pointer Y.
--- @return boolean inserted True when the rows were inserted.
function ReorderableList:_insertExternal(data, px, py)
    if data == nil or data.transferred or data.list == self then
        return false
    end
    if data.kind ~= self.dragKind or data.group ~= self.dragGroup then
        return false
    end
    if not self:_isInsideBody(px, py) then
        return false
    end
    if self.sortKey ~= nil then
        if not self.clearSortOnDrag then
            return false
        end
        self.sortKey = nil
        self.sortAsc = true
        self:refreshView()
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

    for i = 1, #data.rows do
        table.insert(self.rows, k + i, data.rows[i])
    end
    data.transferred = true
    data.target = self

    self:_clearSelection()
    for i = 1, #data.rows do
        self.selected[data.rows[i]] = true
    end
    self.selectionAnchor = data.rows[1]
    self._externalData = nil
    self._dragInsert = -1
    self._pointerInside = false
    self:refreshView()
    if self.onChange ~= nil then
        self.onChange(self)
    end
    if self.onReorder ~= nil then
        self.onReorder(self.rows, 0, k + 1)
    end
    if self.onTransferIn ~= nil then
        self.onTransferIn(self, data.rows, k + 1, data.list)
    end
    return true
end

return ReorderableList
