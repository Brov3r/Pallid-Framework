# Pallid.UI input widgets

Factories for text entry, numeric entry and selection controls. Every factory lives on `Pallid.UI.Widgets` and returns a widget you attach to a parent with the base tree API described in [ui-widget.md](ui-widget.md); enable/disable, visibility, bounds and focus come from that base class.

All widgets here are client-side and draw inside a Pallid host element. Text fields are backed by the game's `ISTextEntryBox`, which owns layout, IME, clipboard and key repeat; Pallid positions that native box, mirrors its text and paints the chrome.

Each example below assumes the matching widget file has been required (`require "pallid/ui/widgets/inputtext"`, `require "pallid/ui/widgets/checkbox"`, and so on) and that `parent` is a widget already attached to a live tree.

```lua
require "pallid/ui/widgets/inputtext"

local E = Pallid.UI.Widgets
local field = E.inputText(8, 8, 240, 26, { placeholder = "Name", })
parent:add(field)
```

## InputText

Single-line text field with optional input pattern, password masking, native filters and rounded chrome.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Options; all fields are optional.
- opts.text (string, default `""`) - Initial value.
- opts.placeholder (string|nil) - Placeholder shown while the value is empty.
- opts.placeholderColor (PallidColor, default `Pallid.UI.Color.gray`) - Placeholder RGB tint; the engine forces alpha 1.
- opts.textColor (PallidColor, default `Pallid.UI.Color.textPrimary`) - Text tint.
- opts.font (UIFont|string, default `Pallid.UI.Fonts.default`) - Font object or a key from `Pallid.UI.Fonts`.
- opts.maxLength (integer, default `0`) - Character cap; `0` keeps the engine default.
- opts.pattern (string|nil) - Input template such as `##-##-###`; compiled with `Pallid.UI.Mask`.
- opts.masked (boolean, default `false`) - Native password masking with `*`.
- opts.mask (boolean|string|nil) - Deprecated alias for `masked`; any value except `false`/`nil` enables masking and the string itself is unused.
- opts.numeric (boolean, default `false`) - Keeps digits, one dot and an optional leading minus.
- opts.decimals (integer|nil, default `nil`) - Fractional digit limit when `numeric` is on; `nil` is unlimited.
- opts.allowNegative (boolean, default `true`) - Accepts a leading minus when `numeric` is on.
- opts.onlyText (boolean, default `false`) - Native filter that accepts ASCII letters only.
- opts.forceUpperCase (boolean, default `false`) - Native upper-case conversion.
- opts.clearButton (boolean, default `false`) - Shows the native clear button.
- opts.selectable (boolean, default `true`) - Allows selecting the text.
- opts.readOnly (boolean, default `false`) - Select-only value: no native caret, drag to select.
- opts.editable (boolean, default `nil`) - `false` is an alias for `readOnly = true`.
- opts.rounded (boolean, default `false`) - Enables rounded chrome with radius `4`.
- opts.radius (number|table, default `nil`) - Corner radius, or `{ tl, tr, br, bl }`; `nil` or `0` draws square chrome.
- opts.paddingX (number, default `min(7 + radius/2, 12)`) - Horizontal text padding.
- opts.paddingY (number, default `4 + min(radius/2, 2)`) - Vertical text padding.
- opts.padding (number|nil) - Deprecated shorthand that sets both paddings.
- opts.background (PallidColor|false, default `Pallid.UI.Color.surface`) - Field fill; `false` draws none.
- opts.border (PallidColor|false, default `Pallid.UI.Color.border`) - Field border; `false` draws none.
- opts.borderWidth (number, default `1`) - Border thickness.
- opts.transparent (boolean, default `false`) - Draws no widget chrome at all.
- opts.onChange (function|nil) - Called as `(input, text, raw)` after the value changes.
- opts.onSubmit (function|nil) - Called as `(input, text, raw)` when Enter is pressed.
- opts.onKeyPress (function|nil) - Called as `(input, key)` before the built-in editor shortcuts; return `true` to consume the key.

### Returns
- PallidInputText - Single-line field; class `PallidInputText` (base `PallidInputBase`), registered as `Pallid.UI.Widgets.InputText`.

### Methods
- `getText()` -> string - Current native value, formatted when a pattern is set.
- `getRawText()` -> string - Value without pattern literals.
- `isComplete()` -> boolean - True when every pattern slot is filled; without a pattern, true for any non-empty value.
- `setText(value, silent)` -> self - Replaces the value and reformats it; `silent` skips `onChange`.
- `setPattern(pattern)` -> self - Replaces or removes (`nil`) the input pattern.
- `setMasked(masked)` -> self - Toggles native password masking.
- `isMasked()` -> boolean - True while the value is masked.
- `getCursorPos()` -> integer - Native caret offset.
- `setCursorPos(position)` -> self - Moves the native caret.
- `selectAll()` -> self - Selects the whole native value.
- `clear()` -> self - Clears the value through the native clear method.
- `setPlaceholder(text)` / `getPlaceholder()` -> self / string|nil - Replace or read the placeholder.
- `setPlaceholderColor(color)` -> self - Replaces the placeholder tint.
- `setTextColor(color)` -> self - Replaces the text tint.
- `setReadOnly(readOnly)` -> self - Switches between editable and select-only.
- `setEnabled(enabled)` / `setVisible(visible)` -> self - Also update the native box.
- `setNativeVisible(visible)` - Shows or hides only the native box.
- `blurNative()` - Unfocuses the native box and clears the root focus pointer.

