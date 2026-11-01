# Layout and container widgets

`Pallid.UI.Widgets` provides eight client-side containers for building Pallid UI trees: `window`, `panel`, `groupBox`, `hbox`, `vbox`, `grid`, `stack` and `flow`. Every factory returns a widget that is attached to a parent with `add`; the shared tree API (`add`, `remove`, `setBounds`, `setVisible`, `setEnabled`, `setTooltip`, `preferredSize`) is documented in [ui-widget.md](ui-widget.md).

## Widgets.Window

Floating panel with a title bar, close/collapse/pin caption buttons, a resize grip and padded, clipped content. Dragging the title bar moves the window; the bottom-right grip resizes it.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels when fully open.
- opts (table|nil) - Optional appearance and callbacks.
    - opts.title (string) - Window title; defaults to `"Window"`.
    - opts.closable (boolean) - Draws the close button; only `false` disables it.
    - opts.resizable (boolean) - Allows resizing from the grip; only `false` disables it.
    - opts.pinned (boolean) - Starts pinned: title bar only, expands while the cursor is inside; defaults to `false`.
    - opts.collapsed (boolean) - Starts collapsed to the title bar; defaults to `false`.
    - opts.padding (number) - Content inset below the title bar, in pixels; defaults to `4`.
    - opts.onClose (fun(window: PallidWindow)|nil) - Called after `close()` hides the window.
    - opts.onMoved (fun(window: PallidWindow)|nil) - Called on every drag move.
    - opts.onResized (fun(window: PallidWindow)|nil) - Called on every resize move.

### Returns
- PallidWindow - The new window, registered as `Widgets.Window` (`className = "Window"`).

### Example
```lua
local window = Pallid.UI.Widgets.window(100, 80, 320, 220, {
    title   = "Inventory",
    padding = 8,
})

window:add(Pallid.UI.Widgets.button(0, 0, 120, 28, { text = "Take all" }))

local host = Pallid.UI.Host:new()
host:setRoot(window)
host:addToUIManager()
```

### Notes
- Children are positioned relative to the padded content origin below the 26 px title bar, not the window origin: a child at `(0, 0)` sits in the inner top-left corner.
- Content is clipped to the visible box and is not drawn while the window is collapsed or pinned shut.
- The window never sizes itself from its children; `h` is the fully open height and `titleH` is fixed at 26.
- `close()` only hides the window (`visible = false`) and fires `onClose`; the widget stays in the tree, so `setVisible(true)` shows it again.
- Resizing clamps to `minW` (120) and `minH` (80). The grip is unavailable while pinned.
- Appearance is controlled by assignable fields: `fill`, `titleFill`, `titleFillHover`, `borderColor`, `titleColor`, `closeColor`, `collapseColor`, `pinColor`, `buttonActive`, `gripColor`.
- The title is truncated so it never runs under the caption buttons.

## Window:close()

Hides the window and calls `onClose` when one was supplied.

**Side:** client

## Window:toggleCollapsed()

Flips the explicit collapsed state. Does nothing while the window is pinned.

**Side:** client

## Window:togglePinned()

Flips the pinned state. Unpinning snaps the window to its explicit `collapsed` state (fully open unless `collapsed` is true).

**Side:** client

## Window:isOpen()

Returns whether the window is at least half open, based on the animated height.

**Side:** client

### Returns
- boolean - `true` when `effectiveHeight() > titleH + 0.5`.

## Window:effectiveHeight()

Returns the height currently drawn, interpolated between the title bar and `h` by the open animation.

**Side:** client

### Returns
- number - Drawn height in pixels.

## Window:contentSize()

Returns the space available to children below the title bar, excluding the padding.

**Side:** client

### Returns
- number w - Inner width in pixels.
- number h - Inner height in pixels.

### Notes
- Uses the fully open `h`, so the result does not change while the window is collapsed or mid-animation.

## Window:bringToTop()

Moves the window to the end of its parent's child list, so it draws and hit-tests above its siblings.

**Side:** client

## Widgets.Panel

Plain container that paints an optional background and border. Children are positioned relative to its top-left corner.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Optional appearance.
    - opts.background (PallidColor|nil) - Fill color; `nil` leaves the panel transparent. Copied into `fill`.
    - opts.border (PallidColor|nil) - Border color; `nil` draws no border. Copied into `borderColor`.
    - opts.borderWidth (number) - Border thickness; defaults to `1` when `opts.border` is set, otherwise `0`.
    - opts.radius (number|table) - Corner radius: a number for all corners or `{tl, tr, br, bl}`; defaults to `0`.
    - opts.fillInset (number) - Inset applied to the fill inside the border; defaults to `0`.

