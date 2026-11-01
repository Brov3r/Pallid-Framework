# Colors

`Pallid.UI.Color` builds and blends RGBA colors and holds the shared palette that
every Pallid widget reads. A color is a plain table, so it can be created, copied
and stored freely; the palette entries are shared and must be treated as read-only.

## PallidColor

The color shape used by every draw call: four numeric channels in the 0..1 range.

**Side:** client

### Parameters
- r (number) - Red, 0..1.
- g (number) - Green, 0..1.
- b (number) - Blue, 0..1.
- a (number) - Alpha, 0..1. Missing alpha is treated as 1 by the draw helpers.

### Example
```lua
local tint = { r = 1, g = 0.5, b = 0.5, a = 1 }
```

### Notes
- Channel fields may be omitted in a hand-written table; the draw API fills missing
  channels with 1, including alpha.
- Draw functions accept `nil` for "white".

## Color.new

Creates a color from 0..1 components, clamping every channel.

**Side:** client

### Parameters
- r (number|nil) - Red, 0..1. Nil becomes 0.
- g (number|nil) - Green, 0..1. Nil becomes 0.
- b (number|nil) - Blue, 0..1. Nil becomes 0.
- a (number|nil) - Alpha, 0..1. Nil becomes 1.

### Returns
- PallidColor - New table with clamped `r`, `g`, `b`, `a`.

### Example
```lua
require "pallid/ui/api/color"

local Color = Pallid.UI.Color
local red = Color.new(1, 0, 0)          -- alpha 1
local faded = Color.new(1, 0, 0, 0.25)
```

## Color.fromBytes

Creates a color from 0..255 components.

**Side:** client

### Parameters
- r (number|nil) - Red, 0..255. Nil becomes 0.
- g (number|nil) - Green, 0..255. Nil becomes 0.
- b (number|nil) - Blue, 0..255. Nil becomes 0.
- a (number|nil) - Alpha, 0..255. Nil becomes 255.

### Returns
- PallidColor - New table with each channel divided by 255 and clamped to 0..1.

### Example
```lua
require "pallid/ui/api/color"

local skin = Pallid.UI.Color.fromBytes(155, 209, 193)
```

### Notes
- Out-of-range input is clamped, so 300 becomes 1.0 rather than wrapping.

## Color.fromHex

Parses a `#RRGGBB` or `#RRGGBBAA` string.

**Side:** client

### Parameters
- hex (string) - Six or eight hexadecimal digits. The leading `#` is optional.

### Returns
- PallidColor or nil - Parsed color, or nil when the input is malformed.

### Example
```lua
require "pallid/ui/api/color"

local Color = Pallid.UI.Color
local solid = Color.fromHex("#9BD1C1")
local clear = Color.fromHex("00000000")
```

### Notes
- Three-digit shorthand (`#ABC`) and whitespace are not accepted; both return nil.
- A non-string argument returns nil instead of raising an error.

## Color.hsvInto

Converts HSV into an existing color table, so per-frame effects do not allocate.

**Side:** client

### Parameters
- out (PallidColor) - Destination table. `r`, `g`, `b` and `a` are overwritten.
- h (number|nil) - Hue in degrees. Nil becomes 0.
- s (number|nil) - Saturation, 0..1. Nil becomes 0.
- v (number|nil) - Value, 0..1. Nil becomes 0.
- a (number|nil) - Alpha, 0..1. Nil becomes 1.

### Returns
- PallidColor - The same `out` table.

### Example
```lua
require "pallid/ui/api/color"

local scratch = { r = 1, g = 1, b = 1, a = 1 }
Pallid.UI.Color.hsvInto(scratch, 170, 0.4, 0.9, 1)
```

### Notes
- Hue wraps at 360 in both directions, including negative values such as -30.
- The caller owns `out`; nothing is allocated per call.

## Color.fromHSV

Converts HSV to a new RGB color.

**Side:** client

### Parameters
- h (number|nil) - Hue in degrees. Nil becomes 0.
- s (number|nil) - Saturation, 0..1. Nil becomes 0.
- v (number|nil) - Value, 0..1. Nil becomes 0.
- a (number|nil) - Alpha, 0..1. Nil becomes 1.

### Returns
- PallidColor - New table holding the converted color.

### Example
```lua
require "pallid/ui/api/color"

local hue = Pallid.UI.Color.fromHSV(170, 0.4, 0.9)
```

