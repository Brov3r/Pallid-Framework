# Data widgets

The data widgets display collections: tables, trees, virtual lists, reorderable lists, property grids and rule builders. Each one is a `Pallid.UI.Widgets` factory that returns a `PallidWidget` subclass, so `add`, `remove`, `setBounds`, `setVisible`, `setEnabled` and tooltips come from the base API documented in [ui-widget.md](ui-widget.md).

## Table (Pallid.UI.Widgets.Table)

Data table with sortable headers, draggable column widths, optional multi-selection, both scrollbars and per-row context and double-click callbacks. It is a leaf widget: its scrollbars are internal and it paints them itself.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels; nil becomes 0.
- h (number) - Height in pixels; nil becomes 0.
- columns (PallidTableColumn[]) - Column descriptors; see below.
- rows (table[]|nil) - Row records keyed by column key; nil or a non-table becomes an empty list.
- opts (table|nil) - Layout, behaviour and palette overrides; see below.

### Options
- rowHeight (number) - Row height in pixels, at least 1. Default `22`.
- headerHeight (number) - Header height in pixels; `0` hides the header. Default `24`.
- selectionMode ("single"|"multi"|"none") - Selection model; an unknown value falls back to `"single"`. Default `"single"`.
- sortKey (string) - Initial sort column key. Default `nil`.
- sortAsc (boolean) - Initial sort direction. Default `true`.
- showVerticalBars (boolean) - `false` disables the vertical bar. Default enabled.
- showHorizontalBars (boolean) - `false` disables the horizontal bar. Default enabled.
- barSize (number) - Scrollbar thickness in pixels. Default `10`.
- barGap (number) - Gap between the bar and the table edge. Default `3` when the table is smaller than 80 px on either axis, otherwise `5`.
- dragSelect (boolean) - Enables rubber-band range selection; requires `selectionMode = "multi"`, otherwise it is logged and ignored. Default `false`.
- stretchLastColumn (boolean) - `false` keeps fixed last columns at their configured width. Default `true`.
- leadWidth (number) - Fixed gutter left of the first column. Default `0`.
- background (PallidColor) - Fill behind empty row space. Default `Pallid.UI.Color.background`.
- headerColor (PallidColor) - Header fill. Default `Color.surfaceElevated`.
- headerHoverColor (PallidColor) - Hovered header cell fill. Default `Color.accentSoft`.
- rowColor (PallidColor) - Even row fill. Default `Color.surface`.
- rowAltColor (PallidColor) - Odd row fill. Default `Color.surfaceMuted`.
- rowHoverColor (PallidColor) - Hovered row fill. Default `Color.accentSoft`.
- rowSelectedColor (PallidColor) - Selected row fill. Default `Color.primarySoft`.
- border (PallidColor) - Table, header and column divider colour. Default `Color.border`.
- textColor (PallidColor) - Cell and header text colour. Default `Color.text`.
- sortColor (PallidColor) - Active sort marker and resize handle tint. Default `Color.primaryStrong`.
- dragColor (PallidColor) - Drag-selection accent, also used to derive `dragFill`. Default `Color.primary`.
- dragFill (PallidColor) - Explicit drag-selection overlay fill. Default `Color.withAlpha(dragColor, 0.18)`.
- dragBorder (PallidColor) - Explicit drag-selection outline. Default `dragColor`.
- onChange (fun(tableElement)) - Called after the selection changes.
- onSort (fun(tableElement, key, ascending)) - Called after a header sort changes; `key` is nil when the sort is cleared.
- onContext (fun(tableElement, row, x, y)) - Called on a row right-click; `x`/`y` are root-local.
- onActivate (fun(tableElement, row, index)) - Called when two left clicks land on the same row within 400 ms.
- footerHeight (number) - Footer height in pixels; rows shrink by this amount. `0` disables the footer. Default `0`.
- drawFooter (fun(el, x, y, w, h)) - Footer painter in root-local coordinates.

### Returns
- PallidTable - New table instance; the class is registered as `Pallid.UI.Widgets.Table`, and `Pallid.UI.Widgets.Table.new(...)` takes the same arguments.

### Columns and rows
A column is a plain table; these fields are read:

