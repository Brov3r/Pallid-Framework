# Pallid.UI.Anim

`Pallid.UI.Anim` is the animation layer of the framework: time helpers, an easing
table, a single `Track` class that tweens several channels with one easing, ready
made preset tracks, and draw helpers that read a track without allocating. All of
it is client-side and designed to be called from a widget's `render`.

## Pallid.UI.Anim.now

Returns the current time in seconds. Every call crosses into Java, so read it
once per frame and pass the value on.

**Side:** client

### Returns
- number - Current time in seconds, derived from the millisecond game clock.

### Example
```lua
local now = Pallid.UI.Anim.now()
self.anim:update(now)
```

### Notes
- Reading the clock once per frame and passing `now` into `track:update(now)` avoids one Java crossing per track.

## Pallid.UI.Anim.lerp

Linearly interpolates between two numbers.

**Side:** client

### Parameters
- a (number) - Value at `t = 0`.
- b (number) - Value at `t = 1`.
- t (number) - Interpolation factor, normally 0..1.

### Returns
- number - `a + (b - a) * t`; not clamped, so `t` outside 0..1 extrapolates.

### Example
```lua
local width = Pallid.UI.Anim.lerp(120, 240, progress)
```

## Pallid.UI.Anim.clamp

Clamps a value into an inclusive range.

**Side:** client

### Parameters
- value (number) - Value to clamp.
- lo (number) - Inclusive lower bound.
- hi (number) - Inclusive upper bound.

### Returns
- number - The clamped value.

### Example
```lua
local alpha = Pallid.UI.Anim.clamp(self.anim.alpha, 0, 1)
```

### Notes
- This is the same function as the internal UI clamp; when `lo > hi`, `lo` wins.

## Pallid.UI.Anim.lerpColor

Writes the interpolation of two colors into a caller-owned table, so a tween
never allocates a color during a frame.

**Side:** client

### Parameters
- out (PallidColor) - Destination table; overwritten in place.
- a (PallidColor) - Color at `t = 0`.
- b (PallidColor) - Color at `t = 1`.
- t (number) - Interpolation factor, normally 0..1.

### Returns
- nil - The result is written into `out`; nothing is returned.

### Example
```lua
self.tint = { r = 1, g = 1, b = 1, a = 1 }
Pallid.UI.Anim.lerpColor(self.tint, Pallid.UI.Color.accent, Pallid.UI.Color.white, t)
```

### Notes
- Every channel is clamped to 0..1 after interpolation.
- All four channels must exist on both colors; a missing channel raises an arithmetic error instead of defaulting.

## Pallid.UI.Anim.alpha

Returns a color with its alpha multiplied by a factor.

**Side:** client

### Parameters
- color (PallidColor|nil) - Base color; nil means white.
- a (number|nil) - Alpha multiplier, normally 0..1; nil means 1.

### Returns
- PallidColor - Shared scratch table holding the tinted color.

### Example
```lua
Pallid.UI.rect(self, x, y, w, h, Pallid.UI.Anim.alpha(Pallid.UI.Color.accent, 0.5))
```

### Notes
- The returned table is reused on the next call; pass it straight to a draw call and never store it.
- Missing color channels default to 1, and the final alpha is clamped to 0..1.

## Pallid.UI.Anim.scaleRect

Scales a box around its center and returns the new box.

**Side:** client

### Parameters
- x (number) - Left coordinate.
- y (number) - Top coordinate.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- scale (number) - Scale multiplier.

### Returns
- number - New X coordinate.
- number - New Y coordinate.
- number - New width.
- number - New height.

### Example
```lua
local x, y, w, h = Pallid.UI.Anim.scaleRect(100, 100, 40, 20, 1.25)
```

## Pallid.UI.Anim.shakeOffset

Returns a stateless, time-based shake offset in pixels. Any track or timer can
drive it.

**Side:** client

### Parameters
- time (number) - Seconds.
- amplitude (number) - Maximum offset in pixels.
- frequency (number|nil) - Oscillations per second; defaults to 18.

### Returns
- number - Horizontal offset.
- number - Vertical offset.

### Example
```lua
local dx, dy = Pallid.UI.Anim.shakeOffset(Pallid.UI.Anim.now(), 3)
Pallid.UI.rect(self, x + dx, y + dy, w, h, color)
```

