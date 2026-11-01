require "pallid/ui/internal"
require "pallid/ui/api/clip"
local Atlas = require "pallid/ui/api/icon_atlas"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local I = Pallid.UI._internal

--- @class PallidTextureOpts Options for Pallid.UI.texture.
--- @field mode "stretch"|"fit"|"fill"|nil How the texture fills the box. Defaults to "stretch".
--- @field flipX boolean|nil Mirror horizontally. Applies to stretch and fit.
--- @field flipY boolean|nil Mirror vertically. Applies to stretch and fit.
--- @field rotation number|nil Clockwise rotation in degrees around the box center. Applies to stretch and fit.
--- @field tiled boolean|nil Tile the texture at its natural size. Ignores mode/flip/rotation.

--- Texture loading and icon registry.
--- @class PallidTexturesModule Texture loading and icon registry.
local Textures = {}
Pallid.UI.Textures = Textures

local cache = {}
local warned = {}
local iconPaths = {}
local ICON_OPTS = { mode = "fit" }
local textureMetricsCache = {}
local originFrame = -1
local originElement = nil
local originX, originY = 0, 0
local ATLAS_DIR = "media/assets/ui/pallid/atlas/"
local regionCache = {}

--- One rectangle in an icon or emoji atlas.
--- @class PallidTextureRegion
--- @field texture Texture Loaded atlas texture.
--- @field sx number Source X in atlas pixels.
--- @field sy number Source Y in atlas pixels.
--- @field sw number Source width in atlas pixels.
--- @field sh number Source height in atlas pixels.
--- @field width number Original icon width in pixels.
--- @field height number Original icon height in pixels.

--- Cached intrinsic metrics for one texture.
--- @class PallidTextureMetrics
--- @field width number Trimmed texture width in pixels.
--- @field height number Trimmed texture height in pixels.
--- @field origWidth number Untrimmed original width in pixels.
--- @field origHeight number Untrimmed original height in pixels.
--- @field offsetX number Trimmed-content X offset inside the original image.
--- @field offsetY number Trimmed-content Y offset inside the original image.

--- Returns cached intrinsic metrics for a texture. The game getters cross into
--- Java; icons and atlas pieces are otherwise re-measured on every draw.
--- @param texture Texture|nil Source texture.
--- @return PallidTextureMetrics|nil metrics Cached metrics, or nil for a nil texture.
function Textures.metrics(texture)
    if texture == nil then
        return nil
    end
    local metrics = textureMetricsCache[texture]
    if metrics ~= nil then
        return metrics
    end

    local width = texture:getWidth()
    local height = texture:getHeight()
    local origWidth, origHeight = width, height
    if texture.getWidthOrig ~= nil then
        origWidth = texture:getWidthOrig() or width
    end
    if texture.getHeightOrig ~= nil then
        origHeight = texture:getHeightOrig() or height
    end
    local offsetX, offsetY = 0, 0
    if texture.getOffsetX ~= nil then
        offsetX = texture:getOffsetX() or 0
    end
    if texture.getOffsetY ~= nil then
        offsetY = texture:getOffsetY() or 0
    end

    metrics = {
        width      = width,
        height     = height,
        origWidth  = origWidth,
        origHeight = origHeight,
        offsetX    = offsetX,
        offsetY    = offsetY,
    }
    textureMetricsCache[texture] = metrics
    return metrics
end

--- Resolves a registered icon name to its texture path.
--- @param name string|nil Icon name.
--- @return string|nil path Texture path, or nil when the name is not registered.
local function iconPath(name)
    if type(name) ~= "string" then
        return nil
    end
    return iconPaths[name]
end

