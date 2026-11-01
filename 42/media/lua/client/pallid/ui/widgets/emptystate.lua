require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/animation/track"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/button"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local DEFAULT_ICON_SIZE = 48
local DEFAULT_PADDING = 24
local DEFAULT_SPACING = 8
local ACTION_HEIGHT = 30
local ICON_OPTS = { mode = "fit" }

local ICON_DIR = "media/assets/ui/pallid/icons/"
local ICONS = {
    default = "pallid_emptystate_default",
}
Pallid.UI.Textures.registerIcon(ICONS.default, ICON_DIR .. "document.png")

--- Centered placeholder for empty lists, containers and search results.
---
--- The widget itself has no background: put it inside a panel or a list body
--- and it will centre its own icon, title, explanation and optional action in
--- the given bounds. When `h` is zero, the height is measured from the content.
--- The widget is inert: `hittable = false` lets hover reach the widget below,
--- while the action button still receives input as a child.
--- @class PallidEmptyState : PallidWidget
--- @field title string Heading text.
--- @field description string Explanation text under the heading.
--- @field icon Texture|string|false|nil Icon source; nil means the default glyph.
--- @field iconSize number Square size of the icon block in pixels.
--- @field iconName string|nil Registered icon name, when drawing through the registry.
--- @field iconTexture Texture|nil Loaded texture, when drawing a texture directly.
--- @field iconColor PallidColor|nil Icon tint; nil uses the muted text colour.
--- @field padding number Outer padding used for centring and auto-height.
--- @field spacing number Gap between the blocks.
--- @field showIcon boolean True draws the icon block.
--- @field animated boolean True runs the entrance fade/rise.
--- @field floatIcon boolean True runs the looping icon pulse.
--- @field autoHeight boolean True recomputes `h` from the content on every layout.
--- @field titleStyle PallidTextStyle Reused title style.
--- @field descriptionStyle PallidTextStyle Reused description style.
--- @field actionButton PallidButton|nil Optional action button.
--- @field entry PallidAnimTrack Entrance animation track.
--- @field iconFloat PallidAnimTrack|nil Looping icon pulse track.
local EmptyState = Widgets.class("EmptyState")