### Notes
- Horizontal and vertical use different phases, so the motion is a Lissajous curve rather than a straight line.
- This is not the `Anim.shake` preset; that preset is a finite track.

## Pallid.UI.Anim.stagger

Returns the start delay for one item of a staggered list.

**Side:** client

### Parameters
- index (integer) - 1-based item index.
- step (number) - Seconds between items.

### Returns
- number - Delay in seconds; the first item gets 0.

### Example
```lua
local track = Pallid.UI.Anim.fade(0.25, Pallid.UI.Anim.stagger(i, 0.05))
track:play()
```

### Notes
- Only the delay is computed; the track still has to be created and started by the caller.

## Pallid.UI.Anim.ease

Table of easing functions. Each entry takes normalized time and returns an eased
value; `back` and `elastic` curves intentionally overshoot outside 0..1.

**Side:** client

### Parameters
- t (number) - Normalized time, 0..1, for every function in the table.

### Returns
- number - Eased value; may overshoot for `inBack`, `outBack`, `inOutBack`, `inElastic`, `outElastic`.

### Example
```lua
local track = Pallid.UI.Anim.new({ duration = 0.4, easing = Pallid.UI.Anim.ease.outBack, scale = { 0.8, 1 } })
```

### Functions
- linear (function) - Returns `t` unchanged.
- inQuad (function) - Quadratic ease-in.
- outQuad (function) - Quadratic ease-out; the default for `Anim.new`.
- inOutQuad (function) - Quadratic ease-in-out.
- inCubic (function) - Cubic ease-in.
- outCubic (function) - Cubic ease-out.
- inOutCubic (function) - Cubic ease-in-out.
- inQuart (function) - Quartic ease-in.
- outQuart (function) - Quartic ease-out.
- inOutQuart (function) - Quartic ease-in-out.
- inSine (function) - Sine ease-in.
- outSine (function) - Sine ease-out.
- inOutSine (function) - Sine ease-in-out.
- inExpo (function) - Exponential ease-in.
- outExpo (function) - Exponential ease-out.
- inOutExpo (function) - Exponential ease-in-out.
- inCirc (function) - Circular ease-in.
- outCirc (function) - Circular ease-out.
- inOutCirc (function) - Circular ease-in-out.
- inBack (function) - Pulls back before moving forward.
- outBack (function) - Overshoots the target before settling.
- inOutBack (function) - Back pull at the start, overshoot at the end.
- inElastic (function) - Damped oscillation at the start.
- outElastic (function) - Damped oscillation at the end.
- outBounce (function) - Bounces several times before settling.
- inBounce (function) - Mirrored bounce at the start.
- smoothstep (function) - Hermite smoothstep with zero slope at both ends.

### Notes
- There is no `inOutElastic` and no `inOutBounce` entry.
- The table is a plain function map; nothing prevents adding custom easings, and `Anim.new` accepts any `fun(t): number`.

## Pallid.UI.Anim.new

Creates a track. Nothing is allocated after construction, and the channel pairs
are read immediately, so the options table can be discarded.

**Side:** client

### Parameters
- opts (PallidAnimOpts|nil) - Track options.
  - `duration` (number|nil) - Seconds per pass; defaults to 0.25, and 0 or a negative value is treated as 0.25.
  - `delay` (number|nil) - Seconds before the first pass; defaults to 0.
  - `speed` (number|nil) - Multiplier on elapsed time; defaults to 1.
  - `easing` (function|nil) - `fun(t): number`; defaults to `Anim.ease.outQuad`.
  - `loop` (boolean|integer|nil) - `true` loops forever, a number runs that many passes.
  - `pingPong` (boolean|nil) - Reverse direction on every other pass.
  - `reverse` (boolean|nil) - Play from 1 to 0 instead of 0 to 1.
  - `alpha` (number[]|nil) - `{from, to}` pair in 0..1.
  - `scale` (number[]|nil) - `{from, to}` pair.
  - `dx` (number[]|nil) - `{from, to}` pair in pixels.
  - `dy` (number[]|nil) - `{from, to}` pair in pixels.
  - `rotation` (number[]|nil) - `{from, to}` pair in degrees.
  - `value` (number[]|nil) - `{from, to}` pair exposed as `track.number`.
  - `color` (table|nil) - `{ from = PallidColor, to = PallidColor }`, exposed as `track.color`.
  - `onComplete` (function|nil) - `fun(track)` called once when the last pass is reached.

