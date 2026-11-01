# PallidWidget

`PallidWidget` is the base class of every Pallid UI widget and owns the retained
tree: a widget keeps its children, and the root is the only widget without a
parent. Coordinates are relative to the parent, while hit tests and input hooks
receive root-local coordinates. Input is routed topmost-first; the widget that
accepted a press becomes the capture and keeps receiving moves until the
matching release.

## Pallid.UI.Widgets

Table of the UI widget classes and helpers. `Widgets.Widget` is the base class,
`Widgets.Tooltip` is the tooltip class, and every concrete widget is registered
under its own name (for example `Widgets.Button`, `Widgets.Window`).

**Side:** client

### Example
```lua
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/button"

local row = Pallid.UI.Widgets.widget(0, 0, 0, 0)
local button = Pallid.UI.Widgets.button(0, 0, 120, 28, { text = "OK" })
```

### Notes
- Require `pallid/ui/widgets/widget` to get this table; each concrete widget file registers itself when it is required.
- The same table also holds `class`, `widget` and `approach`.

## Widgets.class(name, base)

Creates an empty class table whose metatable inherits from `base` (the base
widget by default) and registers it as `Widgets[name]`. An existing entry with
the same name is replaced.

**Side:** client

### Parameters
- name (string) - Class name used as the registry key.
- base (table|nil) - Parent class; defaults to the base `Widget`.

### Returns
- table - The new, empty class table.

### Example
```lua
require "pallid/ui/widgets/widget"

local Badge = Pallid.UI.Widgets.class("Badge")

function Badge.new(x, y, w, h)
    local self = setmetatable({}, Badge)
    self:init(x, y, w, h)
    return self
end
```

### Notes
- The subclass must define its own `new`: the inherited one would create an instance of the base class with the wrong metatable.
- `className` is set on the new class.

## Widgets.widget(x, y, w, h)

Factory shortcut for `Widget.new` that creates a plain container with no drawing
of its own. Containers with `w` or `h` equal to 0 are layout nodes: they are
still traversed by hit tests and drawing.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels; 0 marks a layout container.
- h (number) - Height in pixels; 0 marks a layout container.

### Returns
- PallidWidget - New container widget.

### Example
```lua
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/label"

local row = Pallid.UI.Widgets.widget(0, 0, 0, 0)
row:add(Pallid.UI.Widgets.label("Name", 0, 0, 120, 20))
```

## Widget.new(x, y, w, h)

Creates a plain container widget directly on the base class. Use it when you do
not need a subclass, or call `Widget:init` from your own `new`.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.

### Returns
- PallidWidget - New widget.

### Example
```lua
require "pallid/ui/widgets/widget"

local spacer = Pallid.UI.Widgets.Widget.new(0, 0, 8, 8)
```

## Widget:init(x, y, w, h)

Shared field setup used by every `new`. It sets the bounds, makes the widget
visible and enabled, and resets the cached origins, the update timestamp and the
tick delta.

**Side:** client

### Parameters
- x (number) - Offset X from the parent's origin.
- y (number) - Offset Y from the parent's origin.
- w (number) - Width in pixels.
- h (number) - Height in pixels.

### Returns
- PallidWidget - The initialized widget.

### Notes
- `x`, `y`, `w` and `h` fall back to 0 when omitted.
- Call it before any subclass-specific field setup so the defaults are in place.

## Widget:add(child)

Adds a child to the end of the parent's draw and hit-test order. Re-adding an
existing child moves it to the top instead of duplicating it, and `onAttach` runs
on the child and every descendant.

**Side:** client

### Parameters
- child (PallidWidget) - Widget to attach.

### Returns
- PallidWidget - The same child, for chaining.

### Example
```lua
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/button"

local row = Pallid.UI.Widgets.widget(0, 0, 200, 32)
row:add(Pallid.UI.Widgets.button(0, 0, 120, 28, { text = "OK" }))
```

### Notes
- Errors when `child` is the widget itself or one of its ancestors, because the cycle would make draw and update recurse forever.
- A child that already has a parent is removed from the old parent first.

## Widget:remove(child)

