require "utils/logger"

Pallid = Pallid or {}
Pallid.Net = Pallid.Net or {}

local Codec = require "pallid/net/codec"
local Guard = require "pallid/net/guard"

local Net = Pallid.Net
local logger = Pallid.getLogger("Net")

--- Lua module name carried by every Pallid network command.
local MODULE = "Pallid_Net"

--- Command name carried by every Pallid network command.
local COMMAND = "msg"

--- Envelope version. A mismatched version is logged and dropped.
local PROTOCOL_VERSION = 1

--- Minimum interval between repeated rejection log lines.
local LOG_INTERVAL_MS = 5000

--- Maximum number of characters written for a client-controlled log value.
local LOG_TEXT_LIMIT = 64

--- Maximum number of characters written for a handler error message.
local LOG_ERROR_TEXT_LIMIT = 256

--- Upper bound for a random dedup nonce. Kept below 2^31 so it is a safe
--- integer on the native double transport.
local NONCE_MAX = 2147483646

--- Envelope keys accepted by the dispatcher. `n` is the optional dedup nonce.
local ENVELOPE_KEYS = {
    a = true,
    p = true,
    v = true,
    n = true,
}

--- Internal module state. Kept on `Pallid.Net` so a repeated execution of this
--- file reuses the same handler tables and listener guard instead of adding a
--- second set of event listeners.
local internal = Net._internal
if internal == nil then
    internal = {
        initialized       = false,
        serverHandlers    = {},
        clientHandlers    = {},
        lastVersionWarnMs = 0,
        lastCodecWarnMs   = 0,
        lastUnknownWarnMs = 0,
        lastSchemaWarnMs  = 0,
    }
    Net._internal = internal
end

-- Defensive defaults for a file that is re-executed in an existing environment.
internal.lastCommandWarnMs = internal.lastCommandWarnMs or 0
internal.lastEnvelopeWarnMs = internal.lastEnvelopeWarnMs or 0
internal.lastDedupWarnMs = internal.lastDedupWarnMs or 0

--- Sanitizes a client-controlled value before it reaches the log.
---
--- Truncates long strings and replaces control characters so a newline or a
--- control sequence cannot forge a log line.
---@param value any Value to convert to safe log text.
---@param limit number|nil Maximum number of characters to keep.
---@return string text Sanitized text.
local function sanitizeForLog(value, limit)
    local text = tostring(value)
    local maxLength = limit or LOG_TEXT_LIMIT
    if #text > maxLength then
        text = string.sub(text, 1, maxLength) .. "..."
    end
    return (string.gsub(text, "%c", "?"))
end

--- Logs a rejected payload with throttling.
---@param context string Short description of the call site.
---@param action string Action whose payload was rejected.
---@param reason string|nil Codec or schema failure reason.
local function warnCodec(context, action, reason)
    local now = getTimestampMs()
    if now - internal.lastCodecWarnMs < LOG_INTERVAL_MS then
        return
    end

    internal.lastCodecWarnMs = now
    Pallid.warn(context, "rejected payload for", sanitizeForLog(action), ":", sanitizeForLog(reason))
end

--- Logs a schema rejection with throttling.
---@param context string Short description of the call site.
---@param action string Action whose payload failed the schema.
---@param reason string|nil Schema failure reason.
local function warnSchema(context, action, reason)
    local now = getTimestampMs()
    if now - internal.lastSchemaWarnMs < LOG_INTERVAL_MS then
        return
    end

    internal.lastSchemaWarnMs = now
    Pallid.warn(context, "schema rejected payload for", sanitizeForLog(action), ":", sanitizeForLog(reason))
end

--- Logs a protocol version mismatch with throttling.
---@param version any Version value received in the envelope.
local function warnVersion(version)
    local now = getTimestampMs()
    if now - internal.lastVersionWarnMs < LOG_INTERVAL_MS then
        return
    end

    internal.lastVersionWarnMs = now
    Pallid.warn("dropped message with protocol version", sanitizeForLog(version),
        "expected", tostring(PROTOCOL_VERSION))
end

