require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Texture or registered icon with fit/stretch/fill, flip and rotation.
--- @class PallidImage : PallidWidget
--- @field texture Texture|nil Loaded texture source, when drawing a texture directly.
--- @field iconName string|nil Registered icon name, when drawing through the icon registry.
--- @field opts PallidTextureOpts Normalized fit/stretch/fill, flip, rotation and tiling options.
local Image = Widgets.class("Image")

local DEFAULT_OPTS = { mode = "fit" }

--- Copies texture options and fills in the default fit mode.
--- @param options PallidTextureOpts|nil Source options.
--- @return PallidTextureOpts opts Copy with the default mode filled in.
local function copyOptions(options)
    options = options or DEFAULT_OPTS
    return {
        mode     = options.mode or "fit",
        flipX    = options.flipX,
        flipY    = options.flipY,
        rotation = options.rotation,
        tiled    = options.tiled,
    }
end

--- Creates a new `Image` instance.
--- @param source Texture|string|nil Texture, texture path, registered icon name, or nil.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts PallidTextureOpts|nil Texture options; defaults to fit.
--- @return PallidImage image New image instance.
function Image.new(source, x, y, w, h, opts)
    local self = setmetatable({}, Image)
    self:init(x, y, w, h)
    self.opts = copyOptions(opts)
    self._iconRegion = nil
    self._iconTexture = nil
    self._fallbackPath = nil

    if type(source) == "string" then
        if source ~= "" then
            if string.find(source, "/", 1, true) ~= nil then
                self:setTexture(source)
            else
                self:setIcon(source)
            end
        end
    elseif source ~= nil then
        self.texture = source
    end

    return self
end

--- Factory shortcut for `Image.new`.
--- @param source Texture|string|nil Texture, path, registered icon name, or nil.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts PallidTextureOpts|nil Texture options; see `Image.new`.
--- @return PallidImage image New image instance.
function Widgets.image(source, x, y, w, h, opts)
    return Image.new(source, x, y, w, h, opts)
end

--- Sets the texture.
--- @param path string Texture path relative to media/.
--- @return PallidImage self For chaining.
function Image:setTexture(path)
    self.iconName = nil
    self._fallbackPath = path
    self._iconRegion = Pallid.UI.Textures.getRegion(path)
    self.texture = self._iconRegion == nil and Pallid.UI.Textures.get(path) or nil
    self._iconTexture = nil
    return self
end

--- Sets the icon.
--- @param name string Name registered with Textures.registerIcon.
--- @return PallidImage self For chaining.
function Image:setIcon(name)
    self.texture = nil
    self.iconName = name
    self._fallbackPath = nil
    self._iconRegion = Pallid.UI.Textures.getIconRegion(name)
    self._iconTexture = self._iconRegion == nil and Pallid.UI.Textures.getIcon(name) or nil
    return self
end

--- Replaces the option list.
--- @param opts PallidTextureOpts|nil New texture options; defaults to fit.
--- @return PallidImage self For chaining.
function Image:setOptions(opts)
    self.opts = copyOptions(opts)
    return self
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the tree is rendered into.
function Image:drawSelf(el)
    local x, y = self:originX(), self:originY()
    local tint = self.enabled and nil or self:shade(Pallid.UI.Color.white)
    local opts = self.opts
    local transformed = opts.tiled or (opts.rotation or 0) ~= 0 or opts.flipX or opts.flipY

    if self._iconRegion ~= nil and not transformed then
        Pallid.UI.textureRegion(el, self._iconRegion, x, y, self.w, self.h, tint, opts)
        return
    end

    -- Transformed atlases and third-party icons fall back to the individual
    -- texture path, preserving every transform.
    if self.iconName ~= nil then
        if self._iconTexture == nil then
            if self._fallbackPath ~= nil then
                self._iconTexture = Pallid.UI.Textures.get(self._fallbackPath)
            else
                self._iconTexture = Pallid.UI.Textures.getIcon(self.iconName)
            end
        end
        if self._iconTexture ~= nil then
            Pallid.UI.texture(el, self._iconTexture, x, y, self.w, self.h, tint, opts)
        else
            local size = math.min(self.w, self.h)
            Pallid.UI.icon(el, self.iconName, x + (self.w - size) * 0.5,
                y + (self.h - size) * 0.5, size, tint)
        end
        return
    end

    if self.texture == nil and self._fallbackPath ~= nil then
        self.texture = Pallid.UI.Textures.get(self._fallbackPath)
    end
    if self.texture == nil then
        return
    end
    Pallid.UI.texture(el, self.texture, x, y, self.w, self.h, tint, opts)
end
