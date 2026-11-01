require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/geometry"
require "pallid/ui/api/progress"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets
local Textures = Pallid.UI.Textures

local RECT_SHAPE = Pallid.UI.Shape.rect()
local DEFAULT_SPEED = 12
local MODES = { linear = true, radial = true, outline = true, texture = true }
local DIRECTIONS = { left = true, right = true, up = true, down = true }
local TEXTURE_MODES = { stretch = true, fit = true, fill = true }

--- Copies a color so later palette edits do not leak into the widget.
--- @param color PallidColor|nil Source color; nil becomes white.
--- @return PallidColor copy Independent color table.
local function copyColor(color)
    color = color or Pallid.UI.Color.white
    return {
        r = color.r or 1,
        g = color.g or 1,
        b = color.b or 1,
        a = color.a or 1,
    }
end

--- Clamps a fraction to the 0..1 range.
--- @param value number Value to clamp.
--- @return number fraction Clamped fraction.
local function clamp01(value)
    if value < 0 then
        return 0
    elseif value > 1 then
        return 1
    end
    return value
end

--- True when the radius has any positive corner.
--- @param radius number|table Radius value from options.
--- @return boolean rounded True when a rounded shape is needed.
local function hasRadius(radius)
    if type(radius) == "table" then
        return (radius.tl or 0) > 0 or (radius.tr or 0) > 0
            or (radius.br or 0) > 0 or (radius.bl or 0) > 0
    end
    return type(radius) == "number" and radius > 0
end

--- Progress bar built on Pallid.UI.progress. Supports linear, radial and
--- outline modes plus a textured fill clipped by the progress band. The shown
--- value eases toward the target so programmatic changes look animated.
---
--- Texture mode reveals the foreground texture inside a rectangular band and
--- therefore has no rounded-corner mask; use linear/outline if rounded chrome
--- is required. The widget is display-only by default (`hittable = false`).
---
--- Outline mode strokes a vector perimeter; the engine has no anti-aliased
--- thick stroke, so keep outline thickness small. Rounded linear fills use the
--- AA rounded-rect primitives and are the preferred pill-shaped variant.
--- @class PallidProgressBar : PallidWidget
--- @field value number Target value, 0..1.
--- @field display number Currently drawn value.
--- @field mode "linear"|"radial"|"outline"|"texture" Fill mode.
--- @field direction "left"|"right"|"up"|"down" Linear/texture fill direction.
--- @field animate boolean True eases `display` toward `value`.
--- @field animateSpeed number Easing speed; higher is faster.
--- @field showValue boolean True draws the formatted value in the centre.
--- @field format string|fun(display: number, value: number): string Value formatter.
--- @field radius number|table Rounded corner radius for linear/outline.
--- @field thickness number Outline stroke thickness in pixels.
--- @field plateAlpha number Background plate alpha for outline mode.
--- @field trackAlpha number|nil Explicit track alpha; nil uses the background alpha.
--- @field fg PallidColor Fill color.
--- @field bg PallidColor Track color.
--- @field textColor PallidColor Value text color.
local ProgressBar = Widgets.class("ProgressBar")