### Example
```lua
local E = Pallid.UI.Widgets

local phone = E.inputText(8, 8, 240, 26, {
    pattern  = "###-###-####",
    onChange = function(_, text, raw)
        Pallid.log("formatted " .. text .. " raw " .. raw)
    end,
})

parent:add(phone)
Pallid.log(tostring(phone:isComplete()))
```

### Notes
- `pattern` is ignored for multiline or masked fields, and `maxLength` is ignored while a pattern is set: the native cap becomes the pattern length.
- With a pattern, the native `numeric`, `onlyText` and `forceUpperCase` filters are disabled and the pattern rules decide what is accepted.
- The native box is a separate always-on-top UI element. It is hidden whenever it is not fully inside the active clip rectangle, so a partially scrolled field inside a scroll panel shows only the Pallid chrome until it is fully visible.
- `setVisible(false)` hides and blurs the native box, `setEnabled(false)` blurs it, and detaching the widget hides it and unregisters it from the root, so a hidden field cannot keep capturing keys.
- `onChange` fires for every native edit, including edits made through `setText` unless `silent` is passed.

## InputArea

Multi-line text area over the same native text box, with wrapping and a line cap.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Options; `multiline` is forced to `true`.
- opts.text (string, default `""`) - Initial value; `\n` separates lines.
- opts.placeholder (string|nil) - Placeholder shown while the value is empty.
- opts.placeholderColor (PallidColor, default `Pallid.UI.Color.gray`) - Placeholder RGB tint.
- opts.textColor (PallidColor, default `Pallid.UI.Color.textPrimary`) - Text tint.
- opts.font (UIFont|string, default `Pallid.UI.Fonts.default`) - Font object or `Pallid.UI.Fonts` key.
- opts.maxLength (integer, default `0`) - Character cap; `0` keeps the engine default.
- opts.maxLines (integer, default `1000`) - Maximum line count.
- opts.wrap (boolean, default `true`) - Wraps long lines visually; the logical value is unchanged.
- opts.masked (boolean, default `false`) - Native password masking.
- opts.numeric (boolean, default `false`) - Digits, one dot and an optional leading minus.
- opts.decimals (integer|nil, default `nil`) - Fractional digit limit for `numeric`.
- opts.allowNegative (boolean, default `true`) - Accepts a leading minus for `numeric`.
- opts.onlyText (boolean, default `false`) - Native ASCII-letter filter.
- opts.forceUpperCase (boolean, default `false`) - Native upper-case conversion.
- opts.clearButton (boolean, default `false`) - Shows the native clear button.
- opts.selectable (boolean, default `true`) - Allows selecting the text.
- opts.readOnly (boolean, default `false`) - Select-only value; drag selects.
- opts.editable (boolean, default `nil`) - `false` is an alias for `readOnly = true`.
- opts.mask (boolean|string|nil) - Deprecated alias for `masked`.
- opts.rounded (boolean, default `false`) - Rounded chrome with radius `4`.
- opts.radius (number|table, default `nil`) - Corner radius or `{ tl, tr, br, bl }`.
- opts.paddingX (number, default `min(7 + radius/2, 12)`) - Horizontal text padding.
- opts.paddingY (number, default `4 + min(radius/2, 2)`) - Vertical text padding.
- opts.padding (number|nil) - Deprecated shorthand for both paddings.
- opts.background (PallidColor|false, default `Pallid.UI.Color.surface`) - Field fill.
- opts.border (PallidColor|false, default `Pallid.UI.Color.border`) - Field border.
- opts.borderWidth (number, default `1`) - Border thickness.
- opts.transparent (boolean, default `false`) - Draws no widget chrome.
- opts.onChange (function|nil) - Called as `(input, text, raw)` after the value changes.
- opts.onSubmit (function|nil) - Called as `(input, text, raw)` when Enter is pressed.
- opts.onKeyPress (function|nil) - Called as `(input, key)`; return `true` to consume the key.
- opts.pattern (string|nil) - Accepted but ignored: patterns are single-line only.

### Returns
- PallidInputArea - Multiline field; class `PallidInputArea` (base `PallidInputBase`), registered as `Pallid.UI.Widgets.InputArea`.

### Methods
- All methods documented for `inputText`; `getText()` returns the value with `\n` line breaks.
- `setPattern(pattern)` -> self - Logs and does nothing, because the field is multiline.

### Example
```lua
local E = Pallid.UI.Widgets

local notes = E.inputArea(8, 8, 320, 120, {
    placeholder = "Session notes",
    maxLines    = 8,
    wrap        = true,
})

parent:add(notes)
```

### Notes
- `opts.pattern` is dropped with a log line instead of being applied.
- A multiline box is not vertically centred: the first line starts at the top padding, unlike a single-line field.
- `wrap` only affects painting and native hit-testing; the stored value keeps the original line breaks.

## InputPassword

Password preset over `inputText` with an optional eye button that toggles masking.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Same options as `inputText`; `masked` is forced to `true`.
- opts.revealButton (boolean, default `true`) - Draws the eye toggle; `false` hides it.

### Returns
- PallidInputPassword - Masked single-line field; class `PallidInputPassword` (base `PallidInputText`), registered as `Pallid.UI.Widgets.InputPassword`.

### Methods
- `setMasked(masked)` -> self - Toggles masking and updates the eye icon and tooltip.
- `setBounds(x, y, w, h)` -> self - Also repositions the eye button on the right edge.
- `setEnabled(enabled)` -> self - Enables or disables the field and the eye button together.
- All other methods are inherited from `inputText`.