Detaches a direct child from the tree and calls `onDetach` on its subtree.
Removing a widget that is not a direct child is a no-op.

**Side:** client

### Parameters
- child (PallidWidget) - Widget to detach.

### Example
```lua
row:remove(button)
```

### Notes
- The child is not hidden or destroyed; it can be added to another parent afterwards.
- Removing a grandchild through its grandparent does nothing.

## Widget:onAttach()

Lifecycle hook called after the widget has been added to a parent, then on every
descendant. The default implementation is a no-op.

**Side:** client

### Example
```lua
function MyWidget:onAttach()
    Registry[self] = true
end
```

### Notes
- It fires on any `add`, not only when the tree becomes reachable from a root.
- Widgets that keep external registries should register themselves here.

## Widget:onDetach()

Lifecycle hook called after the widget leaves the tree, then on every descendant.
The default implementation is a no-op.

**Side:** client

### Example
```lua
function MyWidget:onDetach()
    Registry[self] = nil
end
```

### Notes
- Kahlua does not implement weak tables, so a registry never shrinks on its own; release entries here.
- It is not called when a host is shut down or when `Host:setRoot` replaces the tree.

## Widget:setOverlay(overlay)

Marks the widget to be painted after all normal siblings of its parent,
regardless of insertion order. The flag can be changed while the widget is
attached; the parent's overlay counter stays in sync.

**Side:** client

### Parameters
- overlay (boolean) - True to draw in the overlay pass.

### Returns
- PallidWidget - The widget itself, for chaining.

### Example
```lua
local banner = Pallid.UI.Widgets.panel(0, 0, 200, 24)
root:add(banner)
banner:setOverlay(true)  -- paints above later siblings
```

### Notes
- Only siblings are affected; the widget still paints inside its parent's pass.
- Setting the same value twice is a no-op.

## Widget:setBounds(x, y, w, h)

Moves and resizes the widget without touching its children. Children keep their
own offsets, so they move with the parent but do not resize.

**Side:** client

### Parameters
- x (number) - New offset X from the parent's origin.
- y (number) - New offset Y from the parent's origin.
- w (number) - New width in pixels.
- h (number) - New height in pixels.

### Returns
- PallidWidget - The widget itself, for chaining.

### Example
```lua
label:setBounds(12, 12, 240, 20)
```

## Widget:setVisible(visible)

Shows or hides the widget and its whole subtree. Hidden widgets are skipped by
drawing, update, animation and hit testing.

**Side:** client

### Parameters
- visible (boolean) - True shows the widget, false hides the subtree.

### Returns
- PallidWidget - The widget itself, for chaining.

### Example
```lua
label:setVisible(false)
```

### Notes
- A hidden parent hides its children even when they are `visible = true` themselves.
- This does not affect native text boxes; the host hides those on its own.

## Widget:setEnabled(enabled)

Sets the `enabled` flag that widget implementations use to draw themselves
dimmed and to reject input. The base class only stores the flag.

**Side:** client

### Parameters
- enabled (boolean) - False marks the widget as disabled.

### Returns
- PallidWidget - The widget itself, for chaining.

### Example
```lua
saveButton:setEnabled(false)
```

### Notes
- The base input routing does not check `enabled`; concrete widgets such as buttons test it in their own `onDown`.
- `shade` is the base helper that reads the flag, so custom drawing can dim itself.

## Widget:setTooltip(text, delay)

Attaches a hover tooltip. A string creates or updates a plain-text tooltip; a
prepared `PallidTooltip` is attached as rich content with title, rows and footer.

**Side:** client

### Parameters
- text (string|PallidTooltip) - Tooltip body text, or a tooltip instance whose `draw` field is set.
- delay (number|nil) - Seconds before the fade starts; defaults to 0.12 on creation.

### Returns
- PallidWidget - The widget itself, for chaining.

### Example
```lua
local save = Pallid.UI.Widgets.button(8, 8, 120, 28, { text = "Save" })
save:setTooltip("Writes the profile to disk", 0.3)
```