### Notes
- This allocates a table. Use `Color.hsvInto` inside draw or update code.

## Color.withAlpha

Returns a copy of a color with a different alpha.

**Side:** client

### Parameters
- color (PallidColor|nil) - Source color. Nil is treated as white.
- a (number|nil) - New alpha, 0..1. Nil becomes 1.

### Returns
- PallidColor - New table with the source channels and the new alpha.

### Example
```lua
require "pallid/ui/api/color"

local Color = Pallid.UI.Color
local ghost = Color.withAlpha(Color.primary, 0.2)
```

### Notes
- This is the supported way to derive a transparent variant of a palette entry.
- Missing source channels default to 1, so a partial table still produces a valid color.

## Color.mixInto

Blends two colors and writes the result into an existing table.

**Side:** client

### Parameters
- out (PallidColor) - Destination table. All four channels are overwritten.
- from (PallidColor) - Color at `t = 0`. Must not be nil.
- to (PallidColor) - Color at `t = 1`. Must not be nil.
- t (number|nil) - Interpolation factor, clamped to 0..1. Nil becomes 0.

### Returns
- PallidColor - The same `out` table.

### Example
```lua
require "pallid/ui/api/color"

local Color = Pallid.UI.Color
local scratch = Color.new(0, 0, 0, 1)
Color.mixInto(scratch, Color.surface, Color.surfaceElevated, 0.5)
```

### Notes
- Unlike `Color.lerp`, `from` and `to` are not defaulted; passing nil raises an error.
- Alpha is interpolated as well, so the result fades between the two colors.
- Blending is linear in the stored channels, with no gamma conversion.

## Color.lerp

Linearly interpolates two colors into a new table.

**Side:** client

### Parameters
- c1 (PallidColor|nil) - Color at `t = 0`. Nil is treated as white.
- c2 (PallidColor|nil) - Color at `t = 1`. Nil is treated as white.
- t (number|nil) - Interpolation factor, clamped to 0..1. Nil becomes 0.

### Returns
- PallidColor - New interpolated color.

### Example
```lua
require "pallid/ui/api/color"

local Color = Pallid.UI.Color
local mid = Color.lerp(Color.surface, Color.primary, 0.35)
```

### Notes
- This allocates a table; prefer `Color.mixInto` in hot paths.

## Color.contrastText

Picks black or white text for a background.

**Side:** client

### Parameters
- bgColor (PallidColor|nil) - Background color. Nil is treated as white.

### Returns
- PallidColor - `Color.black` or `Color.white`.

### Example
```lua
require "pallid/ui/api/color"

local Color = Pallid.UI.Color
local label = Color.contrastText(Color.primary)
```

### Notes
- The returned table is one of the shared palette entries, not a copy. Do not mutate it.
- Uses linear coefficients `0.2126/0.7152/0.0722` and a 0.5 threshold; alpha is ignored.
- The result is a fixed black/white choice, not a derived tint.

## Palette

Named palette entries, allocated once at load time and shared by all widgets.

**Side:** client

### Example
```lua
require "pallid/ui/api/color"

local Color = Pallid.UI.Color
local panelFill = Color.withAlpha(Color.surface, 0.9)
```

### Notes
- Every entry is a shared table. Mutating one changes it for every widget and for
  every alias that points at it. Derive variants with `Color.withAlpha`,
  `Color.mixInto` or `Color.lerp` instead of assigning into a palette entry.
- `Color.transparent` is `#00000000`, i.e. black at zero alpha. Lerping toward it
  darkens the color; use `Color.withAlpha(c, 0)` to fade a color out without tinting.
- Semantic aliases share the exact table of their source, so they are not separate
  colors.

### Neutrals

Light to dark ramp, plus the fully transparent entry.

- `white` (`#FFFFFF`) - Pure white.
- `snow` (`#FCFCFC`)
- `ivory` (`#FAF7F0`)
- `offWhite` (`#F5F5F0`)
- `pearl` (`#EDEDEB`)
- `cloud` (`#E6E6E6`)
- `mist` (`#DBDBDE`)
- `silver` (`#D1D1D6`)
- `lightGray` (`#BFBFBF`)
- `gray` (`#808080`)
- `slate` (`#5C6673`)
- `gunmetal` (`#4A4F54`)
- `darkGray` (`#404040`)
- `graphite` (`#363638`)
- `charcoal` (`#29292B`)
- `obsidian` (`#1A1A1C`)
- `ink` (`#0D0D0F`)
- `black` (`#000000`) - Pure black.
- `transparent` (`#00000000`) - Black at zero alpha.