### Example
```lua
local E = Pallid.UI.Widgets

local password = E.inputPassword(8, 8, 240, 26, {
    placeholder  = "Password",
    revealButton = true,
})

parent:add(password)
```

### Notes
- The mask glyph is always `*`; the engine exposes no custom mask character.
- The eye button is a normal child button that calls `setMasked(not isMasked())`; it reserves `rightInset` space so text does not run underneath it.
- New code can use `inputText` with `masked = true`; this class only adds the toggle.

## InputRich

Multi-line code editor with Pallid-painted syntax highlighting, caret and selection.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Options; base input options are forwarded.
- opts.text (string, default `""`) - Initial text.
- opts.placeholder (string|nil) - Placeholder drawn while the text is empty.
- opts.language (string, default `"lua"`) - Language name registered with `Pallid.UI.RichText`.
- opts.highlight (function|nil) - Called as `(text)`; returns run tables, RichText markup, or `nil` to use the language rules.
- opts.multiline (boolean, default `true`) - Set `false` for a one-line editor.
- opts.font (UIFont|string, default `Pallid.UI.Fonts.small`) - Editor font.
- opts.background (PallidColor, default `Pallid.UI.Color.surface`) - Editor fill.
- opts.border (PallidColor, default `Pallid.UI.Color.border`) - Editor border.
- opts.padding (number, default native box inset, usually `2`) - Inner text inset.
- opts.selectionColor (PallidColor, default primary at 0.38 alpha) - Selection highlight.
- opts.placeholderColor (PallidColor, default `Pallid.UI.Color.textDisabled`) - Placeholder tint.
- opts.showBackground (boolean, default `true`) - Draws the fill and border.
- opts.radius (number, default `3`) - Corner radius of the editor chrome.
- opts.readOnly (boolean, default `false`) - Prevents editing but keeps native selection for copy.
- opts.onChange (function|nil) - Called as `(input, text, raw)` after the text changes.
- opts.maxLength (integer, default `0`) - Character cap; `0` keeps the engine default.
- opts.pattern / opts.mask / opts.masked (any) - Not supported; cleared with a log line.
- opts.numeric (boolean) - Not supported; forced to `false` with a log line.

### Returns
- PallidInputRich - Rich editor; class `PallidInputRich` (base `PallidInputArea`), registered as `Pallid.UI.Widgets.InputRich`.

### Methods
- `getText()` -> string - Current text from the native box.
- `setText(value, silent)` -> self - Replaces the text and drops cached layout and selection.
- `setLanguage(language)` -> self - Switches the highlighting language.
- `setHighlight(fn)` -> self - Installs a custom run provider.
- `refreshHighlight()` -> self - Drops cached runs after rules changed at runtime.
- `cursorLineCol()` -> integer, integer - 1-based caret line and column.
- `effectiveLineHeight()` -> number - Painted line height in pixels.
- `visibleLineCount()` -> number - Lines that fit in the viewport.
- `indexAt(px, py)` -> integer|nil, integer|nil - Zero-based UTF-16 index and line at a point.
- `textRect()` -> number, number, number, number - Inner text rectangle.
- `ensureCaretVisible()` / `syncNativeScroll()` - Keep the painted view and native scroll aligned.
- `setReadOnly(readOnly)` -> self - Keeps selection but suppresses the caret.
- `setEnabled(enabled)` -> self - Keeps native selection available for read-only editors.
- `buildRuns(text)` -> table[]|string - Styled runs for the text.
- `setNativeVisible(visible)` - Always hides the native box; the argument is ignored.

### Example
```lua
local E = Pallid.UI.Widgets

local editor = E.inputRich(8, 8, 360, 160, {
    language    = "lua",
    text        = "local x = 1",
    placeholder = "Type Lua code",
})

parent:add(editor)
```

### Notes
- The native box is an input device only: it is kept invisible and every glyph, the caret and the selection are painted by Pallid, so `setTextColor` does not change the visible text colour.
- Wrapping is disabled on the native box; Pallid owns line breaks, so one logical line is one drawn line.
- Inline icon runs are not supported and are logged once; link runs render as plain text without click handling.
- `setNativeVisible` ignores its argument and always hides the native box.

## Checkbox

Checkbox with a pill switch or a square tick box, optionally tri-state.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- opts (table|nil) - Content and behaviour.
- opts.checked (boolean|nil, default `false`) - Initial boolean state.
- opts.state (boolean|nil, default `nil`) - Initial tri-state value; takes precedence over `checked` when not `nil`.
- opts.tristate (boolean, default `false`) - Enables the `nil` indeterminate state.
- opts.variant ("switch"|"box", default `"switch"`) - Pill switch or square box.
- opts.label (string|nil) - Text drawn to the right; an empty string is treated as `nil`.
- opts.onChange (function|nil) - Called as `(checkbox, state)` after a change.
- opts.sound (string|false, default `"UIToggleTickBox"`) - UI sound name; `false` or `""` silences it.
- opts.width (number, default `44`) - Switch width; the box variant ignores it and uses the height.
- opts.height (number, default `22`) - Control height, also the box size.
- opts.flat (boolean, default `false`) - Plain rectangle track instead of rounded chrome.
- opts.border (boolean, default `true`) - `false` skips the track border.

### Returns
- PallidCheckbox - Checkbox instance; class `PallidCheckbox`, registered as `Pallid.UI.Widgets.Checkbox`.