### Notes
- Passing a string to a widget that already has a rich tooltip clears its title, rows and footer first.
- An existing tooltip keeps its delay unless a new `delay` is passed.
- The tooltip is shown by the host's overlay pass, so it needs a hovered widget and a cursor position.

## Widget:originX()

Absolute X of the widget inside the root: the parent origin cached by the last
draw or input traversal plus the widget's own `x`.

**Side:** client

### Returns
- number - Absolute X in root-local coordinates.

### Example
```lua
local ax, ay = label:originX(), label:originY()
```

### Notes
- The cached origin is 0 until the widget has been drawn or hit-tested at least once.

## Widget:originY()

Absolute Y of the widget inside the root: the cached parent origin plus the
widget's own `y`.

**Side:** client

### Returns
- number - Absolute Y in root-local coordinates.

## Widget:isInside(px, py)

Returns true when the point lies inside the widget's box. The test is half-open:
the left and top edges are inside, the right and bottom edges are not.

**Side:** client

### Parameters
- px (number) - Cursor X in root-local coordinates.
- py (number) - Cursor Y in root-local coordinates.

### Returns
- boolean - True when the point is inside the widget's box.

### Example
```lua
-- host is a Pallid.UI.Host; see ui-host.md
local x, y = host:mouseX(), host:mouseY()
if label:isInside(x, y) then
    -- cursor is over the label
end
```

### Notes
- Coordinates are root-local, not widget-local; subtract `originX()` / `originY()` if you need local values.
- Zero-sized layout containers never contain a point, but their children can.

## Widget:isPointVisible(px, py)

True when the point can reach the widget after every ancestor applies its
visibility and clipping. Use it for external hit tests such as drop targets,
where a widget inside an inactive tab page or a scrolled-out row is still
`visible = true` for itself.

**Side:** client

### Parameters
- px (number) - Cursor X in root-local coordinates.
- py (number) - Cursor Y in root-local coordinates.

### Returns
- boolean - True when the point is inside the painted subtree.

### Example
```lua
-- host is a Pallid.UI.Host; see ui-host.md
local x, y = host:mouseX(), host:mouseY()
if dropTarget:isPointVisible(x, y) then
    -- the target is reachable through every visible, unclipped ancestor
end
```

### Notes
- It checks ancestors only; it does not test whether the point is inside this widget's own box. Combine it with `isInside` when both are needed.

## Widget:preferredSize(maxW, maxH)

Returns the size the widget would like to occupy. The default is its current
bounds; auto-sized and composite widgets override it so containers can lay them
out without hard-coded sizes.

**Side:** client

### Parameters
- maxW (number|nil) - Available width in pixels; nil means unconstrained.
- maxH (number|nil) - Available height in pixels; nil means unconstrained.

### Returns
- number - Preferred width in pixels.
- number - Preferred height in pixels.

### Example
```lua
local w, h = widget:preferredSize(availableWidth, availableHeight)
```

## Widget:preferredWidth(maxH)

Returns the preferred width for an available height by calling
`preferredSize(nil, maxH)` and keeping the first result.

**Side:** client

### Parameters
- maxH (number|nil) - Available height in pixels; nil means unconstrained.

### Returns
- number - Preferred width in pixels.

## Widget:preferredHeight(maxW)

Returns the preferred height for an available width by calling
`preferredSize(maxW, nil)` and keeping the second result.

**Side:** client

### Parameters
- maxW (number|nil) - Available width in pixels; nil means unconstrained.

### Returns
- number - Preferred height in pixels.

## Widget:update(now)

Game-tick pass. It calls `onUpdate` when the widget overrides it, updates every
child, removes children marked dead during the pass, and updates the overlays
owned by the root.

**Side:** client

### Parameters
- now (number) - Current game-tick time in seconds.

