require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/geometry"
require "pallid/ui/api/clip"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/animation/track"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/badge"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local CIRCLE_SHAPE = Pallid.UI.Shape.circle()
local RECT_SHAPE   = Pallid.UI.Shape.rect()
local FILL_OPTS    = { mode = "fill" }

local DISABLED_ALPHA   = 0.4
local BADGE_MARGIN     = 2
local BADGE_GAP        = 2
local STEAM_RETRY      = 2
local STEAM_MAX_TRY    = 10
local STEAM_MAX_DELAY  = 30

-- The engine exposes exact stencils only for rectangles and circles
-- (UIElement.setStencilRect/setStencilCircle). A rounded-rect clip is not
-- possible without a mask shader, so `shape` is either square or circle.
local PALETTE = {
    Pallid.UI.Color.primary,
    Pallid.UI.Color.primaryStrong,
    Pallid.UI.Color.secondary,
    Pallid.UI.Color.info,
    Pallid.UI.Color.success,
    Pallid.UI.Color.warning,
    Pallid.UI.Color.accent,
    Pallid.UI.Color.error,
}

-- One warning per bad source name; a list can rebuild avatars often.
local warnedSources = {}

--- Logs a source warning once per name.
--- @param source string Source name that failed to resolve.
local function warnSource(source)
    if warnedSources[source] == nil then
        warnedSources[source] = true
        Pallid.log("Avatar: source is not a texture, icon or SteamID: '" .. source .. "'")
    end
end

--- True for a Java Texture or a texture-like table.
--- @param value any Value to inspect.
--- @return boolean True when the value looks like a texture.
local function isTextureLike(value)
    if value == nil or value == false then
        return false
    end
    local kind = type(value)
    if kind ~= "table" and kind ~= "userdata" then
        return false
    end
    return value.getWidth ~= nil
end

