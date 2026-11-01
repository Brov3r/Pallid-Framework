require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/api/clip"
require "pallid/ui/api/url"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/toast"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local I = Pallid.UI._internal
local RECT_SHAPE = Pallid.UI.Shape.rect()
local ICON_OPTS = { mode = "fit" }

--- @param byte integer First byte of a UTF-8 sequence.
--- @return integer length Sequence length in bytes.
local function utf8Length(byte)
    if byte < 0x80 then
        return 1
    elseif byte < 0xE0 then
        return 2
    elseif byte < 0xF0 then
        return 3
    elseif byte < 0xF8 then
        return 4
    end
    return 1
end

--- Rich text parser, layout and syntax-highlighting helpers.
---
--- Markup: `**bold**`, `__underline__`, `~~strike~~`,
--- `{c=#RRGGBB}coloured{/c}`, `{icon=name}` and `[label](url)`. The tag form
--- `{b}...{/b}`, `{u}`, `{s}` is accepted as well. Italic is intentionally not
--- offered: the game has no oblique bitmap face and its SDF atlases are drawn
--- as plain bitmaps by `drawText`.
---
--- Highlighting is rule based: each language is an ordered array of
--- `{ pattern = "<Lua pattern>", color = <colour or fn>, bold = <bool or fn>, ... }`.
--- Rules are matched with a leading `^` at the current position, so new
--- languages and keywords are added by appending tables instead of editing the
--- tokenizer.
--- @class PallidRichTextModule
local Rich = {}
Pallid.UI.RichText = Rich

local KEYWORDS = {
    ["local"] = true, ["function"] = true, ["if"] = true, ["then"] = true,
    ["else"] = true, ["elseif"] = true, ["end"] = true, ["return"] = true,
    ["for"] = true, ["while"] = true, ["do"] = true, ["in"] = true,
    ["and"] = true, ["or"] = true, ["not"] = true,
    ["break"] = true, ["repeat"] = true, ["until"] = true,
    ["self"] = true, ["goto"] = true,
}

local CONSTANTS = {
    ["true"] = true,
    ["false"] = true,
    ["nil"] = true,
}

local BUILTINS = {
    ["assert"] = true, ["collectgarbage"] = true, ["dofile"] = true,
    ["error"] = true, ["getmetatable"] = true, ["ipairs"] = true,
    ["load"] = true, ["loadstring"] = true, ["next"] = true,
    ["pairs"] = true, ["pcall"] = true, ["print"] = true,
    ["rawequal"] = true, ["rawget"] = true, ["rawset"] = true,
    ["require"] = true, ["select"] = true, ["setmetatable"] = true,
    ["tonumber"] = true, ["tostring"] = true, ["type"] = true,
    ["unpack"] = true, ["xpcall"] = true,
    ["table"] = true, ["string"] = true, ["math"] = true,
    ["io"] = true, ["os"] = true, ["coroutine"] = true,
    ["debug"] = true, ["package"] = true, ["utf8"] = true,
}

Rich.Palette = {
    text     = Pallid.UI.Color.textPrimary,
    keyword  = Pallid.UI.Color.primary,
    builtin  = Pallid.UI.Color.info,
    constant = Pallid.UI.Color.warning,
    func     = Pallid.UI.Color.secondary,
    string   = Pallid.UI.Color.success,
    number   = Pallid.UI.Color.accent,
    comment  = Pallid.UI.Color.textDisabled,
    operator = Pallid.UI.Color.textMuted,
    field    = Pallid.UI.Color.sky,
}

-- Mutable style table used while parsing; runs copy the flags.
local function packStyle(bold, underline, strike, color)
    return {
        bold = bold or nil,
        underline = underline or nil,
        strike = strike or nil,
        color = color,
    }
end

