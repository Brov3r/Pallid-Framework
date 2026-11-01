require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/geometry"
require "pallid/ui/api/clip"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/scrollbar"
local addViewMethods = require "pallid/ui/widgets/table/view"
local addDrawMethods = require "pallid/ui/widgets/table/draw"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local HEADER = 24
local ROW = 22
local MIN_COLUMN = 40
-- The resize zone is centred on the divider: half of it lies in each column,
-- so the target is twice as wide as a one-sided grab strip.
local RESIZE_GRAB = 20
local BAR = Widgets.DEFAULT_SCROLLBAR_SIZE or 10
local ICON_DIR = "media/assets/ui/pallid/icons/"
local ICON_OPTS = { mode = "fit" }
-- Bound per-row text caches. Tables can contain tens of thousands of rows and
-- scrolling through all of them must not retain a layout table for every cell.
local CELL_TEXT_CACHE_LIMIT = 512
-- Candidate scrollbar states, fewest bars first. Evaluating all four avoids
-- the oscillation where a vertical bar creates a horizontal one and back.
local BAR_STATES = {
    { v = false, h = false },
    { v = true,  h = false },
    { v = false, h = true  },
    { v = true,  h = true  },
}

--- True while either Shift key is held. The wheel uses it for horizontal
--- scrolling; a missing Keyboard table (tests) simply means "not held".
--- @return boolean down True when Shift is held.
local function shiftDown()
    return Keyboard ~= nil and Keyboard.isKeyDown ~= nil
        and (Keyboard.isKeyDown(Keyboard.KEY_LSHIFT) or Keyboard.isKeyDown(Keyboard.KEY_RSHIFT))
end

--- True while either Control key is held.
--- @return boolean down True when Control is held.
local function ctrlDown()
    return Keyboard ~= nil and Keyboard.isKeyDown ~= nil
        and (Keyboard.isKeyDown(Keyboard.KEY_LCONTROL) or Keyboard.isKeyDown(Keyboard.KEY_RCONTROL))
end

--- One cell value that can carry an icon and text. A plain string/number/boolean
--- keeps the old text-only behaviour; a table with any descriptor field is
--- rendered through this shape.
--- @class PallidTableCell
--- @field text string|number|nil Primary cell text.
--- @field label string|number|nil Fallback text when `text` is nil.
--- @field icon string|Texture|InventoryItem|Item|false|nil Icon source: a texture path, a registered icon name, a Texture, an item object, or false to suppress a column icon.
--- @field iconColor PallidColor|nil Tint for textures and registered icons; item icons keep their own colours.
--- @field iconSize number|nil Icon box size in pixels, clamped to the row height and column width.
--- @field color PallidColor|nil Text colour override for this cell.

--- One column descriptor. Extra caller fields are preserved on the internal
--- copy, so custom metadata such as `format` can live alongside these fields.
--- @class PallidTableColumn
--- @field key string Row field key.
--- @field title string|nil Header label; defaults to `key`.
--- @field width number|nil Fixed width in pixels; nil makes the column flexible.
--- @field sortable boolean|nil False disables sorting for this column.
--- @field icon string|Texture|InventoryItem|Item|fun(row: table, value: any): string|Texture|InventoryItem|Item|nil Icon source or resolver for every cell in the column.
--- @field iconColor PallidColor|fun(row: table, value: any): PallidColor|nil Shared icon tint or a resolver.
--- @field iconSize number|nil Default icon box size for this column.
--- @field headerIcon string|Texture|InventoryItem|Item|false|nil Icon drawn before the header title; false suppresses it.
--- @field headerIconColor PallidColor|nil Tint for the header icon.
--- @field headerIconSize number|nil Header icon box size, clamped to the header height and column width.