### Methods
- `getState()` -> boolean|nil - Current value; `nil` only in tri-state mode.
- `setState(state, silent)` -> self - Sets the value; `nil` is normalised to `false` outside tri-state mode.
- `setChecked(checked, silent)` -> self - Boolean compatibility setter; never sets `nil`.

### Example
```lua
local E = Pallid.UI.Widgets

local toggle = E.checkbox(8, 8, {
    label    = "Enable feature",
    checked  = true,
    onChange = function(_, state)
        Pallid.log(tostring(state))
    end,
})

parent:add(toggle)
```

### Notes
- `checked` is a compatibility mirror: it is `true` only when `state` is `true`, so a tri-state `nil` reads as `checked == false`.
- A `nil` initial state cannot be passed through `opts.state`, because the constructor treats `nil` as "not set"; call `setState(nil)` after creation.
- Clicking cycles `true -> false -> nil -> true` in tri-state mode and toggles `true`/`false` otherwise; the state changes on release inside the control, and the sound plays then.
- The widget width is the track width plus the measured label width, so the label does not wrap.

## Slider

Numeric slider with snapping, ticks and an optional value bubble.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Range and appearance.
- opts.vertical (boolean, default `false`) - Vertical orientation.
- opts.min (number, default `0`) - Minimum value.
- opts.max (number, default `1`) - Maximum value; forced to `min + 1` when not greater than `min`.
- opts.value (number, default `min`) - Initial value, clamped and snapped.
- opts.step (number, default `0`) - Snap step; `0` keeps continuous values.
- opts.showValue (boolean, default `false`) - Enables the hover bubble and the static min/max labels.
- opts.format (string, default `"%.0f"`) - `string.format` pattern for values.
- opts.ticks (number|table|nil) - Equal tick count, or an explicit list of tick values.
- opts.tickSize (number, default `4`) - Tick length in pixels.
- opts.tickColor (PallidColor, default `Pallid.UI.Color.textDisabled`) - Tick colour.
- opts.onChange (function|nil) - Called as `(slider, value)` after a change.

### Returns
- PallidSlider - Slider instance; class `PallidSlider`, registered as `Pallid.UI.Widgets.Slider`.

### Methods
- `setValue(value, silent)` -> self - Clamps, snaps and stores the value; `silent` skips `onChange`.
- `snap(value)` -> number - Clamps and snaps a raw value without storing it.
- `getT()` -> number - Normalized knob position, `0..1`.
- `setT(t)` - Sets the position from a `0..1` fraction.
- `setFromPoint(px, py)` - Sets the value from a root-local point.
- `valueText()` -> string - Formatted current value, cached.
- `formatValue(value)` -> string - Compact text such as `100k` or `1.25M` for labels.
- `hasValueRow()` -> boolean - True when the static min/max labels fit.
- `trackRect()` -> number, number, number, number - Track geometry.
- `tFromPoint(px, py)` -> number - Track fraction at a point.
- `knobPoint()` -> number, number - Knob centre in root-local coordinates.
- `labels()` -> string, string, number, number - Cached formatted min/max and their widths.

### Example
```lua
local E = Pallid.UI.Widgets

local volume = E.slider(8, 8, 240, 32, {
    min       = 0,
    max       = 100,
    value     = 40,
    step      = 5,
    showValue = true,
    onChange  = function(_, value)
        Pallid.log(tostring(value))
    end,
})

parent:add(volume)
```

### Notes
- There is no `getValue`; read the public `value` field.
- The value bubble appears on hover or drag only when `showValue` is set; the static min/max labels additionally need a horizontal slider with `h >= 22`.
- Dragging the knob keeps the grab offset, so the knob does not jump to the cursor; clicking the track jumps to the clicked position.
- With `step > 0` the value is snapped to `min + n * step`, and a snapped value equal to the current value does not fire `onChange`.

## RangeSlider

Two-thumb slider that selects an interval, inheriting geometry and bubbles from `slider`.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Range and appearance.
- opts.min (number, default `0`) - Minimum value.
- opts.max (number, default `100`) - Maximum value.
- opts.low (number, default `min`) - Initial lower value.
- opts.high (number, default `max`) - Initial upper value.
- opts.step (number, default `0`) - Snap step; `0` keeps continuous values.
- opts.showValue (boolean, default `false`) - Enables the bubbles and min/max labels.
- opts.format (string, default `"%.0f"`) - `string.format` pattern for values.
- opts.ticks (number|table|nil) - Equal tick count, or explicit tick values.
- opts.tickSize (number, default `4`) - Tick length in pixels.
- opts.tickColor (PallidColor, default `Pallid.UI.Color.textDisabled`) - Tick colour.
- opts.onChange (function|nil) - Called as `(slider, low, high)` after a change.

### Returns
- PallidRangeSlider - Range slider; class `PallidRangeSlider` (base `PallidSlider`), registered as `Pallid.UI.Widgets.RangeSlider`.

### Methods
- `setValues(low, high, silent)` -> self - Snaps both values, orders them and fires `onChange` once.
- `valueText(value, isLow)` -> string - Cached bubble text for one thumb.
- `tOf(value)` -> number - Track fraction of a value.
- `valueOf(t)` -> number - Snapped value at a track fraction.
- `tFromPoint(px)` -> number - Track fraction at a point.
- `trackLeft()` / `trackWidth()` / `trackY()` -> number - Track geometry.
- `hasValueRow()`, `formatValue(value)`, `trackRect()` - Inherited from `slider`.

