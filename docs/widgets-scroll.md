# Scroll and layout widgets

The scroll and layout helpers: a draggable two-pane splitter, a clipped scrolling viewport, a standalone scrollbar, and three small layout primitives. Every factory returns a widget that is added to the tree with the base API; see [ui-widget.md](ui-widget.md) for `add`/`remove`, bounds, visibility and input routing.

All factories live on `Pallid.UI.Widgets` and require their own file, for example `require "pallid/ui/widgets/scrollpanel"`.

## SplitPanel

`Pallid.UI.Widgets.splitPanel(x, y, w, h, opts)` creates a `PallidSplitPanel` (class `SplitPanel`) holding two panels separated by a draggable divider.

**Side:** client

### Parameters
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts.orientation ("horizontal"|"vertical", default "horizontal") - `"horizontal"` places the panes side by side, `"vertical"` stacks them.
- opts.ratio (number, default 0.5) - First pane share of the space left after the divider, 0..1.
- opts.minFirst (number, default 40) - Minimum first pane size in pixels, clamped to >= 0.
- opts.minSecond (number, default 40) - Minimum second pane size in pixels, clamped to >= 0.
- opts.divider (number, default 6) - Divider thickness in pixels, clamped to >= 0.
- opts.background (PallidColor|nil) - Fill color passed to both panes; nil leaves them transparent.
- opts.onChange (fun(panel: PallidSplitPanel, ratio: number)|nil) - Called with the clamped ratio after a change.

### Returns
- PallidSplitPanel - The new split panel.

### Methods
- `setRatio(ratio)` - Sets the first-pane ratio, re-lays out and calls `onChange`; returns the panel for chaining.
- `sync()` - Recomputes both pane rectangles and clamps the ratio. Runs automatically from draw and update.
- `dividerRect()` - Returns `x, y, w, h` of the divider in root-local coordinates.
- `isOnDivider(px, py)` - Returns true when a root-local point hits the divider, including a 2 px margin on each side.

### Example
```lua
require "pallid/ui/widgets/splitpanel"
require "pallid/ui/widgets/panel"

local Widgets = Pallid.UI.Widgets
local Color = Pallid.UI.Color

local split = Widgets.splitPanel(0, 0, 600, 400, {
    orientation = "horizontal",
    ratio       = 0.6,
    minFirst    = 120,
    minSecond   = 160,
    background  = Color.surface,
    onChange    = function(panel, ratio)
        -- ratio is already clamped to the pane minimums
    end,
})

split.first:add(Widgets.panel(0, 0, 100, 100, { background = Color.surfaceMuted }))
split.second:add(Widgets.panel(0, 0, 100, 100, { background = Color.background }))
```

### Notes
- `first` and `second` are owned panes, not tree children. Fill them with `split.first:add(...)`; `split:add(...)` attaches an unrelated child that neither pane lays out or clips.
- Each pane is clipped to its own rectangle, so overflowing content is cut at the divider.
- Only `"vertical"` is treated as vertical; any other value, including nil, means horizontal.
- `minFirst` and `minSecond` are clamped to the available space, so both cannot always be honoured; `minSecond` wins when the panel is too small.
- `onChange` fires from `setRatio` and on every drag move, but not when `sync` clamps the ratio.
- Pane rectangles are recomputed during draw and update. After changing `divider`, `minFirst` or `minSecond` at runtime, call `sync()` for an immediate layout.
- A right click on the divider is consumed and never starts a drag.

## ScrollPanel

`Pallid.UI.Widgets.scrollPanel(x, y, w, h, opts)` creates a `PallidScrollPanel` (class `ScrollPanel`, a `PallidPanel` subclass): a viewport that clips and offsets a content panel.

**Side:** client

### Parameters
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts.background (PallidColor|nil) - Panel fill, inherited from `PallidPanel`.
- opts.border (PallidColor|nil) - Panel border color, inherited from `PallidPanel`.
- opts.radius (number|table|nil) - Corner radius, inherited from `PallidPanel`.
- opts.borderWidth (number|nil) - Border thickness; defaults to 1 when `border` is set.
- opts.fillInset (number|nil) - Inset applied to the fill; defaults to 0.
- opts.vertical (boolean, default true) - Allows the vertical bar to appear.
- opts.horizontal (boolean, default false) - Allows the horizontal bar to appear.
- opts.barSize (number, default 10) - Bar thickness in pixels; defaults to `Widgets.DEFAULT_SCROLLBAR_SIZE`.
- opts.barGap (number|nil, default nil) - Gap between the bars and the panel edge. When nil it is 3 if `min(w, h) < 80`, otherwise 5.
- opts.wheelStep (number, default 28) - Pixels scrolled per wheel notch.
- opts.contentW (number, default 0) - Initial content width.
- opts.contentH (number, default 0) - Initial content height.

