require "utils/logger"

Pallid = Pallid or {}

--- Payload codec shared by the Pallid network layer.
---
--- The native Lua command transport silently drops `nil` values, values of
--- unsupported types and table keys that are not strings or numbers. Strings
--- longer than 32767 UTF-8 bytes overflow the native 16-bit length prefix and
--- arrive as an empty string. Cyclic tables recurse forever in the native
--- serializer. This module rejects all of those cases before a message leaves
--- the process, and applies the same rules to untrusted incoming payloads.
---
--- Validation is read-only: the payload table is not copied and not mutated.
--- The returned payload is the same table that was passed in.
---@class PallidNetCodec
local Codec = {}

--- Maximum nested table depth accepted in a payload.
local MAX_DEPTH = 8

--- Maximum UTF-8 size of a single string, matching the native 16-bit prefix.
local MAX_STRING_BYTES = 32767

--- Maximum estimated payload size in bytes. The native packet buffer is
--- 1000000 bytes, so this leaves a large safety margin for the envelope.
local MAX_PAYLOAD_BYTES = 262144

--- Maximum number of keys in a single payload table.
--- Kahlua's table iterator copies the key set before the loop, so this limit
--- is enforced after that copy. The native packet size and the network rate
--- limits bound the worst case; a pure Lua codec cannot avoid the copy.
local MAX_TABLE_KEYS = 256

--- Maximum number of visited keys and values in one payload.
local MAX_NODES = 4096

--- Pattern that matches any character above ASCII. Kahlua `#` counts UTF-16
--- code units, so byte counting is only needed when this pattern matches.
--- Built with `string.char` so the source does not depend on decimal escapes.
local NON_ASCII_PATTERN = "[^%z" .. string.char(1) .. "-" .. string.char(127) .. "]"

--- Tables currently on the recursion path; used for cycle detection.
--- Reused between calls because validation is synchronous and not reentrant.
local ancestors = {}

--- True when `ancestors` may still contain entries after an unexpected error.
--- A normal validation always unwinds its own entries, so the defensive clear
--- only runs after an exception and does not cost an iterator per message.
local ancestorsDirty = false

--- Running node count of the current validation.
local nodeCount = 0

--- Running estimated byte count of the current validation.
local byteCount = 0

--- Returns the UTF-8 byte length of a Kahlua string.
---
--- Kahlua stores strings as Java UTF-16 strings, so `#text` is the number of
--- code units, not bytes. ASCII strings are measured with one pattern match;
--- other strings are walked code unit by code unit. An unpaired surrogate is
--- counted as three bytes while the native encoder replaces it with one, so
--- the estimate is never lower than the real encoded size.
---@param text string String to measure.
---@return number bytes UTF-8 byte length estimate.
local function utf8ByteLength(text)
    if string.find(text, NON_ASCII_PATTERN) == nil then
        return #text
    end

    local total = 0
    local index = 1
    local length = #text

    while index <= length do
        local code = string.byte(text, index)
        if code < 128 then
            total = total + 1
        elseif code < 2048 then
            total = total + 2
        elseif code >= 55296 and code <= 56319 then
            local nextCode = 0
            if index < length then
                nextCode = string.byte(text, index + 1)
            end
            if nextCode >= 56320 and nextCode <= 57343 then
                total = total + 4
                index = index + 1
            else
                total = total + 3
            end
        else
            total = total + 3
        end
        index = index + 1
    end

    return total
end

--- Adds the estimated size of a string and enforces the per-string limit.
---@param text string String value or key.
---@return boolean ok False when the string or payload limit is exceeded.
---@return string|nil reason Failure description.
local function addString(text)
    local bytes = utf8ByteLength(text)
    if bytes > MAX_STRING_BYTES then
        return false, "string exceeds the " .. tostring(MAX_STRING_BYTES) .. "-byte limit"
    end

    byteCount = byteCount + bytes + 3
    if byteCount > MAX_PAYLOAD_BYTES then
        return false, "payload exceeds the " .. tostring(MAX_PAYLOAD_BYTES) .. "-byte limit"
    end

    return true
