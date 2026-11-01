require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/panel"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Small floating panel anchored to another widget. The root draws it above
--- the tree and closes it on any outside click, so it can overlap siblings.
--- @class PallidPopover : PallidPanel
--- @field content PallidWidget|nil Content widget, added as a child.
--- @field anchor PallidWidget|nil Current anchor widget.
--- @field offset number Gap from the anchor in pixels.
--- @field side string Last requested side: bottom, top, left or right.
--- @field onOpen fun(popover: PallidPopover)|nil Called after the popover is shown.
--- @field onClose fun(popover: PallidPopover)|nil Called after the popover is closed.
local Popover = Widgets.class("Popover", Widgets.Panel)

--- Creates a new `Popover` instance.
--- @param content PallidWidget|nil Content widget, added as a child.
--- @param opts table|nil Appearance and behaviour.
--- @field opts.width number|nil Panel width, defaults to 220.
--- @field opts.height number|nil Panel height, defaults to 120.
--- @field opts.padding number|nil Content inset, defaults to 8.
--- @field opts.offset number|nil Gap from the anchor, defaults to 6.
--- @field opts.background PallidColor|nil Panel fill.
--- @field opts.border PallidColor|nil Panel border.
--- @field opts.radius number|nil Panel corner radius.
--- @field opts.clipChildren boolean|nil False lets content paint outside the panel.
--- @field opts.onOpen fun(popover: PallidPopover)|nil Called after opening.
--- @field opts.onClose fun(popover: PallidPopover)|nil Called after closing.
--- @return PallidPopover popover New popover instance.
function Popover.new(content, opts)
    opts = opts or {}
    local width = math.max(1, opts.width or 220)
    local height = math.max(1, opts.height or 120)

    local self = setmetatable(Widgets.Panel.new(0, 0, width, height, {
        background = opts.background or Pallid.UI.Color.surfaceElevated,
        border = opts.border or Pallid.UI.Color.border,
        radius = opts.radius or 6,
    }), Popover)

    self.content = nil
    self.padding = math.max(0, opts.padding or 8)
    self.offset = math.max(0, opts.offset or 6)
    self.side = "bottom"
    self.anchor = nil
    self.visible = false
    self.clipChildren = opts.clipChildren ~= false
    self.onOpen = opts.onOpen
    self.onClose = opts.onClose

    if content ~= nil then
        self:setContent(content)
    end
    return self
end

--- Factory shortcut for `Popover.new`.
--- @param content PallidWidget|nil Content widget, added as a child.
--- @param opts table|nil Appearance and behaviour.
--- @return PallidPopover popover New popover instance.
function Widgets.popover(content, opts)
    return Popover.new(content, opts)
end

--- Replaces the content widget.
--- @param content PallidWidget|nil New content; nil removes the current one.
--- @return PallidPopover self For chaining.
function Popover:setContent(content)
    if self.content ~= nil then
        self:remove(self.content)
    end
    self.content = content
    if content ~= nil then
        self:add(content)
        self:_resizeContent()
    end
    return self
end

--- Resizes the content to the panel's padded area.
function Popover:_resizeContent()
    if self.content == nil then
        return
    end
    self.content:setBounds(
        self.padding,
        self.padding,
        math.max(0, self.w - self.padding * 2),
        math.max(0, self.h - self.padding * 2)
    )
end

--- Updates the widget bounds.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidPopover self For chaining.
function Popover:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:_resizeContent()
    return self
end

--- Changes the panel size and resizes the content.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidPopover self For chaining.
function Popover:setSize(w, h)
    return self:setBounds(self.x, self.y, math.max(1, w), math.max(1, h))
end

--- Recomputes the position from the current anchor.
--- @return PallidPopover self For chaining.
function Popover:reposition()
    if self.visible and self.anchor ~= nil then
        self:_place(self.anchor, self.side)
    end
    return self
end

