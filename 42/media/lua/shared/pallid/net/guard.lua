require "utils/logger"

Pallid = Pallid or {}

--- Validation and abuse protection for the Pallid network layer.
---
--- The guard owns per-player rate limiting, capability checks, schema
--- validation of untrusted payloads, optional replay protection and limiter
--- state cleanup. All state is keyed by numeric online ids; no `IsoPlayer`
--- reference is retained.
---@class PallidNetGuard
local Guard = {}

--- Logger used for throttled rejection messages.
local logger = Pallid.getLogger("Net")

--- Minimum interval between repeated rejection log lines.
local WARN_INTERVAL_MS = 5000

--- Default per-action rate limit used when `onServer` omits `limit`.
local DEFAULT_LIMIT_MAX = 10

--- Default per-action rate-limit window in milliseconds.
local DEFAULT_LIMIT_WINDOW = 1000

--- Global per-player token bucket capacity applied before dispatch.
local GLOBAL_LIMIT_MAX = 50

--- Global per-player token-bucket refill window in milliseconds.
local GLOBAL_LIMIT_WINDOW = 1000

--- Number of recent nonces kept for a deduplicated action.
local DEDUP_WINDOW = 128

--- Reusable scratch list for limiter cleanup and schema field removal.
local scratch = {}

--- Global token buckets keyed by online id.
local globalTokens = {}

--- Timestamp of the last global token refill, keyed by online id.
local globalRefilledAt = {}

--- Timestamp of the last throttled global rate-limit warning.
local lastGlobalWarnMs = 0

--- Timestamp of the last throttled spoofed-identity warning.
local lastSpoofWarnMs = 0

--- Timestamp of the last throttled replay warning.
local lastReplayWarnMs = 0

--- Payload field names that must never carry identity from a client.
local SPOOF_FIELDS = {
    onlineID = true,
    username = true,
    playerId = true,
    role     = true,
    steamID  = true,
}

--- Schema types accepted by `normalizeOptions`.
local VALID_SCHEMA_TYPES = {
    string    = true,
    number    = true,
    boolean   = true,
    table     = true,
    numberMap = true,
}

--- Returns true when a number is finite.
---@param value number Value to inspect.
---@return boolean finite False for NaN and positive/negative infinity.
local function isFinite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end

--- Normalizes one schema field definition into an owned table.
---@param field string Payload field name.
---@param spec string|table Type string or a detailed field spec.
---@return table|nil normalized Owned field spec.
---@return string|nil reason Failure description.
local function normalizeFieldSpec(field, spec)
    local specType = type(spec)
    local normalized = {
        type      = nil,
        optional  = false,
        min       = nil,
        max       = nil,
        maxLength = nil,
    }

    if specType == "string" then
        if not VALID_SCHEMA_TYPES[spec] then
            return nil, "unknown schema type '" .. tostring(spec) .. "' for field '" .. field .. "'"
        end
        normalized.type = spec
        return normalized
    end

    if specType ~= "table" then
        return nil, "schema field '" .. field .. "' must be a type string or a spec table"
    end

    if type(spec.type) ~= "string" or not VALID_SCHEMA_TYPES[spec.type] then
        return nil, "schema field '" .. field .. "' has an unknown type"
    end
    normalized.type = spec.type

    if spec.optional ~= nil then
        if type(spec.optional) ~= "boolean" then
            return nil, "schema field '" .. field .. "' optional must be a boolean"
        end
        normalized.optional = spec.optional
    end

    if spec.maxLength ~= nil then
        if normalized.type ~= "string" then
            return nil, "schema field '" .. field .. "' uses maxLength on a non-string type"
        end
        if type(spec.maxLength) ~= "number" or not isFinite(spec.maxLength)
            or spec.maxLength < 1 or spec.maxLength ~= math.floor(spec.maxLength) then
            return nil, "schema field '" .. field .. "' has an invalid maxLength"
        end
        normalized.maxLength = spec.maxLength
    end

    if spec.min ~= nil or spec.max ~= nil then
        if normalized.type ~= "number" then
            return nil, "schema field '" .. field .. "' uses min/max on a non-number type"
        end

        if spec.min ~= nil then
            if type(spec.min) ~= "number" or not isFinite(spec.min) then
                return nil, "schema field '" .. field .. "' has an invalid min"
            end
            normalized.min = spec.min
        end

        if spec.max ~= nil then
            if type(spec.max) ~= "number" or not isFinite(spec.max) then
                return nil, "schema field '" .. field .. "' has an invalid max"
            end
            normalized.max = spec.max
        end

        if normalized.min ~= nil and normalized.max ~= nil and normalized.min > normalized.max then
            return nil, "schema field '" .. field .. "' has min greater than max"
        end
    end

    return normalized