### Example
```lua
local E = Pallid.UI.Widgets

local range = E.rangeSlider(8, 8, 240, 32, {
    min      = 0,
    max      = 100,
    low      = 20,
    high     = 80,
    step     = 5,
    onChange = function(_, low, high)
        Pallid.log(low .. " - " .. high)
    end,
})

parent:add(range)
```

### Notes
- There is no `getValues`; read the public `low` and `high` fields.
- `opts.vertical` is copied and then forced to `false`, so a vertical range slider is not supported.
- The inherited `setValue` changes the unused single `value` field, not `low`/`high`; use `setValues`.
- Dragging a thumb past the other one is clamped, so the two thumbs never cross.

## Knob

Rotary dial for bounded values, adjustable by drag, wheel and arrow keys.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- size (number, default `56`, minimum `24`) - Diameter in pixels; the widget is square.
- opts (table|nil) - Range and appearance.
- opts.min (number, default `0`) - Minimum value.
- opts.max (number, default `100`) - Maximum value; forced to `min + 1` when not greater than `min`.
- opts.value (number, default `min`) - Initial value, clamped and snapped.
- opts.step (number, default `1`) - Snap step; `0` keeps continuous values.
- opts.startAngle (number, default `135`) - Arc start in degrees.
- opts.endAngle (number, default `405`) - Arc end in degrees; forced past `startAngle`.
- opts.thickness (number, default 12% of size) - Arc thickness in pixels.
- opts.ticks (number|table|nil) - Equal radial tick count, or explicit tick values.
- opts.tickSize (number, default `5`) - Tick length in pixels.
- opts.tickColor (PallidColor, default `Pallid.UI.Color.textDisabled`) - Tick colour.
- opts.color (PallidColor, default `Pallid.UI.Color.primary`) - Value arc colour.
- opts.track (PallidColor, default `Pallid.UI.Color.border`) - Track arc colour.
- opts.showValue (boolean, default `true`) - Draws the formatted value in the centre.
- opts.format (string, default `"%.0f"`) - `string.format` pattern for the centre label.
- opts.onChange (function|nil) - Called as `(knob, value)` after a change.

### Returns
- PallidKnob - Knob instance; class `PallidKnob`, registered as `Pallid.UI.Widgets.Knob`.

### Methods
- `getValue()` -> number - Current value.
- `setValue(value, silent)` -> self - Clamps, snaps and stores the value; `silent` skips `onChange`.
- `snap(value)` -> number - Clamps and snaps without storing.
- `getT()` -> number - Normalized value, `0..1`.
- `valueText()` -> string - Formatted current value, cached.
- `preferredSize(maxW, maxH)` -> number, number - Square preferred size.

### Example
```lua
local E = Pallid.UI.Widgets

local dial = E.knob(8, 8, 64, {
    min       = 0,
    max       = 10,
    value     = 5,
    step      = 1,
    showValue = true,
})

parent:add(dial)
```

### Notes
- Dragging maps 150 pixels of travel to the whole value range and uses the dominant axis: up and right increase, down and left decrease.
- With `step == 0` the wheel and arrow keys move by 2% of the range.
- The knob accepts focus, so arrow keys, `Home` (min) and `End` (max) work only after it is focused.

## NumberStepper

Number field with minus/plus buttons, auto-repeat and direct typing.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Range, formatting, palette and callbacks.
- opts.min (number, default `0`) - Minimum value; swapped with `max` when greater.
- opts.max (number, default `100`) - Maximum value.
- opts.step (number, default `1`) - Button increment; non-positive values fall back to `1`.
- opts.value (number, default `min`) - Initial value, clamped and rounded.
- opts.decimals (integer, default `0`, range `0..12`) - Fractional digits kept and shown.
- opts.allowNegative (boolean, default `min < 0`) - Accepts a leading minus; `true` always enables it.
- opts.onChange (function|nil) - Called as `(stepper, value)` whenever the value changes.
- opts.onCommit (function|nil) - Called as `(stepper, value)` after Enter or an explicit commit.
- opts.background (PallidColor, default `Pallid.UI.Color.surface`) - Outer fill.
- opts.border (PallidColor, default `Pallid.UI.Color.border`) - Outer border.
- opts.buttonFill (PallidColor, default `Pallid.UI.Color.surfaceMuted`) - Idle button fill.
- opts.buttonHoverColor (PallidColor, default `Pallid.UI.Color.accentSoft`) - Hovered button fill.
- opts.buttonPressedColor (PallidColor, default `Pallid.UI.Color.primarySoft`) - Held button fill.
- opts.glyphColor (PallidColor, default `Pallid.UI.Color.textPrimary`) - Plus/minus tint.
- opts.textColor (PallidColor, default `Pallid.UI.Color.textPrimary`) - Value text tint.

### Returns
- PallidNumberStepper - Stepper instance; class `PallidNumberStepper`, registered as `Pallid.UI.Widgets.NumberStepper`.

### Methods
- `getValue()` -> number - Current value.
- `setValue(value, silent)` -> self - Clamps, rounds and stores; non-number and NaN values are logged and ignored.
- `change(direction)` - Adds one `step`; `direction` must be `-1` or `1`.
- `commit(text)` -> number - Clamps the typed text, rewrites the canonical text, drops focus and fires `onCommit`; `nil` reads the field.
- `setMin(value, silent)` / `setMax(value, silent)` / `setRange(min, max, silent)` -> self - Change the range and re-clamp.
- `setStep(value)` -> self - Replaces the increment; must be positive.
- `setDecimals(decimals, silent)` -> self - Changes precision and re-clamps the value.
- `clamp(value)` -> number - Rounds and clamps without storing.
- `valueText()` -> string - Canonical value text with `decimals` places.
- `syncText()` - Writes the canonical text into the native field.

