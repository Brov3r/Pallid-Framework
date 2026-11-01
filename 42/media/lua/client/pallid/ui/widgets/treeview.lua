require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/api/geometry"
require "pallid/ui/api/clip"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/scrollbar"
local TreeViewLayout = require "pallid/ui/widgets/treeview/layout"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local RECT_SHAPE   = Pallid.UI.Shape.rect()
local ROW_HEIGHT   = 22
local INDENT       = 16
local BAR_SIZE     = Widgets.DEFAULT_SCROLLBAR_SIZE or 10
local SCROLL_SPEED = 18
local SCROLL_EPSILON = 0.5
local HOVER_SPEED  = 18
local SELECT_SPEED = 16
local OPEN_SPEED   = 14
local ICON_DIR     = "media/assets/ui/pallid/icons/"
local ICON_OPTS    = { mode = "fit" }
-- Bound per-node label layouts; scrolling a huge tree must not retain one
-- prepared text table for every node ever rendered.
local LABEL_CACHE_LIMIT = 512
local ICONS        = {
    branch = ICON_DIR .. "folder.png",
    leaf   = ICON_DIR .. "file.png",
    arrow  = ICON_DIR .. "arrow-right-04.png",
}

--- Forces the eased expansion state of every node to follow `node.expanded`.
--- Used when the tree is replaced so an old animation cannot leak in.
--- @param nodes PallidTreeNode[]|nil Node list to synchronise.
--- @param seen table|nil Cycle guard; created on the first call.
local function syncExpansion(nodes, seen)
    if type(nodes) ~= "table" then
        return
    end
    seen = seen or {}
    for i = 1, #nodes do
        local node = nodes[i]
        if type(node) == "table" and not seen[node] then
            seen[node] = true
            node._openT = node.expanded and 1 or 0
            syncExpansion(node.children, seen)
        end
    end
end

--- Hierarchical list with expandable branches and indentation, like a file
--- explorer. Rows are flattened on every structural change so wheel scrolling
--- and hit testing stay simple; branches animate their height while opening
--- and closing.
--- @class PallidTreeView : PallidWidget
--- @field nodes PallidTreeNode[] Root nodes.
--- @field rows PallidTreeRow[] Flattened rows in depth-first order. Closing branches keep their rows until the animation settles.
--- @field rowHeight number Height of one row in pixels.
--- @field indent number Horizontal indent per depth level in pixels.
--- @field selected PallidTreeNode|nil Currently selected node.
--- @field onSelect fun(tree: PallidTreeView, node: PallidTreeNode)|nil Called when a row is clicked.
--- @field onToggle fun(tree: PallidTreeView, node: PallidTreeNode)|nil Called after a branch is expanded or collapsed.
--- @field hoverRow integer Index of the hovered visible row; 0 when none.
--- @field hoverPy number|nil Cursor Y that produced `hoverRow`; nil when not hovering.
--- @field hoverT number Eased hover highlight amount, 0..1.
--- @field selectT number Eased selection highlight amount, 0..1.
--- @field scrollY number Smooth vertical scroll offset in pixels.
--- @field scrollTarget number Target vertical scroll offset used by wheel easing.
--- @field maxScroll number Maximum vertical scroll offset.
--- @field viewW number Width of the content viewport, excluding the scrollbar.
--- @field barV PallidScrollBar Vertical scrollbar child.
--- @field barSize number Scrollbar thickness in pixels.
--- @field barGap number|nil Gap between the scrollbar and the edge; nil uses an adaptive default.
--- @field fill PallidColor Background fill.
--- @field borderColor PallidColor Border colour.
--- @field rowHover PallidColor Hovered row fill.
--- @field rowSelected PallidColor Selected row fill.
--- @field textColor PallidColor Row label colour.
--- @field chevronColor PallidColor Chevron icon tint.
--- @field iconColor PallidColor Default node icon tint.
--- @field defaultIcons boolean True draws folder/file icons when `node.icon` is nil.
--- @field iconSize number Default node icon box size in pixels.
--- @field chevronSize number Chevron icon box size in pixels.
--- @field style PallidTextStyle Reused label style.
local TreeView = Widgets.class("TreeView")