--- Logs an unknown action only in debug mode, with throttling.
---@param side string "server" or "client".
---@param action string Unknown action name.
local function warnUnknown(side, action)
    local now = getTimestampMs()
    if now - internal.lastUnknownWarnMs < LOG_INTERVAL_MS then
        return
    end

    internal.lastUnknownWarnMs = now
    Pallid.log("ignored unknown", side, "action", sanitizeForLog(action))
end

--- Logs an unknown command inside the Pallid_Net namespace with throttling.
---@param side string "server" or "client".
---@param command string Unknown command name.
local function warnCommand(side, command)
    local now = getTimestampMs()
    if now - internal.lastCommandWarnMs < LOG_INTERVAL_MS then
        return
    end

    internal.lastCommandWarnMs = now
    Pallid.warn("ignored unknown", side, "command", sanitizeForLog(command))
end

--- Logs a malformed envelope with throttling.
---
--- The offending key is intentionally not logged because it is controlled by
--- the sender and could inject text into the log.
---@param side string "server" or "client".
local function warnEnvelope(side)
    local now = getTimestampMs()
    if now - internal.lastEnvelopeWarnMs < LOG_INTERVAL_MS then
        return
    end

    internal.lastEnvelopeWarnMs = now
    Pallid.warn("dropped malformed envelope on", side)
end

--- Logs a dedup rejection with throttling.
---@param side string "server" or "client".
---@param action string Registered action name.
---@param reason string|nil Dedup failure reason.
local function warnDedup(side, action, reason)
    local now = getTimestampMs()
    if now - internal.lastDedupWarnMs < LOG_INTERVAL_MS then
        return
    end

    internal.lastDedupWarnMs = now
    Pallid.warn("dedup rejected payload for", sanitizeForLog(action), ":", sanitizeForLog(reason))
end

--- Returns true when an envelope contains only supported keys.
---@param args table Envelope table received from the transport.
---@return boolean valid False when an unexpected key is present.
local function hasOnlyEnvelopeKeys(args)
    for key in pairs(args) do
        if not ENVELOPE_KEYS[key] then
            return false
        end
    end
    return true
end

--- Random source for dedup nonces. Kahlua exposes `newrandom()` instead of
--- `math.random`, so the module keeps one random object and reuses it.
local nonceRandom = newrandom()

--- Returns a fresh random nonce for the optional dedup check.
---@return number nonce Random integer in the supported nonce range.
local function nextNonce()
    return nonceRandom:random(1, NONCE_MAX)
end

--- Dispatches one server-bound message to a registered handler.
---
--- The player always comes from the command event, never from the payload.
--- The global per-player bucket is applied before the action lookup so unknown
--- actions cannot bypass it.
---@param action string Action name from the envelope.
---@param player IsoPlayer|nil Sending player taken from the event.
---@param payload any Payload value from the envelope.
---@param nonce number|nil Optional dedup nonce from the envelope.
---@return boolean ok False when the message was rejected before the handler.
---@return string|nil reason Rejection reason.
local function dispatchServer(action, player, payload, nonce)
    local onlineID = -1
    if player ~= nil then
        onlineID = player:getOnlineID()
    end

    local now = getTimestampMs()

    if not Guard.checkGlobalRateLimit(onlineID, now) then
        return false, "global rate limited"
    end

    local entry = internal.serverHandlers[action]
    if entry == nil then
        if getDebug() then
            warnUnknown("server", action)
        end
        return true
    end

    if entry.limit ~= nil then
        if not Guard.checkRateLimit(entry, onlineID, now) then
            return false, "rate limited"
        end
    end

    local ok, reason = Codec.validate(payload)
    if not ok then
        warnCodec("server", action, reason)
        return false, reason
    end

    if not Guard.checkCapability(entry, player, now) then
        return false, "capability denied"
    end

    if entry.schema ~= nil then
        local schemaOk, schemaReason = Guard.applySchema(entry.schema, payload)
        if not schemaOk then
            warnSchema("server", action, schemaReason)
            return false, schemaReason
        end
    end

    if entry.dedup then
        local dedupOk, dedupReason = Guard.checkDedup(entry, onlineID, nonce)
        if not dedupOk then
            warnDedup("server", action, dedupReason)
            return false, dedupReason
        end
    end

    local called, callErr = pcall(entry.handler, player, payload)
    if not called then
        Pallid.error("Pallid.Net handler failed for action", action, ":",
            sanitizeForLog(callErr, LOG_ERROR_TEXT_LIMIT))
    end

    return true