--- Data table with sortable headers, draggable column widths, single or multi
--- selection and both scrollbars. Right-clicking a row calls `opts.onContext`.
---
--- Column widths are resolved to whole pixels on every layout pass. A column
--- without an explicit `width` is flexible; fixed columns never shrink below
--- their configured width. The last flexible column absorbs the integer
--- remainder, and with no flexible columns at all `stretchLastColumn` decides
--- whether the last column fills the remaining space. Resizing the last column
--- by hand disables that automatic stretch so the dragged width is kept.
---
--- Cells are plain text values by default. A `PallidTableCell` table adds an
--- icon, a text colour or an explicit text label; a column-level icon applies
--- to every cell and can be a function of the row/value. Headers accept their
--- own `headerIcon`, and header/row heights are independent.
---
--- Row heights are uniform per table; use `setRowHeight` and `setHeaderHeight`
--- to change them after construction.
---
--- The table is a leaf: it owns its two scrollbars and paints them manually, so
--- `drawChildren` is intentionally empty. Use a Panel/VBox around the table if
--- additional widgets are needed.
---
--- Column resizing uses a grab zone centred on each divider, so half of the
--- target lies in each neighbouring column. A resize icon and a highlighted
--- divider appear on hover because the OS cursor shape cannot be changed from
--- Lua. The active sort marker is drawn directly after the header text.
---
--- The first manual resize freezes flexible columns at their current widths.
--- Dragging a divider changes the column on its left; every column to its
--- right shifts by the same amount. When the table has spare width the last
--- column absorbs it, so its right edge stays on the table edge; growing past
--- the viewport raises the horizontal bar. The last column's right edge changes
--- only that column and disables `stretchLastColumn` for the table.
--- @class PallidTable : PallidWidget
--- @field columns PallidTableColumn[] Resolved column descriptors; extra caller fields are preserved.
--- @field rows table[] Source rows in caller order.
--- @field view table[] Visible rows in current sort order.
--- @field sortKey string|nil Active sort column key, or nil when unsorted.
--- @field sortAsc boolean True when the active sort is ascending.
--- @field selectionMode "single"|"multi"|"none" Current selection mode.
--- @field selected table<table, boolean> Selected rows as a set keyed by row table.
--- @field barV PallidScrollBar Vertical scrollbar child.
--- @field barH PallidScrollBar Horizontal scrollbar child.
--- @field rowHeight number Resolved row height in pixels.
--- @field headerHeight number Configured header height in pixels.
--- @field leadWidth number Fixed gutter width left of the first column.
--- @field drawRowLead fun(table: PallidTable, el: ISUIElement, y: number, h: number, index: integer, row: table)|nil Optional per-row gutter painter, called inside the body clip.
--- @field stretchLastColumn boolean True lets the last column absorb leftover width when all columns are fixed.
--- @field dragSelect boolean True when multi-row range selection is enabled.
--- @field bodyColor PallidColor Fill behind empty row space.
--- @field headerColor PallidColor Header fill.
--- @field headerHover PallidColor Hovered header cell fill.
--- @field rowColor PallidColor Even row fill.
--- @field rowAltColor PallidColor Odd row fill.
--- @field rowHover PallidColor Hovered row fill.
--- @field rowSelected PallidColor Selected row fill.
--- @field hoverEdge boolean True while the cursor is on a divider resize zone.
--- @field borderColor PallidColor Table, header divider and column divider colour.
--- @field textColor PallidColor Cell and header text colour.
--- @field sortColor PallidColor Active sort marker tint.
--- @field dragFill PallidColor Drag-selection overlay fill.
--- @field dragBorder PallidColor Drag-selection outline colour.
local Table = Widgets.class("Table")

-- Sorting/selection and drawing live in table/view.lua / table/draw.lua.
addViewMethods(Table)
addDrawMethods(Table)

