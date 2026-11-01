# Selection widgets

Factories and public methods for the Pallid selection and option widgets. Every
widget here is client-side; attach it to a tree with the base API described in
[ui-widget.md](ui-widget.md).

All factories live in `Pallid.UI.Widgets` and are created by requiring the
widget file first. `root:add(widget)` below stands for adding the widget to your
tree; see [ui-widget.md](ui-widget.md) for `add`, `remove` and layout.

## Dropdown

Closed field that shows the selected value; opening it shows a popup list. The
list geometry, scrolling and row painting are shared with `multiSelect` through
the `PopupSelect` base class.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- options ((string|table)[]) - Option list; a string becomes both label and value, a table may set `label` (fallback `text`, then `value`), `value`, `icon` and `disabled`.
- opts (table|nil) - Appearance and behaviour; fields below.
- opts.selected (integer|nil) - Initial 1-based selection, 0 or nil for none; applied silently.
- opts.placeholder (string|nil) - Field text while nothing is selected, defaults to `"Select..."`.
- opts.maxHeight (number|nil) - Maximum popup height, defaults to 220.
- opts.itemHeight (number|nil) - Popup row height, defaults to 22.
- opts.listGap (number|nil) - Gap between field and popup, defaults to 2.
- opts.arrowSize (number|nil) - Arrow icon size in pixels, defaults to 9.
- opts.font (UIFont|string|nil) - Label font or a `Pallid.UI.Fonts` key.
- opts.sound (string|false|nil) - Click sound, defaults to `"UISelectListItem"`; `false` or `""` silences it.
- opts.onChange (fun(dropdown, index, value, item)|nil) - Called when the selection changes.
- opts.onOpen (fun(dropdown)|nil) - Called after the popup opens.
- opts.onClose (fun(dropdown)|nil) - Called after the popup closes.

### Returns
- Pallid.UI.Widgets.Dropdown - The new dropdown (`PallidDropdown` in EmmyLua).

### Methods
- `getSelected() -> integer` - 1-based selected index, 0 when nothing is selected.
- `getSelectedItem() -> PallidOption|nil` - Selected option descriptor.
- `getSelectedOption() -> string|nil` - Selected label.
- `getSelectedValue() -> any|nil` - Selected `value`.
- `isSelected(index) -> boolean` - True when the index is the current selection.
- `setSelected(index, silent) -> self` - Selects an index; 0 or nil clears it.
- `clearSelection(silent) -> self` - Clears the field.
- `setOptions(options) -> self` - Replaces the option list (from `PopupSelect`).
- `show() -> self` / `close() -> self` - Opens or closes the popup list.
- `setFont(font) -> self`, `setColors(colors) -> self`, `setEnabled(enabled) -> self`, `setBounds(x, y, w, h) -> self`.

### Example
```lua
require "pallid/ui/widgets/dropdown"

local dd = Pallid.UI.Widgets.dropdown(20, 20, 200, 26, { "Small", "Large" }, {
    selected = 1,
    onChange = function(_, index, value)
        Pallid.log("dropdown", index, value)
    end,
})
root:add(dd)
```

### Notes
- There is no `getValue`/`setValue`; use `getSelectedValue` and `setSelected`.
- `getSelectedValue()` is nil for a table option without `value` (a plain string
  option always reports its label as the value).
- `disabled` only counts when it is the literal `true`; any other value leaves
  the option selectable. The same normalisation is used by `multiSelect`,
  `radioGroup`, `toggleGroup`, `segmentedControl`, `listBox` and
  `multiSelectComboBox`.
- `setSelected` ignores disabled rows, an unchanged index and out-of-range
  indexes (the last case logs), so no callback fires for them.
- `setOptions` closes the popup and clamps the selection silently: if the
  selected row disappears or becomes disabled, the field clears without firing
  `onChange`.
- `setColors` accepts `fill`, `hoverFill`, `listFill`, `border`, `highlight`,
  `arrow`, `markerFill`, `markerBorder`, `check` and `text`.

## ComboBox

