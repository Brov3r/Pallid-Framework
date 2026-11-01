require "pallid/ui/internal"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/dragdrop"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets  = Pallid.UI.Widgets
local DragDrop = Pallid.UI.DragDrop

local ReorderableList = Widgets.ReorderableList

--- True while either Control key is held.
--- @return boolean down True when Control is held.
local function ctrlDown()
    return Keyboard ~= nil and Keyboard.isKeyDown ~= nil
        and (Keyboard.isKeyDown(Keyboard.KEY_LCONTROL) or Keyboard.isKeyDown(Keyboard.KEY_RCONTROL))
end

--- True while either Shift key is held.
--- @return boolean down True when Shift is held.
local function shiftDown()
    return Keyboard ~= nil and Keyboard.isKeyDown ~= nil
        and (Keyboard.isKeyDown(Keyboard.KEY_LSHIFT) or Keyboard.isKeyDown(Keyboard.KEY_RSHIFT))
end

--- Handles a press on a row body or its grip. A plain press keeps an existing
--- multi-selection so the whole block can be dragged; it collapses to one row
--- on release when the pointer did not move. Ctrl and Shift defer to the
--- table's selection rules and arm a drag only when the pressed row ends up
--- selected.
--- @param row table Row record.
--- @param index integer One-based view index.
--- @param px number Root-local pointer X.
--- @param py number Root-local pointer Y.
--- @param fromLead boolean True when the press is in the grip gutter.
function ReorderableList:_pressRow(row, index, px, py, fromLead)
    local ctrl = ctrlDown()
    local shift = shiftDown()
    self._armedCollapse = false

    if self.selectionMode == "none" then
        -- Rows are still draggable, but there is no selection to update.
        self._armedCollapse = false
    elseif (shift or ctrl) and not self.dragSelect then
        Widgets.Table.onDown(self, px, py, "left")
    elseif not self:isRowSelected(row) then
        self:_clearSelection()
        self:setRowSelected(row, true, true)
        self.selectionAnchor = row
        if self.onChange ~= nil then
            self.onChange(self)
        end
    elseif not fromLead then
        local selectedCount = 0
        for _ in pairs(self.selected) do
            selectedCount = selectedCount + 1
        end
        -- A click on one row of a multi selection collapses it on release; the
        -- block stays selected while the pointer is down so it can be dragged.
        self._armedCollapse = selectedCount > 1
    end

    if self.selectionMode == "none" or self:isRowSelected(row) then
        self:_armDrag(row, index, px, py)
    end
end

--- Handles a pointer press inside the widget.
--- @param px number Root-local pointer X.
--- @param py number Root-local pointer Y.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the event was handled.
function ReorderableList:onDown(px, py, button)
    if not self.enabled then
        return false
    end
    if DragDrop.isActive(self) then
        -- A non-left press while dragging cancels the session instead of
        -- opening a context menu under the ghost.
        if button ~= nil and button ~= "left" then
            DragDrop.cancel()
        end
        return true
    end
    self:syncBars()
    local localY = py - self:originY()
    local headerH = self._headerH or self.headerHeight

    if localY >= headerH and button ~= "right" then
        local index = self:rowAt(py)
        local row = index > 0 and self.view[index] or nil
        if row ~= nil then
            if row.disabled == true then
                return true
            end
            local contentX = px - self:originX() + self.scrollX
            local fromLead = contentX >= 0 and contentX < (self.leadWidth or 0)
            -- With dragSelect enabled the body keeps its range-selection gesture
            -- and only the grip starts a row drag; otherwise the whole row is a
            -- drag surface.
            if fromLead or not self.dragSelect then
                self:_pressRow(row, index, px, py, fromLead)
                return true
            end
        end
    end
    return Widgets.Table.onDown(self, px, py, button)
end

--- Handles pointer movement.
--- @param px number Root-local pointer X.
--- @param py number Root-local pointer Y.
function ReorderableList:onMove(px, py)
    if self._armedRow == nil then
        Widgets.Table.onMove(self, px, py)
        return
    end

    self._pointerX, self._pointerY = px, py
    if not self._dragStarted then
        local dx, dy = px - self._pressX, py - self._pressY
        if dx * dx + dy * dy < self.dragThreshold * self.dragThreshold then
            return
        end
        if not self:_startDrag(px, py) then
            self._armedRow = nil
            return
        end
        self._dragStarted = true
        return
    end
    DragDrop.move(px, py)
end

