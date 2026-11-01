# Pallid UI basic widgets

Small single-purpose widgets built by factories in `Pallid.UI.Widgets`. Each
factory returns a widget that you add to a parent tree; `add`, `remove`,
`setBounds`, `setVisible`, `setEnabled` and `setTooltip` are inherited and
documented in [ui-widget.md](ui-widget.md).

All examples assume `parent` is a widget you already own and that the widget
files have been loaded.

## Label

Static single- or multi-line text block. Wrapping and ellipsis use the widget
width, so layout only has to set the bounds.

**Side:** client

### Parameters
- text (string) - Initial text; nil becomes `""`.
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- w (number) - Width in pixels; wrapping and ellipsis use it.
- h (number) - Height in pixels; only used to anchor the text vertically.
- opts (table|nil) - Appearance overrides.
- opts.style (PallidTextStyle|nil) - Full text style copied into the label before the fields below override it.
- opts.font (UIFont|string|nil) - Font; defaults to `Pallid.UI.Fonts.small`.
- opts.alignH ("left"|"center"|"right"|nil) - Horizontal anchor; defaults to `"left"`.
- opts.alignV ("top"|"middle"|"bottom"|nil) - Vertical anchor; defaults to `"middle"`.
- opts.wrap (boolean|nil) - Enables word wrapping at the widget width; nil keeps the style value.
- opts.ellipsis (boolean|string|nil) - Ellipsis suffix; `false` disables it.
- opts.maxLines (integer|nil) - Maximum wrapped line count.
- opts.color (PallidColor|nil) - Text colour; overrides the style colour.

### Returns
- PallidLabel - the created label.

### Methods
- `setText(text) -> self` - Replaces the text; nil becomes an empty string.
- `getText() -> string` - Returns the current text.
- `setColor(color) -> self` - Replaces the text colour in place.
- `preferredSize(maxW, maxH) -> number, number` - Returns the natural width and height; `maxW` is used as the wrap width.

### Example
```lua
local label = Pallid.UI.Widgets.label("Health: 82%", 8, 8, 160, 20, {
    wrap = true,
})
parent:add(label)
label:setText("Health: 61%")
```

### Notes
- A label with `w <= 0` draws nothing.
- `opts.style` is copied field by field, so nested tables such as `shadow` are shared with the caller's table.
- `preferredSize(maxW)` measures with `maxW` as the wrap width and returns `width, height`.

## Button

Button with optional icon, toggle mode and click sound. Hover, press and the
toggle fill are eased every frame.

**Side:** client

### Parameters
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Content and behaviour.
- opts.text (string|nil) - Label; empty draws only the icon.
- opts.icon (string|nil) - Registered icon name, or a texture path containing `/`.
- opts.iconSide ("left"|"right"|nil) - Icon side; defaults to `"left"`.
- opts.toggle (boolean|nil) - When true a click flips `active`.
- opts.active (boolean|nil) - Initial toggle state; defaults to `false`.
- opts.onClick (fun(button: PallidButton)|nil) - Called after the toggle state is updated.
- opts.sound (string|false|nil) - UI sound name; nil keeps `"UIActivateButton"`, `false` or `""` silences it.
- opts.radius (number|table|nil) - Corner radius, a number or `{tl, tr, br, bl}`; defaults to 4.
- opts.background (boolean|nil) - Draws the fill and border; defaults to true.
- opts.flat (boolean|nil) - Plain rectangle instead of rounded chrome.
- opts.border (boolean|nil) - `false` skips the chrome border.
- opts.iconColor (PallidColor|nil) - Icon tint; nil draws it white.
- opts.iconInset (number|nil) - Pixels trimmed from every side of the icon box; defaults to 10.

### Returns
- PallidButton - the created button.

### Methods
- `setText(text) -> self` - Replaces the label; an empty string leaves only the icon.
- `setIcon(icon) -> self` - Replaces the icon; nil or an empty string removes it.
- `hasIcon() -> boolean` - True when the icon resolves to a drawable texture or registered icon.
- `setActive(active) -> self` - Sets the toggle state; the fill eases to it.
- `getActive() -> boolean` - Returns the current toggle state.
- `preferredSize(maxW, maxH) -> number, number` - Returns the width needed for the label and icon at the current height.

### Example
```lua
local button = Pallid.UI.Widgets.button(8, 40, 120, 28, {
    text    = "Apply",
    onClick = function(clicked) Pallid.log(clicked.text) end,
})
parent:add(button)
```