--- One row of a tree. Nodes are plain tables so callers can keep and mutate
--- them without a separate constructable class. The tree stores its eased
--- expansion amount on the node as `_openT` (0..1).
--- @class PallidTreeNode
--- @field label string Row label.
--- @field children PallidTreeNode[]|nil Child nodes; nil or an empty table makes a leaf.
--- @field expanded boolean|nil True expands children when the tree is rebuilt.
--- @field icon string|false|nil Texture path, registered icon name, or false to suppress the default icon.
--- @field iconColor PallidColor|nil Tint for a custom icon; nil keeps the texture colours.
--- @field onClick fun(node: PallidTreeNode)|nil Called after the node is selected.
--- @field _openT number|nil Eased expansion amount managed by the owning tree; do not edit.
--- @field _openFull number|nil Full children-block height used to snap the animation; managed by the owning tree.

--- Creates a new `TreeView` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional content, appearance and behaviour.
--- @field opts.nodes PallidTreeNode[]|nil Root nodes.
--- @field opts.rowHeight number|nil Row height in pixels, defaults to 22; values below 1 are clamped.
--- @field opts.indent number|nil Indent per depth level in pixels, defaults to 16.
--- @field opts.barSize number|nil Scrollbar thickness in pixels, defaults to 10.
--- @field opts.barGap number|nil Gap between the scrollbar and the edge; nil uses an adaptive default.
--- @field opts.background PallidColor|nil Background fill.
--- @field opts.border PallidColor|nil Border colour.
--- @field opts.iconColor PallidColor|nil Default node icon tint.
--- @field opts.defaultIcons boolean|nil Set false to suppress default folder/file icons.
--- @field opts.iconSize number|nil Default icon box size; defaults to rowHeight - 6, clamped to 10..16.
--- @field opts.chevronSize number|nil Chevron box size; defaults to rowHeight - 10, clamped to 8..12.
--- @field opts.onSelect fun(tree: PallidTreeView, node: PallidTreeNode)|nil Called when a row is clicked.
--- @field opts.onToggle fun(tree: PallidTreeView, node: PallidTreeNode)|nil Called after a branch is expanded or collapsed.
--- @return PallidTreeView tree New tree view instance.
function TreeView.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, TreeView)
    self:init(x, y, w or 0, h or 0)

    self.nodes = type(opts.nodes) == "table" and opts.nodes or {}
    self.rowHeight = math.max(1, math.floor(opts.rowHeight or ROW_HEIGHT))
    self.indent = math.max(0, math.floor(opts.indent or INDENT))
    self.barSize = math.max(1, math.floor(opts.barSize or BAR_SIZE))
    self.barGap = opts.barGap
    self.onSelect = opts.onSelect
    self.onToggle = opts.onToggle

    self.rows = {}
    self.selected = nil
    self.hoverRow = 0
    self.hoverPy = nil
    self.hoverT = 0
    self.selectT = 0
    self.scrollY = 0
    self.scrollTarget = 0
    self.maxScroll = 0
    self.viewW = self.w
    self._contentH = 0
    self._layoutDirty = true
    self._rowsUniform = true
    self._prunePending = false
    self._expandAnimating = false
    self._maxDepth = 0
    -- Scratch layout state; reused every frame to keep draw allocation-free.
    self._pendingHeight = {}
    self._lastRowByDepth = {}

    self.fill = opts.background or Pallid.UI.Color.surface
    self.borderColor = opts.border or Pallid.UI.Color.border
    self.rowHover = Pallid.UI.Color.accentSoft
    self.rowSelected = Pallid.UI.Color.primarySoft
    self.textColor = Pallid.UI.Color.text
    self.chevronColor = Pallid.UI.Color.textMuted
    self.iconColor = opts.iconColor or Pallid.UI.Color.textMuted
    self.defaultIcons = opts.defaultIcons ~= false
    self.iconSize = math.max(10, math.min(16, math.floor(opts.iconSize or self.rowHeight - 6)))
    self.chevronSize = math.max(8, math.min(12, math.floor(opts.chevronSize or self.rowHeight - 10)))
    self._iconTextures = {
        branch = Pallid.UI.Textures.get(ICONS.branch),
        leaf   = Pallid.UI.Textures.get(ICONS.leaf),
        arrow  = Pallid.UI.Textures.get(ICONS.arrow),
    }
    -- Scratch colour for eased row fills; never allocated inside draw.
    self._rowFill = { r = 0, g = 0, b = 0, a = 1 }
    -- Reused rotation options for the chevron; never allocated inside draw.
    self._chevronOpts = { mode = "fit", rotation = 0 }

    self.style = {
        font = Pallid.UI.Fonts.small,
        color = self.textColor,
        alignH = "left",
        alignV = "middle",
    }
    self._labelCaches = {}
    self._labelCacheNodes = 0
    self._iconResolved = {}

    self.barV = Widgets.scrollBar(
        true,
        self.w - self.barSize,
        1,
        self.barSize,
        math.max(1, self.h - 2),
        { margin = 1 }
    )
    self.barV.onChange = function(_, value)
        local offset = value * (self.maxScroll or 0)
        self.scrollY = offset
        self.scrollTarget = offset
    end
    self.barV:setOverlay(true)
    self:add(self.barV)

    syncExpansion(self.nodes)
    self:rebuild()
    return self