end

--- Adds the estimated size of a number and rejects non-finite values.
---@param number number Numeric value or key.
---@return boolean ok False when the value is NaN or infinite.
---@return string|nil reason Failure description.
local function addNumber(number)
    if number ~= number then
        return false, "NaN numbers are not supported"
    end

    if number == math.huge or number == -math.huge then
        return false, "infinite numbers are not supported"
    end

    byteCount = byteCount + 9
    if byteCount > MAX_PAYLOAD_BYTES then
        return false, "payload exceeds the " .. tostring(MAX_PAYLOAD_BYTES) .. "-byte limit"
    end

    return true
end

--- Validates one payload value and accumulates its estimated size.
---@param value any Value to validate.
---@param depth number Current nesting depth; the root value is depth 0.
---@return boolean ok False when the value cannot be transported.
---@return string|nil reason Failure description.
local function validateValue(value, depth)
    nodeCount = nodeCount + 1
    if nodeCount > MAX_NODES then
        return false, "payload exceeds the " .. tostring(MAX_NODES) .. "-node limit"
    end

    local valueType = type(value)

    if valueType == "string" then
        return addString(value)
    end

    if valueType == "number" then
        return addNumber(value)
    end

    if valueType == "boolean" then
        byteCount = byteCount + 2
        if byteCount > MAX_PAYLOAD_BYTES then
            return false, "payload exceeds the " .. tostring(MAX_PAYLOAD_BYTES) .. "-byte limit"
        end
        return true
    end

    if valueType ~= "table" then
        return false, "unsupported value type '" .. valueType .. "'"
    end

    if depth >= MAX_DEPTH then
        return false, "payload nesting exceeds the depth limit of " .. tostring(MAX_DEPTH)
    end

    if ancestors[value] then
        return false, "cyclic table reference"
    end

    ancestors[value] = true
    ancestorsDirty = true
    byteCount = byteCount + 5
    if byteCount > MAX_PAYLOAD_BYTES then
        ancestors[value] = nil
        return false, "payload exceeds the " .. tostring(MAX_PAYLOAD_BYTES) .. "-byte limit"
    end

    local keyCount = 0
    for key, child in pairs(value) do
        keyCount = keyCount + 1
        if keyCount > MAX_TABLE_KEYS then
            ancestors[value] = nil
            return false, "table exceeds the " .. tostring(MAX_TABLE_KEYS) .. "-key limit"
        end

        local keyType = type(key)
        if keyType == "string" then
            local ok, reason = addString(key)
            if not ok then
                ancestors[value] = nil
                return false, reason
            end
        elseif keyType == "number" then
            local ok, reason = addNumber(key)
            if not ok then
                ancestors[value] = nil
                return false, reason
            end
        else
            ancestors[value] = nil
            return false, "table keys must be strings or numbers, got '" .. keyType .. "'"
        end

        local ok, reason = validateValue(child, depth + 1)
        if not ok then
            ancestors[value] = nil
            return false, reason
        end
    end

    ancestors[value] = nil
    return true
end

--- Validates a payload against the native transport rules.
---
--- A `nil` payload is rejected: the native envelope would simply omit the
--- payload key, so the receiver could not tell it apart from a message that
--- never had a payload. Use an empty table when an action carries no data.
--- Scalars are valid payloads; use a schema when the payload must be a table.
---@param payload any Payload value sent by the caller.
---@return boolean ok False when the payload cannot be transported safely.
---@return string|nil reason Human-readable failure reason.
function Codec.validate(payload)
    if ancestorsDirty then
        for key in pairs(ancestors) do
            ancestors[key] = nil
        end
        ancestorsDirty = false
    end

    nodeCount = 0
    byteCount = 0

    if payload == nil then
        return false, "nil payload is not supported; send an empty table"
    end

    local ok, reason = validateValue(payload, 0)
    ancestorsDirty = false
    return ok, reason
end

