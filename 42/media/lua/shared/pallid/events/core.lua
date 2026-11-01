require "utils/logger"

Pallid = Pallid or {}

--- Facade that guards the game's global `Events` table.
---
--- The module extends the native table in place instead of replacing it: every
--- existing event receives a guarded `Add`/`Remove`, and a missing name is
--- created on first access. Code that keeps using `Events.X.Add(fn)` therefore
--- becomes safe without changes, including events the engine creates lazily,
--- such as `OnExitVehicle`.
---
--- Side: shared.
---@class PallidEvents
Pallid.Events = Pallid.Events or {}

local api = Pallid.Events

--- Maximum number of event parameters accepted by one trigger.
--- The engine has overloads for zero to eight parameters, so a ninth value is
--- rejected instead of being dropped silently.
local MAX_PARAMS = 8

--- Internal module state. Kept on `Pallid.Events` so a repeated execution of
--- this file reuses the same event records instead of wrapping each event twice.
local internal = api._internal
if internal == nil then
    internal = {
        records            = {},
        metatableInstalled = false,
    }
    api._internal = internal
end

--- Adds a handler to an already wrapped event.
---
--- The same handler is registered once per event. `original` is the function the
--- caller passed in, while `registered` is the closure handed to the engine; the
--- two differ for `Pallid.Events.once`.
---@param name string Event name.
---@param original function Handler supplied by the caller.
---@param registered function Closure actually passed to the engine.
---@return boolean ok True when the handler is registered.
local function addHandler(name, original, registered)
    if type(original) ~= "function" then
        return false
    end

    local record = internal.records[name]
    if record == nil then
        return false
    end

    local subscriptions = record.subscriptions
    if subscriptions == nil then
        subscriptions = {}
        record.subscriptions = subscriptions
    end

    if subscriptions[original] ~= nil then
        return true
    end

    subscriptions[original] = registered
    record.nativeAdd(registered)
    return true
end

--- Removes a handler from an already wrapped event.
---
--- Accepts the function the caller subscribed with, so a `once` wrapper is
--- resolved back to its original handler. A handler that was registered before
--- this module loaded is forwarded to the native `Remove`.
---@param name string Event name.
---@param original function Handler supplied by the caller.
---@return boolean ok True when a tracked handler was removed.
local function removeHandler(name, original)
    local record = internal.records[name]
    if record == nil or type(original) ~= "function" then
        return false
    end

    local subscriptions = record.subscriptions
    if subscriptions == nil then
        if record.nativeRemove ~= nil then
            record.nativeRemove(original)
        end
        return false
    end

    local registered = subscriptions[original]
    if registered == nil then
        if record.nativeRemove ~= nil then
            record.nativeRemove(original)
        end
        return false
    end

    subscriptions[original] = nil
    if record.nativeRemove ~= nil then
        record.nativeRemove(registered)
    end
    return true
end

--- Replaces the native `Add` and `Remove` of one event with guarded versions.
---
--- The event table itself is kept, so a cached reference such as
--- `local event = Events.OnTick` stays valid. Native functions are captured once
--- and reused, which keeps the engine dispatch path untouched.
---@param name string Event name.
---@return table|nil event The same event table, or nil when it is not usable.
local function wrapEvent(name)
    local event = rawget(Events, name)
    if type(event) ~= "table" then
        return nil
    end

    if internal.records[name] ~= nil then
        return event
    end

    local nativeAdd = event.Add
    local nativeRemove = event.Remove
    if type(nativeAdd) ~= "function" then
        return nil
    end

    internal.records[name] = {
        nativeAdd    = nativeAdd,
        nativeRemove = nativeRemove,
    }

    --- Guards the native `Add` of this event.
    ---
    --- Returns nothing, exactly like the native function. A value that is not a
    --- function is ignored, which also matches the native contract. Call
    --- `Pallid.Events.add` when a success flag is needed.
    ---@param handler function Callback invoked with the event parameters.
    event.Add = function(handler)
        if type(handler) ~= "function" then
            return
        end

        addHandler(name, handler, handler)
    end

    --- Guards the native `Remove` of this event.
    ---
    --- Returns nothing, exactly like the native function.
    ---@param handler function Callback previously passed to `Add`.
    event.Remove = function(handler)
        removeHandler(name, handler)
    end

    return event
end

