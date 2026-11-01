-- Row geometry for PallidTreeView. Kept out of the widget so draw and input
-- code stay readable; this module owns no state and never allocates.

local floor = math.floor
local min = math.min
local abs = math.abs
local HUGE = math.huge

local Layout = {}

--- One flattened row owned by a tree view. Positions are content-local: the
--- tree adds its origin and subtracts the scroll offset when drawing.
--- @class PallidTreeRow
--- @field node PallidTreeNode Node that owns the row.
--- @field depth integer Indentation depth; roots are 0.
--- @field hasChildren boolean True while the node has at least one child.
--- @field subH number Animated height of the row together with its subtree.
--- @field blockH number Animated height of the children block below the row.
--- @field childClip number Clip bottom inherited by the rows below this one.
--- @field y number Row top in content-local coordinates.
--- @field visH number Visible row height after the animated clip is applied.

--- Recomputes animated subtree heights, row positions and per-row clipping.
--- Rows must be in depth-first order. Collapsing children keep their full
--- positions and are cut from the bottom, so the rows after a block slide
--- instead of the children.
--- @param rows PallidTreeRow[] Flattened rows in depth-first order.
--- @param rowHeight number Height of one row in pixels.
--- @param pending number[] Scratch accumulator indexed by row depth; cleared by this call.
--- @param lastByDepth PallidTreeRow[] Scratch slots for the last row at each depth; slot `depth + 1` holds a row at `depth`.
--- @param maxDepth integer Deepest row depth in `rows`.
--- @return number contentH Total animated content height in pixels.
--- @return boolean uniform True when every row is evenly spaced and fully visible.
function Layout.place(rows, rowHeight, pending, lastByDepth, maxDepth)
    local count = #rows
    if count == 0 then
        return 0, true
    end

    for i = 0, maxDepth + 1 do
        pending[i] = 0
    end

    -- Reverse pass: a parent scales the block whose height is already known.
    for i = count, 1, -1 do
        local row = rows[i]
        local node = row.node
        local depth = row.depth
        local childSum = pending[depth + 1]
        pending[depth + 1] = 0

        local openT = node._openT or 0
        local blockH = 0
        if row.hasChildren and (node.expanded or openT > 0) then
            blockH = childSum * openT
            node._openFull = childSum
        else
            node._openFull = 0
        end

        row.blockH = blockH
        row.subH = rowHeight + blockH
        pending[depth] = pending[depth] + row.subH
    end
    pending[0] = 0

    -- Forward pass: position rows and carry the clip down to their children.
    local contentH = 0
    local uniform = true
    local y = 0
    -- Slots deeper than this belong to a finished sibling and must be ignored.
    local validDepth = 0
    for i = 1, count do
        local row = rows[i]
        local depth = row.depth
        local parent = nil
        if depth > 0 then
            -- depth - 1 is the parent's depth, stored in the 1-based slot `depth`.
            parent = lastByDepth[depth]
        end

        -- A previous sibling already knows where this row starts; otherwise it
        -- is the first child and starts right below the parent.
        local sibling = nil
        local siblingSlot = depth + 1
        if siblingSlot <= validDepth then
            sibling = lastByDepth[siblingSlot]
        end
        if sibling ~= nil then
            y = sibling.y + sibling.subH
        elseif parent ~= nil then
            y = parent.y + rowHeight
        else
            y = 0
        end
        local clip = parent ~= nil and parent.childClip or HUGE

        local visibleH = min(rowHeight, clip - y)
        if visibleH < 0 then
            visibleH = 0
        end

        row.y = y
        row.visH = visibleH
        row.childClip = min(clip, y + rowHeight + row.blockH)
        lastByDepth[siblingSlot] = row
        validDepth = siblingSlot
        if depth == 0 then
            contentH = y + row.subH
        end
        if uniform and (visibleH < rowHeight - 0.01 or abs(y - (i - 1) * rowHeight) > 0.01) then
            uniform = false
        end
    end

    return contentH, uniform
end

--- Finds the row under a content-local Y. Only the visible part of a clipped
--- row can be hit, so a collapsing branch cannot swallow presses below it.
--- @param rows PallidTreeRow[] Flattened rows in depth-first order.
--- @param contentY number Cursor Y in content-local coordinates.
--- @param rowHeight number Height of one row in pixels.
--- @param uniform boolean True when the rows are evenly spaced and fully visible.
--- @return integer index One-based row index, or 0 when no row is hit.
function Layout.rowAt(rows, contentY, rowHeight, uniform)
    local count = #rows
    if count == 0 or contentY < 0 then
        return 0
    end

    if uniform then
        local index = floor(contentY / rowHeight) + 1
        if index < 1 or index > count then
            return 0
        end
        return index
    end

    for i = 1, count do
        local row = rows[i]
        if contentY >= row.y and contentY < row.y + row.visH then
            return i
        end
    end
    return 0
end

return Layout