Searchable dropdown built on `Popover` + `VirtualList`. The closed field shows
the value; the popover holds a filter field above a virtualised option list, so
long lists stay cheap.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- options ((string|table)[]|nil) - Option list; a table may set `label` (fallback `text`, then `value`) and `value`.
- opts (table|nil) - Behaviour and appearance; fields below.
- opts.placeholder (string|nil) - Field text while no value is selected.
- opts.allowCustom (boolean|nil) - True lets Enter accept typed filter text as the value.
- opts.filter (string|fun(option, label, text): boolean|nil) - Initial filter text, or a predicate; returning `false` excludes the option.
- opts.value (string|nil) - Initial value, applied silently.
- opts.onChange (fun(combo, value, index, option)|nil) - Called after the value changes.
- opts.onFilter (fun(combo, text)|nil) - Called after the filter text changes.
- opts.maxHeight (number|nil) - Maximum list height in pixels, defaults to 200 (at least 22).
- opts.filterPlaceholder (string|nil) - Filter field placeholder, defaults to the translated `"Filter..."`.

### Returns
- Pallid.UI.Widgets.ComboBox - The new combo box (`PallidComboBox` in EmmyLua).

### Methods
- `getValue() -> string|nil` - Current display value.
- `getIndex() -> integer|nil` - One-based raw option index, nil for custom or empty values.
- `setValue(value, silent) -> self` - Sets the value, matching by value or label.
- `setOptions(options, silent) -> self` - Replaces the options and rebuilds the filter.
- `setTextColor(color) -> self` - Field text colour.
- `setEnabled(enabled) -> self` - Disabling also closes the popover.
- `show() -> self`, `close() -> self`, `isOpen() -> boolean`.

### Example
```lua
require "pallid/ui/widgets/combobox"

local combo = Pallid.UI.Widgets.comboBox(20, 60, 200, 26, {
    { label = "Axe",   value = "axe" },
    { label = "Knife", value = "knife" },
}, {
    allowCustom = true,
    onChange = function(_, value, index)
        Pallid.log("combo", value, index)
    end,
})
root:add(combo)
```

### Notes
- This widget uses its own option normalisation: a table without `value` reports
  its label as the value. `icon` and `disabled` are not read here, unlike
  `dropdown` and `multiSelect`.
- `setValue` converts the argument with `tostring` and matches it against values
  or labels; an unknown value is stored as typed and `getIndex()` becomes nil.
  `allowCustom` only affects what Enter accepts while typing.
- `setOptions` only clears `getIndex()` when the old index is beyond the new list
  length. `getValue()` keeps the previous text in that case, and the index is not
  re-checked against the new labels.
- The filter predicate receives `(rawOption, label, text)`; matching is a
  case-insensitive substring test on the label before the predicate runs.
- Up/Down/Enter/Escape work while the filter field has focus; the combo polls raw
  key state because native text entry suppresses `Events.OnKeyPressed`.

## MultiSelect

Multi-select field with chips for the selected labels and a popup list that stays
open while toggling. Chip widths are measured only when options, selection, font
or bounds change.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- options ((string|table)[]) - Option list; same entry shape as `dropdown`.
- opts (table|nil) - Appearance and behaviour; fields below.
- opts.selected (integer[]|nil) - Initially checked 1-based indexes, applied silently.
- opts.placeholder (string|nil) - Field text while nothing is selected, defaults to `"None selected"`.
- opts.maxHeight (number|nil) - Maximum popup height, defaults to 220.
- opts.itemHeight (number|nil) - Popup row height, defaults to 22.
- opts.listGap (number|nil) - Gap between field and popup, defaults to 2.
- opts.arrowSize (number|nil) - Arrow icon size in pixels, defaults to 9.
- opts.font (UIFont|string|nil) - Label font or a `Pallid.UI.Fonts` key.
- opts.sound (string|false|nil) - Toggle sound, defaults to `"UIToggleTickBox"`; `false` or `""` silences it.
- opts.onChange (fun(multi, index, checked, item)|nil) - Called after an option is toggled.
- opts.onOpen (fun(multi)|nil), opts.onClose (fun(multi)|nil) - Popup lifecycle callbacks.

### Returns
- Pallid.UI.Widgets.MultiSelect - The new multi-select (`PallidMultiSelect` in EmmyLua).