### Notes
- `opts.icon` containing `/` is loaded as a texture path; any other string is looked up with `Pallid.UI.Textures.getIcon`.
- Right-click is ignored, and a release outside the button cancels the click.
- `onClick` runs after `toggle` has flipped `active`, so the callback sees the new state.
- With `background = false` only the icon and label are drawn; the icon tint still reacts to hover and press.

## SplitButton

Button with an attached arrow segment that opens a menu. The left part behaves
like a normal button, the right part opens the menu below itself.

**Side:** client

### Parameters
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Content and menu settings.
- opts.text (string|nil) - Main button label.
- opts.icon (string|nil) - Main button icon, same rules as `button`.
- opts.items ((string|table)[]|nil) - Menu items; strings are labels, tables are menu item descriptors.
- opts.menuOptions (table|nil) - Extra options forwarded to the menu constructor.
- opts.onClick (fun(split: PallidSplitButton, button: PallidButton)|nil) - Main button callback.
- opts.onArrowClick (fun(split: PallidSplitButton, menu: PallidMenu)|nil) - Called after the menu opens.
- opts.arrowWidth (number|nil) - Arrow segment width; defaults to 24 and is clamped to at least 12.
- opts.radius (number|nil) - Corner radius; defaults to 4.
- opts.sound (string|false|nil) - Main button sound.

### Returns
- PallidSplitButton - the created split button.

### Methods
- `setItems(items) -> self` - Replaces the menu items.
- `setText(text) -> self` - Replaces the main button label.
- `showMenu() -> PallidMenu|nil` - Opens the attached menu below the arrow; nil when the widget is detached.

### Example
```lua
local split = Pallid.UI.Widgets.splitButton(8, 8, 180, 28, {
    text  = "Save",
    items = {
        { text = "Save as", onClick = function() end },
        "Discard",
    },
    onClick = function(_, button) end,
})
parent:add(split)
split:setItems({ "Overwrite" })
```

### Notes
- The child button is resized to `w - arrowWidth`; the arrow segment is painted by the split button itself.
- `showMenu` returns nil when the widget is not attached to a root, so call it only after `add`.
- `setText` and `setItems` forward to the main button and the menu; `setEnabled(false)` also closes an open menu.

## Badge

Small pill or dot used as a counter or status marker. It is an ordinary child,
so it can be positioned over another widget.

**Side:** client

### Parameters
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- opts (table|nil) - Content and appearance.
- opts.text (string|nil) - Pill text.
- opts.dot (boolean|nil) - Draws a circle without text.
- opts.color (PallidColor|nil) - Fill; defaults to `Pallid.UI.Color.primaryStrong`.
- opts.textColor (PallidColor|nil) - Text colour; defaults to a contrast colour of the fill.
- opts.border (PallidColor|nil) - Optional pill outline; ignored by dots.
- opts.width (number|nil) - Fixed width; measured when omitted.
- opts.height (number|nil) - Fixed height; defaults to 18, or `size` for a dot.
- opts.size (number|nil) - Dot diameter; defaults to 8.
- opts.padding (number|nil) - Horizontal text padding; defaults to 6.
- opts.font (UIFont|string|nil) - Text font; defaults to `Pallid.UI.Fonts.small`.

### Returns
- PallidBadge - the created badge.

### Methods
- `setText(text) -> self` - Replaces the text and re-measures the width while it is automatic.
- `setColor(color) -> self` - Replaces the fill and recomputes the contrast text colour.

### Example
```lua
local badge = Pallid.UI.Widgets.badge(180, 8, {
    text  = "12",
    color = Pallid.UI.Color.danger,
})
parent:add(badge)
badge:setColor(Pallid.UI.Color.warning)
```

### Notes
- `setColor` always recomputes the contrast text colour, so a custom `textColor` is lost.
- A measured width follows later `setText` calls, but the height is never recomputed; pass `width` and `height` for a fixed pill.

## Hyperlink

Link-styled text with an animated underline and a click callback. Without a
callback the URL is opened through `Pallid.UI.openUrl`.

**Side:** client

### Parameters
- text (string) - Link label.
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- w (number|nil) - Width; nil or 0 measures the text.
- h (number|nil) - Height; nil or a non-positive value uses 18.
- opts (table|nil) - Link options.
- opts.url (string|nil) - Passed to `onClick` and opened when no callback is set.
- opts.onClick (fun(link: PallidHyperlink, url: string|nil)|nil) - Click handler.
- opts.color (PallidColor|nil) - Resting colour; defaults to `Pallid.UI.Color.primary`.
- opts.hoverColor (PallidColor|nil) - Hover text and underline colour; defaults to `Pallid.UI.Color.primaryStrong`.
- opts.font (UIFont|string|nil) - Font or a key from `Pallid.UI.Fonts`; defaults to `Fonts.small`.