--- Handles a pointer release.
--- @param px number Root-local pointer X.
--- @param py number Root-local pointer Y.
function ReorderableList:onUp(px, py)
    local wasStarted = self._dragStarted
    if DragDrop.isActive(self) then
        DragDrop.drop(px, py)
    end

    -- A plain click on one row of a multi selection collapses it only if the
    -- pointer never crossed the threshold; a real drag keeps the block.
    if not wasStarted and not DragDrop.isActive(self)
        and self._armedRow ~= nil and self._armedCollapse then
        local row = self._armedRow
        self:_clearSelection()
        self:setRowSelected(row, true, true)
        self.selectionAnchor = row
        if self.onChange ~= nil then
            self.onChange(self)
        end
    end

    self._armedRow = nil
    self._armedIndex = 0
    self._dragStarted = false
    self._armedCollapse = false
    -- Focus is only held for Esc while a drag is possible; after release it
    -- must go back to the game so hotkeys are not swallowed by the table.
    if not DragDrop.isActive(self) then
        self:blur()
    end
    Widgets.Table.onUp(self, px, py)
end

--- Focus is accepted only while armed or dragging. A plain selection click
--- must not leave the table owning the keyboard.
function ReorderableList:focus()
    if self._armedRow ~= nil or self._dragging then
        Widgets.Widget.focus(self)
    end
end

--- DragDrop notifies the source after the session is fully cleaned up, when
--- `isActive` is already false, so `onBlur` cannot re-enter the cancel path.
--- @param dropped boolean True when the payload was dropped.
--- @param payload table Payload that was dragged.
function ReorderableList:_onDragFinished(dropped, payload) -- luacheck: ignore
    self:releaseCapture()
    self:blur()
end

--- Esc cancels an armed or active drag because the list owns the focus.
--- @param key integer Keyboard.KEY_* value.
--- @return boolean handled True when the event was handled.
function ReorderableList:onKeyPress(key)
    if Keyboard == nil or key ~= Keyboard.KEY_ESCAPE then
        return false
    end
    if DragDrop.isActive(self) then
        DragDrop.cancel()
        return true
    end
    if self._armedRow ~= nil then
        self._armedRow = nil
        self._dragStarted = false
        self._armedCollapse = false
        self:blur()
        return true
    end
    return false
end

--- Losing focus (tab switch, modal) must not leave a ghost behind.
function ReorderableList:onBlur()
    if DragDrop.isActive(self) then
        DragDrop.cancel()
    end
    self._armedRow = nil
    self._dragStarted = false
    self._armedCollapse = false
end

--- Cancels a drag whose release was lost outside the window.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous tick.
function ReorderableList:onUpdate(now, dt) -- luacheck: ignore
    if not DragDrop.isActive(self) and self._armedRow == nil then
        return
    end
    if Mouse == nil or Mouse.isButtonDown == nil then
        return
    end
    -- Button 0 is the left mouse button (zombie.input.Mouse).
    if not Mouse.isButtonDown(0) then
        if DragDrop.isActive(self) then
            DragDrop.cancel()
        end
        self._armedRow = nil
        self._dragStarted = false
        self._armedCollapse = false
        if not DragDrop.isActive(self) then
            self:blur()
        end
    end
end

--- Auto-scroll and insertion tracking run per rendered frame, not on the game
--- tick, so dragged rows and the indicator move smoothly. This also derives the
--- external preview directly from the active drag, so a target list does not
--- depend on the internal drop zone being reached by the zone hit test.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous frame.
function ReorderableList:onAnimate(now, dt) -- luacheck: ignore
    self:_trackExternalPreview()
    if self._dragInsert < 0 or self._pointerY == nil or not self._pointerInside then
        return
    end
    self:_autoScroll(dt, self._pointerY)
    self:_updateInsertion(self._pointerY)
end

--- Keeps the target preview (insertion line) in sync with the active drag.
--- Runs for every visible list; the source ignores itself.
function ReorderableList:_trackExternalPreview()
    local active = DragDrop.active
    if active == nil or active.root ~= self:getRoot() then
        if self._externalData ~= nil then
            self:_externalLeave(self._externalData)
        end
        return
    end
    local data = active.payload and active.payload.dragData or nil

    if data == nil or data.list == self or data.transferred
        or data.kind ~= self.dragKind or data.group ~= self.dragGroup then
        if data ~= nil and data.previewList == self then
            data.previewList = nil
        end
        if self._externalData ~= nil then
            self:_externalLeave(self._externalData)
        end
        return
    end

    if not self:_isInsideBody(active.px, active.py) then
        if data.previewList == self then
            data.previewList = nil
        end
        if self._externalData == data then
            self._externalData = nil
            self._dragInsert = -1
            self._pointerInside = false
        end
        return
    end

    if self._externalData ~= data then
        self:_externalEnter(data, active.px, active.py)
    else
        self._pointerX, self._pointerY = active.px, active.py
        self:_updateInsertion(active.py)
    end
    data.previewList = self
end

return ReorderableList