--- Shows the popup.
--- @param anchor PallidWidget Anchor widget.
--- @param side string|nil "bottom", "top", "left", "right" or "auto".
--- @return PallidPopover self For chaining.
function Popover:show(anchor, side)
    if anchor == nil then
        Pallid.log("Popover:show requires an anchor widget")
        return self
    end
    local root = anchor:getRoot()
    if root == nil then
        Pallid.log("Popover:show requires an anchor attached to a root")
        return self
    end

    if root.openPopover ~= nil and root.openPopover ~= self then
        -- Only one popover may be open. Without this, opening a second picker
        -- left the first popover's always-on-top text field alive, stealing
        -- clicks from the new panel.
        root.openPopover:close()
    end
    self.parent = root
    self.anchor = anchor
    self:_resizeContent()
    self:_place(anchor, side or "bottom")
    root.openPopover = self
    if self.onOpen ~= nil then
        self.onOpen(self)
    end
    return self
end

--- Shows the popover at root-local coordinates without an anchor.
--- @param root PallidWidget Root that owns the popover.
--- @param x number Root-local X.
--- @param y number Root-local Y.
--- @return PallidPopover self For chaining.
function Popover:showAt(root, x, y)
    if root == nil then
        Pallid.log("Popover:showAt requires a root widget")
        return self
    end
    if root.openPopover ~= nil and root.openPopover ~= self then
        root.openPopover:close()
    end
    self.parent = root
    self.anchor = nil
    self:_resizeContent()
    self.x = math.max(4, math.min(x, math.max(4, root.w - self.w - 4)))
    self.y = math.max(4, math.min(y, math.max(4, root.h - self.h - 4)))
    self.visible = true
    self._ox = 0
    self._oy = 0
    root.openPopover = self
    if self.onOpen ~= nil then
        self.onOpen(self)
    end
    return self
end

--- Chooses a side and clamps the panel inside the root.
--- @param anchor PallidWidget Anchor widget.
--- @param side string Requested side or "auto".
function Popover:_place(anchor, side)
    local root = self.parent
    local ax, ay = anchor:originX(), anchor:originY()
    local x, y

    if side == "auto" then
        local below = root ~= nil and ay + anchor.h + self.offset + self.h <= root.h - 4
        side = below and "bottom" or "top"
    end
    if side ~= "top" and side ~= "left" and side ~= "right" then
        side = "bottom"
    end

    if side == "right" then
        x = ax + anchor.w + self.offset
        y = ay
        if root ~= nil and x + self.w > root.w - 4 then
            x = ax - self.w - self.offset
        end
    elseif side == "left" then
        x = ax - self.w - self.offset
        y = ay
        if root ~= nil and x < 4 then
            x = ax + anchor.w + self.offset
        end
    elseif side == "top" then
        x = ax
        y = ay - self.h - self.offset
        if root ~= nil and y < 4 then
            y = ay + anchor.h + self.offset
        end
    else
        x = ax
        y = ay + anchor.h + self.offset
        if root ~= nil and y + self.h > root.h - 4 then
            y = ay - self.h - self.offset
        end
    end

    if root ~= nil then
        x = math.max(4, math.min(x, math.max(4, root.w - self.w - 4)))
        y = math.max(4, math.min(y, math.max(4, root.h - self.h - 4)))
    else
        x = math.max(4, x)
        y = math.max(4, y)
    end

    self.side = side
    self.x = math.floor(x)
    self.y = math.floor(y)
    self.visible = true
    self._ox = 0
    self._oy = 0
end

--- Closes the popover and hides its native children.
--- @return PallidPopover self For chaining.
function Popover:close()
    if not self.visible then
        return self
    end
    self.visible = false
    self:setNativeVisible(false)
    self:blurNative()
    if self.content ~= nil and self.content.onClose ~= nil then
        self.content:onClose()
    end
    if self.onClose ~= nil then
        self.onClose(self)
    end
    local root = self.parent
    if root ~= nil and root.openPopover == self then
        root.openPopover = nil
    end
    self.anchor = nil
    return self
end

--- Closes the popover when its anchor disappears from the tree.
--- @param now number Current time in seconds.
function Popover:update(now)
    Widgets.Widget.update(self, now)
    if not self.visible or self.anchor == nil then
        return
    end
    local root = self.parent
    if not self.anchor.visible or (root ~= nil and self.anchor:getRoot() ~= root) then
        self:close()
    end
end

--- Returns true while the popup is open.
--- @return boolean open True while the popover is visible.
function Popover:isOpen()
    return self.visible
end