### Methods
- `getSelected() -> integer[]` - Checked 1-based indexes in ascending order.
- `getSelectedOptions() -> string[]` - Checked labels in ascending order.
- `getSelectedCount() -> integer` - Number of checked options.
- `isSelected(index) -> boolean` - True when the option is checked.
- `setSelected(index, checked, silent) -> self` - Sets one option.
- `setAll(checked, silent) -> self` - Checks or clears every enabled option.
- `clear(silent) -> self` - Clears the selection (`setAll(false)`).
- `setOptions(options) -> self`, `show() -> self`, `close() -> self`.
- `setColors(colors) -> self`, `setFont(font) -> self`, `setEnabled(enabled) -> self`, `setBounds(x, y, w, h) -> self`.

### Example
```lua
require "pallid/ui/widgets/multiselect"

local ms = Pallid.UI.Widgets.multiSelect(20, 100, 240, 26, { "Doors", "Windows", "Locks" }, {
    selected = { 1, 3 },
    onChange = function(_, index, checked)
        Pallid.log("multi", index, checked)
    end,
})
root:add(ms)
```

### Notes
- `setSelected` requires the `checked` argument; it is coerced with `== true`, so
  passing nil clears the option. Disabled options cannot be checked.
- `setOptions` drops selected indexes that no longer exist or became disabled
  without firing `onChange`.
- The constructor writes its default sound into the `opts` table you pass, so
  reusing that table for another widget carries the value over.
- `setColors` accepts the popup keys plus `chip` for the chip fill.

## MultiSelectComboBox

Searchable multi-select dropdown. The field summarises the selection (one label
or `"N selected"`); the popover holds a filter field and a virtualised list with
checkboxes. Clicking a row toggles it without closing the popover.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- options ((string|table)[]|nil) - Option list; same entry shape as `dropdown` (icons and `disabled` are honoured).
- opts (table|nil) - Behaviour and appearance; fields below.
- opts.placeholder (string|nil) - Field text while nothing is selected.
- opts.selected (integer[]|nil) - Initially selected 1-based indexes, applied silently.
- opts.filter (string|fun(item, text): boolean|nil) - Initial filter text, or a predicate receiving the normalised option; returning `false` excludes it.
- opts.onChange (fun(combo, values, indexes)|nil) - Called after the selection changes.
- opts.onFilter (fun(combo, text)|nil) - Called after the filter text changes.
- opts.maxHeight (number|nil) - Maximum list height in pixels, defaults to 200 (at least 22).
- opts.filterPlaceholder (string|nil) - Filter field placeholder, defaults to the translated `"Filter..."`.

### Returns
- Pallid.UI.Widgets.MultiSelectComboBox - The new widget (`PallidMultiSelectComboBox` in EmmyLua).

### Methods
- `getSelected() -> values, indexes` - Selected values then selected 1-based indexes, both in option order.
- `setSelectedIndexes(indexes, silent) -> self` - Replaces the selection; nil clears it.
- `getSelectedCount() -> integer` - Number of selected options.
- `clearSelection(silent) -> self` - Clears every selected option.
- `setOptions(options, silent) -> self` - Replaces the options and prunes stale indexes.
- `show() -> self`, `close() -> self`, `isOpen() -> boolean`, `setEnabled(enabled) -> self`.

### Example
```lua
require "pallid/ui/widgets/multiselectcombo"

local mc = Pallid.UI.Widgets.multiSelectComboBox(20, 140, 240, 26, {
    { label = "Nails",  value = "nails" },
    { label = "Screws", value = "screws" },
}, {
    onChange = function(_, values, indexes)
        Pallid.log("multiCombo", #values, #indexes)
    end,
})
root:add(mc)
```

### Notes
- `getSelected` returns two values, not one table; the value list falls back to
  the label for options without `value`.
- `setSelectedIndexes` replaces rather than merges, floors each index and ignores
  out-of-range values, but it does not reject disabled options.
- `setOptions` calls `onChange` whenever `silent` is not true, even if nothing was
  pruned.
- Enter and Escape close the popover; clicking a row only toggles it.
- The field shows a clear button while something is selected; clicking it calls
  `clearSelection()`.

## RadioGroup