### Returns
- PallidHyperlink - the created link.

### Methods
- `setText(text) -> self` - Replaces the label and re-measures the width while it is automatic.
- `getText() -> string` - Returns the current label.

### Example
```lua
local link = Pallid.UI.Widgets.hyperlink("Project Zomboid", 8, 8, nil, nil, {
    url = "https://projectzomboid.com",
})
parent:add(link)
```

### Notes
- The engine only opens Indie Stone domains; other URLs are copied to the clipboard and a toast reports it. `lastResult` and `lastHow` record the outcome.
- A zero width in `setBounds` returns to auto-measuring the text.

## Image

Texture or registered icon with fit, stretch, fill, flip, rotation and tiling.

**Side:** client

### Parameters
- source (Texture|string|nil) - Texture, texture path containing `/`, registered icon name, or nil.
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (PallidTextureOpts|nil) - Texture options; defaults to `{ mode = "fit" }`.
- opts.mode ("stretch"|"fit"|"fill"|nil) - How the texture fills the box.
- opts.flipX (boolean|nil) - Mirrors horizontally.
- opts.flipY (boolean|nil) - Mirrors vertically.
- opts.rotation (number|nil) - Clockwise rotation in degrees around the box centre.
- opts.tiled (boolean|nil) - Tiles at natural size and ignores mode, flip and rotation.

### Returns
- PallidImage - the created image.

### Methods
- `setTexture(path) -> self` - Loads a texture from a path containing `/`.
- `setIcon(name) -> self` - Shows a registered icon by name.
- `setOptions(opts) -> self` - Replaces the fit, flip, rotation and tiling options.

### Example
```lua
Pallid.UI.Textures.registerIcon("Pallid_demo", "media/assets/ui/pallid/icons/document.png")
local image = Pallid.UI.Widgets.image("Pallid_demo", 8, 8, 48, 48, { mode = "fit" })
parent:add(image)
image:setOptions({ mode = "fill" })
```

### Notes
- The default mode here is `"fit"`, not the `"stretch"` default of `Pallid.UI.texture`.
- `setTexture` takes a path string; to show a `Texture` object, pass it as `source` or assign the `texture` field.
- Flip, rotation and tiling need an individual texture. A registered icon without one is drawn centred and untransformed.

## ImageGallery

Scrollable grid of thumbnails with selection, hover, wheel scrolling and
keyboard navigation.

**Side:** client

### Parameters
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Items and appearance.
- opts.items (table[]|nil) - Initial items; each item is a source string or `{ source, caption, value }`.
- opts.cellW (number|nil) - Cell width; defaults to 96, minimum 32.
- opts.cellH (number|nil) - Cell height; defaults to 96, minimum 32.
- opts.gap (number|nil) - Gap between cells; defaults to 8.
- opts.padding (number|nil) - Inner inset; defaults to 4.
- opts.columns (number|nil) - Forced column count; otherwise derived from the width.
- opts.selectionMode ("single"|"multi"|"none"|nil) - Selection model; defaults to `"single"`.
- opts.showCaptions (boolean|nil) - Reserves one caption line per cell; defaults to true.
- opts.background (PallidColor|nil) - Gallery fill; defaults to `Pallid.UI.Color.surface`.
- opts.border (PallidColor|nil) - Gallery outline; defaults to `Pallid.UI.Color.border`.
- opts.radius (number|nil) - Gallery radius; defaults to 4.
- opts.emptyText (string|nil) - Text shown when there are no items.
- opts.onSelect (fun(gallery: PallidImageGallery, index: integer, item: table)|nil) - Selection callback.
- opts.onActivate (fun(gallery: PallidImageGallery, index: integer, item: table)|nil) - Double-click or Enter callback.
- opts.barSize (number|nil) - Scrollbar thickness; defaults to `Pallid.UI.Widgets.DEFAULT_SCROLLBAR_SIZE`.
- opts.barGap (number|nil) - Scrollbar gap; otherwise 3 for small galleries and 5 for larger ones.

### Returns
- PallidImageGallery - the created gallery.