### Notes
- Override `onUpdate`, not this method.
- Hidden widgets and their whole subtree are skipped.
- The host calls it from `Host:update`; see [Host:update](ui-host.md#hostupdate).

## Widget:onUpdate(now, dt)

Called on the game tick (about 10 Hz) for logic: timers, retries and input
bookkeeping. Visual state belongs in `onAnimate`.

**Side:** client

### Parameters
- now (number) - Current time in seconds.
- dt (number) - Seconds since the previous tick, clamped to 0..0.1.

### Example
```lua
function MyWidget:onUpdate(now, dt)
    self.elapsed = (self.elapsed or 0) + dt
end
```

### Notes
- It is only called when the widget overrides it; a widget that leaves the default does not pay for the delta computation.
- One long stall cannot make a step larger than 0.1 s.

## Widget:onAnimate(now, dt)

Called once per rendered frame, before the widget is drawn. Override it to
advance time-based visual state such as tracks or approach smoothing.

**Side:** client

### Parameters
- now (number) - Current time in seconds.
- dt (number) - Seconds since the previous frame, clamped to 0..0.1.

### Example
```lua
function MyWidget:onAnimate(now, dt)
    self.alpha = Pallid.UI.Widgets.approach(self.alpha or 0, 1, 12, dt)
end
```

### Notes
- Do not change the tree or fire events here; use `onUpdate` for that.
- Frames are not guaranteed; a hidden widget receives no animation calls.

## Widget:updateAnimations(now)

Advances animation state for this widget, its children and the overlays owned by
the root. The host calls it from `render`, once per frame.

**Side:** client

### Parameters
- now (number) - Current time in seconds.

### Notes
- Override only if you need a different traversal; visual logic belongs in `onAnimate`.
- Hidden widgets and their subtree are skipped.

## Widget:delta(now)

Time since the previous `delta` call on this widget, clamped to 0..0.1. The
first call returns 0 and only starts the clock.

**Side:** client

### Parameters
- now (number) - Current time in seconds.

### Returns
- number - Seconds since the previous call, 0..0.1.

### Example
```lua
local dt = widget:delta(now)  -- 0 on the first call
```

### Notes
- It uses its own timestamp, separate from `animDelta`, so the tick pass and the frame pass do not steal each other's time.
- `update` calls it once per tick before `onUpdate`; a manual call consumes the timestamp the next tick would have used.

## Widget:animDelta(now)

Time since the previous animation frame for this widget, clamped to 0..0.1.
`updateAnimations` calls it before `onAnimate` and passes the result as `dt`.

**Side:** client

### Parameters
- now (number) - Current time in seconds.

### Returns
- number - Seconds since the previous frame, 0..0.1.

### Notes
- It uses a separate timestamp from `delta`; a manual call consumes the next frame's delta.

## Widget:shade(color, slot)

Returns `color` unchanged while the widget is enabled, or a copy with its alpha
multiplied by 0.4 while disabled. Use it in custom drawing so disabled widgets
dim consistently.

**Side:** client

### Parameters
- color (PallidColor) - Source color.
- slot (integer|nil) - Scratch slot, defaults to 1.

### Returns
- PallidColor - Dimmed color owned by the widget, or the source color while enabled.

### Example
```lua
function MyWidget:drawSelf(el)
    Pallid.UI.rect(el, self:originX(), self:originY(), self.w, self.h,
        self:shade(Pallid.UI.Color.surface))
end
```

### Notes
- The returned table is reused by the widget; pass it straight to a draw call instead of storing it.
- Use two different slots when a single call needs two dimmed colors at once.

## Widgets.approach(current, target, speed, dt)

Frame-rate independent exponential approach with a dead zone. It returns
`target` once the remaining distance is below 0.001, and `current` when `dt` is
zero or negative.

**Side:** client

### Parameters
- current (number) - Current value.
- target (number) - Value to approach.
- speed (number) - Higher is faster.
- dt (number) - Time step in seconds.

### Returns
- number - Next value, or `target` once inside the dead zone.

### Example
```lua
function MyWidget:onAnimate(now, dt)
    self.alpha = Pallid.UI.Widgets.approach(self.alpha or 0, 1, 12, dt)
end
```

### Notes
- The dead zone is what lets the value settle exactly on the target instead of oscillating forever.

## Overlay state

The root owns its overlays as fields, not as tree children: `modal`,
`openPopover`, `openPopup` and `openMenu` are updated and drawn separately from
`children`.

**Side:** client

### Notes
- There is no `Widget:setModal`, `Widget:openPopover`, `Widget:closePopover`, `Widget:openMenu` or `Widget:closeMenu`.
- Overlays are opened by their own widgets: `PallidModalDialog:open(root)`, `PallidPopover:show(anchor, side)` or `Popover:showAt(root, x, y)`, and `PallidMenu:show(root, x, y)`; each closes with `close()`.
- Opening an overlay sets the matching root field, and the host's input routing checks those fields before the tree.

## Widget:mouseDown(px, py, button)

Root entry point for a mouse press. It walks the tree topmost-first, makes the
topmost widget whose `onDown` returns true the capture, and returns whether
anything consumed the press.

**Side:** client

### Parameters
- px (number) - Cursor X in root-local coordinates.
- py (number) - Cursor Y in root-local coordinates.
- button (string|nil) - `"left"` (default) or `"right"`.

### Returns
- boolean - True when a widget consumed the press.

### Example
```lua
-- Normally called by the host; call it yourself only when you drive the tree.
local handled = root:mouseDown(host:mouseX(), host:mouseY(), "left")
```

### Notes
- The host calls it from `onMouseDown` / `onRightMouseDown`; see [ui-host.md](ui-host.md).
- Only a left press creates a capture in the normal tree; overlays and popups capture on both buttons.
- A modal or an open popup / popover consumes every press, including presses outside its content.
- Override `onDown(px, py, button)` to accept presses; `px` and `py` are root-local.

## Widget:mouseUp(px, py, button)

Root entry point for a mouse release. It sends the release to the active capture
only when the released button matches the one that created the capture, then
clears the capture.

**Side:** client

### Parameters
- px (number) - Cursor X in root-local coordinates.
- py (number) - Cursor Y in root-local coordinates.
- button (string|nil) - Button being released; nil means `"left"`.

### Returns
- boolean - True when an active capture received the release.

### Notes
- A release of a different button returns false and keeps the capture, so a drag is not aborted by another button.
- The capture is restored to the coordinates it had at press time, so `onUp` works in the same space as `onMove`.
- Override `onUp(px, py)` to react to the release.

## Widget:mouseMove(px, py)

Root entry point for cursor movement. It routes the move to a modal, an open
menu or the active capture first, then to the topmost hovered widget, checking
an open popup and popover before the tree.

**Side:** client

### Parameters
- px (number) - Cursor X in root-local coordinates.
- py (number) - Cursor Y in root-local coordinates.

### Returns
- boolean - True when a capture or hovered widget consumed the move.

### Notes
- It stores the cursor in `mouseX` / `mouseY` on the root; tooltips and external hit tests read those fields.
- Entering and leaving a widget calls `onHoverStart` / `onHoverEnd`; `onHoverEnd` resets the tooltip fade.
- Override `onMove(px, py)` to follow a drag; it runs while the widget is the capture, even outside its bounds.

## Widget:mouseWheel(px, py, delta)

Root entry point for the wheel. It routes the step to a modal, an open menu,
then an open popover or popup, and finally to the innermost widget that
overrides `onWheel`.

**Side:** client

### Parameters
- px (number) - Cursor X in root-local coordinates.
- py (number) - Cursor Y in root-local coordinates.
- delta (number) - Wheel steps; positive is up.

### Returns
- boolean - True when a widget consumed the wheel.

### Notes
- The wheel over popover padding is consumed too, so the world zoom does not react under an open popover.
- Override `onWheel(delta)` to consume the wheel; the default returns false.

## Widget:keyPress(key)

Root entry point for a key press. It routes the key to the modal, an open popup,
an open popover (Escape only), an open menu, then the focused widget.

**Side:** client

### Parameters
- key (integer) - `Keyboard.KEY_*` value.

### Returns
- boolean - True when a widget consumed the key.

### Notes
- A visible focused widget counts as handled even if its `onKeyPress` does nothing.
- Escape cancels an open popover before the focused widget sees it.
- Override `onKeyPress(key)` to handle keys while the widget owns focus.

## Widget:focus()

Gives keyboard focus to the widget, calling `onBlur` on the previous owner and
`onFocus` on this widget. Calling it on the widget that already owns focus is a
no-op.

**Side:** client

### Example
```lua
entry:focus()
```

### Notes
- Focus is stored on the root, so a widget must be attached to a tree for `keyPress` to reach it.
- Only widgets with `acceptsFocus = true` are focused automatically on a left press.

## Widget:blur()

Releases keyboard focus when this widget owns it, calling `onBlur`.

**Side:** client

### Returns
- boolean - True when the widget owned the keyboard focus.

### Example
```lua
entry:blur()
```

## Widget:releaseCapture()

Drops the root's mouse capture when this widget owns it. Use it when a drag or a
keybind recording ends without a matching release, such as a lost mouse-up or a
watchdog cancel.

**Side:** client

### Notes
- It does not call `onUp`; clean up drag state yourself after calling it.
- Calling it on a widget that is not the capture does nothing.

## Widget:getRoot()

Returns the topmost widget of the tree by walking the `parent` chain. A widget
without a parent returns itself.

**Side:** client

### Returns
- PallidWidget - Topmost widget of the tree this one belongs to.

### Example
```lua
local root = widget:getRoot()
```

## Widget:registerNative(native)

Registers a widget that owns a native text box on the root, so overlays can mask
the box later in the frame. The registry stores the owning widget, not the Java
element, and native boxes are not tree children.

**Side:** client

### Parameters
- native (PallidInputBase) - Input widget that owns the native text box.

### Notes
- Text inputs register themselves from their draw pass with `root:registerNative(self)`.
- The registry is a plain Lua table, so a widget that leaves the tree must unregister itself.

## Widget:unregisterNative(native)

Removes a widget previously passed to `registerNative`. Removing a widget that
is not registered is a no-op.

**Side:** client

### Parameters
- native (PallidInputBase) - Input widget previously registered by the widget.

### Example
```lua
function MyInput:onDetach()
    -- `parent` is already cleared here, so use the root cached when registering.
    if self.nativeRoot ~= nil then
        self.nativeRoot:unregisterNative(self)
        self.nativeRoot = nil
    end
end
```

### Notes
- `onDetach` runs after the parent link is cleared, so `getRoot()` no longer returns the tree you registered with.
- Call it on the same widget that received `registerNative`, which is normally the root.

## Widget:setNativeVisible(visible)

Hides or shows the native text boxes owned by this widget, its subtree and its
overlays. The host calls it with false before each frame so only the boxes
actually drawn in that frame stay visible.

**Side:** client

### Parameters
- visible (boolean) - False hides the native boxes of the whole subtree.

### Notes
- The base implementation recurses into children, the modal, the open popover and the open menu; input widgets override it to hide their own box.
- It does not touch the widgets themselves; only the native elements are affected.

## Widget:blurNative()

Unfocuses the native text boxes owned by this widget, its subtree and its
overlays. The host calls it when it hides or shuts down.

**Side:** client

### Notes
- The base implementation recurses into children and overlays; input widgets override it to unfocus their own box.
- Use it when you hide a subtree manually and a native box inside it may still own keyboard focus.

## Widget:maskNative(overlay, x, y, w, h)

Hides registered native boxes that intersect a rectangle, except boxes that
belong to `overlay`. All coordinates are root-local.

**Side:** client

### Parameters
- overlay (PallidWidget) - Overlay whose own subtree is kept visible.
- x (number) - Rectangle left in root-local coordinates.
- y (number) - Rectangle top in root-local coordinates.
- w (number) - Rectangle width in pixels.
- h (number) - Rectangle height in pixels.

### Notes
- The base implementation forwards the call to the widgets registered on this one; the root normally holds the registry.
- The host calls it for open menus, popups and popovers, because native boxes would otherwise draw above those overlays.

## Widget:maskNativeExcept(overlay)

Hides every registered native box outside `overlay`'s subtree. The modal
backdrop uses it because the dim covers the whole root.

**Side:** client

### Parameters
- overlay (PallidWidget) - Overlay whose own subtree is kept visible.
