require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"

local addNativeMethods = require "pallid/ui/widgets/model3d/native"
local addInputMethods = require "pallid/ui/widgets/model3d/input"
local addDrawMethods = require "pallid/ui/widgets/model3d/draw"
local addSourceMethods = require "pallid/ui/widgets/model3d/source"

-- The native model is the only 3D character preview the game exposes to Lua:
-- ISUI3DModel wraps zombie.ui.UI3DModel, which renders an IsoGameCharacter or a
-- named outfit. Vehicles use the ISUI3DScene wrapper, the same script-driven
-- scene the vanilla vehicle editor uses. There is no public Lua API for an item
-- preview, so `opts.item` stays a 2D placeholder. Drawing a stock photo or an empty model
-- rect and calling it 3D would mislead callers.
-- When no source is given the widget renders a character dummy using a named
-- outfit (default "Classy"), because a bare model is still a character model.
--
-- Context matters: a SurvivorDesc or an IsoGameCharacter fills the native
-- ModelInstance synchronously, exactly like the character-creation avatar, so
-- those sources work on the main menu. A named outfit is dressed later by
-- AnimatedModel.update and therefore needs a live player; the widget falls back
-- to 2D otherwise. See Model3D:_nativeContextAvailable and UI3DModel.java.
--
-- The native is a separate always-on-top UIManager element: it is never clipped
-- by Pallid panels and paints above the widget tree, so the widget hides it
-- unless the whole viewport is inside the active software clip.
--
-- Character yaw is limited to the eight IsoDirections values exposed by
-- UI3DModel; there is no continuous angle or pitch setter. Vehicle previews use
-- ISUI3DScene and therefore support smooth camera yaw and pitch.
if ISUI3DModel == nil then
    pcall(require, "ISUI/ISUI3DModel")
end

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local I = Pallid.UI._internal

local DEFAULT_INSET = 4
local DEFAULT_RADIUS = 4
local DEFAULT_LABEL = "Drag to rotate - wheel to zoom"
local DEFAULT_FALLBACK_TEXT = "No 3D preview"
local DEFAULT_DUMMY_OUTFIT = "Classy"
local DEFAULT_ROTATE_INTERVAL = 2.5
-- UI3DModel renders at size - zoom, so the range is inverted relative to scale.
local ZOOM_MIN = -2
local ZOOM_MAX = 4

--- @param value any Value to inspect.
--- @return boolean nonBlank True for a string with at least one non-space char.
local function isNonBlank(value)
    return type(value) == "string" and value:find("%S") ~= nil
end

--- @param value any Value to convert.
--- @param fallback number Value used when the input is not a number.
--- @param minValue number|nil Lower clamp.
--- @param maxValue number|nil Upper clamp.
--- @return number value Numeric value clamped to the requested range.
local function asNumber(value, fallback, minValue, maxValue)
    if type(value) ~= "number" then
        return fallback
    end
    if minValue ~= nil and value < minValue then
        value = minValue
    end
    if maxValue ~= nil and value > maxValue then
        value = maxValue
    end
    return value
end

--- Checks a Java object without assuming the `instanceof` helper exists.
--- @param value any Value to inspect.
--- @param className string Java class name.
--- @return boolean matches True when the value matches.
local function isInstanceOf(value, className)
    if value == nil then
        return false
    end
    if type(instanceof) ~= "function" then
        return type(value) == "userdata"
    end
    local ok, result = pcall(instanceof, value, className)
    return ok and result == true
end

--- Java enums reach Lua as userdata; a plain table or string would make
--- AnimatedModel.setAngle fail on the next frame.
--- @param value any Value to inspect.
--- @return boolean valid True when the value is valid.
local function isDirection(value)
    return type(value) == "userdata"
end