### Methods
- `setItems(items) -> self` - Replaces the items and clears the selection and scroll offset.
- `getItems() -> table[]` - Returns the normalised items.
- `refresh() -> self` - Recomputes the grid, scroll range and scrollbar.
- `cellRect(index) -> number, number` - Returns the cell origin in root-local coordinates.
- `itemAt(px, py) -> integer` - Returns the 1-based item index under a point, or 0.
- `isSelected(index) -> boolean` - True when the item counts as selected.
- `setSelected(index, silent) -> self` - Selects an item; nil clears it and `silent` skips `onSelect`.
- `getSelected() -> integer|nil` - Returns the last selected index.
- `scrollToItem(index) -> self` - Scrolls so the item is visible.

### Example
```lua
local gallery = Pallid.UI.Widgets.imageGallery(8, 8, 300, 220, {
    items         = {
        { source = "Pallid_demo", caption = "Document" },
    },
    selectionMode = "single",
    onSelect      = function(_, index, item) end,
})
parent:add(gallery)
gallery:setSelected(1)
gallery:scrollToItem(1)
```

### Notes
- Items are normalised to `{ source, caption, value, region, texture, raw }`; `value` is stored but not used by the widget.
- `getSelected` returns the last selected index even in `"multi"` mode; `isSelected(index)` is the per-item check.
- Ctrl-click toggles items in `"multi"` mode, and two clicks on the same cell within 400 ms fire `onActivate`.
- `setItems` clears the selection and the scroll offset.
- `refresh` runs on every draw, so call it manually only after changing `cellW`, `cellH` or `columns`.

## Avatar

Square or circular avatar for players, NPCs and items, with initials fallback,
an optional status dot and corner badges.

**Side:** client

### Parameters
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- size (number) - Square side in pixels.
- opts (table|nil) - Avatar options.
- opts.source (Texture|string|nil) - Texture, texture path, registered icon name or a 17-digit Steam ID.
- opts.steamID (string|nil) - Steam ID used to resolve the avatar.
- opts.username (string|nil) - Steam username used as a fallback.
- opts.item (InventoryItem|Item|nil) - Inventory item whose icon is shown.
- opts.name (string|nil) - Display name used for initials and the fallback colour.
- opts.initials (string|nil) - Overrides the derived initials.
- opts.fallbackColor (PallidColor|nil) - Fixed fallback colour instead of the name hash.
- opts.shape ("square"|"circle"|nil) - Clip shape; defaults to `"square"`.
- opts.status (PallidColor|nil) - Status dot colour; nil hides the dot.
- opts.statusBorder (PallidColor|nil) - Ring around the dot; defaults to `Pallid.UI.Color.panel`.
- opts.badge (table|string|nil) - Primary badge text, a badge descriptor, or an array of specs.
- opts.badges (table|nil) - Array of specs passed to `addBadge`.
- opts.border (PallidColor|nil) - Frame colour; defaults to `Pallid.UI.Color.panelBorder`.
- opts.animated (boolean|nil) - Fades the picture in; defaults to true.
- opts.pulseStatus (boolean|nil) - Slow pulse of the status dot; defaults to false.
- opts.steamRetry (number|nil) - First Steam retry delay in seconds; defaults to 2, minimum 0.5.
- opts.steamMaxAttempts (number|nil) - Lookup attempt cap; defaults to 10, and 0 removes the cap.

### Returns
- PallidAvatar - the created avatar.

### Methods
- `playIntro() -> self` - Replays the picture fade.
- `setName(name) -> self` - Sets the display name and re-derives the initials.
- `setInitials(initials) -> self` - Overrides the initials; nil or an empty string restores the derived ones.
- `setFallbackColor(color) -> self` - Fixes the fallback colour; nil restores the name hash.
- `setShape(shape) -> self` - Sets the clip shape to `"square"` or `"circle"`.
- `setSource(source) -> self` - Assigns a texture, path, icon name or Steam ID as the source.
- `setTexture(texture) -> self` - Shows a `Texture` object.
- `setIcon(name) -> self` - Shows a registered icon by name.
- `setItem(item) -> self` - Shows an inventory item icon.
- `setSteamID(steamID) -> self` - Resolves the picture from a Steam ID.
- `setUsername(username) -> self` - Resolves the picture from a Steam username.
- `setStatus(color, borderColor) -> self` - Sets or clears the status dot colour and its ring.
- `setBorder(color) -> self` - Sets the frame colour.
- `setStatusBorder(color) -> self` - Sets the ring colour around the status dot.
- `setAnimated(animated) -> self` - Enables or disables the picture fade.
- `setPulse(enabled) -> self` - Enables or disables the status dot pulse.
- `addBadge(text, opts) -> PallidBadge` - Adds a badge and returns it.
- `setBadge(text, opts) -> self` - Adds or updates the primary badge; nil or an empty string removes it.
- `removeBadge(badgeOrIndex) -> self` - Removes a badge by instance or index.
- `clearBadges() -> self` - Removes every badge.
- `getBadges() -> PallidBadge[]` - Returns the badge widgets in creation order.
- `setSize(size) -> self` - Sets the square side in pixels.

