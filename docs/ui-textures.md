# Pallid.UI textures and icons

`Pallid.UI` draws textures through two separate lookup systems: texture paths
resolved with `getTexture`, and named icons registered at runtime or taken from
the built-in icon and emoji atlases. All drawing helpers are client-side and
return false when the element has no Java peer; `Pallid.UI.texture` and
`Pallid.UI.textureRegion` additionally cull boxes outside the active clip.

## Pallid.UI.Textures.metrics

Returns the cached intrinsic metrics of a texture: trimmed size, original size
and trim offsets. The values are read once per texture because the game getters
cross into Java.

**Side:** client

### Parameters
- texture (Texture|nil) - Source texture.

### Returns
- PallidTextureMetrics|nil - Table with `width`, `height`, `origWidth`, `origHeight`, `offsetX`, `offsetY`; nil when `texture` is nil.

### Example
```lua
local tex = Pallid.UI.Textures.get(Pallid.UI.Assets.panel)
local m = Pallid.UI.Textures.metrics(tex)
local aspect = m.origWidth / m.origHeight
```

### Notes
- The result is cached by texture object and must be treated as read-only.

## Pallid.UI.Textures.resolve

Splits an icon specification into either a loaded texture or a registered icon
name. The decision is made purely by the presence of a `/` in the string.

**Side:** client

### Parameters
- icon (string|false|nil) - Registered icon name, texture path, or `false`.

### Returns
- Texture or nil - Loaded texture when `icon` contains `/`.
- string or nil - The name unchanged when `icon` contains no `/`.

### Example
```lua
local texture, name = Pallid.UI.Textures.resolve(self.opts.icon)
if texture ~= nil then
    Pallid.UI.texture(self, texture, x, y, 32, 32, color)
elseif name ~= nil then
    Pallid.UI.icon(self, name, x, y, 32, color)
end
```

### Notes
- The name is returned even when it was never registered; registration is not checked here.
- A non-string input returns `nil, nil`.

## Pallid.UI.Textures.get

Loads a texture by path and caches the result. Failed loads are cached as
failures, so a bad path warns once instead of once per frame.

**Side:** client

### Parameters
- path (string|nil) - Texture path as accepted by the game `getTexture`, including the `media/` prefix.

### Returns
- Texture or nil - Loaded texture, or nil for an empty path or a failed load.

### Example
```lua
local panel = Pallid.UI.Textures.get("media/assets/ui/pallid/shapes/panel.png")
```

### Notes
- A failed path is cached permanently for the session; fixing the file on disk does not help until restart.
- The failure warning is emitted once per distinct path.

## Pallid.UI.Textures.getRegion

Resolves a built-in atlas path to an atlas region descriptor. Paths that are not
part of the generated atlas return nil.

**Side:** client

### Parameters
- path (string|nil) - Texture path or bare file name.

### Returns
- PallidTextureRegion|nil - Region with `texture`, `sx`, `sy`, `sw`, `sh`, `width`, `height`; nil when the art is not in the atlas.

### Example
```lua
local region = Pallid.UI.Textures.getRegion("media/assets/ui/pallid/icons/tick.png")
if region ~= nil then
    Pallid.UI.textureRegion(self, region, x, y, 16, 16, color)
end
```

### Notes
- The atlas is generated art: icon pages are `icons-01.png` to `icons-04.png` and the emoji page is `emoji-01.png`, all under `media/assets/ui/pallid/atlas/`. A region descriptor points at one page plus a source rectangle, so drawing an atlas icon costs one quad and no per-icon texture.
- A path containing `/emoji-32/` is looked up in the emoji atlas; `/icons/` in the icon atlas; anything else is tried as an icon file name first, then as an emoji file name.
- Misses are cached as well, so third-party paths pay the lookup only once.

## Pallid.UI.Textures.getIconRegion

Resolves a registered icon name, a texture path, or a raw icon atlas file name
to an atlas region.

**Side:** client