### Returns
- PallidPanel - The new panel, registered as `Widgets.Panel` (`className = "Panel"`).

### Example
```lua
local card = Pallid.UI.Widgets.panel(0, 0, 240, 120, {
    background  = Pallid.UI.Color.surface,
    border      = Pallid.UI.Color.border,
    borderWidth = 1,
    radius      = 6,
})

card:add(Pallid.UI.Widgets.button(12, 12, 120, 28, { text = "Apply" }))
```

### Notes
- The panel has no public methods of its own; use the base tree API from [ui-widget.md](ui-widget.md).
- Option names differ from the fields they fill: `opts.background` becomes `panel.fill`, `opts.border` becomes `panel.borderColor`.
- `opts.borderWidth` is only read when `opts.border` is set; a width without a border is ignored and `borderWidth` stays `0`.
- Colors are copied into new tables, so changing the table passed to the constructor afterwards does not affect the panel.
- `fillInset` shrinks the fill rectangle and reduces a numeric `radius` by the same amount, so the antialiased fill stays inside the border.
- Setting `panel.hittable = false` (a base widget field) lets hover and presses pass through to widgets behind the panel.

## Widgets.GroupBox

Frame around related widgets with the title sitting on the top border. Children are positioned relative to the padded content area.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- title (string) - Title text drawn on the top border; defaults to `""`.
- opts (table|nil) - Optional appearance.
    - opts.background (PallidColor|nil) - Frame fill; no fill by default.
    - opts.border (PallidColor) - Frame border color; defaults to `Pallid.UI.Color.border`.
    - opts.radius (number) - Corner radius; defaults to `6`.
    - opts.titleBackground (PallidColor) - Patch drawn behind the title; defaults to `Pallid.UI.Color.surface`.

### Returns
- PallidGroupBox - The new group box, registered as `Widgets.GroupBox` (`className = "GroupBox"`).

### Example
```lua
local group = Pallid.UI.Widgets.groupBox(0, 0, 280, 140, "Options", {
    border = Pallid.UI.Color.border,
    radius = 6,
})

group:add(Pallid.UI.Widgets.button(0, 0, 120, 28, { text = "Apply" }))
```

### Notes
- `title` is the fifth positional argument, not an option.
- Children are offset by 10 px from the left and 18 px from the top (the title line), so a child at `(0, 0)` sits in the padded content area, not the frame corner.
- Content is clipped to the content rectangle, which is `w - 20` wide and `h - 19` high.
- Only the content rectangle accepts input: presses and hovers on the frame or title do not reach the group box.
- `opts.titleBackground` alpha is forced to `1` so the border line is fully interrupted behind the title.
- The group box has no public methods of its own; use the base tree API from [ui-widget.md](ui-widget.md).

## Widgets.HBox

Invisible container that lays children out in one row, left to right, with equal spacing. Fixed children keep their own width; children with a `weight` share the leftover width.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels; the space distributed between children.
- h (number) - Height in pixels; children are stretched to the inner height by default.
- opts (table|nil) - Optional layout metrics.
    - opts.padding (number) - Inner inset on every side; defaults to `0`.
    - opts.spacing (number) - Gap between neighbouring children; defaults to `4`.
    - opts.align ("stretch"|"start"|"center"|"end") - Cross-axis placement; defaults to `"stretch"`.
    - opts.autoSize (boolean) - Fits both axes to the children; defaults to `false`.
    - opts.autoWidth (boolean) - Fits only the width to the children; defaults to `false`.
    - opts.autoHeight (boolean) - Fits only the height to the tallest child; defaults to `false`.

### Returns
- PallidHBox - The new box, registered as `Widgets.HBox` (`className = "HBox"`).

### Example
```lua
local row = Pallid.UI.Widgets.hbox(0, 0, 320, 40, { spacing = 8, align = "center" })

row:add(Pallid.UI.Widgets.button(0, 0, 100, 28, { text = "OK" }))
row:add(Pallid.UI.Widgets.spacer(1))
row:add(Pallid.UI.Widgets.button(0, 0, 100, 28, { text = "Cancel" }))
```

