# Charts, colour, 3D and picker widgets

Factories and public methods for the chart, donut chart, colour picker, 3D model preview, date picker and time picker. Every widget here is client-side; attach it to a tree with the base API described in [ui-widget.md](ui-widget.md).

All factories live in `Pallid.UI.Widgets` and are registered when the widget file is required. `root:add(widget)` below stands for adding the widget to your tree; see [ui-widget.md](ui-widget.md) for `add`, `remove`, `setBounds`, `setVisible`, `setEnabled`, `setTooltip` and the draw/update lifecycle.

## Chart

Line, bar or sparkline chart with optional axes, grid, legend and a hover tooltip. A sparkline is the same renderer with different defaults, not a separate mode.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Data and appearance; fields below.
- opts.mode (`"line"`|`"bar"`|`"sparkline"`|nil) - Chart mode, defaults to `"line"`.
- opts.series (table[]|nil) - Array of `{ name, values, color }` records, defaults to empty.
- opts.labels (string[]|nil) - X captions aligned with the value index, defaults to empty.
- opts.axes (boolean|nil) - Axis lines and tick labels, defaults to `true` (or `false` for a sparkline). Passing `false` is ignored for `"line"`/`"bar"`; use `setAxes(false)`.
- opts.grid (boolean|nil) - Grid lines, defaults to `true` when axes are on. Passing `false` is ignored while axes are on; use `setGrid(false)`.
- opts.legend (boolean|nil) - `nil` shows the legend only when more than one series exists, `true` always shows it, `false` hides it.
- opts.tooltip (boolean|nil) - Hover tooltip, defaults to `true` (or `false` for a sparkline). Passing `false` is ignored for `"line"`/`"bar"`; use `setTooltip(false)`.
- opts.min (number|nil) - Fixed value-axis minimum, derived from the data when nil.
- opts.max (number|nil) - Fixed value-axis maximum, derived from the data when nil.
- opts.includeZero (boolean|nil) - Forces zero into the value range, defaults to `true` for `"bar"` and `false` otherwise.
- opts.ticks (integer|nil) - Number of value-axis intervals, minimum 1, defaults to 4.
- opts.format (function|string|nil) - Value formatter: a function receiving the number, or a `string.format` pattern such as `"%.1f"`. Defaults to `"%.0f"`.
- opts.lineWidth (number|nil) - Line width in pixels, minimum 1, defaults to 2.
- opts.showPoints (boolean|nil) - `true` forces point markers, `false` hides them, `nil` uses the automatic rule (line mode, up to `pointLimit` points).
- opts.pointLimit (integer|nil) - Point count above which the automatic marker rule hides markers, minimum 1, defaults to 40.
- opts.maxDrawPoints (integer|nil) - Per-series draw cap. `nil` uses the plot width (at most 384), `0` disables the cap. Decimation affects drawing only; hover and tooltips still use every point.
- opts.animated (boolean|nil) - Reveal animation on data changes, defaults to `true`.
- opts.background (PallidColor|nil) - Background fill; no fill when omitted.
- opts.border (PallidColor|nil) - Outer border; no border when omitted.
- opts.gridColor (PallidColor|nil) - Grid line colour, defaults to `Color.border` at 80% alpha.
- opts.axisColor (PallidColor|nil) - Axis line colour, defaults to `Color.borderStrong`.
- opts.radius (number|nil) - Background and border corner radius, defaults to 4.
- opts.fillInset (number|nil) - Inset of the background fill, defaults to 1 when `radius > 0` and 0 otherwise.
- opts.tooltipDelay (number|nil) - Seconds before the hover tooltip fades in, defaults to 0.12.

### Returns
- Pallid.UI.Widgets.Chart - The new chart (`PallidChart` in EmmyLua).

