# Navigation widgets

Pagination, filter bar, timeline, stepper, tab panel, accordion and breadcrumbs for Pallid UI. Every factory lives on `Pallid.UI.Widgets` and is registered when its file is required, for example `require "pallid/ui/widgets/pagination"`. Tree operations such as `add`, `remove`, `setBounds`, `setVisible` and `setEnabled` come from the base widget API described in [ui-widget.md](ui-widget.md) and are not repeated here.

## Pagination

Compact pager that paints previous/next arrows and numbered page slots itself, without child buttons.

**Side:** client

### Parameters
- `x` (number) - Offset X from the parent's origin.
- `y` (number) - Offset Y from the parent's origin.
- `w` (number) - Width in pixels.
- `h` (number) - Height in pixels.
- `opts.page` (integer|nil) - Initial page, default `1`, clamped to `1..pageCount`.
- `opts.pageCount` (integer|nil) - Total pages, default `0`; floored and clamped to `>= 0`.
- `opts.maxButtons` (integer|nil) - Maximum number/ellipsis slots excluding the two arrows, default `7`, minimum `1`.
- `opts.onChange` (fun(pager, page)|nil) - Called after the page changes.

### Returns
- `PallidPagination` - New pager. Class `Pagination`, registered as `Pallid.UI.Widgets.Pagination`.

### Methods
- `pager:setPage(page, silent)` - Sets the page, clamped to `1..pageCount`; `silent` skips `onChange`.
- `pager:setPageCount(count, silent)` - Replaces the page count, clamps the page and emits `onChange` only when the page value changed.
- `pager:getPage()` - Returns the current page, or `0` when there are no pages.

### Example
```lua
require "pallid/ui/widgets/pagination"

local pager = Pallid.UI.Widgets.pagination(8, 8, 220, 26, {
    page       = 1,
    pageCount  = 12,
    maxButtons = 5,
    onChange   = function(pager, page) end,
})

pager:setPageCount(20)
pager:setPage(3)
local page = pager:getPage()
```

### Notes
- The arrows are always drawn in addition to the page slots, so `maxButtons = 7` shows up to 9 slots.
- Ellipsis slots are not clickable; only the arrows and numbered slots change the page.
- With `pageCount = 0` the pager draws nothing and `getPage()` returns `0`.
- `setPage` and `setPageCount` do nothing when the resulting page equals the current one.

## FilterBar

One row with a debounced search field followed by one dropdown per configured filter, reporting the combined state through a single callback.

**Side:** client

### Parameters
- `x` (number) - Offset X from the parent's origin.
- `y` (number) - Offset Y from the parent's origin.
- `w` (number) - Width in pixels.
- `h` (number|nil) - Height in pixels, default `26`.
- `opts.placeholder` (string|nil) - Search placeholder, default the `UI_Pallid_Search` translation.
- `opts.debounce` (number|nil) - Search debounce in seconds, default `0`.
- `opts.fields` (table[]|nil) - Filter fields, each `{ key, label, options, width?, allLabel? }`. Entries without a `key` are skipped.
- `opts.fields[i].options` (table) - Option list; strings or `{ label, value }` tables.
- `opts.fields[i].width` (number|nil) - Combo width in pixels, default `140`.
- `opts.fields[i].allLabel` (string|nil) - Label of the implicit clear entry, default the `UI_Pallid_All` translation.
- `opts.gap` (number|nil) - Gap between controls in pixels, default `6`.
- `opts.onChange` (fun(bar, filters)|nil) - Called with the state after any filter changes.

### Returns
- `PallidFilterBar` - New filter bar. Class `FilterBar`, registered as `Pallid.UI.Widgets.FilterBar`.

### Methods
- `bar:setFields(fields, silent)` - Replaces the fields and rebuilds the combos; `silent` skips the initial emit.
- `bar:getFilters()` - Returns a new state table `{ query, values, count }`.
- `bar:setFilter(key, value)` - Selects a value on one field by key and emits `onChange`.
- `bar:clear(silent)` - Clears the search text and every combo; `silent` skips `onChange`.

### Example
```lua
require "pallid/ui/widgets/filterbar"

local bar = Pallid.UI.Widgets.filterBar(8, 8, 420, 26, {
    placeholder = "Filter rows",
    debounce    = 0.15,
    fields      = {
        { key = "state", label = "State", options = { "Ready", "Busy" }, width = 130 },
        { key = "role",  label = "Role",  options = { { label = "Scout", value = 1 } }, width = 140 },
    },
    onChange = function(bar, filters)
        -- filters.query, filters.values.state, filters.count
    end,
})

bar:setFilter("state", "Busy")
local filters = bar:getFilters()
bar:clear()
```