### Notes
- Layout is explicit: it runs on `add`, `remove` and `setBounds`, and when you call `layout()` yourself. It does not re-run after a child changes size.
- Weighted children are recognised by a non-nil `child.weight`; set it before adding, or use `Widgets.spacer(weight)`.
- `weight` replaces the child's width entirely; the child's `w` is ignored for weighted children.
- Leftover space is clamped to zero, so fixed children that do not fit keep their width and overflow the box instead of shrinking.
- `"stretch"` overrides each child's height; the other alignments clamp `child.h` to the inner height and position it on the cross axis.
- Hidden children still occupy their slot.
- `autoWidth` sums the children's current `w`, including weighted children whose laid-out width differs.

## HBox:add(child)

Attaches a child and re-runs the layout.

**Side:** client

### Parameters
- child (PallidWidget) - Widget to attach.

### Returns
- PallidWidget - The same widget, for chaining.

## HBox:remove(child)

Detaches a child and re-runs the layout so the freed space is reclaimed.

**Side:** client

### Parameters
- child (PallidWidget) - Widget to detach.

## HBox:setBounds(x, y, w, h)

Moves and resizes the box, then re-runs the layout.

**Side:** client

### Parameters
- x (number) - New offset X from the parent's origin.
- y (number) - New offset Y from the parent's origin.
- w (number) - New width in pixels.
- h (number) - New height in pixels.

### Returns
- PallidHBox - `self`, for chaining.

## HBox:layout()

Places the children from left to right: fixed widths first, then the leftover width split between weighted children. Call it after changing a child size.

**Side:** client

### Notes
- `padding`, `spacing`, `align`, `autoWidth` and `autoHeight` are plain fields; change them and call `layout()` again. There are no setters.

## Widgets.VBox

Invisible container that stacks children vertically with equal spacing. Fixed children keep their own height; children with a `weight` share the leftover height.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels; children are stretched to the inner width by default.
- h (number) - Height in pixels; the space distributed between children.
- opts (table|nil) - Optional layout metrics.
    - opts.padding (number) - Inner inset on every side; defaults to `0`.
    - opts.spacing (number) - Gap between neighbouring children; defaults to `4`.
    - opts.align ("stretch"|"start"|"center"|"end") - Cross-axis placement; defaults to `"stretch"`.
    - opts.autoSize (boolean) - Fits both axes to the children; defaults to `false`.
    - opts.autoWidth (boolean) - Fits only the width to the widest child; defaults to `false`.
    - opts.autoHeight (boolean) - Fits only the height to the children; defaults to `false`.

### Returns
- PallidVBox - The new box, registered as `Widgets.VBox` (`className = "VBox"`).

### Example
```lua
local column = Pallid.UI.Widgets.vbox(0, 0, 200, 160, { spacing = 6, padding = 8 })

column:add(Pallid.UI.Widgets.button(0, 0, 0, 30, { text = "First" }))
column:add(Pallid.UI.Widgets.button(0, 0, 0, 30, { text = "Second" }))
```

### Notes
- Layout is explicit: it runs on `add`, `remove` and `setBounds`, and when you call `layout()` yourself. It does not re-run after a child changes size.
- Weighted children are recognised by a non-nil `child.weight`; set it before adding, or use `Widgets.spacer(weight)`.
- `weight` replaces the child's height entirely; the child's `h` is ignored for weighted children.
- Leftover space is clamped to zero, so fixed children that do not fit keep their height and overflow the box instead of shrinking.
- `"stretch"` overrides each child's width; the other alignments clamp `child.w` to the inner width and position it on the cross axis.
- Hidden children still occupy their slot.
- `autoHeight` sums the children's current `h`, including weighted children whose laid-out height differs.

## VBox:add(child)

Attaches a child and re-runs the layout.

**Side:** client

### Parameters
- child (PallidWidget) - Widget to attach.

### Returns
- PallidWidget - The same widget, for chaining.

## VBox:remove(child)

Detaches a child and re-runs the layout so the freed space is reclaimed.

**Side:** client

### Parameters
- child (PallidWidget) - Widget to detach.

## VBox:setBounds(x, y, w, h)

Moves and resizes the box, then re-runs the layout.

**Side:** client

### Parameters
- x (number) - New offset X from the parent's origin.
- y (number) - New offset Y from the parent's origin.
- w (number) - New width in pixels.
- h (number) - New height in pixels.

### Returns
- PallidVBox - `self`, for chaining.