--- UIElement.DrawTexture is the only game quad call that does not add
--- absoluteX/Y or scroll (UIElement.java:257), so every point has to be shifted
--- by hand. Without this, rotated quads stay at screen coordinates and ignore
--- window movement.
--- @param el ISUIElement Target element.
--- @return number x X coordinate.
--- @return number y Y coordinate.
local function absoluteOffset(el)
    local frame = I.textureFrame
    if originElement == el and originFrame == frame then
        return originX, originY
    end

    local x, y = 0, 0
    if el.getAbsoluteX ~= nil then
        x = el:getAbsoluteX() or 0
        y = el:getAbsoluteY() or 0
    end
    local java = el.javaObject
    if java ~= nil and java.getXScroll ~= nil then
        x = x + (java:getXScroll() or 0)
        y = y + (java:getYScroll() or 0)
    end
    originElement = el
    originFrame = frame
    originX, originY = x, y
    return x, y
end

--- Resolves an icon specification to a texture or a registered name.
--- @param icon string|false|nil Registered icon name, texture path or false.
--- @return Texture|nil texture Loaded texture when a path was given.
--- @return string|nil name Registered icon name when a bare name was given.
function Textures.resolve(icon)
    if type(icon) ~= "string" then
        return nil, nil
    end
    if string.find(icon, "/", 1, true) ~= nil then
        return Textures.get(icon), nil
    end
    return nil, icon
end

