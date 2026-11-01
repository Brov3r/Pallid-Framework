require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/geometry"
require "pallid/ui/api/clip"
require "pallid/ui/api/textures"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local RECT_SHAPE = Pallid.UI.Shape.rect()
local ARROW_W = 20
local MIN_TAB_W = 44
local MAX_TAB_W = 210
local TAB_PAD = 14
local TAB_ICON = 14
local TAB_ICON_GAP = 4
local TAB_INSET = 2
local SCROLL_SPEED = 18
local SCROLL_EPSILON = 0.5
local ICON_OPTS = { mode = "fit" }
local TAB_CLEAR = { r = 0, g = 0, b = 0, a = 0 }

local ICON_DIR = "media/assets/ui/pallid/icons/"
local ARROW_ICONS = {
    left  = "pallid_tab_arrow_left",
    right = "pallid_tab_arrow_right",
    up    = "pallid_tab_arrow_up",
    down  = "pallid_tab_arrow_down",
}
Pallid.UI.Textures.registerIcon(ARROW_ICONS.left, ICON_DIR .. "arrow-left.png")
Pallid.UI.Textures.registerIcon(ARROW_ICONS.right, ICON_DIR .. "arrow-right.png")
Pallid.UI.Textures.registerIcon(ARROW_ICONS.up, ICON_DIR .. "arrow-up.png")
Pallid.UI.Textures.registerIcon(ARROW_ICONS.down, ICON_DIR .. "arrow-down.png")

--- Tabs with a content area. `position = "top"` puts a flat modern strip above
--- the content, `"left"` puts it beside it. Only the active tab is drawn and
--- hit-tested.
---
--- The strip scrolls smoothly when the tabs do not fit: arrow buttons appear at
--- both ends and the mouse wheel adds to the scroll target. Only the visible
--- tabs are painted (prefix widths + binary search), so hundreds of tabs cost
--- about the same as a dozen.
---
--- Each tab may carry an icon in its table: `{ title, content, icon,
--- iconSide, iconColor }`. A nil title with an icon produces an icon-only tab.
---
--- There is one visual style: transparent inactive tabs, an animated hover fill,
--- a soft active pill with a faint outline. The fields below can be replaced on
--- an instance (or the drawing can be overridden) for a custom look.
--- @class PallidTabPanel : PallidWidget
--- @field tabs table[] Tab entries: { title, content, icon?, iconSide?, iconColor? }.
--- @field active integer Index of the visible page.
--- @field position "top"|"left" Strip orientation.
--- @field tabSize number Strip height (top) or width (left).
--- @field contentPadding number Inner padding around the active page.
--- @field scrollable boolean Whether the strip may scroll.
--- @field hoverIndex integer Tab under the cursor, 0 when none.
--- @field onChange fun(panel: PallidTabPanel, index: integer)|nil
--- @field tabFill PallidColor Inactive tab fill.
--- @field tabHover PallidColor Hovered tab fill.
--- @field tabActive PallidColor Active tab fill.
--- @field tabAccent PallidColor Active tab outline colour.
--- @field tabRadius number Tab pill corner radius.
--- @field fill PallidColor Panel background behind the content.
--- @field borderColor PallidColor Separator between the strip and the content.
local TabPanel = Widgets.class("TabPanel")

--- Resolves a tab icon once per layout. A value containing a slash is a texture
--- path; anything else is a name registered with Pallid.UI.Textures.
--- @param tab table Tab entry.
local function resolveTabIcon(tab)
    tab._iconTexture = nil
    tab._iconRegion = nil
    tab._iconName = nil
    tab._hasIcon = false
    local icon = tab.icon
    if type(icon) ~= "string" or icon == "" then
        return
    end
    if string.find(icon, "/", 1, true) ~= nil then
        tab._iconRegion = Pallid.UI.Textures.getRegion(icon)
        tab._iconTexture = tab._iconRegion == nil and Pallid.UI.Textures.get(icon) or nil
        tab._hasIcon = tab._iconRegion ~= nil or tab._iconTexture ~= nil
    else
        tab._iconName = icon
        tab._iconRegion = Pallid.UI.Textures.getIconRegion(icon)
        tab._hasIcon = tab._iconRegion ~= nil or Pallid.UI.Textures.hasIcon(icon)
    end
end

--- @param color PallidColor Source colour.
--- @return PallidColor copy Independent table with the same channels.
local function copyColor(color)
    return { r = color.r, g = color.g, b = color.b, a = color.a or 1 }
end

