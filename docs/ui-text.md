# Pallid.UI text

`Pallid.UI` provides text layout, measurement and drawing for `ISUIElement` hosts. A text style is a plain table that you create once and reuse; colors are `PallidColor` tables with 0..1 components (see [ui-color.md](ui-color.md)).

All drawing functions require an element with a Java peer (`el.javaObject`). Calls made before `addToUIManager` are harmless: they return `false` and draw nothing. Widgets that wrap these helpers are described in [ui-widget.md](ui-widget.md).

## Pallid.UI.Fonts

Table of named `UIFont` handles, so code does not depend on the enum names directly.

**Side:** client

### Fields
| Field | Font |
| --- | --- |
| `small` | `UIFont.Small` |
| `medium` | `UIFont.Medium` |
| `large` | `UIFont.Large` |
| `massive` | `UIFont.Massive` |
| `newSmall` | `UIFont.NewSmall` |
| `newMedium` | `UIFont.NewMedium` |
| `newLarge` | `UIFont.NewLarge` |
| `code` | `UIFont.Code` |
| `codeSmall` | `UIFont.CodeSmall` |
| `codeMedium` | `UIFont.CodeMedium` |
| `codeLarge` | `UIFont.CodeLarge` |
| `dialogue` | `UIFont.Dialogue` |
| `intro` | `UIFont.Intro` |
| `handwritten` | `UIFont.Handwritten` |
| `title` | `UIFont.Title` |
| `debug` | `UIFont.DebugConsole` |
| `default` | `UIFont.Small` |

### Example
```lua
local style = {
    font  = Pallid.UI.Fonts.codeSmall,
    color = Pallid.UI.Color.textPrimary,
}
```

### Notes
- `default` and `small` are the same `UIFont`.
- A string font is looked up in this table, and an unknown key falls back to `default`.

## Text style

Plain table read by the text functions. Only the fields below are used; any other key is ignored.

**Side:** client

### Fields
- font (UIFont or string or nil) - Game font or a `Pallid.UI.Fonts` key; nil or an unknown key means `Fonts.default`.
- color (PallidColor or nil) - Text color; nil means white.
- scale (number or nil) - Glyph scale; default 1, values <= 0 are treated as 1.
- alignH (string or nil) - Horizontal anchor: `"left"` (default), `"center"` or `"right"`; other values behave like `"left"`.
- alignV (string or nil) - Vertical anchor: `"top"` (default), `"middle"` or `"bottom"`; other values behave like `"top"`.
- bold (boolean or nil) - Draw a second copy one pixel to the right.
- underline (boolean or nil) - Draw a one-pixel rule under each line.
- strike (boolean or nil) - Draw a one-pixel rule through each line.
- shadow (table or nil) - `{ dx, dy, color }`; `dx`/`dy` default to 0 and `color` to black.
- outline (table or nil) - `{ thickness, color }`; `thickness` defaults to 1 and values <= 0 disable it, `color` defaults to black.
- maxWidth (number or nil) - Line width budget in pixels; nil or 0 means unlimited.
- wrap (boolean or nil) - Wrap to `maxWidth`; has no effect unless `maxWidth` is above 0.
- maxLines (integer or nil) - Maximum wrapped lines; only used together with `wrap`.
- ellipsis (boolean or string or nil) - Suffix for cut text: `false` disables it, a string replaces `"..."`.
- lineSpacing (number or nil) - Extra pixels between wrapped lines; default 0.

### Example
```lua
local STYLE = {
    font        = Pallid.UI.Fonts.small,
    color       = Pallid.UI.Color.textPrimary,
    alignH      = "center",
    alignV      = "middle",
    maxWidth    = 180,
    wrap        = true,
    maxLines    = 3,
    lineSpacing = 1,
}
```