## VBox:layout()

Places the children from top to bottom: fixed heights first, then the leftover height split between weighted children. Call it after changing a child size.

**Side:** client

### Notes
- `padding`, `spacing`, `align`, `autoWidth` and `autoHeight` are plain fields; change them and call `layout()` again. There are no setters.

## Widgets.Grid

Invisible fixed-column grid. Cells are filled row by row; `cellW`/`cellH` can force a cell size, otherwise the grid divides its own box evenly.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- columns (integer) - Column count; values below `1` are clamped to `1` and floored.
- opts (table|nil) - Optional layout metrics.
    - opts.padding (number) - Inner inset on every side; defaults to `0`.
    - opts.gap (number) - Gap between cells in both axes; defaults to `4`.
    - opts.cellW (number|nil) - Forced cell width; `nil` divides the box width.
    - opts.cellH (number|nil) - Forced cell height; `nil` divides the box height by the row count.
    - opts.align ("stretch"|"start"|"center"|"end") - Placement on both axes; defaults to `"stretch"`.
    - opts.alignH ("stretch"|"start"|"center"|"end") - Horizontal placement; overrides `opts.align`.
    - opts.alignV ("stretch"|"start"|"center"|"end") - Vertical placement; overrides `opts.align`.
    - opts.autoSize (boolean) - Fits both axes to the cells; defaults to `false`.
    - opts.autoWidth (boolean) - Fits only the width; defaults to `false`.
    - opts.autoHeight (boolean) - Fits only the height; defaults to `false`.

### Returns
- PallidGrid - The new grid, registered as `Widgets.Grid` (`className = "Grid"`).

### Example
```lua
local grid = Pallid.UI.Widgets.grid(0, 0, 320, 160, 3, { gap = 6 })

grid:add(Pallid.UI.Widgets.button(0, 0, 0, 0, { text = "A" }))
grid:add(Pallid.UI.Widgets.button(0, 0, 0, 0, { text = "B" }))
grid:add(Pallid.UI.Widgets.button(0, 0, 0, 0, { text = "C" }))
```

### Notes
- There is no `setColumns`: `columns` is a public field. Assign it and call `layout()`, which re-clamps the value.
- The row count is derived as `ceil(childCount / columns)`, so a partial last row still reserves a full cell height.
- Forced `cellW`/`cellH` can overflow the grid box; the grid does not clip its children.
- `"stretch"` overrides each child's size in that axis; the other alignments keep the child's own size, clamped to the cell, and position it inside the cell.
- Layout is explicit: it runs on `add`, `remove` and `setBounds`, and when you call `layout()` yourself.

## Grid:add(child)

Attaches a child and re-runs the layout.

**Side:** client

### Parameters
- child (PallidWidget) - Widget to attach.

### Returns
- PallidWidget - The same widget, for chaining.

## Grid:remove(child)

Detaches a child and re-runs the layout so the cells reflow.

**Side:** client

### Parameters
- child (PallidWidget) - Widget to detach.

## Grid:setBounds(x, y, w, h)

Moves and resizes the grid, then re-runs the layout.

**Side:** client

### Parameters
- x (number) - New offset X from the parent's origin.
- y (number) - New offset Y from the parent's origin.
- w (number) - New width in pixels.
- h (number) - New height in pixels.

### Returns
- PallidGrid - `self`, for chaining.

## Grid:layout()

Places the children row by row using the current `columns`, `gap`, `padding` and alignment fields.

**Side:** client

## Widgets.Stack

Invisible z-order container. Children keep their own bounds and draw in insertion order, so later children sit on top.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Optional overlay behaviour.
    - opts.padding (number) - Inner inset used by `fill` and `autoSize`; defaults to `0` and is clamped to `>= 0`.
    - opts.fill (boolean) - Stretches every child to the padded box; defaults to `false`.
    - opts.autoSize (boolean) - Grows the container to its children; defaults to `false`.

### Returns
- PallidStack - The new stack, registered as `Widgets.Stack` (`className = "Stack"`).

### Example
```lua
local stack = Pallid.UI.Widgets.stack(0, 0, 120, 80)

stack:add(Pallid.UI.Widgets.panel(0, 0, 120, 80, { background = Pallid.UI.Color.surface }))
stack:add(Pallid.UI.Widgets.panel(8, 8, 32, 32, { background = Pallid.UI.Color.primary }))
```

