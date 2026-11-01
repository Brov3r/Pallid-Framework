require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/geometry"
require "pallid/ui/api/clip"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local RECT_SHAPE = Pallid.UI.Shape.rect()

local PADDING = 14
local MIN_WIDTH = 180
local MAX_WIDTH = 360
local FADE_IN = 0.18
local FADE_OUT = 0.35
local GAP = 6
local MAX_TEXT_LINES = 3
local ICON_GAP = 8
local RADIUS = 8
local PROGRESS_HEIGHT = 4
local PROGRESS_SHAPE_HEIGHT = RADIUS * 2
local PROGRESS_CORNERS = { tl = 0, tr = 0, br = RADIUS, bl = RADIUS }
local PROGRESS_FALLBACK_RADIUS = 2
local RIGHT_INSET = 14
local PROGRESS_GAP = 2
local ICON_PAD = 4
local ICON_RADIUS = 6
local TITLE_GAP = 2
local ICON_OPTS = { mode = "fit" }

local CORNERS = {
    ["top-right"]    = true,
    ["top-left"]     = true,
    ["bottom-right"] = true,
    ["bottom-left"]  = true,
}

--- @param corner string|nil Requested corner.
--- @return string corner Valid corner, defaults to "top-right".
local function validCorner(corner)
    if CORNERS[corner] then
        return corner
    end
    return "top-right"
end

--- Short self-dismissing notification.
---
--- At most `Toast.MAX_VISIBLE` (10) toasts are on screen; the rest wait in a
--- per-root queue and slide in as older ones fade out. Each corner owns an
--- independent stack. Text wraps to three lines and is ellipsised beyond that,
--- and the bottom track shows the remaining lifetime.
--- @class PallidToast : PallidWidget
--- @field text string Notification body; wrapped to at most three lines.
--- @field title string Bold first line; empty hides it.
--- @field duration number Seconds the toast stays fully visible.
--- @field age number Seconds since the toast was last shown.
--- @field alpha number 0..1 fade factor applied to the whole toast.
--- @field corner "top-right"|"top-left"|"bottom-right"|"bottom-left" Screen corner the stack is anchored to.
--- @field margin number Distance from the screen edges in pixels.
--- @field accent PallidColor Accent colour of the icon and the lifetime track.
--- @field icon string|nil Registered icon name or texture path; nil hides it.
--- @field showProgress boolean True draws the bottom lifetime track.
local Toast = Widgets.class("Toast")

--- Maximum number of simultaneously visible toasts.
Toast.MAX_VISIBLE = 10

local function ensureState(root)
    local state = root._pallidToastState
    if state == nil then
        state = { active = {}, queue = {} }
        root._pallidToastState = state
    end
    return state
end

--- @param root PallidWidget Root whose box and state anchor the stacks.
local function relayout(root)
    local state = root._pallidToastState
    if state == nil then
        return
    end
    local active = state.active
    -- Every corner owns its own stack: a toast on the left never reserves the
    -- height of a toast on the right, and vice versa.
    local topLeft, topRight = 0, 0
    local bottomLeft, bottomRight = 0, 0
    local width = root.w or 0
    local height = root.h or 0

    for i = 1, #active do
        local toast = active[i]
        local corner = toast.corner
        local margin = toast.margin
        if corner == "top-left" then
            toast._targetX = margin
            toast._targetY = margin + topLeft
            topLeft = topLeft + toast.h + GAP
        elseif corner == "bottom-left" then
            toast._targetX = margin
            toast._targetY = height - toast.h - margin - bottomLeft
            bottomLeft = bottomLeft + toast.h + GAP
        elseif corner == "bottom-right" then
            toast._targetX = width - toast.w - margin
            toast._targetY = height - toast.h - margin - bottomRight
            bottomRight = bottomRight + toast.h + GAP
        else
            toast._targetX = width - toast.w - margin
            toast._targetY = margin + topRight
            topRight = topRight + toast.h + GAP
        end
    end
end