--- Returns an independent copy of a color.
--- @param color PallidColor Color to copy.
--- @return PallidColor Copied color.
local function copyColor(color)
    return Pallid.UI.Color.new(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
end

--- First UTF-8 code point of a word. Used for initials so a Cyrillic name
--- does not lose half of its first byte.
--- @param word string Word to convert.
--- @return string First UTF-8 code point, or an empty string.
local function firstGlyph(word)
    local byte = string.byte(word, 1)
    if byte == nil then
        return ""
    end
    local length = 1
    if byte >= 0xF0 then
        length = 4
    elseif byte >= 0xE0 then
        length = 3
    elseif byte >= 0xC0 then
        length = 2
    end
    return string.sub(word, 1, length)
end

--- Builds uppercase initials from a display name.
--- @param name string|nil Display name, or nil.
--- @return string Initials, or "?" when the name is empty.
local function makeInitials(name)
    if name == nil or name == "" then
        return "?"
    end
    local first, second = string.match(name, "(%S+)%s+(%S+)")
    if first ~= nil then
        return string.upper(firstGlyph(first)) .. string.upper(firstGlyph(second))
    end
    local word = string.match(name, "%S+")
    if word == nil then
        return "?"
    end
    return string.upper(firstGlyph(word))
end

--- Computes a stable numeric hash from a string.
--- @param text string Text to hash.
--- @return integer Stable hash in 0..1000002.
local function hashName(text)
    local hash = 0
    for i = 1, #text do
        hash = (hash * 31 + string.byte(text, i)) % 1000003
    end
    return hash
end

--- Checks whether a value looks like a 17-digit Steam ID.
--- @param value string|nil Value to test.
--- @return boolean True when the value is a 17-digit Steam ID.
local function isSteamID(value)
    return type(value) == "string" and #value == 17 and string.match(value, "^%d+$") ~= nil
end

--- Normalizes a corner alias to a supported corner name.
--- @param side string|nil Corner name.
--- @return string side Normalized corner name.
local function normalizeSide(side)
    local value = string.lower(tostring(side or "top-right"))
    if value == "tl" or value == "left-top" then
        return "top-left"
    elseif value == "tr" or value == "right-top" then
        return "top-right"
    elseif value == "bl" or value == "left-bottom" then
        return "bottom-left"
    elseif value == "br" or value == "right-bottom" then
        return "bottom-right"
    elseif value == "top-left" or value == "top-right"
        or value == "bottom-left" or value == "bottom-right" then
        return value
    end
    return "top-right"
end

--- Normalizes a badge shape name, defaulting to "pill".
--- @param shape string|nil Shape name.
--- @return string shape "pill", "circle" or "dot".
local function normalizeShape(shape)
    if shape == "circle" or shape == "dot" then
        return shape
    end
    return "pill"
end

--- Square or circular avatar for players, NPCs and items.
---
--- Sources, in priority order: `item`, `source` (Texture, texture path, icon
--- name or SteamID), `steamID`, `username`. When no texture is available the
--- widget draws a deterministic colour with initials, so a list never shows a
--- hole. Steam avatars are retried with backoff until the client exposes them,
--- because the lookup returns nil while the game is still on the main menu.
---
--- Badges can be placed on any corner. `addBadge` appends independent badges;
--- `setBadge` manages the primary one. A side stacks its badges inward, and a
--- badge can be a pill, a circle with text or a dot.
--- @class PallidAvatar : PallidWidget
--- @field shape string Clip shape: "square" or "circle".
--- @field name string Display name.
--- @field initials string Initials shown when no texture is available.
--- @field texture Texture|nil Texture displayed in the avatar.
--- @field item InventoryItem|Item|nil Inventory item used for the icon.
--- @field statusColor PallidColor|nil Status dot color, or nil when hidden.
--- @field badge PallidBadge|nil Primary badge (legacy accessor).
--- @field badges table[] Badge entries `{ widget, side, shape, ... }`.
--- @field fallbackColor PallidColor Deterministic background when no picture exists.
--- @field entry PallidAnimTrack Fade-in track for the avatar.
--- @field statusPulse PallidAnimTrack|nil Pulse track for the status dot.
local Avatar = Widgets.class("Avatar")

--- Creates a new `Avatar` instance.
--- @param x number X coordinate.
--- @param y number Y coordinate.
--- @param size number Square side in pixels.
--- @param opts table|nil Avatar options.
--- @field opts.source Texture|string|nil Texture, texture path, icon name or SteamID.
--- @field opts.steamID string|nil Steam ID used to resolve the avatar.
--- @field opts.username string|nil Steam username used as a fallback.
--- @field opts.item InventoryItem|Item|nil Inventory item used for the icon.
--- @field opts.name string|nil Used for initials and the fallback colour.
--- @field opts.initials string|nil Overrides the derived initials.
--- @field opts.fallbackColor PallidColor|nil Fixed fallback colour.
--- @field opts.shape "square"|"circle"|nil Defaults to "square".
--- @field opts.status PallidColor|nil Status dot colour.
--- @field opts.statusBorder PallidColor|nil Ring around the dot. Defaults to the panel colour.
--- @field opts.badge table|string|nil Primary badge, an array of badge specs, or a descriptor.
--- @field opts.badges table|nil Array of badge specs for `addBadge`.
--- @field opts.border PallidColor|nil Frame colour. Defaults to panelBorder.
--- @field opts.animated boolean|nil Fade the picture in. Defaults to true.
--- @field opts.pulseStatus boolean|nil Slow pulse of the status dot. Defaults to false.
--- @field opts.steamRetry number|nil First Steam retry delay in seconds; defaults to 2.
--- @field opts.steamMaxAttempts number|nil Max lookup attempts; 0 disables the limit.
--- @return PallidAvatar New avatar instance.
function Avatar.new(x, y, size, opts)
    opts = opts or {}
    local self = setmetatable({}, Avatar)
    self:init(x, y, size, size)

    self.shape = opts.shape == "circle" and "circle" or "square"
    self.customInitials = opts.initials
    self.steamID = nil
    self.username = nil
    self.texture = nil
    self.iconName = nil
    self.item = nil
    self._steamSource = false
    self._steamTimer = 0
    self._steamAttempts = 0
    self.steamRetry = math.max(0.5, opts.steamRetry or STEAM_RETRY)
    self.steamMaxAttempts = math.max(0, opts.steamMaxAttempts or STEAM_MAX_TRY)
    self._steamDelay = self.steamRetry
    self._steamWarned = false
    self.fallbackOverride = opts.fallbackColor

    self.borderColor = opts.border or Pallid.UI.Color.panelBorder
    self.statusBorderColor = opts.statusBorder or Pallid.UI.Color.panel
    self.statusColor = opts.status or nil
    self.badge = nil
    self._primaryEntry = nil
    self.badges = {}
    self._borderTint = { r = 1, g = 1, b = 1, a = 1 }

    self.initialsStyle = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.white,
        alignH = "center",
        alignV = "middle",
        bold = true,
        ellipsis = "...",
    }

    self.animated = opts.animated ~= false
    self.hover = 0
    self.entry = Pallid.UI.Anim.new({
        duration = 0.26,
        easing = Pallid.UI.Anim.ease.outCubic,
        alpha = { 0, 1 },
    })
    if opts.pulseStatus then
        self:_createPulse()
    end
    if self.animated then
        self.entry:play()
    end

    self:setName(opts.name)
    self:_selectFont()

    if opts.item ~= nil then
        self:setItem(opts.item)
    elseif opts.source ~= nil then
        self:setSource(opts.source)
    elseif opts.steamID ~= nil then
        self:setSteamID(opts.steamID)
    elseif opts.username ~= nil then
        self:setUsername(opts.username)
    end

    self:_addBadgeSpecs(opts)
    return self