--- @class PallidModel3D : PallidWidget
--- @field model ISUI3DModel|nil Native model. Created lazily.
--- @field character IsoGameCharacter|nil Live character source.
--- @field outfitName string|nil Named outfit source from clothing.xml.
--- @field outfitFemale boolean Female body for the outfit source.
--- @field outfitZombie boolean Zombie body for the outfit source.
--- @field survivorDesc SurvivorDesc|nil Procedural survivor source.
--- @field animSet string|nil AnimSet name applied to the native model.
--- @field state string|nil AnimSet state applied to the native model.
--- @field isometric boolean|nil Isometric projection; nil keeps the native default.
--- @field animateWhilePaused boolean Keeps the native animation running while paused.
--- @field randomExtAnimations boolean Enables the native idle animation events.
--- @field zoom number Native zoom; negative zooms in.
--- @field xOffset number Model offset inside the viewport.
--- @field yOffset number Model offset inside the viewport.
--- @field autoRotate boolean Rotates the model one step every `rotateInterval`.
--- @field rotateInterval number Seconds between auto-rotate steps.
--- @field interactive boolean False makes the preview display-only.
--- @field dragRotate boolean Enables rotation by horizontal dragging.
--- @field wheelZoom boolean Enables zooming with the mouse wheel.
--- @field dummy boolean True when the preview falls back to the built-in dummy outfit.
--- @field dummyOutfit string Outfit used by the built-in dummy.
--- @field dummyFemale boolean Female body for the built-in dummy.
--- @field direction IsoDirections|nil Cached direction, resolved on first turn.
--- @field label string|nil Footer hint. Nil hides the footer strip.
--- @field inset number Padding between the frame and the model viewport.
--- @field radius number Frame corner radius.
--- @field footerHeight number Height of the footer strip in pixels.
--- @field textHeight number Line height of the footer/fallback font.
--- @field item InventoryItem|Item|nil 2D fallback icon source.
--- @field vehicle BaseVehicle|nil Vehicle source rendered through ISUI3DScene.
--- @field vehicleScript string|nil Vehicle script rendered without a world object.
--- @field vehicleView string|nil Initial native vehicle view name, when supported.
--- @field fallbackText string Caption drawn when 3D is unavailable.
--- @field fallbackTexture Texture|nil Resolved fallback texture.
--- @field fallbackIconName string|nil Registered fallback icon name.
--- @field footerStyle PallidTextStyle Reused footer text style; never allocated per frame.
--- @field fallbackStyle PallidTextStyle Reused fallback text style; never allocated per frame.
--- @field _rotateT number Seconds accumulated since the last auto-rotate step.
--- @field _dragging boolean True while a horizontal drag owns the pointer.
--- @field _dragAccum number Accumulated horizontal drag distance.
--- @field _lastMouseX number|nil Previous pointer X during a drag.
--- @field _nativeFailed boolean True when the last native creation attempt failed.
--- @field _nativeKind string|nil "character" or "vehicle" for the current native class.
--- @field _nativeRetryAt number|nil Timestamp of the next native retry.
--- @field _nativeLastError string|nil Last logged native failure.
--- @field _nativeRoot PallidWidget|nil Root that currently owns the native registry entry.
--- @field _vehicleYaw number Camera yaw for the vehicle scene.
--- @field _vehiclePitch number Camera pitch for the vehicle scene.
--- @field _lastMouseY number|nil Previous pointer Y during a drag.
--- @field _nativeLocalX number|nil Viewport left in root-local coordinates.
--- @field _nativeLocalY number|nil Viewport top in root-local coordinates.
--- @field _nativeW number|nil Viewport width.
--- @field _nativeH number|nil Viewport height.
--- @field _fallbackLines string[]|nil Cached wrapped fallback lines.
--- @field _fallbackLineHeight number Cached fallback line height.
--- @field _fallbackWidth number|nil Width the cached fallback lines were wrapped for.
--- @field _fallbackCachedText string|nil Text the cached fallback lines belong to.
--- @field _footerWidth number|nil Width the cached footer text was truncated for.
--- @field _footerCachedLabel string|nil Label the cached footer text belongs to.
--- @field _footerText string|nil Cached truncated footer text.
local Model3D = Widgets.class("Model3D")