--- Creates a new `Table` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param columns PallidTableColumn[] Column descriptors.
--- @param rows table[] Row records keyed by column keys; a cell may be a PallidTableCell.
--- @param opts table|nil Optional layout, behaviour and palette overrides.
--- @field opts.rowHeight number|nil Row height in pixels, defaults to 22.
--- @field opts.headerHeight number|nil Header height in pixels, defaults to 24; 0 hides the header.
--- @field opts.selectionMode "single"|"multi"|"none"|nil Selection mode, defaults to "single".
--- @field opts.sortKey string|nil Initial sort column key.
--- @field opts.sortAsc boolean|nil Initial sort direction; defaults to ascending.
--- @field opts.showVerticalBars boolean|nil False disables the vertical bar.
--- @field opts.showHorizontalBars boolean|nil False disables the horizontal bar.
--- @field opts.barSize number|nil Scrollbar thickness, defaults to 10.
--- @field opts.barGap number|nil Gap between the table edge and a bar; nil picks 3 or 5.
--- @field opts.dragSelect boolean|nil Enables range selection; requires selectionMode "multi".
--- @field opts.stretchLastColumn boolean|nil False keeps fixed last columns at their width.
--- @field opts.leadWidth number|nil Fixed gutter left of the first column; defaults to 0.
--- @field opts.background PallidColor|nil Fill behind empty row space.
--- @field opts.headerColor PallidColor|nil Header fill.
--- @field opts.headerHoverColor PallidColor|nil Hovered header cell fill.
--- @field opts.rowColor PallidColor|nil Even row fill.
--- @field opts.rowAltColor PallidColor|nil Odd row fill.
--- @field opts.rowHoverColor PallidColor|nil Hovered row fill.
--- @field opts.rowSelectedColor PallidColor|nil Selected row fill.
--- @field opts.border PallidColor|nil Table and divider colour.
--- @field opts.textColor PallidColor|nil Cell and header text colour.
--- @field opts.sortColor PallidColor|nil Active sort marker tint.
--- @field opts.dragColor PallidColor|nil Drag-selection accent; also derives `dragFill`.
--- @field opts.dragFill PallidColor|nil Explicit drag-selection overlay fill.
--- @field opts.dragBorder PallidColor|nil Explicit drag-selection outline.
--- @field opts.onChange fun(tableElement: PallidTable)|nil Called after the selection changes.
--- @field opts.onSort fun(tableElement: PallidTable, key: string|nil, ascending: boolean)|nil Called after a header sort changes.
--- @field opts.onContext fun(tableElement: PallidTable, row: table, x: number, y: number)|nil Called on a row right-click with root-local cursor coordinates.
--- @return PallidTable table New table instance.
function Table.new(x, y, w, h, columns, rows, opts)
    opts = opts or {}
    w, h = w or 0, h or 0
    columns = type(columns) == "table" and columns or {}
    local self = setmetatable({}, Table)
    self:init(x, y, w, h)

    self.columns = {}
    for i = 1, #columns do
        local source = columns[i]
        if type(source) ~= "table" then
            Pallid.log("Table: column " .. i .. " is not a table; using an empty column")
            source = {}
        end

        -- Copy every caller field first: extra fields such as format or align
        -- belong to the caller and must survive the normalisation below.
        local column = {}
        for key, value in pairs(source) do
            column[key] = value
        end

        column.key = source.key
        column.title = source.title ~= nil and source.title or source.key
        if column.title == nil then
            column.title = ""
        elseif type(column.title) ~= "string" then
            column.title = tostring(column.title)
        end
        if type(source.width) ~= "number" then
            column.width = nil
        else
            column.width = source.width
        end
        column.flex = column.width == nil
        column._w = 0
        if column.key == nil then
            column.sortable = false
            Pallid.log("Table: column " .. i .. " has no key; sorting is disabled for it")
        else
            column.sortable = source.sortable ~= false
        end
        self.columns[i] = column
    end

    self.rows = rows or {}
    self.view = {}
    self.rowHeight = math.max(1, math.floor(opts.rowHeight or ROW))
    self.headerHeight = math.max(0, math.floor(opts.headerHeight or HEADER))
    self._headerH = self.headerHeight
    self.selectionMode = opts.selectionMode or "single"
    if self.selectionMode ~= "single" and self.selectionMode ~= "multi"
        and self.selectionMode ~= "none" then
        Pallid.log("Table: unknown selectionMode '" .. tostring(self.selectionMode) .. "'; using \"single\"")
        self.selectionMode = "single"
    end
    self.stretchLastColumn = opts.stretchLastColumn ~= false
    self.leadWidth = math.max(0, math.floor(opts.leadWidth or 0))
    self.dragSelect = opts.dragSelect == true and self.selectionMode == "multi"
    if opts.dragSelect == true and not self.dragSelect then
        Pallid.log("Table: dragSelect requires selectionMode = \"multi\"; disabled")
    end
    self.dragSelecting = false
    self.dragStartRow = nil
    self.dragCurrentRow = nil
    self.dragStartX = 0
    self.dragStartY = 0
    self.dragCurrentX = 0
    self.dragCurrentY = 0
    self.sortKey = opts.sortKey
    self.sortAsc = opts.sortAsc ~= false
    self.onChange = opts.onChange
    self.onContext = opts.onContext
    -- Row-keyed text layouts, bounded by CELL_TEXT_CACHE_LIMIT rows. Only
    -- visible cells ever populate the cache; scrolling across a huge data set
    -- resets it instead of retaining one layout per row.
    self._cellTextCaches = {}
    self._cellTextCacheRows = 0
    self._headerTextCaches = {}
    self.onSort = opts.onSort
    self.barSize = math.max(1, math.floor(opts.barSize or BAR))
    self.barGap = opts.barGap
    self.showVerticalBars = opts.showVerticalBars
    self.showHorizontalBars = opts.showHorizontalBars
    self.scrollY = 0
    self.scrollX = 0
    self.maxScrollY = 0
    self.maxScrollX = 0
    self.viewW = w
    self.viewH = math.max(0, h - self.headerHeight)
    self.totalW = 0
    self.selected = {}
    self.selectionAnchor = nil
    self.hoverRow = 0
    self.hoverColumn = 0
    self.hoverX = nil
    self.hoverY = nil
    self.hoverEdge = false
    self.resizing = nil

    local Color = Pallid.UI.Color
    self.bodyColor = opts.background or Color.background
    self.headerColor = opts.headerColor or Color.surfaceElevated
    self.headerHover = opts.headerHoverColor or Color.accentSoft
    self.rowColor = opts.rowColor or Color.surface
    self.rowAltColor = opts.rowAltColor or Color.surfaceMuted
    self.rowHover = opts.rowHoverColor or Color.accentSoft
    self.rowSelected = opts.rowSelectedColor or Color.primarySoft
    self.borderColor = opts.border or Color.border
    self.textColor = opts.textColor or Color.text
    self.sortColor = opts.sortColor or Color.primaryStrong
    local dragColor = opts.dragColor or Color.primary
    self.dragFill = opts.dragFill or Color.withAlpha(dragColor, 0.18)
    self.dragBorder = opts.dragBorder or dragColor
    self.style = {
        font = Pallid.UI.Fonts.small,
        color = self.textColor,
        alignH = "left",
        alignV = "middle",
    }
    -- Sort markers use the shared icon pack; the vector triangle stays as a
    -- fallback for a missing texture. Textures are resolved once per table.
    self._sortAscTexture = Pallid.UI.Textures.get(ICON_DIR .. "arrow-up-04.png")
    self._sortDescTexture = Pallid.UI.Textures.get(ICON_DIR .. "arrow-down-04.png")
    self._resizeTexture = Pallid.UI.Textures.get(ICON_DIR .. "cursor-horizontal-resize.png")
    self._sortIconOpts = ICON_OPTS

    self.barV = Widgets.scrollBar(true, w - self.barSize, self.headerHeight, self.barSize, h - self.headerHeight, { margin = 1 })
    self.barH = Widgets.scrollBar(false, 0, h - self.barSize, w, self.barSize, { margin = 1 })
    self.barV.onChange = function(_, value)
        self.scrollY = math.floor(value * (self.maxScrollY or 0))
    end
    self.barH.onChange = function(_, value)
        self.scrollX = math.floor(value * (self.maxScrollX or 0))
    end
    self:add(self.barV)
    self:add(self.barH)

    self:refreshView()
    return self