### Notes
- The first option of every combo is always the implicit all/clear entry, so `getFilters` maps a combo index back to `field.options[index - 1]`; the reported value is the option's `value` when it is a table, otherwise its label.
- `filters.count` includes a non-empty query as one active filter.
- `setFilter` has no silent flag and always emits `onChange`; a value that matches neither a label nor an option value leaves the combo unselected.
- `setFields` drops the current selections even when `silent` is true.
- The field `label` is stored but never drawn by this widget; the combo only shows its options.
- The search field takes the remaining width with a minimum of 80 px, so narrow bars squeeze it first.

## Timeline

Vertical activity timeline with a connector line, markers, title, time and secondary text; rows are virtualised so a long history does not create one child per entry.

**Side:** client

### Parameters
- `x` (number) - Offset X from the parent's origin.
- `y` (number) - Offset Y from the parent's origin.
- `w` (number) - Width in pixels.
- `h` (number) - Height in pixels.
- `opts.entries` (table[]|nil) - Initial entries; a string or `{ title, text?, time?, color? }`.
- `opts.rowHeight` (number|fun(index): number|nil) - Row height in pixels, default `46`.
- `opts.background` (PallidColor|nil) - Panel fill, default `Color.surface`.
- `opts.border` (PallidColor|nil) - Panel outline, default `Color.border`; stored as `borderColor`.
- `opts.radius` (number|nil) - Corner radius, default `4`.
- `opts.lineColor` (PallidColor|nil) - Connector colour, default `Color.border`.
- `opts.markerColor` (PallidColor|nil) - Default marker colour, default `Color.primary`.
- `opts.onSelect` (fun(timeline, index, entry)|nil) - Called when a row is selected.

### Returns
- `PallidTimeline` - New timeline. Class `Timeline`, registered as `Pallid.UI.Widgets.Timeline`.

### Methods
- `timeline:setEntries(entries)` - Replaces every entry and clears the selection.
- `timeline:addEntry(entry)` - Appends one entry and keeps the selection.
- `timeline:scrollToEntry(index)` - Scrolls the list so the entry row is at the top.

### Example
```lua
require "pallid/ui/widgets/timeline"

local timeline = Pallid.UI.Widgets.timeline(8, 8, 400, 220, {
    entries = {
        { title = "Spawned", time = "08:12", text = "Character created" },
        { title = "Looted",  time = "09:40", color = Pallid.UI.Color.warning },
        "Plain string entry",
    },
    onSelect = function(timeline, index, entry) end,
})

timeline:addEntry({ title = "Slept", time = "22:10" })
timeline:scrollToEntry(1)
timeline:setEntries({ { title = "Reset" } })
```

### Notes
- Entries are normalised on the way in: `title` falls back to `label`, `text` and `time` default to `""`, and a non-table value becomes its `tostring` title.
- `onSelect` receives the normalised entry, not the table you passed; the original is kept in `entry.raw`.
- `rowHeight` is handed to the internal list at construction. Changing `timeline.rowHeight` later has no effect; assign `timeline.list.rowHeight` instead.
- An empty list draws the `UI_Pallid_NoItems` empty state inside the panel.
- The selection highlight is internal; read the index from the `onSelect` callback.

## Stepper

Horizontal progress stepper with numbered or icon circles, completed/current/future/error/disabled states and animated connectors.

**Side:** client