- key (string) - Row field to display. A column without a key cannot be sorted.
- title (string) - Header label; defaults to `key`.
- width (number) - Fixed width in pixels; omit for a flexible column.
- sortable (boolean) - `false` disables sorting for this column. Default `true`.
- icon (string|Texture|InventoryItem|Item|fun(row, value)) - Icon for every cell in the column.
- iconColor (PallidColor|fun(row, value)) - Shared icon tint or resolver.
- iconSize (number) - Default icon box size; clamped to the row height and column width.
- headerIcon (string|Texture|InventoryItem|Item|false) - Icon before the header title; `false` suppresses it.
- headerIconColor (PallidColor) - Header icon tint.
- headerIconSize (number) - Header icon box size.

Extra fields are copied onto the internal column and preserved, so custom metadata is allowed.

A row is a table keyed by column keys: `row[column.key]` is the cell value. A cell is normally a string, number or boolean. A cell table is treated as a `PallidTableCell` descriptor when it has any of `text`, `label`, `icon`, `iconColor`, `color` or `iconSize`:

- text (string|number) - Primary cell text.
- label (string|number) - Fallback text when `text` is nil.
- icon (string|Texture|InventoryItem|Item|false) - Cell icon; `false` suppresses the column icon.
- iconColor (PallidColor) - Icon tint for textures and registered icons.
- iconSize (number) - Icon box size; clamped to the row height and column width.
- color (PallidColor) - Text colour override.

Row tables must be unique objects: selection and drag payloads use identity.

### Methods
- setRows(rows) - Replaces the data, clears selection and scroll, and rebuilds the view. Returns the table.
- refreshView() - Rebuilds the visible order from `rows` and the active sort. Call it after mutating `rows` in place.
- setSort(key) - Sorts by a column key; the same key toggles direction, nil clears the sort. Fires `onSort`. Returns the table.
- clearSort() - Removes the sort and restores source order. Fires `onSort`. Returns the table.
- getSortKey() - Returns the active sort key, or nil.
- getSortAscending() - Returns true when the sort is ascending.
- setRowSelected(row, selected, silent) - Selects or deselects one row; `silent` skips `onChange`. In `"single"` mode selecting a row clears the previous one.
- isRowSelected(row) - Returns true when the row is selected.
- getSelectedRows() - Returns the selected rows in current view order.
- clearSelection(silent) - Clears the selection; `silent` skips `onChange`. Returns the table.
- setSelectionMode(mode) - Changes the mode; any switch clears the selection, and leaving `"multi"` disables `dragSelect`. Returns the table.
- setRowHeight(height) - Sets the uniform row height and re-runs layout. Returns the table.
- setHeaderHeight(height) - Sets the header height; `0` hides it. Returns the table.
- setColumnWidth(index, width) - Sets a fixed width, or nil for a flexible column; values below 40 px are clamped. Returns the table.
- columnWidth(index) - Returns the resolved width of a column, or 0.
- columnRect(index) - Returns the column's root-local left edge and width.

### Example
```lua
require "pallid/ui/widgets/table"

local rows = {
    { name = "Axe",    weight = 3.0, },
    { name = "Nails",  weight = 0.1, },
}

local tbl = Pallid.UI.Widgets.table(10, 10, 320, 200, {
    { key = "name",   title = "Item", },
    { key = "weight", title = "Weight", width = 90, },
}, rows, {
    selectionMode = "multi",
    onSort = function(_, key, ascending) end,
})

tbl:setSort("name")
tbl:setRowSelected(rows[2], true)
```

### Notes
- There is no `setColumns` and no `getSelected`: columns are copied at construction, and selection is exposed through `getSelectedRows`, `isRowSelected` and the `selected` set keyed by row table.
- The first manual column resize freezes every flexible column at its current width; dragging the table's right edge also turns off `stretchLastColumn` for that table.
- A right-click on the header is consumed without re-sorting, so it cannot fall through to a parent widget.
- `drawChildren` is empty: widgets added to the table are not painted. Wrap the table in a Panel or VBox when other widgets are needed.

## TreeView (Pallid.UI.Widgets.TreeView)

Hierarchical list with expandable branches, indentation, optional tri-state checkboxes and lazy child loading. Rows are flattened in depth-first order and branches animate while opening and closing.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels; nil becomes 0.
- h (number) - Height in pixels; nil becomes 0.
- opts (table|nil) - Content, appearance and behaviour; see below.