--- Creates a new `Model3D` instance.
--- @param x number X coordinate.
--- @param y number Y coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional settings.
--- @field opts.character IsoGameCharacter|nil Rendered as-is.
--- @field opts.outfit table|string|nil `{ name, female, zombie }` or an outfit name.
--- @field opts.outfitName string|nil Same as `opts.outfit.name`.
--- @field opts.dummy boolean|nil Render a character dummy when no source is given. Defaults to true.
--- @field opts.dummyOutfit string|nil Outfit name for the dummy. Defaults to "Classy".
--- @field opts.dummyFemale boolean|nil Female dummy body. Defaults to false.
--- @field opts.female boolean|nil Used with `opts.outfitName`.
--- @field opts.zombie boolean|nil Used with `opts.outfitName`.
--- @field opts.survivorDesc SurvivorDesc|nil Procedural survivor appearance.
--- @field opts.animSet string|nil AnimSet name, e.g. "player". Blank strings are ignored.
--- @field opts.state string|nil AnimSet state, e.g. "idle".
--- @field opts.isometric boolean|nil Isometric projection.
--- @field opts.animateWhilePaused boolean|nil Keep animating while paused.
--- @field opts.randomExtAnimations boolean|nil Enable native idle animation events.
--- @field opts.zoom number|nil Defaults to 0. Negative zooms in.
--- @field opts.xOffset number|nil Model offset inside the viewport.
--- @field opts.yOffset number|nil Model offset inside the viewport.
--- @field opts.autoRotate boolean|nil Defaults to true.
--- @field opts.rotateInterval number|nil Seconds per auto-rotate step. Defaults to 2.5.
--- @field opts.direction IsoDirections|nil Initial direction.
--- @field opts.interactive boolean|nil False makes the preview display-only.
--- @field opts.dragRotate boolean|nil Enables rotation by horizontal dragging; defaults to true.
--- @field opts.wheelZoom boolean|nil Enables zooming with the mouse wheel; defaults to true.
--- @field opts.label string|false|nil Footer hint. False hides it.
--- @field opts.inset number|nil Inset from the widget edges in pixels.
--- @field opts.radius number|nil Corner radius in pixels.
--- @field opts.fallbackIcon string|nil Icon name or texture path drawn when 3D is unavailable.
--- @field opts.fallbackText string|nil Caption for the fallback.
--- @field opts.item InventoryItem|Item|nil Drawn as a 2D inventory icon only.
--- @field opts.vehicle BaseVehicle|nil Rendered by script through ISUI3DScene.
--- @field opts.vehicleScript string|nil Vehicle script name, e.g. "Base.CarNormal"; no world object needed.
--- @field opts.vehicleView string|nil Initial view name passed to the vehicle scene.
--- @return PallidModel3D New 3D model widget.
function Model3D.new(x, y, w, h, opts)
    opts = type(opts) == "table" and opts or {}
    local self = setmetatable({}, Model3D)
    self:init(x, y, w, h)

    self.inset              = asNumber(opts.inset, DEFAULT_INSET, 0)
    self.radius             = asNumber(opts.radius, DEFAULT_RADIUS, 0)
    self.zoom               = I.clamp(asNumber(opts.zoom, 0), ZOOM_MIN, ZOOM_MAX)
    self.xOffset            = asNumber(opts.xOffset, 0)
    self.yOffset            = asNumber(opts.yOffset, 0)
    self.autoRotate         = opts.autoRotate ~= false
    self.rotateInterval     = asNumber(opts.rotateInterval, DEFAULT_ROTATE_INTERVAL, 0)
    self.animateWhilePaused = opts.animateWhilePaused == true
    self.randomExtAnimations = opts.randomExtAnimations == true
    self.interactive        = opts.interactive ~= false
    self.dragRotate         = opts.dragRotate ~= false
    self.wheelZoom          = opts.wheelZoom ~= false
    self.hittable           = self.interactive
    self.animSet            = isNonBlank(opts.animSet) and opts.animSet or nil
    self.state              = type(opts.state) == "string" and opts.state or nil
    if type(opts.isometric) == "boolean" then
        self.isometric = opts.isometric
    end
    if opts.direction ~= nil then
        if isDirection(opts.direction) then
            self.direction = opts.direction
        else
            Pallid.warn("Model3D: ignoring invalid direction; expected IsoDirections")
        end
    end
    self.item               = opts.item
    self.vehicle            = nil
    self.vehicleScript      = nil
    self.vehicleView        = type(opts.vehicleView) == "string" and opts.vehicleView or nil
    self.dummy              = false
    self.dummyOutfit        = isNonBlank(opts.dummyOutfit) and opts.dummyOutfit or DEFAULT_DUMMY_OUTFIT
    self.dummyFemale        = opts.dummyFemale == true
    self.outfitFemale       = self.dummyFemale
    self.outfitZombie       = false

    if opts.label == false then
        self.label = nil
    elseif type(opts.label) == "string" then
        self.label = isNonBlank(opts.label) and opts.label or nil
    else
        self.label = DEFAULT_LABEL
    end

    if type(opts.fallbackText) == "string" then
        self.fallbackText = opts.fallbackText
    elseif opts.vehicle ~= nil or isNonBlank(opts.vehicleScript) then
        self.fallbackText = "Vehicle 3D preview unavailable"
    elseif opts.item ~= nil then
        self.fallbackText = "Item icon preview"
    else
        self.fallbackText = DEFAULT_FALLBACK_TEXT
    end

    self._rotateT       = 0
    self._dragging      = false
    self._dragAccum     = 0
    self._lastMouseX    = nil
    self._lastMouseY    = nil
    self._vehicleYaw    = 90
    self._vehiclePitch  = 0
    self._nativeFailed  = false
    self._nativeKind    = nil
    self._nativeRetryAt = nil
    self._nativeLastError = nil
    self._nativeRoot    = nil

    self.footerStyle = {
        font    = Pallid.UI.Fonts.small,
        color   = Pallid.UI.Color.textMuted,
        alignH  = "center",
        alignV  = "middle",
    }
    self.fallbackStyle = {
        font    = Pallid.UI.Fonts.small,
        color   = Pallid.UI.Color.textMuted,
        alignH  = "center",
        alignV  = "middle",
        wrap    = false,
    }

    -- Font height is resolved once. It drives the footer strip and the line
    -- height of the cached fallback block; both are used every frame.
    local fontHeight = 11
    if type(getTextManager) == "function" then
        local tm = getTextManager()
        if tm ~= nil and tm.getFontHeight ~= nil then
            local ok, value = pcall(tm.getFontHeight, tm, self.footerStyle.font)
            if ok and type(value) == "number" and value > 0 then
                fontHeight = value
            end
        end
    end
    self.textHeight = math.max(1, math.ceil(fontHeight))
    self.footerHeight = math.max(0, math.ceil(fontHeight + 6))

    -- A path goes through the texture cache, a bare name through the icon
    -- registry, matching Image/Button.
    if isNonBlank(opts.fallbackIcon) then
        if string.find(opts.fallbackIcon, "/", 1, true) ~= nil then
            self.fallbackTexture = Pallid.UI.Textures.get(opts.fallbackIcon)
        else
            self.fallbackIconName = opts.fallbackIcon
        end
    end

    if opts.character ~= nil then
        self:setCharacter(opts.character)
    elseif opts.survivorDesc ~= nil then
        self:setSurvivorDesc(opts.survivorDesc)
    elseif opts.vehicle ~= nil then
        self:setVehicle(opts.vehicle)
    elseif isNonBlank(opts.vehicleScript) then
        self:setVehicleScript(opts.vehicleScript)
    else
        local outfit = opts.outfit
        local name, female, zombie
        if type(outfit) == "table" then
            name, female, zombie = outfit.name, outfit.female, outfit.zombie
        elseif type(outfit) == "string" then
            name = outfit
        end
        if name == nil then
            name, female, zombie = opts.outfitName, opts.female, opts.zombie
        end
        if isNonBlank(name) then
            self:setOutfit(name, female, zombie)
        end
    end

    -- Nothing else is renderable in 3D, so an empty preview is a dummy rather
    -- than an empty black rectangle. Item/vehicle callers still get their 2D
    -- placeholder because those are explicit non-character sources.
    if not self:_hasSource() and opts.item == nil and opts.vehicle == nil and opts.dummy ~= false then
        self:setDummy(self.dummyOutfit, self.dummyFemale)
    end

    return self