### Parameters
- `x` (number) - Offset X from the parent's origin.
- `y` (number) - Offset Y from the parent's origin.
- `w` (number) - Width in pixels.
- `h` (number) - Height in pixels; `0` auto-grows to the row height.
- `steps` ((string|table)[]) - Strings or `{ label, icon, disabled?, error?, color?, iconColor?, labelColor? }` tables.
- `opts.current` (number|nil) - Initial 1-based active step, default `1`.
- `opts.complete` (boolean|nil) - Starts in the all-completed state, default `false`.
- `opts.circleSize` (number|nil) - Circle diameter cap, default `28`, clamped to `6..64`.
- `opts.showLabels` (boolean|nil) - Allows labels under the circles, default `true`.
- `opts.autoHideLabels` (boolean|nil) - Hides labels when the slot is too narrow, default `true`.
- `opts.labelMinSlot` (number|nil) - Slot width below which labels hide, default `44`.
- `opts.connectorThickness` (number|nil) - Connector line thickness, default `2`, minimum `1`.
- `opts.clickable` (boolean|nil) - Enables step selection by click, default `false`.
- `opts.font` (UIFont|string|nil) - Label font, or a `Pallid.UI.Fonts` key.
- `opts.numberFont` (UIFont|string|nil) - Number font; defaults to a size-based font.
- `opts.activeColor` (PallidColor|nil) - Active circle colour, default `Color.primaryStrong`.
- `opts.completedColor` (PallidColor|nil) - Completed circle colour, default `Color.success`.
- `opts.futureFill` (PallidColor|nil) - Future circle fill, default `Color.surfaceMuted`.
- `opts.futureBorder` (PallidColor|nil) - Future ring colour, default `Color.border`.
- `opts.lineColor` (PallidColor|nil) - Incomplete connector colour, default `Color.border`.
- `opts.completedLineColor` (PallidColor|nil) - Completed connector colour, default the completed colour at 55% alpha.
- `opts.activeLabelColor` (PallidColor|nil) - Active label colour, default `Color.textPrimary`.
- `opts.completedLabelColor` (PallidColor|nil) - Completed label colour, default `Color.textMuted`.
- `opts.futureLabelColor` (PallidColor|nil) - Future label colour, default `Color.textMuted`.
- `opts.futureContentColor` (PallidColor|nil) - Future icon/number colour, default the future label colour.
- `opts.errorColor` (PallidColor|nil) - Error circle and label colour, default `Color.error`.
- `opts.hoverColor` (PallidColor|nil) - Hover ring colour, default `Color.borderStrong`.
- `opts.animated` (boolean|nil) - Pulse, pop and connector animations, default `true`.
- `opts.onChange` (fun(stepper, current, previous)|nil) - Called after the active step changes.
- `opts.onComplete` (fun(stepper)|nil) - Called when advancing past the last available step.
- `opts.onStepClick` (fun(stepper, index, step)|nil) - Called after a clickable step is pressed.

### Returns
- `PallidStepper` - New stepper. Class `Stepper`, registered as `Pallid.UI.Widgets.Stepper`.

### Methods
- `stepper:setSteps(steps, silent)` - Replaces the steps, clamps the active index and clears the completed state.
- `stepper:setCurrent(index, silent)` - Sets the active step and reopens a completed flow.
- `stepper:setComplete(done, silent)` - Marks the whole flow finished or reopens it.
- `stepper:getCurrent()` - Returns the 1-based active step.
- `stepper:getStepCount()` - Returns the number of steps.
- `stepper:isFirst()` / `stepper:isLast()` - Test the first step, and the last reachable step or a completed flow.
- `stepper:isComplete()` - Returns `true` when the whole flow is finished.
- `stepper:next()` / `stepper:previous()` - Move to the next or previous enabled step; `next()` past the last step completes the flow.
- `stepper:setClickable(clickable)` - Enables or disables step selection by click.
- `stepper:setShowLabels(show)` - Shows or hides labels and recalculates auto-height.
- `stepper:setCircleSize(size)` - Changes the diameter, clamped to `6..64`.
- `stepper:setFont(font, numberFont)` - Replaces the label and number fonts.
- `stepper:setColors(colors)` - Replaces palette colours; keys `active`, `completed`, `futureFill`, `futureBorder`, `line`, `completedLine`, `activeLabel`, `completedLabel`, `futureLabel`, `futureContent`, `error`, `hover`.
- `stepper:setAnimated(animate)` - Enables or disables the animations; disabling snaps every connector to its target.

### Example
```lua
require "pallid/ui/widgets/stepper"

local stepper = Pallid.UI.Widgets.stepper(8, 8, 400, 0, {
    "Pick",
    { label = "Review", icon = "media/assets/ui/pallid/icons/tick.png" },
    { label = "Blocked", disabled = true },
}, {
    current    = 1,
    clickable  = true,
    onChange   = function(stepper, current, previous) end,
    onComplete = function(stepper) end,
})

stepper:next()
stepper:previous()
stepper:setCurrent(2)
stepper:setComplete(true)
```