### Example
```lua
local avatar = Pallid.UI.Widgets.avatar(8, 8, 40, {
    name   = "Jane Doe",
    status = Pallid.UI.Color.success,
    badge  = "3",
})
parent:add(avatar)
avatar:setShape("circle")
```

### Notes
- Source priority is `item`, then `source`, then `steamID`, then `username`.
- `shape` supports only `"square"` and `"circle"`; the engine exposes no rounded-rectangle stencil.
- `addBadge` returns the badge widget, while `setBadge`, `removeBadge` and `clearBadges` return the avatar.
- Badge sides accept `top-right` (default), `top-left`, `bottom-left`, `bottom-right` and the aliases `tr`, `tl`, `br`, `bl`; badges on one side stack inward.
- A `bottom-right` badge is drawn above the status dot; use another corner when both are needed.
- Steam lookups are retried with backoff until the client exposes the avatar.

## Keycap

Keycap-style label, optionally clickable, for shortcuts and help screens.

**Side:** client

### Parameters
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- opts (table|nil) - Content and appearance.
- opts.text (string|nil) - Key name.
- opts.width (number|nil) - Fixed width; measured when omitted.
- opts.height (number|nil) - Cap height; defaults to 24, minimum 2.
- opts.font (UIFont|string|nil) - Font; defaults to `Pallid.UI.Fonts.codeSmall`.
- opts.padding (number|nil) - Horizontal text padding; defaults to 7.
- opts.radius (number|nil) - Corner radius; defaults to 4.
- opts.onClick (fun(keycap: PallidKeycap)|nil) - Click callback; nil makes the cap decorative.

### Returns
- PallidKeycap - the created keycap.

### Methods
- `setText(text) -> self` - Replaces the key name and re-measures the width while it is automatic.

### Example
```lua
local cap = Pallid.UI.Widgets.keycap(8, 8, { text = "Ctrl" })
parent:add(cap)
cap:setText("Shift")
```

### Notes
- A measured width is at least 24 px and follows later `setText` calls.
- A keycap without `onClick` never captures input.

## ProgressBar

Linear, radial, outline or textured progress bar whose displayed value eases
toward the target value.

**Side:** client

### Parameters
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Appearance and behaviour.
- opts.mode ("linear"|"radial"|"outline"|"texture"|nil) - Fill mode; defaults to `"linear"`.
- opts.value (number|nil) - Initial target, clamped to 0..1; defaults to 0.
- opts.direction ("left"|"right"|"up"|"down"|nil) - Fill direction for linear and texture modes; defaults to `"right"`.
- opts.startAngle (number|nil) - Radial start angle in degrees; defaults to -90.
- opts.clockwise (boolean|nil) - Radial direction; defaults to true.
- opts.radius (number|table|nil) - Corner radius for linear and outline modes; defaults to 0.
- opts.thickness (number|nil) - Outline thickness in pixels; defaults to 4, minimum 1.
- opts.fg (PallidColor|nil) - Fill colour; defaults to `Pallid.UI.Color.primary`.
- opts.bg (PallidColor|nil) - Track colour; defaults to `Pallid.UI.Color.surfaceElevated`.
- opts.trackAlpha (number|nil) - Explicit track alpha; otherwise the background alpha, or 0.9.
- opts.plateAlpha (number|nil) - Background plate alpha for outline mode; defaults to 0.35.
- opts.texture (string|nil) - Background texture path for texture mode.
- opts.textureFg (string|nil) - Foreground texture path; defaults to `texture`.
- opts.textureMode ("stretch"|"fit"|"fill"|nil) - Texture scaling; defaults to `"stretch"`.
- opts.showValue (boolean|nil) - Draws the formatted value; defaults to false.
- opts.format (string|function|nil) - String format for the integer percent, or `fun(display, value)`; defaults to `"%d%%"`.
- opts.animate (boolean|nil) - Eases value changes; defaults to true.
- opts.animateSpeed (number|nil) - Easing speed; defaults to 12.
- opts.textColor (PallidColor|nil) - Value text colour; defaults to `Pallid.UI.Color.textPrimary`.
- opts.textShadow (table|false|nil) - Shadow style; nil uses a soft default, `false` disables it.