--- Creates a new `TabPanel` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param tabs table[] Each: { title, content, icon?, iconSide?, iconColor? }.
--- @param opts table|nil Optional behaviour and appearance.
--- @field opts.position "top"|"left"|nil Defaults to "top".
--- @field opts.tabSize number|nil Strip height (top) or width (left). Defaults to 28/110.
--- @field opts.active integer|nil Index of the visible page.
--- @field opts.scrollable boolean|nil Defaults to true.
--- @field opts.minTabWidth number|nil Minimum tab width, defaults to 44.
--- @field opts.maxTabWidth number|nil Maximum tab width, defaults to 210.
--- @field opts.tabPadding number|nil Horizontal padding inside a tab, defaults to 14.
--- @field opts.contentPadding number|nil Inner padding around the active page, defaults to 4.
--- @field opts.background PallidColor|nil Panel fill.
--- @field opts.border PallidColor|nil Separator colour.
--- @field opts.tabFill PallidColor|nil Inactive tab fill.
--- @field opts.tabHover PallidColor|nil Hovered tab fill.
--- @field opts.tabActive PallidColor|nil Active tab fill.
--- @field opts.tabAccent PallidColor|nil Active tab outline colour.
--- @field opts.tabRadius number|nil Pill radius, defaults to 4.
--- @field opts.onChange fun(panel: PallidTabPanel, index: integer)|nil
--- @return PallidTabPanel panel New tab panel instance.
function TabPanel.new(x, y, w, h, tabs, opts)
    opts = opts or {}
    local self = setmetatable({}, TabPanel)
    self:init(x, y, w, h)

    self.tabs = tabs or {}
    local count = #self.tabs
    for i = 1, count do
        local content = self.tabs[i].content
        if content ~= nil then
            content.parent = self
        end
        self.tabs[i]._hoverT = 0
        self.tabs[i]._activeT = 0
    end

    self.position = opts.position == "left" and "left" or "top"
    self.tabSize = math.max(20, opts.tabSize or (self.position == "top" and 28 or 110))
    self.contentPadding = math.max(0, opts.contentPadding or 4)
    self.active = math.max(1, math.min(opts.active or 1, math.max(1, count)))
    -- Pages outside the active tab are not drawn and not hit-tested. Marking
    -- them invisible keeps external hit tests (drop zones, drag targets) from
    -- reaching controls the user cannot see.
    for i = 1, count do
        local content = self.tabs[i].content
        if content ~= nil then
            content.visible = (i == self.active)
        end
    end
    self.onChange = opts.onChange
    self.scrollable = opts.scrollable ~= false
    self.minTabWidth = opts.minTabWidth or MIN_TAB_W
    self.maxTabWidth = math.max(self.minTabWidth, opts.maxTabWidth or MAX_TAB_W)
    self.tabPadding = opts.tabPadding or TAB_PAD
    self._scroll = 0
    self._scrollTarget = 0
    self._tabW = {}
    self._tabX = {}
    self._tabsDirty = true
    self._showArrows = false
    self._stripX = 0
    self._stripY = 0
    self._stripW = 1
    self._stripH = 1
    self._maxScroll = 0
    self.hoverIndex = 0
    self._hoverArrow = nil

    for i = 1, count do
        self.tabs[i]._activeT = (i == self.active) and 1 or 0
    end

    self.fill = copyColor(opts.background or Pallid.UI.Color.surface)
    self.borderColor = copyColor(opts.border or Pallid.UI.Color.border)
    self.tabFill = copyColor(opts.tabFill or TAB_CLEAR)
    self.tabHover = copyColor(opts.tabHover or Pallid.UI.Color.accentSoft)
    self.tabActive = copyColor(opts.tabActive or Pallid.UI.Color.primarySoft)
    self.tabAccent = copyColor(opts.tabAccent or Pallid.UI.Color.primaryStrong)
    self.tabRadius = opts.tabRadius or 4
    self.activeColor = self.tabAccent
    self.arrowColor = copyColor(Pallid.UI.Color.textPrimary)
    self.arrowDisabled = { r = Pallid.UI.Color.textDisabled.r, g = Pallid.UI.Color.textDisabled.g, b = Pallid.UI.Color.textDisabled.b, a = 0.55 }
    self.arrowBg = { r = Pallid.UI.Color.surfaceMuted.r, g = Pallid.UI.Color.surfaceMuted.g, b = Pallid.UI.Color.surfaceMuted.b, a = 0.62 }
    self.arrowHoverBg = { r = Pallid.UI.Color.primarySoft.r, g = Pallid.UI.Color.primarySoft.g, b = Pallid.UI.Color.primarySoft.b, a = 0.95 }
    self.style = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.textMuted,
        alignH = "left",
        alignV = "middle",
    }
    self.activeStyle = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.textPrimary,
        alignH = "left",
        alignV = "middle",
    }
    self:layout()
    return self
end