end

--- Dispatches one client-bound message to a registered handler.
---@param action string Action name from the envelope.
---@param payload any Payload value from the envelope.
---@return boolean ok False when the message was rejected before the handler.
---@return string|nil reason Rejection reason.
local function dispatchClient(action, payload)
    local entry = internal.clientHandlers[action]
    if entry == nil then
        if getDebug() then
            warnUnknown("client", action)
        end
        return true
    end

    local ok, reason = Codec.validate(payload)
    if not ok then
        warnCodec("client", action, reason)
        return false, reason
    end

    if entry.schema ~= nil then
        local schemaOk, schemaReason = Guard.applySchema(entry.schema, payload)
        if not schemaOk then
            warnSchema("client", action, schemaReason)
            return false, schemaReason
        end
    end

    local called, callErr = pcall(entry.handler, payload)
    if not called then
        Pallid.error("Pallid.Net handler failed for action", action, ":",
            sanitizeForLog(callErr, LOG_ERROR_TEXT_LIMIT))
    end

    return true
end

--- Handles every client-to-server Pallid command.
---
--- The server Lua directory is also loaded on a multiplayer client, so this
--- listener must do nothing there. In singleplayer both `isServer()` and
--- `isClient()` are false and the listener is active for local dispatch.
---@param module string Command module name.
---@param command string Command name.
---@param player IsoPlayer|nil Player taken from the command event.
---@param args table|nil Command arguments.
local function onClientCommand(module, command, player, args)
    if module ~= MODULE then
        return
    end

    if command ~= COMMAND then
        warnCommand("server", command)
        return
    end

    if isClient() and not isServer() then
        return
    end

    if type(args) ~= "table" then
        return
    end

    if not hasOnlyEnvelopeKeys(args) then
        warnEnvelope("server")
        return
    end

    if type(args.v) ~= "number" or args.v ~= PROTOCOL_VERSION then
        warnVersion(args.v)
        return
    end

    if type(args.a) ~= "string" then
        return
    end

    dispatchServer(args.a, player, args.p, args.n)
end

--- Handles every server-to-client Pallid command.
---
--- A dedicated server never runs this listener because it never receives its
--- own server commands.
---@param module string Command module name.
---@param command string Command name.
---@param args table|nil Command arguments.
local function onServerCommand(module, command, args)
    if module ~= MODULE then
        return
    end

    if command ~= COMMAND then
        warnCommand("client", command)
        return
    end

    if isServer() and not isClient() then
        return
    end

    if type(args) ~= "table" then
        return
    end

    if not hasOnlyEnvelopeKeys(args) then
        warnEnvelope("client")
        return
    end

    if type(args.v) ~= "number" or args.v ~= PROTOCOL_VERSION then
        warnVersion(args.v)
        return
    end

    if type(args.a) ~= "string" then
        return
    end

    dispatchClient(args.a, args.p)
end

--- Returns whether this process owns authoritative game state.
---
--- True on a dedicated or co-op server and in singleplayer, where neither
--- `isServer()` nor `isClient()` is set. False on a multiplayer client.
---@return boolean authority True when sending and broadcasting are allowed.
function Net.isAuthority()
    return isServer() or not isClient()
end