### Returns
- PallidScrollPanel - The new scroll panel.

### Methods
- `setContentSize(w, h)` - Sets the scrollable extent (`content.w`/`content.h`) and re-syncs; returns the panel for chaining. It does not move or resize children.
- `getScroll()` - Returns the current `x, y` offsets in pixels.
- `scrollTo(x, y, silent)` - Scrolls to the given offsets, clamped to the content range, and updates the bar thumbs unless `silent` is true; returns the panel for chaining.
- `sync()` - Recomputes bar visibility, page sizes and offsets. Runs automatically from draw, update and input.

### Content container

The scrolled area is `panel.content`, a `PallidPanel` created at `(0, 0)` in content-local coordinates. Add children to it with `panel.content:add(child)`; their positions are content-relative and the panel offsets them by the scroll position. `panel.content` is not in `panel.children`, so it is never reached by `panel:add(...)`.

The bars are ordinary children: `panel.barV` and `panel.barH`, both `PallidScrollBar` instances.

### Example
```lua
require "pallid/ui/widgets/scrollpanel"
require "pallid/ui/widgets/panel"

local Widgets = Pallid.UI.Widgets
local Color = Pallid.UI.Color

local list = Widgets.scrollPanel(0, 0, 320, 240, {
    vertical   = true,
    horizontal = false,
    contentW   = 300,
    contentH   = 1200,
    background = Color.surface,
    border     = Color.border,
    radius     = 4,
    wheelStep  = 32,
})

for i = 1, 20 do
    list.content:add(Widgets.panel(0, (i - 1) * 60, 300, 56, { background = Color.surfaceMuted }))
end

list:scrollTo(0, 120)
```

### Notes
- The panel does not measure children. Set the extent with `contentW`/`contentH` or `setContentSize`; while `content.h` and `content.w` stay 0 no bar appears and nothing scrolls.
- Assigning `scrollX`/`scrollY` directly skips the bar thumbs; use `scrollTo` instead.
- The wheel scrolls vertically. Holding Shift, or using a panel with `vertical = false, horizontal = true`, scrolls horizontally.
- Only content children that intersect the viewport are updated and animated, so off-screen rows do not receive `onUpdate`/`onAnimate` until they scroll into view. Zero-sized children are always visited.
- Clipping uses the viewport (`viewW` x `viewH`), not the panel box, so a point over the bar gutter or outside the viewport cannot reach a content child.
- Bars stay in `children` but are hidden while the content fits the viewport.
- A nested scrollable child is asked for the wheel first, so inner lists scroll before the outer panel.

## ScrollBar

`Pallid.UI.Widgets.scrollBar(vertical, x, y, w, h, opts)` creates a `PallidScrollBar` (class `ScrollBar`), a standalone draggable bar driven by a normalized value.

**Side:** client

### Parameters
- vertical (boolean) - True for a vertical bar, false for a horizontal one.
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts.onChange (fun(bar: PallidScrollBar, value: number)|nil) - Called with the new normalized position.
- opts.minThumb (number, default 24) - Minimum thumb length in pixels.
- opts.margin (number, default 2) - Gap between the track and the widget edge; clamped to 25% of the bar thickness.

### Returns
- PallidScrollBar - The new scrollbar.

### Methods
- `setValue(value)` - Sets the position, clamped to 0..1, and calls `onChange` only when the value actually changes; returns the bar for chaining.
- `setThumbColor(color)` - Replaces the idle thumb color; returns the bar for chaining.
- `trackLength()` - Usable track length in pixels after the margin.
- `thumbLength()` - Thumb length in pixels for the current `page`.
- `thumbOffset()` - Thumb offset in pixels from the track start.
- `thumbRect()` - Returns `x, y, w, h` of the thumb in root-local coordinates.
- `scrollToPoint(px, py)` - Moves the thumb so its center follows the point.

### Example
```lua
require "pallid/ui/widgets/scrollbar"

local bar = Pallid.UI.Widgets.scrollBar(true, 0, 0, 10, 240, {
    minThumb = 24,
    margin   = 2,
    onChange = function(scrollBar, value)
        -- value is 0..1
    end,
})

bar.page = 0.25
bar:setValue(0.5)
```

### Notes
- `page` is a plain field, the visible fraction of the content (0..1, default 1). Set it to `viewport / content`; otherwise the thumb covers the whole track.
- Assigning `bar.value` directly neither clamps nor fires `onChange`; use `setValue`.
- Clicking the track moves the thumb so its center lands on the cursor; pressing the thumb keeps the grab offset and drags it.
- A right click is consumed and never starts a drag.
- Nothing is drawn for a zero-sized bar; the track inset is always clamped to 25% of the thickness, so `margin` alone never empties the track.