### Options
- nodes (PallidTreeNode[]) - Root nodes. Default empty.
- rowHeight (number) - Row height in pixels, at least 1. Default `22`.
- indent (number) - Indent per depth level in pixels. Default `16`.
- barSize (number) - Scrollbar thickness in pixels. Default `10`.
- barGap (number) - Gap between the scrollbar and the edge. Default `3` when the tree is smaller than 80 px on either axis, otherwise `5`.
- background (PallidColor) - Background fill. Default `Color.surface`.
- border (PallidColor) - Border colour. Default `Color.border`.
- iconColor (PallidColor) - Default folder/file icon tint. Default `Color.textMuted`.
- defaultIcons (boolean) - `false` suppresses the default folder/file icons. Default `true`.
- iconSize (number) - Node icon box size; clamped to 10..16. Default `rowHeight - 6`.
- chevronSize (number) - Chevron box size; clamped to 8..12. Default `rowHeight - 10`.
- onSelect (fun(tree, node)) - Called when a row is clicked or selected with Enter.
- onToggle (fun(tree, node)) - Called after a branch is expanded or collapsed, including after a lazy load completes.
- loadChildren (fun(node, done)) - Lazy child loader; called once per node that has no `children` field.
- checkable (boolean) - True draws tri-state checkboxes. Default `false`.

### Returns
- PallidTreeView - New tree view instance; the class is registered as `Pallid.UI.Widgets.TreeView`.

### Node shape
A node is a plain table, so callers keep and mutate it:

- label (string) - Row label.
- children (PallidTreeNode[]|nil) - Child nodes; nil or an empty table makes a leaf.
- expanded (boolean) - True expands the branch when the tree is rebuilt. Default `false`.
- icon (string|false) - Texture path or registered icon name; `false` suppresses the default icon.
- iconColor (PallidColor) - Custom icon tint; nil keeps the texture colours.
- onClick (fun(node)) - Called after the node is selected by a click or Enter.
- checked (boolean|nil) - Tri-state check value; nil is indeterminate.

The tree maintains `_parent`, `_loaded`, `_loading`, `_openT` and `_openFull` on nodes; do not edit them.

### Methods
- setNodes(nodes) - Replaces the roots and clears selection, hover and scroll. Returns the tree.
- expandAll(expanded) - Expands every branch when true, collapses them when false. Returns the tree.
- rebuild() - Re-flattens the rows from `nodes`; call it after mutating `children` or adding nodes. Returns nothing.

### Example
```lua
require "pallid/ui/widgets/treeview"

local tree = Pallid.UI.Widgets.treeView(10, 10, 260, 300, {
    nodes = {
        { label = "Loot", expanded = true, children = {
            { label = "Kitchen", },
            { label = "Garage", },
        }, },
    },
    onSelect = function(_, node) end,
})

tree:expandAll(true)
```

### Notes
- There is no public API to expand, collapse or select a single node. Set `node.expanded = true` and call `rebuild()`, or assign the `selected` field; `_toggleNode` is private.
- Clicking a checkbox cycles the node through true, false and nil, applies the new state to all descendants, then recomputes ancestors: all children equal gives that value, a mixed set gives nil.
- `loadChildren(node, done)` must call `done(children)`; a loader error is logged with `Pallid.error` and the node stays collapsed.
- Row labels are read on every draw, so changing `node.label` needs no rebuild.

## VirtualList (Pallid.UI.Widgets.VirtualList)

Virtualised list leaf that draws and hit-tests only the rows intersecting the viewport. Rows have no child widgets; the caller paints each row through `render`.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels; nil becomes 0.
- h (number) - Height in pixels; nil becomes 0.
- opts (table|nil) - Content and behaviour; see below.

### Options
- itemCount (number) - Number of rows, at least 0. Default `0`.
- rowHeight (number|fun(index)) - Uniform height in pixels, or a resolver per one-based index. Default `22`.
- render (fun(el, index, x, y, w, h, state)) - Row painter; `index` is one-based and `x`/`y` are root-local.
- selectionMode ("single"|"multi"|"none") - Selection model; an unknown value falls back to `"single"`. Default `"single"`.
- onSelect (fun(list, index)) - Called after the selection changes; `index` is nil when cleared.
- background (PallidColor) - Optional list fill. Default nil.
- border (PallidColor) - Optional list outline. Default nil.
- radius (number) - Corner radius. Default `0`.
- barSize (number) - Scrollbar thickness in pixels. Default `10`.
- barGap (number) - Gap between the scrollbar and the edge. Default `3` when the list is smaller than 80 px on either axis, otherwise `5`.