### Parameters
- name (string|nil) - Registered icon name, texture path, or atlas icon key.

### Returns
- PallidTextureRegion|nil - Atlas region, or nil when nothing matches.

### Example
```lua
local region = Pallid.UI.Textures.getIconRegion("arrow-down-04.png")
```

### Notes
- Bare names are used as atlas keys verbatim; `.png` is not appended, so `"tick"` does not match `"tick.png"`.
- The emoji atlas is not searched; use `getEmojiRegion` for emoji.

## Pallid.UI.Textures.getEmojiRegion

Resolves an emoji name or path to an emoji atlas region. Accepts `alien`,
`alien.png` and full paths.

**Side:** client

### Parameters
- name (string|nil) - Emoji name, file name, or texture path.

### Returns
- PallidTextureRegion|nil - Atlas region, or nil when the emoji is not catalogued.

### Example
```lua
local region = Pallid.UI.Textures.getEmojiRegion("alien")
```

### Notes
- A missing `.png` extension is appended automatically, and directory prefixes are stripped before lookup.

## Pallid.UI.Textures.registerIcon

Registers a name so `Pallid.UI.icon` and `Pallid.UI.Textures.getIcon` can resolve
it. Register once at load time, not per frame.

**Side:** client

### Parameters
- name (string) - Name used at draw time.
- path (string) - Texture path as accepted by `Textures.get`, including the `media/` prefix.

### Returns
- nil - No return value.

### Example
```lua
Pallid.UI.Textures.registerIcon("Pallid_Shop_coin", "media/ui/MyMod/coin.png")
```

### Notes
- Registering the same name again silently replaces the previous path.
- An empty or non-string name is ignored; a non-string path is stored as-is, so `getIcon` returns nil for it.

## Pallid.UI.Textures.hasIcon

Reports whether a name was registered with `Textures.registerIcon`. It does not
report atlas art.

**Side:** client

### Parameters
- name (string|nil) - Icon name.

### Returns
- boolean - True only when the name maps to a registered texture path.

### Example
```lua
if not Pallid.UI.Textures.hasIcon("Pallid_Shop_coin") then
    Pallid.UI.Textures.registerIcon("Pallid_Shop_coin", "media/ui/MyMod/coin.png")
end
```

## Pallid.UI.Textures.getIcon

Resolves a registered icon name to its loaded texture.

**Side:** client

### Parameters
- name (string|nil) - Name passed to `Textures.registerIcon`.

### Returns
- Texture or nil - Loaded texture, or nil when the name is unknown or the file is missing.

### Example
```lua
local coin = Pallid.UI.Textures.getIcon("Pallid_Shop_coin")
```

### Notes
- Atlas icons are not resolved here; use `getIconRegion` for those.

## Pallid.UI.texture

Draws a texture into a box with a selectable fill mode and optional flip,
rotation and tiling.

**Side:** client

### Parameters
- el (ISUIElement) - Target element with an instantiated Java peer.
- texture (Texture|nil) - Texture to draw.
- x (number) - Left coordinate.
- y (number) - Top coordinate.
- w (number) - Destination width in pixels.
- h (number) - Destination height in pixels.
- color (PallidColor|nil) - Tint; nil means white.
- opts (PallidTextureOpts|nil) - Drawing options; create the table once and reuse it.
  - `mode` (string) - `"stretch"` (default), `"fit"` or `"fill"`.
  - `flipX` (boolean) - Mirror horizontally; applies to stretch and fit only.
  - `flipY` (boolean) - Mirror vertically; applies to stretch and fit only.
  - `rotation` (number) - Clockwise degrees around the box center; applies to stretch and fit only.
  - `tiled` (boolean) - Tile at natural size and ignore mode, flip and rotation.

### Returns
- boolean - True when the draw call rendered something.

### Example
```lua
-- self.textureOpts = { mode = "fit" } created once in the constructor
Pallid.UI.texture(self, self.iconTexture, 8, 8, 32, 32, Pallid.UI.Color.white, self.textureOpts)
```