--- Creates a new `EmptyState` instance.
--- @param x number X coordinate.
--- @param y number Y coordinate.
--- @param w number Width in pixels.
--- @param h number Zero or negative height is measured from the content.
--- @param opts table|nil Optional settings.
--- @field opts.title string|nil Title text.
--- @field opts.description string|nil Description text.
--- @field opts.icon Texture|string|false|nil Icon name, texture path, texture,
---                                     false to hide the default glyph, or nil
---                                     for the packaged document icon.
--- @field opts.iconSize number|nil Defaults to 48.
--- @field opts.iconColor PallidColor|nil Defaults to a muted grey.
--- @field opts.showIcon boolean|nil Defaults to true; false hides the icon block.
--- @field opts.titleFont UIFont|string|nil Title font.
--- @field opts.titleColor PallidColor|nil Title color.
--- @field opts.descriptionFont UIFont|string|nil Description font.
--- @field opts.descriptionColor PallidColor|nil Description color.
--- @field opts.maxLines integer|nil Description line limit. Defaults to 3.
--- @field opts.padding number|nil Defaults to 24.
--- @field opts.spacing number|nil Gap between blocks. Defaults to 8.
--- @field opts.animated boolean|nil Entrance fade/rise. Defaults to true.
--- @field opts.floatIcon boolean|nil Gentle looping icon drift and pulse. Defaults to true.
--- @field opts.action table|nil `{ text, onClick, icon, width, height, sound, radius }`.
--- @return PallidEmptyState New empty-state widget.
function EmptyState.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, EmptyState)
    self:init(x, y, w, h)

    self.autoHeight = h == nil or h <= 0
    self.hittable = false

    self.title = opts.title or "Nothing here"
    self.description = opts.description or ""
    self.iconSize = math.max(0, opts.iconSize or DEFAULT_ICON_SIZE)
    self.padding = math.max(0, opts.padding or DEFAULT_PADDING)
    self.spacing = math.max(0, opts.spacing or DEFAULT_SPACING)
    self.showIcon = opts.showIcon ~= false
    self.animated = opts.animated ~= false
    self.floatIcon = opts.floatIcon ~= false
    self.iconColor = opts.iconColor

    self.titleStyle = {
        font = opts.titleFont or Pallid.UI.Fonts.medium,
        color = opts.titleColor or Pallid.UI.Color.textPrimary,
        alignH = "center",
        alignV = "top",
        ellipsis = "...",
    }
    self.descriptionStyle = {
        font = opts.descriptionFont or Pallid.UI.Fonts.small,
        color = opts.descriptionColor or Pallid.UI.Color.textMuted,
        alignH = "center",
        alignV = "top",
        wrap = true,
        maxLines = opts.maxLines or 3,
        ellipsis = "...",
        lineSpacing = 2,
    }

    if opts.icon == false then
        self:_setIconSource(nil, false)
    else
        self:_setIconSource(opts.icon, true)
    end
    -- An explicit showIcon = false wins over the icon source.
    if opts.showIcon == false then
        self.showIcon = false
    end

    self.entry = Pallid.UI.Anim.new({
        duration = 0.32,
        -- A smooth start avoids the one-pixel jump that outCubic produced on
        -- the first frame of a 10 px rise.
        easing = Pallid.UI.Anim.ease.inOutSine,
        alpha = { 0, 1 },
        dy = { 10, 0 },
    })
    if self.floatIcon then
        self.iconFloat = Pallid.UI.Anim.new({
            duration = 1.8,
            easing = Pallid.UI.Anim.ease.inOutSine,
            loop = true,
            pingPong = true,
            -- Texture x/y are floored to whole pixels by UIElement and
            -- SpriteRenderer, so a position drift always steps. Alpha is the
            -- only channel that stays smooth here.
            alpha = { 1, 0.6 },
        })
    end
    -- Pages of a TabPanel are updated only while active, so a timer started
    -- here would finish before the tab is opened. Start on the first frame the
    -- widget is actually visible instead.
    self._introPending = true

    self:setAction(opts.action)
    return self
end

--- Factory shortcut for `EmptyState.new`.
--- @param x number X coordinate.
--- @param y number Y coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional settings.
--- @return PallidEmptyState New empty-state widget.
function Widgets.emptyState(x, y, w, h, opts)
    return EmptyState.new(x, y, w, h, opts)
end

--- Resolves an icon source into a texture or a registered name.
--- @param icon Texture|string|nil Source; nil means the packaged default glyph.
--- @param visible boolean False hides the icon block.
function EmptyState:_setIconSource(icon, visible)
    self.icon = icon
    self.iconTexture = nil
    self.iconName = nil
    self.showIcon = visible
    if icon == nil then
        if visible then
            self.icon = ICONS.default
            self.iconName = ICONS.default
        end
        return
    end
    if type(icon) == "string" then
        if string.find(icon, "/", 1, true) ~= nil then
            self.iconTexture = Pallid.UI.Textures.get(icon)
        else
            self.iconName = icon
        end
        return
    end
    self.iconTexture = icon
end

--- Replays the entrance animation and the icon drift/pulse. The drift is
--- independent of `animated`, so `animated = false` keeps it running.
--- @return PallidEmptyState self The same instance, for chaining.
function EmptyState:playIntro()
    self._introPending = false
    if self.animated then
        self.entry:play()
        if self.actionButton ~= nil then
            self.actionButton:setVisible(false)
        end
    end
    if self.iconFloat ~= nil then
        self.iconFloat:play()
    end
    return self
end

--- Advances the entrance and icon-float tracks. Per-frame so the reveal does
--- not step at the game tick.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function EmptyState:onAnimate(now, dt)
    if self._introPending then
        self:playIntro()
    end
    if self.animated then
        self.entry:update(now)
        if self.actionButton ~= nil then
            self.actionButton:setVisible(self.entry.finished)
        end
    end
    if self.iconFloat ~= nil then
        self.iconFloat:update(now)
    end