### Example
```lua
local E = Pallid.UI.Widgets

local count = E.numberStepper(8, 8, 160, 26, {
    min      = 0,
    max      = 99,
    value    = 1,
    step     = 1,
    onChange = function(_, value)
        Pallid.log(tostring(value))
    end,
})

parent:add(count)
```

### Notes
- Typing updates `value` live through `onChange`, but the canonical text is only rewritten when the field is not focused, on Enter, or after a button click.
- Holding a side button repeats after `0.4 s`, then every `0.08 s`.
- `onCommit` fires on every Enter or `commit()` call, even when the value did not change.
- `setValue` ignores a non-number or NaN value with a log line instead of raising an error.
- `allowNegative` cannot be turned off while `min < 0`: the constructor enables it whenever the minimum is negative, even when `false` is passed.

## UnitInput

Numeric field with a unit selector; the stored value is always in base units.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Value and unit settings.
- opts.value (number, default `0`) - Initial value in base units.
- opts.units (table|nil) - Unit descriptors `{ key, label, factor }` or plain strings with factor `1`; `nil` or empty gives one unit named `unit`.
- opts.unit (string|number|nil, default first unit) - Initial unit key, label or one-based index.
- opts.min (number|nil, default `nil`) - Minimum base value.
- opts.max (number|nil, default `nil`) - Maximum base value.
- opts.decimals (number, default `2`) - Fractional digits of the visible number.
- opts.onChange (function|nil) - Called as `(field, baseValue, visibleNumber, unitDescriptor)`.

### Returns
- PallidUnitInput - Unit field; class `PallidUnitInput`, registered as `Pallid.UI.Widgets.UnitInput`.

### Methods
- `getValue()` -> number - Current value in base units.
- `setValue(value, silent)` -> self - Sets the base value, clamps it and refreshes the visible number.
- `getUnit()` -> table - Descriptor of the selected unit.
- `setUnit(unit, silent)` -> self - Selects a unit by key, label or one-based index; unknown units are ignored.
- `setUnits(units, unit, silent)` -> self - Replaces the unit list and selects an initial unit.
- `setEnabled(enabled)` -> self - Enables or disables the field and the selector together.
- `preferredSize(maxW, maxH)` -> number, number - Preferred size.
- `layout()` - Repositions the field and the selector.

### Example
```lua
local E = Pallid.UI.Widgets

local distance = E.unitInput(8, 8, 260, 26, {
    value = 1500,
    unit  = "m",
    units = {
        { key = "m",  label = "m",  factor = 1 },
        { key = "km", label = "km", factor = 1000 },
    },
})

parent:add(distance)
```

### Notes
- `factor` converts the selected unit back to the base value: the visible number is `value / factor` and typing multiplies by `factor`.
- `min` and `max` apply to the base value, not to the visible number.
- The unit selector is a fixed `82` px combo box; the numeric field takes the remaining width minus a `4` px gap.
- `getUnit()` returns the internal descriptor table, so treat it as read-only.

## DurationInput

Duration field that stores seconds and displays them in a chosen time unit.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Range and unit settings.
- opts.value (number, default `0`) - Initial duration in seconds.
- opts.unit (string, default `"s"`) - Initial unit key.
- opts.units (table, default `{ "ms", "s", "min", "h" }`) - Unit keys offered by the selector.
- opts.min (number|nil, default `nil`) - Minimum duration in seconds.
- opts.max (number|nil, default `nil`) - Maximum duration in seconds.
- opts.decimals (number, default `3`) - Fractional digits of the visible number.
- opts.onChange (function|nil) - Called as `(field, seconds, visibleNumber, unitKey)`.

### Returns
- PallidDurationInput - Duration field; class `PallidDurationInput`, registered as `Pallid.UI.Widgets.DurationInput`.

### Methods
- `getValue()` -> number - Current duration in seconds.
- `setValue(seconds, silent)` -> self - Sets the duration, clamps it and refreshes the visible number.
- `getUnit()` -> string - Current unit key.
- `setUnit(unit, silent)` -> self - Changes the display unit without changing the duration.
- `setEnabled(enabled)` -> self - Enables or disables the field and the selector together.
- `preferredSize(maxW, maxH)` -> number, number - Preferred size.
- `layout()` - Repositions the field and the selector.

### Example
```lua
local E = Pallid.UI.Widgets

local delay = E.durationInput(8, 8, 260, 26, {
    value    = 90,
    unit     = "s",
    onChange = function(_, seconds, number, unit)
        Pallid.log(string.format("%s %s = %s s", tostring(number), unit, tostring(seconds)))
    end,
})

parent:add(delay)
```

### Notes
- Only these unit keys have a factor: `ms` (0.001), `s` (1), `min` (60), `h` (3600), `d` (86400). A key listed in `opts.units` without a factor is offered but cannot be selected.
- `min` and `max` are compared against seconds, not against the visible number.
- The unit selector is a fixed `76` px combo box; the numeric field takes the remaining width minus a `4` px gap.

## Keybind