end

--- Factory shortcut for `Model3D.new`.
--- @param x number X coordinate.
--- @param y number Y coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional settings.
--- @return PallidModel3D New 3D model widget.
function Widgets.model3D(x, y, w, h, opts)
    return Model3D.new(x, y, w, h, opts)
end

--- True when the native model has something to render. Without a source an
--- empty AnimatedModel would be shown, so the 2D fallback is used instead.
--- @return boolean True when a source is configured.
function Model3D:_hasSource()
    return self.character ~= nil
        or self.survivorDesc ~= nil
        or self.vehicle ~= nil
        or isNonBlank(self.vehicleScript)
        or isNonBlank(self.outfitName)
end

--- Sets the zoom factor.
--- @param zoom number Negative zooms in, positive zooms out. Clamped to -2..4.
--- @return PallidModel3D self The same instance, for chaining.
function Model3D:setZoom(zoom)
    if type(zoom) ~= "number" then
        return self
    end
    self.zoom = I.clamp(zoom, ZOOM_MIN, ZOOM_MAX)
    local model = self.model
    if model ~= nil and model.javaObject ~= nil and model.setZoom ~= nil then
        model:setZoom(self.zoom)
    end
    return self
end

--- Returns the zoom factor.
--- @return number zoom Current native zoom.
function Model3D:getZoom()
    return self.zoom
