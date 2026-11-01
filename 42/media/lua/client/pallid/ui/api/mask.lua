Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

--- @class PallidMaskSlot One input slot compiled from a pattern.
--- @field token string Pattern character that declared the slot.
--- @field rule "digit"|"letter"|"upperLetter"|"alnum"|"upperAlnum" Accepted character class.
--- @field before string Literals printed immediately before this slot.

--- @class PallidMask Compiled input pattern.
--- @field pattern string Source pattern.
--- @field slots PallidMaskSlot[] Input slots in order.
--- @field slotCount integer Number of input slots.
--- @field tail string Literals after the last slot.

--- Input pattern compiler and formatter.
---
--- Tokens: `#`/`9` digit, `a` letter, `A` upper-case letter, `x` letter or
--- digit, `X` upper-case letter or digit. Any other character is a literal;
--- `\` escapes the next literal. Patterns are fixed-length and ASCII oriented.
--- @class PallidMaskModule Pattern compiler and formatter.
local Mask = {}
Pallid.UI.Mask = Mask

local CACHE = {}

local RULES = {
    ["#"] = "digit",
    ["9"] = "digit",
    ["a"] = "letter",
    ["A"] = "upperLetter",
    ["x"] = "alnum",
    ["X"] = "upperAlnum",
}

--- @param ch string Single byte.
--- @return boolean digit True for 0..9.
local function isDigit(ch)
    local byte = string.byte(ch)
    return byte ~= nil and byte >= 48 and byte <= 57
end

--- @param ch string Single byte.
--- @return boolean letter True for ASCII A..Z and a..z.
local function isLetter(ch)
    local byte = string.byte(ch)
    return byte ~= nil and ((byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122))
end

--- @param rule string Slot rule.
--- @param ch string Character to test.
--- @return boolean accepted True when the character fits the slot.
local function accepts(rule, ch)
    if rule == "digit" then
        return isDigit(ch)
    end
    if rule == "letter" or rule == "upperLetter" then
        return isLetter(ch)
    end
    return isDigit(ch) or isLetter(ch)
end

--- @param rule string Slot rule.
--- @param ch string Accepted character.
--- @return string value Character normalized for the slot.
local function normalize(rule, ch)
    if rule == "upperLetter" or rule == "upperAlnum" then
        return string.upper(ch)
    end
    return ch
end

--- Compiles a pattern. Results are cached because patterns are immutable.
--- @param pattern string|nil Pattern such as `##-##-###`.
--- @return PallidMask|nil compiled Nil for an empty pattern or one with no slots.
function Mask.compile(pattern)
    if type(pattern) ~= "string" or pattern == "" then
        return nil
    end
    local cached = CACHE[pattern]
    if cached ~= nil then
        return cached or nil
    end

    local slots = {}
    local pending = {}
    local index = 1
    while index <= #pattern do
        local ch = string.sub(pattern, index, index)
        if ch == "\\" then
            index = index + 1
            if index <= #pattern then
                pending[#pending + 1] = string.sub(pattern, index, index)
            end
        elseif RULES[ch] ~= nil then
            slots[#slots + 1] = {
                token  = ch,
                rule   = RULES[ch],
                before = table.concat(pending),
            }
            pending = {}
        else
            pending[#pending + 1] = ch
        end
        index = index + 1
    end

    local compiled = {
        pattern   = pattern,
        slots     = slots,
        slotCount = #slots,
        tail      = table.concat(pending),
    }
    CACHE[pattern] = (#slots > 0) and compiled or false
    if #slots == 0 then
        return nil
    end
    return compiled
end

--- @param mask PallidMask|string|nil Compiled mask or pattern.
--- @return PallidMask|nil compiled Compiled mask, or nil.
local function compiledOf(mask)
    if type(mask) == "string" then
        return Mask.compile(mask)
    end
    return mask
end

--- Collects characters that fit consecutive slots, ignoring literals and
--- invalid characters. Positions are 1-based byte indexes in the source text.
--- @param compiled PallidMask Compiled mask.
--- @param text string Source text.
--- @return string[] accepted Normalized slot characters.
--- @return integer[] positions Source positions of accepted characters.
local function collect(compiled, text)
    local accepted = {}
    local positions = {}
    local slot = 1
    local slotCount = compiled.slotCount
    for index = 1, #text do
        if slot > slotCount then
            break
        end
        local ch = string.sub(text, index, index)
        local rule = compiled.slots[slot].rule
        if accepts(rule, ch) then
            accepted[#accepted + 1] = normalize(rule, ch)
            positions[#positions + 1] = index
            slot = slot + 1
        end
    end
    return accepted, positions
end

--- Builds formatted text from accepted characters. Literals are inserted only
--- before a filled slot, so `12` stays `12` instead of growing a trailing `-`.
--- @param compiled PallidMask Compiled mask.
--- @param accepted string[] Accepted slot characters.
--- @param positions integer[] Source positions of accepted characters.
--- @param caret integer|nil Source caret as a 0-based character offset.
--- @return string formatted Formatted text.
--- @return string raw Concatenated slot characters.
--- @return integer caretOut Caret offset in the formatted text.
local function build(compiled, accepted, positions, caret)
    local chars = {}
    local isSlot = {}
    local raw = {}
    local filled = 0

    for slot = 1, compiled.slotCount do
        local value = accepted[slot]
        if value == nil then
            break
        end
        local before = compiled.slots[slot].before
        for i = 1, #before do
            chars[#chars + 1] = string.sub(before, i, i)
            isSlot[#chars] = false
        end
        chars[#chars + 1] = value
        isSlot[#chars] = true
        raw[#raw + 1] = value
        filled = slot
    end

    if filled == compiled.slotCount and compiled.tail ~= "" then
        local tail = compiled.tail
        for i = 1, #tail do
            chars[#chars + 1] = string.sub(tail, i, i)
            isSlot[#chars] = false
        end
    end

    local formatted = table.concat(chars)
    local rawText = table.concat(raw)
    local caretOut = #formatted
    if caret ~= nil then
        local beforeCaret = 0
        for i = 1, #positions do
            if positions[i] <= caret then
                beforeCaret = beforeCaret + 1
            else
                break
            end
        end

        local pos = 0
        local seen = 0
        while pos < #chars and seen < beforeCaret do
            pos = pos + 1
            if isSlot[pos] then
                seen = seen + 1
            end
        end
        -- The caret may not sit before a literal that starts the next slot.
        while pos < #chars and not isSlot[pos + 1] do
            pos = pos + 1
        end
        caretOut = pos
    end

    return formatted, rawText, caretOut
end

--- Formats arbitrary text through a mask.
--- @param mask PallidMask|string|nil Compiled mask or pattern.
--- @param text string|nil Source text.
--- @param caret integer|nil Caret offset in the source text, 0..length.
--- @return string formatted Formatted text.
--- @return string raw Slot characters without literals.
--- @return integer caretOut Caret offset in the formatted text.
function Mask.format(mask, text, caret)
    text = text or ""
    local compiled = compiledOf(mask)
    if compiled == nil then
        return text, text, caret or #text
    end
    local accepted, positions = collect(compiled, text)
    return build(compiled, accepted, positions, caret)
end

--- Extracts slot characters from formatted text.
--- @param mask PallidMask|string|nil Compiled mask or pattern.
--- @param text string|nil Formatted text.
--- @return string raw Slot characters without literals.
function Mask.raw(mask, text)
    text = text or ""
    local compiled = compiledOf(mask)
    if compiled == nil then
        return text
    end
    local accepted = collect(compiled, text)
    return table.concat(accepted)
end

--- Returns true when the text satisfies the mask.
--- @param mask PallidMask|string|nil Compiled mask or pattern.
--- @param text string|nil Formatted text.
--- @return boolean complete True when every slot is filled.
function Mask.isComplete(mask, text)
    local compiled = compiledOf(mask)
    if compiled == nil then
        return (text or "") ~= ""
    end
    local accepted = collect(compiled, text or "")
    return #accepted == compiled.slotCount
end