end

--- Factory shortcut for `TreeView.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Optional settings; see `TreeView.new`.
--- @return PallidTreeView tree New tree view instance.
function Widgets.treeView(x, y, w, h, opts)
    return TreeView.new(x, y, w, h, opts)
end

--- Returns the prepared label cache for a node, bounded to the nodes that have
--- actually been rendered.
--- @param node PallidTreeNode Node that owns the label.
--- @return PallidPreparedText cache Reusable label layout.
function TreeView:_labelCache(node)
    local caches = self._labelCaches
    local cache = caches[node]
    if cache ~= nil then
        return cache
    end

    if (self._labelCacheNodes or 0) >= LABEL_CACHE_LIMIT then
        caches = {}
        self._labelCaches = caches
        self._labelCacheNodes = 0
    end
    cache = {}
    caches[node] = cache
    self._labelCacheNodes = (self._labelCacheNodes or 0) + 1
    return cache
end

--- Rebuilds the flattened row list from the node tree. Invalid nodes and
--- duplicate references are skipped so a cyclic `children` table cannot loop.
--- Children of a collapsed branch stay while its animation is still running.
function TreeView:rebuild()
    local rows = {}
    local seen = {}
    local maxDepth = 0
    local prune = false
    local animate = false
    local function visit(nodes, depth)
        if type(nodes) ~= "table" then
            return
        end
        for i = 1, #nodes do
            local node = nodes[i]
            if type(node) == "table" and not seen[node] then
                seen[node] = true
                if node._openT == nil then
                    node._openT = node.expanded and 1 or 0
                end
                local children = node.children
                local hasChildren = type(children) == "table" and #children > 0
                if hasChildren and node._openT ~= (node.expanded and 1 or 0) then
                    animate = true
                end
                rows[#rows + 1] = {
                    node        = node,
                    depth       = depth,
                    hasChildren = hasChildren,
                    y           = 0,
                    visH        = 0,
                    subH        = 0,
                    blockH      = 0,
                    childClip   = 0,
                }
                if depth > maxDepth then
                    maxDepth = depth
                end
                if hasChildren and (node.expanded or node._openT > 0) then
                    if not node.expanded then
                        prune = true
                    end
                    visit(children, depth + 1)
                end
            end
        end
    end
    visit(self.nodes, 0)
    self.rows = rows
    self._maxDepth = maxDepth
    self._prunePending = prune
    self._expandAnimating = animate
    self._layoutDirty = true
    self:sync()
end

--- Recomputes animated subtree heights, row positions and clipping. Runs only
--- while the layout is dirty.
function TreeView:_layout()
    self._contentH, self._rowsUniform = TreeViewLayout.place(
        self.rows,
        self.rowHeight,
        self._pendingHeight,
        self._lastRowByDepth,
        self._maxDepth
    )
    self._layoutDirty = false
end

--- Recomputes the viewport, scroll range, scrollbar state and integer scroll
--- offset. Called once per draw and before wheel and pointer handling.
function TreeView:sync()
    if self._layoutDirty then
        self:_layout()
    end
    local viewH = math.max(0, self.h - 2)
    local contentH = self._contentH
    local gap = math.max(0, self.barGap or (math.min(self.w, self.h) < 80 and 3 or 5))
    local barFits = self.w > self.barSize + gap * 2 and viewH > gap * 2
    local needV = contentH > viewH and barFits
    self.viewW = math.max(0, needV and (self.w - self.barSize - gap) or self.w)
    self.maxScroll = math.max(0, contentH - viewH)

    self.scrollY = math.max(0, math.min(self.maxScroll, self.scrollY))
    self.scrollTarget = math.max(0, math.min(self.maxScroll, self.scrollTarget or self.scrollY))
    -- Row drawing and hit-testing share a whole-pixel offset; the eased
    -- `scrollY` stays fractional so wheel scrolling can move smoothly.
    self._scrollPx = math.floor(self.scrollY + 0.5)
    if self.hoverPy ~= nil then
        local index = self:rowAt(self.hoverPy)
        if index ~= self.hoverRow then
            self.hoverRow = index
            self.hoverT = 0
        end
    end

    self.barV:setEnabled(self.enabled)
    if needV then
        self.barV:setVisible(true)
        self.barV:setBounds(
            self.w - self.barSize - gap,
            1 + gap,
            self.barSize,
            math.max(1, viewH - gap * 2)
        )
        self.barV.page = math.min(1, viewH / math.max(1, contentH))
        self.barV.value = self.maxScroll > 0 and self.scrollY / self.maxScroll or 0
    else
        self.barV:setVisible(false)
        self.barV.value = 0
        self.barV.page = 1
    end
end

--- Replaces the tree nodes.
--- @param nodes PallidTreeNode[]|nil Root nodes; nil or a non-table clears the tree.
--- @return PallidTreeView self For chaining.
function TreeView:setNodes(nodes)
    self.nodes = type(nodes) == "table" and nodes or {}
    self._labelCaches = {}
    self._labelCacheNodes = 0
    self.selected = nil
    self.hoverRow = 0
    self.hoverPy = nil
    self.hoverT = 0
    self.selectT = 0
    self.scrollY = 0
    self.scrollTarget = 0
    syncExpansion(self.nodes)
    self:rebuild()
    return self
end

--- Expands every tree node.
--- @param expanded boolean True expands every branch, false collapses them.
--- @return PallidTreeView self For chaining.
function TreeView:expandAll(expanded)
    local seen = {}
    local function visit(nodes)
        if type(nodes) ~= "table" then
            return
        end
        for i = 1, #nodes do
            local node = nodes[i]
            if type(node) == "table" and not seen[node] then
                seen[node] = true
                local children = node.children
                if type(children) == "table" and #children > 0 then
                    node.expanded = expanded
                    visit(children)
                end
            end
        end
    end
    visit(self.nodes)
    self:rebuild()
    return self
end

--- Returns the row at the point.
--- @param py number Cursor Y in root-local coordinates.
--- @return integer index Visible row index, or 0 when the point is outside the rows.
function TreeView:rowAt(py)
    if self._layoutDirty then
        self:_layout()
    end
    local localY = py - self:originY() - 1 + (self._scrollPx or 0)
    return TreeViewLayout.rowAt(self.rows, localY, self.rowHeight, self._rowsUniform)
end

--- Draws the background, the visible rows and their chevron/node icons. The
--- scrollbar is an overlay child and is painted by the base child pass.
--- @param el ISUIElement Host element the tree is rendered into.
function TreeView:drawSelf(el)
    self:sync()
    if self.w <= 0 or self.h <= 0 then
        return
    end
    local x, y = self:originX(), self:originY()

    Pallid.UI.roundedRect(el, x, y, self.w, self.h, 4, self:shade(self.fill))
    Pallid.UI.roundedBorder(el, x, y, self.w, self.h, 4, 1, self:shade(self.borderColor))

    local contentW = math.max(0, self.viewW - 2)
    local contentH = math.max(0, self.h - 2)
    if contentW <= 0 or contentH <= 0 then
        self.hoverRow = 0
        return
    end

    local contentClip = Pallid.UI.clip(el, RECT_SHAPE, x + 1, y + 1, contentW, contentH)
    if not contentClip then
        return
    end

    local first, last
    local rows = self.rows
    local count = #rows
    local scrollPx = self._scrollPx or 0
    if self._rowsUniform then
        first = math.floor(scrollPx / self.rowHeight) + 1
        last = math.ceil((scrollPx + contentH) / self.rowHeight)
    else
        -- While a branch animates the rows are no longer on a fixed grid, so
        -- every row is visited and culled by its animated position.
        first, last = 1, count
    end
    local style = self.style
    local base = style.color
    local rowHeight = self.rowHeight
    local iconSize = self.iconSize
    local chevronSize = self.chevronSize
    local rowFill = self._rowFill
    local chevronOpts = self._chevronOpts

    for i = first, math.min(count, last) do
        local row = rows[i]
        local relativeY = row.y - scrollPx
        if row.visH > 0.01 and relativeY < contentH and relativeY + rowHeight > 0 then
            local node = row.node
            local rowY = y + 1 + relativeY
            -- A row that straddles the animated block edge is cut by its own
            -- stencil; rows below the edge are already fully hidden.
            local partial = row.visH < rowHeight - 0.01
            local entered = false
            if partial then
                entered = Pallid.UI.clip(el, RECT_SHAPE, x + 1, rowY, contentW, row.visH)
            end
            if not partial or entered then
                local fill = nil
                if node == self.selected and self.selectT > 0.01 then
                    fill = self.rowSelected
                    rowFill.r = fill.r or 1
                    rowFill.g = fill.g or 1
                    rowFill.b = fill.b or 1
                    rowFill.a = (fill.a or 1) * self.selectT
                    fill = rowFill
                elseif self.enabled and i == self.hoverRow and self.hoverT > 0.01 then
                    fill = self.rowHover
                    rowFill.r = fill.r or 1
                    rowFill.g = fill.g or 1
                    rowFill.b = fill.b or 1
                    rowFill.a = (fill.a or 1) * self.hoverT
                    fill = rowFill
                end
                if fill ~= nil then
                    Pallid.UI.rect(el, x + 1, rowY, contentW, row.visH, self:shade(fill))
                end

                local tx = x + 8 + row.depth * self.indent
                local midY = rowY + rowHeight * 0.5
                local hasChildren = row.hasChildren

                if hasChildren then
                    -- One arrow rotated by the eased amount keeps the glyph
                    -- continuous instead of swapping two textures mid-motion.
                    chevronOpts.rotation = (node._openT or 0) * 90
                    Pallid.UI.texture(
                        el,
                        self._iconTextures.arrow,
                        tx,
                        midY - chevronSize * 0.5,
                        chevronSize,
                        chevronSize,
                        self:shade(self.chevronColor),
                        chevronOpts
                    )
                end

                local labelX = tx + chevronSize + 4
                local icon = node.icon
                local iconColor
                if icon == nil and self.defaultIcons then
                    icon = hasChildren and ICONS.branch or ICONS.leaf
                    iconColor = self:shade(self.iconColor)
                elseif icon == false then
                    icon = nil
                elseif icon ~= nil then
                    -- Custom textures keep their own colours unless the caller opts in.
                    iconColor = node.iconColor and self:shade(node.iconColor) or nil
                end

                if icon ~= nil then
                    local cached = self._iconResolved[icon]
                    if cached == nil then
                        local region = Pallid.UI.Textures.getIconRegion(icon)
                        if region ~= nil then
                            cached = { region = region }
                        else
                            local texture = self._iconTextures[icon]
                            if texture == nil then
                                if Pallid.UI.Textures.hasIcon(icon) then
                                    texture = Pallid.UI.Textures.getIcon(icon)
                                else
                                    texture = Pallid.UI.Textures.get(icon)
                                end
                            end
                            cached = { texture = texture or false }
                        end
                        self._iconResolved[icon] = cached
                    end
                    if cached.region ~= nil then
                        Pallid.UI.textureRegion(
                            el, cached.region, labelX, midY - iconSize * 0.5,
                            iconSize, iconSize, iconColor, ICON_OPTS
                        )
                    elseif cached.texture ~= false and cached.texture ~= nil then
                        Pallid.UI.texture(
                            el, cached.texture, labelX, midY - iconSize * 0.5,
                            iconSize, iconSize, iconColor, ICON_OPTS
                        )
                    end
                    labelX = labelX + iconSize + 6
                end

                local label = node.label
                if type(label) ~= "string" then
                    label = label == nil and "" or tostring(label)
                end
                style.color = self:shade(base)
                Pallid.UI.textPrepared(
                    el,
                    Pallid.UI.prepareText(label, style, self:_labelCache(node)),
                    labelX,
                    midY,
                    style
                )
                style.color = base
            end
            if entered then
                Pallid.UI.clipEnd(el)
            end
        end
    end

    Pallid.UI.clipEnd(el)
end

--- Advances the eased wheel scroll, the hover/selection fades and the
--- expand/collapse progress of every visible branch. Per-frame so the list
--- glides instead of stepping at the game tick.
--- @param now number Current time in seconds.
--- @param dt number Seconds since the previous animation frame, 0..0.1.
function TreeView:onAnimate(now, dt)
    local target = self.scrollTarget or self.scrollY
    if target ~= self.scrollY then
        local nextY = Widgets.approach(self.scrollY, target, SCROLL_SPEED, dt)
        if math.abs(target - nextY) < SCROLL_EPSILON then
            nextY = target
        end
        self.scrollY = nextY
    end

    self.hoverT = Widgets.approach(self.hoverT, (self._hover and self.enabled) and 1 or 0, HOVER_SPEED, dt)
    self.selectT = Widgets.approach(self.selectT, self.selected ~= nil and 1 or 0, SELECT_SPEED, dt)

    local rows = self.rows
    local eased = false
    local moving = false
    if self._expandAnimating then
        for i = 1, #rows do
            local row = rows[i]
            if row.hasChildren then
                local node = row.node
                local openTarget = node.expanded and 1 or 0
                local openT = node._openT or 0
                if openT ~= openTarget then
                    local nextT = Widgets.approach(openT, openTarget, OPEN_SPEED, dt)
                    -- The block edge is drawn on whole pixels; snap the last
                    -- sub-pixel step so a settled branch cannot reveal a sliver.
                    local full = node._openFull or 0
                    if full > 0 and math.abs(openTarget - nextT) * full < 1 then
                        nextT = openTarget
                    end
                    node._openT = nextT
                    openT = nextT
                    eased = true
                end
                if openT ~= openTarget then
                    moving = true
                end
            end
        end
        self._expandAnimating = moving
    end
    if eased then
        self._layoutDirty = true
    end
    -- Rows of a closing branch stay until it finishes; drop them once nothing
    -- moves so hit testing and drawing go back to the cheap uniform path.
    if not moving and self._prunePending then
        self:rebuild()
    end
end

--- Handles a pointer press inside the widget.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the press was accepted.
function TreeView:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end
    self:sync()

    local index = self:rowAt(py)
    if index == 0 then
        return self:isInside(px, py)
    end

    local row = self.rows[index]
    local node = row.node
    local tx = self:originX() + 8 + row.depth * self.indent

    if row.hasChildren and px >= tx - 2 and px <= tx + self.chevronSize + 2 then
        node.expanded = not node.expanded
        self:rebuild()
        if self.onToggle ~= nil then
            self.onToggle(self, node)
        end
    else
        if self.selected ~= node then
            self.selected = node
            self.selectT = 0
        end
        if self.onSelect ~= nil then
            self.onSelect(self, node)
        end
        if node.onClick ~= nil then
            node.onClick(node)
        end
    end
    return true
end

--- Tracks the row under the cursor. The row index is recomputed in draw so
--- wheel scrolling and rebuilds cannot leave a stale highlight.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function TreeView:onHoverMove(px, py)
    if not self.enabled then
        self.hoverPy = nil
        self.hoverRow = 0
        return
    end
    local index = self:rowAt(py)
    if index ~= self.hoverRow then
        self.hoverT = 0
    end
    self.hoverPy = py
    self.hoverRow = index
end

--- Clears the row highlight when the cursor leaves the tree.
function TreeView:onHoverEnd()
    self.hoverPy = nil
    self.hoverRow = 0
    self.hoverT = 0
    Widgets.Widget.onHoverEnd(self)
end

--- Finds the child that handles a wheel event at the given point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param ox number Origin X of the parent widget.
--- @param oy number Origin Y of the parent widget.
--- @return PallidWidget|nil target Widget that handles the wheel, or nil.
function TreeView:findWheel(px, py, ox, oy)
    self._ox, self._oy = ox, oy
    if not self.visible or not self.enabled or not self:isInside(px, py) then
        return nil
    end
    self:sync()
    if self.maxScroll <= 0 then
        return nil
    end
    return self
end

--- Handles a mouse-wheel event.
--- @param delta number Wheel steps; positive scrolls up.
--- @return boolean handled True when the tree actually scrolled.
function TreeView:onWheel(delta)
    self:sync()
    if not self.enabled or self.maxScroll <= 0 then
        return false
    end
    local target = (self.scrollTarget or self.scrollY) + delta * self.rowHeight * 3
    self.scrollTarget = math.max(0, math.min(self.maxScroll, target))
    return true
end