--- Sends a message from the client to the server as a specific local player.
---
--- Internal use only. Public callers use `Net.sendToServer`, which resolves the
--- primary local player. Split-screen consumers that already hold the correct
--- local player use this variant so the native packet carries the right player
--- index. The player is a trusted local object, never taken from a payload.
---@param player IsoPlayer|nil Local player sending the message.
---@param action string Action name, conventionally "Owner_action".
---@param payload any Payload value; validated before sending.
---@return boolean ok True when the message was accepted for delivery.
---@return string|nil reason Failure reason.
function Net._sendToServerAs(player, action, payload)
    if type(action) ~= "string" or action == "" then
        return false, "action must be a non-empty string"
    end

    if isServer() and not isClient() then
        return false, "cannot send to the server from the server"
    end

    if not isClient() then
        return dispatchServer(action, player, payload, nextNonce())
    end

    if player == nil then
        return false, "no local player"
    end

    if not player:isLocalPlayer() then
        return false, "local player expected"
    end

    local ok, reason = Codec.validate(payload)
    if not ok then
        warnCodec("sendToServer", action, reason)
        return false, reason
    end

    local envelope = {
        a = action,
        n = nextNonce(),
        p = payload,
        v = PROTOCOL_VERSION,
    }

    local sent, sendErr = pcall(sendClientCommand, player, MODULE, COMMAND, envelope)
    if not sent then
        logger:error("sendClientCommand failed for", action, ":", tostring(sendErr))
        return false, "native send failed"
    end

    return true
end

--- Sends a message from the client to the server.
---
--- In singleplayer the registered server handler is called directly because
--- the native `sendServerCommand` transport does nothing there. The message is
--- never delivered twice: the local path does not use the native transport.
--- The native packet is sent as the primary local player (`getPlayer()`).
--- Split-screen consumers that already hold a specific local player use the
--- internal `_sendToServerAs` variant instead.
---@param action string Action name, conventionally "Owner_action".
---@param payload any Payload value; validated before sending.
---@return boolean ok True when the message was accepted for delivery.
---@return string|nil reason Failure reason.
function Net.sendToServer(action, payload)
    if isServer() and not isClient() then
        return false, "cannot send to the server from the server"
    end

    return Net._sendToServerAs(getPlayer(), action, payload)
end

--- Sends a message from the server to one client.
---
--- In singleplayer the registered client handler is called directly because
--- the native `sendServerCommand` transport does nothing there.
---@param player IsoPlayer Target player.
---@param action string Action name, conventionally "Owner_action".
---@param payload any Payload value; validated before sending.
---@return boolean ok True when the message was accepted for delivery.
---@return string|nil reason Failure reason.
function Net.send(player, action, payload)
    if not Net.isAuthority() then
        return false, "not authority"
    end

    if type(action) ~= "string" or action == "" then
        return false, "action must be a non-empty string"
    end

    if player == nil or not instanceof(player, "IsoPlayer") then
        return false, "IsoPlayer expected"
    end

    if not isServer() then
        return dispatchClient(action, payload)
    end

    local ok, reason = Codec.validate(payload)
    if not ok then
        warnCodec("send", action, reason)
        return false, reason
    end

    local envelope = {
        a = action,
        p = payload,
        v = PROTOCOL_VERSION,
    }

    local sent, sendErr = pcall(sendServerCommand, player, MODULE, COMMAND, envelope)
    if not sent then
        logger:error("sendServerCommand failed for", action, ":", tostring(sendErr))
        return false, "native send failed"
    end

    return true
end

--- Sends a message from the server to every client.
---
--- In singleplayer the registered client handler is called once directly
--- because the native `sendServerCommand` transport does nothing there.
---@param action string Action name, conventionally "Owner_action".
---@param payload any Payload value; validated before sending.
---@return boolean ok True when the message was accepted for delivery.
---@return string|nil reason Failure reason.
function Net.broadcast(action, payload)
    if not Net.isAuthority() then
        return false, "not authority"
    end

    if type(action) ~= "string" or action == "" then
        return false, "action must be a non-empty string"
    end

    if not isServer() then
        return dispatchClient(action, payload)
    end

    local ok, reason = Codec.validate(payload)
    if not ok then
        warnCodec("broadcast", action, reason)
        return false, reason
    end

    local envelope = {
        a = action,
        p = payload,
        v = PROTOCOL_VERSION,
    }

    local sent, sendErr = pcall(sendServerCommand, MODULE, COMMAND, envelope)
    if not sent then
        logger:error("sendServerCommand failed for", action, ":", tostring(sendErr))
        return false, "native send failed"
    end

    return true
end