### Methods
- `setData(series, labels, opts) -> self` - Replaces series and labels, rebuilds the value cache and replays the reveal unless `opts.animate == false`. `labels` may be nil to clear.
- `setSeries(series, labels) -> self` - `setData` without the options table.
- `playIntro() -> self` - Restarts the reveal animation.
- `setMode(mode) -> self` - Switches between `"line"`, `"bar"` and `"sparkline"`; an unknown mode is logged and ignored.
- `setAxes(axes) -> self` - Shows or hides axes and re-lays out.
- `setGrid(grid) -> self` - Shows or hides grid lines.
- `setLegend(legend) -> self` - Forces the legend on or off, overriding the automatic rule.
- `setTooltip(tooltip) -> self` - Enables or disables the hover tooltip. Takes a boolean, not tooltip text.
- `setTicks(ticks) -> self` - Sets the number of value-axis intervals, floored and at least 1.
- `setRange(min, max) -> self` - Sets the value range; a non-finite value restores the automatic range for that side.
- `setColors(background, border, gridColor, axisColor) -> self` - Replaces the named colours; nil keeps the current value.
- `setLineWidth(width) -> self` - Sets the line width, minimum 1.
- `setShowPoints(show) -> self` - Overrides marker visibility; nil restores the automatic rule.
- `setAnimated(animated) -> self` - Enables the reveal animation or jumps to the finished frame.
- `refresh() -> self` - Re-runs the layout after labels, series names or series colours were changed in place.
- `setBounds(x, y, w, h) -> self` - Moves and resizes the widget, then re-lays out.
- `formatValue(value) -> string` - Formats a number with the configured `format`, falling back to `"%.0f"`.

### Example
```lua
require "pallid/ui/widgets/chart"

local chart = Pallid.UI.Widgets.chart(0, 0, 320, 160, {
    labels = { "Mon", "Tue", "Wed", "Thu" },
    series = {
        { name = "Kills", values = { 3, 7, 2, 9 } },
    },
})
root:add(chart)

chart:setData({
    { name = "Kills", values = { 4, 5, 8, 1 }, color = Pallid.UI.Color.error },
}, { "Mon", "Tue", "Wed", "Thu" }, { animate = false })
```

### Notes
- Series shape: an array of tables with `name` (string, falls back to `"Series N"`), `values` (array of numbers, one per point) and `color` (PallidColor table, otherwise a shared palette entry). Values go through `tonumber`; non-numeric and non-finite entries are dropped and leave a gap in that series.
- `pointCount` is the larger of the longest `values` array and `#labels`. A missing label falls back to the 1-based point index as a string.
- `opts.axes = false`, `opts.grid = false` and `opts.tooltip = false` are ignored for `"line"` and `"bar"`, because the constructor falls back to the default whenever the option is falsy. Use `setAxes`, `setGrid` and `setTooltip` instead.
- `refresh()` re-reads labels, names and colours only. Values are cached by `setData`, so in-place edits to `values` need `setData`/`setSeries`.
- The reveal starts at 0 and a chart that is never updated draws no data. Pass `animated = false` or call `setAnimated(false)` to render statically without an update loop.
- The legend is suppressed below 60 px height, and entries that do not fit collapse into a `+N` marker.
- `setTooltip` overrides `PallidWidget:setTooltip` with a boolean parameter. `chart:setTooltip("text")` only re-enables the hover tooltip; it does not set tooltip text.
- A `format` function or pattern that raises an error falls back to `"%.0f"` and logs once per instance.

## DonutChart

Ring chart for part-to-whole values, with an optional centre caption and legend column. Segments are plain tables, so no widget per slice.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Data and appearance; fields below.
- opts.segments (table[]|nil) - Array of `{ label, value, color }` records, defaults to empty.
- opts.thickness (number|nil) - Ring thickness in pixels, minimum 4, defaults to 26. Drawing clamps it to 90% of the outer radius.
- opts.startAngle (number|nil) - Start angle in degrees, defaults to -90 (top).
- opts.track (PallidColor|nil) - Full-ring track drawn behind the segments; none when omitted.
- opts.showLegend (boolean|nil) - Draws the legend column, defaults to `true`. The legend only appears when the widget is at least 220 px wide.
- opts.animated (boolean|nil) - Eases the reveal, defaults to `true`.
- opts.centerText (string|nil) - Large centre caption.
- opts.centerSubtext (string|nil) - Small caption under the centre text.
- opts.format (string|function|nil) - Legend and tooltip value formatter: a `string.format` pattern or a function receiving the number. Defaults to `"%.0f"`.
- opts.onSelect (fun(chart: PallidDonutChart, index: integer, segment: table)|nil) - Called on a left click over a segment.
- opts.tooltipDelay (number|nil) - Seconds before the segment tooltip fades in, defaults to 0.05.