end

--- Normalizes a rate-limit option into an owned table.
---@param limit table Rate-limit definition with `max` and `window`.
---@return table|nil normalized Owned rate-limit definition.
---@return string|nil reason Failure description.
local function normalizeLimit(limit)
    if type(limit) ~= "table" then
        return nil, "limit must be a table"
    end

    local max = limit.max
    local window = limit.window

    if type(max) ~= "number" or not isFinite(max) or max < 1 then
        return nil, "limit.max must be a positive number"
    end

    if type(window) ~= "number" or not isFinite(window) or window < 1 then
        return nil, "limit.window must be a positive number of milliseconds"
    end

    return {
        max    = max,
        window = window,
    }
end

--- Normalizes a schema definition into an owned table.
---@param schema table Map of payload field name to type string or field spec.
---@return table|nil normalized Owned schema map.
---@return string|nil reason Failure description.
local function normalizeSchema(schema)
    if type(schema) ~= "table" then
        return nil, "schema must be a table"
    end

    local normalized = {}
    for field, spec in pairs(schema) do
        if type(field) ~= "string" then
            return nil, "schema field names must be strings"
        end

        local fieldSpec, reason = normalizeFieldSpec(field, spec)
        if fieldSpec == nil then
            return nil, reason
        end
        normalized[field] = fieldSpec
    end

    return normalized
end

--- Normalizes the options table accepted by `onServer` and `onClient`.
---
--- Server handlers get a conservative default rate limit when `limit` is
--- omitted. `limit = false` opts out of the per-action limit explicitly; the
--- global per-player limit still applies. `capability` must be a real
--- `Capability` value, not a string or a boolean.
---@param options table|nil Options supplied at registration.
---@param side string "server" or "client"; selects the allowed options.
---@return table|nil normalized Owned options with `limit`, `schema`, `capability` and `dedup`.
---@return string|nil reason Failure description.
function Guard.normalizeOptions(options, side)
    local normalized = {
        limit      = nil,
        schema     = nil,
        capability = nil,
        dedup      = false,
    }

    if options == nil then
        if side == "server" then
            normalized.limit = {
                max    = DEFAULT_LIMIT_MAX,
                window = DEFAULT_LIMIT_WINDOW,
            }
        end
        return normalized
    end

    if type(options) ~= "table" then
        return nil, "options must be a table"
    end

    for key in pairs(options) do
        if key ~= "limit" and key ~= "schema" and key ~= "capability" and key ~= "dedup" then
            return nil, "unknown option '" .. tostring(key) .. "'"
        end
    end

    if options.limit ~= nil then
        if side ~= "server" then
            return nil, "limit is only supported by onServer"
        end

        if options.limit == false then
            normalized.limit = nil
        else
            local limit, reason = normalizeLimit(options.limit)
            if limit == nil then
                return nil, reason
            end
            normalized.limit = limit
        end
    elseif side == "server" then
        normalized.limit = {
            max    = DEFAULT_LIMIT_MAX,
            window = DEFAULT_LIMIT_WINDOW,
        }
    end

    if options.schema ~= nil then
        local schema, reason = normalizeSchema(options.schema)
        if schema == nil then
            return nil, reason
        end
        normalized.schema = schema
    end

    if options.capability ~= nil then
        if side ~= "server" then
            return nil, "capability is only supported by onServer"
        end
        local capabilityType = type(options.capability)
        if capabilityType == "string" or capabilityType == "number"
            or capabilityType == "boolean" or capabilityType == "function" then
            return nil, "capability must be a Capability value"
        end
        normalized.capability = options.capability
    end

    if options.dedup ~= nil then
        if side ~= "server" then
            return nil, "dedup is only supported by onServer"
        end
        if type(options.dedup) ~= "boolean" then
            return nil, "dedup must be a boolean"
        end
        normalized.dedup = options.dedup
    end

    return normalized
end

--- Applies a token-bucket rate limit for one player and action.
---
--- The bucket holds `limit.max` tokens and refills `limit.max` tokens over
--- `limit.window` milliseconds. This avoids the double burst a fixed window
--- allows at the window boundary. A rejected message is dropped and the
--- rejection log line is throttled.
---@param entry table Registered server handler entry with limiter state.
---@param onlineID number Online id of the sending player, or -1 when unknown.
---@param now number Current timestamp in milliseconds.
---@return boolean allowed False when the message must be dropped.
function Guard.checkRateLimit(entry, onlineID, now)
    local limit = entry.limit
    if limit == nil then
        return true
    end

    if entry.tokens == nil then
        entry.tokens = {}
        entry.refilledAt = {}
        entry.lastWarnMs = 0
    end

    local tokens = entry.tokens[onlineID]
    local refilledAt = entry.refilledAt[onlineID]

    if tokens == nil then
        tokens = limit.max
        refilledAt = now
    else
        local elapsed = now - refilledAt
        if elapsed > 0 then
            tokens = math.min(limit.max, tokens + elapsed * limit.max / limit.window)
            refilledAt = now
        end
    end

    if tokens < 1 then
        entry.tokens[onlineID] = tokens
        entry.refilledAt[onlineID] = refilledAt
        if now - entry.lastWarnMs >= WARN_INTERVAL_MS then
            entry.lastWarnMs = now
            logger:warn("rate-limited action", entry.action, "for player", tostring(onlineID))
        end
        return false
    end

    entry.tokens[onlineID] = tokens - 1
    entry.refilledAt[onlineID] = refilledAt
    return true