### Returns
- PallidVirtualList - New virtual list; the class is registered as `Pallid.UI.Widgets.VirtualList`.

### Row state
`render` receives one table that is reused for every row and every frame:

- index (number) - One-based row index.
- hovered (boolean) - True when the cursor is over the row.
- selected (boolean) - True when the row is selected.

### Methods
- setItemCount(count) - Sets the row count and rebuilds the offset cache. Returns the list.
- refresh() - Rebuilds the offset cache and scroll range; call it after changing a function `rowHeight` or the row heights it returns. Returns the list.
- scrollTo(y) - Scrolls to a content-space offset, clamped to the list range. Returns the list.
- getScroll() - Returns the current scroll offset in pixels.
- setSelected(index, silent) - Replaces the selection; nil clears it and out-of-range indexes become nil. `silent` skips `onSelect`. Returns the list.
- isSelected(index) - Returns true when the row is selected.
- indexAt(py) - Returns the row index under a root-local Y coordinate, or 0.
- rowOffset(index) - Returns the content-space top offset of a row.

### Example
```lua
require "pallid/ui/widgets/virtuallist"

local style = {
    font   = Pallid.UI.Fonts.small,
    color  = Pallid.UI.Color.text,
    alignV = "middle",
}

local list = Pallid.UI.Widgets.virtualList(10, 10, 300, 240, {
    itemCount = 500,
    render = function(el, index, x, y, w, h, state)
        Pallid.UI.text(el, "Row " .. index, x + 6, y + h * 0.5, style)
    end,
})

list:setItemCount(600)
list:scrollTo(0)
```

### Notes
- The `state` table is reused: read it inside `render` and never keep a reference to it.
- A function `rowHeight` is cached as prefix sums; without `refresh()` the scroll range and hit testing use stale offsets.
- Multi selection is only produced by Ctrl+click. `setSelected` always replaces the whole selection, even in `"multi"` mode.
- There is no `getSelected`: read the `selected` index, or call `isSelected(i)` for multi mode.

## ReorderableList (Pallid.UI.Widgets.ReorderableList)

Table whose rows can be reordered by dragging a grip gutter, including drags between lists. It subclasses `PallidTable`, so columns, sorting, resizing, selection and scrollbars behave like the table.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels; nil becomes 0.
- h (number) - Height in pixels; nil becomes 0.
- columns (PallidTableColumn[]) - Column descriptors, identical to the table.
- rows (table[]|nil) - Row records; must be unique tables.
- opts (table|nil) - Table options plus the fields below.

### Options
- leadWidth (number) - Grip gutter width in pixels. Default `22`.
- handleIcon (string|false) - Grip icon; a texture path or registered icon name. Default `menu-07.png`, `false` draws no grip.
- handleSize (number) - Grip icon box size, at least 6. Default `14`.
- handleColor (PallidColor) - Idle grip tint. Default `Color.textMuted`.
- handleHoverColor (PallidColor) - Hovered grip tint. Default `Color.primaryStrong`.
- dragKind (string) - Payload kind. Default `"reorder"`.
- dragGroup (string) - Lists exchange rows only within the same group. Default `"default"`.
- dragLabel (fun(row)) - Ghost label resolver; falls back to `row[labelKey]`.
- labelKey (string) - Row key used for the ghost label. Default `"name"`.
- iconKey (string) - Row key used for the ghost icon. Default `"icon"`.
- dragIcon (fun(row)) - Ghost icon resolver, used when `row[iconKey]` is nil.
- dragThreshold (number) - Pointer movement in pixels before a drag starts, at least 1. Default `4`.
- clearSortOnDrag (boolean) - Clears the active sort when a drag starts. Default `true`.
- autoScrollEdge (number) - Edge zone in pixels for drag auto-scroll. Default `24`.
- autoScrollSpeed (number) - Auto-scroll speed in pixels per second. Default `420`.
- insertionColor (PallidColor) - Insertion line colour. Default `Color.accent`.
- onReorder (fun(rows, from, to)) - Called after rows move; `from` is 0 for an external insert.
- onTransferIn (fun(list, rows, index, source)) - Called when rows arrive from another list.
- onTransferOut (fun(list, rows, target)) - Called when this list's rows are dropped elsewhere.