### Reds

- `lightRed` (`#FF9999`)
- `salmon` (`#FA8073`)
- `coral` (`#FF804F`)
- `tomato` (`#FF6347`)
- `red` (`#FF0000`)
- `crimson` (`#DB143D`)
- `darkRed` (`#8C0D0D`)
- `maroon` (`#66000D`)

### Oranges and browns

- `peach` (`#FFCC9E`)
- `orange` (`#FF8C00`)
- `amber` (`#FFBF1A`)
- `darkOrange` (`#CC6600`)
- `brown` (`#8C5933`)
- `darkBrown` (`#4C2E1A`)

### Yellows

- `lightYellow` (`#FFFFB2`)
- `yellow` (`#FFFF00`)
- `gold` (`#FFD600`)
- `olive` (`#808000`)
- `darkGold` (`#B28C00`)

### Greens

- `mint` (`#99FFCC`)
- `lightGreen` (`#8CE68C`)
- `lime` (`#80FF00`)
- `green` (`#00FF00`)
- `emerald` (`#4FC778`)
- `forest` (`#218C21`)
- `darkGreen` (`#006600`)
- `teal` (`#008080`)

### Cyans and blues

- `cyan` (`#00FFFF`)
- `aqua` (`#80FFFF`)
- `sky` (`#87CFEB`)
- `lightBlue` (`#99CCFF`)
- `steel` (`#4582B5`)
- `azure` (`#0080FF`)
- `blue` (`#0000FF`)
- `royalBlue` (`#4069E0`)
- `darkBlue` (`#00008C`)
- `navy` (`#0D1A4C`)
- `indigo` (`#4A0082`)

### Purples and pinks

- `lavender` (`#CCBFF2`)
- `violet` (`#994CE6`)
- `purple` (`#800080`)
- `darkPurple` (`#4C0059`)
- `plum` (`#8C4073`)
- `pink` (`#FFBFCC`)
- `hotPink` (`#FF69B5`)
- `magenta` (`#FF00FF`)

### Theme tokens

Default dark theme tokens. Widget chrome reads these fields, so retheming does not
require editing each widget.

- `background` (`#1A1A1A`) - Base background.
- `surface` (`#222222`) - Standard surface.
- `surfaceElevated` (`#2A2A2A`) - Raised surface.
- `surfaceMuted` (`#1E1E1E`) - Recessed surface.
- `border` (`#3A3A3A`) - Default border.
- `borderStrong` (`#4D4D4D`) - Emphasised border.
- `primarySoft` (`#26332F`) - Muted primary.
- `primary` (`#9BD1C1`) - Primary accent.
- `primaryStrong` (`#BCE3D5`) - Strong primary.
- `secondarySoft` (`#2D2B33`) - Muted secondary.
- `secondary` (`#B9B4D6`) - Secondary accent.
- `accentSoft` (`#2E2E2E`) - Neutral hover background.
- `accent` (`#E7C3B4`) - Warm accent.
- `textPrimary` (`#ECECEC`) - Body text.
- `textMuted` (`#B9B9B9`) - Secondary text.
- `textDisabled` (`#7C7C7C`) - Disabled text.
- `success` (`#AEDCB6`) - Success status.
- `warning` (`#E8D4A2`) - Warning status.
- `error` (`#E9B4B4`) - Error status.
- `info` (`#B3CCE8`) - Informational status.
- `focusRing` (`#BCE3D5`) - Focus outline.

### Semantic aliases

Aliases that point at the same cached table as their source color.

- `text` - Same table as `textPrimary`.
- `danger` - Same table as `error`.
- `panel` - Same table as `surface`.
- `panelBorder` - Same table as `border`.
- `overlay` (`#00000080`) - 50% black scrim.
- `overlayLight` (`#00000040`) - 25% black scrim.

### Rainbow

Twelve cached hues at 30 degree steps, indexed 1..12 starting at red.

### Example
```lua
require "pallid/ui/api/color"

local Color = Pallid.UI.Color
local index = ((characterIndex - 1) % #Color.rainbow) + 1
local tint = Color.rainbow[index]
```

### Notes
- Entries are shared tables; tint them with `Color.withAlpha` instead of mutating.
- The list is 1-based and has no index 13, so wrap the index before indexing.