end

--- Sets the horizontal model offset.
--- @param xOffset number Horizontal offset.
--- @return PallidModel3D self The same instance, for chaining.
function Model3D:setXOffset(xOffset)
    self.xOffset = asNumber(xOffset, 0)
    local model = self.model
    if model ~= nil and model.javaObject ~= nil and model.setXOffset ~= nil then
        model:setXOffset(self.xOffset)
    end
    return self
end

--- Sets the vertical model offset.
--- @param yOffset number Vertical offset.
--- @return PallidModel3D self The same instance, for chaining.
function Model3D:setYOffset(yOffset)
    self.yOffset = asNumber(yOffset, 0)
    local model = self.model
    if model ~= nil and model.javaObject ~= nil and model.setYOffset ~= nil then
        model:setYOffset(self.yOffset)
    end
    return self
end

--- Sets the model direction.
--- @param direction IsoDirections|nil New direction. Nil and invalid values are ignored.
--- @return PallidModel3D self The same instance, for chaining.
function Model3D:setDirection(direction)
    if direction == nil then
        return self
    end
    if not isDirection(direction) then
        Pallid.warn("Model3D:setDirection expects an IsoDirections value")
        return self
    end
    self.direction = direction
    local model = self.model
    if model ~= nil and model.javaObject ~= nil and model.setDirection ~= nil then
        model:setDirection(direction)
    end
    return self
end

--- Returns the model direction.
--- @return IsoDirections|nil direction Current model direction.
function Model3D:getDirection()
    return self.direction
end

--- Sets the label text.
--- @param label string|nil Footer hint; nil or a blank string hides the footer.
--- @return PallidModel3D self The same instance, for chaining.
function Model3D:setLabel(label)
    if label == nil then
        self.label = nil
    elseif type(label) == "string" then
        self.label = isNonBlank(label) and label or nil
    else
        Pallid.warn("Model3D:setLabel expects a string or nil")
        return self
    end
    self._footerText = nil
    self._footerWidth = nil
    self._footerCachedLabel = nil
    return self
end

--- Sets whether the model animates while paused.
--- @param enabled boolean Keep the native animation running while the game is paused.
--- @return PallidModel3D self The same instance, for chaining.
function Model3D:setAnimateWhilePaused(enabled)
    self.animateWhilePaused = enabled == true
    local model = self.model
    if model ~= nil and model.javaObject ~= nil and model.setAnimateWhilePaused ~= nil then
        model:setAnimateWhilePaused(self.animateWhilePaused)
    end
    return self
end

--- Shows or hides the widget.
--- @param visible boolean Whether the model is visible.
--- @return PallidModel3D self The same instance, for chaining.
function Model3D:setVisible(visible)
    self.visible = visible
    if not visible then
        self:_hideNative()
        self:_cancelDrag()
    end
    return self
end

-- Native lifecycle, source application, positioning and masking live in a
-- separate file: they are the only code that touches ISUI3DModel directly.
addDrawMethods(Model3D)
addNativeMethods(Model3D, isNonBlank)
-- Source setters live together because switching between a character and a
-- vehicle must also switch the native class.
addSourceMethods(Model3D, isNonBlank, isInstanceOf)
-- Drag, wheel and auto-rotate live in a separate file so the input contract
-- stays readable next to the native lifecycle it controls.
addInputMethods(Model3D)