The constructor also applies table defaults when the caller omits them: `selectionMode = "multi"`, `rowHeight = 28` and `headerHeight = 26`. All other table options are accepted.

### Returns
- PallidReorderableList - New list; the class is registered as `Pallid.UI.Widgets.ReorderableList` and inherits `PallidTable`.

### Methods
- setRows(rows) - Replaces the rows, cancels an active drag and clears drag state. Returns the list.
- addRow(row) - Appends one row and rebuilds the view; non-table values are ignored. Returns the list.
- removeRow(rowOrIndex) - Removes a row by table identity or one-based index and returns the removed row, or nil.
- moveRow(from, to) - Moves a row between one-based positions and fires `onReorder`. Returns the list.
- scrollToRow(index) - Scrolls the minimum amount needed to show a view index. Returns the list.
- viewIndexOf(row) - Returns the one-based index of a row in the current view, or 0.
- canSelectRow(row) - Returns false for rows with `disabled = true`; overrides the table behaviour.

### Example
```lua
require "pallid/ui/widgets/reorderablelist"

local list = Pallid.UI.Widgets.reorderableList(10, 10, 320, 260, {
    { key = "name", title = "Name", },
}, {
    { name = "First",  },
    { name = "Second", },
}, {
    onReorder = function(rows, from, to) end,
})

list:moveRow(1, 2)
```

### Notes
- `onReorder` is called as `onReorder(rows, from, to)`: there is no list argument, despite the EmmyLua annotation on the class and option. `rows` is the live `self.rows` array.
- Starting a drag clears the active sort unless `clearSortOnDrag = false`; a sorted view has no meaningful manual order.
- Cross-list transfer requires both lists to share `dragKind` and `dragGroup`, and the source row objects are moved, not copied.
- A row with `disabled = true` is not selectable, not draggable and is skipped when a block drag collects selected rows.

## PropertyGrid (Pallid.UI.Widgets.PropertyGrid)

Property inspector and settings grid. Each property is a row with a label and an editor chosen by `type`, placed in a scroll panel and optionally filtered by a search field.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels; nil becomes 0.
- h (number) - Height in pixels; nil becomes 0.
- opts (table|nil) - Properties and appearance; see below.

### Options
- properties (table[]) - Property descriptors. Default empty.
- showSearch (boolean) - Draws the search field. Default `true`.
- searchPlaceholder (string) - Search placeholder. Default the translated `UI_Pallid_Search` string.
- showReset (boolean) - Draws a reset button that calls `reset()`. Default `false`.
- labelWidth (number) - Label column width, at least 60. Default `150`.
- rowHeight (number) - Row height, at least 20. Default `28`.
- groupHeight (number) - Group header height, at least 16. Default `22`.
- striped (boolean) - Alternating row fills. Default `false`.
- onChange (fun(grid, key, value, property)) - Called after a value changes.

### Returns
- PallidPropertyGrid - New grid; the class is registered as `Pallid.UI.Widgets.PropertyGrid`.

### Property shape
A property is a plain table stored by reference:

- key (string) - Unique key used by `values`, `getValue` and `setValue`.
- label (string) - Row label; defaults to `key`.
- group (string) - Optional group header shown before the first property of that group.
- type (string) - Editor kind: `"text"` (default), `"boolean"`, `"number"` or `"select"`.
- value (any) - Current value.
- default (any) - Reset value; filled from `value` when omitted.
- options (any[]) - Select options, used when `type = "select"`.
- placeholder (string) - Select placeholder.
- readOnly (boolean) - Makes a text or number editor read-only.
- onChange (fun(grid, value, property)) - Per-property change callback, called after the grid callback.

### Methods
- setProperties(properties) - Replaces the descriptors, resets `values` and rebuilds the rows. Returns the grid.
- getValue(key) - Returns the current value, or nil for an unknown key.
- setValue(key, value, silent) - Sets a value, optionally fires `onChange`, and rebuilds every row editor. Returns the grid.
- getValues() - Returns the live value map keyed by property key.
- reset(silent) - Restores every property to `default` and rebuilds; without `silent` it fires `onChange(grid, nil, nil, nil)` once. Returns the grid.
- setBounds(x, y, w, h) - Resizes the search field, scroll panel and reset button, then rebuilds. Returns the grid.