### Returns
- PallidProgressBar - the created progress bar.

### Methods
- `setValue(value) -> self` - Sets the target value, clamped to 0..1.
- `setAnimate(animate) -> self` - Enables or disables easing; disabling snaps to the target.
- `setMode(mode) -> self` - Switches between `"linear"`, `"radial"`, `"outline"` and `"texture"`.
- `setRadius(radius) -> self` - Sets the corner radius for linear and outline modes.
- `setThickness(thickness) -> self` - Sets the outline stroke thickness in pixels.
- `setTextureMode(mode) -> self` - Sets how texture mode scales its textures.
- `setColors(fg, bg, trackAlpha) -> self` - Sets the fill, track and optional track alpha.
- `setShowValue(show) -> self` - Shows or hides the centred value text.
- `setFormat(format) -> self` - Sets a string format or a `fun(display, value)` formatter.
- `setDirection(direction) -> self` - Sets the fill direction for linear and texture modes.
- `setTexture(texture, textureFg) -> self` - Replaces the background and foreground texture paths.
- `valueText() -> string` - Returns the formatted value text.

### Example
```lua
local bar = Pallid.UI.Widgets.progressBar(8, 8, 200, 12, {
    value     = 0.4,
    radius    = 6,
    showValue = true,
})
parent:add(bar)
bar:setValue(0.75)
```

### Notes
- The bar is display-only: it is created with `hittable = false`.
- `setValue` ignores non-numbers and NaN and logs the rejection; the target is clamped to 0..1.
- With `animate = false` the displayed value snaps to the target immediately.
- A string `format` receives the rounded integer percent; a function receives `(display, value)`.
- Texture mode reveals a rectangular band and has no rounded-corner mask.
- Unknown mode, direction or texture mode values are logged and replaced with the defaults.

## Spinner

Indeterminate loading spinner. The rotation phase advances every frame.

**Side:** client

### Parameters
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- size (number) - Outer diameter in pixels; minimum 4.
- opts (table|nil) - Appearance and motion.
- opts.thickness (number|nil) - Ring thickness; defaults to 12% of the size, minimum 2.
- opts.color (PallidColor|nil) - Arc colour; defaults to `Pallid.UI.Color.primary`.
- opts.track (PallidColor|nil) - Full-circle track colour; nil draws no track.
- opts.speed (number|nil) - Turns per second; defaults to 1.1.
- opts.arc (number|nil) - Visible arc fraction, clamped to 0.05..1; defaults to 0.3.

### Returns
- PallidSpinner - the created spinner.

### Methods
- No methods beyond the base widget API in [ui-widget.md](ui-widget.md).

### Example
```lua
local spinner = Pallid.UI.Widgets.spinner(8, 8, 24, { track = Pallid.UI.Color.border })
parent:add(spinner)
```

### Notes
- There is no fractional progress value; use `progressBar` for determinate work.
- The spinner always animates while it is visible; it has no public setter.

## Skeleton

Placeholder for loading content: rounded bars with an optional pulse and moving
highlight.

**Side:** client

### Parameters
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- opts (table|nil) - Appearance.
- opts.lines (integer|nil) - Number of bars; defaults to 3, minimum 1.
- opts.lineHeight (number|nil) - Bar height; nil splits the height evenly across the bars.
- opts.gap (number|nil) - Vertical gap between bars; defaults to 6.
- opts.radius (number|nil) - Bar radius; defaults to 4.
- opts.color (PallidColor|nil) - Bar colour; defaults to `Pallid.UI.Color.surfaceMuted`.
- opts.animated (boolean|nil) - `false` keeps the bars static.

### Returns
- PallidSkeleton - the created skeleton placeholder.

### Methods
- No methods beyond the base widget API in [ui-widget.md](ui-widget.md).

### Example
```lua
local skeleton = Pallid.UI.Widgets.skeleton(8, 8, 200, 40, { lines = 2 })
parent:add(skeleton)
```

### Notes
- The widget needs an explicit width and height; with `h <= 0` nothing is drawn.
- With more than one bar, the last bar is drawn at 62% width so the block reads as a paragraph.
- Bars that start below the height are skipped, and the bar crossing the bottom edge is clamped to the remaining height.