end

--- Factory shortcut for `Avatar.new`.
--- @param x number X coordinate.
--- @param y number Y coordinate.
--- @param size number Size in pixels.
--- @param opts table|nil Optional settings.
--- @return PallidAvatar New avatar instance.
function Widgets.avatar(x, y, size, opts)
    return Avatar.new(x, y, size, opts)
end

--- Creates the optional status-dot pulse track.
function Avatar:_createPulse()
    self.statusPulse = Pallid.UI.Anim.new({
        duration = 1.6,
        easing = Pallid.UI.Anim.ease.inOutSine,
        loop = true,
        pingPong = true,
        alpha = { 1, 0.45 },
    })
    self.statusPulse:play()
end

--- Adds badges from `opts.badge` / `opts.badges`.
--- @param opts table Badge option table.
function Avatar:_addBadgeSpecs(opts)
    local list = opts.badges
    if type(list) == "table" then
        if list[1] ~= nil then
            for i = 1, #list do
                local spec = list[i]
                if type(spec) == "table" then
                    self:addBadge(spec.text, spec)
                else
                    self:addBadge(spec)
                end
            end
            return
        end
        self:setBadge(list.text, list)
        return
    end

    local badge = opts.badge
    if type(badge) == "table" then
        if badge[1] ~= nil then
            for i = 1, #badge do
                local spec = badge[i]
                if type(spec) == "table" then
                    self:addBadge(spec.text, spec)
                else
                    self:addBadge(spec)
                end
            end
        else
            self:setBadge(badge.text, badge)
        end
    elseif badge ~= nil then
        self:setBadge(badge)
    end
end

--- Restarts the picture fade. Called when the source changes, including when a
--- Steam avatar finally arrives.
function Avatar:_playEntry()
    if self.animated and self.entry ~= nil then
        self.entry:play()
    end
end

--- Replays the picture fade, for example after a list row is reused.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:playIntro()
    self:_playEntry()
    return self
end