### Notes
- Layout fields (`font`, `scale`, `maxWidth`, `wrap`, `maxLines`, `ellipsis`, `lineSpacing`) define the prepared layout. The other fields are read at draw time and may change every frame without re-preparing.
- Missing color channels default to 1, so `{ r = 1, g = 0, b = 0 }` is opaque red.
- `maxWidth` is in scaled pixels when truncating, because the value is divided by `scale` before measuring, but it is passed unscaled to the game wrapper when wrapping. With `wrap` and `scale > 1` the wrapped block can therefore be wider than `maxWidth`.
- The ellipsis suffix is appended to the last wrapped line only when wrapping actually exceeds `maxLines`; the cut is made by character count, not on a UTF-8 boundary.
- `shadow`, `outline` and `bold` add extra draw calls per line.

## Pallid.UI.prepareText

Builds or refreshes a layout: wrapped lines or a truncated single line, per-line heights and the block height.

**Side:** client

### Parameters
- str (string) - Text to prepare; a non-string is treated as `""`.
- style (table or nil) - Text style; only the layout fields are read.
- cache (table or nil) - Layout returned by an earlier call, reused in place. Pass the same table on every frame.

### Returns
- PallidPreparedText - The layout table, owned by the caller.

### Example
```lua
local STYLE = {
    font     = Pallid.UI.Fonts.small,
    wrap     = true,
    maxWidth = 180,
}

local Panel = ISPanel:derive("PallidPreparedTextDemo")

function Panel:render()
    self.prepared = Pallid.UI.prepareText(self.message, STYLE, self.prepared)
    Pallid.UI.textPrepared(self, self.prepared, 8, 8, STYLE)
end

local panel = Panel:new(100, 100, 200, 120)
panel.message = "Wrapped text drawn from a reusable layout."
panel:addToUIManager()
```

### Notes
- The layout is rebuilt only when the text, the resolved font, `scale`, `maxWidth`, `wrap`, `maxLines`, `ellipsis` or `lineSpacing` differ from the cache. Changing `color`, `alignH`, `alignV`, `bold`, `underline`, `strike`, `shadow` or `outline` does not invalidate it.
- Prepared text must be re-prepared when the text or a layout field changes; drawing a stale layout draws the old text and geometry.
- Do not share one cache between different strings unless the last prepared string is the one you want to draw.
- The cache table is mutated in place, so the first call may pass `nil` and later calls can reuse the returned table.
- `lines` is nil for a single-line layout; the truncated text is then in `single`. Per-line widths, `width` and `widthsValid` are filled lazily by `measurePrepared` or by drawing.

## Pallid.UI.measurePrepared

Measures a prepared layout without rebuilding it.

**Side:** client

### Parameters
- prepared (table) - Layout returned by `Pallid.UI.prepareText`.

### Returns
- number - Width of the widest line in pixels; 0 for an invalid layout.
- number - Total block height in pixels, including `lineSpacing`; 0 for an invalid layout.

### Example
```lua
-- STYLE comes from the text style example above.
local prepared = Pallid.UI.prepareText("Hello", STYLE)
local width, height = Pallid.UI.measurePrepared(prepared)
```

### Notes
- The widest line is measured on the first call and cached in the layout, so repeated calls are cheap.
- The width is the measured text width, not the `maxWidth` budget, and it does not include shadow, outline or underline.
- A non-table argument returns `0, 0` instead of raising.

## Pallid.UI.wrapText

Wraps text to a width and returns the resulting lines.

**Side:** client

### Parameters
- str (string) - Text to wrap.
- font (UIFont or string or nil) - Font or a `Pallid.UI.Fonts` key; nil means the default font.
- maxWidth (number) - Maximum line width in pixels.
- maxLines (integer or nil) - Maximum number of lines; nil means no limit.

### Returns
- string[] - One entry per line; an empty table for a non-string input.

### Example
```lua
local lines = Pallid.UI.wrapText("one two three", Pallid.UI.Fonts.small, 80)
```

### Notes
- `maxWidth` nil or <= 0 returns `{ str }` unchanged.
- The suffix passed to the game wrapper is always empty, so this function never adds an ellipsis.
- Wrapping uses unscaled font metrics; `scale` is not applied and `maxWidth` is in font pixels.
- A word longer than the line is split with hyphens by the game wrapper.
- Existing newlines start a new line, so the result can contain more lines than the wrapping alone would produce.