### Returns
- PallidAnimTrack - New track, not started; call `:play()`.

### Example
```lua
require "pallid/ui/animation/track"

self.anim = Pallid.UI.Anim.new({
    duration = 0.25,
    easing   = Pallid.UI.Anim.ease.outCubic,
    alpha    = { 0, 1 },
    scale    = { 0.9, 1 },
})
self.anim:play()
```

### Notes
- Unused channels keep their resting value (`alpha` 1, `scale` 1, `dx`/`dy` 0, `rotation` 0) and are not touched by `update`.
- A channel pair is read with defaults per entry, so `{ 0 }` means from 0 to the default end (1 for `alpha` and `scale`, 0 for the rest).
- `color` is ignored unless both `from` and `to` are present; the track then owns a private output table starting at `from`.
- `color.from` and `color.to` are kept by reference, not copied, so mutating those tables later changes the running tween.
- Require the defining file first; only the util/ease layer is required by the framework itself.

## Pallid.UI.Anim.Track

The track class returned by `Anim.new` and every preset. One easing drives all
configured channels, and each `update` writes plain numbers onto the instance.

**Side:** client

### Fields
- value (number) - Eased progress, normally 0..1 but overshooting for back/elastic easings.
- alpha (number) - Current alpha.
- scale (number) - Current scale.
- dx (number) - Current X offset in pixels.
- dy (number) - Current Y offset in pixels.
- rotation (number) - Current rotation in degrees.
- number (number) - Numeric channel; only valid when `opts.value` was supplied.
- color (PallidColor) - Track-owned color; only present when `opts.color` was supplied.
- duration (number) - Seconds per pass.
- delay (number) - Seconds before the first pass.
- speed (number) - Multiplier on elapsed time.
- easing (function) - Easing applied to every pass.
- loop (boolean|integer) - True for endless playback, a number for that many passes.
- pingPong (boolean) - Reverse direction on every other pass.
- reverse (boolean) - Play from 1 to 0 instead of 0 to 1.
- startAt (number|nil) - Absolute start time; nil while stopped.
- finished (boolean) - True once the last pass has been reached.
- done (boolean) - True after `onComplete` has fired at least once.
- onComplete (function|nil) - Completion callback.

### Example
```lua
local track = Pallid.UI.Anim.new({ duration = 0.2, alpha = { 1, 0 } })
track:play()
track:update(Pallid.UI.Anim.now())
local a = track.alpha
```

### Notes
- Fields are public and can be changed before `play()`, for example `track.loop = true`.
- `rotation` is in degrees; the channel is only meaningful for draw helpers that apply rotation (`Anim.regularPolygon`, `Anim.texture`).

## Pallid.UI.Anim.Track:play

Starts or restarts the track.

**Side:** client

### Parameters
- now (number|nil) - Time in seconds from `Anim.now()`; nil reads the clock.

### Returns
- PallidAnimTrack - The same instance, for chaining.

### Example
```lua
self.anim:play(Pallid.UI.Anim.now())
```

### Notes
- `startAt` becomes `now + delay`, and `done`/`finished` are cleared, so `onComplete` can fire again after a restart.
- A reversed track starts with its channels applied at 1, so the first frame already shows the end state.

## Pallid.UI.Anim.Track:update

Recomputes every channel for a point in time.

**Side:** client

### Parameters
- now (number|nil) - Current time in seconds; nil reads the clock.

### Returns
- PallidAnimTrack - The same instance, for chaining.

### Example
```lua
function MyWidget:render()
    local now = Pallid.UI.Anim.now()
    self.anim:update(now)
    Pallid.UI.Anim.rect(self, self.anim, 10, 10, 120, 32, Pallid.UI.Color.accent)
end
```

### Notes
- Does nothing while the track is stopped (`startAt` is nil); call `play()` first.
- Time before `startAt` is clamped to progress 0, so the track holds its start state (progress 1 for a reversed track) until `delay` expires.
- `speed` multiplies elapsed time but not `delay`.
- With `pingPong`, one `duration` is one half-pass: an unlooped ping-pong track runs two of them, and `loop = n` runs `n` of them.
- `onComplete` fires on the update where the pass limit is reached, and only once per `play()`.
- `reverse` inverts the phase before easing, so the easing curve is traversed backwards rather than mirrored.