end

--- Applies the global per-player token bucket before action dispatch.
---
--- This bounds the total message rate even for actions that opt out of their
--- per-action limit, and also covers unknown actions that only cost the native
--- deserializer.
---@param onlineID number Online id of the sending player, or -1 when unknown.
---@param now number Current timestamp in milliseconds.
---@return boolean allowed False when the message must be dropped.
function Guard.checkGlobalRateLimit(onlineID, now)
    local tokens = globalTokens[onlineID]
    local refilledAt = globalRefilledAt[onlineID]

    if tokens == nil then
        tokens = GLOBAL_LIMIT_MAX
        refilledAt = now
    else
        local elapsed = now - refilledAt
        if elapsed > 0 then
            tokens = math.min(GLOBAL_LIMIT_MAX, tokens + elapsed * GLOBAL_LIMIT_MAX / GLOBAL_LIMIT_WINDOW)
            refilledAt = now
        end
    end

    if tokens < 1 then
        globalTokens[onlineID] = tokens
        globalRefilledAt[onlineID] = refilledAt
        if now - lastGlobalWarnMs >= WARN_INTERVAL_MS then
            lastGlobalWarnMs = now
            logger:warn("global rate limit reached for player", tostring(onlineID))
        end
        return false
    end

    globalTokens[onlineID] = tokens - 1
    globalRefilledAt[onlineID] = refilledAt
    return true
end

--- Checks a handler capability against the sending player's role.
---
--- Capability checks are enforced only on a real multiplayer server. In
--- singleplayer the local player has no server role, and blocking the local
--- player would break singleplayer behaviour for no security benefit.
---@param entry table Registered server handler entry.
---@param player IsoPlayer|nil Player taken from the command event.
---@param now number Current timestamp in milliseconds.
---@return boolean allowed False when the player lacks the capability.
function Guard.checkCapability(entry, player, now)
    if entry.capability == nil or not isServer() then
        return true
    end

    if player ~= nil and Role.hasCapability(player, entry.capability) then
        return true
    end

    if now - (entry.lastDenyMs or 0) >= WARN_INTERVAL_MS then
        entry.lastDenyMs = now
        logger:warn("capability denied for action", entry.action)
    end

    return false
end

--- Validates an untrusted payload against a schema and normalizes it in place.
---
--- Required fields are enforced. Extra fields are removed; known identity
--- fields (`onlineID`, `username`, `playerId`, `role`, `steamID`) trigger a
--- throttled spoof warning before removal. A numeric field outside its
--- `min`/`max` range is clamped, not rejected: clamping is the documented
--- behaviour and matches the second-level clamping done by gameplay modules
--- such as moodles. A `numberMap` field must be a table of numbers. A string
--- `maxLength` is measured in UTF-16 code units, while the codec separately
--- enforces the native 32767-byte limit.
---@param schema table Normalized schema map.
---@param payload any Incoming payload value.
---@return boolean ok False when the payload does not match the schema.
---@return string|nil reason Failure description.
function Guard.applySchema(schema, payload)
    if type(payload) ~= "table" then
        return false, "payload must be a table when a schema is set"
    end

    for field, spec in pairs(schema) do
        local value = payload[field]
        if value == nil then
            if not spec.optional then
                return false, "missing required field '" .. field .. "'"
            end
        elseif spec.type == "numberMap" then
            if type(value) ~= "table" then
                return false, "field '" .. field .. "' must be a number map"
            end
            for key, item in pairs(value) do
                if type(item) ~= "number" then
                    return false, "field '" .. field .. "' must contain only numbers"
                end
            end
        else
            local valueType = type(value)
            if valueType ~= spec.type then
                return false, "field '" .. field .. "' must be " .. spec.type .. ", got " .. valueType
            end

            if spec.type == "number" then
                if spec.min ~= nil and value < spec.min then
                    value = spec.min
                end
                if spec.max ~= nil and value > spec.max then
                    value = spec.max
                end
                payload[field] = value
            elseif spec.type == "string" and spec.maxLength ~= nil and #value > spec.maxLength then
                return false, "field '" .. field .. "' exceeds the " .. tostring(spec.maxLength) .. "-character limit"
            end
        end
    end

    local count = 0
    for field in pairs(payload) do
        if schema[field] == nil then
            if SPOOF_FIELDS[field] then
                local now = getTimestampMs()
                if now - lastSpoofWarnMs >= WARN_INTERVAL_MS then
                    lastSpoofWarnMs = now
                    logger:warn("ignored spoofed identity field", field, "in a payload")
                end
            end
            count = count + 1
            scratch[count] = field
        end
    end

    for i = 1, count do
        payload[scratch[i]] = nil
        scratch[i] = nil
    end

    return true