## EmptyState

Centred placeholder for empty lists and search results, with an optional action
button.

**Side:** client

### Parameters
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- w (number) - Width in pixels.
- h (number) - Height; zero or negative measures the height from the content.
- opts (table|nil) - Content and appearance.
- opts.title (string|nil) - Heading; defaults to `"Nothing here"`.
- opts.description (string|nil) - Explanation under the heading; defaults to `""`.
- opts.icon (Texture|string|false|nil) - Icon name, texture path, texture, `false` to hide the icon, or nil for the packaged document icon.
- opts.iconSize (number|nil) - Icon block size; defaults to 48.
- opts.iconColor (PallidColor|nil) - Icon tint; defaults to the muted text colour.
- opts.showIcon (boolean|nil) - `false` hides the icon block; defaults to true.
- opts.titleFont (UIFont|string|nil) - Title font; defaults to `Pallid.UI.Fonts.medium`.
- opts.titleColor (PallidColor|nil) - Title colour; defaults to `Pallid.UI.Color.textPrimary`.
- opts.descriptionFont (UIFont|string|nil) - Description font; defaults to `Pallid.UI.Fonts.small`.
- opts.descriptionColor (PallidColor|nil) - Description colour; defaults to `Pallid.UI.Color.textMuted`.
- opts.maxLines (integer|nil) - Description line limit; defaults to 3.
- opts.padding (number|nil) - Outer padding; defaults to 24.
- opts.spacing (number|nil) - Gap between blocks; defaults to 8.
- opts.animated (boolean|nil) - Entrance fade and rise; defaults to true.
- opts.floatIcon (boolean|nil) - Looping icon alpha pulse; defaults to true.
- opts.action (table|nil) - `{ text, onClick, icon, width, height, sound, radius }` for the action button.

### Returns
- PallidEmptyState - the created empty state.

### Methods
- `playIntro() -> self` - Replays the entrance animation and the icon pulse.
- `setTitle(title) -> self` - Sets the heading text.
- `setDescription(description) -> self` - Sets the explanation text.
- `setIcon(icon) -> self` - Replaces the icon; nil restores the default glyph and `false` hides it.
- `setShowIcon(visible) -> self` - Shows or hides the icon block without changing its source.
- `setAction(action) -> self` - Replaces or removes (`nil`) the action button.

### Example
```lua
local empty = Pallid.UI.Widgets.emptyState(0, 0, 300, 0, {
    title       = "No saves",
    description = "Create a save to see it here.",
    action      = { text = "Create", onClick = function() end },
})
parent:add(empty)
```

### Notes
- The widget has no background and is inert (`hittable = false`); only the action button receives input.
- With `h <= 0` the height follows the content and keeps following later text changes.
- The entrance animation starts on the first animation frame the widget is visible, not at construction.

## Alert

Horizontal, non-blocking message with a severity icon, wrapped text and an
optional close button.

**Side:** client

### Parameters
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- w (number) - Width in pixels.
- h (number) - Height; zero measures it from the text, minimum 44.
- opts (table|nil) - Appearance and severity overrides.
- opts.severity ("info"|"success"|"warning"|"danger"|"neutral"|"warn"|"error"|nil) - Severity; defaults to `"info"`, and `warn`/`error` alias `warning`/`danger`.
- opts.title (string|nil) - Bold first line; empty hides it.
- opts.message (string|nil) - Wrapped body text; empty hides it.
- opts.closable (boolean|nil) - Shows the close button and enables dismissal; defaults to true.
- opts.onClose (fun(alert: PallidAlert)|nil) - Called once the banner is dismissed.
- opts.color (PallidColor|nil) - Overrides the severity accent.
- opts.background (PallidColor|nil) - Panel fill; defaults to `Pallid.UI.Color.surfaceElevated`.
- opts.border (PallidColor|nil) - Panel border; defaults to `Pallid.UI.Color.border`.
- opts.textColor (PallidColor|nil) - Message colour; defaults to `Pallid.UI.Color.textMuted`.
- opts.titleColor (PallidColor|nil) - Title colour; defaults to `Pallid.UI.Color.textPrimary`.
- opts.icon (string|false|nil) - Registered icon, texture path, `false` to hide it, or nil for the severity icon.
- opts.iconSize (number|nil) - Status icon size; defaults to 20.
- opts.iconGap (number|nil) - Space between icon and text; defaults to 12.
- opts.iconColor (PallidColor|nil) - Icon tint; defaults to the severity accent.
- opts.font (UIFont|string|nil) - Title and message font; defaults to `Pallid.UI.Fonts.small`.
- opts.maxLines (integer|nil) - Message line cap; defaults to 3.
- opts.radius (number|nil) - Corner radius; defaults to 8.
- opts.animated (boolean|nil) - Slide and fade in and out; defaults to true.
- opts.padding (number|nil) - Inner padding; defaults to 14.
- opts.closeSize (number|nil) - Close button box size; defaults to 20.