end

--- Updates the widget bounds.
--- @param x number X coordinate.
--- @param y number Y coordinate.
--- @param w number Width in pixels.
--- @param h number Zero or negative height switches to content-measured height.
--- @return PallidEmptyState self The same instance, for chaining.
function EmptyState:setBounds(x, y, w, h)
    self.autoHeight = h == nil or h <= 0
    Widgets.Widget.setBounds(self, x, y, w or 0, h or 0)
    self:_layout()
    return self
end

--- Sets the title text.
--- @param title string Title text.
--- @return PallidEmptyState self The same instance, for chaining.
function EmptyState:setTitle(title)
    self.title = title or ""
    self:_layout()
    return self
end

--- Sets the description text.
--- @param description string Description text.
--- @return PallidEmptyState self The same instance, for chaining.
function EmptyState:setDescription(description)
    self.description = description or ""
    self:_layout()
    return self
end

--- Replaces the icon. A nil restores the packaged default glyph and a false
--- hides the icon block. A texture, texture path or registered icon name is
--- stored as-is.
--- @param icon Texture|string|false|nil Icon source.
--- @return PallidEmptyState self The same instance, for chaining.
function EmptyState:setIcon(icon)
    if icon == false then
        self:_setIconSource(nil, false)
    else
        self:_setIconSource(icon, true)
    end
    self:_layout()
    return self
end

--- Shows or hides the icon block without changing the icon source.
--- @param visible boolean True reserves and draws the icon block.
--- @return PallidEmptyState self The same instance, for chaining.
function EmptyState:setShowIcon(visible)
    self.showIcon = visible and true or false
    self:_layout()
    return self
end

--- Replaces the optional action button. Pass nil to remove it.
--- @param action table|nil `{ text, onClick, icon, width, height, sound, radius }`.
--- @return PallidEmptyState self The same instance, for chaining.
function EmptyState:setAction(action)
    if self.actionButton ~= nil then
        self:remove(self.actionButton)
        self.actionButton = nil
    end
    if action == nil then
        self:_layout()
        return self
    end

    local text = action.text or "OK"
    local width = action.width
    if width == nil then
        width = math.max(140, getTextManager():MeasureStringX(Pallid.UI.Fonts.small, text) + 40)
    end
    local height = action.height or ACTION_HEIGHT
    local button = Widgets.button(0, 0, width, height, {
        text = text,
        icon = action.icon,
        onClick = action.onClick,
        sound = action.sound,
        radius = action.radius,
    })
    self.actionButton = button
    if self.animated and self.entry ~= nil and not self.entry.finished then
        button:setVisible(false)
    end
    self:add(button)
    self:_layout()
    return self
end