Vertical list with a single selection and a radio-circle marker. Input is
pointer-only.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- options ((string|table)[]) - Option list; same entry shape as `dropdown`.
- opts (table|nil) - Shared option-list settings; fields below.
- opts.selected (integer|nil) - Initial 1-based selection, 0 or nil for none.
- opts.rowHeight (number|nil) - Row height, defaults to 22 and clamped to at least 16.
- opts.font (UIFont|string|nil) - Label font or a `Pallid.UI.Fonts` key.
- opts.onChange (fun(group, index, label, item)|nil) - Called when the selection changes; index is 0 on clear.
- opts.sound (string|false|nil) - Click sound, defaults to `"UISelectListItem"`; `false` or `""` silences it.

### Returns
- Pallid.UI.Widgets.RadioGroup - The new group (`PallidRadioGroup` in EmmyLua).

### Methods
- `getSelected() -> integer` - 1-based selected index, 0 when none.
- `isSelected(index) -> boolean` - True when the index is selected.
- `getSelectedOption() -> string|nil` - Selected label.
- `setSelected(index, silent) -> self` - Selects an index; 0 or nil clears it.
- `clearSelection(silent) -> self` - Clears the selection.
- `setOptions(options) -> self`, `setRowHeight(height) -> self`, `setFont(font) -> self`.
- `setColors(colors) -> self`, `setEnabled(enabled) -> self`, `setBounds(x, y, w, h) -> self`.

### Example
```lua
require "pallid/ui/widgets/radiogroup"

local group = Pallid.UI.Widgets.radioGroup(20, 20, 200, { "Low", "Normal", "High" }, {
    selected = 2,
    onChange = function(_, index, label)
        Pallid.log("radio", index, label)
    end,
})
root:add(group)
```

### Notes
- There is no height parameter: the widget height is `rowHeight * #options`.
  `setBounds(x, y, w, 0)` re-enables that automatic height after a fixed one.
- `onChange` receives the label, not the caller value. There is no value getter;
  when an index is selected, read `group.items[group:getSelected()].value`.
- Disabled options cannot be selected and `setSelected` ignores them silently.
- Keyboard navigation is not implemented; only pointer input selects rows.
- `setColors` accepts `text`, `markerFill`, `markerBorder`, `selectedFill`,
  `checkColor` and `hover`.

## ToggleGroup

Multi-select list with square check-box markers. Input is pointer-only.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- options ((string|table)[]) - Option list; same entry shape as `dropdown`.
- opts (table|nil) - Shared option-list settings; fields below.
- opts.selected (integer[]|nil) - Initially checked 1-based indexes; any other type is logged and ignored.
- opts.rowHeight (number|nil) - Row height, defaults to 22 and clamped to at least 16.
- opts.font (UIFont|string|nil) - Label font or a `Pallid.UI.Fonts` key.
- opts.onChange (fun(group, index, checked, label, item)|nil) - Toggle callback.
- opts.sound (string|false|nil) - Toggle sound, defaults to `"UIToggleTickBox"`; `false` or `""` silences it.

### Returns
- Pallid.UI.Widgets.ToggleGroup - The new group (`PallidToggleGroup` in EmmyLua).

### Methods
- `getSelected() -> integer[]` - Checked 1-based indexes in ascending order.
- `getSelectedCount() -> integer` - Number of checked options.
- `isSelected(index) -> boolean` - True when the option is checked.
- `setSelected(index, checked, silent) -> self` - Sets one option.
- `setAll(checked, silent) -> self` - Checks or clears every enabled option.
- `clear(silent) -> self` - Clears every checked option.
- `setOptions(options) -> self`, `setRowHeight(height) -> self`, `setFont(font) -> self`.
- `setColors(colors) -> self`, `setEnabled(enabled) -> self`, `setBounds(x, y, w, h) -> self`.

### Example
```lua
require "pallid/ui/widgets/togglegroup"

local group = Pallid.UI.Widgets.toggleGroup(20, 120, 200, { "Sound", "Music", "Ambient" }, {
    selected = { 1, 2 },
    onChange = function(_, index, checked, label)
        Pallid.log("toggle", index, checked, label)
    end,
})
root:add(group)
```

### Notes
- `setSelected` coerces `checked` with `== true`, so passing nil unchecks the
  option; disabled options cannot be checked.
