# Pallid.UI.Host

`Pallid.UI.Host` is a full-screen `ISUIElement` that renders one Pallid widget
tree and forwards mouse and keyboard input into it. It never swallows input on
its own: an event is reported as handled only when a widget in the tree consumes
it, so clicks and moves pass through to the game and to elements below the host.

## Pallid.UI.Host:new(opts)

Creates a host element sized from `opts.width` / `opts.height`, or from the
screen when they are omitted. The element is not added to the UI manager and has
no root until `setRoot` is called.

**Side:** client

### Parameters
- opts (table|nil) - Optional host configuration.
- opts.width (number|nil) - Element width in pixels; defaults to `getCore():getScreenWidth()`.
- opts.height (number|nil) - Element height in pixels; defaults to `getCore():getScreenHeight()`.
- opts.onFrame (fun(elapsedMs: number)|nil) - Called after each rendered frame with the UI cost in milliseconds.

### Returns
- PallidUIHost - The new, empty host element.

### Example
```lua
require "pallid/ui/host"
require "pallid/ui/widgets/window"

local host = Pallid.UI.Host:new({
    width  = 1280,
    height = 720,
    onFrame = function(elapsedMs)
        -- elapsedMs is the time spent in animation, draw and overlay.
    end,
})

local root = Pallid.UI.Widgets.window(40, 40, 360, 240, { title = "Example" })
host:setRoot(root)
host:addToUIManager()

Events.OnKeyPressed.Add(function(key)
    host:keyPressed(key)
end)
```

### Notes
- `wantMouseEvents` and `wantExtraMouseEvents` are set to false, which is what makes unconsumed input fall through to the world.
- The element size is fixed at creation; the host does not react to resolution changes.
- To subclass, derive with `Pallid.UI.Host:derive("MyHost")`, call `Pallid.UI.Host:new(opts)` inside your `new`, then reset the metatable on the returned element.

## Host:setRoot(root)

Installs the widget tree that this host draws and routes input to. Passing `nil`
detaches the tree, after which `render`, `update` and every input entry point do
nothing.

**Side:** client

### Parameters
- root (PallidWidget|nil) - Topmost widget of the tree; `nil` removes the tree.

### Returns
- PallidUIHost - The host itself, for chaining.

### Example
```lua
local root = Pallid.UI.Widgets.widget(0, 0, 800, 600)
root:add(Pallid.UI.Widgets.label("Hello", 8, 8, 200, 20))
host:setRoot(root)
```

### Notes
- The host draws the root at element origin `(0, 0)`; the root's own `x` / `y` position it on screen.
- `setRoot` only assigns the field: it does not call `onDetach` on the previous tree, and `shutdown` does not either.

## Host:keyPressed(key)

Forwards a key press to the tree so the focused widget, an open overlay or a
modal can react. The host does not override `onKeyPressed`, so this must be
wired manually, usually from `Events.OnKeyPressed`.

**Side:** client

### Parameters
- key (integer) - `Keyboard.KEY_*` value.

### Returns
- boolean - True when a widget consumed the key.

### Example
```lua
Events.OnKeyPressed.Add(function(key)
    if host:keyPressed(key) then
        return
    end
    -- the key was not consumed by the tree
end)
```