--- Factory shortcut for `TabPanel.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param tabs table[] Tab entries.
--- @param opts table|nil Optional behaviour and appearance; see `TabPanel.new`.
--- @return PallidTabPanel panel New tab panel instance.
function Widgets.tabPanel(x, y, w, h, tabs, opts)
    return TabPanel.new(x, y, w, h, tabs, opts)
end

--- Content rectangle in widget-local coordinates, inset by `contentPadding`.
--- @return number x Left edge of the page area.
--- @return number y Top edge of the page area.
--- @return number w Page width after padding.
--- @return number h Page height after padding.
function TabPanel:contentRect()
    local pad = self.contentPadding or 0
    if self.position == "top" then
        return pad, self.tabSize + pad,
            math.max(0, self.w - pad * 2), math.max(0, self.h - self.tabSize - pad * 2)
    end
    return self.tabSize + pad, pad,
        math.max(0, self.w - self.tabSize - pad * 2), math.max(0, self.h - pad * 2)
end

--- Recomputes tab sizes, prefix positions, the strip viewport and the scroll
--- limits. Icons are resolved here, so call `refreshTabs` after changing one.
function TabPanel:relayoutTabs()
    local count = #self.tabs
    local widths, prefix = {}, {}
    local manager = getTextManager()
    local font = self.style.font
    local total = 0

    for i = 1, count do
        local tab = self.tabs[i]
        local title = tab.title or ""
        resolveTabIcon(tab)
        local iconW = tab._hasIcon and TAB_ICON or 0
        local gap = (iconW > 0 and title ~= "") and TAB_ICON_GAP or 0

        if self.position == "top" then
            local width = manager:MeasureStringX(font, title) + iconW + gap + self.tabPadding * 2
            width = math.max(self.minTabWidth, math.min(self.maxTabWidth, math.floor(width)))
            widths[i] = width
            prefix[i] = total
            total = total + width
        else
            local height = math.max(manager:MeasureStringY(font, title), iconW) + 10
            height = math.floor(math.max(22, math.min(46, height)))
            widths[i] = height
            prefix[i] = total
            total = total + height
        end
    end
    prefix[count + 1] = total

    if self.position == "top" then
        local available = self.w
        self._showArrows = self.scrollable and total > available
        self._stripX = self._showArrows and ARROW_W or 0
        self._stripY = 0
        self._stripW = math.max(1, available - self._stripX * 2)
        self._stripH = self.tabSize
        self._maxScroll = math.max(0, total - self._stripW)
    else
        local available = self.h
        self._showArrows = self.scrollable and total > available
        self._stripX = 0
        self._stripY = self._showArrows and ARROW_W or 0
        self._stripH = math.max(1, available - self._stripY * 2)
        self._stripW = self.tabSize
        self._maxScroll = math.max(0, total - self._stripH)
    end

    self._tabW = widths
    self._tabX = prefix
    self._tabsDirty = false

    local maxScroll = self._maxScroll or 0
    self._scroll = math.max(0, math.min(maxScroll, self._scroll))
    self._scrollTarget = math.max(0, math.min(maxScroll, self._scrollTarget or self._scroll))
end

--- Tab rectangle in widget-local coordinates.
--- @param index integer One-based tab index.
--- @return number x Left edge of the tab cell.
--- @return number y Top edge of the tab cell.
--- @return number w Width of the tab cell.
--- @return number h Height of the tab cell.
function TabPanel:tabRect(index)
    if self._tabsDirty then
        self:relayoutTabs()
    end
    if self.position == "top" then
        return self._stripX + (self._tabX[index] or 0) - self._scroll, 0,
            self._tabW[index] or self.minTabWidth, self.tabSize
    end
    return 0, self._stripY + (self._tabX[index] or 0) - self._scroll,
        self.tabSize, self._tabW[index] or 26
end

--- Sizes every page to the content rectangle.
function TabPanel:layout()
    local cx, cy, cw, ch = self:contentRect()
    for i = 1, #self.tabs do
        local content = self.tabs[i].content
        if content ~= nil then
            content:setBounds(cx, cy, cw, ch)
        end
    end
end

--- Updates the widget bounds.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidTabPanel self For chaining.
function TabPanel:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self._tabsDirty = true
    self:layout()
    self:relayoutTabs()
    self:ensureActiveVisible()
    return self
end

--- Marks the strip dirty after tab titles, icons or contents were changed.
--- @return PallidTabPanel self For chaining.
function TabPanel:refreshTabs()
    self._tabsDirty = true
    self:layout()
    self:relayoutTabs()
    self:ensureActiveVisible()
    self:_refreshHover()
    return self
end

--- Activates a tab and optionally notifies `onChange`.
--- @param index integer One-based tab index.
--- @param silent boolean|nil True skips the `onChange` callback.
--- @return PallidTabPanel self For chaining.
function TabPanel:setActive(index, silent)
    if index < 1 or index > #self.tabs or index == self.active then
        return self
    end
    -- A focused field inside the page being left (keybind capture, text input)
    -- must lose focus, otherwise it keeps receiving keys while hidden.
    local previous = self.tabs[self.active]
    local root = self:getRoot()
    local focused = root ~= nil and root.focused or nil
    if focused ~= nil and previous ~= nil and previous.content ~= nil then
        local node = focused
        while node ~= nil do
            if node == previous.content then
                focused:blur()
                break
            end
            node = node.parent
        end
    end
    -- A mouse capture inside the page being hidden (a keybind recording or a
    -- drag) would otherwise swallow the next press after the tab change.
    if root ~= nil and root.capture ~= nil and previous ~= nil and previous.content ~= nil then
        local node = root.capture
        while node ~= nil do
            if node == previous.content then
                root.capture = nil
                root.captureButton = nil
                root.captureOx, root.captureOy = nil, nil
                break
            end
            node = node.parent
        end
    end
    if previous ~= nil and previous.content ~= nil then
        previous.content.visible = false
    end
    self.active = index
    local tab = self.tabs[index]
    if tab ~= nil and tab.content ~= nil then
        tab.content.visible = true
    end
    self:ensureActiveVisible()
    if not silent and self.onChange ~= nil then
        self.onChange(self, index)
    end
    return self
end

--- Scrolls the strip so the active tab is fully visible. The scroll animates.
function TabPanel:ensureActiveVisible()
    if self._tabsDirty then
        self:relayoutTabs()
    end
    local index = self.active
    local start = self._tabX[index]
    if start == nil then
        return
    end
    local size = self._tabW[index] or 0
    local view = (self.position == "top") and self._stripW or self._stripH
    local target = self._scrollTarget or self._scroll
    if start < target then
        target = start
    elseif start + size > target + view then
        target = start + size - view
    end
    self._scrollTarget = math.max(0, math.min(self._maxScroll or 0, target))
end

--- Adds a delta to the smooth scroll target (positive scrolls forward).
--- @param delta number Pixels to scroll.
--- @return PallidTabPanel self For chaining.
function TabPanel:scrollBy(delta)
    if self._tabsDirty then
        self:relayoutTabs()
    end
    local target = (self._scrollTarget or self._scroll) + delta
    self._scrollTarget = math.max(0, math.min(self._maxScroll or 0, target))
    return self
end

--- Appends a tab. Inserting before the active tab keeps the same page open.
--- @param title string Tab title; an empty string leaves only the icon.
--- @param content PallidWidget|nil Page shown when the tab is active.
--- @param index integer|nil Insert position; appended by default.
--- @param icon string|nil Registered icon name or texture path.
--- @return PallidTabPanel self For chaining.
function TabPanel:addTab(title, content, index, icon)
    local count = #self.tabs
    index = math.max(1, math.min(index or (count + 1), count + 1))
    local tab = { title = title or "", content = content, icon = icon }
    table.insert(self.tabs, index, tab)
    if content ~= nil then
        content.parent = self
        content:_notifyAttached()
    end

    if count == 0 then
        self.active = index
    elseif index <= self.active then
        self.active = self.active + 1
    end
    if content ~= nil then
        content.visible = (index == self.active)
    end

    tab._hoverT = 0
    tab._activeT = (index == self.active) and 1 or 0
    self._tabsDirty = true
    self:layout()
    self:relayoutTabs()
    self:ensureActiveVisible()
    self:_refreshHover()
    return self
end

--- Removes a tab and keeps the active page sensible.
--- @param index integer One-based tab index.
--- @return PallidTabPanel self For chaining.
function TabPanel:removeTab(index)
    local tab = self.tabs[index]
    if tab == nil then
        return self
    end

    local oldActive = self.active
    local oldContent = self.tabs[oldActive] and self.tabs[oldActive].content
    if tab.content ~= nil then
        tab.content:_notifyDetached()
        tab.content.parent = nil
    end
    table.remove(self.tabs, index)

    if index < oldActive then
        self.active = oldActive - 1
    elseif index == oldActive then
        self.active = math.max(1, math.min(oldActive, #self.tabs))
    end
    local activeTab = self.tabs[self.active]
    if activeTab ~= nil and activeTab.content ~= nil then
        activeTab.content.visible = true
    end

    self._tabsDirty = true
    self:layout()
    self:relayoutTabs()
    self:ensureActiveVisible()
    self:_refreshHover()

    local newContent = self.tabs[self.active] and self.tabs[self.active].content
    if newContent ~= oldContent and self.onChange ~= nil then
        self.onChange(self, self.active)
    end
    return self
end

-- Drawing --------------------------------------------------------------------

local TAB_FILL = { r = 0, g = 0, b = 0, a = 1 }
local TAB_FILL2 = { r = 0, g = 0, b = 0, a = 1 }
local TAB_TEXT = { r = 1, g = 1, b = 1, a = 1 }
local TAB_ACCENT = { r = 1, g = 1, b = 1, a = 1 }

--- @param out PallidColor Scratch colour written in place.
--- @param from PallidColor Colour at t = 0.
--- @param to PallidColor Colour at t = 1.
--- @param t number Interpolation amount, 0..1.
local function blendInto(out, from, to, t)
    out.r = from.r + (to.r - from.r) * t
    out.g = from.g + (to.g - from.g) * t
    out.b = from.b + (to.b - from.b) * t
    out.a = (from.a or 1) + ((to.a or 1) - (from.a or 1)) * t
end

--- Draws the icon/text group of a fully visible tab, centred in the tab box.
--- @param el ISUIElement Host element the tree is rendered into.
--- @param tab table Tab entry.
--- @param ax number Absolute X of the tab.
--- @param ay number Absolute Y of the tab.
--- @param aw number Tab width.
--- @param ah number Tab height.
--- @param textColor PallidColor Shaded text and default icon tint.
function TabPanel:_drawTabContent(el, tab, ax, ay, aw, ah, textColor)
    local title = tab.title or ""
    local hasIcon = tab._hasIcon == true
    local iconW = hasIcon and TAB_ICON or 0
    local showText = title ~= ""
    local gap = (hasIcon and showText) and TAB_ICON_GAP or 0
    local maxText = math.max(0, aw - self.tabPadding * 2 - iconW - gap)
    local display = ""
    local textW = 0

    if showText then
        if maxText <= 0 then
            showText = false
            gap = 0
        else
            display = Pallid.UI.truncateText(title, self.style.font, maxText)
            textW = getTextManager():MeasureStringX(self.style.font, display)
            if textW <= 0 then
                showText = false
                gap = 0
            end
        end
    end

    local groupW = textW + iconW + gap
    local startX = ax + (aw - groupW) * 0.5
    local textX = startX
    local iconX = startX
    local iconSide = tab.iconSide == "right" and "right" or "left"
    if hasIcon and iconSide == "left" then
        textX = startX + iconW + gap
    elseif hasIcon then
        iconX = startX + textW + gap
    end

    if hasIcon then
        local tint = textColor
        if tab.iconColor ~= nil then
            tint = self:shade(tab.iconColor, 5)
        end
        local iconY = ay + (ah - iconW) * 0.5
        if tab._iconRegion ~= nil then
            Pallid.UI.textureRegion(el, tab._iconRegion, iconX, iconY, iconW, iconW, tint, ICON_OPTS)
        elseif tab._iconTexture ~= nil then
            Pallid.UI.texture(el, tab._iconTexture, iconX, iconY, iconW, iconW, tint, ICON_OPTS)
        elseif tab._iconName ~= nil then
            Pallid.UI.icon(el, tab._iconName, iconX, iconY, iconW, tint)
        end
    end

    if showText then
        local style = self.style
        local baseColor = style.color
        local baseAlign = style.alignH
        style.color = textColor
        style.alignH = "left"
        Pallid.UI.text(el, display, textX, ay + ah * 0.5, style)
        style.alignH = baseAlign
        style.color = baseColor
    end
end

--- @param el ISUIElement Host element the arrow is drawn into.
--- @param px number Arrow center X.
--- @param py number Arrow center Y.
--- @param key string "left"|"right"|"up"|"down".
--- @param color PallidColor Arrow tint.
function TabPanel:_drawArrow(el, px, py, key, color)
    local hovered = self._hoverArrow == key
    Pallid.UI.circle(el, px, py, 9, self:shade(hovered and self.arrowHoverBg or self.arrowBg, 1))
    Pallid.UI.icon(el, ARROW_ICONS[key], px - 6, py - 6, 12, self:shade(color, 2))
end

--- Paints the widget into the host element.
--- @param el ISUIElement Host element the tree is rendered into.
function TabPanel:drawSelf(el)
    if self._tabsDirty then
        self:relayoutTabs()
    end
    local x, y = self:originX(), self:originY()

    Pallid.UI.rect(el, x, y, self.w, self.h, self:shade(self.fill))

    -- A single hairline separates the strip from the page; there is no frame
    -- around the tabs, which keeps the modern look flat.
    if self.position == "top" then
        Pallid.UI.rect(el, x, y + self.tabSize - 1, self.w, 1, self:shade(self.borderColor))
    else
        Pallid.UI.rect(el, x + self.tabSize - 1, y, 1, self.h, self:shade(self.borderColor))
    end

    local stripLeft, stripTop, stripRight, stripBottom
    if self.position == "top" then
        stripLeft = x + self._stripX
        stripTop = y
        stripRight = stripLeft + self._stripW
        stripBottom = y + self.tabSize
    else
        stripLeft = x
        stripTop = y + self._stripY
        stripRight = x + self.tabSize
        stripBottom = stripTop + self._stripH
    end

    -- Only the visible slice of the strip is painted. A binary search over the
    -- prefix widths keeps this O(log n + visible) for thousands of tabs.
    local viewSize = (self.position == "top") and self._stripW or self._stripH
    local low, high = 1, #self.tabs
    local first = #self.tabs + 1
    while low <= high do
        local middle = math.floor((low + high) * 0.5)
        if (self._tabX[middle] or 0) + (self._tabW[middle] or 0) <= self._scroll then
            low = middle + 1
        else
            first = middle
            high = middle - 1
        end
    end

    for i = first, #self.tabs do
        if (self._tabX[i] or 0) >= self._scroll + viewSize then
            break
        end
        local tab = self.tabs[i]
        local tx, ty, tw, th = self:tabRect(i)
        local ax, ay = x + tx, y + ty
        local vl = math.max(ax, stripLeft)
        local vr = math.min(ax + tw, stripRight)
        local vt = math.max(ay, stripTop)
        local vb = math.min(ay + th, stripBottom)
        if vr > vl and vb > vt then
            local activeT = tab._activeT or 0
            local hoverT = tab._hoverT or 0

            blendInto(TAB_FILL, self.tabFill, self.tabHover, hoverT)
            blendInto(TAB_FILL2, TAB_FILL, self.tabActive, activeT)
            local fill = self:shade(TAB_FILL2, 1)

            local base = self.style.color
            local activeBase = self.activeStyle.color
            TAB_TEXT.r = (base.r or 1) + ((activeBase.r or 1) - (base.r or 1)) * activeT
            TAB_TEXT.g = (base.g or 1) + ((activeBase.g or 1) - (base.g or 1)) * activeT
            TAB_TEXT.b = (base.b or 1) + ((activeBase.b or 1) - (base.b or 1)) * activeT
            TAB_TEXT.a = (base.a or 1) + ((activeBase.a or 1) - (base.a or 1)) * activeT
            local textColor = self:shade(TAB_TEXT, 3)

            local full = vl == ax and vr == ax + tw and vt == ay and vb == ay + th
            if full then
                if fill.a > 0.005 then
                    Pallid.UI.roundedRect(el, ax + TAB_INSET, ay + TAB_INSET,
                        math.max(0, tw - TAB_INSET * 2), math.max(0, th - TAB_INSET * 2),
                        self.tabRadius, fill)
                end

                if activeT > 0.01 then
                    TAB_ACCENT.r = self.tabAccent.r
                    TAB_ACCENT.g = self.tabAccent.g
                    TAB_ACCENT.b = self.tabAccent.b
                    TAB_ACCENT.a = (self.tabAccent.a or 1) * activeT * 0.45
                    Pallid.UI.roundedBorder(el, ax + TAB_INSET, ay + TAB_INSET,
                        math.max(0, tw - TAB_INSET * 2), math.max(0, th - TAB_INSET * 2),
                        self.tabRadius, 1, self:shade(TAB_ACCENT, 2))
                end

                self:_drawTabContent(el, tab, ax, ay, tw, th, textColor)
            else
                if fill.a > 0.005 then
                    Pallid.UI.rect(el, vl, vt, vr - vl, vb - vt, fill)
                end

                -- A tab can be cut by the strip edge. Clip the full icon/text
                -- group instead of drawing a text-only variant, otherwise the
                -- icon pops in and out while the strip scrolls.
                local entered = Pallid.UI.clip(el, RECT_SHAPE, vl, vt, vr - vl, vb - vt)
                self:_drawTabContent(el, tab, ax, ay, tw, th, textColor)
                if entered then
                    Pallid.UI.clipEnd(el)
                end
            end
        end
    end

    -- Scroll arrows live outside the strip clip. Their enabled state follows the
    -- scroll target, so an arrow disables as soon as it has nothing left to do.
    if self._showArrows then
        local scroll = self._scrollTarget or self._scroll
        local maxScroll = self._maxScroll or 0
        local leftOn = scroll > 0.5
        local rightOn = scroll < maxScroll - 0.5
        local colorLeft = leftOn and self.arrowColor or self.arrowDisabled
        local colorRight = rightOn and self.arrowColor or self.arrowDisabled
        if self.position == "top" then
            self:_drawArrow(el, x + ARROW_W * 0.5, y + self.tabSize * 0.5, "left", colorLeft)
            self:_drawArrow(el, x + self.w - ARROW_W * 0.5, y + self.tabSize * 0.5, "right", colorRight)
        else
            self:_drawArrow(el, x + self.tabSize * 0.5, y + ARROW_W * 0.5, "up", colorLeft)
            self:_drawArrow(el, x + self.tabSize * 0.5, y + self.h - ARROW_W * 0.5, "down", colorRight)
        end
    end
end

--- Paints every visible child in order.
--- @param el ISUIElement Host element the active page is rendered into.
function TabPanel:drawChildren(el)
    local tab = self.tabs[self.active]
    if tab == nil or tab.content == nil then
        return
    end
    local cx, cy, cw, ch = self:contentRect()
    local x = self:originX() + cx
    local y = self:originY() + cy
    local entered = Pallid.UI.clip(el, RECT_SHAPE, x, y, cw, ch)
    tab.content:draw(el, x - cx, y - cy)
    if entered then
        Pallid.UI.clipEnd(el)
    end
end

-- Update ---------------------------------------------------------------------

--- Advances the widget state for the current frame.
--- @param now number Current game-tick time in seconds.
function TabPanel:update(now)
    if not self.visible then
        return
    end
    Widgets.Widget.update(self, now)
    local tab = self.tabs[self.active]
    if tab ~= nil and tab.content ~= nil then
        tab.content:update(now)
    end
end

--- Recomputes the hovered tab and arrow from the last cursor position, so the
--- highlight follows the strip while it scrolls under a stationary cursor.
function TabPanel:_refreshHover()
    local root = self:getRoot()
    if root == nil or root.mouseX == nil or root.mouseY == nil then
        return
    end
    if not self:isInside(root.mouseX, root.mouseY) then
        self.hoverIndex = 0
        self._hoverArrow = nil
        return
    end
    self:_updateHover(root.mouseX, root.mouseY)
end

--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function TabPanel:_updateHover(px, py)
    if not self.enabled then
        self.hoverIndex = 0
        self._hoverArrow = nil
        return
    end
    self.hoverIndex = self:hitTab(px, py)
    self._hoverArrow = nil
    if not self._showArrows then
        return
    end

    local lx = px - self:originX()
    local ly = py - self:originY()
    local scroll = self._scrollTarget or self._scroll
    local maxScroll = self._maxScroll or 0
    local leftOn = scroll > 0.5
    local rightOn = scroll < maxScroll - 0.5

    if self.position == "top" then
        if ly >= 0 and ly < self.tabSize then
            if lx >= 0 and lx < ARROW_W and leftOn then
                self._hoverArrow = "left"
            elseif lx >= self.w - ARROW_W and lx < self.w and rightOn then
                self._hoverArrow = "right"
            end
        end
    elseif lx >= 0 and lx < self.tabSize then
        if ly >= 0 and ly < ARROW_W and leftOn then
            self._hoverArrow = "up"
        elseif ly >= self.h - ARROW_W and ly < self.h and rightOn then
            self._hoverArrow = "down"
        end
    end
end

--- Advances tab hover/active blends and the smooth strip scroll.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function TabPanel:onAnimate(now, dt)
    local scroll = self._scroll
    local scrollTarget = self._scrollTarget or scroll
    if scroll ~= scrollTarget then
        local nextScroll = Widgets.approach(scroll, scrollTarget, SCROLL_SPEED, dt)
        if math.abs(scrollTarget - nextScroll) < SCROLL_EPSILON then
            nextScroll = scrollTarget
        end
        self._scroll = nextScroll
        self:_refreshHover()
    end

    local k = 1 - math.exp(-14 * dt)
    local hover = self.enabled and self.hoverIndex or 0
    local active = self.active
    for i = 1, #self.tabs do
        local tab = self.tabs[i]
        local hoverTarget = i == hover and 1 or 0
        local h = tab._hoverT or 0
        if h ~= hoverTarget then
            local nextH = h + (hoverTarget - h) * k
            if math.abs(hoverTarget - nextH) < 0.001 then
                nextH = hoverTarget
            end
            tab._hoverT = nextH
        end
        local activeTarget = i == active and 1 or 0
        local a = tab._activeT or 0
        if a ~= activeTarget then
            local nextA = a + (activeTarget - a) * k
            if math.abs(activeTarget - nextA) < 0.001 then
                nextA = activeTarget
            end
            tab._activeT = nextA
        end
    end
end

--- Pages are drawn manually and are not in `children`, so the base traversal
--- would never reach them.
--- @param now number Current time in seconds.
function TabPanel:updateAnimations(now)
    if not self.visible then
        return
    end
    Widgets.Widget.updateAnimations(self, now)
    local tab = self.tabs[self.active]
    if tab ~= nil and tab.content ~= nil then
        tab.content:updateAnimations(now)
    end
end

-- Input ----------------------------------------------------------------------

--- Pages are owned outside `children`; forward the lifecycle so registries
--- (drop zones) see them when the whole panel is attached or removed.
function TabPanel:onAttach()
    for i = 1, #self.tabs do
        local content = self.tabs[i].content
        if content ~= nil then
            content:_notifyAttached()
        end
    end
end

--- Cleans up when the widget is detached from the tree.
function TabPanel:onDetach()
    for i = 1, #self.tabs do
        local content = self.tabs[i].content
        if content ~= nil then
            content:_notifyDetached()
        end
    end
end

--- Shows or hides the native input boxes.
--- @param visible boolean False hides native boxes on every page.
function TabPanel:setNativeVisible(visible)
    for i = 1, #self.tabs do
        local content = self.tabs[i].content
        if content ~= nil then
            content:setNativeVisible(visible)
        end
    end
end

--- Unfocuses every native text box in the subtree.
function TabPanel:blurNative()
    for i = 1, #self.tabs do
        local content = self.tabs[i].content
        if content ~= nil then
            content:blurNative()
        end
    end
end

--- Returns the tab under the cursor.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return integer index 0 when the point is not on a tab.
function TabPanel:hitTab(px, py)
    if self._tabsDirty then
        self:relayoutTabs()
    end
    local lx = px - self:originX()
    local ly = py - self:originY()

    if self.position == "top" then
        if ly < 0 or ly >= self.tabSize or lx < self._stripX or lx >= self._stripX + self._stripW then
            return 0
        end
        local localX = lx - self._stripX + self._scroll
        local low, high = 1, #self.tabs
        while low <= high do
            local middle = math.floor((low + high) * 0.5)
            local start = self._tabX[middle]
            local finish = start + (self._tabW[middle] or 0)
            if localX < start then
                high = middle - 1
            elseif localX >= finish then
                low = middle + 1
            else
                return middle
            end
        end
        return 0
    end

    if lx < 0 or lx >= self.tabSize or ly < self._stripY or ly >= self._stripY + self._stripH then
        return 0
    end
    local localY = ly - self._stripY + self._scroll
    local low, high = 1, #self.tabs
    while low <= high do
        local middle = math.floor((low + high) * 0.5)
        local start = self._tabX[middle]
        local finish = start + (self._tabW[middle] or 0)
        if localY < start then
            high = middle - 1
        elseif localY >= finish then
            low = middle + 1
        else
            return middle
        end
    end
    return 0
end

--- Finds the child that handles a press at the given point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this panel's parent.
--- @param oy number Origin Y of this panel's parent.
--- @param button string|nil "left" or "right".
--- @return PallidWidget|nil target Widget that accepted the press.
function TabPanel:findDown(px, py, ox, oy, button)
    self._ox = ox
    self._oy = oy
    if not self.visible then
        return nil
    end
    if not self.enabled then
        return self:isInside(px, py) and self or nil
    end

    local index = self:hitTab(px, py)
    if index > 0 and self:isInside(px, py) then
        if self:onDown(px, py, button) then
            return self
        end
        return nil
    end

    if self._showArrows then
        local lx = px - self:originX()
        local ly = py - self:originY()
        local overArrow = false
        if self.position == "top" and ly >= 0 and ly < self.tabSize then
            if lx >= 0 and lx < ARROW_W then
                overArrow = true
                if button ~= "right" then
                    self:scrollBy(-self._stripW * 0.75)
                end
            elseif lx >= self.w - ARROW_W and lx < self.w then
                overArrow = true
                if button ~= "right" then
                    self:scrollBy(self._stripW * 0.75)
                end
            end
        elseif self.position == "left" and lx >= 0 and lx < self.tabSize then
            if ly >= 0 and ly < ARROW_W then
                overArrow = true
                if button ~= "right" then
                    self:scrollBy(-self._stripH * 0.75)
                end
            elseif ly >= self.h - ARROW_W and ly < self.h then
                overArrow = true
                if button ~= "right" then
                    self:scrollBy(self._stripH * 0.75)
                end
            end
        end
        if overArrow then
            return self
        end
    end

    local tab = self.tabs[self.active]
    if tab ~= nil and tab.content ~= nil and self:isInside(px, py) then
        return tab.content:findDown(px, py, self:originX(), self:originY(), button)
    end
    return nil
end

--- Handles a pointer press inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when a tab was activated.
function TabPanel:onDown(px, py, button)
    if not self.enabled then
        return false
    end
    -- Right-click must not switch the page; consume it instead.
    if button == "right" then
        return true
    end
    local index = self:hitTab(px, py)
    if index == 0 then
        return false
    end
    self:setActive(index)
    return true
end

--- Updates hover state for the current pointer position.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function TabPanel:onHoverMove(px, py)
    self:_updateHover(px, py)
end

--- Clears hover state when the pointer leaves.
function TabPanel:onHoverEnd()
    self.hoverIndex = 0
    self._hoverArrow = nil
    Widgets.Widget.onHoverEnd(self)
end

--- Handles a mouse-wheel event.
--- @param delta number Wheel steps; positive scrolls forward.
--- @return boolean handled True when the strip consumed the wheel.
function TabPanel:onWheel(delta)
    if not self.enabled or not self._showArrows then
        return false
    end
    local step = (self.position == "top") and 48 or 32
    self:scrollBy(delta * step)
    return true
end

--- Finds the child that handles hover at the given point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this panel's parent.
--- @param oy number Origin Y of this panel's parent.
--- @return PallidWidget|nil hovered Widget under the cursor.
function TabPanel:findHover(px, py, ox, oy)
    self._ox = ox
    self._oy = oy
    if not self.visible then
        return nil
    end
    if not self.enabled then
        return self:isInside(px, py) and self or nil
    end
    if self:hitTab(px, py) > 0 then
        return self
    end

    local tab = self.tabs[self.active]
    if tab ~= nil and tab.content ~= nil and self:isInside(px, py) then
        local hit = tab.content:findHover(px, py, self:originX(), self:originY())
        if hit ~= nil then
            return hit
        end
    end
    if self:isInside(px, py) then
        return self
    end
    return nil
end

--- Finds the child that handles a wheel event at the given point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of this panel's parent.
--- @param oy number Origin Y of this panel's parent.
--- @return PallidWidget|nil target Widget that handles the wheel.
function TabPanel:findWheel(px, py, ox, oy)
    self._ox = ox
    self._oy = oy
    if not self.visible or not self.enabled or not self:isInside(px, py) then
        return nil
    end
    local lx = px - self:originX()
    local ly = py - self:originY()
    if self.position == "top" then
        if ly < self.tabSize then
            return self
        end
    elseif lx < self.tabSize then
        return self
    end
    local tab = self.tabs[self.active]
    if tab ~= nil and tab.content ~= nil then
        return tab.content:findWheel(px, py, self:originX(), self:originY())
    end
    return nil
end
