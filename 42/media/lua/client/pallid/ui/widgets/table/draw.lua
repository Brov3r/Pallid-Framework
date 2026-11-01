require "pallid/ui/internal"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/api/textures"
require "pallid/ui/api/geometry"
require "pallid/ui/api/clip"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local RECT_SHAPE = Pallid.UI.Shape.rect()
local SORT_ICON = 10
local SORT_GAP = 4
local CELL_ICON = 14
local CELL_ICON_GAP = 4
local CELL_ICON_OPTS = { mode = "fit" }
-- Resolve icon names and texture paths once. Cells redraw every frame and the
-- registry lookup was previously repeated for every visible icon.
local STRING_ICON_CACHE = {}

--- Draws one cell icon. Supported sources are a texture path, a registered
--- icon name, a Texture object and an InventoryItem/Item. Item icons keep the
--- game's own colours; the tint applies to textures and registered icons.
--- @param el ISUIElement Host element.
--- @param icon string|Texture|InventoryItem|Item|false|nil Icon source.
--- @param x number Left edge of the icon box.
--- @param y number Top edge of the icon box.
--- @param size number Icon box size in pixels.
--- @param color PallidColor|nil Tint for textures and registered icons.
--- @return boolean drawn True when an icon was painted.
local function drawCellIcon(el, icon, x, y, size, color)
    if icon == nil or icon == false or size <= 0 then
        return false
    end

    if type(icon) == "string" then
        local cached = STRING_ICON_CACHE[icon]
        if cached == nil then
            local region = Pallid.UI.Textures.getIconRegion(icon)
            if region ~= nil then
                cached = { region = region }
            elseif Pallid.UI.Textures.hasIcon(icon) then
                cached = { texture = Pallid.UI.Textures.getIcon(icon) or false }
            else
                cached = { texture = Pallid.UI.Textures.get(icon) or false }
            end
            STRING_ICON_CACHE[icon] = cached
        end
        if cached.region ~= nil then
            return Pallid.UI.textureRegion(el, cached.region, x, y, size, size, color, CELL_ICON_OPTS)
        end
        if cached.texture == nil or cached.texture == false then
            return false
        end
        return Pallid.UI.texture(el, cached.texture, x, y, size, size, color, CELL_ICON_OPTS)
    end

    local kind = type(icon)
    if kind == "table" or kind == "userdata" then
        if icon.getWidth ~= nil and icon.getHeight ~= nil then
            return Pallid.UI.texture(el, icon, x, y, size, size, color, CELL_ICON_OPTS)
        end
        -- InventoryItem and script items both expose getFullType/getNormalTexture.
        if (icon.getFullType ~= nil or icon.getNormalTexture ~= nil)
            and Pallid.UI.itemIcon ~= nil then
            return Pallid.UI.itemIcon(el, icon, x, y, size, size, 1) == true
        end
    end
    return false
end