- Height is automatic (`rowHeight * #options`); `setBounds(x, y, w, 0)` restores
  automatic height.
- There is no label or value getter; read `group.items[index]`.
- `setOptions` removes checked indexes that no longer exist or became disabled
  without firing `onChange`.

## SegmentedControl

Row of joined segments with exactly one active segment. The active thumb slides
between segments unless animation is disabled.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- options ((string|table)[]) - Segment list; same entry shape as `dropdown`.
- opts (table|nil) - Appearance and behaviour; fields below.
- opts.selected (integer|nil) - Initial 1-based segment; invalid or disabled values fall back to the first enabled segment.
- opts.onChange (fun(control, index, label, item)|nil) - Selection callback; index is 0 on clear.
- opts.sound (string|false|nil) - Click sound, defaults to `"UIActivateTab"`; `false` or `""` silences it.
- opts.animated (boolean|nil) - `false` snaps the thumb instead of sliding it; defaults to true.
- opts.font (UIFont|string|nil) - Label font or a `Pallid.UI.Fonts` key.

### Returns
- Pallid.UI.Widgets.SegmentedControl - The new control (`PallidSegmentedControl` in EmmyLua).

### Methods
- `getSelected() -> integer` - Active 1-based segment, 0 when none.
- `isSelected(index) -> boolean` - True when the segment is active.
- `getSelectedOption() -> string|nil` - Active label.
- `getSelectedItem() -> PallidOption|nil` - Active option descriptor.
- `setSelected(index, silent) -> self` - Selects a segment.
- `clearSelection(silent) -> self` - Clears the active segment.
- `setOptions(options) -> self`, `setAnimated(animate) -> self`, `setFont(font) -> self`.
- `setColors(colors) -> self`, `setEnabled(enabled) -> self`, `setBounds(x, y, w, h) -> self`.

### Example
```lua
require "pallid/ui/widgets/segmentedcontrol"

local tabs = Pallid.UI.Widgets.segmentedControl(20, 200, 240, 26, { "Day", "Week", "Month" }, {
    selected = 1,
    animated = false,
    onChange = function(_, index, label)
        Pallid.log("segment", index, label)
    end,
})
root:add(tabs)
```

### Notes
- When `opts.selected` is absent, invalid or disabled, the control starts on the
  first enabled segment, so `getSelected()` is 0 only for an empty or fully
  disabled list, or after `clearSelection()`.
- `setSelected(0)` is rejected and logged; use `clearSelection()` instead.
- `setSelected` does nothing when the segment is already active or disabled, so
  no callback fires.
- `setColors` accepts `track`, `trackBorder`, `active`, `activeText`, `hover` and
  `text`.

## OptionList

Shared option-list implementation (`pallid/ui/widgets/optionlist.lua`). It is not
a widget and has no factory: the module returns an installer that `radioGroup`
and `toggleGroup` already apply.

**Side:** client

### Parameters
- OptionList (table) - Class table that receives the shared methods.

### Returns
- function - Installer that augments the given class in place.

### Notes
- The installed public methods are `setOptions(options)`, `setRowHeight(height)`,
  `setFont(font)`, `setColors(colors)`, `setEnabled(enabled)` and
  `setBounds(x, y, w, h)`; see `radioGroup` and `toggleGroup`.
- `rowHeight` is rounded and clamped to at least 16 px, the marker size plus 2.
- `setBounds` with `h <= 0` re-enables automatic height
  (`rowHeight * #options`).
- `setColors` accepts `text`, `markerFill`, `markerBorder`, `selectedFill`,
  `checkColor` and `hover`.
- Rows are pointer-only: there is no keyboard selection in this shared layer.

## ListBox