### Notes
- `setSteps` clears `allComplete` and clamps `current` to the new list, but never calls `onComplete`.
- `setComplete(true)` moves the active index to the last step that is not disabled, so `previous()` later reopens on that step.
- Disabled steps are skipped by `next`, `previous` and `setComplete`, and they consume a click without selecting; error steps are never drawn as active or completed.
- A step without an icon shows its 1-based number; `icon` accepts a texture path containing `/`, a registered icon name, or a `Texture`.
- `setFont(font)` without `numberFont` applies the label font to the numbers as well.
- `h = 0` auto-grows, and `setBounds` with `h = 0` re-enables auto-height.

## TabPanel

Tabs with a content area above or beside the pages; only the active page is drawn and hit-tested, and an overflowing strip scrolls smoothly with arrows and the mouse wheel.

**Side:** client

### Parameters
- `x` (number) - Offset X from the parent's origin.
- `y` (number) - Offset Y from the parent's origin.
- `w` (number) - Width in pixels.
- `h` (number) - Height in pixels.
- `tabs` (table[]) - Each `{ title, content, icon?, iconSide?, iconColor?, closable? }`. A `nil` or empty title with an icon produces an icon-only tab.
- `opts.position` ("top"|"left"|nil) - Strip orientation, default `"top"`.
- `opts.tabSize` (number|nil) - Strip height for `"top"` or width for `"left"`, default `28` / `110`, minimum `20`.
- `opts.active` (integer|nil) - Index of the visible page, default `1`.
- `opts.scrollable` (boolean|nil) - Allows the strip to scroll, default `true`.
- `opts.minTabWidth` (number|nil) - Minimum tab width, default `44`.
- `opts.maxTabWidth` (number|nil) - Maximum tab width, default `210`; raised to `minTabWidth` when smaller.
- `opts.tabPadding` (number|nil) - Horizontal padding inside a tab, default `14`.
- `opts.contentPadding` (number|nil) - Inner padding around the page, default `4`.
- `opts.background` (PallidColor|nil) - Panel fill, default `Color.surface`.
- `opts.border` (PallidColor|nil) - Strip separator colour, default `Color.border`.
- `opts.tabFill` (PallidColor|nil) - Inactive tab fill, default transparent.
- `opts.tabHover` (PallidColor|nil) - Hovered tab fill, default `Color.accentSoft`.
- `opts.tabActive` (PallidColor|nil) - Active tab fill, default `Color.primarySoft`.
- `opts.tabAccent` (PallidColor|nil) - Active tab outline colour, default `Color.primaryStrong`.
- `opts.tabRadius` (number|nil) - Tab pill corner radius, default `4`.
- `opts.closable` (boolean|nil) - Draws a close cross on every tab, default `false`; a tab-level `closable` overrides it.
- `opts.dragThreshold` (number|nil) - Pixels the pointer must travel before a tab drag starts, default `4`.
- `opts.onChange` (fun(panel, index)|nil) - Called when the active tab changes.
- `opts.onClose` (fun(panel, index, tab)|nil) - Called after a tab is closed by its cross.

### Returns
- `PallidTabPanel` - New tab panel. Class `TabPanel`, registered as `Pallid.UI.Widgets.TabPanel`.

### Methods
- `panel:setActive(index, silent)` - Activates a tab; `silent` skips `onChange`.
- `panel:addTab(title, content, index, icon)` - Inserts a tab at `index` (appended by default) with an optional icon.
- `panel:removeTab(index)` - Removes a tab and keeps the active page sensible.
- `panel:moveTab(from, to)` - Reorders a tab without changing the active page.
- `panel:setTabClosable(index, closable)` / `panel:isTabClosable(index)` - Set or query the close cross of one tab.
- `panel:refreshTabs()` - Re-measures the strip after titles, icons or contents changed.
- `panel:scrollBy(delta)` - Adds a delta to the smooth scroll target; positive scrolls forward.
- `panel:ensureActiveVisible()` - Scrolls the strip so the active tab is fully visible.
- `panel:contentRect()` - Returns the page rectangle in widget-local coordinates.
- `panel:tabRect(index)` - Returns the tab cell rectangle in widget-local coordinates.