Button-like field that captures the next key or mouse button and stores its modifiers.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Initial binding and appearance.
- opts.key (integer|nil) - Keyboard key code, e.g. `Keyboard.KEY_S`.
- opts.mouse (string|nil) - Mouse binding: `"left"`, `"right"` or `"middle"`.
- opts.ctrl (boolean, default `false`) - Initial Ctrl modifier.
- opts.shift (boolean, default `false`) - Initial Shift modifier.
- opts.alt (boolean, default `false`) - Initial Alt modifier.
- opts.win (boolean, default `false`) - Initial Windows-key modifier.
- opts.icon (string|false|nil, default keyboard icon) - Icon name or texture path; `false` hides it.
- opts.onChange (function|nil) - Called as `(keybind, key, labelText)` after a change.
- opts.onComboChange (function|nil) - Called as `(keybind, combo)` with the full combo table.
- opts.onValidate (function|nil) - Called as `(combo)`; return `false` to reject a captured binding.

### Returns
- PallidKeybind - Keybind field; class `PallidKeybind`, registered as `Pallid.UI.Widgets.Keybind`.

### Methods
- `isBound()` -> boolean - True when a key, mouse button or modifier is set.
- `isListening()` -> boolean - True while the field is capturing input.
- `comboText()` -> string - Human-readable combo, or the localized "Unbound".
- `getCombo()` -> table - `{ key, mouse, ctrl, shift, alt, win }`.
- `getKey()` -> integer|nil - Assigned key code.
- `getMouse()` -> string|nil - Assigned mouse button.
- `getKeyName()` -> string|nil - Display name of the assigned key.
- `setKey(key, silent)` -> self - Assigns a key and clears all modifiers.
- `setCombo(key, ctrl, shift, alt, win, silent)` -> self - Assigns a key combination.
- `setMouseCombo(mouse, ctrl, shift, alt, win, silent)` -> self - Assigns a mouse combination; any non-`nil` value other than `"right"`/`"middle"` becomes `"left"`.
- `clear()` -> self - Removes the binding and fires `onChange`.
- `setIcon(icon)` -> self - Accepts a registered icon name, a texture path or `false`.

### Example
```lua
local E = Pallid.UI.Widgets

local bind = E.keybind(8, 8, 200, 28, {
    key      = Keyboard.KEY_S,
    ctrl     = true,
    onChange = function(_, _, text)
        Pallid.log("bound " .. text)
    end,
})

parent:add(bind)
```

### Notes
- Clicking the field starts capture; the next key or mouse button becomes the binding. Every key is bindable, including Escape, Backspace and Delete.
- A modifier pressed alone becomes its own binding after `0.6 s`, so `Ctrl+S` still records as a combination.
- The cross cancels capture while listening and clears the binding otherwise.
- Key names come from a fixed US-English table, not from the OS layout, so the displayed key matches the physical key.
- `onValidate` only guards captured input; `setKey`, `setCombo` and `setMouseCombo` bypass it.

## TagInput

Tag editor with a text field on the first row and removable chips below.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number|nil) - Height in pixels; `nil` or `0` fits one input row plus one chip row.
- opts (table|nil) - Content and behaviour.
- opts.tags (string[]|nil, default empty) - Initial tags; empty strings are dropped.
- opts.maxTags (integer, default `0`) - Maximum tag count; `0` is unlimited.
- opts.placeholder (string|nil) - Placeholder of the text field.
- opts.validate (function|nil) - Called as `(tag)`; return `false` to reject the tag.
- opts.onChange (function|nil) - Called as `(input, tags)` after the tag list changes.
- opts.inputHeight (number, default `24`, minimum `16`) - Height of the text field.

### Returns
- PallidTagInput - Tag editor; class `PallidTagInput`, registered as `Pallid.UI.Widgets.TagInput`.

### Methods
- `getTags()` -> string[] - Live internal tag list in insertion order.
- `setTags(tags, silent)` -> self - Replaces every tag, applying `maxTags`.
- `addTag(tag, silent)` -> boolean - Trims, validates, rejects duplicates and adds; returns `true` when added.
- `removeTag(index, silent)` -> boolean - Removes a one-based tag index.
- `setBounds(x, y, w, h)` -> self - Also resizes the field and recomputes the chip layout.

### Example
```lua
local E = Pallid.UI.Widgets

local tags = E.tagInput(8, 8, 300, 96, {
    tags        = { "alpha", "beta" },
    maxTags     = 8,
    placeholder = "Add a tag",
    onChange    = function(_, list)
        Pallid.log("tags: " .. tostring(#list))
    end,
})

parent:add(tags)
```

### Notes
- Enter adds the field text, the chip cross removes that tag, and Backspace in an empty field removes the last tag.
- Tags are trimmed and duplicates are rejected; `validate` runs before a tag enters the list.
- `getTags()` returns the live internal table. Mutating it leaves the chips stale; use `setTags` instead.
- Chips that do not fit the widget height collapse into a `+N` counter.

## SearchField

Single-line search input with a leading magnifier, a clear button and optional debouncing.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Search and input settings; base input options are forwarded.
- opts.placeholder (string|nil) - Placeholder text.
- opts.text (string, default `""`) - Initial value.
- opts.debounce (number, default `0`) - Seconds of inactivity before `onSearch` fires; `0` fires on each change.
- opts.onSearch (function|nil) - Called as `(field, text)` when the debounced text changes.
- opts.onChange (function|nil) - Called as `(input, text, raw)` on every edit.
- opts.showClear (boolean, default `true`) - `false` hides the clear button.
- opts.font (UIFont|string, default `Pallid.UI.Fonts.default`) - Field font.
- opts.paddingY (number, default `2`) - Vertical text padding.
- opts.paddingX (number) - Ignored; the left padding is fixed at `22` for the magnifier.