--- Registers a server-side action handler.
---
--- Registration is allowed on every side because the server Lua directory is
--- also loaded on a multiplayer client for checksum parity. The handler is only
--- invoked by the guarded dispatcher. A duplicate action on the same side is
--- rejected instead of silently overwriting the previous handler.
---
--- A conservative rate limit is applied when `limit` is omitted. Pass
--- `limit = false` to opt out of the per-action limit; the global per-player
--- limit still applies. `dedup = true` enables replay protection using the
--- random nonce carried by every server-bound envelope.
---@param action string Action name, conventionally "Owner_action".
---@param options table|function|nil Optional options table, or the handler.
---@param handler function|nil Handler receiving `(player, payload)`.
---@return boolean ok False when the registration was rejected.
---@return string|nil reason Failure reason.
function Net.onServer(action, options, handler)
    if type(options) == "function" and handler == nil then
        handler = options
        options = nil
    end

    if type(action) ~= "string" or action == "" then
        Pallid.error("Pallid.Net.onServer: action must be a non-empty string")
        return false, "action required"
    end

    if type(handler) ~= "function" then
        Pallid.error("Pallid.Net.onServer: handler must be a function for", action)
        return false, "handler required"
    end

    if internal.serverHandlers[action] ~= nil then
        Pallid.error("Pallid.Net.onServer: duplicate action", action)
        return false, "duplicate action"
    end

    local normalized, reason = Guard.normalizeOptions(options, "server")
    if normalized == nil then
        Pallid.error("Pallid.Net.onServer: invalid options for", action, ":", tostring(reason))
        return false, reason
    end

    local entry = {
        action     = action,
        handler    = handler,
        limit      = normalized.limit,
        schema     = normalized.schema,
        capability = normalized.capability,
        dedup      = normalized.dedup,
    }

    if entry.limit ~= nil then
        entry.tokens = {}
        entry.refilledAt = {}
        entry.lastWarnMs = 0
    end

    if entry.dedup then
        entry.nonceRings = {}
        entry.nonceIndexes = {}
    end

    internal.serverHandlers[action] = entry
    return true
end

--- Registers a client-side action handler.
---
--- `limit`, `capability` and `dedup` are server-only options and are rejected
--- here.
---@param action string Action name, conventionally "Owner_action".
---@param options table|function|nil Optional options table, or the handler.
---@param handler function|nil Handler receiving `(payload)`.
---@return boolean ok False when the registration was rejected.
---@return string|nil reason Failure reason.
function Net.onClient(action, options, handler)
    if type(options) == "function" and handler == nil then
        handler = options
        options = nil
    end

    if type(action) ~= "string" or action == "" then
        Pallid.error("Pallid.Net.onClient: action must be a non-empty string")
        return false, "action required"
    end

    if type(handler) ~= "function" then
        Pallid.error("Pallid.Net.onClient: handler must be a function for", action)
        return false, "handler required"
    end

    if internal.clientHandlers[action] ~= nil then
        Pallid.error("Pallid.Net.onClient: duplicate action", action)
        return false, "duplicate action"
    end

    local normalized, reason = Guard.normalizeOptions(options, "client")
    if normalized == nil then
        Pallid.error("Pallid.Net.onClient: invalid options for", action, ":", tostring(reason))
        return false, reason
    end

    internal.clientHandlers[action] = {
        action = action,
        handler = handler,
        schema = normalized.schema,
    }

    return true
end

--- Runs the codec self-check. Intended for manual debugging only.
---
--- Not called during load and refused outside debug mode. Run it from the Lua
--- console with `Pallid.Net.selfTest()` while debug mode is enabled.
---@return boolean ok True when every codec case produced the expected result.
---@return number passed Number of passed checks.
function Net.selfTest()
    if not getDebug() then
        Pallid.warn("Pallid.Net.selfTest requires debug mode")
        return false, 0
    end

    return Codec.selfTest()
end

if not internal.initialized then
    Events.OnClientCommand.Add(onClientCommand)
    Events.OnServerCommand.Add(onServerCommand)
    Events.EveryOneMinute.Add(function()
        Guard.cleanup(internal.serverHandlers)
    end)
    internal.initialized = true
end

return Pallid