### Example
```lua
require "pallid/ui/widgets/propertygrid"

local grid = Pallid.UI.Widgets.propertyGrid(10, 10, 360, 320, {
    properties = {
        { key = "volume", label = "Volume", type = "number",  value = 50,    group = "Audio", },
        { key = "mute",   label = "Mute",   type = "boolean", value = false, group = "Audio", },
        { key = "mode",   label = "Mode",   type = "select",  value = "A",   options = { "A", "B", }, },
    },
    onChange = function(_, key, value) end,
})

grid:setValue("volume", 80)
```

### Notes
- `setProperties` stores the caller's descriptor tables and writes `property.default = property.value` when `default` is nil, so the input tables are mutated.
- Every `setValue` and `setBounds` recreates all editor widgets; the search field focus is restored, but text editors lose their transient state.
- The search filter matches `label` and `key` with a case-insensitive substring test.
- `type = "select"` uses the shared combo box; `options` values are passed through unchanged.

## QueryBuilder (Pallid.UI.Widgets.QueryBuilder)

Rule builder with rows of field, operator and value joined by AND or OR. It is a UI composite, not a query parser: callers receive the rule list and apply their own filtering.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels; nil becomes 0.
- h (number|nil) - Height in pixels; nil or 0 fits the current rows.
- opts (table|nil) - Fields and initial rules; see below.

### Options
- fields (table[]) - Field descriptors; see below. Default empty.
- rules (table[]) - Initial rules; each is copied. Default empty.
- combinator ("and"|"or") - Initial join mode; any other value becomes `"and"`. Default `"and"`.
- autoHeight (boolean) - Fits the height to the row stack. Default `false`, but always enabled when `h` is nil or 0.
- onChange (fun(builder, rules, combinator)) - Called after the rules or the join mode change.

### Returns
- PallidQueryBuilder - New builder; the class is registered as `Pallid.UI.Widgets.QueryBuilder`.

### Field and rule shape
A field descriptor:

- key (string) - Field key stored in `rule.field`.
- label (string) - Label shown in the field selector; defaults to `key`.
- type (string) - `"text"` (default), `"number"` or `"select"`.
- options (any[]) - Value choices when `type = "select"`.
- operators (table[]) - Explicit operator list, either strings or `{ key, label }` tables; overrides the type defaults.

A rule is `{ field = key, op = string, value = any }`. Without an explicit `op`, the default depends on the field type: `"eq"` for numbers, `"is"` for selects, otherwise `"contains"`.

### Methods
- setRules(rules, silent) - Replaces the rules with copies and rebuilds; `silent` skips `onChange`. Returns the builder.
- getRules() - Returns the live rule list.
- addRule(silent) - Appends an empty rule using the first field; does nothing when `fields` is empty. Returns the builder.
- removeRule(index, silent) - Removes a one-based rule index. Returns the builder.
- setCombinator(combinator, silent) - Sets `"and"` or `"or"` and fires `onChange`. Returns the builder.
- setBounds(x, y, w, h) - Resizes and rebuilds; `h` of nil or 0 re-enables automatic height. Returns the builder.

### Example
```lua
require "pallid/ui/widgets/querybuilder"

local builder = Pallid.UI.Widgets.queryBuilder(10, 10, 420, 0, {
    fields = {
        { key = "name",   label = "Name", },
        { key = "weight", label = "Weight", type = "number", },
    },
    onChange = function(_, rules, combinator) end,
})

builder:addRule()
```

### Notes
- `setCombinator` does not rebuild the rows, so the AND/OR combo box keeps its previous label until the next rebuild (`addRule`, `removeRule`, `setRules`, a field change or `setBounds`). The `combinator` field and emitted rules are updated immediately.
- `setRules` copies the rule tables; `getRules` returns the live internal list. Mutating that list changes what `onChange` reports, but the row controls are only refreshed by the next rebuild.
- Changing a rule's field resets its operator to the type default and clears its value; that rebuild is deferred to the next update.
- Editing a value or operator does not rebuild the rows, only emits the change.
- There is no `getCombinator`; read the `combinator` field.