end

--- Factory shortcut for `Table.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param columns PallidTableColumn[] Column descriptors.
--- @param rows table[] Row records keyed by column keys; a cell may be a PallidTableCell.
--- @param opts table|nil Optional layout, behaviour and palette overrides.
--- @return PallidTable table New table instance.
function Widgets.table(x, y, w, h, columns, rows, opts)
    return Table.new(x, y, w, h, columns, rows, opts)
end

--- Returns the per-cell text layout cache for a row and column. The cache is
--- keyed by the row object, so sorting does not invalidate it; it is bounded
--- and reset after a large scroll sweep.
--- @param row table Row record that owns the cell.
--- @param columnIndex integer One-based column index.
--- @return PallidPreparedText cache Reusable layout cache for the cell.
function Table:_cellTextCache(row, columnIndex)
    local caches = self._cellTextCaches
    local rowCaches = caches[row]
    if rowCaches == nil then
        if (self._cellTextCacheRows or 0) >= CELL_TEXT_CACHE_LIMIT then
            caches = {}
            self._cellTextCaches = caches
            self._cellTextCacheRows = 0
        end
        rowCaches = {}
        caches[row] = rowCaches
        self._cellTextCacheRows = (self._cellTextCacheRows or 0) + 1
    end

    local cache = rowCaches[columnIndex]
    if cache == nil then
        cache = {}
        rowCaches[columnIndex] = cache
    end
    return cache
end

--- Returns the prepared header cache for a column.
--- @param columnIndex integer One-based column index.
--- @return PallidPreparedText cache Reusable header title layout.
function Table:_headerTextCache(columnIndex)
    local cache = self._headerTextCaches[columnIndex]
    if cache == nil then
        cache = {}
        self._headerTextCaches[columnIndex] = cache
    end
    return cache
end

-- Layout --------------------------------------------------------------------

--- Resolves every column to a whole-pixel width for `availableW`. Flexible
--- columns share the remaining width after `leadWidth` is reserved; the last
--- flexible column absorbs the integer remainder so the column sum fills the
--- viewport. Fixed columns are never shrunk below their configured width; a
--- table that cannot fit them reports the overflow through `totalW` and the
--- horizontal bar.
--- @param availableW number Width available to the columns, in pixels.
function Table:syncColumns(availableW)
    local viewport = math.max(MIN_COLUMN, math.floor((availableW or 0) + 0.5))
    local lead = self.leadWidth or 0
    -- The lead gutter is reserved before the columns; every width below is in
    -- column space so flexible columns share only the space that remains.
    local available = math.max(MIN_COLUMN, viewport - lead)
    local fixedTotal, flexCount = 0, 0
    for i = 1, #self.columns do
        local column = self.columns[i]
        if type(column.width) == "number" then
            column.flex = false
            fixedTotal = fixedTotal + math.max(MIN_COLUMN, math.floor(column.width + 0.5))
        else
            column.flex = true
            flexCount = flexCount + 1
        end
    end

    local remaining = available - fixedTotal
    local each = MIN_COLUMN
    if flexCount > 0 and remaining >= flexCount * MIN_COLUMN then
        each = math.floor(remaining / flexCount)
    end

    local total, lastFlex = 0, nil
    for i = 1, #self.columns do
        local column = self.columns[i]
        if column.flex then
            column._w = each
            lastFlex = i
        else
            column._w = math.max(MIN_COLUMN, math.floor(column.width + 0.5))
        end
    end

    if flexCount > 0 and lastFlex ~= nil then
        -- Keep every neighbouring column on an integer edge; the last flexible
        -- column absorbs the sub-column remainder. On overflow the deficit stays
        -- visible through the horizontal bar instead of shrinking below minimum.
        local used = 0
        for i = 1, #self.columns do
            used = used + self.columns[i]._w
        end
        local remainder = available - used
        if remainder > 0 then
            self.columns[lastFlex]._w = self.columns[lastFlex]._w + remainder
        end
    elseif flexCount == 0 and self.stretchLastColumn then
        local last = self.columns[#self.columns]
        if last ~= nil then
            -- The last column is the fill column: keep its right edge on the
            -- table edge in both directions. Resizing a middle column then
            -- shifts the following columns instead of leaving a gap or pushing
            -- content under the horizontal bar.
            local others = 0
            for i = 1, #self.columns - 1 do
                others = others + self.columns[i]._w
            end
            local fill = available - others
            if fill < MIN_COLUMN then
                fill = MIN_COLUMN
            end
            last._w = fill
        end
    end

    self._colX = self._colX or {}
    for i = 1, #self.columns do
        self._colX[i] = lead + total
        total = total + self.columns[i]._w
    end
    self.totalW = lead + total
end

--- Freezes every flexible column at its current resolved width. A manual
--- resize switches the table from automatic distribution to explicit widths,
--- so dragging a divider cannot silently resize a third column.
function Table:_freezeColumns()
    for i = 1, #self.columns do
        local column = self.columns[i]
        if column.width == nil then
            column.width = math.max(MIN_COLUMN, column._w or MIN_COLUMN)
        end
        column.flex = false
    end
end

--- Recomputes the viewport, scroll ranges and both scrollbars. The table is
--- not an animated scroller, so every offset is snapped to a whole pixel here:
--- masks, row stripes and text then share the same geometry.
function Table:syncBars()
    local wPx = math.max(0, math.floor(self.w + 0.5))
    local hPx = math.max(0, math.floor(self.h + 0.5))
    local headerHeight = math.min(self.headerHeight, hPx)
    self._headerH = headerHeight
    local bodyH = math.max(0, hPx - headerHeight)
    local contentH = #self.view * self.rowHeight
    local barSize = math.max(1, math.floor(self.barSize + 0.5))
    local gap = math.max(0, math.floor((self.barGap or (math.min(wPx, hPx) < 80 and 3 or 5)) + 0.5))
    local vFits = self.showVerticalBars ~= false
        and wPx > barSize + gap * 2 and bodyH > gap * 2
    local hFits = self.showHorizontalBars ~= false
        and bodyH > barSize + gap * 2 and wPx > gap * 2

    -- Try the four bar states with the fewest bars first. A state is accepted
    -- only when it does not create the bar it left out; this avoids the classic
    -- vertical/horizontal feedback loop instead of iterating an arbitrary count.
    local needV, needH, viewW, viewH = false, false, wPx, bodyH
    local found = false
    for i = 1, #BAR_STATES do
        local state = BAR_STATES[i]
        if (not state.v or vFits) and (not state.h or hFits) then
            local candidateW = math.max(0, wPx - (state.v and (barSize + gap) or 0))
            local candidateH = math.max(0, bodyH - (state.h and (barSize + gap) or 0))
            self:syncColumns(candidateW)
            local wantsV = vFits and contentH > candidateH
            local wantsH = hFits and self.totalW > candidateW
            if wantsV == state.v and wantsH == state.h then
                needV, needH = state.v, state.h
                viewW, viewH = candidateW, candidateH
                found = true
                break
            end
        end
    end
    if not found then
        -- Pathological content: prefer showing both bars when they fit.
        needV, needH = vFits, hFits
        viewW = math.max(0, wPx - (needV and (barSize + gap) or 0))
        viewH = math.max(0, bodyH - (needH and (barSize + gap) or 0))
    end
    -- Columns must match the final viewport after the chosen state.
    self:syncColumns(viewW)

    self.viewW = viewW
    self.viewH = viewH
    self.maxScrollY = math.max(0, contentH - viewH)
    self.maxScrollX = math.max(0, self.totalW - viewW)
    self.scrollY = math.floor(math.max(0, math.min(self.maxScrollY, self.scrollY)))
    self.scrollX = math.floor(math.max(0, math.min(self.maxScrollX, self.scrollX)))

    self.barV:setEnabled(self.enabled)
    self.barH:setEnabled(self.enabled)

    if needV then
        self.barV:setVisible(true)
        self.barV:setBounds(
            wPx - barSize - gap,
            headerHeight + gap,
            barSize,
            math.max(1, bodyH - gap * 2 - (needH and (barSize + gap) or 0))
        )
        self.barV.page = math.min(1, viewH / math.max(1, contentH))
        self.barV.value = self.maxScrollY > 0 and self.scrollY / self.maxScrollY or 0
    else
        self.barV:setVisible(false)
    end

    if needH then
        self.barH:setVisible(true)
        self.barH:setBounds(
            gap,
            hPx - barSize - gap,
            math.max(1, wPx - gap * 2 - (needV and (barSize + gap) or 0)),
            barSize
        )
        self.barH.page = math.min(1, viewW / math.max(1, self.totalW))
        self.barH.value = self.maxScrollX > 0 and self.scrollX / self.maxScrollX or 0
    else
        self.barH:setVisible(false)
    end
end

--- Resolved width of a column.
--- @param index integer One-based column index.
--- @return number width Resolved width in pixels, or 0 for an invalid index.
function Table:columnWidth(index)
    local column = self.columns[index]
    return column ~= nil and (column._w or 0) or 0
end

--- Sets a column width programmatically. `nil` makes the column flexible.
--- @param index integer One-based column index.
--- @param width number|nil Fixed width in pixels, or nil for a flexible column.
--- @return PallidTable self For chaining.
function Table:setColumnWidth(index, width)
    local column = self.columns[index]
    if column == nil then
        return self
    end
    if width == nil then
        column.width = nil
        column.flex = true
    elseif type(width) == "number" then
        column.width = math.max(MIN_COLUMN, math.floor(width + 0.5))
        column.flex = false
    else
        Pallid.log("Table:setColumnWidth: width must be a number or nil")
        return self
    end
    self:syncBars()
    return self
end

--- Sets the header height. Zero hides the header; the value is clamped to the
--- table height during layout.
--- @param height number New header height in pixels.
--- @return PallidTable self For chaining.
function Table:setHeaderHeight(height)
    if type(height) ~= "number" then
        Pallid.log("Table:setHeaderHeight: height must be a number")
        return self
    end
    self.headerHeight = math.max(0, math.floor(height + 0.5))
    self:syncBars()
    return self
end

--- Sets the uniform data row height.
--- @param height number New row height in pixels; clamped to at least one.
--- @return PallidTable self For chaining.
function Table:setRowHeight(height)
    if type(height) ~= "number" then
        Pallid.log("Table:setRowHeight: height must be a number")
        return self
    end
    self.rowHeight = math.max(1, math.floor(height + 0.5))
    self:syncBars()
    return self
end

--- Left edge and width of a column in root-local coordinates.
--- @param index integer One-based column index.
--- @return number x Left edge including the current horizontal scroll.
--- @return number w Resolved width in pixels, or 0 for an invalid index.
function Table:columnRect(index)
    local column = self.columns[index]
    if column == nil then
        return self:originX(), 0
    end
    local x = self:originX() - self.scrollX
        + (self._colX and self._colX[index] or 0)
    return x, column._w or 0
end

--- Returns the first and last column that intersects the visible viewport.
--- Off-screen columns are skipped by drawing; text measurement is not free.
--- @param viewW number Visible width in pixels.
--- @return integer first One-based first visible column, or 1 when none.
--- @return integer last One-based last visible column, or 0 when none.
function Table:visibleColumns(viewW)
    local count = #self.columns
    if count == 0 or viewW <= 0 then
        return 1, 0
    end

    local left = self.scrollX
    local right = left + viewW
    local colX = self._colX
    local first, last = 0, 0
    for i = 1, count do
        local x = colX and colX[i] or 0
        local w = self.columns[i]._w or 0
        if x >= right then
            break
        end
        if x + w > left then
            if first == 0 then
                first = i
            end
            last = i
        end
    end
    if first == 0 then
        return 1, 0
    end
    return first, last
end

-- Input ----------------------------------------------------------------------

--- Finds the column under the cursor and whether it sits on a resize edge.
--- A divider belongs to the column on its left: dragging it changes that
--- column's width and shifts every column to its right. The table's right edge
--- resizes the last column.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates; unused, kept for symmetry.
--- @return integer column One-based column index, or 0 when none.
--- @return boolean onEdge True when the cursor is inside the resize handle.
function Table:hitColumn(px, py)
    local originX = self:originX()
    if self.viewW <= 0 or px < originX or px >= originX + self.viewW then
        return 0, false
    end

    local count = #self.columns
    local colX = self._colX
    local half = math.floor(RESIZE_GRAB * 0.5)
    local right = originX + self.viewW

    for i = 1, count - 1 do
        local x = originX - self.scrollX + (colX and colX[i] or 0)
        local divider = x + (self.columns[i]._w or 0)
        if divider > originX and divider < right
            and px >= divider - half and px < divider + half then
            return i, true
        end
    end

    -- The table's right edge resizes the last column. When the table has spare
    -- width the last column is visually extended to this edge (see drawSelf).
    if count > 0 then
        local last = self.columns[count]
        local lastX = originX - self.scrollX + (colX and colX[count] or 0)
        local lastRight = lastX + (last._w or 0)
        if lastRight <= right + 0.5 and px >= right - half and px < right then
            return count, true
        end
    end

    for i = 1, count do
        local x, w = self:columnRect(i)
        if px >= x and px < x + w then
            return i, false
        end
    end
    return 0, false
end

--- Finds the visible row under the cursor.
--- @param py number Cursor Y in root-local coordinates.
--- @return integer index One-based row index in `view`, or 0 when none.
function Table:rowAt(py)
    local localY = py - self:originY()
    local headerHeight = self._headerH or self.headerHeight
    if localY < headerHeight or localY >= headerHeight + self.viewH then
        return 0
    end
    local index = math.floor((localY - headerHeight + self.scrollY) / self.rowHeight) + 1
    if index < 1 or index > #self.view then
        return 0
    end
    return index
end

--- Recomputes the hovered row and column from the last cursor position. Called
--- after sorting, scrolling and resizing, because those change what is under a
--- stationary cursor.
function Table:refreshHover()
    local px, py = self.hoverX, self.hoverY
    if px == nil or py == nil then
        return
    end
    if not self.enabled then
        self.hoverRow = 0
        self.hoverColumn = 0
        self.hoverEdge = false
        return
    end

    -- While a column is being resized keep the handle pinned to that column
    -- even if the cursor leaves the original narrow grab strip.
    if self.resizing ~= nil then
        self.hoverColumn = self.resizing
        self.hoverEdge = true
        self.hoverRow = 0
        return
    end

    local localY = py - self:originY()
    local headerHeight = self._headerH or self.headerHeight
    if localY < headerHeight then
        local column, onEdge = self:hitColumn(px, py)
        self.hoverColumn = column
        self.hoverEdge = onEdge
        self.hoverRow = 0
    else
        self.hoverColumn = 0
        self.hoverEdge = false
        self.hoverRow = self:rowAt(py)
    end
end

--- Handles a press on the header or the body.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the table consumed the press.
function Table:onDown(px, py, button)
    if not self.enabled then
        return false
    end
    self:syncBars()
    local localY = py - self:originY()
    local headerHeight = self._headerH or self.headerHeight

    if localY < headerHeight then
        local column, onEdge = self:hitColumn(px, py)
        if column == 0 then
            return false
        end
        -- A right click on a header must not re-sort the table; it is consumed
        -- here so it cannot fall through to the parent.
        if button == "right" then
            return true
        end
        if onEdge then
            -- First manual resize freezes every flexible column at its current
            -- width. Resizing then changes only the dragged column; all columns
            -- to its right shift, and the last column keeps filling the table.
            self:_freezeColumns()
            local primary = column
            local isRightEdge = primary == #self.columns
            if isRightEdge then
                -- Allow the last column to leave the fill width when dragged.
                self.stretchLastColumn = false
                -- The last column is drawn to the table edge even when its
                -- logical width is smaller; start from that visual width so the
                -- first drag cannot jump.
                local originX = self:originX()
                local lastX = originX - self.scrollX + (self._colX and self._colX[primary] or 0)
                local visualWidth = math.max(0, originX + self.viewW - lastX)
                if visualWidth > (self.columns[primary]._w or 0) then
                    self.columns[primary].width = visualWidth
                    self.columns[primary]._w = visualWidth
                    self.columns[primary].flex = false
                end
            end

            self.resizing = primary
            self.resizeStartX = px
            self.resizeStartWidth = self.columns[primary]._w
            self.hoverColumn = primary
            self.hoverEdge = true
        elseif self.columns[column].sortable and self.columns[column].key ~= nil then
            self:setSort(self.columns[column].key)
        end
        return true
    end

    local index = self:rowAt(py)
    if index == 0 then
        return true
    end

    local row = self.view[index]
    if button == "right" then
        -- Keep a multi selection when the pressed row is already part of it;
        -- otherwise make this row the only selected row.
        if self.selectionMode ~= "none" and not self.selected[row] then
            self:_clearSelection()
            self:setRowSelected(row, true)
        end
        if self.onContext ~= nil then
            self.onContext(self, row, px, py)
        end
        return true
    end

    if self.dragSelect and self.selectionMode == "multi" then
        self.dragSelecting = true
        self.dragStartRow = index
        self.dragCurrentRow = index
        self.dragStartX = px
        self.dragStartY = py
        self.dragCurrentX = px
        self.dragCurrentY = py
        self:_clearSelection()
        self:setRowSelected(row, true, true)
        self.selectionAnchor = row
        if self.onChange ~= nil then
            self.onChange(self)
        end
        return true
    end

    if self.selectionMode == "single" then
        self:setRowSelected(row, true)
        self.selectionAnchor = row
    elseif self.selectionMode == "multi" then
        local ctrl = ctrlDown()
        local shift = shiftDown()
        local anchorIndex = 0
        if shift and self.selectionAnchor ~= nil then
            for i = 1, #self.view do
                if self.view[i] == self.selectionAnchor then
                    anchorIndex = i
                    break
                end
            end
        end

        if anchorIndex > 0 then
            local anchor = self.selectionAnchor
            local first = math.min(anchorIndex, index)
            local last = math.max(anchorIndex, index)
            self:_clearSelection()
            for i = first, last do
                local rangeRow = self.view[i]
                if rangeRow ~= nil and self:canSelectRow(rangeRow) then
                    self.selected[rangeRow] = true
                end
            end
            self.selectionAnchor = anchor
            if self.onChange ~= nil then
                self.onChange(self)
            end
        elseif ctrl then
            self:setRowSelected(row, not self.selected[row])
            self.selectionAnchor = row
        else
            self:_clearSelection()
            self:setRowSelected(row, true, true)
            self.selectionAnchor = row
            if self.onChange ~= nil then
                self.onChange(self)
            end
        end
    end
    return true
end

--- Handles a captured drag: range selection or column resizing.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Table:onMove(px, py)
    if not self.enabled then
        self.dragSelecting = false
        self.resizing = nil
        return
    end
    self.hoverX = px
    self.hoverY = py

    if self.dragSelecting then
        self.dragCurrentX = px
        self.dragCurrentY = py
        local index = self:rowAt(py)
        if index == 0 then
            local localY = py - self:originY()
            local headerHeight = self._headerH or self.headerHeight
            if localY < headerHeight then
                index = 1
            else
                index = #self.view
            end
        end
        if index > 0 and index ~= self.dragCurrentRow then
            self.dragCurrentRow = index
            local first = math.min(self.dragStartRow or index, index)
            local last = math.max(self.dragStartRow or index, index)
            self:_clearSelection()
            for i = first, last do
                local rangeRow = self.view[i]
                if rangeRow ~= nil and self:canSelectRow(rangeRow) then
                    self.selected[rangeRow] = true
                end
            end
            if self.onChange ~= nil then
                self.onChange(self)
            end
        end
        return
    end

    if self.resizing == nil then
        return
    end
    local column = self.columns[self.resizing]
    if column == nil then
        return
    end

    local width = self.resizeStartWidth + (px - self.resizeStartX)
    column.width = math.max(MIN_COLUMN, math.floor(width + 0.5))
    column.flex = false
    self:syncBars()
end

--- Ends a range selection or column resize.
--- @param px number Cursor X in root-local coordinates; unused.
--- @param py number Cursor Y in root-local coordinates; unused.
function Table:onUp(px, py)
    self.resizing = nil
    self.dragSelecting = false
    self.hoverX = px
    self.hoverY = py
    self:refreshHover()
end

--- Scrolls vertically, or horizontally while Shift is held. Returns false when
--- the chosen axis cannot move, so a parent list can consume the wheel instead.
--- @param delta number Wheel steps; positive scrolls down.
--- @return boolean handled True when the view actually moved.
function Table:onWheel(delta)
    if not self.enabled then
        return false
    end
    self:syncBars()

    if shiftDown() and self.showHorizontalBars ~= false and self.maxScrollX > 0 then
        local nextX = math.floor(math.max(0, math.min(self.maxScrollX, self.scrollX + delta * self.rowHeight * 3)))
        if nextX == self.scrollX then
            return false
        end
        self.scrollX = nextX
        return true
    end

    if self.maxScrollY <= 0 then
        return false
    end
    local nextY = math.floor(math.max(0, math.min(self.maxScrollY, self.scrollY + delta * self.rowHeight * 2)))
    if nextY == self.scrollY then
        return false
    end
    self.scrollY = nextY
    return true
end

--- Tracks the hovered row or header column and remembers the cursor position so
--- scrolling can re-resolve the hover without a mouse move.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Table:onHoverMove(px, py)
    self.hoverX = px
    self.hoverY = py
    self:refreshHover()
end

--- Clears the hover highlight when the cursor leaves the table.
function Table:onHoverEnd()
    self.hoverX = nil
    self.hoverY = nil
    self.hoverRow = 0
    self.hoverColumn = 0
    self.hoverEdge = false
    Widgets.Widget.onHoverEnd(self)
end

--- Routes a press to the scrollbars first and then to the table itself.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of the parent widget.
--- @param oy number Origin Y of the parent widget.
--- @param button string|nil "left" or "right".
--- @return PallidWidget|nil target Widget that accepted the press, or nil.
function Table:findDown(px, py, ox, oy, button)
    self._ox = ox
    self._oy = oy
    if not self.visible or not self.enabled then
        return nil
    end
    self:syncBars()

    -- Scrollbars are children and take priority over the rows.
    if self.barV.visible then
        local hit = self.barV:findDown(px, py, self:originX(), self:originY(), button)
        if hit ~= nil then
            return hit
        end
    end
    if self.barH.visible then
        local hit = self.barH:findDown(px, py, self:originX(), self:originY(), button)
        if hit ~= nil then
            return hit
        end
    end

    if self:isInside(px, py) then
        if self:onDown(px, py, button) then
            return self
        end
    end
    return nil
end

--- Finds the scrollbar or the table under the cursor.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of the parent widget.
--- @param oy number Origin Y of the parent widget.
--- @return PallidWidget|nil hovered Widget under the cursor, or nil.
function Table:findHover(px, py, ox, oy)
    self._ox = ox
    self._oy = oy
    if not self.visible or not self.enabled then
        return nil
    end
    self:syncBars()

    if self.barV.visible then
        local hit = self.barV:findHover(px, py, self:originX(), self:originY())
        if hit ~= nil then
            return hit
        end
    end
    if self.barH.visible then
        local hit = self.barH:findHover(px, py, self:originX(), self:originY())
        if hit ~= nil then
            return hit
        end
    end

    if self:isInside(px, py) then
        return self
    end
    return nil
end

--- Returns the table for the wheel only when the axis that would move has
--- overflow. Otherwise the parent list keeps the wheel.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of the parent widget.
--- @param oy number Origin Y of the parent widget.
--- @return PallidWidget|nil target Widget that handles the wheel, or nil.
function Table:findWheel(px, py, ox, oy)
    self._ox = ox
    self._oy = oy
    if not self.visible or not self.enabled or not self:isInside(px, py) then
        return nil
    end
    self:syncBars()
    if (shiftDown() and self.showHorizontalBars ~= false and self.maxScrollX > 0)
        or self.maxScrollY > 0 then
        return self
    end
    return nil
end