--- Loads and caches a texture. Missing textures are cached as failures so a
--- bad path produces one warning instead of one per frame.
--- @param path string|nil Texture path relative to media/.
--- @return Texture|nil texture Resolved texture, or nil.
function Textures.get(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end
    local cached = cache[path]
    if cached ~= nil then
        return cached or nil
    end

    local ok, texture = pcall(getTexture, path)
    if not ok or texture == nil then
        cache[path] = false
        if not warned[path] then
            warned[path] = true
            I.logger:warn("cannot load texture: " .. path)
        end
        return nil
    end
    cache[path] = texture
    return texture
end

--- Drops the path prefix up to and including the first slash.
--- @param path string Source path or file name.
--- @return string name Final path component.
local function baseName(path)
    local slash = string.find(path, "/", 1, true)
    if slash ~= nil then
        return string.sub(path, slash + 1)
    end
    return path
end

--- Loads the numbered atlas page image for a texture family.
--- @param kind "icons"|"emoji" Atlas family.
--- @param index integer One-based atlas index.
--- @return Texture|nil texture Loaded atlas texture.
local function atlasTexture(kind, index)
    local file = kind == "emoji" and "emoji-" or "icons-"
    return Textures.get(ATLAS_DIR .. file .. string.format("%02d", index) .. ".png")
end

--- Builds a region descriptor from an atlas entry and its page texture.
--- @param kind "icons"|"emoji" Atlas family.
--- @param entry integer[] `{ atlasIndex, x, y, width, height }`.
--- @return PallidTextureRegion|nil region Cached region descriptor.
local function buildRegion(kind, entry)
    local texture = atlasTexture(kind, entry[1])
    if texture == nil then
        return nil
    end
    return {
        texture = texture,
        sx      = entry[2],
        sy      = entry[3],
        sw      = entry[4],
        sh      = entry[5],
        width   = entry[4],
        height  = entry[5],
    }
end

--- Resolves a built-in icon or emoji path to an atlas region. Third-party or
--- unknown paths return nil and must use the individual texture API.
--- @param path string Texture path or file name.
--- @return PallidTextureRegion|nil region Atlas region, or nil.
function Textures.getRegion(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end
    local cached = regionCache[path]
    if cached ~= nil then
        return cached or nil
    end

    local file = baseName(path)
    local entry, kind
    if string.find(path, "/emoji-32/", 1, true) ~= nil then
        entry = Atlas.emoji[file]
        kind = "emoji"
    elseif string.find(path, "/icons/", 1, true) ~= nil then
        entry = Atlas.icons[file]
        kind = "icons"
    else
        entry = Atlas.icons[file]
        kind = "icons"
        if entry == nil then
            entry = Atlas.emoji[file]
            kind = "emoji"
        end
    end
    local region = entry ~= nil and buildRegion(kind, entry) or nil
    regionCache[path] = region or false
    return region
end

--- Resolves a registered icon name to an atlas region.
--- @param name string|nil Registered icon name or texture path.
--- @return PallidTextureRegion|nil region Atlas region, or nil.
function Textures.getIconRegion(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local path = iconPaths[name]
    if path ~= nil then
        return Textures.getRegion(path)
    end
    if string.find(name, "/", 1, true) ~= nil then
        return Textures.getRegion(name)
    end
    local entry = Atlas.icons[name]
    return entry ~= nil and buildRegion("icons", entry) or nil
end

--- Resolves an emoji name to an atlas region. Accepts `alien`, `alien.png`
--- and full paths; unknown names return nil.
--- @param name string|nil Emoji name or path.
--- @return PallidTextureRegion|nil region Atlas region, or nil.
function Textures.getEmojiRegion(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local file = baseName(name)
    if string.sub(file, -4) ~= ".png" then
        file = file .. ".png"
    end
    local key = "emoji:" .. file
    local cached = regionCache[key]
    if cached ~= nil then
        return cached or nil
    end
    local entry = Atlas.emoji[file]
    local region = entry ~= nil and buildRegion("emoji", entry) or nil
    regionCache[key] = region or false
    return region
end

--- Registers a named icon for Pallid.UI.icon.
--- @param name string Icon name used at draw time.
--- @param path string Texture path relative to media/.
function Textures.registerIcon(name, path)
    if type(name) ~= "string" or name == "" then
        return
    end
    iconPaths[name] = path
end

--- True when an icon name was registered with Textures.registerIcon.
--- @param name string|nil Icon name.
--- @return boolean known True when the name resolves to a texture path.
function Textures.hasIcon(name)
    return type(name) == "string" and iconPaths[name] ~= nil
end

--- Resolves a registered icon to its loaded texture.
--- @param name string|nil Icon name passed to Textures.registerIcon.
--- @return Texture|nil texture Loaded texture, or nil when unknown or missing.
function Textures.getIcon(name)
    local path = iconPath(name)
    if path == nil then
        return nil
    end
    return Textures.get(path)
end

--- Draws a texture into a box.
--- "stretch" fills the box exactly, "fit" preserves the aspect ratio of the
--- original texture, and "fill" covers the box by cropping. Trimming offsets
--- (getWidthOrig/getOffsetX/getOffsetY) are honoured by stretch and fit; fill
--- works in trimmed texture space and ignores flipX/flipY/rotation.
--- @param el ISUIElement Target element.
--- @param texture Texture|nil Texture to draw.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Destination width in pixels.
--- @param h number Destination height in pixels.
--- @param color PallidColor|nil Tint color. Nil means white.
--- @param opts PallidTextureOpts|nil Drawing options. Create the table once and reuse it.
--- @return boolean drawn True when the draw call rendered something.
function Pallid.UI.texture(el, texture, x, y, w, h, color, opts)
    if not I.hasJava(el) or texture == nil or w <= 0 or h <= 0 then
        return false
    end
    if Pallid.UI.isClippedOut(x, y, w, h) then
        return false
    end

    local r, g, b, a = I.colorParts(color)
    local mode = (opts and opts.mode) or "stretch"
    if mode ~= "stretch" and mode ~= "fit" and mode ~= "fill" then
        -- A typo in the mode must not silently fall back to stretch without a trace.
        local key = "mode:" .. tostring(mode)
        if not warned[key] then
            warned[key] = true
            I.logger:warn("texture: unknown mode '" .. tostring(mode) .. "', using stretch")
        end
        mode = "stretch"
    end
    local rotation = (opts and opts.rotation) or 0
    local flipX = opts and opts.flipX
    local flipY = opts and opts.flipY

    if opts and opts.tiled then
        local perf = I.perf
        if perf.enabled then
            perf.textures = perf.textures + 1
            perf.sprites = perf.sprites + 1
        end
        el:drawTextureTiled(texture, x, y, w, h, r, g, b, a)
        return true
    end

    local metrics = Textures.metrics(texture)
    local tw, th = metrics.width, metrics.height
    if tw <= 0 or th <= 0 then
        return false
    end

    if mode == "fill" then
        local scale = math.max(w / tw, h / th)
        local sw, sh = w / scale, h / scale
        local sx, sy = (tw - sw) * 0.5, (th - sh) * 0.5
        x, y, w, h = I.snapBox(x, y, w, h)
        return Pallid.UI.subTexture(el, texture, sx, sy, sw, sh, x, y, w, h, color)
    end

    local perf = I.perf
    if perf.enabled then
        perf.textures = perf.textures + 1
        perf.sprites = perf.sprites + 1
    end

    local drawX, drawY, drawW, drawH = x, y, w, h
    if mode == "fit" then
        local ow, oh = metrics.origWidth, metrics.origHeight
        if ow > 0 and oh > 0 then
            local scale = math.min(w / ow, h / oh)
            drawW, drawH = tw * scale, th * scale
            -- Center the original (untrimmed) texture first, then move to the
            -- trimmed content so every side keeps its real padding.
            drawX = x + (w - ow * scale) * 0.5 + metrics.offsetX * scale
            drawY = y + (h - oh * scale) * 0.5 + metrics.offsetY * scale
        end
    else
        local ow, oh = metrics.origWidth, metrics.origHeight
        if ow > 0 and oh > 0 then
            local scaleX, scaleY = w / ow, h / oh
            drawX = x + metrics.offsetX * scaleX
            drawY = y + metrics.offsetY * scaleY
            drawW, drawH = tw * scaleX, th * scaleY
        end
    end

    if rotation == 0 and not flipX and not flipY then
        drawX, drawY, drawW, drawH = I.snapBox(drawX, drawY, drawW, drawH)
        el:drawTextureScaled(texture, drawX, drawY, drawW, drawH, a, r, g, b)
        return true
    end

    local tlx, tly = drawX, drawY
    local trx, trY = drawX + drawW, drawY
    local brx, bry = drawX + drawW, drawY + drawH
    local blx, bly = drawX, drawY + drawH

    if flipX then
        tlx, trx = trx, tlx
        blx, brx = brx, blx
    end
    if flipY then
        tly, bly = bly, tly
        trY, bry = bry, trY
    end

    if rotation ~= 0 then
        local cx, cy = drawX + drawW * 0.5, drawY + drawH * 0.5
        local angle = math.rad(rotation)
        local c, s = math.cos(angle), math.sin(angle)
        local px, py = tlx - cx, tly - cy
        tlx, tly = cx + px * c - py * s, cy + px * s + py * c
        px, py = trx - cx, trY - cy
        trx, trY = cx + px * c - py * s, cy + px * s + py * c
        px, py = brx - cx, bry - cy
        brx, bry = cx + px * c - py * s, cy + px * s + py * c
        px, py = blx - cx, bly - cy
        blx, bly = cx + px * c - py * s, cy + px * s + py * c
    end

    local ax, ay = absoluteOffset(el)
    el:drawTextureAllPoint(
        texture,
        tlx + ax, tly + ay,
        trx + ax, trY + ay,
        brx + ax, bry + ay,
        blx + ax, bly + ay,
        r, g, b, a
    )
    return true
end

--- Draws one atlas region. Supports stretch/fit/fill; rotation, flipping and
--- tiling are not supported for a sub-region and return false, so callers keep
--- their individual-texture fallback for those cases.
--- @param el ISUIElement Target element.
--- @param region PallidTextureRegion|nil Atlas region.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Destination width.
--- @param h number Destination height.
--- @param color PallidColor|nil Tint color.
--- @param opts PallidTextureOpts|nil Drawing options; only `mode` is used.
--- @return boolean drawn True when the region was drawn.
function Pallid.UI.textureRegion(el, region, x, y, w, h, color, opts)
    if not I.hasJava(el) or type(region) ~= "table" or region.texture == nil then
        return false
    end
    if w <= 0 or h <= 0 or Pallid.UI.isClippedOut(x, y, w, h) then
        return false
    end
    if opts ~= nil and (opts.tiled or opts.rotation ~= nil and opts.rotation ~= 0
        or opts.flipX or opts.flipY) then
        return false
    end

    local mode = (opts and opts.mode) or "stretch"
    local sx, sy, sw, sh = region.sx, region.sy, region.sw, region.sh
    local dx, dy, dw, dh = x, y, w, h
    if mode == "fit" then
        local scale = math.min(w / math.max(1, sw), h / math.max(1, sh))
        dw, dh = sw * scale, sh * scale
        dx = x + (w - dw) * 0.5
        dy = y + (h - dh) * 0.5
    elseif mode == "fill" then
        local scale = math.max(w / math.max(1, sw), h / math.max(1, sh))
        local cropW, cropH = w / scale, h / scale
        sx = sx + (sw - cropW) * 0.5
        sy = sy + (sh - cropH) * 0.5
        sw, sh = cropW, cropH
    end
    dx, dy, dw, dh = I.snapBox(dx, dy, dw, dh)
    return Pallid.UI.subTexture(el, region.texture, sx, sy, sw, sh, dx, dy, dw, dh, color)
end

--- Draws a sub-region of a texture. All thirteen game arguments are always
--- passed because the game's nine-argument branch is broken. The destination
--- offset is compensated so x/y is exact.
--- @param el ISUIElement Target element.
--- @param texture Texture|nil Source texture.
--- @param sx number Source X in texture pixels (trimmed texture space).
--- @param sy number Source Y in texture pixels (trimmed texture space).
--- @param sw number Source width in pixels.
--- @param sh number Source height in pixels.
--- @param x number Destination left.
--- @param y number Destination top.
--- @param w number Destination width.
--- @param h number Destination height.
--- @param color PallidColor|nil Tint color.
--- @return boolean drawn True when the draw call rendered something.
function Pallid.UI.subTexture(el, texture, sx, sy, sw, sh, x, y, w, h, color)
    if not I.hasJava(el) or texture == nil or sw <= 0 or sh <= 0 or w <= 0 or h <= 0 then
        return false
    end
    local r, g, b, a = I.colorParts(color)
    local metrics = Textures.metrics(texture)
    local perf = I.perf
    if perf.enabled then
        perf.textures = perf.textures + 1
        perf.sprites = perf.sprites + 1
    end
    el:drawSubTexture(
        texture, sx, sy, sw, sh,
        x - metrics.offsetX, y - metrics.offsetY,
        w, h, a, r, g, b
    )
    return true
end

--- Draws a nine-slice texture. Border pieces keep their source pixel size; the
--- center and edges stretch. If borders do not fit the destination, the whole
--- texture is stretched instead.
--- @param el ISUIElement Target element.
--- @param texture Texture|nil Source texture.
--- @param x number Destination left.
--- @param y number Destination top.
--- @param w number Destination width.
--- @param h number Destination height.
--- @param borders table Border sizes: { left, right, top, bottom } or { l, r, t, b }.
--- @param color PallidColor|nil Tint color.
--- @return boolean drawn True when the draw call rendered something.
function Pallid.UI.nineSlice(el, texture, x, y, w, h, borders, color)
    if not I.hasJava(el) or texture == nil or w <= 0 or h <= 0 or type(borders) ~= "table" then
        return false
    end

    local left = borders.left or borders.l or 0
    local right = borders.right or borders.r or 0
    local top = borders.top or borders.t or 0
    local bottom = borders.bottom or borders.b or 0
    local metrics = Textures.metrics(texture)
    local tw, th = metrics.width, metrics.height

    if left + right >= tw or top + bottom >= th or left + right >= w or top + bottom >= h then
        return Pallid.UI.texture(el, texture, x, y, w, h, color)
    end

    Pallid.UI.subTexture(el, texture, 0, 0, left, top, x, y, left, top, color)
    Pallid.UI.subTexture(el, texture, tw - right, 0, right, top, x + w - right, y, right, top, color)
    Pallid.UI.subTexture(el, texture, 0, th - bottom, left, bottom, x, y + h - bottom, left, bottom, color)
    Pallid.UI.subTexture(el, texture, tw - right, th - bottom, right, bottom, x + w - right, y + h - bottom, right, bottom, color)

    Pallid.UI.subTexture(el, texture, left, 0, tw - left - right, top, x + left, y, w - left - right, top, color)
    Pallid.UI.subTexture(el, texture, left, th - bottom, tw - left - right, bottom, x + left, y + h - bottom, w - left - right, bottom, color)
    Pallid.UI.subTexture(el, texture, 0, top, left, th - top - bottom, x, y + top, left, h - top - bottom, color)
    Pallid.UI.subTexture(el, texture, tw - right, top, right, th - top - bottom, x + w - right, y + top, right, h - top - bottom, color)

    Pallid.UI.subTexture(
        el,
        texture,
        left, top, tw - left - right, th - top - bottom,
        x + left, y + top, w - left - right, h - top - bottom,
        color
    )
    return true
end

--- Draws a registered icon, preserving aspect ratio inside the size box.
--- @param el ISUIElement Target element.
--- @param name string Icon name passed to Textures.registerIcon.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param size number Width and height of the icon box.
--- @param color PallidColor|nil Tint color.
--- @return boolean drawn True when the draw call rendered something.
function Pallid.UI.icon(el, name, x, y, size, color)
    if size == nil or size <= 0 then
        return false
    end
    local region = Textures.getIconRegion(name)
    if region ~= nil then
        return Pallid.UI.textureRegion(el, region, x, y, size, size, color, ICON_OPTS)
    end
    local path = iconPath(name)
    if path == nil then
        local key = "icon:" .. tostring(name)
        if not warned[key] then
            warned[key] = true
            I.logger:warn("icon: '" .. tostring(name) .. "' is not registered")
        end
        return false
    end
    local texture = Textures.get(path)
    if texture == nil then
        return false
    end
    return Pallid.UI.texture(el, texture, x, y, size, size, color, ICON_OPTS)
end

--- Draws an emoji from the generated emoji atlas. A full texture path or an
--- uncatalogued name falls back to the individual source PNG, so third-party
--- emoji sets keep working.
--- @param el ISUIElement Target element.
--- @param name string Emoji name (`alien`), file name or texture path.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param size number Width and height of the emoji box.
--- @param color PallidColor|nil Tint color.
--- @return boolean drawn True when the draw call rendered something.
function Pallid.UI.emoji(el, name, x, y, size, color)
    if size == nil or size <= 0 then
        return false
    end
    local region = Textures.getEmojiRegion(name)
    if region ~= nil then
        return Pallid.UI.textureRegion(el, region, x, y, size, size, color, ICON_OPTS)
    end
    if type(name) ~= "string" or name == "" then
        return false
    end
    local path = name
    if string.find(path, "/", 1, true) == nil then
        if string.sub(path, -4) ~= ".png" then
            path = path .. ".png"
        end
        path = "media/assets/ui/pallid/emoji-32/" .. path
    end
    local texture = Textures.get(path)
    if texture == nil then
        return false
    end
    return Pallid.UI.texture(el, texture, x, y, size, size, color, ICON_OPTS)
end

--- Draws an inventory item or script item icon through the correct game method.
--- @param el ISUIElement Target element.
--- @param item InventoryItem|Item|nil Item instance or script item.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Icon width in pixels.
--- @param h number Icon height in pixels.
--- @param alpha number|nil Alpha, 0..1. Defaults to 1.
--- @return boolean drawn True when the draw call rendered something.
function Pallid.UI.itemIcon(el, item, x, y, w, h, alpha)
    if not I.hasJava(el) or item == nil or w <= 0 or h <= 0 then
        return false
    end
    local isInventoryItem = false
    if instanceof ~= nil then
        isInventoryItem = instanceof(item, "InventoryItem")
    end
    if isInventoryItem then
        el:drawItemIcon(item, x, y, alpha or 1, w, h)
    else
        el:drawScriptItemIcon(item, x, y, alpha or 1, w, h)
    end
    return true
end