## Separator

`Pallid.UI.Widgets.separator(vertical, x, y, w, h, color, thickness)` creates a `PallidSeparator` (class `Separator`), a thin decorative line.

**Side:** client

### Parameters
- vertical (boolean) - True for a vertical line, false for a horizontal one.
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- color (PallidColor|nil) - Line color; defaults to `Pallid.UI.Color.panelBorder` (the theme border). The table is copied into the widget.
- thickness (number|nil, default 1) - Line thickness in pixels, clamped to >= 1.

### Returns
- PallidSeparator - The new separator.

### Example
```lua
require "pallid/ui/widgets/separator"

local Widgets = Pallid.UI.Widgets
local Color = Pallid.UI.Color

local line = Widgets.separator(false, 0, 40, 300, 1)
local rule = Widgets.separator(true, 0, 0, 2, 200, Color.borderStrong, 2)
```

### Notes
- The line is centered on the cross axis, so a box thicker than `thickness` leaves empty space above and below (or left and right).
- There are no setters: change the `color` and `thickness` fields directly.
- `hittable` is false, so the line never steals hover or clicks from widgets behind it.

## Spacer

`Pallid.UI.Widgets.spacer(weight)` creates a `PallidSpacer` (class `Spacer`), an invisible flexible gap.

**Side:** client

### Parameters
- weight (number|nil, default 1) - Relative share of the leftover space, clamped to >= 0.

### Returns
- PallidSpacer - The new spacer.

### Example
```lua
require "pallid/ui/widgets/spacer"
require "pallid/ui/widgets/vbox"
require "pallid/ui/widgets/panel"

local Widgets = Pallid.UI.Widgets

local column = Widgets.vbox(0, 0, 200, 400, { spacing = 8 })
column:add(Widgets.panel(0, 0, 0, 40))
column:add(Widgets.spacer(1))
column:add(Widgets.panel(0, 0, 0, 40))
```

### Notes
- The spacer takes no position or size arguments: it is created at `(0, 0)` with zero size and is sized by its layout container.
- Only `VBox` and `HBox` read `weight`; in other containers the spacer stays zero-sized and has no visible effect.
- `hittable` is false, so the gap never blocks hover.
- Changing `weight` after adding requires calling the container's `layout()`.

## Anchor

`Pallid.UI.Widgets.anchor(x, y, w, h, opts)` creates a `PallidAnchor` (class `Anchor`), a single-content container that pins or stretches one child.

**Side:** client

### Parameters
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts.content (PallidWidget|nil) - Initial content widget.
- opts.padding (number, default 0) - Inner inset on every side in pixels, clamped to >= 0.
- opts.fillX (boolean, default false) - Stretches the content to the inner width.
- opts.fillY (boolean, default false) - Stretches the content to the inner height.
- opts.alignH ("left"|"center"|"right", default "left") - Horizontal placement when `fillX` is false.
- opts.alignV ("top"|"middle"|"bottom", default "top") - Vertical placement when `fillY` is false.
- opts.autoSize (boolean, default false) - Resizes the container to the content on the axes that are not filled.

### Returns
- PallidAnchor - The new anchor container.

### Methods
- `setContent(content)` - Replaces the content widget; passing nil removes it. Returns the installed content or nil.
- `add(child)` - Attaches a child, replacing the previous content, and returns the child.
- `remove(child)` - Detaches a child and clears `content` when it was the current one.
- `setBounds(x, y, w, h)` - Resizes the container and re-runs the layout; returns the anchor for chaining.
- `layout()` - Re-positions the content according to the fill and alignment settings.
- `preferredSize(maxW, maxH)` - Returns the preferred width and height for the container.

### Example
```lua
require "pallid/ui/widgets/anchor"
require "pallid/ui/widgets/panel"

local Widgets = Pallid.UI.Widgets
local Color = Pallid.UI.Color

local frame = Widgets.anchor(0, 0, 400, 300, {
    alignH  = "center",
    alignV  = "middle",
    padding = 16,
})

frame:setContent(Widgets.panel(0, 0, 160, 100, { background = Color.surface }))
```

### Notes
- The anchor owns exactly one child: `add` and `setContent` replace the previous content instead of appending, and the replaced widget is detached from the tree.
- Layout runs on construction, `setContent`, `add`, `remove` and `setBounds` only. If the content changes its own size, call `layout()`.
- `autoSize` only affects axes that are not filled; a filled axis keeps the anchor's current size.
- `preferredSize` caps a non-filled width to `maxW`, but a non-filled height is not capped to `maxH`.
- With `fillX`/`fillY`, `preferredSize` reports `maxW`/`maxH` when given, otherwise the anchor's own size.