### Returns
- Pallid.UI.Widgets.DonutChart - The new donut chart (`PallidDonutChart` in EmmyLua).

### Methods
- `setSegments(segments) -> self` - Replaces the segments, resets the reveal and hover state and rebuilds the cached legend values.
- `setFormat(format) -> self` - Replaces the formatter and rebuilds the cached legend values.
- `getTotal() -> number` - Sums every segment with a positive value.
- `formatValue(value) -> string` - Formats one value with the configured formatter.
- `segmentAt(px, py) -> integer` - 1-based segment index under a root-local point, or 0 outside the ring.

### Example
```lua
require "pallid/ui/widgets/donutchart"

local donut = Pallid.UI.Widgets.donutChart(0, 0, 280, 180, {
    segments = {
        { label = "Food",    value = 12, color = Pallid.UI.Color.success },
        { label = "Ammo",    value = 5,  color = Pallid.UI.Color.warning },
        { label = "Medical", value = 3 },
    },
    centerText = "20",
    onSelect   = function(chart, index, segment) end,
})
root:add(donut)

local total = donut:getTotal()
```

### Notes
- Segment shape: `label` (string; the tooltip falls back to `"Segment N"` and the legend to an empty string), `value` (number via `tonumber`; only positive values are drawn and summed) and `color` (PallidColor table, otherwise a shared palette entry).
- `centerText` and `centerSubtext` are plain fields read on every draw; assign them directly, there is no setter.
- The legend is limited to `floor(h / 18)` rows and only drawn when `w >= 220`; its values are right-aligned.
- For values, `setSegments` is the refresh path. Editing `donut.segments[i].value` in place leaves the cached legend strings stale.
- A `Color.surface` disc is painted inside the ring when it has an inner hole, so the centre does not show the background behind the widget.
- `onSelect` fires only when a left click lands on a positive segment, but the click is consumed whenever `segmentAt` finds any segment.
- `segmentAt` expects root-local coordinates, the same space the input hooks receive.
- A `format` function is not protected: an error inside it propagates.

## ColorPicker

Colour swatch that opens an HSV picker panel in a popover. The swatch draws a checkerboard under the colour so alpha is visible.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Options; fields below.
- opts.color (PallidColor|nil) - Initial colour, defaults to `Color.primary`. The picker stores its own copy.
- opts.onChange (fun(picker: PallidColorPicker, color: PallidColor)|nil) - Called after a change made in the panel.

### Returns
- Pallid.UI.Widgets.ColorPicker - The new swatch (`PallidColorPicker` in EmmyLua).

### Methods
- `setColor(color) -> self` - Replaces the colour and pushes it into an already created panel. Does not fire `onChange`.
- `getColor() -> PallidColor` - Copy of the current colour.
- `open()` - Opens the picker popover to the right of the swatch. The panel and popover are created on the first call.

### Example
```lua
require "pallid/ui/widgets/colorpicker"

local swatch = Pallid.UI.Widgets.colorPicker(0, 0, 28, 28, {
    color    = { r = 0.2, g = 0.6, b = 1, a = 1 },
    onChange = function(picker, color) end,
})
root:add(swatch)

swatch:setColor(Pallid.UI.Color.error)
local current = swatch:getColor()
```