### Example
```lua
require "pallid/ui/widgets/tabpanel"
require "pallid/ui/widgets/panel"

local generalPage = Pallid.UI.Widgets.panel(0, 0, 0, 0)
local advancedPage = Pallid.UI.Widgets.panel(0, 0, 0, 0)

local panel = Pallid.UI.Widgets.tabPanel(8, 8, 420, 260, {
    { title = "General",  content = generalPage },
    { title = "Advanced", content = advancedPage, icon = "media/assets/ui/pallid/icons/settings.png" },
}, {
    position = "top",
    closable = true,
    onChange = function(panel, index) end,
    onClose  = function(panel, index, tab) end,
})

panel:setActive(2)
panel:addTab("About", Pallid.UI.Widgets.panel(0, 0, 0, 0))
panel:moveTab(1, 3)
panel:removeTab(2)
```

### Notes
- Tab tables are stored by reference and decorated with internal fields; do not share one table between panels.
- Pages are not children of the panel, so `panel:add` is not how they are attached: pass each page as `content` and add widgets inside that page.
- `addTab` has no `iconSide` or `iconColor` parameters; build such tabs in the constructor's `tabs` array.
- `addTab` and `moveTab` never fire `onChange`; `removeTab` fires it only when the active page content changes.
- `setActive` blurs a focused field and drops a mouse capture inside the page being hidden.
- Removing the last tab leaves `active = 0`, and `setActive` then ignores every index.
- Changing titles, icons or tab lists in place requires `refreshTabs()`; `setBounds` refreshes automatically.

## Accordion

Stack of collapsible sections with a clickable header, a rotating chevron and an animated content reveal.

**Side:** client

### Parameters
- `x` (number) - Offset X from the parent's origin.
- `y` (number) - Offset Y from the parent's origin.
- `w` (number) - Width in pixels.
- `sections` (table[]) - Each `{ title, content?, height?, open? }`.
- `opts.headerHeight` (number|nil) - Height of each clickable header, default `24`.
- `opts.onlyOne` (boolean|nil) - Keeps at most one section open, default `false`.
- `opts.onChange` (fun(accordion, index, open)|nil) - Called after a section is opened or closed.

### Returns
- `PallidAccordion` - New accordion. Class `Accordion`, registered as `Pallid.UI.Widgets.Accordion`.

### Methods
- `accordion:setOpen(index, open, silent)` - Opens or closes a section; `silent` skips `onChange`.

### Example
```lua
require "pallid/ui/widgets/accordion"
require "pallid/ui/widgets/panel"

local inventory = Pallid.UI.Widgets.panel(0, 0, 0, 0)

local accordion = Pallid.UI.Widgets.accordion(8, 8, 420, {
    { title = "Inventory", height = 80, open = true, content = inventory },
    { title = "Skills",    height = 60 },
}, {
    headerHeight = 24,
    onlyOne      = true,
    onChange     = function(accordion, index, open) end,
})

accordion:setOpen(2, true)
```

### Notes
- There is no height parameter: the accordion height is the sum of the headers plus the visible content and is recomputed by `layout`.
- A section's height falls back to `content.h`, which defaults to `0`, so a section with content but no `height` never reveals anything.
- `setOpen` only flips `section.open`; the height animation and layout run on the next animation/update frame, so `accordion.h` updates later.
- With `onlyOne`, the other sections are closed without firing `onChange` for them.
- Section tables and their content widgets are mutated in place (`openT`, `contentHeight`, `_headerY`, `_contentY`, `_visibleHeight`); use one section table per accordion.
- There is no add or remove method: edit `accordion.sections` directly, and layout catches up on the next update.

## Breadcrumbs

Horizontal breadcrumb trail with icons, separators and middle collapsing, controlled through callbacks.

**Side:** client