--- Measures the blocks and places the action button. The bottom is centred in
--- the widget height; with `h <= 0` the widget grows to fit its content and
--- keeps doing so after later text changes.
function EmptyState:_layout()
    local maxTextW = math.max(20, self.w - self.padding * 2)

    local titleH = 0
    if self.title ~= "" then
        self.titleStyle.maxWidth = maxTextW
        titleH = select(2, Pallid.UI.measureText(self.title, self.titleStyle))
    end

    local descriptionH = 0
    if self.description ~= "" then
        self.descriptionStyle.maxWidth = maxTextW
        descriptionH = select(2, Pallid.UI.measureText(self.description, self.descriptionStyle))
    end

    local iconH = self.showIcon and math.max(0, self.iconSize) or 0
    local actionH = self.actionButton ~= nil and self.actionButton.h or 0

    local hasIcon = iconH > 0
    local hasTitle = titleH > 0
    local hasDesc = descriptionH > 0
    local hasAction = actionH > 0
    -- The action keeps the double gap only when the description is present;
    -- otherwise the measured total would not match the placement below.
    local actionGap = hasDesc and self.spacing * 2 or self.spacing

    local total = 0
    if hasIcon then
        total = total + iconH
    end
    if hasTitle then
        total = total + (hasIcon and self.spacing or 0) + titleH
    end
    if hasDesc then
        total = total + ((hasIcon or hasTitle) and self.spacing or 0) + descriptionH
    end
    if hasAction then
        total = total + ((hasIcon or hasTitle or hasDesc) and actionGap or 0) + actionH
    end

    if self.autoHeight then
        self.h = total + self.padding * 2
    end

    local cursor = math.max(0, (self.h - total) * 0.5)
    self._iconY = 0
    self._titleY = 0
    self._descriptionY = 0

    local placed = false
    if hasIcon then
        self._iconY = cursor
        cursor = cursor + iconH
        placed = true
    end
    if hasTitle then
        if placed then
            cursor = cursor + self.spacing
        end
        self._titleY = cursor
        cursor = cursor + titleH
        placed = true
    end
    if hasDesc then
        if placed then
            cursor = cursor + self.spacing
        end
        self._descriptionY = cursor
        cursor = cursor + descriptionH
        placed = true
    end
    if hasAction then
        if placed then
            cursor = cursor + actionGap
        end
        self.actionButton:setBounds(
            math.floor((self.w - self.actionButton.w) * 0.5),
            math.floor(cursor),
            self.actionButton.w,
            self.actionButton.h
        )
    end
end

--- Fallback glyph used only when the packaged default texture cannot load.
--- @param el ISUIElement Host element used for drawing.
--- @param ix number Icon X coordinate.
--- @param iy number Icon Y coordinate.
--- @param size number Size in pixels.
--- @param color PallidColor Color to use.
function EmptyState:drawDefaultIcon(el, ix, iy, size, color)
    local inset = math.max(4, size * 0.2)
    Pallid.UI.roundedBorder(el, ix, iy, size, size, 4, 1, color)
    Pallid.UI.line(el, ix + inset, iy + size * 0.42, ix + size - inset, iy + size * 0.42, 1, color)
    Pallid.UI.line(el, ix + inset, iy + size * 0.62, ix + size - inset, iy + size * 0.62, 1, color)
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element used for drawing.
function EmptyState:drawSelf(el)
    local ox, oy = self:originX(), self:originY()
    local alpha = self.animated and self.entry.alpha or 1
    local dy = self.animated and self.entry.dy or 0
    local iconAlpha = alpha
    if self.iconFloat ~= nil then
        iconAlpha = iconAlpha * self.iconFloat.alpha
    end

    if self.showIcon and self.iconSize > 0 then
        local size = self.iconSize
        local ix = ox + (self.w - size) * 0.5
        local iy = oy + self._iconY + dy
        local color = Pallid.UI.Anim.alpha(self:shade(self.iconColor or Pallid.UI.Color.textMuted), iconAlpha)
        if self.iconTexture ~= nil then
            Pallid.UI.texture(el, self.iconTexture, ix, iy, size, size, color, ICON_OPTS)
        elseif self.iconName ~= nil then
            if not Pallid.UI.icon(el, self.iconName, ix, iy, size, color) then
                self:drawDefaultIcon(el, ix, iy, size, color)
            end
        else
            self:drawDefaultIcon(el, ix, iy, size, color)
        end
    end

    if self.title ~= "" then
        local base = self.titleStyle.color
        self.titleStyle.color = Pallid.UI.Anim.alpha(self:shade(base), alpha)
        Pallid.UI.text(el, self.title, ox + self.w * 0.5, oy + self._titleY + dy, self.titleStyle)
        self.titleStyle.color = base
    end

    if self.description ~= "" then
        local base = self.descriptionStyle.color
        self.descriptionStyle.color = Pallid.UI.Anim.alpha(self:shade(base), alpha)
        Pallid.UI.text(el, self.description, ox + self.w * 0.5, oy + self._descriptionY + dy, self.descriptionStyle)
        self.descriptionStyle.color = base
    end
end