### Notes
- `getColor()` returns a new table; mutating it does not change the picker.
- `onChange` receives the picker's internal colour table, not a copy. Copy it if the value is stored.
- `picker.panel` is nil until `open()` has run. The panel is a `PallidColorPickerPanel` exposing `setColor(color)`, `getColor()` (a clamped copy) and `reset()`, plus the `Pallid.UI.Widgets.ColorPickerPanel.WIDTH` (270) and `HEIGHT` (334) constants used to size the popover.
- The panel clamps every channel to 0..1 and keeps the HEX and R/G/B/A fields in sync; invalid hex input gets an error border and is reverted on blur.

## Model3D

Interactive 3D preview of a character, outfit, survivor or vehicle, with drag rotation, wheel zoom and optional auto-rotation. Only one source is active at a time.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Source, playback and framing; fields below.
- opts.character (IsoGameCharacter|nil) - Live character rendered as-is.
- opts.survivorDesc (SurvivorDesc|nil) - Procedural survivor appearance.
- opts.outfit (table|string|nil) - `{ name, female, zombie }` or a plain outfit name from `clothing.xml`.
- opts.outfitName (string|nil) - Outfit name, used when `opts.outfit` is absent or has no `name`.
- opts.female (boolean|nil) - Female body for the `outfitName` path.
- opts.zombie (boolean|nil) - Zombie body for the `outfitName` path.
- opts.vehicle (BaseVehicle|nil) - Vehicle rendered through the vehicle scene.
- opts.vehicleScript (string|nil) - Vehicle script full name, e.g. `"Base.CarNormal"`, rendered without a world object.
- opts.vehicleView (string|nil) - Initial vehicle scene view name.
- opts.item (InventoryItem|Item|nil) - Only a 2D inventory icon; items cannot be rendered in 3D.
- opts.dummy (boolean|nil) - Enables the built-in dummy when no source and no item are given, defaults to `true`; `false` leaves the 2D fallback.
- opts.dummyOutfit (string|nil) - Outfit used by the dummy, defaults to `"Classy"`.
- opts.dummyFemale (boolean|nil) - Female dummy body, defaults to `false`.
- opts.animSet (string|nil) - AnimSet name, e.g. `"player"`; blank strings are ignored.
- opts.state (string|nil) - AnimSet state, e.g. `"idle"`.
- opts.isometric (boolean|nil) - Isometric projection; nil keeps the native default.
- opts.animateWhilePaused (boolean|nil) - Keeps the native animation running while paused, defaults to `false`.
- opts.randomExtAnimations (boolean|nil) - Enables the native idle animation events, defaults to `false`.
- opts.zoom (number|nil) - Native zoom clamped to -2..4; negative zooms in. Defaults to 0.
- opts.xOffset (number|nil) - Horizontal model offset inside the viewport, defaults to 0.
- opts.yOffset (number|nil) - Vertical model offset inside the viewport, defaults to 0.
- opts.autoRotate (boolean|nil) - Turns the model one step every `rotateInterval`, defaults to `true`.
- opts.rotateInterval (number|nil) - Seconds between auto-rotate steps, minimum 0 (0 disables the timer), defaults to 2.5.
- opts.direction (IsoDirections|nil) - Initial facing direction; a non-`IsoDirections` value is logged and ignored.
- opts.interactive (boolean|nil) - `false` makes the preview display-only, defaults to `true`.
- opts.dragRotate (boolean|nil) - Enables rotation by horizontal dragging, defaults to `true`.
- opts.wheelZoom (boolean|nil) - Enables zooming with the mouse wheel, defaults to `true`.
- opts.label (string|false|nil) - Footer hint; `false` or a blank string hides the footer. Defaults to `"Drag to rotate - wheel to zoom"`.
- opts.inset (number|nil) - Padding between the frame and the viewport, defaults to 4.
- opts.radius (number|nil) - Frame corner radius, defaults to 4.
- opts.fallbackIcon (string|nil) - Icon name or texture path for the 2D fallback. A path containing `/` is loaded as a texture, anything else as a registered icon name.
- opts.fallbackText (string|nil) - Fallback caption. Defaults to `"No 3D preview"`, `"Vehicle 3D preview unavailable"` for vehicle sources and `"Item icon preview"` for an item.