### Returns
- PallidAlert - the created banner.

### Methods
- `setTitle(title) -> self` - Sets the bold first line; empty hides it.
- `setMessage(message) -> self` - Sets the wrapped body text; empty hides it.
- `setSeverity(severity) -> self` - Sets the severity and recomputes the accent palette.
- `setClosable(closable) -> self` - Shows or hides the close button and enables or disables dismissal.
- `setIcon(icon) -> self` - Sets a custom icon, hides it (`false`), or restores the severity icon (`nil`).
- `show() -> self` - Reopens a closed banner and replays the entrance.
- `close(immediate) -> self` - Dismisses the banner; `immediate` skips the exit animation.

### Example
```lua
local alert = Pallid.UI.Widgets.alert(8, 8, 320, 0, {
    severity = "warning",
    title    = "Low fuel",
    message  = "The generator will stop soon.",
})
parent:add(alert)
alert:close()
```

### Notes
- The banner paints in the overlay pass, so it draws above siblings added after it.
- Only the close button takes input; clicks on the body pass through to what is underneath.
- `onClose` fires once, after the exit animation, or immediately when `animated = false` or `close(true)` is used.
- `show()` reopens the banner and replays the entrance; `onClose` fires again only after another dismissal.
- An unknown `severity` silently falls back to `info` without a log entry.

## RichText

Display-only rich text with inline markup, inline icons and clickable links.
Use `inputRich` for editing.

**Side:** client

### Parameters
- text (string) - Initial markup text.
- x (number) - Offset X from the parent origin.
- y (number) - Offset Y from the parent origin.
- w (number) - Width in pixels; text wraps to it.
- h (number) - Height in pixels; overflowing content is clipped.
- opts (table|nil) - Rich text options.
- opts.font (UIFont|string|nil) - Font or a key from `Pallid.UI.Fonts`; nil uses the default font.
- opts.color (PallidColor|nil) - Base text colour; defaults to `Pallid.UI.Color.text`.
- opts.linkColor (PallidColor|nil) - Link colour; defaults to `Pallid.UI.Color.primary`.
- opts.linkHoverColor (PallidColor|nil) - Hovered link colour; defaults to `Pallid.UI.Color.primaryStrong`.
- opts.lineSpacing (number|nil) - Extra spacing between lines; defaults to 2.
- opts.iconSize (number|nil) - Inline icon size; defaults to 16.
- opts.onLink (fun(rich: PallidRichText, url: string)|nil) - Called when a link is activated.

### Returns
- PallidRichText - the created rich text widget.

### Methods
- `setText(text) -> self` - Replaces the markup text and invalidates the layout cache.
- `measuredSize() -> number, number` - Forces a layout and returns the content width and height.
- `linkAt(px, py) -> integer|nil` - Returns the link segment index at a point, or nil.

### Example
```lua
local rich = Pallid.UI.Widgets.richText(
    "Press **F1** for help, or read the [manual](https://pzwiki.net).",
    8, 8, 260, 60
)
parent:add(rich)
rich:setText("{c=#E8D4A2}Warning{/c}: low fuel.")
```

### Notes
- Supported markup: `**bold**`, `__underline__`, `~~strike~~`, `{c=#RRGGBB}...{/c}`, `{icon=name}` and `[label](url)`. The tag forms `{b}...{/b}`, `{u}...{/u}` and `{s}...{/s}` are also accepted.
- Italic is not supported: the game has no oblique bitmap face.
- The colour tag accepts 6 or 8 hex digits and an optional `#`. An invalid value keeps the current colour but still consumes its `{/c}`.
- `{icon=...}` takes a registered icon name or a path containing `/`.
- Links are always underlined; clicking one calls `onLink(rich, url)`, otherwise the URL is opened with `Pallid.UI.openUrl` (non-Indie Stone URLs are copied to the clipboard).
- Newlines start a new line, words wrap at the widget width, and overlong words are split at UTF-8 boundaries.
- `measuredSize()` forces a layout and returns the content width and height.