--- Returns the UTF-8 byte length estimate of a string.
--- Exposed for tests and diagnostics only.
---@param text string String to measure.
---@return number bytes UTF-8 byte length estimate.
function Codec.byteLength(text)
    return utf8ByteLength(text)
end

--- Builds a string of a repeated chunk without relying on `string.rep`.
---@param chunk string Chunk to repeat.
---@param count number Repetition count.
---@return string text Concatenated result.
local function repeatText(chunk, count)
    local parts = {}
    for i = 1, count do
        parts[i] = chunk
    end
    return table.concat(parts)
end

--- Deep-copies a payload for the self-test round trip.
---@param value any Value to copy.
---@param seen table Table-to-copy map used for cycle detection.
---@return any copy Copied value.
local function clone(value, seen)
    if type(value) ~= "table" then
        return value
    end

    local existing = seen[value]
    if existing ~= nil then
        return existing
    end

    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[key] = clone(child, seen)
    end
    return copy
end

--- Runs the codec self-check. Intended for manual debugging only.
---
--- This is not called during load. Run it from the Lua console with
--- `Pallid.Net.selfTest()` after enabling debug mode.
---@return boolean ok True when every case produced the expected result.
---@return number passed Number of passed checks.
function Codec.selfTest()
    local passed = 0
    local failures = {}

    --- Records one self-test result.
    ---@param condition boolean Whether the check passed.
    ---@param message string Description used on failure.
    local function check(condition, message)
        if condition then
            passed = passed + 1
        else
            failures[#failures + 1] = message
        end
    end

    local sample = {
        id     = "apple",
        count  = 1,
        active = true,
        nested = {
            name  = "value",
            [2]   = 3.5,
        },
    }

    check(Codec.validate(sample), "valid nested payload must pass")
    check(Codec.validate(clone(sample, {})), "cloned payload must pass the round trip")

    check(not Codec.validate({ fn = function() end }), "function value must be rejected")
    check(not Codec.validate({ value = 0 / 0 }), "NaN must be rejected")
    check(not Codec.validate({ value = math.huge }), "positive infinity must be rejected")
    check(not Codec.validate({ value = -math.huge }), "negative infinity must be rejected")

    local tableKey = {}
    local tableKeyPayload = {}
    tableKeyPayload[tableKey] = 1
    check(not Codec.validate(tableKeyPayload), "table key must be rejected")

    local cycle = {}
    cycle.self = cycle
    check(not Codec.validate(cycle), "cyclic table must be rejected")

    local deep = {}
    local cursor = deep
    for i = 1, MAX_DEPTH + 1 do
        cursor.child = {}
        cursor = cursor.child
    end
    check(not Codec.validate(deep), "payload deeper than the limit must be rejected")

    local maxString = repeatText("a", MAX_STRING_BYTES)
    local longString = repeatText("a", MAX_STRING_BYTES + 1)
    check(Codec.validate({ value = maxString }), "string at the byte limit must pass")
    check(not Codec.validate({ value = longString }), "string above the byte limit must be rejected")

    local cyrillic = repeatText(string.char(1072), 16384)
    check(Codec.byteLength(cyrillic) == 32768, "non-ASCII byte length must count UTF-8 bytes")
    check(not Codec.validate({ value = cyrillic }), "non-ASCII string above the byte limit must be rejected")

    local manyKeys = {}
    for i = 1, MAX_TABLE_KEYS + 1 do
        manyKeys[i] = i
    end
    check(not Codec.validate(manyKeys), "table above the key limit must be rejected")

    local huge = repeatText("a", MAX_STRING_BYTES)
    local hugePayload = {}
    for i = 1, 9 do
        hugePayload[i] = huge
    end
    check(not Codec.validate(hugePayload), "payload above the byte limit must be rejected")

    check(Codec.validate(nil) == false, "nil payload must be rejected")

    for i = 1, #failures do
        Pallid.error("net codec self-test failed:", failures[i])
    end

    if #failures == 0 then
        Pallid.log("net codec self-test passed:", passed, "checks")
        return true, passed
    end

    return false, passed
end

return Codec