## Pallid.UI.Anim.Track:stop

Freezes the track at its current channel values.

**Side:** client

### Returns
- nil - No return value.

### Example
```lua
self.anim:stop()
```

### Notes
- `update` becomes a no-op afterwards and `isPlaying` returns false; the last values stay on the track for drawing.

## Pallid.UI.Anim.Track:isPlaying

Reports whether the track is started and not finished.

**Side:** client

### Returns
- boolean - True while the track is running.

### Example
```lua
if not self.anim:isPlaying() then
    self.anim:play()
end
```

### Notes
- A looping track stays playing forever; a finished non-looping track returns false even though `startAt` is still set.

## Preset tracks

Ready-made tracks for common UI motions. Each preset is a normal track, so its
channels, loop and `onComplete` can still be changed before the first `play()`.
Names ending in `In` start at the pre-animation state, names ending in `Out`
start at the resting state and end hidden.

**Side:** client

### Presets
- `fade(duration, delay, easing)` - Alpha 0 to 1; default 0.25 s, `outCubic`.
- `fadeOut(duration, delay)` - Alpha 1 to 0; default 0.25 s, `inCubic`.
- `pop(duration, delay)` - Alpha 0 to 1 and scale 0.85 to 1; default 0.28 s, `outBack`.
- `popOut(duration, delay)` - Alpha 1 to 0 and scale 1 to 1.08; default 0.2 s, `inCubic`.
- `zoomIn(duration, delay, fromScale)` - Alpha 0 to 1 and scale `fromScale` (default 0.6) to 1; default 0.24 s, `outCubic`.
- `dropIn(duration, delay, distance)` - Alpha, scale 0.9 to 1 and `dy` from `-distance` (default 16) to 0; default 0.35 s, `outBack`.
- `bounceIn(duration, delay)` - Alpha 0 to 1 and scale 0.3 to 1; default 0.5 s, `outBounce`.
- `wobbleIn(duration, delay, degrees)` - Alpha 0 to 1 and rotation from `-degrees` (default 8) to 0; default 0.4 s, `outBack`.
- `slide(duration, dx, dy, delay)` - Alpha 0 to 1 and offset from `(dx, dy)` to 0; default 0.3 s, `outCubic`.
- `slideOut(duration, dx, dy, delay)` - Alpha 1 to 0 and offset from 0 to `(dx, dy)`; default 0.22 s, `inCubic`.
- `pulse(duration, minAlpha)` - Looping ping-pong alpha 1 to `minAlpha` (default 0.4); default 0.9 s per direction, `inOutSine`.
- `breathe(duration, maxScale)` - Looping ping-pong scale 1 to `maxScale` (default 1.05); default 1.2 s per direction, `inOutSine`.
- `blink(duration, minAlpha)` - Looping ping-pong alpha 1 to `minAlpha` (default 0); default 0.5 s per direction, `inQuad`.
- `spin(duration)` - Looping rotation 0 to 360 degrees; default 4 s per turn, `linear`.
- `wobble(duration, degrees)` - Looping ping-pong rotation from `-degrees` to `degrees` (default 4); default 0.35 s per direction, `inOutSine`.
- `float(duration, distance)` - Looping ping-pong `dy` from 0 to `-distance` (default 4); default 1.4 s per direction, `inOutSine`.
- `colorPulse(duration, from, to)` - Looping ping-pong color from `Color.accent` to `Color.white`; default 1.1 s per direction, `inOutSine`.
- `shake(amplitude, swings, swingTime)` - Horizontal `dx` 0 to `amplitude` (default 4) for `swings * 2` half-passes (default 4 swings) of `swingTime` (default 0.06 s), `linear`.

### Example
```lua
require "pallid/ui/animation/presets"

self.anim = Pallid.UI.Anim.pop(0.3)
self.anim:play()
```

### Notes
- Every preset returns an unstarted track; nothing animates until `play()` is called.
- The looping presets use `loop = true` and never finish, so `onComplete` is never called for them.
- `shake` is finite and ends back at offset 0 after roughly `swings * 2 * swingTime` seconds.
- `slide` and `slideOut` take `delay` as the fourth argument, not the second.
- `colorPulse` needs `Pallid.UI.Color`; the presets file requires it for you.