--- Adds drawing methods to the Table class. The header and body use separate,
--- sequential stencils; row backgrounds are clipped arithmetically so they can
--- cover the scrollbar gutter.
--- @param Table table PallidTable class.
--- @return fun Augmenter that installs the methods.
return function(Table)
    --- Draws the table: background, header, rows and both scrollbars.
    ---
    --- Clipping strategy: the header and the body each get their own rect stencil,
    --- strictly one after another (never nested). Row backgrounds are bounded
    --- arithmetically because they intentionally span the scrollbar gutter. The
    --- scrollbars are painted last, outside both stencils, and stay inside the
    --- table box. Every content pass is skipped when its mask would be empty, so a
    --- zero-width table cannot leak text past its border.
    --- @param el ISUIElement Host element the table is rendered into.
    function Table:drawSelf(el)
        if self.w <= 0 or self.h <= 0 then
            return
        end
        self:syncBars()
        self:refreshHover()

        local x, y = self:originX(), self:originY()
        local headerHeight = self._headerH or self.headerHeight
        local rowHeight = self.rowHeight
        local viewW = self.viewW
        local viewH = self.viewH
        local bodyY = y + headerHeight
        local bodyBottom = bodyY + viewH
        local style = self.style
        local base = style.color
        local firstCol, lastCol = self:visibleColumns(viewW)

        -- Header and row fills span the full width, including the scrollbar gutter:
        -- the bar floats inside the table instead of looking like a separate panel.
        Pallid.UI.rect(el, x, y, self.w, self.h, self:shade(self.bodyColor))
        Pallid.UI.rect(el, x, y, self.w, headerHeight, self:shade(self.headerColor))

        if headerHeight > 0 and viewW > 0 then
            local headerClip = Pallid.UI.clip(el, RECT_SHAPE, x, y, viewW, headerHeight)
            if headerClip then
                for i = firstCol, lastCol do
                    local column = self.columns[i]
                    local cx, cw = self:columnRect(i)
                    if i == self.hoverColumn then
                        local hoverWidth = math.max(0, cw - 1)
                        if i == #self.columns then
                            hoverWidth = math.max(0, x + viewW - cx)
                        end
                        Pallid.UI.rect(el, cx, y, hoverWidth, headerHeight, self:shade(self.headerHover))
                    end

                    local sorted = self.sortKey ~= nil and column.key == self.sortKey
                    local headerIconX = cx + 6
                    local iconOffset = 0
                    if column.headerIcon ~= nil and column.headerIcon ~= false then
                        local iconSize = column.headerIconSize or CELL_ICON
                        iconSize = math.max(1, math.min(
                            math.floor(iconSize + 0.5),
                            math.max(1, headerHeight - 2),
                            math.max(1, cw - 12)
                        ))
                        local iconColor = column.headerIconColor
                        local drawn = drawCellIcon(
                            el,
                            column.headerIcon,
                            headerIconX,
                            y + (headerHeight - iconSize) * 0.5,
                            iconSize,
                            iconColor ~= nil and iconColor ~= false and self:shade(iconColor) or nil
                        )
                        if drawn then
                            iconOffset = iconSize + CELL_ICON_GAP
                        end
                    end

                    local titleX = cx + 6 + iconOffset
                    local titleWidth = math.max(
                        0,
                        cw - 12 - iconOffset - (sorted and (SORT_ICON + SORT_GAP) or 0)
                    )
                    style.maxWidth = titleWidth
                    local prepared = Pallid.UI.prepareText(
                        column.title,
                        style,
                        self:_headerTextCache(i)
                    )
                    style.color = self:shade(base)
                    Pallid.UI.textPrepared(
                        el,
                        prepared,
                        titleX,
                        y + headerHeight * 0.5,
                        style
                    )
                    style.maxWidth = nil

                    if sorted then
                        -- Keep the marker next to the text instead of pinning it
                        -- to the column edge; long titles leave it after the ellipsis.
                        local titleW = Pallid.UI.measurePrepared(prepared)
                        local iconX = titleX + titleW + SORT_GAP
                        local maxIconX = cx + cw - 6 - SORT_ICON
                        if iconX > maxIconX then
                            iconX = maxIconX
                        end
                        local iconY = y + math.floor((headerHeight - SORT_ICON) * 0.5)
                        if iconX >= x + 4 and iconX + SORT_ICON <= x + viewW then
                            local texture = self.sortAsc and self._sortAscTexture or self._sortDescTexture
                            if texture ~= nil then
                                Pallid.UI.texture(
                                    el,
                                    texture,
                                    iconX,
                                    iconY,
                                    SORT_ICON,
                                    SORT_ICON,
                                    self:shade(self.sortColor),
                                    self._sortIconOpts
                                )
                            else
                                -- Fallback for a missing icon texture: the old AA triangle.
                                Pallid.UI.regularPolygon(
                                    el,
                                    3,
                                    iconX + SORT_ICON * 0.5,
                                    iconY + SORT_ICON * 0.5,
                                    SORT_ICON * 0.4,
                                    self.sortAsc and -90 or 90,
                                    self:shade(self.sortColor)
                                )
                            end
                        end
                    end

                    local dividerX = cx + cw
                    if i < #self.columns then
                        Pallid.UI.rect(el, dividerX - 1, y, 1, headerHeight, self:shade(self.borderColor))
                    end
                end

                if (self.leadWidth or 0) > 0 then
                    local divider = x - self.scrollX + self.leadWidth
                    if divider > x and divider < x + viewW then
                        Pallid.UI.rect(el, divider - 1, y, 1, headerHeight, self:shade(self.borderColor))
                    end
                end

                -- Draw the resize handle last so it sits above the neighbouring
                -- column's title and sort marker. The OS cursor shape cannot be
                -- changed from Lua, so this icon is the resize affordance.
                if self.hoverEdge and self.hoverColumn > 0
                    and self.hoverColumn <= #self.columns and headerHeight >= 10 then
                    local hx, hw = self:columnRect(self.hoverColumn)
                    -- A right-edge hover always means the last column; keep the
                    -- handle on the table's visible right edge, even when the
                    -- logical width leaves a small filler strip.
                    local dividerX = (self.hoverColumn == #self.columns) and (x + viewW) or (hx + hw)
                    if dividerX >= x and dividerX <= x + viewW then
                        local handleSize = math.min(12, headerHeight - 4)
                        Pallid.UI.rect(el, dividerX - 1, y + 2, 2, headerHeight - 4, self:shade(self.sortColor))
                        if self._resizeTexture ~= nil and handleSize >= 8 then
                            Pallid.UI.texture(
                                el,
                                self._resizeTexture,
                                dividerX - handleSize * 0.5,
                                y + (headerHeight - handleSize) * 0.5,
                                handleSize,
                                handleSize,
                                self:shade(self.sortColor),
                                self._sortIconOpts
                            )
                        end
                    end
                end
                Pallid.UI.clipEnd(el)
            end
        end
        style.color = base

        local first = math.floor(self.scrollY / rowHeight) + 1
        local visible = math.ceil(viewH / rowHeight) + 1
        local last = math.min(#self.view, first + visible)

        -- Row backgrounds use arithmetic clipping: a row can start above the body
        -- box, and the stripes intentionally cover the full table width so the bar
        -- gutter is part of the table. Masking them would cut that gutter.
        if viewH > 0 then
            for i = first, last do
                local row = self.view[i]
                if row ~= nil then
                    local rowY = bodyY + (i - 1) * rowHeight - self.scrollY
                    local top = math.max(rowY, bodyY)
                    local bottom = math.min(rowY + rowHeight, bodyBottom)
                    if bottom > top then
                        local color = (i % 2 == 0) and self.rowAltColor or self.rowColor
                        if self.selected[row] then
                            color = self.rowSelected
                        elseif i == self.hoverRow then
                            color = self.rowHover
                        end
                        Pallid.UI.rect(el, x, top, self.w, bottom - top, self:shade(color))
                    end
                end
            end
        end

        -- Exactly one body stencil for cell text and the drag rectangle. It stops
        -- at `viewW`, so a horizontally scrolled column cannot paint over the
        -- vertical bar or outside the table. If the mask cannot be pushed (empty
        -- viewport or invalid element), no content is drawn at all.
        if viewW > 0 and viewH > 0 then
            local bodyClip = Pallid.UI.clip(el, RECT_SHAPE, x, bodyY, viewW, viewH)
            if bodyClip then
                local lead = self.leadWidth or 0
                if lead > 0 then
                    -- The gutter is a structural column: a divider separates it
                    -- from the data columns, then the per-row hook draws the
                    -- grip. It lives inside the body clip so a horizontal
                    -- scroll cannot paint it over the scrollbar.
                    local divider = x - self.scrollX + lead
                    if divider > x and divider < x + viewW then
                        Pallid.UI.rect(el, divider - 1, bodyY, 1, viewH, self:shade(self.borderColor))
                    end
                    if self.drawRowLead ~= nil then
                        for i = first, last do
                            local row = self.view[i]
                            if row ~= nil then
                                self:drawRowLead(
                                    el,
                                    bodyY + (i - 1) * rowHeight - self.scrollY,
                                    rowHeight,
                                    i,
                                    row
                                )
                            end
                        end
                    end
                end

                for i = first, last do
                    local row = self.view[i]
                    if row ~= nil then
                        local rowY = bodyY + (i - 1) * rowHeight - self.scrollY
                        for c = firstCol, lastCol do
                            local column = self.columns[c]
                            local value = row[column.key]
                            if value ~= nil then
                                local cx, cw = self:columnRect(c)

                                -- A table value is a cell descriptor when it carries
                                -- any of the descriptor fields; other tables keep the
                                -- old tostring behaviour.
                                local descriptor = nil
                                if type(value) == "table" then
                                    if value.text ~= nil or value.label ~= nil or value.icon ~= nil
                                        or value.iconColor ~= nil or value.color ~= nil
                                        or value.iconSize ~= nil then
                                        descriptor = value
                                    end
                                end

                                local textValue
                                local icon
                                local iconColor
                                local iconSize
                                if descriptor ~= nil then
                                    textValue = descriptor.text
                                    if textValue == nil then
                                        textValue = descriptor.label
                                    end
                                    icon = descriptor.icon
                                    iconColor = descriptor.iconColor
                                    iconSize = descriptor.iconSize
                                else
                                    textValue = value
                                end

                                if icon == nil and column.icon ~= nil then
                                    if type(column.icon) == "function" then
                                        icon = column.icon(row, value)
                                    else
                                        icon = column.icon
                                    end
                                end
                                if iconColor == nil and column.iconColor ~= nil then
                                    if type(column.iconColor) == "function" then
                                        iconColor = column.iconColor(row, value)
                                    else
                                        iconColor = column.iconColor
                                    end
                                end
                                if iconSize == nil then
                                    iconSize = column.iconSize
                                end
                                iconSize = math.max(1, math.min(
                                    math.floor((iconSize or CELL_ICON) + 0.5),
                                    math.max(1, rowHeight - 2),
                                    math.max(1, cw - 12)
                                ))

                                local textX = cx + 6
                                local textOffset = 0
                                if icon ~= nil and icon ~= false then
                                    local drawn = drawCellIcon(
                                        el,
                                        icon,
                                        textX,
                                        rowY + (rowHeight - iconSize) * 0.5,
                                        iconSize,
                                        iconColor ~= nil and iconColor ~= false
                                            and self:shade(iconColor) or nil
                                    )
                                    if drawn then
                                        textOffset = iconSize + CELL_ICON_GAP
                                    end
                                end

                                if textValue ~= nil then
                                    local maxTextW = math.max(0, cw - 12 - textOffset)
                                    style.maxWidth = maxTextW
                                    local prepared = Pallid.UI.prepareText(
                                        tostring(textValue),
                                        style,
                                        self:_cellTextCache(row, c)
                                    )
                                    local textColor = descriptor ~= nil and descriptor.color or base
                                    if textColor == false then
                                        textColor = base
                                    end
                                    style.color = self:shade(textColor)
                                    Pallid.UI.textPrepared(
                                        el,
                                        prepared,
                                        textX + textOffset,
                                        rowY + rowHeight * 0.5,
                                        style
                                    )
                                    style.maxWidth = nil
                                end
                            end
                        end
                    end
                end
                style.color = base

                if self.dragSelecting then
                    local left = math.min(self.dragStartX, self.dragCurrentX)
                    local right = math.max(self.dragStartX, self.dragCurrentX)
                    local top = math.min(self.dragStartY, self.dragCurrentY)
                    local bottom = math.max(self.dragStartY, self.dragCurrentY)
                    local x1 = math.max(x, left)
                    local y1 = math.max(bodyY, top)
                    local x2 = math.min(x + viewW, right)
                    local y2 = math.min(bodyBottom, bottom)
                    if x2 > x1 and y2 > y1 then
                        Pallid.UI.rect(el, x1, y1, x2 - x1, y2 - y1, self:shade(self.dragFill))
                        Pallid.UI.border(el, x1, y1, x2 - x1, y2 - y1, 1, self:shade(self.dragBorder))
                    end
                end

                Pallid.UI.clipEnd(el)
            end
        end

        if headerHeight > 0 then
            Pallid.UI.rect(el, x, y + headerHeight - 1, self.w, 1, self:shade(self.borderColor))
        end
        Pallid.UI.border(el, x, y, self.w, self.h, 1, self:shade(self.borderColor))

        -- Paint the scrollbars above the rows and border. They sit inside the
        -- table bounds and do not need any clip of their own.
        if self.barV.visible then
            self.barV:draw(el, x, y)
        end
        if self.barH.visible then
            self.barH:draw(el, x, y)
        end
    end

    --- Scrollbars are painted at the end of `drawSelf`, so the generic child pass
    --- is intentionally empty; Table is a leaf widget.
    --- @param el ISUIElement Host element the table is rendered into; unused.
    function Table:drawChildren(el) -- luacheck: ignore
    end
end