--- Returns an event table, creating the event when the engine has not done so.
---
--- The engine registers some events only on their first trigger. Reading such a
--- name before that point yields nil, which is why a direct `.Add` call used to
--- fail. `LuaEventManager.AddEvent` registers the event immediately; a plain
--- trigger is kept as a fallback for a build where that class is not exposed.
---@param name string Event name.
---@return table|nil event Guarded event table, or nil when creation failed.
local function ensure(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local event = rawget(Events, name)
    if type(event) ~= "table" then
        if type(LuaEventManager) == "table" and type(LuaEventManager.AddEvent) == "function" then
            LuaEventManager.AddEvent(name)
        end

        event = rawget(Events, name)
        if type(event) ~= "table" and type(triggerEvent) == "function" then
            triggerEvent(name)
            event = rawget(Events, name)
        end
    end

    if type(event) ~= "table" then
        return nil
    end

    return wrapEvent(name)
end

--- Wraps every event that the engine registered during startup.
local function wrapAll()
    for name in pairs(Events) do
        if type(name) == "string" then
            wrapEvent(name)
        end
    end
end

--- Installs an `__index` fallback so an unknown name is created on first access.
---
--- A metatable alone cannot cover the existing events because `rawget` resolves
--- them before metamethods run, which is why `wrapAll` is required as well. An
--- existing metatable is not discarded: its `__index` is chained after this one.
local function installMetatable()
    if internal.metatableInstalled then
        return
    end

    local previous = getmetatable(Events)
    local previousIndex = nil
    if type(previous) == "table" then
        previousIndex = rawget(previous, "__index")
    end

    setmetatable(Events, {
        __index = function(_, key)
            if type(key) ~= "string" then
                return nil
            end

            local event = ensure(key)
            if event ~= nil then
                return event
            end

            if type(previousIndex) == "function" then
                return previousIndex(Events, key)
            end

            if type(previousIndex) == "table" and previousIndex ~= Events then
                return previousIndex[key]
            end

            return nil
        end,
    })

    internal.metatableInstalled = true
end

--- Returns whether an event exists, creating it when the engine has not done so.
---@param name string Event name.
---@return boolean ok True when the event is available and guarded.
function api.ensure(name)
    return ensure(name) ~= nil
end

--- Subscribes a function to an event.
---
--- Safe to call during file load: the event is created when the engine has not
--- registered it yet, and the same function is never registered twice.
---@param name string Event name.
---@param handler function Callback invoked with the event parameters.
---@return boolean ok True when the handler is subscribed.
---@return string|nil reason Failure reason: `name required`, `handler required` or `event unavailable`.
function api.add(name, handler)
    if type(name) ~= "string" or name == "" then
        Pallid.error("Pallid.Events.add requires an event name")
        return false, "name required"
    end

    if type(handler) ~= "function" then
        Pallid.error("Pallid.Events.add requires a function handler for", name)
        return false, "handler required"
    end

    if ensure(name) == nil then
        Pallid.error("Pallid.Events.add could not resolve the event", name)
        return false, "event unavailable"
    end

    if not addHandler(name, handler, handler) then
        return false, "event unavailable"
    end

    return true
end

--- Removes a function previously subscribed to an event.
---
--- The original handler is resolved even when it was registered through
--- `Pallid.Events.once`. Removing an untracked handler is forwarded to the
--- native `Remove` and reported as `false`. Unlike `add`, this function never
--- creates the event.
---@param name string Event name.
---@param handler function Callback passed to `add` or `once`.
---@return boolean ok True when a tracked handler was removed.
---@return string|nil reason Failure reason: `name required`, `handler required` or `unknown event`.
function api.remove(name, handler)
    if type(name) ~= "string" or name == "" then
        return false, "name required"
    end

    if type(handler) ~= "function" then
        return false, "handler required"
    end

    if type(rawget(Events, name)) ~= "table" then
        return false, "unknown event"
    end

    removeHandler(name, handler)
    return true
end

--- Returns whether a handler is tracked as subscribed to an event.
---
--- A handler registered before this module loaded is not tracked and is
--- reported as absent.
---@param name string Event name.
---@param handler function Callback passed to `add`, `once` or `Events.X.Add`.
---@return boolean ok True when the handler is tracked for this event.
function api.has(name, handler)
    if type(name) ~= "string" or type(handler) ~= "function" then
        return false
    end

    local record = internal.records[name]
    if record == nil or record.subscriptions == nil then
        return false
    end

    return record.subscriptions[handler] ~= nil
end

--- Removes every tracked handler of one event.
---
--- The event must already exist; this function never creates it. Handlers that
--- were registered before this module loaded are not tracked and stay attached.
---@param name string Event name.
---@return boolean ok True when the event was found.
---@return string|nil reason Failure reason: `name required` or `unknown event`.
function api.removeAll(name)
    if type(name) ~= "string" or name == "" then
        return false, "name required"
    end

    local record = internal.records[name]
    if record == nil then
        return false, "unknown event"
    end

    local subscriptions = record.subscriptions
    if subscriptions == nil then
        return true
    end

    for handler, registered in pairs(subscriptions) do
        subscriptions[handler] = nil
        if record.nativeRemove ~= nil then
            record.nativeRemove(registered)
        end
    end

    return true
end

--- Subscribes a function that is removed before its first invocation.
---
--- The wrapper unsubscribes itself first, so a failing handler is not invoked a
--- second time. `Pallid.Events.remove` and `Events.X.Remove` both accept the
--- original function.
---@param name string Event name.
---@param handler function Callback invoked once.
---@return boolean ok True when the handler is subscribed.
---@return string|nil reason Failure reason: `name required`, `handler required`, `already subscribed` or `event unavailable`.
function api.once(name, handler)
    if type(name) ~= "string" or name == "" then
        Pallid.error("Pallid.Events.once requires an event name")
        return false, "name required"
    end

    if type(handler) ~= "function" then
        Pallid.error("Pallid.Events.once requires a function handler for", name)
        return false, "handler required"
    end

    if ensure(name) == nil then
        Pallid.error("Pallid.Events.once could not resolve the event", name)
        return false, "event unavailable"
    end

    local record = internal.records[name]
    if record ~= nil and record.subscriptions ~= nil and record.subscriptions[handler] ~= nil then
        return false, "already subscribed"
    end

    --- Unsubscribes itself, then invokes the caller handler once.
    ---@param ... any Event parameters.
    ---@return any result Values returned by the caller handler.
    local function wrapper(...)
        removeHandler(name, handler)
        return handler(...)
    end

    if not addHandler(name, handler, wrapper) then
        return false, "event unavailable"
    end

    return true
end

--- Subscribes several handlers in one call.
---
--- Each entry is a table with `name` and `fn` fields. Invalid entries are logged
--- and skipped, so one broken entry does not stop the remaining subscriptions.
---@param list table Array of `{ name = string, fn = function }` entries.
---@return integer|boolean added Number of subscribed entries, or `false` when `list` is not a table.
function api.addMany(list)
    if type(list) ~= "table" then
        Pallid.error("Pallid.Events.addMany requires a list")
        return false
    end

    local added = 0
    for index = 1, #list do
        local entry = list[index]
        if type(entry) ~= "table" then
            Pallid.error("Pallid.Events.addMany entry", index, "is not a table")
        else
            local ok, reason = api.add(entry.name, entry.fn)
            if ok then
                added = added + 1
            else
                Pallid.error("Pallid.Events.addMany entry", index, "failed:", tostring(reason))
            end
        end
    end

    return added
end

--- Wraps one Lua method so it reports itself after every call.
---
--- Intended for domain event modules that hook timed actions. The class table is
--- modified in place; existing instances resolve the method through their class
--- metatable, so already created objects are covered.
---@param class table|nil Class table that owns the method.
---@param methodName string Method to wrap.
---@param report function Callback receiving the instance after the call.
---@return boolean ok True when the method was wrapped.
function api.wrapAction(class, methodName, report)
    if type(class) ~= "table" or type(class[methodName]) ~= "function" or type(report) ~= "function" then
        return false
    end

    local original = class[methodName]

    --- Forwards the call, then reports the instance.
    ---@param self table Instance the method was called on.
    ---@param ... any Original method arguments.
    ---@return any result Value returned by the original method.
    local function wrapped(self, ...)
        local result = original(self, ...)
        report(self)
        return result
    end

    class[methodName] = wrapped
    return true
end

--- Triggers an event, creating it when missing.
---
--- Unlike a raw `triggerEvent`, the number of event parameters is checked
--- against the engine limit and the engine call itself is protected. Handler
--- exceptions are already caught and logged by the engine, so they never reach
--- this function.
---@param name string Event name.
---@param ... any Event parameters; at most eight values.
---@return boolean ok True when the event was triggered.
---@return string|nil reason Failure reason: `name required`, `too many parameters`, `event unavailable` or the engine call error.
function api.emit(name, ...)
    if type(name) ~= "string" or name == "" then
        Pallid.error("Pallid.Events.emit requires an event name")
        return false, "name required"
    end

    if select("#", ...) > MAX_PARAMS then
        Pallid.error("Pallid.Events.emit accepts at most", MAX_PARAMS, "parameters:", name)
        return false, "too many parameters"
    end

    if ensure(name) == nil then
        Pallid.error("Pallid.Events.emit could not resolve the event", name)
        return false, "event unavailable"
    end

    local ok, err = pcall(triggerEvent, name, ...)
    if not ok then
        Pallid.error("Pallid.Events.emit failed for", name, ":", tostring(err))
        return false, tostring(err)
    end

    return true
end

if type(Events) == "table" then
    wrapAll()
    installMetatable()
else
    Pallid.error("Pallid.Events: global Events table is unavailable")
end

return Pallid