Selectable list built on `VirtualList`, with option normalisation, default row
painting, single/multi/none selection and keyboard navigation. A custom `render`
can replace the row painter entirely.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Items and behaviour; fields below.
- opts.items ((string|table)[]|nil) - Initial items; same entry shape as `dropdown`.
- opts.rowHeight (number|fun(index): number|nil) - Row height, defaults to 22.
- opts.selectionMode ("single"|"multi"|"none"|nil) - Defaults to `"single"`.
- opts.getLabel (fun(item, index): string|nil) - Label resolver used by the default row painter.
- opts.onSelect (fun(list, index, item)|nil) - Selection callback; index is nil when the selection is cleared.
- opts.onActivate (fun(list, index, item)|nil) - Enter callback.
- opts.render (fun(el, index, x, y, w, h, state, item, list)|nil) - Custom row painter.
- opts.emptyText (string|nil) - Text shown when the list has no items.
- opts.background (PallidColor|nil), opts.border (PallidColor|nil) - List fill and outline.
- opts.radius (number|nil) - Corner radius, defaults to 4.
- opts.barSize (number|nil), opts.barGap (number|nil) - Scrollbar thickness and gap.

### Returns
- Pallid.UI.Widgets.ListBox - The new list box (`PallidListBox` in EmmyLua).

### Methods
- `setItems(items, silent) -> self` - Replaces the items and clears the selection.
- `getItems() -> PallidOption[]` - Normalised items.
- `getItem(index) -> PallidOption|nil` - Item at a 1-based index.
- `setItem(index, item) -> self` - Replaces one item.
- `setSelected(index, silent) -> self` - Selects a row; nil clears it.
- `getSelected() -> integer|nil` - Selected row index.
- `getSelectedItem() -> PallidOption|nil` - Selected item.
- `scrollToItem(index) -> self` - Scrolls a row into view.
- `setBounds(x, y, w, h) -> self`, `setEnabled(enabled) -> self`.
- `preferredSize(maxW, maxH) -> width, height` - Preferred size hint.

### Example
```lua
require "pallid/ui/widgets/listbox"

local box = Pallid.UI.Widgets.listBox(20, 20, 240, 180, {
    items = { "Axe", "Knife", "Hammer" },
    selectionMode = "single",
    emptyText = "Nothing here",
    onSelect = function(_, index, item)
        Pallid.log("list", index, item and item.label)
    end,
})
root:add(box)
```

### Notes
- `setItems` clears the selection and then fires `onSelect(self, nil, nil)`
  unless `silent` is true.
- In `"multi"` mode the inner list keeps a set, but `getSelected()` returns only
  the most recent row; query the full set with `box.list:isSelected(index)`.
- `"none"` mode still highlights hover but never selects.
- Keyboard support is Up/Down/Home/End plus Enter for `onActivate`; it is handled
  by `onKeyPress(key)` and requires focus.
- `opts.rowHeight` may be a function, which the inner `VirtualList` resolves per
  row.

## PickerField

Shared compact field chrome for `datePicker` and `timePicker`: hover/press
animation, an icon, a caption and the popover lifecycle. It has no factory of its
own; use `Pallid.UI.Widgets.datePicker` or `Pallid.UI.Widgets.timePicker`.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts.radius (number|nil) - Corner radius, defaults to 4.
- opts.icon (string|false|nil) - Registered icon name or texture path (any string containing `/`); `false` hides the icon.

### Returns
- Pallid.UI.Widgets.PickerField - Base class only (`PallidPickerField` in EmmyLua); subclasses return their own instance.

### Methods
- `setIcon(icon) -> self` - Accepts a registered icon name, a texture path or `false` to hide the icon.
- `close() -> self` - Closes the popover if it was created.
- `isOpen() -> boolean` - True while the popover is visible.
- `setEnabled(enabled) -> self`, `setBounds(x, y, w, h) -> self` - Inherited from the base widget.

### Example
```lua
require "pallid/ui/widgets/datepicker"

local picker = Pallid.UI.Widgets.datePicker(20, 20, 140, 26, {
    onChange = function(_, year, month, day)
        Pallid.log("date", year, month, day)
    end,
})
picker:setIcon(false)
root:add(picker)
```

### Notes
- There is no `Pallid.UI.Widgets.pickerField` factory. Subclasses implement
  `open()`; a bare base instance has no `open`, so clicking it fails. Always use
  `datePicker` or `timePicker`.
- `setIcon` treats any string containing `/` as a texture path and anything else
  as a registered icon name.
- The shared initialiser also declares `onChange`, but only the subclasses store
  it; the base field itself never calls it.
- The concrete pickers are documented in
  [widgets-charts.md](widgets-charts.md#datepicker) and
  [widgets-charts.md](widgets-charts.md#timepicker).