--- @param runs table[] Styled text runs.
--- @param text string Text to process.
--- @param color PallidColor|nil Color to use.
--- @param style table|nil Text style overrides.
local function pushRun(runs, text, color, style)
    if text == nil or text == "" then
        return
    end
    local run = {
        text = text,
        color = color,
        bold = style and style.bold or nil,
        underline = style and style.underline or nil,
        strike = style and style.strike or nil,
    }
    local last = runs[#runs]
    if last ~= nil
        and last.newline == nil and last.icon == nil and last.link == nil
        and last.bold == run.bold
        and last.underline == run.underline
        and last.strike == run.strike
        and last.color == run.color then
        last.text = last.text .. run.text
    else
        runs[#runs + 1] = run
    end
end

--- Parses markup into runs. Newlines become `{ newline = true }` runs.
--- @param str string Markup string.
--- @param opts table|nil Parser options.
--- @field opts.color PallidColor|nil Default text colour.
--- @return table[] Parsed text runs.
function Rich.parse(str, opts)
    opts = opts or {}
    str = str or ""
    -- Normalise Windows/old-Mac line endings before tokenising.
    str = string.gsub(str, "\r\n", "\n")
    str = string.gsub(str, "\r", "\n")
    local defaultColor = opts.color or Pallid.UI.Color.text
    local runs = {}
    local bold, underline, strike = false, false, false
    local color = defaultColor
    local colorStack = {}
    local style = packStyle(bold, underline, strike, color)
    local buffer = {}

    local function flush()
        if #buffer > 0 then
            pushRun(runs, table.concat(buffer), color, style)
            buffer = {}
        end
    end

    local function updateStyle()
        style.bold = bold or nil
        style.underline = underline or nil
        style.strike = strike or nil
    end

    local i = 1
    while i <= #str do
        local two = string.sub(str, i, i + 1)
        if two == "**" then
            flush()
            bold = not bold
            updateStyle()
            i = i + 2
        elseif two == "__" then
            flush()
            underline = not underline
            updateStyle()
            i = i + 2
        elseif two == "~~" then
            flush()
            strike = not strike
            updateStyle()
            i = i + 2
        elseif string.sub(str, i, i + 2) == "{c=" then
            local close = string.find(str, "}", i + 3, true)
            if close == nil then
                buffer[#buffer + 1] = string.sub(str, i, i)
                i = i + 1
            else
                flush()
                -- Always push the current colour: an invalid hex tag must
                -- consume its matching {/c} instead of closing an outer scope.
                colorStack[#colorStack + 1] = color
                local parsed = Pallid.UI.Color.fromHex(string.sub(str, i + 3, close - 1))
                if parsed ~= nil then
                    color = parsed
                end
                i = close + 1
            end
        elseif string.sub(str, i, i + 3) == "{/c}" then
            flush()
            color = colorStack[#colorStack] or defaultColor
            colorStack[#colorStack] = nil
            i = i + 4
        elseif string.sub(str, i, i + 2) == "{b}" then
            flush(); bold = true; updateStyle(); i = i + 3
        elseif string.sub(str, i, i + 3) == "{/b}" then
            flush(); bold = false; updateStyle(); i = i + 4
        elseif string.sub(str, i, i + 2) == "{u}" then
            flush(); underline = true; updateStyle(); i = i + 3
        elseif string.sub(str, i, i + 3) == "{/u}" then
            flush(); underline = false; updateStyle(); i = i + 4
        elseif string.sub(str, i, i + 2) == "{s}" then
            flush(); strike = true; updateStyle(); i = i + 3
        elseif string.sub(str, i, i + 3) == "{/s}" then
            flush(); strike = false; updateStyle(); i = i + 4
        elseif string.sub(str, i, i + 5) == "{icon=" then
            local close = string.find(str, "}", i + 6, true)
            if close == nil then
                buffer[#buffer + 1] = string.sub(str, i, i)
                i = i + 1
            else
                flush()
                runs[#runs + 1] = { icon = string.sub(str, i + 6, close - 1) }
                i = close + 1
            end
        elseif string.sub(str, i, i) == "[" then
            local labelEnd = string.find(str, "](", i + 1, true)
            local urlEnd = labelEnd and string.find(str, ")", labelEnd + 2, true)
            if labelEnd ~= nil and urlEnd ~= nil then
                flush()
                runs[#runs + 1] = {
                    text = string.sub(str, i + 1, labelEnd - 1),
                    link = string.sub(str, labelEnd + 2, urlEnd - 1),
                    bold = bold or nil,
                    underline = underline or true,
                    strike = strike or nil,
                    color = color,
                }
                i = urlEnd + 1
            else
                buffer[#buffer + 1] = string.sub(str, i, i)
                i = i + 1
            end
        elseif string.sub(str, i, i) == "\n" then
            flush()
            runs[#runs + 1] = { newline = true }
            i = i + 1
        else
            buffer[#buffer + 1] = string.sub(str, i, i)
            i = i + 1
        end
    end
    flush()
    return runs
end

--- Lays runs out into positioned segments. Tokens wider than the line are
--- split at UTF-8 boundaries so display wrapping never overflows the width.
--- @param runs table[] Runs to lay out.
--- @param font UIFont|string Base font.
--- @param maxWidth number Maximum line width in pixels.
--- @param lineSpacing number|nil Extra spacing between lines in pixels.
--- @param iconSize number|nil Inline icon size in pixels.
--- @return table[] segments Layered text segments.
--- @return number width Measured width in pixels.
--- @return number height Measured height in pixels.
--- @return number lineHeight Line height in pixels.
function Rich.layout(runs, font, maxWidth, lineSpacing, iconSize)
    font = I.resolveFont(font)
    maxWidth = maxWidth or 0
    local segments = {}
    local manager = getTextManager()
    local lineH = manager:MeasureStringY(font, "Ag")
    local spacing = lineSpacing or 2
    local icon = iconSize or 16
    local x, y = 0, 0
    local lineW, maxW = 0, 0

    local function newline()
        y = y + lineH + spacing
        x = 0
        lineW = 0
    end

    local function breakLine()
        if lineW > maxW then
            maxW = lineW
        end
        newline()
    end

    local function pushSegment(text, width, run)
        if text == "" then
            return
        end
        segments[#segments + 1] = {
            text = text,
            x = x,
            y = y,
            w = width,
            bold = run.bold,
            underline = run.underline,
            strike = run.strike,
            color = run.color,
            link = run.link,
        }
        x = x + width
        lineW = x
    end

    --- Splits a token wider than the line at UTF-8 boundaries.
    --- @param word string Token to split.
    --- @param run table Run providing the style.
    local function pushLongWord(word, run)
        if maxWidth <= 0 then
            pushSegment(word, manager:MeasureStringX(font, word), run)
            return
        end
        local index = 1
        while index <= #word do
            local lastFit = index - 1
            local cursor = index
            while cursor <= #word do
                local length = utf8Length(string.byte(word, cursor))
                local nextIndex = cursor + length
                local candidate = string.sub(word, index, nextIndex - 1)
                if manager:MeasureStringX(font, candidate) > maxWidth then
                    break
                end
                lastFit = nextIndex - 1
                cursor = nextIndex
            end
            if lastFit < index then
                lastFit = index + utf8Length(string.byte(word, index)) - 1
            end
            local chunk = string.sub(word, index, lastFit)
            pushSegment(chunk, manager:MeasureStringX(font, chunk), run)
            index = lastFit + 1
            if index <= #word then
                breakLine()
            end
        end
    end

    for r = 1, #runs do
        local run = runs[r]
        if run.newline then
            breakLine()
        elseif run.icon ~= nil then
            local width = icon + 4
            if x > 0 and x + width > maxWidth then
                breakLine()
            end
            segments[#segments + 1] = {
                icon = run.icon,
                x = x,
                y = y,
                w = icon,
                color = run.color,
            }
            x = x + width
            lineW = x
        else
            local text = run.text or ""
            if string.find(text, "%S") == nil then
                -- Whitespace-only runs have no token for the gmatch below.
                if text ~= "" then
                    pushSegment(text, manager:MeasureStringX(font, text), run)
                end
            else
                for token in string.gmatch(text, "%s*%S+%s*") do
                    local word = token
                    local tokenWidth = manager:MeasureStringX(font, word)
                    if x > 0 and x + tokenWidth > maxWidth then
                        breakLine()
                        word = string.gsub(word, "^%s+", "")
                        tokenWidth = manager:MeasureStringX(font, word)
                    end
                    if tokenWidth > maxWidth and word ~= "" then
                        if x > 0 then
                            breakLine()
                        end
                        pushLongWord(word, run)
                    elseif word ~= "" then
                        pushSegment(word, tokenWidth, run)
                    end
                end
            end
        end
    end

    if lineW > maxW then
        maxW = lineW
    end
    local height = y + lineH
    return segments, maxW, height, lineH
end

-- Highlighting ---------------------------------------------------------------

local languageRules = {}
local languageCompiled = {}
local lastHighlight = {}

--- @param pattern string|nil Lua pattern.
--- @return boolean valid True when the pattern compiles.
local function validPattern(pattern)
    if type(pattern) ~= "string" or pattern == "" then
        return false
    end
    local ok = pcall(string.find, "", "^" .. pattern)
    return ok
end

--- Registers a syntax language. A rule is:
--- `{ pattern = <Lua pattern>, color = <colour or fn(text)>, bold/underline/strike = <bool or fn(text)> }`.
--- Rules are tried in order at each byte position; the first match wins.
--- @param name string Language name.
--- @param rules table[] Ordered rules.
--- @return boolean ok False for a bad name or a malformed pattern.
function Rich.registerLanguage(name, rules)
    if type(name) ~= "string" or name == "" or type(rules) ~= "table" then
        return false
    end
    for i = 1, #rules do
        if not validPattern(rules[i].pattern) then
            return false
        end
    end
    languageRules[name] = rules
    languageCompiled[name] = nil
    lastHighlight[name] = nil
    return true
end

--- Appends one rule to an existing language, or creates the language. User
--- rules are prepended so they can override a built-in token rule (a `TODO`
--- rule must win over the generic identifier rule); rules added later are
--- tried first.
--- @param name string Language name.
--- @param rule table Rule table; see `Rich.registerLanguage`.
--- @return boolean ok False for a bad name or a malformed pattern.
function Rich.addRule(name, rule)
    if type(name) ~= "string" or name == "" or type(rule) ~= "table" then
        return false
    end
    if not validPattern(rule.pattern) then
        return false
    end
    local rules = languageRules[name]
    if rules == nil then
        rules = {}
        languageRules[name] = rules
    end
    table.insert(rules, 1, rule)
    languageCompiled[name] = nil
    lastHighlight[name] = nil
    return true
end

local function identifierColor(word)
    if CONSTANTS[word] then
        return Rich.Palette.constant
    end
    if BUILTINS[word] then
        return Rich.Palette.builtin
    end
    if KEYWORDS[word] then
        return Rich.Palette.keyword
    end
    return Rich.Palette.text
end

local function identifierBold(word)
    return KEYWORDS[word] == true
end

--- @param word string Matched call token, including the trailing parenthesis.
--- @return PallidColor color Keyword/builtin/function tint for the call name.
local function callColor(word)
    local name = string.match(word, "^([%a_][%w_]*)") or word
    if CONSTANTS[name] then
        return Rich.Palette.constant
    elseif BUILTINS[name] then
        return Rich.Palette.builtin
    elseif KEYWORDS[name] then
        return Rich.Palette.keyword
    end
    return Rich.Palette.func
end

--- @param word string Matched call token.
--- @return boolean bold True for keyword calls.
local function callBold(word)
    local name = string.match(word, "^([%a_][%w_]*)")
    return name ~= nil and KEYWORDS[name] == true
end

local LUA_RULES = {
    { pattern = "%-%-%[%[.-%]%]", color = Rich.Palette.comment },
    { pattern = "%-%-[^\n]*", color = Rich.Palette.comment },
    { pattern = "%[%[.-%]%]", color = Rich.Palette.string },
    { pattern = '"[^"\n]*"', color = Rich.Palette.string },
    { pattern = "'[^'\n]*'", color = Rich.Palette.string },
    { pattern = "0[xX]%x+", color = Rich.Palette.number },
    { pattern = "%d+%.?%d*[eE][%+%-]?%d+", color = Rich.Palette.number },
    { pattern = "%d+%.?%d*", color = Rich.Palette.number },
    { pattern = "%.%d+", color = Rich.Palette.number },
    { pattern = "%.[%a_][%w_]*", color = Rich.Palette.field },
    { pattern = ":[%a_][%w_]*", color = Rich.Palette.field },
    { pattern = "[%a_][%w_]*[ \t]*%(", color = callColor, bold = callBold },
    { pattern = "[%a_][%w_]*", color = identifierColor, bold = identifierBold },
    { pattern = "[%+%-%*/%%=<>~#%^]+", color = Rich.Palette.operator },
    { pattern = "[%(%[{}%]%)%,;:%.]+", color = Rich.Palette.text },
    { pattern = "[ \t]+", color = Rich.Palette.text },
    { pattern = "\n", color = Rich.Palette.text },
    { pattern = ".", color = Rich.Palette.text },
}

local PLAIN_RULES = {
    { pattern = ".", color = Rich.Palette.text },
}

languageRules.lua = LUA_RULES
languageRules.plain = PLAIN_RULES

--- Returns a copy of a language's rules so callers cannot mutate the registry
--- without invalidating the compiled cache. Use `addRule`/`registerLanguage`.
--- @param name string Language name; defaults to "lua".
--- @return table[]|nil rules Copy of the rule list, or nil when unknown.
function Rich.getLanguage(name)
    local rules = languageRules[name or "lua"]
    if rules == nil then
        return nil
    end
    local copy = {}
    for i = 1, #rules do
        copy[i] = rules[i]
    end
    return copy
end

local function compile(name)
    local rules = languageRules[name] or PLAIN_RULES
    local patterns = {}
    for i = 1, #rules do
        patterns[i] = "^" .. (rules[i].pattern or ".")
    end
    return function(text)
        local runs = {}
        local pos = 1
        local length = #text
        while pos <= length do
            local matched = false
            for i = 1, #rules do
                local s, e = string.find(text, patterns[i], pos)
                if s ~= nil and e >= s then
                    local word = string.sub(text, s, e)
                    local rule = rules[i]
                    local color = rule.color
                    if type(color) == "function" then
                        color = color(word)
                    end
                    local bold = rule.bold
                    if type(bold) == "function" then
                        bold = bold(word)
                    end
                    local underline = rule.underline
                    if type(underline) == "function" then
                        underline = underline(word)
                    end
                    local strike = rule.strike
                    if type(strike) == "function" then
                        strike = strike(word)
                    end
                    pushRun(runs, word, color or Rich.Palette.text, {
                        bold = bold,
                        underline = underline,
                        strike = strike,
                    })
                    pos = e + 1
                    matched = true
                    break
                end
            end
            if not matched then
                pushRun(runs, string.sub(text, pos, pos), Rich.Palette.text, nil)
                pos = pos + 1
            end
        end
        return runs
    end
end

--- Returns highlighted runs for a language. The last result is cached, so an
--- editor that redraws every frame does not re-tokenise unchanged text.
--- @param text string Text to highlight.
--- @param language string|nil Defaults to "lua".
--- @return table[] Highlighted text runs.
function Rich.highlight(text, language)
    language = language or "lua"
    local cached = lastHighlight[language]
    if cached ~= nil and cached.text == text then
        return cached.runs
    end
    local compiled = languageCompiled[language]
    if compiled == nil then
        compiled = compile(language)
        languageCompiled[language] = compiled
    end
    local runs = compiled(text)
    lastHighlight[language] = { text = text, runs = runs }
    return runs
end

--- Backwards-compatible alias for the default Lua highlighter.
--- @param str string Lua source to highlight.
--- @return table[] Highlighted Lua runs.
function Rich.highlightLua(str)
    return Rich.highlight(str, "lua")
end

-- Rich text widget ----------------------------------------------------------

--- Display-only rich text. Use `inputRich` for editing.
--- @class PallidRichText : PallidWidget
--- @field text string Current text.
--- @field onLink fun(rich: PallidRichText, url: string)|nil
local RichText = Widgets.class("RichText")

--- Creates a new `RichText` instance.
--- @param text string Initial markup text.
--- @param x number X coordinate.
--- @param y number Y coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Rich text options.
--- @field opts.font UIFont|string|nil Font override.
--- @field opts.color PallidColor|nil Text color.
--- @field opts.linkColor PallidColor|nil Link color.
--- @field opts.linkHoverColor PallidColor|nil Hovered link color.
--- @field opts.lineSpacing number|nil Extra spacing between lines in pixels.
--- @field opts.iconSize number|nil Inline icon size in pixels.
--- @field opts.onLink fun(rich: PallidRichText, url: string)|nil
--- @return PallidRichText New rich text widget.
function RichText.new(text, x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, RichText)
    self:init(x, y, w, h)
    self.text = text or ""
    self.font = I.resolveFont(opts.font)
    self.color = opts.color or Pallid.UI.Color.text
    self.linkColor = opts.linkColor or Pallid.UI.Color.primary
    self.linkHoverColor = opts.linkHoverColor or Pallid.UI.Color.primaryStrong
    self.lineSpacing = opts.lineSpacing or 2
    self.iconSize = opts.iconSize or 16
    self.onLink = opts.onLink
    self._segments = {}
    self._lineHeight = 14
    self._contentHeight = 14
    self._hoverIndex = nil
    self._pressedIndex = nil
    self._cacheText = nil
    self._cacheW = nil
    self._cacheFont = nil
    self._cacheLineSpacing = nil
    self._cacheIconSize = nil
    self._cacheColor = nil
    -- Reused per-segment style: creating one table per word per frame is the
    -- main allocation cost of rich text.
    self._style = {
        font = self.font,
        color = self.color,
        alignH = "left",
        alignV = "top",
    }
    return self
end

--- Factory shortcut for `RichText.new`.
--- @param text string Text to process.
--- @param x number X coordinate.
--- @param y number Y coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional settings.
--- @return PallidRichText New rich text widget.
function Widgets.richText(text, x, y, w, h, opts)
    return RichText.new(text, x, y, w, h, opts)
end

--- Sets the text.
--- @param text string Text to process.
--- @return PallidRichText self The same instance, for chaining.
function RichText:setText(text)
    self.text = text or ""
    self._cacheText = nil
    self._hoverIndex = nil
    self._pressedIndex = nil
    return self
end

--- Returns the measured content size.
--- @return number width Measured width in pixels.
--- @return number height Measured height in pixels.
function RichText:measuredSize()
    self:_ensureLayout()
    return self._contentWidth or self.w, self._contentHeight
end

function RichText:_ensureLayout()
    if self._cacheText == self.text
        and self._cacheW == self.w
        and self._cacheFont == self.font
        and self._cacheLineSpacing == self.lineSpacing
        and self._cacheIconSize == self.iconSize
        and self._cacheColor == self.color then
        return
    end
    local runs = Rich.parse(self.text, { color = self.color })
    local segments, width, height, lineHeight = Rich.layout(
        runs, self.font, self.w, self.lineSpacing, self.iconSize
    )

    -- Coalesce adjacent plain runs with the same style. The parser emits one
    -- segment per word/token, which turns a wide paragraph into hundreds of
    -- text draw calls. Links stay separate because hover state is per link.
    local merged = 1
    for i = 1, #segments do
        local segment = segments[i]
        local previous = segments[merged - 1]
        if previous ~= nil
            and previous.icon == nil and segment.icon == nil
            and previous.link == nil and segment.link == nil
            and previous.bold == segment.bold
            and previous.underline == segment.underline
            and previous.strike == segment.strike
            and previous.color == segment.color
            and previous.y == segment.y
            and previous.x + previous.w == segment.x then
            previous.text = previous.text .. segment.text
            previous.w = previous.w + segment.w
        else
            segments[merged] = segment
            merged = merged + 1
        end
    end
    for i = merged, #segments do
        segments[i] = nil
    end

    -- Resolve inline icons once per layout instead of once per frame.
    for i = 1, #segments do
        local segment = segments[i]
        if segment.icon ~= nil then
            segment.iconRegion = Pallid.UI.Textures.getIconRegion(segment.icon)
            if segment.iconRegion == nil then
                if string.find(segment.icon, "/", 1, true) ~= nil then
                    segment.iconTexture = Pallid.UI.Textures.get(segment.icon)
                else
                    segment.iconTexture = Pallid.UI.Textures.getIcon(segment.icon)
                end
                if segment.iconTexture == nil then
                    segment.iconTexture = false
                end
            end
        end
    end

    self._segments = segments
    self._contentWidth = width
    self._contentHeight = height
    self._lineHeight = lineHeight
    self._cacheText = self.text
    self._cacheW = self.w
    self._cacheFont = self.font
    self._cacheLineSpacing = self.lineSpacing
    self._cacheIconSize = self.iconSize
    self._cacheColor = self.color
end

--- Returns the link index at the point.
--- @param px number Pointer X in local coordinates.
--- @param py number Pointer Y in local coordinates.
--- @return integer|nil Link index at the point, or nil.
function RichText:linkAt(px, py)
    self:_ensureLayout()
    local x, y = self:originX(), self:originY()
    for i = 1, #self._segments do
        local segment = self._segments[i]
        if segment.link ~= nil then
            local sy = y + segment.y
            if px >= x + segment.x and px < x + segment.x + segment.w
                and py >= sy and py < sy + self._lineHeight then
                return i
            end
        end
    end
    return nil
end

--- Updates hover state for the current pointer position.
--- @param px number Pointer X in local coordinates.
--- @param py number Pointer Y in local coordinates.
function RichText:onHoverMove(px, py)
    self._hoverIndex = self:linkAt(px, py)
end

--- Clears hover state when the pointer leaves.
function RichText:onHoverEnd()
    self._hoverIndex = nil
    Widgets.Widget.onHoverEnd(self)
end

--- Handles a pointer press inside the widget.
--- @param px number Pointer X in local coordinates.
--- @param py number Pointer Y in local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean True when the press was handled.
function RichText:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end
    self._pressedIndex = self:linkAt(px, py)
    return self._pressedIndex ~= nil
end

--- Handles a pointer release.
--- @param px number Pointer X in local coordinates.
--- @param py number Pointer Y in local coordinates.
function RichText:onUp(px, py)
    local index = self._pressedIndex
    self._pressedIndex = nil
    if index == nil or not self.enabled or not self:isInside(px, py) then
        return
    end
    local segment = self._segments[index]
    if segment == nil or segment.link == nil then
        return
    end
    if self.onLink ~= nil then
        self.onLink(self, segment.link)
    else
        local opened, how = Pallid.UI.openUrl(segment.link)
        if how == "clipboard" then
            local root = self:getRoot()
            if root ~= nil then
                local text = I.translate("UI_Pallid_LinkCopied", "Link copied to clipboard")
                Widgets.toast(text, {
                    corner = "bottom-right",
                    duration = 2.5,
                    accent = Pallid.UI.Color.warning,
                }):show(root)
            end
        end
    end
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element used for drawing.
function RichText:drawSelf(el)
    if self.w <= 0 or self.h <= 0 then
        return
    end
    self:_ensureLayout()
    local x, y = self:originX(), self:originY()

    -- Only pay for a stencil when the content can actually overflow.
    local needsClip = (self._contentHeight or 0) > self.h or (self._contentWidth or 0) > self.w
    local entered = false
    if needsClip then
        entered = Pallid.UI.clip(el, RECT_SHAPE, x, y, self.w, self.h)
    end

    -- Restrict drawing to the intersection of the widget and the active clip.
    -- Without this, a tall RichText inside a short viewport still issued a text
    -- draw call for every off-screen line.
    local topLimit, bottomLimit = 0, self.h
    local clipX, clipY, clipW, clipH = Pallid.UI.clipRect()
    if clipX ~= nil and clipY ~= nil then
        local clipTop = clipY - y
        local clipBottom = clipTop + clipH
        if clipTop > topLimit then
            topLimit = clipTop
        end
        if clipBottom < bottomLimit then
            bottomLimit = clipBottom
        end
    end
    if bottomLimit <= topLimit then
        if entered then
            Pallid.UI.clipEnd(el)
        end
        return
    end

    local style = self._style
    style.font = self.font
    style.alignH = "left"
    style.alignV = "top"
    local lineHeight = self._lineHeight
    local iconSize = self.iconSize
    local iconOffset = (lineHeight - iconSize) * 0.5

    for i = 1, #self._segments do
        local segment = self._segments[i]
        if segment.y + lineHeight > topLimit and segment.y < bottomLimit then
            if segment.icon ~= nil then
                local iconY = y + segment.y + iconOffset
                if segment.iconRegion ~= nil then
                    Pallid.UI.textureRegion(
                        el, segment.iconRegion,
                        x + segment.x, iconY, iconSize, iconSize,
                        segment.color, ICON_OPTS
                    )
                elseif segment.iconTexture then
                    Pallid.UI.texture(
                        el, segment.iconTexture,
                        x + segment.x, iconY, iconSize, iconSize,
                        segment.color, ICON_OPTS
                    )
                else
                    -- Preserve the one-time warning for unknown inline icons.
                    Pallid.UI.icon(el, segment.icon, x + segment.x, iconY, iconSize, segment.color)
                end
            else
                local isLink = segment.link ~= nil
                local isHover = isLink and i == self._hoverIndex
                if isLink then
                    style.color = isHover and self.linkHoverColor or self.linkColor
                    style.underline = isHover or segment.underline
                else
                    style.color = segment.color or self.color
                    style.underline = segment.underline
                end
                style.bold = segment.bold
                style.strike = segment.strike
                local cache = segment._textCache
                if cache == nil then
                    cache = {}
                    segment._textCache = cache
                end
                Pallid.UI.textPrepared(
                    el,
                    Pallid.UI.prepareText(segment.text, style, cache),
                    x + segment.x,
                    y + segment.y,
                    style
                )
            end
        end
    end
    if entered then
        Pallid.UI.clipEnd(el)
    end
end