end

--- Rejects a replayed nonce for an action that opted into deduplication.
---
--- The client sends a fresh random nonce with every server-bound message. The
--- guard keeps the last `DEDUP_WINDOW` nonces per `(online id, action)` and
--- rejects a nonce that is still in that window. This is independent of packet
--- ordering and survives reconnects because nonces are random, not sequential.
---@param entry table Registered server handler entry with dedup state.
---@param onlineID number Online id of the sending player, or -1 when unknown.
---@param nonce any Nonce value from the envelope.
---@return boolean ok False when the nonce is missing, malformed or replayed.
---@return string|nil reason Failure description.
function Guard.checkDedup(entry, onlineID, nonce)
    if entry.dedup ~= true then
        return true
    end

    if type(nonce) ~= "number" or not isFinite(nonce) or nonce < 0
        or nonce ~= math.floor(nonce) then
        return false, "invalid dedup nonce"
    end

    if entry.nonceRings == nil then
        entry.nonceRings = {}
    end
    if entry.nonceIndexes == nil then
        entry.nonceIndexes = {}
    end

    local ring = entry.nonceRings[onlineID]
    if ring == nil then
        ring = {}
        entry.nonceRings[onlineID] = ring
        entry.nonceIndexes[onlineID] = 0
    end

    for i = 1, #ring do
        if ring[i] == nonce then
            local now = getTimestampMs()
            if now - lastReplayWarnMs >= WARN_INTERVAL_MS then
                lastReplayWarnMs = now
                logger:warn("replayed action", entry.action, "for player", tostring(onlineID))
            end
            return false, "replayed nonce"
        end
    end

    local index = (entry.nonceIndexes[onlineID] % DEDUP_WINDOW) + 1
    ring[index] = nonce
    entry.nonceIndexes[onlineID] = index
    return true
end

--- Returns true when a player with the given online id is still connected.
---@param players table Online player list returned by `getOnlinePlayers`.
---@param playerCount number Number of entries in `players`.
---@param onlineID number Online id to look for.
---@return boolean online True when a matching connected player exists.
local function isPlayerOnline(players, playerCount, onlineID)
    for i = 0, playerCount - 1 do
        local player = players:get(i)
        if player ~= nil then
            local ok, id = pcall(player.getOnlineID, player)
            if ok and id == onlineID then
                return true
            end
        end
    end
    return false
end

--- Removes entries for offline players from one state table and its companion.
---@param primary table State keyed by online id.
---@param companion table|nil Second state table keyed by the same ids.
---@param players table Online player list returned by `getOnlinePlayers`.
---@param playerCount number Number of entries in `players`.
local function cleanState(primary, companion, players, playerCount)
    local staleCount = 0
    for onlineID in pairs(primary) do
        if not isPlayerOnline(players, playerCount, onlineID) then
            staleCount = staleCount + 1
            scratch[staleCount] = onlineID
        end
    end

    for i = 1, staleCount do
        local onlineID = scratch[i]
        primary[onlineID] = nil
        if companion ~= nil then
            companion[onlineID] = nil
        end
        scratch[i] = nil
    end
end

--- Removes limiter, dedup and global bucket state for players who left.
---
--- The server has no reliable join/leave event, so this runs from
--- `EveryOneMinute` and compares stored online ids with `getOnlinePlayers()`.
--- Only ids are stored, so no player object can leak.
---@param handlers table Server handler entries keyed by action.
function Guard.cleanup(handlers)
    if not isServer() then
        return
    end

    local players = getOnlinePlayers()
    if players == nil then
        return
    end

    local playerCount = players:size()

    for _, entry in pairs(handlers) do
        if entry.tokens ~= nil then
            cleanState(entry.tokens, entry.refilledAt, players, playerCount)
        end
        if entry.nonceRings ~= nil then
            cleanState(entry.nonceRings, entry.nonceIndexes, players, playerCount)
        end
    end

    cleanState(globalTokens, globalRefilledAt, players, playerCount)
end

return Guard