## Pallid.UI.Anim.waveText

Draws a string with every character bouncing in a sine wave.

**Side:** client

### Parameters
- el (ISUIElement) - Target element.
- str (string) - Text to draw.
- x (number) - Left edge of the first character.
- y (number) - Top edge used as the wave origin.
- style (PallidTextStyle) - Text style; create it once and reuse it.
- time (number) - Seconds, usually `Anim.now()`.
- amplitude (number|nil) - Vertical amplitude in pixels; defaults to 4.
- frequency (number|nil) - Waves per second; defaults to 1.2.
- phaseStep (number|nil) - Phase shift between characters in radians; defaults to 0.6.

### Returns
- boolean - True when the draw call rendered something.

### Example
```lua
Pallid.UI.Anim.waveText(self, "SALE", x, y, self.titleStyle, Pallid.UI.Anim.now(), 4, 1.2, 0.6)
```

### Notes
- Each character is a separate draw call, so cost grows with string length.
- `style.alignH` is forced to `"left"` for the call and restored afterwards; `alignV` still applies per character.
- `wrap`, `maxWidth` and `maxLines` do not apply, and `underline`, `strike`, `shadow` and `outline` are drawn per character, which produces gaps.
- Character slices are cached per string, up to 64 distinct strings, then the cache is cleared.

## Pallid.UI.Anim.rainbowText

Draws a string where each character takes the next color from
`Pallid.UI.Color.rainbow`, and the whole wheel shifts over time.

**Side:** client

### Parameters
- el (ISUIElement) - Target element.
- str (string) - Text to draw.
- x (number) - Left edge of the first character.
- y (number) - Top edge.
- style (PallidTextStyle) - Text style; create it once and reuse it.
- time (number) - Seconds, usually `Anim.now()`.
- speed (number|nil) - Palette steps per second; defaults to 4.

### Returns
- boolean - True when the draw call rendered something.

### Example
```lua
Pallid.UI.Anim.rainbowText(self, "RAINBOW", x, y, self.titleStyle, Pallid.UI.Anim.now(), 6)
```

### Notes
- `style.color` only contributes its alpha; the hue comes from the palette.
- `style.color` and `style.alignH` are restored after the call, including when a glyph draw raises.
- The same per-character limits as `Anim.waveText` apply: no wrapping or truncation, and decorations are drawn per glyph.

## Pallid.UI.Anim.rect

Draws a rectangle that follows a track's alpha, scale and offset.

**Side:** client

### Parameters
- el (ISUIElement) - Target element.
- track (PallidAnimTrack) - Track already advanced for this frame.
- x (number) - Left coordinate.
- y (number) - Top coordinate.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- color (PallidColor|nil) - Fill color; nil means white.

### Returns
- boolean - True when the draw call rendered something.

### Example
```lua
Pallid.UI.Anim.rect(self, self.anim, 10, 10, 120, 32, Pallid.UI.Color.accent)
```

### Notes
- The track's rotation is not applied; use `Anim.regularPolygon` or `Anim.texture` when rotation matters.
- Scaling happens around the box center, so `x`/`y` describe the unscaled box.

## Pallid.UI.Anim.roundedRect

Draws a rounded rectangle that follows a track's alpha, scale and offset.

**Side:** client

### Parameters
- el (ISUIElement) - Target element.
- track (PallidAnimTrack) - Track already advanced for this frame.
- x (number) - Left coordinate.
- y (number) - Top coordinate.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- radius (number|table) - Corner radius, or a `{tl, tr, br, bl}` table.
- color (PallidColor|nil) - Fill color; nil means white.

### Returns
- boolean - True when the draw call rendered something.

### Example
```lua
Pallid.UI.Anim.roundedRect(self, self.anim, 10, 10, 160, 48, 6, Pallid.UI.Color.surface)
```

### Notes
- A numeric radius is multiplied by `track.scale`; a table radius is passed through unchanged.

## Pallid.UI.Anim.circle

Draws a circle or sector with the track's alpha, scale and offset applied.

**Side:** client