--- Recomputes initials and the deterministic fallback colour.
function Avatar:_refreshFallback()
    local key = self.name ~= "" and self.name or self.initials
    local color = self.fallbackOverride or PALETTE[(hashName(key) % #PALETTE) + 1]
    self.fallbackColor = color
    self.initialsStyle.color = Pallid.UI.Color.contrastText(color)
end

--- Sets the display name.
--- @param name string|nil Display name, or nil to clear.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:setName(name)
    self.name = name or ""
    if self.customInitials == nil then
        self.initials = makeInitials(self.name)
    else
        self.initials = self.customInitials
    end
    self:_refreshFallback()
    return self
end

--- Overrides initials. `nil` or an empty string restores the derived initials.
--- @param initials string|nil Initials text, or nil to derive them.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:setInitials(initials)
    if initials == nil or initials == "" then
        self.customInitials = nil
        self.initials = makeInitials(self.name)
    else
        self.customInitials = initials
        self.initials = initials
    end
    self:_refreshFallback()
    return self
end

--- Fixes the fallback colour instead of deriving it from the name.
--- @param color PallidColor|nil Nil restores the hash-derived colour.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:setFallbackColor(color)
    self.fallbackOverride = color
    self:_refreshFallback()
    return self
end

--- Sets the clip shape.
--- @param shape "square"|"circle" Clip shape.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:setShape(shape)
    self.shape = shape == "circle" and "circle" or "square"
    self:_layoutBadges()
    return self
end

--- Clears every source field without touching the fade.
function Avatar:_clearSource()
    self.item = nil
    self.texture = nil
    self.sourceRegion = nil
    self.iconName = nil
    self.steamID = nil
    self.username = nil
    self._steamSource = false
end

--- Resets the Steam lookup backoff state.
function Avatar:_resetSteamRetry()
    self._steamTimer = 0
    self._steamAttempts = 0
    self._steamDelay = self.steamRetry
    self._steamWarned = false
end

--- Clears every other source and assigns a Texture, path, icon name or SteamID.
--- An unknown icon or unsupported value falls back to initials.
--- @param source Texture|string|nil Texture, path, icon name, or Steam ID.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:setSource(source)
    self:_clearSource()
    self:_resetSteamRetry()

    if type(source) == "string" then
        if source == "" then
            -- No source; keep the fallback.
        elseif string.find(source, "/", 1, true) ~= nil then
            self.sourceRegion = Pallid.UI.Textures.getRegion(source)
            self.texture = self.sourceRegion == nil and Pallid.UI.Textures.get(source) or nil
        elseif isSteamID(source) then
            self.steamID = source
            self._steamSource = true
        elseif Pallid.UI.Textures.hasIcon(source) then
            self.iconName = source
        else
            warnSource(source)
        end
    elseif isTextureLike(source) then
        self.texture = source
    elseif source ~= nil and source ~= false then
        Pallid.log("Avatar:setSource ignores unsupported value of type " .. type(source))
    end

    self:_playEntry()
    if self._steamSource then
        self:_resolveSteam()
    end
    return self
end

--- Sets the texture.
--- @param texture Texture|nil Texture to display, or nil to clear.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:setTexture(texture)
    self:_clearSource()
    self:_resetSteamRetry()
    if isTextureLike(texture) then
        self.texture = texture
    elseif texture ~= nil then
        Pallid.log("Avatar:setTexture expects a Texture, got " .. type(texture))
    end
    self:_playEntry()
    return self
end

--- Sets the icon.
--- @param name string Registered icon name.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:setIcon(name)
    self:_clearSource()
    self:_resetSteamRetry()
    if type(name) == "string" and name ~= "" then
        if Pallid.UI.Textures.hasIcon(name) then
            self.iconName = name
        else
            warnSource(name)
        end
    end
    self:_playEntry()
    return self
end

--- Uses the game's inventory/script item icon. Pass nil to remove it.
--- @param item InventoryItem|Item|nil Inventory item, or nil to clear.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:setItem(item)
    self:_clearSource()
    self:_resetSteamRetry()
    self.item = item
    self:_playEntry()
    return self
end

--- Shared Steam source switch used by `setSteamID` and `setUsername`.
--- @param value string|nil Steam ID or username, or nil to clear.
--- @param byID boolean True for a SteamID, false for a username.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:_setSteamSource(value, byID)
    self:_clearSource()
    self:_resetSteamRetry()
    if byID then
        self.steamID = value
    else
        self.username = value
    end
    self._steamSource = value ~= nil and value ~= ""
    self:_playEntry()
    self:_resolveSteam()
    return self
end

--- Sets the Steam ID.
--- @param steamID string|nil Steam ID string, or nil to clear.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:setSteamID(steamID)
    return self:_setSteamSource(steamID, true)
end

--- Sets the Steam username.
--- @param username string|nil Steam username, or nil to clear.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:setUsername(username)
    return self:_setSteamSource(username, false)
end

--- Sets the status dot color.
--- @param color PallidColor|nil Status dot color, or nil to clear.
--- @param borderColor PallidColor|nil Status border color, or nil to keep.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:setStatus(color, borderColor)
    self.statusColor = color or nil
    if borderColor ~= nil and borderColor ~= false then
        self.statusBorderColor = borderColor
    end
    return self
end

--- Sets the border color.
--- @param color PallidColor Border color.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:setBorder(color)
    self.borderColor = color or Pallid.UI.Color.panelBorder
    return self
end

--- Sets the status border color.
--- @param color PallidColor Status border color.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:setStatusBorder(color)
    if color ~= nil and color ~= false then
        self.statusBorderColor = color
    end
    return self
end

--- Enables or disables the animation.
--- @param animated boolean True enables the fade-in animation.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:setAnimated(animated)
    self.animated = animated and true or false
    if self.animated then
        self:_playEntry()
    else
        for i = 1, #self.badges do
            self.badges[i].widget.visible = true
        end
    end
    return self
end

--- Enables or disables the status pulse.
--- @param enabled boolean True enables the status pulse.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:setPulse(enabled)
    if enabled then
        if self.statusPulse == nil then
            self:_createPulse()
        else
            self.statusPulse:play()
        end
    else
        self.statusPulse = nil
    end
    return self
end

-- Badges ---------------------------------------------------------------------

--- Resolves the local rectangle the avatar picture actually occupies. A
--- circular avatar is a centred square inside possibly non-square bounds.
--- @return number x X coordinate.
--- @return number y Y coordinate.
--- @return number w Width in pixels.
--- @return number h Height in pixels.
function Avatar:_avatarBox()
    if self.shape == "circle" then
        local size = math.min(self.w, self.h)
        return (self.w - size) * 0.5, (self.h - size) * 0.5, size, size
    end
    return 0, 0, self.w, self.h
end

--- Resolves badge dimensions and shape from the avatar box.
--- @param opts table Badge option table.
--- @return table opts Badge constructor options.
function Avatar:_badgeOptions(opts)
    local _, _, aw, ah = self:_avatarBox()
    local box = math.min(aw, ah)
    local shape = normalizeShape(opts.shape)
    local maxHeight = math.max(8, math.min(18, box))
    local height = opts.height
        or math.max(8, math.min(maxHeight, math.max(12, math.floor(box * 0.5))))
    local result = {
        text      = opts.text,
        color     = opts.color,
        textColor = opts.textColor,
        border    = opts.border,
        font      = opts.font,
    }

    if shape == "dot" then
        result.dot = true
        result.size = opts.size or math.min(14, math.max(6, math.floor(box * 0.18)))
        result.height = opts.height
    elseif shape == "circle" then
        local size = opts.size or height
        result.width = size
        result.height = size
        result.padding = opts.padding or 2
    else
        result.width = opts.width
        result.height = height
        result.padding = opts.padding or math.max(2, math.min(6, math.floor(height * 0.25)))
    end
    return result
end

--- Adds an independent badge.
---
--- Supported options: `side`/`corner` (`top-right` default, `top-left`,
--- `bottom-left`, `bottom-right`, aliases `tr/tl/br/bl`), `shape`
--- (`pill`/`circle`/`dot`), `color`, `textColor`, `border`, `size` (circle and
--- dot), `width`/`height` (pill), `padding`, `margin`, `gap`, `x`, `y` (manual
--- offset inside the avatar box).
--- `bottom-right` badges are drawn above the status dot; pick another corner
--- if both are needed.
--- @param text string|number|nil Badge text, or nil for a dot.
--- @param opts table|nil Badge options.
--- @return PallidBadge badge New badge widget.
function Avatar:addBadge(text, opts)
    opts = opts or {}
    if text ~= nil then
        text = tostring(text)
    end
    local spec = {}
    for key, value in pairs(opts) do
        spec[key] = value
    end
    spec.text = text ~= nil and text or opts.text
    if spec.text ~= nil then
        spec.text = tostring(spec.text)
    end
    local shape = normalizeShape(opts.shape)
    local badge = Widgets.badge(0, 0, self:_badgeOptions(spec))
    badge.hittable = false
    badge:setEnabled(self.enabled)
    self:add(badge)

    local customTextColor = opts.textColor
    if customTextColor == false then
        customTextColor = nil
    end
    local entry = {
        widget = badge,
        side   = normalizeSide(opts.side or opts.corner),
        shape  = shape,
        margin = opts.margin,
        gap    = opts.gap,
        x      = opts.x,
        y      = opts.y,
        primary = opts.primary == true,
        customTextColor = customTextColor,
    }
    self.badges[#self.badges + 1] = entry
    if entry.primary and self._primaryEntry == nil then
        self._primaryEntry = entry
        self.badge = badge
    end
    self:_layoutBadges()
    return badge
end

--- Adds or updates the primary badge. `nil`/empty removes only the primary;
--- badges added with `addBadge` stay in place.
--- @param text string|nil Badge text, or nil to clear.
--- @param opts table|nil Badge options.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:setBadge(text, opts)
    opts = opts or {}
    if text ~= nil then
        text = tostring(text)
    end
    if text == nil or text == "" then
        if self._primaryEntry ~= nil then
            self:removeBadge(self._primaryEntry.widget)
        end
        return self
    end

    local entry = self._primaryEntry
    if entry == nil then
        local badge = self:addBadge(text, opts)
        entry = self.badges[#self.badges]
        entry.primary = true
        entry.customTextColor = (opts.textColor ~= false) and opts.textColor or nil
        self._primaryEntry = entry
        self.badge = badge
        self:_layoutBadges()
        return self
    end

    if opts.shape ~= nil and normalizeShape(opts.shape) ~= entry.shape then
        self:removeBadge(entry.widget)
        return self:setBadge(text, opts)
    end

    entry.widget:setText(text)
    if opts.color ~= nil and opts.color ~= false then
        entry.widget:setColor(opts.color)
        if entry.customTextColor ~= nil then
            entry.widget.textColor = copyColor(entry.customTextColor)
            entry.widget.style.color = entry.widget.textColor
        end
    end
    if opts.textColor ~= nil then
        if opts.textColor == false then
            entry.customTextColor = nil
            entry.widget.textColor = Pallid.UI.Color.contrastText(entry.widget.color)
            entry.widget.style.color = entry.widget.textColor
        else
            entry.customTextColor = opts.textColor
            entry.widget.textColor = copyColor(opts.textColor)
            entry.widget.style.color = entry.widget.textColor
        end
    end
    if opts.side ~= nil or opts.corner ~= nil then
        entry.side = normalizeSide(opts.side or opts.corner)
    end
    if opts.size ~= nil and (entry.shape == "circle" or entry.shape == "dot") then
        entry.widget.w = opts.size
        entry.widget.h = opts.size
        entry.widget.autoWidth = false
        entry.widget.autoHeight = false
    end
    if opts.width ~= nil then
        entry.widget.w = opts.width
        entry.widget.autoWidth = false
    end
    if opts.height ~= nil then
        entry.widget.h = opts.height
        entry.widget.autoHeight = false
    end
    if opts.margin ~= nil then entry.margin = opts.margin end
    if opts.gap ~= nil then entry.gap = opts.gap end
    if opts.x ~= nil then entry.x = opts.x end
    if opts.y ~= nil then entry.y = opts.y end
    self:_layoutBadges()
    return self
end

--- Removes a badge.
--- @param badgeOrIndex PallidBadge|integer Badge instance or its index.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:removeBadge(badgeOrIndex)
    local index
    if type(badgeOrIndex) == "number" then
        index = math.floor(badgeOrIndex)
    else
        for i = 1, #self.badges do
            if self.badges[i] == badgeOrIndex or self.badges[i].widget == badgeOrIndex then
                index = i
                break
            end
        end
    end
    if index == nil or index < 1 or index > #self.badges then
        return self
    end

    local entry = table.remove(self.badges, index)
    self:remove(entry.widget)
    if self._primaryEntry == entry then
        self._primaryEntry = nil
        self.badge = nil
    end
    self:_layoutBadges()
    return self
end

--- Removes every badge.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:clearBadges()
    for i = #self.badges, 1, -1 do
        self:remove(self.badges[i].widget)
        self.badges[i] = nil
    end
    self.badge = nil
    self._primaryEntry = nil
    return self
end

--- Returns the badge list.
--- @return PallidBadge[] badges Current badge widgets in creation order.
function Avatar:getBadges()
    local result = {}
    for i = 1, #self.badges do
        result[i] = self.badges[i].widget
    end
    return result
end

--- Places badges on their corners. Badges on the same side stack inward; the
--- avatar box is the square used by a circular avatar.
function Avatar:_layoutBadges()
    if #self.badges == 0 then
        return
    end
    local ax, ay, aw, ah = self:_avatarBox()
    local offsets = {}
    for i = 1, #self.badges do
        local entry = self.badges[i]
        local widget = entry.widget
        local bw, bh = widget.w, widget.h
        local bx, by
        if entry.x ~= nil or entry.y ~= nil then
            bx = ax + (entry.x or 0)
            by = ay + (entry.y or 0)
        else
            local side = entry.side
            local margin = entry.margin or BADGE_MARGIN
            local gap = entry.gap or BADGE_GAP
            local left = string.find(side, "left", 1, true) ~= nil
            local bottom = string.find(side, "bottom", 1, true) ~= nil
            local offset = offsets[side] or 0
            if left then
                bx = ax + margin
            else
                bx = ax + aw - bw - margin
            end
            if bottom then
                by = ay + ah - margin - bh - offset
            else
                by = ay + margin + offset
            end
            if bx < ax then
                bx = ax
            end
            offsets[side] = offset + bh + gap
        end
        widget:setBounds(bx, by, bw, bh)
    end
end

--- Updates the widget size.
--- @param size number Avatar size in pixels.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:setSize(size)
    self:setBounds(self.x, self.y, size, size)
    return self
end

--- Updates the widget bounds.
--- @param x number X coordinate.
--- @param y number Y coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:_selectFont()
    self:_layoutBadges()
    return self
end

--- Enables or disables the widget.
--- @param enabled boolean Whether the feature is enabled.
--- @return PallidAvatar self The same instance, for chaining.
function Avatar:setEnabled(enabled)
    Widgets.Widget.setEnabled(self, enabled)
    for i = 1, #self.badges do
        self.badges[i].widget:setEnabled(enabled)
    end
    return self
end

--- Selects the initials font from the avatar size.
function Avatar:_selectFont()
    local size = math.min(self.w, self.h)
    if size >= 96 then
        self.initialsStyle.font = Pallid.UI.Fonts.large
    elseif size >= 44 then
        self.initialsStyle.font = Pallid.UI.Fonts.medium
    else
        self.initialsStyle.font = Pallid.UI.Fonts.small
    end
end

--- Resolves a Steam avatar once. Returns true when a texture was assigned.
--- @return boolean resolved True when a texture was resolved.
function Avatar:_resolveSteam()
    if not self._steamSource or self.texture ~= nil then
        return false
    end

    local texture = nil
    local ok = true
    if self.steamID ~= nil and getSteamAvatarFromSteamID ~= nil then
        ok, texture = pcall(getSteamAvatarFromSteamID, self.steamID)
    elseif self.username ~= nil and getSteamAvatarFromUsername ~= nil then
        ok, texture = pcall(getSteamAvatarFromUsername, self.username)
    end

    if not ok then
        if not self._steamWarned then
            self._steamWarned = true
            Pallid.log("Avatar: Steam avatar lookup failed for " .. tostring(self.steamID or self.username))
        end
        texture = nil
    end

    if isTextureLike(texture) then
        self.texture = texture
        self._steamSource = false
        return true
    end

    self._steamAttempts = self._steamAttempts + 1
    if self.steamMaxAttempts > 0 and self._steamAttempts >= self.steamMaxAttempts then
        self._steamSource = false
    else
        self._steamDelay = math.min(
            STEAM_MAX_DELAY,
            self.steamRetry * 2 ^ (self._steamAttempts - 1)
        )
    end
    return false
end

--- Eases hover and advances the entrance and status-pulse tracks. Per-frame so
--- the avatar animates smoothly.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function Avatar:onAnimate(now, dt)
    self.hover = Widgets.approach(self.hover, self._hover and 1 or 0, 16, dt)
    if self.animated and self.entry:isPlaying() then
        self.entry:update(now)
    end
    if self.statusPulse ~= nil then
        self.statusPulse:update(now)
    end
end

--- Retries the Steam avatar download on the game tick with exponential backoff.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous tick, 0..0.1.
function Avatar:onUpdate(now, dt)
    if not self._steamSource or self.texture ~= nil then
        return
    end
    self._steamTimer = self._steamTimer + dt
    if self._steamTimer < self._steamDelay then
        return
    end
    self._steamTimer = 0
    if self:_resolveSteam() then
        self:_playEntry()
    end
end

--- Draws the fallback fill and initials inside the current clip.
--- @param el ISUIElement Host element used for drawing.
--- @param x number Absolute box left.
--- @param y number Absolute box top.
--- @param w number Box width.
--- @param h number Box height.
--- @param px number Scaled picture left.
--- @param py number Scaled picture top.
--- @param pw number Scaled picture width.
--- @param ph number Scaled picture height.
--- @param alpha number Alpha multiplier.
function Avatar:_drawFallback(el, x, y, w, h, px, py, pw, ph, alpha)
    if self.shape == "circle" then
        Pallid.UI.circle(
            el,
            px + pw * 0.5,
            py + ph * 0.5,
            math.min(pw, ph) * 0.5,
            Pallid.UI.Anim.alpha(self:shade(self.fallbackColor), alpha)
        )
    else
        Pallid.UI.rect(el, px, py, pw, ph, Pallid.UI.Anim.alpha(self:shade(self.fallbackColor), alpha))
    end

    local base = self.initialsStyle.color
    self.initialsStyle.color = Pallid.UI.Anim.alpha(self:shade(base), alpha)
    self.initialsStyle.maxWidth = math.max(0, math.min(w, h) - 4)
    Pallid.UI.text(el, self.initials, x + w * 0.5, y + h * 0.5, self.initialsStyle)
    self.initialsStyle.color = base
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element used for drawing.
function Avatar:drawSelf(el)
    local ox, oy = self:originX(), self:originY()
    local w, h = self.w, self.h
    if w <= 0 or h <= 0 then
        return
    end

    local bx, by, bw, bh = self:_avatarBox()
    bx, by = ox + bx, oy + by

    local alpha = self.animated and self.entry.alpha or 1
    local contentAlpha = alpha * (self.enabled and 1 or DISABLED_ALPHA)
    local scale = 1 + self.hover * 0.035
    local px, py, pw, ph = Pallid.UI.Anim.scaleRect(bx, by, bw, bh, scale)

    -- Clip to the original avatar box, not the zoomed picture: hover must not
    -- paint over neighbours in a non-clipping parent and must not cut the
    -- picture in a clipping one.
    local clipped = false
    if self.shape == "circle" then
        clipped = Pallid.UI.clip(el, CIRCLE_SHAPE, bx, by, bw, bh)
    elseif self.hover > 0.001 then
        clipped = Pallid.UI.clip(el, RECT_SHAPE, bx, by, bw, bh)
    end

    local drawn = false
    if self.item ~= nil then
        drawn = Pallid.UI.itemIcon(el, self.item, px, py, pw, ph, contentAlpha)
    end
    if not drawn and self.sourceRegion ~= nil then
        drawn = Pallid.UI.textureRegion(
            el,
            self.sourceRegion,
            px, py, pw, ph,
            Pallid.UI.Anim.alpha(Pallid.UI.Color.white, contentAlpha),
            FILL_OPTS
        )
    end
    if not drawn and isTextureLike(self.texture) then
        drawn = Pallid.UI.texture(
            el,
            self.texture,
            px, py, pw, ph,
            Pallid.UI.Anim.alpha(Pallid.UI.Color.white, contentAlpha),
            FILL_OPTS
        )
    end
    if not drawn and self.iconName ~= nil then
        local size = math.min(pw, ph)
        drawn = Pallid.UI.icon(
            el,
            self.iconName,
            px + (pw - size) * 0.5,
            py + (ph - size) * 0.5,
            size,
            Pallid.UI.Anim.alpha(Pallid.UI.Color.white, contentAlpha)
        )
    end
    if not drawn then
        self:_drawFallback(el, bx, by, bw, bh, px, py, pw, ph, alpha)
    end

    if clipped then
        Pallid.UI.clipEnd(el)
    end

    -- Hover brightens the frame instead of moving the widget. The picture may
    -- zoom inside the clip, but the frame itself stays on the avatar box.
    Pallid.UI.Anim.lerpColor(self._borderTint, self.borderColor, Pallid.UI.Color.focusRing, self.hover * 0.45)
    self._borderTint.a = self._borderTint.a * contentAlpha
    if self.shape == "circle" then
        Pallid.UI.ring(el, bx + bw * 0.5, by + bh * 0.5, math.min(bw, bh) * 0.5 - 0.5, 1, self._borderTint)
    else
        Pallid.UI.border(el, bx, by, bw, bh, 1, self._borderTint)
    end

    if self.statusColor ~= nil and math.min(bw, bh) >= 9 then
        local radius = math.max(2, math.min(8, math.min(bw, bh) * 0.12))
        local inset = 2
        local cx = bx + bw - radius - inset
        local cy = by + bh - radius - inset
        local pulse = self.statusPulse ~= nil and self.statusPulse.alpha or 1
        Pallid.UI.circle(el, cx, cy, radius + 1.5, Pallid.UI.Anim.alpha(self:shade(self.statusBorderColor), alpha))
        Pallid.UI.circle(el, cx, cy, radius, Pallid.UI.Anim.alpha(self:shade(self.statusColor), alpha * pulse))
    end

    if self.animated then
        for i = 1, #self.badges do
            self.badges[i].widget.visible = alpha > 0.5
        end
    end
end