### Returns
- PallidSearchField - Search field; class `PallidSearchField` (base `PallidInputText`), registered as `Pallid.UI.Widgets.SearchField`.

### Methods
- `clear()` -> self - Sets the text to empty and refocuses the native field.
- `preferredSize(maxW, maxH)` -> number, number - Preferred size.
- All other methods are inherited from `inputText`, including `getText`, `setText` and `isComplete`.

### Example
```lua
local E = Pallid.UI.Widgets

local search = E.searchField(8, 8, 300, 26, {
    placeholder = "Search items",
    debounce    = 0.25,
    onSearch    = function(_, text)
        Pallid.log("search: " .. text)
    end,
})

parent:add(search)
```

### Notes
- `onSearch` fires only when the text differs from the last emitted value, so an identical result is not reported twice.
- The debounce timer runs in the widget update, so it needs the widget to stay in a live tree.
- `clear()` goes through `setText("")`, which also fires the base `onChange`.

## FormField

Form row with a label above a control, a hint or error line below, and optional validation.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number|nil) - Height in pixels; `nil` or `0` derives it from the content.
- opts (table|nil) - Content and validation settings.
- opts.label (string|nil) - Text above the control; `" *"` is appended when `required` is set and the label is not empty.
- opts.control (PallidWidget|nil) - Widget placed in the middle row and added as a child.
- opts.hint (string|nil) - Helper text below the control.
- opts.validate (function|nil) - Called as `(value, field)`; return `true`, or `false` with an optional message string.
- opts.getValue (function|nil) - Called as `(field, control)` to read a custom value.
- opts.required (boolean, default `false`) - Adds the required marker and an empty-value check.
- opts.controlHeight (number, default `26`) - Fallback control height when the control has no height.
- opts.padding (number, default `0`) - Inner inset on every side.
- opts.gap (number, default `4`) - Gap between the label, control and footer lines.

### Returns
- PallidFormField - Form row; class `PallidFormField`, registered as `Pallid.UI.Widgets.FormField`.

### Methods
- `validate()` -> boolean - Runs the required check and `validate`; updates the error line and returns success.
- `getValue()` -> any - `opts.getValue`, else `control:getValue()`, else `control:getText()`, else `nil`.
- `setError(message)` -> self - Shows an error; `nil` clears it, `""` keeps the red frame without a message line.
- `clearError()` -> self - Clears the error state.
- `setHint(hint)` -> self - Replaces the helper text.
- `setBounds(x, y, w, h)` -> self - Re-runs the row layout; `h <= 0` returns to automatic height.

### Example
```lua
local E = Pallid.UI.Widgets

local nameRow = E.formField(8, 8, 360, nil, {
    label    = "Player name",
    required = true,
    hint     = "At least three characters",
    control  = E.inputText(0, 0, 0, 24, { placeholder = "name" }),
    validate = function(value)
        if value ~= nil and #value >= 3 then
            return true
        end
        return false, "Name is too short"
    end,
})

parent:add(nameRow)
```

### Notes
- The control is added as a child and its own `w` is always overridden by the row's inner width; its `h` sets the control height when greater than zero, otherwise `controlHeight` is used.
- A required empty value produces the localized "This field is required" message before `validate` runs.
- `setError("")` keeps the error frame but falls back to the hint line, which is how a form can mark a field red without text.
- `validate` reports success only for a literal `true`; any other return is treated as a failure.

## Pallid.UI.Mask

Input pattern compiler and formatter used by `inputText` and the other text fields.

**Side:** client

### Methods
- `Pallid.UI.Mask.compile(pattern)` -> PallidMask|nil - Compiles a pattern string; returns `nil` for an empty pattern or one with no input slots. Results are cached per pattern string.
- `Pallid.UI.Mask.format(mask, text, caret)` -> string, string, integer - Formats `text` through a compiled mask or pattern string. Returns the formatted text, the raw slot characters and the caret offset in the formatted text; with no mask it returns `text, text, caret or #text`.
- `Pallid.UI.Mask.raw(mask, text)` -> string - Extracts the slot characters from formatted text, dropping literals and invalid characters.
- `Pallid.UI.Mask.isComplete(mask, text)` -> boolean - True when every slot is filled; with no mask it is true for any non-empty text.

Tokens: `#` and `9` accept a digit, `a` a letter, `A` an upper-case letter, `x` a letter or digit, `X` an upper-case letter or digit. Every other character is a literal, and `\` escapes the next character.

A compiled mask exposes `pattern` (source string), `slots` (`PallidMaskSlot[]` with `token`, `rule` and `before`), `slotCount` and `tail` (literals after the last slot).

### Example
```lua
local mask = Pallid.UI.Mask.compile("##-##-###")

local text, raw = Pallid.UI.Mask.format(mask, "1234567")
-- text = "12-34-567"
-- raw  = "1234567"

local complete = Pallid.UI.Mask.isComplete(mask, text) -- true
local digits   = Pallid.UI.Mask.raw(mask, "12-34-567") -- "1234567"
```

### Notes
- Patterns are fixed-length and ASCII oriented; non-ASCII characters never satisfy a slot.
- Literals are inserted only before a filled slot, so `"12"` stays `"12"` instead of growing a trailing separator. The trailing `tail` is added only when every slot is filled.
- `compile` caches its result, and a pattern with no slots is cached as a miss, so `compile` returns `nil` again without re-parsing.
- `format` and `raw` also accept a pattern string directly, but compiling once and reusing the result avoids repeated parsing.