### Parameters
- `x` (number) - Offset X from the parent's origin.
- `y` (number) - Offset Y from the parent's origin.
- `w` (number) - Width in pixels; wider trails collapse or truncate.
- `h` (number|nil) - Row height; `nil` or `0` uses a font-based default.
- `items` ((string|table)[]) - Crumbs, each a string or `{ label, value?, icon?, disabled? }`; `label` falls back to `text` then `value`.
- `opts.current` (integer|nil) - Initial 1-based current crumb, default the last one.
- `opts.separator` (string|nil) - Text between crumbs, default `""`; an empty string uses the separator icon.
- `opts.separatorIcon` (string|nil) - Separator icon path, default `media/assets/ui/pallid/icons/arrow-right-04.png`.
- `opts.separatorIconSize` (number|nil) - Icon separator size cap, default `12`, clamped to `6..64`.
- `opts.separatorGap` (number|nil) - Pixels on each side of the separator, default `4`.
- `opts.itemPadding` (number|nil) - Horizontal padding inside a crumb, default `5`.
- `opts.iconSize` (number|nil) - Crumb icon size cap, default `14`, clamped to `6..64`.
- `opts.iconGap` (number|nil) - Gap between a crumb icon and its label, default `5`.
- `opts.font` (UIFont|string|nil) - Crumb font, or a `Pallid.UI.Fonts` key.
- `opts.collapse` (boolean|nil) - Collapses middle crumbs into an ellipsis, default `true`.
- `opts.ellipsis` (string|nil) - Marker for hidden crumbs, default `"..."`.
- `opts.clickableCurrent` (boolean|nil) - Makes the current crumb interactive, default `false`.
- `opts.animated` (boolean|nil) - Eases the hover highlight, default `true`.
- `opts.textColor` (PallidColor|nil) - Colour of non-current crumbs, default `Color.textMuted`.
- `opts.currentColor` (PallidColor|nil) - Colour of the current crumb, default `Color.textPrimary`.
- `opts.hoverColor` (PallidColor|nil) - Text colour at full hover, default `Color.textPrimary`.
- `opts.hoverBackground` (PallidColor|nil) - Hover plate colour, default `Color.primarySoft`.
- `opts.separatorColor` (PallidColor|nil) - Separator colour, default `Color.textDisabled`.
- `opts.ellipsisColor` (PallidColor|nil) - Ellipsis marker colour, default `Color.textMuted`.
- `opts.disabledColor` (PallidColor|nil) - Colour of disabled crumbs, default `Color.textDisabled`.
- `opts.onSelect` (fun(breadcrumbs, index, item)|nil) - Called with the clicked crumb index and its normalised item.
- `opts.onOverflow` (fun(breadcrumbs, hiddenCount)|nil) - Called when the ellipsis is clicked.

### Returns
- `PallidBreadcrumbs` - New breadcrumb trail. Class `Breadcrumbs`, registered as `Pallid.UI.Widgets.Breadcrumbs`.

### Methods
- `crumbs:setItems(items)` - Replaces the crumbs and clamps the current index.
- `crumbs:getItems()` / `crumbs:getItem(index)` - Return the normalised crumbs or one crumb.
- `crumbs:setCurrent(index)` - Sets the current crumb, clamped to the list, without any callback.
- `crumbs:getCurrent()` - Returns the 1-based current crumb, or `0` when empty.
- `crumbs:isCollapsed()` / `crumbs:getHiddenCount()` - Report whether and how many middle crumbs are hidden.
- `crumbs:setSeparator(separator)` - Replaces the separator text; `""` switches back to the separator icon.
- `crumbs:setSeparatorIcon(icon)` - Replaces the separator icon; `nil` or `false` disables it.
- `crumbs:setEllipsis(marker)` - Replaces the hidden-crumb marker.
- `crumbs:setCollapsed(collapse)` - Enables or disables middle collapsing.
- `crumbs:setAnimated(animate)` - Eases or snaps the hover highlight.
- `crumbs:setClickableCurrent(clickable)` - Makes the current crumb interactive.
- `crumbs:setFont(font)` - Replaces the crumb and separator font.
- `crumbs:setColors(colors)` - Replaces palette colours; keys `text`, `current`, `hover`, `hoverBackground`, `separator`, `ellipsis`, `disabled`.

### Example
```lua
require "pallid/ui/widgets/breadcrumbs"

local crumbs = Pallid.UI.Widgets.breadcrumbs(8, 8, 420, 24, {
    { label = "Home", icon = "media/assets/ui/pallid/icons/house.png" },
    { label = "Projects", value = "projects" },
    { label = "Current" },
}, {
    onSelect = function(crumbs, index, item)
        crumbs:setCurrent(index)
    end,
    onOverflow = function(crumbs, hidden) end,
})

crumbs:setCurrent(1)
crumbs:setSeparator(">")
```

### Notes
- The trail is controlled: clicking a crumb calls `onSelect` but does not change `current`; call `setCurrent` from the callback.
- `setCurrent` never calls `onSelect`.
- The current crumb is display-only unless `clickableCurrent` is true, and `disabled` crumbs never react.
- Collapsing requires at least three crumbs and `collapse = true`; otherwise labels are truncated to fit.
- The ellipsis is interactive only when `onOverflow` is set.
- Separator text takes precedence over the separator icon; the icon is drawn only while `separator` is empty.
- `getItems` returns the internal normalised list, not a copy.