### Returns
- Pallid.UI.Widgets.Model3D - The new preview (`PallidModel3D` in EmmyLua).

### Methods
- `setCharacter(character) -> self` - Sets or clears (nil) the live character source; rejects non-`IsoGameCharacter` values.
- `setSurvivorDesc(survivorDesc) -> self` - Sets or clears the survivor description source.
- `setOutfit(name, female, zombie) -> self` - Sets or clears a named outfit source; a blank name warns and clears it.
- `setDummy(outfit, female) -> self` - Shows the built-in dummy, using the last dummy outfit when `outfit` is blank.
- `isDummy() -> boolean` - True while the dummy is the active source.
- `setVehicle(vehicle) -> self` - Sets or clears the vehicle source.
- `setVehicleScript(scriptName) -> self` - Sets a script-only vehicle source; an unknown script name warns and clears the source.
- `setZoom(zoom) -> self` / `getZoom() -> number` - Writes (clamped to -2..4) or reads the native zoom.
- `setXOffset(x) -> self` / `setYOffset(y) -> self` - Sets the model offset inside the viewport.
- `setDirection(direction) -> self` / `getDirection() -> IsoDirections|nil` - Writes or reads the facing direction.
- `setLabel(label) -> self` - Sets the footer hint; nil or a blank string hides it.
- `setAnimateWhilePaused(enabled) -> self` - Keeps the native animation running while the game is paused.
- `setAutoRotate(enabled) -> self` / `setRotateInterval(seconds) -> self` - Control auto-rotation; a zero interval disables the timer.
- `setVisible(visible) -> self` - Hides the widget and immediately hides the native model.
- `destroy() -> self` - Releases the native element for good; the widget keeps drawing the 2D fallback and never recreates the model.

### Example
```lua
require "pallid/ui/widgets/model3d"

local preview = Pallid.UI.Widgets.model3D(0, 0, 220, 260, {
    outfit = "Classy",
})
root:add(preview)

preview:setZoom(-1)
preview:setRotateInterval(3)

local car = Pallid.UI.Widgets.model3D(0, 0, 220, 260, {
    vehicleScript = "Base.CarNormal",
})
root:add(car)
```

### Notes
- Every source setter clears the other sources. Switching between character and vehicle recreates the native with the matching class.
- The native is an always-on-top UIManager element that cannot be clipped by the Pallid stencil. It is hidden unless the whole viewport lies inside the current clip rect, so in a scroll panel or a partly off-screen window the 3D view disappears and the 2D fallback is drawn instead.
- A `character` or `survivorDesc` fills the native synchronously and also works on the main menu. A named outfit is dressed later and needs a live player and a loaded cell. A vehicle is rendered by the vehicle scene instead of `UI3DModel`; an `item` is never rendered in 3D.
- Character rotation is limited to the eight 45-degree `IsoDirections` steps. Vehicle rotation is continuous, through camera yaw and pitch.
- `destroy()` is permanent: the native is not recreated afterwards.
- Reuse one widget per preview instead of creating one per window; the native clothing listener cannot be removed from Lua.
- `opts.dummy` only applies when no character, outfit, survivor, vehicle or item source is configured.
- Auto-rotation runs from `onUpdate`, so the widget must be attached to an updated tree.
- Native setters (zoom, offsets, direction, animate-while-paused) apply immediately when a native exists; before that they only store the value, which is applied on creation.

## DatePicker

Compact date field with a calendar icon that opens a month grid with year and month navigation plus a Today shortcut. It is a `PallidPickerField` subclass.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Picker options; fields below.
- opts.value (table|nil) - `{ year, month, day }` with a 1-based month; overrides the resolved default.
- opts.gameTime (boolean|nil) - Uses the in-game clock for the initial value and Today, defaults to `true`; `false` uses the OS date.
- opts.icon (string|false|nil) - Registered icon name or texture path, defaults to the calendar icon; `false` hides it.
- opts.onChange (fun(picker: PallidDatePicker, year: integer, month: integer, day: integer)|nil) - Called when a date is picked.
- opts.radius (number|nil) - Field corner radius, defaults to 4.