### Notes
- `stretch` and `fit` honour trim offsets, so the visible pixels keep the original padding instead of being scaled edge to edge.
- `fill` works in trimmed texture space and ignores `flipX`, `flipY` and `rotation`.
- An unknown `mode` logs one warning and falls back to `"stretch"`.
- Missing color channels default to 1, including alpha, so `{ r = 1, g = 0.5, b = 0.5 }` is opaque.
- Returns false for a nil texture, a zero or negative size, an element without a Java peer, or a box outside the active clip.
- Boxes are snapped to whole pixels; a positive size never collapses to zero.

## Pallid.UI.textureRegion

Draws one atlas region with the same fill modes as `Pallid.UI.texture`, without
per-region rotation, flipping or tiling.

**Side:** client

### Parameters
- el (ISUIElement) - Target element.
- region (PallidTextureRegion|nil) - Region from `getRegion`, `getIconRegion` or `getEmojiRegion`.
- x (number) - Left coordinate.
- y (number) - Top coordinate.
- w (number) - Destination width.
- h (number) - Destination height.
- color (PallidColor|nil) - Tint; nil means white.
- opts (PallidTextureOpts|nil) - Only `mode` is used.

### Returns
- boolean - True when the region was drawn.

### Example
```lua
local region = Pallid.UI.Textures.getIconRegion("tick.png")
Pallid.UI.textureRegion(self, region, x, y, 16, 16, Pallid.UI.Color.success, { mode = "fit" })
```

### Notes
- Returns false when `opts.tiled` is set, `opts.rotation` is non-zero, or `flipX`/`flipY` is set; callers are expected to fall back to `Pallid.UI.texture`.
- `opts.rotation = 0` is accepted; only a non-zero value is rejected.
- An unknown `mode` is not validated and silently behaves like `"stretch"`.
- `fill` crops the source region instead of scaling the whole sprite.

## Pallid.UI.subTexture

Draws an arbitrary source rectangle of a texture into a destination box. This is
the low-level primitive behind `textureRegion` and `nineSlice`.

**Side:** client

### Parameters
- el (ISUIElement) - Target element.
- texture (Texture|nil) - Source texture.
- sx (number) - Source X in trimmed texture pixels.
- sy (number) - Source Y in trimmed texture pixels.
- sw (number) - Source width in pixels.
- sh (number) - Source height in pixels.
- x (number) - Destination left.
- y (number) - Destination top.
- w (number) - Destination width.
- h (number) - Destination height.
- color (PallidColor|nil) - Tint; nil means white.

### Returns
- boolean - True when the draw call rendered something.

### Example
```lua
Pallid.UI.subTexture(self, tex, 0, 0, 16, 16, x, y, 32, 32, Pallid.UI.Color.white)
```

### Notes
- `sx`/`sy` are in trimmed texture space; the destination is compensated by the texture trim offset so `x`/`y` stay exact.
- No clip test is performed here; `Pallid.UI.texture` and `Pallid.UI.textureRegion` are the helpers that cull against the active clip.
- Returns false for nil textures or any non-positive source or destination size.

## Pallid.UI.nineSlice

Draws a nine-slice panel: corners keep their source pixel size, edges and center
stretch.

**Side:** client

### Parameters
- el (ISUIElement) - Target element.
- texture (Texture|nil) - Source texture.
- x (number) - Destination left.
- y (number) - Destination top.
- w (number) - Destination width.
- h (number) - Destination height.
- borders (table) - `{ left, right, top, bottom }` or `{ l, r, t, b }`; missing entries default to 0.
- color (PallidColor|nil) - Tint; nil means white.

### Returns
- boolean - True when something was drawn.

### Example
```lua
local panel = Pallid.UI.Textures.get(Pallid.UI.Assets.panel)
Pallid.UI.nineSlice(self, panel, x, y, w, h, { left = 8, right = 8, top = 8, bottom = 8 }, color)
```

