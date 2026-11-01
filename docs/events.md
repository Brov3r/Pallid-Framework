# Pallid.Events

`Pallid.Events` guards the game's global `Events` table. It is an extension of the native implementation, not a second event system: the same event tables stay in place, so existing code that writes `Events.X.Add(fn)` keeps working and becomes safer without changes.

The module lives in shared Lua. If your mod subscribes while its own shared files load, run `require "pallid/events/core"` first; the framework does not guarantee load order for you. Log output is described in [logger](logger.md).

**Side:** shared

The module is shared, but each event fires only on the side the engine fires it: `OnClientCommand` fires on the server, `OnTick` on the client. The module does not mirror events across the network.

## What the module changes

The module modifies the native table once, during load:

- For every event the engine registered at startup, `Add` and `Remove` are replaced with guarded versions. The event table itself is kept, so a cached reference such as `local event = Events.OnTick` stays valid, and callback dispatch is still performed by the engine.
- `Events` receives an `__index` fallback. A name that the engine has not registered yet is created on first access instead of evaluating to `nil`.

The replaced functions keep the native return contract: **`Events.X.Add(fn)` and `Events.X.Remove(fn)` return nothing**. Do not write `local ok = Events.OnTick.Add(fn)`; it always evaluates to `nil`. Use `Pallid.Events.add` or `Pallid.Events.remove` when a success flag is needed.

A value that is not a function passed to `Events.X.Add` is ignored silently, which matches the native contract. Some engine scripts rely on that by passing a global that is not defined yet.

This means the following works even though the engine creates the event only on its first trigger:

```lua
Events.OnExitVehicle.Add(function(character)
    local vehicle = character:getVehicle()
end)
```

A metatable alone would not be enough: names the engine already registered resolve before metamethods run, which is why the existing events are also guarded in place.

## Guarantees and limits

- A handler is registered at most once per event, whether it was added with `Events.X.Add(fn)` or with `Pallid.Events.add`. Subscribing the same function twice does not produce two calls.
- Deduplication covers handlers added after this module loaded. A handler attached earlier is invisible to the module and a repeated subscription of the same function produces a second call.
- `Remove` accepts the function that was passed to `Add` or `once`, not the internal wrapper.
- `Pallid.Events.emit` accepts at most eight event parameters, matching the native trigger overloads.
- Callback order, priority and error isolation are unchanged: the engine still runs handlers in registration order and catches their errors. A failing handler never reaches the caller of the event.
- A missing name is created silently. `Pallid.Events.ensure` returns `false` only when the engine cannot create the event at all.
- Subscribing to an event the game never triggers is still a no-op. The module does not detect that case.

## Pallid.Events.ensure

Creates the event when the engine has not registered it yet and returns whether it is available.

**Side:** shared

### Parameters
- name (string) - Event name.

### Returns
- boolean - `true` when the event exists and is guarded.

### Example
```lua
if not Pallid.Events.ensure("Pallid_Shop_Purchased") then
    Pallid.error("event is unavailable")
end
```

## Pallid.Events.add

Subscribes a function to an event, creating the event when missing.

**Side:** shared

### Parameters
- name (string) - Event name.
- handler (function) - Callback invoked with the event parameters.

### Returns
- boolean - `true` when the handler is subscribed.
- string|nil - Failure reason on rejection: `name required`, `handler required` or `event unavailable`.

### Example
```lua
local ok, reason = Pallid.Events.add("OnGameStart", function()
    Pallid.log("game started")
end)
```

## Pallid.Events.remove

Removes a function previously subscribed to an event.

Unlike `add`, this function never creates the event. Calling it for an event that does not exist returns `false, "unknown event"`.

**Side:** shared

### Parameters
- name (string) - Event name.
- handler (function) - Callback passed to `add` or `once`.

### Returns
- boolean - `true` when the event exists and the removal was requested. Removing an untracked function is forwarded to the native `Remove`.
- string|nil - Failure reason: `name required`, `handler required` or `unknown event`.

### Example
```lua
local function onTick()
end

Events.OnTick.Add(onTick)
Events.OnTick.Remove(onTick)
```

## Pallid.Events.has

Returns whether a handler is tracked as subscribed to an event.

**Side:** shared

### Parameters
- name (string) - Event name.
- handler (function) - Callback passed to `add`, `once` or `Events.X.Add`.

### Returns
- boolean - `true` when the handler is tracked for this event.

### Notes
- A handler registered before this module loaded is not tracked and is reported as absent.
- `has` answers "did I subscribe through the guarded table", not "does the engine hold a callback right now".

### Example
```lua
if not Pallid.Events.has("OnTick", onTick) then
    Events.OnTick.Add(onTick)
end
```