### Returns
- Pallid.UI.Widgets.DatePicker - The new date picker (`PallidDatePicker` in EmmyLua).

### Methods
- `getDate() -> integer, integer, integer` - Current `year, month, day` as three values.
- `setDate(year, month, day) -> self` - Sets the date, clamped to a valid calendar day. Does not fire `onChange`.
- `open() -> self` - Builds the popover on first use and opens the calendar below the field.
- `close() -> self` - Closes the popover.
- `isOpen() -> boolean` - True while the popover is visible.
- `setIcon(icon) -> self` - Replaces the field icon; `false` hides it.

### Example
```lua
require "pallid/ui/widgets/datepicker"

local picker = Pallid.UI.Widgets.datePicker(0, 0, 180, 28, {
    value    = { year = 1993, month = 7, day = 9 },
    gameTime = true,
    onChange = function(field, year, month, day) end,
})
root:add(picker)

local year, month, day = picker:getDate()
picker:setDate(1994, 1, 1)
```

### Notes
- `getDate()` returns three values while `opts.value` is a table; `setDate` takes three values.
- Only a picked day or the Today button fires `onChange`; `setDate` is silent.
- `opts.value` is clamped: year at least 1, month 1..12, day to the length of that month.
- The grid is Monday-first and always six rows; days from the previous and next month are shown dimmed and are selectable.
- `gameTime = false` makes both the initial value and Today read the OS clock.
- If neither `getGameTime` nor `os.date` is available, the picker starts at 1993-07-01.

## TimePicker

Compact time field with a clock icon that opens a two-column popover: hours, minutes, a preview and Now/Cancel/OK buttons. It is a `PallidPickerField` subclass.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Picker options; fields below.
- opts.value (table|nil) - `{ hour, minute }`; overrides the resolved default.
- opts.minuteStep (integer|nil) - Minute step, snapped to the nearest of 1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30, 60. Defaults to 5.
- opts.icon (string|false|nil) - Registered icon name or texture path, defaults to the clock icon; `false` hides it.
- opts.onChange (fun(picker: PallidTimePicker, hour: integer, minute: integer)|nil) - Called when the applied time changes.
- opts.radius (number|nil) - Field corner radius, defaults to 4.

### Returns
- Pallid.UI.Widgets.TimePicker - The new time picker (`PallidTimePicker` in EmmyLua).

### Methods
- `getTime() -> integer, integer` - Current `hour, minute` as two values.
- `setTime(hour, minute) -> self` - Sets the time, clamping the hour to 0..23 and rounding the minute to the step. Does not fire `onChange`.
- `open() -> self` - Builds the popover on first use and opens it below the field.
- `close() -> self` - Closes the popover.
- `isOpen() -> boolean` - True while the popover is visible.
- `setIcon(icon) -> self` - Replaces the field icon; `false` hides it.

### Example
```lua
require "pallid/ui/widgets/timepicker"

local picker = Pallid.UI.Widgets.timePicker(0, 0, 120, 28, {
    value      = { hour = 14, minute = 30 },
    minuteStep = 15,
    onChange   = function(field, hour, minute) end,
})
root:add(picker)

local hour, minute = picker:getTime()
picker:setTime(9, 45)
```

### Notes
- `getTime()` returns two values while `opts.value` is a table; `setTime` takes two values.
- There is no `gameTime` option: the initial value and Now always try `getGameTime()` first, then the OS clock, then 00:00.
- The minute column contains `floor(60 / step)` rows, and a minute that rounds up to 60 is reduced by one step (59 with step 5 becomes 55).
- `onChange` fires on OK and on any close that is not a cancel (an outside click or `close()`), but only if the value differs from the last reported pair.
- Cancel and Escape restore the time captured when the popover opened and do not fire `onChange`.
- `step` is fixed at construction; there is no setter.
