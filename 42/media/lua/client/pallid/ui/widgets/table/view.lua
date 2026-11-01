require "pallid/ui/internal"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

--- Adds row sorting and selection methods to the Table class. Kept in a mixin
--- so the main widget file stays focused on layout, input and clipping.
--- @param Table table PallidTable class.
--- @return fun Augmenter that installs the methods.
return function(Table)
    --- Kahlua in PZ does not expose the global `next`; `pairs` is implemented
    --- directly and remains available. Never call `next` from mod code.
    --- @param t table|nil Table to inspect.
    --- @return boolean hasEntries True when the table contains at least one key.
    local function hasEntries(t)
        if t == nil then
            return false
        end
        for _ in pairs(t) do
            return true
        end
        return false
    end

    --- Rebuilds `view` from `rows` and applies the current sort. Mixed types are
    --- ordered by type first (numbers, strings, booleans, other); nil is always
    --- placed after real values. Ties keep the original row order.
    function Table:refreshView()
        local view = self.view
        for i = #view, 1, -1 do
            view[i] = nil
        end
        for i = 1, #self.rows do
            view[i] = self.rows[i]
        end

        local key = self.sortKey
        local count = #view
        if key ~= nil and count > 1 then
            local ascending = self.sortAsc

            local function rank(value)
                local kind = type(value)
                if kind == "number" then
                    return 1
                elseif kind == "string" then
                    return 2
                elseif kind == "boolean" then
                    return 3
                end
                return 4
            end

            --- Compares two cell values. Returns -1 when `left` sorts first,
            --- 1 when `right` sorts first and 0 when they are equal. Empty
            --- cells always stay at the end; the type order is fixed, only the
            --- value order flips with `ascending`.
            --- @param left any First value.
            --- @param right any Second value.
            --- @return integer order Sort order.
            local function compareValues(left, right)
                if left == nil and right == nil then
                    return 0
                end
                if left == nil then
                    return 1
                end
                if right == nil then
                    return -1
                end

                local lr, rr = rank(left), rank(right)
                if lr ~= rr then
                    return lr < rr and -1 or 1
                end

                if lr == 1 or lr == 2 then
                    if left == right then
                        return 0
                    end
                    if ascending then
                        if left < right then
                            return -1
                        elseif left > right then
                            return 1
                        end
                    else
                        if left > right then
                            return -1
                        elseif left < right then
                            return 1
                        end
                    end
                    return 0
                elseif lr == 3 then
                    local lb = left and 1 or 0
                    local rb = right and 1 or 0
                    if lb == rb then
                        return 0
                    end
                    if ascending then
                        return lb < rb and -1 or 1
                    end
                    return lb > rb and -1 or 1
                end

                local ls, rs = tostring(left), tostring(right)
                if ls == rs then
                    return 0
                end
                if ascending then
                    return ls < rs and -1 or 1
                end
                return ls > rs and -1 or 1
            end

            -- Kahlua's table.sort recurses and can overflow the Lua stack on
            -- large tables. A bottom-up merge sort is iterative, stable and
            -- keeps the `view` table identity.
            local buffer = {}
            local width = 1
            while width < count do
                local start = 1
                while start <= count do
                    local mid = math.min(start + width - 1, count)
                    local last = math.min(start + width * 2 - 1, count)
                    local left, right, out = start, mid + 1, start

                    while left <= mid and right <= last do
                        if compareValues(view[right][key], view[left][key]) < 0 then
                            buffer[out] = view[right]
                            right = right + 1
                        else
                            buffer[out] = view[left]
                            left = left + 1
                        end
                        out = out + 1
                    end
                    while left <= mid do
                        buffer[out] = view[left]
                        left = left + 1
                        out = out + 1
                    end
                    while right <= last do
                        buffer[out] = view[right]
                        right = right + 1
                        out = out + 1
                    end

                    start = start + width * 2
                end
                for i = 1, count do
                    view[i] = buffer[i]
                end
                width = width * 2
            end
        end

        -- Data or order changed under the cursor: drop transient interaction state.
        self.hoverRow = 0
        self.hoverColumn = 0
        self.hoverEdge = false
        self.dragSelecting = false
        self.dragStartRow = nil
        self.dragCurrentRow = nil
        self.resizing = nil
        self:syncBars()
    end

    --- Removes every selected row without replacing the `selected` table, so
    --- callers holding a reference keep seeing the live selection.
    function Table:_clearSelection()
        local selected = self.selected
        for row in pairs(selected) do
            selected[row] = nil
        end
        self.selectionAnchor = nil
    end

    --- Replaces the data rows and clears selection and scroll.
    --- @param rows table[]|nil New rows; nil or a non-table clears the table.
    --- @return PallidTable self For chaining.
    function Table:setRows(rows)
        self.rows = type(rows) == "table" and rows or {}
        self:_clearSelection()
        self._cellTextCaches = {}
        self._cellTextCacheRows = 0
        self.scrollY = 0
        self.scrollX = 0
        self:refreshView()
        return self
    end

    --- Sorts by a column key. The same key toggles the direction; nil clears it.
    --- @param key string|nil Column key to sort by; nil clears the sort.
    --- @return PallidTable self For chaining.
    function Table:setSort(key)
        if key == nil then
            return self:clearSort()
        end
        if self.sortKey == key then
            self.sortAsc = not self.sortAsc
        else
            self.sortKey = key
            self.sortAsc = true
        end
        self.scrollY = 0
        self:refreshView()
        if self.onSort ~= nil then
            self.onSort(self, self.sortKey, self.sortAsc)
        end
        return self
    end

    --- Removes the current sort and restores the source row order.
    --- @return PallidTable self For chaining.
    function Table:clearSort()
        if self.sortKey == nil then
            return self
        end
        self.sortKey = nil
        self.sortAsc = true
        self.scrollY = 0
        self:refreshView()
        if self.onSort ~= nil then
            self.onSort(self, nil, true)
        end
        return self
    end

    --- Returns the sort key.
    --- @return string|nil key Active sort column key, or nil when unsorted.
    function Table:getSortKey()
        return self.sortKey
    end

    --- Returns true when sorting ascending.
    --- @return boolean ascending True when the active sort is ascending.
    function Table:getSortAscending()
        return self.sortAsc
    end

    --- Whether a row may become selected. Disabled rows in a list override this.
    --- @param row table Row table from `rows`.
    --- @return boolean selectable True when the row accepts selection.
    function Table:canSelectRow(row) -- luacheck: ignore
        return row ~= nil
    end

    --- Selects or deselects one row. In single mode selecting a row clears the
    --- previous selection; in multi mode the row is toggled.
    --- @param row table Row table from `rows`.
    --- @param selected boolean True to select the row, false to deselect it.
    --- @param silent boolean|nil True skips the `onChange` callback.
    function Table:setRowSelected(row, selected, silent)
        if self.selectionMode == "none" then
            return
        end
        if selected and not self:canSelectRow(row) then
            return
        end
        local wasSelected = self.selected[row] == true
        if selected then
            if self.selectionMode == "single" and not wasSelected then
                self:_clearSelection()
            end
            self.selected[row] = true
        else
            self.selected[row] = nil
        end
        local isSelected = self.selected[row] == true
        if not silent and wasSelected ~= isSelected and self.onChange ~= nil then
            self.onChange(self)
        end
    end

    --- Returns true when the row is selected.
    --- @param row table Row table from `rows`.
    --- @return boolean selected True when the row is currently selected.
    function Table:isRowSelected(row)
        return self.selected[row] == true
    end

    --- Clears the whole selection.
    --- @param silent boolean|nil True skips the `onChange` callback.
    --- @return PallidTable self For chaining.
    function Table:clearSelection(silent)
        local hadSelection = hasEntries(self.selected)
        if not hadSelection then
            return self
        end
        self:_clearSelection()
        self.dragSelecting = false
        if not silent and self.onChange ~= nil then
            self.onChange(self)
        end
        return self
    end

    --- Changes the selection mode. Switching modes clears the selection because a
    --- multi selection is not representable in single mode.
    --- @param mode "single"|"multi"|"none" New selection mode.
    --- @return PallidTable self For chaining.
    function Table:setSelectionMode(mode)
        if mode ~= "single" and mode ~= "multi" and mode ~= "none" then
            Pallid.log("Table:setSelectionMode: unknown mode '" .. tostring(mode) .. "'")
            return self
        end
        if mode == self.selectionMode then
            return self
        end
        local hadSelection = hasEntries(self.selected)
        self.selectionMode = mode
        if mode ~= "multi" then
            self.dragSelect = false
        end
        self:_clearSelection()
        self.dragSelecting = false
        if hadSelection and self.onChange ~= nil then
            self.onChange(self)
        end
        return self
    end

    --- Returns the selected rows in the current view order.
    --- @return table[] rows Selected row tables.
    function Table:getSelectedRows()
        local result = {}
        for i = 1, #self.view do
            local row = self.view[i]
            if self.selected[row] then
                result[#result + 1] = row
            end
        end
        return result
    end
end