## Pallid.UI.truncateText

Shortens text to a width and appends `"..."` when it does not fit.

**Side:** client

### Parameters
- str (string) - Text to truncate.
- font (UIFont or string or nil) - Font or a `Pallid.UI.Fonts` key; nil means the default font.
- maxWidth (number) - Maximum width in pixels.

### Returns
- string - Text that fits, or `""` when nothing fits.

### Example
```lua
local label = Pallid.UI.truncateText("A very long label", Pallid.UI.Fonts.small, 90)
```

### Notes
- Returns `""` when `maxWidth` is <= 0 or when `"..."` alone does not fit.
- The cut is made on a UTF-8 boundary, so a multi-byte glyph is never split.
- Measurement is unscaled; `scale` is not applied.
- The suffix is always `"..."`; use `prepareText` with `style.ellipsis` for a custom suffix.

## Pallid.UI.measureText

Measures a text block with the same wrap and truncate rules as `Pallid.UI.text`.

**Side:** client

### Parameters
- str (string) - Text to measure.
- style (table or nil) - Text style; only `font`, `scale`, `maxWidth`, `wrap`, `maxLines`, `ellipsis` and `lineSpacing` are used.

### Returns
- number - Measured width in pixels.
- number - Measured height in pixels.

### Example
```lua
local width, height = Pallid.UI.measureText("Hello", STYLE)
```

### Notes
- Uses the module's single shared layout cache, so measuring two different strings alternately rebuilds the layout on every call. Use `prepareText` with your own cache in hot paths.
- A non-string returns `0, 0`.

## Pallid.UI.textPrepared

Draws a prepared layout at an anchor.

**Side:** client

### Parameters
- el (ISUIElement) - Host element; must have a Java peer.
- prepared (table) - Layout returned by `Pallid.UI.prepareText`.
- x (number) - Anchor X: left edge, center or right edge depending on `alignH`.
- y (number) - Anchor Y: top, middle or bottom depending on `alignV`.
- style (table or nil) - Style supplying color, alignment and decoration flags.

### Returns
- boolean - `false` when the element has no Java peer or `prepared` is not a table.

### Example
```lua
-- STYLE and prepared come from the prepareText example above.
function Panel:render()
    Pallid.UI.textPrepared(self, self.prepared, 8, 8, STYLE)
end
```

### Notes
- Font, scale, wrapping and line heights come from `prepared`; `style` supplies `color`, `alignH`, `alignV`, `bold`, `underline`, `strike`, `shadow` and `outline`. Alignment is not stored in the layout, so it is read only from the style passed here.
- `alignV` offsets the whole block using the prepared block height, so `"middle"` and `"bottom"` need the height that `prepareText` already computed.
- Lines fully outside the active clip are skipped, and a left-aligned line that overflows the clip is truncated to it when more than 8 px remain. A partly visible line is drawn whole when the clip is backed by the engine stencil.
- Returns `true` even when every line was skipped by the clip.
- Underline and strike rules use `style.color` and are drawn one pixel high.

## Pallid.UI.text

Prepares and draws a text block in one call.

**Side:** client

### Parameters
- el (ISUIElement) - Host element; must have a Java peer.
- str (string) - Text to draw.
- x (number) - Anchor X: left edge, center or right edge depending on `alignH`.
- y (number) - Anchor Y: top, middle or bottom depending on `alignV`.
- style (table or nil) - Text style; create it once and reuse it.

### Returns
- boolean - `false` when the element has no Java peer or `str` is not a string.

### Example
```lua
Pallid.UI.text(el, "Hello", 8, 8, STYLE)
```

### Notes
- Uses the shared single-entry layout cache, so alternating strings rebuild the layout on every call. For per-frame or alternating text, call `prepareText` with your own cache and draw with `textPrepared`.
- All alignment, clipping and decoration behavior is the same as `textPrepared`.