### Parameters
- el (ISUIElement) - Target element.
- track (PallidAnimTrack) - Track already advanced for this frame.
- cx (number) - Center X.
- cy (number) - Center Y.
- radius (number) - Circle radius in pixels.
- color (PallidColor|nil) - Fill color; nil means white.
- a0 (number|nil) - Start angle in radians.
- a1 (number|nil) - End angle in radians.

### Returns
- boolean - True when the draw call rendered something.

### Example
```lua
Pallid.UI.Anim.circle(self, self.anim, cx, cy, 18, Pallid.UI.Color.primary)
```

### Notes
- The radius is multiplied by `track.scale`, so the circle grows from its center.

## Pallid.UI.Anim.regularPolygon

Draws a regular polygon with the track's alpha, scale, offset and rotation.

**Side:** client

### Parameters
- el (ISUIElement) - Target element.
- track (PallidAnimTrack) - Track already advanced for this frame.
- sides (integer) - Number of sides, at least 3.
- cx (number) - Center X.
- cy (number) - Center Y.
- radius (number) - Vertex radius in pixels.
- rotation (number|nil) - Rotation in degrees, added to `track.rotation`.
- color (PallidColor|nil) - Fill color; nil means white.

### Returns
- boolean - True when the draw call rendered something.

### Example
```lua
Pallid.UI.Anim.regularPolygon(self, self.anim, 6, cx, cy, 20, 0, Pallid.UI.Color.warning)
```

### Notes
- This is the draw helper that consumes `track.rotation` for shapes.

## Pallid.UI.Anim.text

Draws text with the track's alpha, offset and scale.

**Side:** client

### Parameters
- el (ISUIElement) - Target element.
- track (PallidAnimTrack) - Track already advanced for this frame.
- str (string) - Text to draw.
- x (number) - Left coordinate.
- y (number) - Top coordinate.
- style (PallidTextStyle) - Text style; create it once and reuse it.

### Returns
- boolean - True when the draw call rendered something.

### Example
```lua
Pallid.UI.Anim.text(self, self.anim, "Loading", 12, 12, self.labelStyle)
```

### Notes
- `style.color` and `style.scale` are mutated for the call and restored afterwards, even when the draw raises.
- The track's rotation is not applied; the text API cannot rotate glyphs.

## Pallid.UI.Anim.texture

Draws a texture around the box center with the track's alpha, scale, offset and
rotation.

**Side:** client

### Parameters
- el (ISUIElement) - Target element.
- track (PallidAnimTrack) - Track already advanced for this frame.
- texture (Texture|nil) - Source texture.
- x (number) - Left coordinate.
- y (number) - Top coordinate.
- w (number) - Width in pixels.
- h (number) - Height in pixels.
- color (PallidColor|nil) - Tint; nil means white.
- opts (PallidTextureOpts|nil) - Texture options; create once and reuse.

### Returns
- boolean - True when the draw call rendered something.

### Example
```lua
local panel = Pallid.UI.Textures.get(Pallid.UI.Assets.panel)
Pallid.UI.Anim.texture(self, self.anim, panel, 10, 10, 200, 64, color, self.textureOpts)
```

### Notes
- `opts` is copied into a shared scratch table, so the same table can be passed every frame.
- The effective rotation is `opts.rotation + track.rotation`.
- Tiled mode tiles inside the scaled box and drops rotation, because the game has no rotated tiled call.
- See [ui-textures.md](ui-textures.md) for the `opts` fields.

## Pallid.UI.Anim.icon

Draws a registered icon scaled around its box center.

**Side:** client

### Parameters
- el (ISUIElement) - Target element.
- track (PallidAnimTrack) - Track already advanced for this frame.
- name (string) - Registered icon name, atlas icon key, or a path containing `/`.
- x (number) - Left coordinate.
- y (number) - Top coordinate.
- size (number) - Width and height of the icon box.
- color (PallidColor|nil) - Tint; nil means white.

### Returns
- boolean - True when the draw call rendered something.

### Example
```lua
Pallid.UI.Anim.icon(self, self.anim, "tick.png", x, y, 16, Pallid.UI.Color.success)
```

### Notes
- The scaled box stays square and centered on the original box, so the icon does not drift while it grows.
- Name resolution is the same as `Pallid.UI.icon`; see [ui-textures.md](ui-textures.md).

See [ui-widget.md](ui-widget.md) for widgets that own their own tracks and call these helpers during render.