### Notes
- Without `fill`, the stack never moves or resizes its children; set their bounds yourself.
- `fill` resets every child to `(padding, padding)` with the padded box size, which makes the stack a full-size overlay layer.
- `autoSize` measures `child.x + child.w` and `child.y + child.h`, then sets `w = maxX + padding` and `h = maxY + padding` — padding is added once, not on both sides.
- Layout runs on `add`, `remove`, `setBounds` and an explicit `layout()` call.

## Stack:add(child)

Attaches a child and applies the stack layout.

**Side:** client

### Parameters
- child (PallidWidget) - Widget to attach.

### Returns
- PallidWidget - The same widget, for chaining.

## Stack:remove(child)

Detaches a child and refreshes an auto-sized box.

**Side:** client

### Parameters
- child (PallidWidget) - Widget to detach.

## Stack:setBounds(x, y, w, h)

Moves and resizes the stack, then re-runs the layout.

**Side:** client

### Parameters
- x (number) - New offset X from the parent's origin.
- y (number) - New offset Y from the parent's origin.
- w (number) - New width in pixels.
- h (number) - New height in pixels.

### Returns
- PallidStack - `self`, for chaining.

## Stack:layout()

Applies the `fill` and `autoSize` behaviour to the children.

**Side:** client

## Widgets.Flow

Wrapping layout container. Children keep their own sizes and flow left to right; a child that does not fit starts a new row.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels; the wrap limit.
- h (number|nil) - Height in pixels; `nil` or `0` grows the height to the content.
- opts (table|nil) - Optional layout metrics.
    - opts.padding (number) - Inner inset on every side; defaults to `0` and is clamped to `>= 0`.
    - opts.gapX (number) - Horizontal gap between children; defaults to `4` and is clamped to `>= 0`.
    - opts.gapY (number) - Vertical gap between rows; defaults to `4` and is clamped to `>= 0`.
    - opts.align ("start"|"center"|"end") - Horizontal placement of each row; defaults to `"start"`.
    - opts.autoHeight (boolean) - Fits the height to the content; implied when `h` is `nil` or `<= 0`.

### Returns
- PallidFlow - The new flow container, registered as `Widgets.Flow` (`className = "Flow"`).

### Example
```lua
local tags = Pallid.UI.Widgets.flow(0, 0, 240, nil, { gapX = 6, gapY = 6 })

tags:add(Pallid.UI.Widgets.button(0, 0, 80, 24, { text = "One" }))
tags:add(Pallid.UI.Widgets.button(0, 0, 90, 24, { text = "Two" }))
```

### Notes
- Flow never stretches a child; only the row origin follows `align`.
- A child wider than the inner width starts its own row and overflows; the container does not clip.
- Child size comes from `child:preferredSize(innerWidth, nil)`, falling back to the child's current `w`/`h` when the preferred value is `0` or less.
- `autoHeight` cannot be switched off: once enabled by a `nil`/`0` height it stays on, so `setBounds` with a positive `h` is overridden by the content height on the next layout.
- Layout runs on `add`, `remove`, `setBounds` and an explicit `layout()` call.

## Flow:add(child)

Attaches a child and re-runs the layout.

**Side:** client

### Parameters
- child (PallidWidget) - Widget to attach.

### Returns
- PallidWidget - The same widget, for chaining.

## Flow:remove(child)

Detaches a child and re-runs the layout.

**Side:** client

### Parameters
- child (PallidWidget) - Widget to detach.

## Flow:setBounds(x, y, w, h)

Moves and resizes the flow, then re-runs the layout. A `nil` or `<= 0` height keeps the automatic height.

**Side:** client

### Parameters
- x (number) - New offset X from the parent's origin.
- y (number) - New offset Y from the parent's origin.
- w (number) - New width in pixels; the new wrap limit.
- h (number|nil) - New height in pixels; `nil` or `0` keeps the automatic height.

### Returns
- PallidFlow - `self`, for chaining.

## Flow:layout()

Places the children in wrapping rows, updates `preferredHeight` and applies the automatic height when enabled.

**Side:** client

## Flow:preferredSize(maxW, maxH)

Returns the height the current children need at a given width, without changing the widget.

**Side:** client

### Parameters
- maxW (number|nil) - Available width; `nil` uses the current width.
- maxH (number|nil) - Unused.

### Returns
- number - The measured width (the given `maxW`, or the current `w`).
- number - The content height in pixels.