--- Creates a new `ProgressBar` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional appearance and behaviour.
--- @field opts.mode "linear"|"radial"|"outline"|"texture"|nil Fill mode, defaults to "linear".
--- @field opts.value number|nil Initial target value, clamped to 0..1.
--- @field opts.direction "left"|"right"|"up"|"down"|nil Linear/texture fill direction.
--- @field opts.startAngle number|nil Radial start angle in degrees, defaults to -90.
--- @field opts.clockwise boolean|nil Radial direction, defaults to true.
--- @field opts.radius number|table|nil Rounded corner radius for linear/outline.
--- @field opts.thickness number|nil Outline thickness, defaults to 4.
--- @field opts.fg PallidColor|nil Fill color, defaults to Color.primary.
--- @field opts.bg PallidColor|nil Track color, defaults to Color.surfaceElevated.
--- @field opts.trackAlpha number|nil Explicit track alpha; nil keeps the background alpha (or 0.9 by default).
--- @field opts.plateAlpha number|nil Background plate alpha for outline mode, defaults to 0.35.
--- @field opts.texture string|nil Background texture path for texture mode.
--- @field opts.textureFg string|nil Foreground texture path, defaults to `texture`.
--- @field opts.textureMode "stretch"|"fit"|"fill"|nil Texture scaling, defaults to "stretch".
--- @field opts.showValue boolean|nil True draws the formatted value.
--- @field opts.format string|function|nil String format for integer percent or `fun(display, value)`.
--- @field opts.animate boolean|nil Eases value changes, defaults to true.
--- @field opts.animateSpeed number|nil Easing speed, defaults to 12.
--- @field opts.textColor PallidColor|nil Value text color, defaults to textPrimary.
--- @field opts.textShadow table|false|nil Shadow style; nil uses a soft default, false disables it.
--- @return PallidProgressBar bar New progress bar instance.
function ProgressBar.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, ProgressBar)
    self:init(x, y, w, h)
    self.hittable = false

    self.mode = opts.mode or "linear"
    if not MODES[self.mode] then
        Pallid.log("ProgressBar: unknown mode '" .. tostring(self.mode) .. "'; using \"linear\"")
        self.mode = "linear"
    end

    self.direction = opts.direction or "right"
    if not DIRECTIONS[self.direction] then
        Pallid.log("ProgressBar: unknown direction '" .. tostring(self.direction) .. "'; using \"right\"")
        self.direction = "right"
    end

    self.startAngle = opts.startAngle or -90
    self.clockwise = opts.clockwise ~= false
    self.animate = opts.animate ~= false
    self.animateSpeed = opts.animateSpeed or DEFAULT_SPEED
    if type(self.animateSpeed) ~= "number" or self.animateSpeed ~= self.animateSpeed
        or self.animateSpeed <= 0 then
        self.animateSpeed = DEFAULT_SPEED
    end
    self.showValue = opts.showValue == true
    self.format = opts.format or "%d%%"
    self.radius = opts.radius or 0
    self.thickness = math.max(1, math.floor((opts.thickness or 4) + 0.5))

    self.value = type(opts.value) == "number" and opts.value or 0
    if self.value ~= self.value then
        self.value = 0
    end
    self.value = clamp01(self.value)
    self.display = self.value

    local hasBackground = opts.bg ~= nil
    self.fg = copyColor(opts.fg or Pallid.UI.Color.primary)
    self.bg = copyColor(opts.bg or Pallid.UI.Color.surfaceElevated)
    if opts.trackAlpha ~= nil then
        self.trackAlpha = opts.trackAlpha
    elseif hasBackground then
        self.trackAlpha = nil
    else
        self.trackAlpha = 0.9
    end
    self.plateAlpha = opts.plateAlpha or 0.35

    self.textColor = opts.textColor or Pallid.UI.Color.textPrimary
    local shadow = opts.textShadow
    if shadow == nil then
        shadow = {
            dx = 1,
            dy = 1,
            color = Pallid.UI.Color.withAlpha(Pallid.UI.Color.black, 0.95),
        }
    elseif shadow == false then
        shadow = nil
    end
    self.textStyle = {
        font = Pallid.UI.Fonts.small,
        color = self.textColor,
        alignH = "center",
        alignV = "middle",
        shadow = shadow,
    }

    self.texture = Textures.get(opts.texture)
    self.textureFg = Textures.get(opts.textureFg or opts.texture)
    self.textureMode = opts.textureMode or "stretch"
    if not TEXTURE_MODES[self.textureMode] then
        Pallid.log("ProgressBar: unknown textureMode '" .. tostring(self.textureMode) .. "'; using \"stretch\"")
        self.textureMode = "stretch"
    end
    self._textureOpts = { mode = self.textureMode }

    self.radialShape = Pallid.UI.Shape.circle()
    self:_rebuildShape()
    self:_rebuildStyle()

    self._shownValue = nil
    self._shownFormat = nil
    self._shownText = ""
    return self
end

