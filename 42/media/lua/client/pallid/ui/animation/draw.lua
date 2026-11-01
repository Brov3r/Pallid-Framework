require "pallid/ui/internal"
require "pallid/ui/animation/util"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Anim = Pallid.UI.Anim
local I = Pallid.UI._internal

--- Animated drawing helpers. Each one reads a track's channels and forwards a
--- single call to Pallid.UI, so a whole frame of animated UI costs the same
--- draw calls as a static one. Nothing here allocates.
---
--- `track` must have been updated for the current frame
--- (track:update(now)); these functions never advance time themselves.

--- Draws a rectangle that follows the track's alpha, scale (around the box
--- center), offset and nothing else.
--- @param el ISUIElement Target element.
--- @param track PallidAnimTrack Track already advanced for this frame.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param color PallidColor|nil Fill or tint color; nil means white.
--- @return boolean drawn True when the draw call rendered something.
function Anim.rect(el, track, x, y, w, h, color)
    local sx, sy, sw, sh = Anim.scaleRect(x + track.dx, y + track.dy, w, h, track.scale)
    return Pallid.UI.rect(el, sx, sy, sw, sh, Anim.alpha(color, track.alpha))
end

--- Draws a rounded rectangle. A numeric radius scales with the track; a
--- {tl,tr,br,bl} table is passed through untouched.
--- @param el ISUIElement Target element.
--- @param track PallidAnimTrack Track already advanced for this frame.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param radius number|table Corner radius or a {tl,tr,br,bl} table.
--- @param color PallidColor|nil Fill or tint color; nil means white.
--- @return boolean drawn True when the draw call rendered something.
function Anim.roundedRect(el, track, x, y, w, h, radius, color)
    local sx, sy, sw, sh = Anim.scaleRect(x + track.dx, y + track.dy, w, h, track.scale)
    local r = radius
    if type(radius) == "number" then
        r = radius * track.scale
    end
    return Pallid.UI.roundedRect(el, sx, sy, sw, sh, r, Anim.alpha(color, track.alpha))
end

--- Draws a circle or sector. The radius scales with the track.
--- @param el ISUIElement Target element.
--- @param track PallidAnimTrack Track already advanced for this frame.
--- @param cx number Center X.
--- @param cy number Center Y.
--- @param radius number Circle radius in pixels.
--- @param color PallidColor|nil Fill or tint color; nil means white.
--- @param a0 number|nil Start angle in radians.
--- @param a1 number|nil End angle in radians.
--- @return boolean drawn True when the draw call rendered something.
function Anim.circle(el, track, cx, cy, radius, color, a0, a1)
    return Pallid.UI.circle(
        el,
        cx + track.dx, cy + track.dy, radius * track.scale,
        Anim.alpha(color, track.alpha),
        a0, a1
    )
end

--- Draws a regular polygon. The vertex radius scales and the track rotation is
--- added to `rotation`.
--- @param el ISUIElement Target element.
--- @param track PallidAnimTrack Track already advanced for this frame.
--- @param sides integer Number of sides, at least 3.
--- @param cx number Center X.
--- @param cy number Center Y.
--- @param radius number Vertex radius in pixels.
--- @param rotation number|nil Rotation in degrees, added to the track rotation.
--- @param color PallidColor|nil Fill or tint color; nil means white.
--- @return boolean drawn True when the draw call rendered something.
function Anim.regularPolygon(el, track, sides, cx, cy, radius, rotation, color)
    return Pallid.UI.regularPolygon(
        el, sides,
        cx + track.dx, cy + track.dy, radius * track.scale,
        (rotation or 0) + track.rotation,
        Anim.alpha(color, track.alpha)
    )
end

--- Draws text with the track's alpha, offset and scale. The caller's style is
--- mutated for the duration of the call and restored afterwards, which keeps
--- the draw path allocation-free. The track rotation is not applied: the text
--- API cannot rotate glyphs.
--- @param el ISUIElement Target element.
--- @param track PallidAnimTrack Track already advanced for this frame.
--- @param str string Text to draw.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param style PallidTextStyle Text style; create it once and reuse it.
--- @return boolean drawn True when the draw call rendered something.
function Anim.text(el, track, str, x, y, style)
    local baseColor = style.color
    local baseScale = style.scale

    style.color = Anim.alpha(baseColor, track.alpha)
    if baseScale ~= nil then
        style.scale = baseScale * track.scale
    elseif track.scale ~= 1 then
        style.scale = track.scale
    end

    local ok, drawn = pcall(Pallid.UI.text, el, str, x + track.dx, y + track.dy, style)

    -- The style belongs to the caller: restore it even when the draw raised.
    style.color = baseColor
    style.scale = baseScale
    if not ok then
        I.logger:error("Anim.text: draw failed: " .. tostring(drawn))
        return false
    end
    return drawn
end

local TEXTURE_OPTS = { mode = "stretch", rotation = 0, flipX = false, flipY = false, tiled = false }

--- Draws a texture around the box center with the track's alpha, scale, offset
--- and rotation. `opts` is copied into a shared scratch table, so passing the
--- same table every frame is enough. Tiled mode tiles inside the scaled
--- destination box and drops the rotation, because the game has no rotated
--- tiled call.
--- @param el ISUIElement Target element.
--- @param track PallidAnimTrack Track already advanced for this frame.
--- @param texture Texture|nil Source texture.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param color PallidColor|nil Fill or tint color; nil means white.
--- @param opts PallidTextureOpts|nil Texture options; create once and reuse it.
--- @return boolean drawn True when the draw call rendered something.
function Anim.texture(el, track, texture, x, y, w, h, color, opts)
    local cx, cy = x + w * 0.5, y + h * 0.5
    local sw, sh = w * track.scale, h * track.scale
    local sx = cx - sw * 0.5 + track.dx
    local sy = cy - sh * 0.5 + track.dy

    TEXTURE_OPTS.mode = opts and opts.mode or "stretch"
    TEXTURE_OPTS.flipX = opts and opts.flipX or false
    TEXTURE_OPTS.flipY = opts and opts.flipY or false
    TEXTURE_OPTS.tiled = opts and opts.tiled or false
    TEXTURE_OPTS.rotation = (opts and opts.rotation or 0) + track.rotation

    return Pallid.UI.texture(el, texture, sx, sy, sw, sh, Anim.alpha(color, track.alpha), TEXTURE_OPTS)
end

--- Draws a registered icon scaled around its center.
--- @param el ISUIElement Target element.
--- @param track PallidAnimTrack Track already advanced for this frame.
--- @param name string Registered icon name.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param size number Width and height of the icon box.
--- @param color PallidColor|nil Fill or tint color; nil means white.
--- @return boolean drawn True when the draw call rendered something.
function Anim.icon(el, track, name, x, y, size, color)
    local scaled = size * track.scale
    local offset = (size - scaled) * 0.5
    return Pallid.UI.icon(
        el, name,
        x + offset + track.dx, y + offset + track.dy, scaled,
        Anim.alpha(color, track.alpha)
    )
end