--- @param root PallidWidget Root whose queue is drained into the visible stack.
local function activateQueued(root)
    local state = ensureState(root)
    local entered = {}
    while #state.active < Toast.MAX_VISIBLE and #state.queue > 0 do
        local toast = table.remove(state.queue, 1)
        toast.age = 0
        toast.alpha = 0
        toast.visible = true
        toast._dead = false
        toast._announced = true
        state.active[#state.active + 1] = toast
        entered[#entered + 1] = toast
        if toast.parent ~= root then
            root:add(toast)
        end
    end
    relayout(root)
    -- Toasts fly in from their own side at exactly the height of their slot,
    -- instead of appearing in the middle of the screen and sliding down.
    for i = 1, #entered do
        local toast = entered[i]
        local right = string.sub(toast.corner, -5) == "right"
        toast.x = right and ((root.w or 0) + 8) or (-(toast.w or 0) - 8)
        toast.y = toast._targetY or toast.y
        toast.alpha = 0
    end
end

--- Creates a new `Toast` instance.
--- @param text string|nil Notification body; empty text is allowed.
--- @param opts table|nil Appearance and timing overrides.
--- @field opts.title string|nil Bold first line; nil or empty hides it.
--- @field opts.duration number|nil Seconds the toast stays fully visible, defaults to 3.
--- @field opts.width number|nil Fixed width; nil measures the text up to 360.
--- @field opts.height number|nil Overrides the measured height.
--- @field opts.margin number|nil Distance from the edges, defaults to 18.
--- @field opts.corner "top-right"|"top-left"|"bottom-right"|"bottom-left"|nil Stack corner, defaults to "top-right".
--- @field opts.background PallidColor|nil Panel fill; defaults to the elevated surface token.
--- @field opts.border PallidColor|nil Panel border; defaults to the border token.
--- @field opts.textColor PallidColor|nil Body text colour; defaults to muted when a title is set.
--- @field opts.titleColor PallidColor|nil Title colour; defaults to textPrimary.
--- @field opts.accent PallidColor|nil Icon and lifetime track colour.
--- @field opts.icon string|nil Registered icon name or a texture path.
--- @field opts.iconSize number|nil Icon size in pixels, defaults to 18.
--- @field opts.iconColor PallidColor|nil Icon tint, defaults to the accent.
--- @field opts.showProgress boolean|nil Draws the bottom lifetime track; defaults to true.
--- @field opts.font UIFont|string|nil Body font.
--- @return PallidToast toast New hidden toast; call `show` to display it.
function Toast.new(text, opts)
    opts = opts or {}
    local self = setmetatable({}, Toast)

    self.duration = opts.duration or 3
    self.margin = opts.margin or 18
    self.corner = validCorner(opts.corner)
    self.accent = opts.accent or Pallid.UI.Color.primary
    self.font = opts.font or Pallid.UI.Fonts.small
    self.title = opts.title or ""
    self.fixedWidth = opts.width
    self.fixedHeight = opts.height
    self.autoWidth = opts.width == nil
    self.icon = opts.icon
    self.iconSize = opts.iconSize or 18
    self.iconColor = opts.iconColor or self.accent
    self.showProgress = opts.showProgress ~= false

    self:init(0, 0, 0, 0)
    -- Toasts are passive: without this they would steal hover from whatever
    -- sits underneath them for their whole lifetime.
    self.hittable = false

    self.fill = opts.background or Pallid.UI.Color.surfaceElevated
    self.borderColor = opts.border or Pallid.UI.Color.border
    self._autoBodyColor = opts.textColor == nil
    self.textColor = opts.textColor or ((self.title ~= "" and Pallid.UI.Color.textMuted) or Pallid.UI.Color.textPrimary)
    self.style = {
        font = self.font,
        color = self.textColor,
        alignH = "left",
        alignV = "middle",
        wrap = true,
    }
    self.titleStyle = {
        font = self.font,
        color = opts.titleColor or Pallid.UI.Color.textPrimary,
        alignH = "left",
        alignV = "top",
        bold = true,
        ellipsis = "...",
        maxLines = 1,
        lineSpacing = 1,
    }
    self._textTint = { r = 1, g = 1, b = 1, a = 1 }
    self._titleTint = { r = 1, g = 1, b = 1, a = 1 }
    self._fillTint = { r = 0, g = 0, b = 0, a = 1 }
    self._borderTint = { r = 0, g = 0, b = 0, a = 1 }
    self._accentTint = { r = 0, g = 0, b = 0, a = 1 }
    self._trackTint = { r = 0, g = 0, b = 0, a = 1 }
    self._iconTint = { r = 1, g = 1, b = 1, a = 1 }
    self._iconBgTint = { r = 0, g = 0, b = 0, a = 1 }

    self.age = 0
    self.alpha = 0
    self.visible = false
    self._dead = false
    self.isToast = true
    self._targetX = 0
    self._targetY = 0
    self._remaining = 1

    self:setText(text or "")
    return self
end

--- Factory shortcut for `Toast.new`.
--- @param text string|nil Notification body; empty text is allowed.
--- @param opts table|nil Appearance and timing overrides; see `Toast.new`.
--- @return PallidToast toast New hidden toast.
function Widgets.toast(text, opts)
    return Toast.new(text, opts)
end

--- Measures the title and body, choosing a width that keeps the body within
--- three lines and reserving room for the lifetime track.
--- @param text string Body text to wrap and measure.
function Toast:_measure(text)
    local iconWidth = self.icon ~= nil and (self.iconSize + ICON_PAD * 2 + ICON_GAP) or 0
    local maxTextW = MAX_WIDTH - PADDING * 2 - RIGHT_INSET - iconWidth
    local measureStyle = self._measureStyle
    if measureStyle == nil then
        measureStyle = {
            font = self.font,
            wrap = true,
            maxLines = MAX_TEXT_LINES,
            ellipsis = "...",
            lineSpacing = 1,
        }
        self._measureStyle = measureStyle
    end
    measureStyle.maxWidth = maxTextW

    local bodyW, bodyH = 0, 0
    if text ~= "" then
        bodyW, bodyH = Pallid.UI.measureText(text, measureStyle)
    end

    local titleW, titleH = 0, 0
    if self.title ~= "" then
        self.titleStyle.maxWidth = maxTextW
        titleW, titleH = Pallid.UI.measureText(self.title, self.titleStyle)
    end

    local textW = math.max(bodyW, titleW)
    local contentH = titleH + bodyH
    if titleH > 0 and bodyH > 0 then
        contentH = contentH + TITLE_GAP
    end

    local hasProgress = self.showProgress and self.duration > 0
    local bottomPad = PADDING + (hasProgress and (PROGRESS_HEIGHT + PROGRESS_GAP) or 0)
    local w = self.fixedWidth or math.max(MIN_WIDTH, math.min(MAX_WIDTH, textW + PADDING * 2 + RIGHT_INSET + iconWidth))
    local h = self.fixedHeight or math.max(34, contentH + PADDING + bottomPad, self.iconSize + PADDING + bottomPad)
    self.w = w
    self.h = h
    self.hasProgress = hasProgress
    self._iconX = PADDING + ICON_PAD
    self._textX = PADDING + iconWidth

    local textMax = math.max(1, w - PADDING * 2 - RIGHT_INSET - iconWidth)
    self.style.maxWidth = textMax
    self.style.maxLines = MAX_TEXT_LINES
    self.style.ellipsis = "..."
    self.style.lineSpacing = 1
    self.titleStyle.maxWidth = textMax
    self.titleStyle.maxLines = 1
    self.titleStyle.ellipsis = "..."

    local lineHeight = getTextManager():MeasureStringY(self.font, "Ag")
    self.lineCount = math.max(1, math.min(MAX_TEXT_LINES, math.ceil(bodyH / math.max(1, lineHeight))))

    local availTop = PADDING
    local availH = math.max(1, h - PADDING - bottomPad)
    local blockTop = availTop + (availH - contentH) * 0.5
    if blockTop < availTop then
        blockTop = availTop
    end

    if self.title ~= "" then
        self.titleStyle.alignV = "top"
        self.style.alignV = "top"
        self._titleY = blockTop
        self._textY = blockTop + titleH + (bodyH > 0 and TITLE_GAP or 0)
    else
        self._titleY = 0
        if self.lineCount > 1 then
            self.style.alignV = "top"
            self._textY = blockTop
        else
            self.style.alignV = "middle"
            self._textY = availTop + availH * 0.5
        end
    end

    self._iconY = blockTop + (contentH - self.iconSize) * 0.5
    if self._iconY < availTop then
        self._iconY = availTop
    end
end

--- Replaces the body and re-runs the layout, so a visible toast reflows right
--- away instead of keeping the width of its previous text.
--- @param text string New notification body.
--- @return PallidToast self For chaining.
function Toast:setText(text)
    self.text = text or ""
    self:_measure(self.text)
    if self.root ~= nil and self.visible then
        relayout(self.root)
    end
    return self
end

--- Replaces the bold title and re-runs the layout, so a visible toast reflows
--- right away.
--- @param title string New bold first line; empty hides it.
--- @return PallidToast self For chaining.
function Toast:setTitle(title)
    self.title = title or ""
    if self._autoBodyColor then
        self.textColor = self.title ~= "" and Pallid.UI.Color.textMuted or Pallid.UI.Color.textPrimary
    end
    self:_measure(self.text)
    if self.root ~= nil and self.visible then
        relayout(self.root)
    end
    return self
end

--- Sets the icon.
--- @param icon string|nil Registered icon name or a texture path. Nil removes it.
--- @return PallidToast self For chaining.
function Toast:setIcon(icon)
    self.icon = icon
    self:_measure(self.text)
    if self.root ~= nil and self.visible then
        relayout(self.root)
    end
    return self
end

--- Sets the accent color.
--- @param color PallidColor New colour for the icon and the lifetime track.
--- @return PallidToast self For chaining.
function Toast:setAccent(color)
    self.accent = color
    return self
end

--- Shows the toast over `root`. Additional toasts above the visible limit are
--- queued. Calling show again on a visible toast restarts its timer without
--- flashing it back to zero alpha.
--- @param root PallidWidget Root whose box anchors the corner stack.
--- @param text string|nil New body; nil keeps the current text.
--- @param opts table|nil Optional overrides; reads `corner` and `title`.
--- @return PallidToast self For chaining.
function Toast:show(root, text, opts)
    opts = opts or {}
    if root == nil then
        return self
    end
    if opts.title ~= nil then
        self:setTitle(opts.title)
    end
    if text ~= nil then
        self:setText(text)
    end
    if opts.corner ~= nil then
        self.corner = validCorner(opts.corner)
    end

    if self.root ~= nil and self.root ~= root then
        self:_detach(self.root)
        self:_removeFromRoot()
    end
    self.root = root
    self.age = 0
    self._remaining = 1
    self._expired = false
    self._dead = false

    local state = ensureState(root)
    -- Remove an older copy from the queue: re-showing refreshes it.
    for i = #state.queue, 1, -1 do
        if state.queue[i] == self then
            table.remove(state.queue, i)
        end
    end
    local active = false
    for i = 1, #state.active do
        if state.active[i] == self then
            active = true
            break
        end
    end
    if active then
        self.visible = true
        -- Already on screen: keep it visible instead of replaying the fade-in.
        self.alpha = 1
    else
        -- A queued toast is not a child yet, so it must not be drawn.
        self.visible = false
        self.alpha = 0
        state.queue[#state.queue + 1] = self
    end
    activateQueued(root)
    return self
end

--- Removes this toast from a root's active/queue lists without touching the
--- child tree. Used when a toast is re-shown on another root.
--- @param root PallidWidget Root to detach the toast from.
function Toast:_detach(root)
    local state = root._pallidToastState
    if state == nil then
        return
    end
    for i = #state.active, 1, -1 do
        if state.active[i] == self then
            table.remove(state.active, i)
        end
    end
    for i = #state.queue, 1, -1 do
        if state.queue[i] == self then
            table.remove(state.queue, i)
        end
    end
end

--- Detaches the toast from the child tree and forgets its root.
function Toast:_removeFromRoot()
    local root = self.root
    if root ~= nil and root.children ~= nil then
        for i = #root.children, 1, -1 do
            if root.children[i] == self then
                table.remove(root.children, i)
            end
        end
    end
    self.parent = nil
    self.root = nil
end

--- Marks the toast dead and promotes the next queued one. The child itself is
--- pruned by the root's update loop, which is why structural changes stay out
--- of the draw traversal.
--- @param root PallidWidget Root that owns the toast.
function Toast:_finish(root)
    local state = root._pallidToastState
    if state ~= nil then
        for i = #state.active, 1, -1 do
            if state.active[i] == self then
                table.remove(state.active, i)
            end
        end
    end
    self.visible = false
    self._expired = false
    self._dead = true
    activateQueued(root)
end

--- Dismisses immediately and promotes the next queued toast.
--- @return PallidToast self For chaining.
function Toast:close()
    if self.root ~= nil and not self._dead then
        self:_finish(self.root)
    elseif not self._dead then
        self.visible = false
        self._dead = true
    end
    return self
end

--- Advances the lifetime, the fade, the slide toward the slot and the lifetime
--- track. Per-frame so the toast fades smoothly; the actual removal stays on
--- the game tick.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function Toast:onAnimate(now, dt)
    local root = self.root
    if root == nil or not self.visible then
        return
    end

    self.age = self.age + math.max(0, dt)
    if self.duration > 0 then
        local remaining = 1 - self.age / self.duration
        if remaining < 0 then
            remaining = 0
        elseif remaining > 1 then
            remaining = 1
        end
        self._remaining = remaining
    else
        self._remaining = 0
    end

    local total = self.duration + FADE_OUT
    if self.age >= total then
        -- Structural change (list removal, queue promotion) is deferred to
        -- onUpdate so the tree is never mutated while it is being traversed.
        self._expired = true
        return
    end

    if self.age < FADE_IN then
        self.alpha = self.age / FADE_IN
    elseif self.age <= self.duration then
        self.alpha = 1
    else
        self.alpha = 1 - (self.age - self.duration) / FADE_OUT
    end

    -- Ease toward the slot computed by relayout(): dismissal of a neighbour
    -- closes the gap smoothly instead of snapping.
    self.x = Widgets.approach(self.x, self._targetX or self.x, 16, dt)
    self.y = Widgets.approach(self.y, self._targetY or self.y, 16, dt)
end

--- Removes the toast once its animation has run out.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous tick, 0..0.1.
function Toast:onUpdate(now, dt)
    local root = self.root
    if root == nil or not self.visible then
        return
    end
    if self._expired then
        self._expired = false
        self:_finish(root)
    end
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the tree is rendered into.
function Toast:drawSelf(el)
    local x, y = self:originX(), self:originY()
    local a = math.max(0, math.min(1, self.alpha))
    if a <= 0.01 then
        return
    end

    local fill = self._fillTint
    fill.r, fill.g, fill.b, fill.a = self.fill.r, self.fill.g, self.fill.b, self.fill.a * a
    local border = self._borderTint
    border.r, border.g, border.b, border.a = self.borderColor.r, self.borderColor.g, self.borderColor.b, self.borderColor.a * a

    Pallid.UI.roundedRect(el, x, y, self.w, self.h, RADIUS, fill)
    Pallid.UI.roundedBorder(el, x, y, self.w, self.h, RADIUS, 1, border)

    if self.icon ~= nil then
        local chip = self._iconBgTint
        chip.r, chip.g, chip.b = self.accent.r, self.accent.g, self.accent.b
        chip.a = 0.16 * a
        local chipSize = self.iconSize + ICON_PAD * 2
        Pallid.UI.roundedRect(el, x + self._iconX - ICON_PAD, y + self._iconY - ICON_PAD,
            chipSize, chipSize, ICON_RADIUS, chip)

        local icon = self._iconTint
        icon.r, icon.g, icon.b = self.iconColor.r, self.iconColor.g, self.iconColor.b
        icon.a = (self.iconColor.a or 1) * a
        local iconX = x + self._iconX
        local iconY = y + self._iconY
        if string.find(self.icon, "/", 1, true) ~= nil then
            Pallid.UI.texture(el, Pallid.UI.Textures.get(self.icon), iconX, iconY,
                self.iconSize, self.iconSize, icon, ICON_OPTS)
        else
            Pallid.UI.icon(el, self.icon, iconX, iconY, self.iconSize, icon)
        end
    end

    if self.title ~= "" then
        local title = self._titleTint
        title.r, title.g, title.b = self.titleStyle.color.r, self.titleStyle.color.g, self.titleStyle.color.b
        title.a = (self.titleStyle.color.a or 1) * a
        local base = self.titleStyle.color
        self.titleStyle.color = title
        Pallid.UI.text(el, self.title, x + self._textX, y + self._titleY, self.titleStyle)
        self.titleStyle.color = base
    end

    local text = self._textTint
    text.r, text.g, text.b = self.textColor.r, self.textColor.g, self.textColor.b
    text.a = (self.textColor.a or 1) * a
    self.style.color = text
    Pallid.UI.text(el, self.text, x + self._textX, y + self._textY, self.style)
    self.style.color = self.textColor

    -- Lifetime track: edge to edge and flush with the bottom. The bar is drawn
    -- as the bottom slice of a card-radius shape, so its corners follow the
    -- card exactly instead of poking through the rounded bottom.
    if self.hasProgress then
        local track = self._trackTint
        track.r = Pallid.UI.Color.border.r
        track.g = Pallid.UI.Color.border.g
        track.b = Pallid.UI.Color.border.b
        track.a = a
        local trackY = y + self.h - PROGRESS_HEIGHT
        local entered = Pallid.UI.clip(el, RECT_SHAPE, x, trackY, self.w, PROGRESS_HEIGHT)
        local shapeH = entered and PROGRESS_SHAPE_HEIGHT or PROGRESS_HEIGHT
        local shapeY = y + self.h - shapeH
        local radius = entered and PROGRESS_CORNERS or PROGRESS_FALLBACK_RADIUS
        Pallid.UI.roundedRect(el, x, shapeY, self.w, shapeH, radius, track)

        local progressW = self.w * self._remaining
        if progressW > 0.5 then
            local progress = self._accentTint
            progress.r = self.accent.r
            progress.g = self.accent.g
            progress.b = self.accent.b
            progress.a = a
            Pallid.UI.roundedRect(el, x, shapeY, progressW, shapeH, radius, progress)
        end
        if entered then
            Pallid.UI.clipEnd(el)
        end
    end
end