--- Factory shortcut for `ProgressBar.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional appearance and behaviour; see `ProgressBar.new`.
--- @return PallidProgressBar bar New progress bar instance.
function Widgets.progressBar(x, y, w, h, opts)
    return ProgressBar.new(x, y, w, h, opts)
end

--- Rebuilds the shape used by linear and outline modes.
function ProgressBar:_rebuildShape()
    self.shape = hasRadius(self.radius)
        and Pallid.UI.Shape.roundedRect(self.radius)
        or RECT_SHAPE
end

--- Rebuilds the style table passed to Pallid.UI.progress.
function ProgressBar:_rebuildStyle()
    self.style = self.style or {}
    self.style.mode = self.mode == "radial" and "radial"
        or (self.mode == "outline" and "outline" or "linear")
    self.style.direction = self.direction
    self.style.startAngle = self.startAngle
    self.style.clockwise = self.clockwise
    self.style.fg = self.fg
    self.style.bg = self.bg
    self.style.thickness = self.thickness
    self.style.trackAlpha = self.trackAlpha

    self._plateStyle = self._plateStyle or {}
    local plate = self._plateStyle
    plate.mode = "linear"
    plate.fg = self.fg
    plate.bg = self.bg
    plate.thickness = self.thickness
    plate.trackAlpha = self.plateAlpha
end

--- Sets the target value. Non-number and NaN values are ignored.
--- @param value number Target value, clamped to 0..1.
--- @return PallidProgressBar self For chaining.
function ProgressBar:setValue(value)
    if type(value) ~= "number" or value ~= value then
        Pallid.log("ProgressBar:setValue expects a finite number")
        return self
    end
    self.value = clamp01(value)
    if not self.animate then
        self.display = self.value
    end
    return self
end

--- Enables or disables easing.
--- @param animate boolean True eases display changes.
--- @return PallidProgressBar self For chaining.
function ProgressBar:setAnimate(animate)
    self.animate = animate == true
    if not self.animate then
        self.display = self.value
    end
    return self
end

--- Switches the fill mode.
--- @param mode "linear"|"radial"|"outline"|"texture" New fill mode.
--- @return PallidProgressBar self For chaining.
function ProgressBar:setMode(mode)
    if not MODES[mode] then
        Pallid.log("ProgressBar:setMode: unknown mode '" .. tostring(mode) .. "'")
        return self
    end
    self.mode = mode
    self:_rebuildStyle()
    return self
end

--- Sets the rounded corner radius for linear/outline modes.
--- @param radius number|table New radius, number or {tl,tr,br,bl}.
--- @return PallidProgressBar self For chaining.
function ProgressBar:setRadius(radius)
    if type(radius) ~= "number" and type(radius) ~= "table" then
        Pallid.log("ProgressBar:setRadius expects a number or a radius table")
        return self
    end
    self.radius = radius
    self:_rebuildShape()
    return self
end

--- Sets the outline stroke thickness.
--- @param thickness number New thickness in pixels, clamped to at least 1.
--- @return PallidProgressBar self For chaining.
function ProgressBar:setThickness(thickness)
    if type(thickness) ~= "number" then
        Pallid.log("ProgressBar:setThickness expects a number")
        return self
    end
    self.thickness = math.max(1, math.floor(thickness + 0.5))
    self:_rebuildStyle()
    return self
end

--- Sets how texture mode scales its textures.
--- @param mode "stretch"|"fit"|"fill" New texture scaling mode.
--- @return PallidProgressBar self For chaining.
function ProgressBar:setTextureMode(mode)
    if not TEXTURE_MODES[mode] then
        Pallid.log("ProgressBar:setTextureMode: unknown mode '" .. tostring(mode) .. "'")
        return self
    end
    self.textureMode = mode
    self._textureOpts.mode = mode
    return self
end

--- Sets fill and track colors.
--- @param fg PallidColor|nil New fill color.
--- @param bg PallidColor|nil New track color.
--- @param trackAlpha number|nil Explicit track alpha; nil keeps the background alpha.
--- @return PallidProgressBar self For chaining.
function ProgressBar:setColors(fg, bg, trackAlpha)
    if fg ~= nil then
        self.fg = copyColor(fg)
    end
    if bg ~= nil then
        self.bg = copyColor(bg)
        -- With an explicit background, nil trackAlpha means "use its own alpha".
        self.trackAlpha = trackAlpha ~= nil and trackAlpha or self.bg.a
    elseif trackAlpha ~= nil then
        self.trackAlpha = trackAlpha
    end
    self:_rebuildStyle()
    return self
end

--- Enables or disables the centred value text.
--- @param show boolean True to draw the formatted value.
--- @return PallidProgressBar self For chaining.
function ProgressBar:setShowValue(show)
    self.showValue = show == true
    return self
end

--- Sets the value formatter. A string receives the integer percentage; a
--- function receives `(display, value)`.
--- @param format string|function New formatter.
--- @return PallidProgressBar self For chaining.
function ProgressBar:setFormat(format)
    self.format = format or "%d%%"
    self._shownValue = nil
    self._shownFormat = nil
    return self
end

--- Sets the fill direction for linear and texture modes.
--- @param direction "left"|"right"|"up"|"down" New direction.
--- @return PallidProgressBar self For chaining.
function ProgressBar:setDirection(direction)
    if not DIRECTIONS[direction] then
        Pallid.log("ProgressBar:setDirection: unknown direction '" .. tostring(direction) .. "'")
        return self
    end
    self.direction = direction
    self:_rebuildStyle()
    return self
end

--- Replaces the texture pair used by texture mode.
--- @param texture string|nil Background texture path.
--- @param textureFg string|nil Foreground texture path; nil reuses `texture`.
--- @return PallidProgressBar self For chaining.
function ProgressBar:setTexture(texture, textureFg)
    self.texture = Textures.get(texture)
    self.textureFg = Textures.get(textureFg or texture)
    return self
end

--- Eases the displayed value toward the target. Per-frame so the bar fills
--- smoothly instead of stepping at the game tick.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function ProgressBar:onAnimate(now, dt)
    if self.animate then
        self.display = Widgets.approach(self.display, self.value, self.animateSpeed, dt)
    end
end

--- Returns the formatted value text. String formatters are cached per percent.
--- @return string text Formatted value shown in the centre.
function ProgressBar:valueText()
    local format = self.format
    if type(format) == "function" then
        local text = format(self.display, self.value)
        return type(text) == "string" and text or tostring(text)
    end

    local shown = math.floor(self.display * 100 + 0.5)
    if shown ~= self._shownValue or format ~= self._shownFormat then
        local ok, text = pcall(string.format, format, shown)
        if not ok then
            Pallid.log("ProgressBar: invalid format '" .. tostring(format) .. "'")
            text = shown .. "%"
        end
        self._shownValue = shown
        self._shownFormat = format
        self._shownText = text
    end
    return self._shownText
end

--- Draws linear mode without a stencil: rounded tracks and fills use the AA
--- rounded-rect primitives, so the reveal edge is not cut by a hard rectangle.
--- @param el ISUIElement Host element.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
function ProgressBar:_drawLinear(el, x, y, w, h)
    local rounded = hasRadius(self.radius)
    local bgColor = self:shade(self.bg, 3)
    local fgColor = self:shade(self.fg, 4)
    if rounded then
        Pallid.UI.roundedRect(el, x, y, w, h, self.radius, bgColor)
    else
        Pallid.UI.rect(el, x, y, w, h, bgColor)
    end

    local fraction = self.display
    if fraction <= 0 then
        return
    end
    if fraction > 1 then
        fraction = 1
    end

    local fx, fy, fw, fh = x, y, w, h
    local direction = self.direction
    if direction == "left" then
        fx = x + w * (1 - fraction)
        fw = w * fraction
    elseif direction == "up" then
        fy = y + h * (1 - fraction)
        fh = h * fraction
    elseif direction == "down" then
        fh = h * fraction
    else
        fw = w * fraction
    end
    if fw <= 0 or fh <= 0 then
        return
    end

    if rounded then
        Pallid.UI.roundedRect(el, fx, fy, fw, fh, self.radius, fgColor)
    else
        Pallid.UI.rect(el, fx, fy, fw, fh, fgColor)
    end
end

--- Draws the bar and, when enabled, the centred value.
--- @param el ISUIElement Host element the widget is rendered into.
function ProgressBar:drawSelf(el)
    if self.w <= 0 or self.h <= 0 then
        return
    end
    local x, y = self:originX(), self:originY()
    local w, h = self.w, self.h

    local fg, bg = self.style.fg, self.style.bg
    self.style.fg = self:shade(self.fg, 1)
    self.style.bg = self:shade(self.bg, 2)

    if self.mode == "texture" then
        self:drawTexture(el, x, y, w, h)
    elseif self.mode == "radial" then
        local size = math.min(w, h)
        local cx = x + (w - size) * 0.5
        local cy = y + (h - size) * 0.5
        Pallid.UI.progress(el, self.radialShape, cx, cy, size, size, self.display, self.style)
    elseif self.mode == "outline" then
        -- A low-alpha plate gives the outline a visible body; the stroke alone
        -- was hard to read on dark surfaces.
        local plateBg = self._plateStyle.bg
        self._plateStyle.bg = self:shade(self.bg, 2)
        Pallid.UI.progress(el, self.shape, x, y, w, h, 0, self._plateStyle)
        self._plateStyle.bg = plateBg
        Pallid.UI.progress(el, self.shape, x, y, w, h, self.display, self.style)
    else
        self:_drawLinear(el, x, y, w, h)
    end

    self.style.fg = fg
    self.style.bg = bg

    if self.showValue then
        local textMax = ((self.mode == "radial") and math.min(w, h) or w) - 8
        if textMax > 0 then
            self.textStyle.maxWidth = textMax
            self.textStyle.color = self:shade(self.textColor)
            local entered = Pallid.UI.clip(el, RECT_SHAPE, x + 2, y + 1, w - 4, h - 2)
            if entered then
                local text = Pallid.UI.truncateText(self:valueText(), self.textStyle.font, textMax)
                if text ~= "" then
                    Pallid.UI.text(el, text, x + w * 0.5, y + h * 0.5, self.textStyle)
                end
                Pallid.UI.clipEnd(el)
            end
            self.textStyle.color = self.textColor
        end
    end
end

--- Draws texture mode: background, then the foreground revealed by the
--- configured direction. A failed clip aborts the foreground instead of
--- painting it unbounded.
--- @param el ISUIElement Host element the widget is rendered into.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
function ProgressBar:drawTexture(el, x, y, w, h)
    if self.texture ~= nil then
        Pallid.UI.texture(el, self.texture, x, y, w, h, self:shade(self.bg), self._textureOpts)
    else
        Pallid.UI.rect(el, x, y, w, h, self:shade(self.bg))
    end

    local fraction = self.display
    if fraction <= 0 then
        return
    end

    local drawFull = fraction >= 1
    local bandX, bandY, bandW, bandH = x, y, w, h
    local direction = self.direction
    if direction == "left" then
        bandX = x + w * (1 - fraction)
        bandW = w * fraction
    elseif direction == "up" then
        bandY = y + h * (1 - fraction)
        bandH = h * fraction
    elseif direction == "down" then
        bandH = h * fraction
    else
        bandW = w * fraction
    end

    if drawFull then
        if self.textureFg ~= nil then
            Pallid.UI.texture(el, self.textureFg, x, y, w, h, self:shade(self.fg, 2), self._textureOpts)
        else
            Pallid.UI.rect(el, x, y, w, h, self:shade(self.fg, 2))
        end
        return
    end
    if bandW <= 0 or bandH <= 0 then
        return
    end

    local entered = Pallid.UI.clip(el, RECT_SHAPE, bandX, bandY, bandW, bandH)
    if not entered then
        return
    end

    if self.textureFg ~= nil then
        -- The full texture is revealed by the band; it does not slide or scale.
        Pallid.UI.texture(el, self.textureFg, x, y, w, h, self:shade(self.fg, 2), self._textureOpts)
    else
        Pallid.UI.rect(el, bandX, bandY, bandW, bandH, self:shade(self.fg, 2))
    end
    Pallid.UI.clipEnd(el)
end