### Notes
- Routing order is modal, open popup, open popover (Escape only), open menu, then the focused widget. See [Widget:keyPress](ui-widget.md#widgetkeypresskey).
- Returns false when no root is installed.

## Host:update()

Game-tick logic pass. It stores the current animation timestamp in `animNow` and
calls `root:update(animNow)`; the engine invokes it once per game tick (about
10 Hz).

**Side:** client

### Notes
- Do not call it from `render`; the engine already drives both.
- All tree logic belongs in `onUpdate`, not here. See [Widget:onUpdate](ui-widget.md#widgetonupdatenow-dt).

## Host:setVisible(visible)

Shows or hides the host element. Hiding also hides every registered native text
box and blurs them, so no native control stays visible or focused over a hidden
tree.

**Side:** client

### Parameters
- visible (boolean) - New visibility of the host element.

### Example
```lua
host:setVisible(false)  -- hides the element and its native text boxes
host:setVisible(true)
```

### Notes
- The tree's own `visible` flags are not changed; only the element and its native boxes are affected.
- Calls `ISUIElement.setVisible`, which instantiates the Java element if it does not exist yet.

## Host:render()

Draws one frame: hides stale native boxes, advances animations, paints the tree
and its overlays, then reports the UI cost to `onFrame`. The engine calls it
while the element is visible.

**Side:** client

### Notes
- Do not call it manually; the engine drives it while the element is visible.
- `onFrame` receives integer milliseconds measured around the animation, draw and overlay passes.

## Host:shutdown()

Stops rendering and releases the tree: hides and blurs native text boxes, clears
`root` and removes the element from the UI manager. Calling it twice is safe.

**Side:** client

### Example
```lua
host:shutdown()
host = nil
```

### Notes
- `onDetach` is not called for the tree, so widgets that keep external registries must release them before shutdown.

## Host:mouseX()

Returns the cursor X position in host-local pixels, read from the element with
`getMouseX()`. This is the coordinate space the widget tree expects.

**Side:** client

### Returns
- number - Cursor X in host-local pixels.

### Example
```lua
local x, y = host:mouseX(), host:mouseY()
if root:isInside(x, y) then
    -- cursor is over the root widget
end
```

## Host:mouseY()

Returns the cursor Y position in host-local pixels, read from the element with
`getMouseY()`.

**Side:** client

### Returns
- number - Cursor Y in host-local pixels.

### Notes
- The element is created at `(0, 0)`, so host-local and screen coordinates coincide until the element is moved.

## Host:onMouseDown(x, y)

Lua `onMouseDown` handler of the element. It dispatches a left press to the root
widget, which makes the topmost accepting widget the mouse capture.

**Side:** client

### Parameters
- x (number) - Ignored; the host reads the cursor with `mouseX()`.
- y (number) - Ignored; the host reads the cursor with `mouseY()`.

### Returns
- boolean - True when a widget consumed the press.

### Example
```lua
local MyHost = Pallid.UI.Host:derive("MyHost")

function MyHost:onMouseDown(x, y)
    -- x and y are ignored by the base implementation.
    return Pallid.UI.Host.onMouseDown(self, x, y)
end
```

### Notes
- Returning false lets the press reach elements below the host and the world.
- The capture keeps receiving moves after the cursor leaves the widget, until the matching release or `releaseCapture`.

## Host:onMouseUp(x, y)

Lua `onMouseUp` handler of the element. It sends a left release to the active
capture and clears it.

**Side:** client

### Parameters
- x (number) - Ignored; the host reads the cursor with `mouseX()`.
- y (number) - Ignored; the host reads the cursor with `mouseY()`.

### Returns
- boolean - True when an active capture received the release.

### Notes
- Returns false when there is no capture or no root, so the release falls through.

## Host:onRightMouseDown(x, y)

Lua `onRightMouseDown` handler. It dispatches a right press to the root widget
and stores the result in `rightDown`.

**Side:** client

### Parameters
- x (number) - Ignored; the host reads the cursor with `mouseX()`.
- y (number) - Ignored; the host reads the cursor with `mouseY()`.

### Returns
- boolean - True when a widget consumed the press.

### Notes
- A right press does not create a capture in the normal tree; only overlays and popups capture on the right button.

## Host:onRightMouseUp(x, y)

Lua `onRightMouseUp` handler. It dispatches the release to the tree, clears
`rightDown` and reports handled when either the pending right press or the
capture consumed it.

**Side:** client

### Parameters
- x (number) - Ignored; the host reads the cursor with `mouseX()`.
- y (number) - Ignored; the host reads the cursor with `mouseY()`.

### Returns
- boolean - True when the active capture or the pending right press consumed the release.

## Host:onMouseMove(dx, dy)

Lua `onMouseMove` handler. It forwards cursor movement to the root widget, which
updates hover state or drives the active capture.

**Side:** client

### Parameters
- dx (number) - Ignored; the host reads the cursor with `mouseX()`.
- dy (number) - Ignored; the host reads the cursor with `mouseY()`.

### Returns
- boolean - True when a capture or a hovered widget consumed the move.

### Notes
- The tree stores the cursor in `mouseX` / `mouseY` on the root here; tooltips and `isInside`-based hit tests rely on it.

## Host:onMouseWheel(del)

Lua `onMouseWheel` handler. It forwards the wheel step to the root widget, which
routes it to a modal, an open menu, a popover or popup, or the innermost widget
that overrides `onWheel`.

**Side:** client

### Parameters
- del (number) - Wheel steps; positive is up.

### Returns
- boolean - True when the tree consumed the wheel.

### Notes
- Returning false keeps the world zoom and other elements below the host responsive.