## Pallid.Events.removeAll

Removes every tracked handler of one event.

The event must already exist; this function never creates it. Handlers registered before this module loaded are not tracked and stay attached.

**Side:** shared

### Parameters
- name (string) - Event name.

### Returns
- boolean - `true` when the event was found, including when it had no tracked handlers.
- string|nil - Failure reason: `name required` or `unknown event`.

### Example
```lua
Pallid.Events.removeAll("Pallid_Shop_Purchased")
```

## Pallid.Events.once

Subscribes a function that is removed before its first invocation.

**Side:** shared

### Parameters
- name (string) - Event name.
- handler (function) - Callback invoked once.

### Returns
- boolean - `true` when the handler is subscribed.
- string|nil - Failure reason: `name required`, `handler required`, `already subscribed` or `event unavailable`.

### Example
```lua
Pallid.Events.once("OnGameStart", function()
    Pallid.UI.Host.mount()
end)
```

## Pallid.Events.addMany

Subscribes several handlers in one call. An invalid entry is logged and skipped, so one broken entry does not stop the rest.

**Side:** shared

### Parameters
- list (table) - Array of `{ name = string, fn = function }` entries.

### Returns
- integer|boolean - Number of subscribed entries, or `false` when `list` is not a table.

### Example
```lua
Pallid.Events.addMany({
    { name = "OnGameStart",   fn = onStart, },
    { name = "OnPlayerDeath", fn = onDeath, },
})
```

## Pallid.Events.wrapAction

Wraps a Lua method so it invokes a reporter after every call. Intended for domain event modules that hook timed actions; the class table is modified in place, so already created instances are covered.

**Side:** shared

### Parameters
- class (table|nil) - Class table that owns the method.
- methodName (string) - Method to wrap.
- report (function) - Callback receiving the instance after the call.

### Returns
- boolean - `true` when the method was wrapped.

### Example
```lua
Pallid.Events.wrapAction(MyActionClass, "perform", function(action)
    Pallid.Events.emit("Pallid_MyActionFinished", action.character)
end)
```

## Pallid.Events.emit

Triggers an event, creating it when missing.

**Side:** shared

### Parameters
- name (string) - Event name.
- ... (any) - Event parameters; at most eight values. A ninth value is rejected instead of being dropped.

### Returns
- boolean - `true` when the engine call completed.
- string|nil - Failure reason: `name required`, `too many parameters`, `event unavailable` or the engine call error.

Handler exceptions are not part of this result: the engine catches and logs them for each callback, so they never reach the caller of `emit`.

### Example
```lua
Pallid.Events.emit("Pallid_Shop_Purchased", player, item, price)
```

### Notes
- The native `triggerEvent` is still available and behaves the same, except that it has no parameter limit check.
- An event triggered off the main Lua thread is queued by the engine and delivered later, independently of this module.
- A custom event name should be prefixed, for example `Pallid_Shop_Purchased`, so it cannot collide with an engine event.
- On a full Lua reset the engine recreates the `Events` table and reloads Lua files, so the guards are reinstalled from scratch.

## Provided events

The framework registers these events in addition to the engine ones. Subscribe with `Events.<name>.Add` or `Pallid.Events.add`; parameters are positional.

| Event | Parameters | Side |
| --- | --- | --- |
| `Pallid_ChatMessageSent` | stream, text | client |
| `Pallid_ChatCommandSent` | command | client |
| `Pallid_ChatMessageReceived` | author, text, tabId | client |
| `Pallid_ChatAlertReceived` | text, tabId | client |
| `Pallid_OnlinePlayersChanged` | added, removed, players | client |
| `Pallid_ItemConsumed` | character, item, kind | shared |
| `Pallid_BookReadStarted` | character, book | shared |
| `Pallid_BookReadFinished` | character, book | shared |
| `Pallid_VehicleEntered` | character, vehicle | client |
| `Pallid_VehicleExited` | character, vehicle | client |
| `Pallid_VehicleDoorToggled` | character, vehicle, part, open | client |

### Notes
- `Pallid_ChatMessageSent` reports an attempt accepted by the client, not server delivery. Messages sent outside the chat box, such as radio or server announcements, are not reported.
- `Pallid_OnlinePlayersChanged` fires when the client receives a scoreboard update. The first call reports every currently online player in `added`.
- `Pallid_ItemConsumed` reports the item after the action finished. `kind` is `"eat"` or `"drink"`.
- The vehicle events wrap the timed actions rather than the native `OnEnterVehicle` and `OnExitVehicle`, because the native exit event fires after the character has already left the vehicle and no longer holds a vehicle reference.