### Notes
- When the borders do not fit the source or the destination, the whole texture is stretched with `Pallid.UI.texture` instead of slicing.
- Borders are measured against the trimmed texture size, not the original image size.

## Pallid.UI.icon

Draws a registered icon or atlas icon inside a square box, preserving aspect
ratio.

**Side:** client

### Parameters
- el (ISUIElement) - Target element.
- name (string) - Registered icon name, atlas icon key, or a path containing `/`.
- x (number) - Left coordinate.
- y (number) - Top coordinate.
- size (number) - Width and height of the icon box.
- color (PallidColor|nil) - Tint; nil means white.

### Returns
- boolean - True when the icon was drawn.

### Example
```lua
Pallid.UI.icon(self, "tick.png", x, y, 16, Pallid.UI.Color.success)
```

### Notes
- Uses `"fit"` mode, so a non-square icon is centered with padding inside the box.
- An unresolved name logs one warning and returns false.
- Icon names are not prefixed automatically; two mods may register the same name and the last registration wins.

## Pallid.UI.emoji

Draws an emoji from the emoji atlas, falling back to the individual source PNG
for uncatalogued names.

**Side:** client

### Parameters
- el (ISUIElement) - Target element.
- name (string) - Emoji name (`alien`), file name, or full texture path.
- x (number) - Left coordinate.
- y (number) - Top coordinate.
- size (number) - Width and height of the emoji box.
- color (PallidColor|nil) - Tint; nil means white.

### Returns
- boolean - True when the emoji was drawn.

### Example
```lua
Pallid.UI.emoji(self, "alien", x, y, 24, Pallid.UI.Color.white)
```

### Notes
- A bare name is resolved against `media/assets/ui/pallid/emoji-32/` with `.png` appended, so third-party emoji files placed there keep working.
- Emoji and icons use different atlases; an icon name will not resolve as an emoji.

## Pallid.UI.itemIcon

Draws an inventory item or script item icon using the correct game draw method.

**Side:** client

### Parameters
- el (ISUIElement) - Target element.
- item (InventoryItem|Item|nil) - Item instance or script item.
- x (number) - Left coordinate.
- y (number) - Top coordinate.
- w (number) - Icon width in pixels.
- h (number) - Icon height in pixels.
- alpha (number|nil) - Alpha in 0..1; defaults to 1.

### Returns
- boolean - True when the draw call rendered something.

### Example
```lua
Pallid.UI.itemIcon(self, self.item, x, y, 32, 32, 0.75)
```

### Notes
- There is no tint parameter; use `alpha` only.
- Detection relies on the global `instanceof`; when it is unavailable the item is treated as a script item.
- No clip test is performed, so the caller must cull off-screen rows.

## Pallid.UI.Assets

Path table for the shared Pallid UI shapes. Every shape is a white silhouette
with an alpha channel, so it is tinted by the color argument of the draw call.

**Side:** client

### Fields
- dir (string) - Directory prefix for all shape textures.
- circle (string) - Filled white anti-aliased circle (256x256).
- panel (string) - Filled white rounded rectangle (256x256), intended for `nineSlice`.
- triangle (string) - Regular 3-gon, first vertex pointing right.
- square (string) - Regular 4-gon at rotation 0, which is a diamond.
- pentagon (string) - Regular 5-gon.
- hexagon (string) - Regular 6-gon.
- octagon (string) - Regular 8-gon.
- polygons (table<integer, string>) - Side count to texture path; 3, 4, 5, 6 and 8 are present.

### Example
```lua
local circle = Pallid.UI.Textures.get(Pallid.UI.Assets.circle)
Pallid.UI.texture(self, circle, x, y, 12, 12, Pallid.UI.Color.success)
```

### Notes
- Paths already include the `media/` prefix and can be passed straight to `Pallid.UI.Textures.get`.
- `polygons` has no entry for 7 sides or for counts above 8; `Pallid.UI.regularPolygon` draws those as a vector fan instead.

See [ui-widget.md](ui-widget.md) for the widgets that wrap these draw helpers.
