require "pallid/ui/internal"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local I = Pallid.UI._internal
local warned = {}

-- Software copy of the active clip, in root-local coordinates. The engine
-- stencil clips pixels when it works; this stack always clips geometry that
-- can be clipped analytically (rects, text) and culls everything that is
-- completely outside. One host draws the whole tree, and stencils alone have
-- proven unreliable there, so the draw API consults this stack as well.
--
-- Entries are pooled: clipping runs during render, so allocating a table per
-- push would allocate every frame. POOL_DEPTH covers nested windows, scroll
-- panels and tables; only a deeper tree grows the pool (once, with a warning).
local POOL_DEPTH = 16
local poolWarned = false
local softStack = {}
for i = 1, POOL_DEPTH do
    softStack[i] = {}
end
local softDepth = 0

-- Unbalanced clipEnd repeats every frame. Report the first one with the likely
-- cause and the depths, then only every Nth occurrence as a counter, so a real
-- bug cannot turn the console into a 20k-line wall.
local clipEndWarnings = 0

--- Returns the innermost clip level, or nil when nothing is clipped.
--- @return table|nil Innermost clip entry, or nil when nothing is clipped.
local function topSoft()
    if softDepth == 0 then
        return nil
    end
    return softStack[softDepth]
end

--- Writes one clip level at the current depth and advances the stack.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param x2 number Second point X.
--- @param y2 number Second point Y.
--- @param empty boolean True when nothing can be visible inside this level.
local function pushEntry(x, y, x2, y2, empty)
    softDepth = softDepth + 1
    local entry = softStack[softDepth]
    if entry == nil then
        if not poolWarned then
            poolWarned = true
            I.logger:warn("clip: soft depth " .. softDepth .. " exceeds the pool (" .. POOL_DEPTH .. "); growing")
        end
        entry = {}
        softStack[softDepth] = entry
    end
    entry.x = x
    entry.y = y
    entry.x2 = x2
    entry.y2 = y2
    entry.empty = empty
    -- Reused entries must not inherit the stencil flag of a previous frame.
    entry.stencil = nil
end

--- Returns the current software clip rectangle.
--- @return number|nil x X coordinate.
--- @return number|nil y Y coordinate.
--- @return number|nil w Width in pixels.
--- @return number|nil h Height in pixels.
function Pallid.UI.clipRect()
    local top = topSoft()
    if top == nil then
        return nil
    end
    if top.empty then
        return top.x, top.y, 0, 0
    end
    return top.x, top.y, top.x2 - top.x, top.y2 - top.y
end

--- Returns whether the innermost software clip has a matching engine stencil.
--- Text uses this to decide if it can draw a line that straddles the clip and
--- let the GPU cut it, instead of dropping the whole line.
--- @return boolean True when the innermost clip is backed by the engine stencil.
function Pallid.UI.clipHasStencil()
    local top = topSoft()
    return top ~= nil and top.stencil == true
end

--- True when the rectangle is completely invisible under the active clip.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @return boolean True when nothing inside the rectangle can be visible.
function Pallid.UI.isClippedOut(x, y, w, h)
    local top = topSoft()
    if top == nil then
        return false
    end
    if top.empty then
        return true
    end
    return x >= top.x2 or y >= top.y2 or x + w <= top.x or y + h <= top.y
end

--- Clears the software clip stack. Call once at the start of a frame, before
--- drawing the root, so an interrupted frame cannot leak a clip.
--- @param el ISUIElement|nil Host element; its clip depth is reset too.
function Pallid.UI.resetClip(el)
    I.beginFrame()
    softDepth = 0
    if type(el) == "table" then
        -- An interrupted frame can leave an engine stencil active even though
        -- the Lua depth is being reset. Such a stencil rejects every later draw
        -- outside its rectangle, which reads as a black screen, so clear it.
        if (el._pallidClipDepth or 0) > 0 and I.hasJava(el) then
            el:clearStencilRect()
        end
        el._pallidClipDepth = 0
    end
end

--- Pushes the rectangle, intersected with the enclosing clip.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
local function pushSoft(x, y, w, h)
    local parent = topSoft()
    local x2, y2 = x + w, y + h
    if parent ~= nil then
        if parent.empty then
            pushEntry(x, y, x, y, true)
            return
        end
        if x < parent.x then
            x = parent.x
        end
        if y < parent.y then
            y = parent.y
        end
        if x2 > parent.x2 then
            x2 = parent.x2
        end
        if y2 > parent.y2 then
            y2 = parent.y2
        end
    end

    if x2 <= x or y2 <= y then
        pushEntry(x, y, x, y, true)
    else
        pushEntry(x, y, x2, y2, false)
    end
end

--- Advances both the engine clip depth and the software stack, and marks the
--- new level as backed by a stencil.
--- @param el ISUIElement Target element.
--- @param x number Left coordinate.
--- @param y number Top coordinate.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
local function enterClip(el, x, y, w, h)
    el._pallidClipDepth = (el._pallidClipDepth or 0) + 1
    pushSoft(x, y, w, h)
    softStack[softDepth].stencil = true
end

--- Pushes a clipping region. Only Shape.rect and Shape.circle are exact:
--- the game exposes just rectangular and elliptical stencils to Lua.
--- Other shapes return false and do not change the stencil.
--- @param el ISUIElement Target element.
--- @param shape PallidShape|nil Shape created with Pallid.UI.Shape.
--- @param x number Left coordinate, local to the element.
--- @param y number Top coordinate, local to the element.
--- @param w number Width in pixels. Must be positive.
--- @param h number Height in pixels. Must be positive.
--- @return boolean entered True when a stencil level was pushed.
--- @return string mode "rect"|"circle"|"circle-nofilter"|"none".
--- @return string|nil reason Set when the clip could not be applied exactly.
function Pallid.UI.clip(el, shape, x, y, w, h)
    if not I.hasJava(el) then
        return false, "none", "invalid element"
    end
    if shape == nil or shape.kind == nil then
        return false, "none", "no shape"
    end
    if w <= 0 or h <= 0 then
        return false, "none", "empty clip box"
    end

    -- The stencil and the software stack both truncate doubles to pixels; snap
    -- once here so the clip covers exactly the same pixels as the draw calls it
    -- bounds.
    local x1, y1 = I.snap(x), I.snap(y)
    local x2, y2 = I.snap(x + w), I.snap(y + h)
    x, y, w, h = x1, y1, math.max(1, x2 - x1), math.max(1, y2 - y1)

    if shape.kind == "rect" then
        el:setStencilRect(x, y, w, h)
        enterClip(el, x, y, w, h)
        return true, "rect"
    end

    if shape.kind == "circle" then
        -- setStencilCircle normally runs with GL_ALWAYS. Queue a threshold so
        -- the transparent corners of circle.png are not written to the stencil.
        local thresholded = I.queueAlphaFunc(I.GL_GREATER, 0.5)
        el:setStencilCircle(x, y, w, h)
        if thresholded then
            -- Restore what clearStencilRect leaves behind, not GL_GREATER 0:
            -- a rect stencil relies on the ambient value.
            I.queueAlphaFunc(I.GL_ALWAYS, 0.0)
            enterClip(el, x, y, w, h)
            return true, "circle"
        end
        enterClip(el, x, y, w, h)
        if not warned["circle-nofilter"] then
            warned["circle-nofilter"] = true
            I.logger:warn("clip(circle): alpha threshold unavailable; the stencil may be rectangular")
        end
        return true, "circle-nofilter", "alpha test threshold is unavailable"
    end

    if not warned[shape.kind] then
        warned[shape.kind] = true
        I.logger:warn("clip(" .. tostring(shape.kind) .. ") is not supported; only Shape.rect and Shape.circle are exact")
    end
    return false, "none", "only Shape.rect and Shape.circle can be clipped"
end

--- Pops one clipping level. A call without a matching clip only logs a warning
--- and leaves the stencil alone.
--- @param el ISUIElement Target element.
--- @return boolean popped True when a clip was popped.
function Pallid.UI.clipEnd(el)
    if type(el) ~= "table" then
        return false
    end
    local depth = el._pallidClipDepth or 0
    if depth <= 0 then
        clipEndWarnings = clipEndWarnings + 1
        if clipEndWarnings == 1 then
            I.logger:warn(string.format(
                "clipEnd without a matching clip on %s: software depth %d, element depth %d. "
                    .. "A widget drawn with parent == nil is treated as a frame root and resets both stacks; "
                    .. "containers that draw their content manually must set content.parent = self.",
                tostring(el.name or "unnamed element"), softDepth, depth))
        elseif clipEndWarnings % 600 == 0 then
            I.logger:warn(string.format(
                "clipEnd without a matching clip on %s: %d occurrences since the first report",
                tostring(el.name or "unnamed element"), clipEndWarnings))
        end
        return false
    end
    el._pallidClipDepth = depth - 1
    if softDepth > 0 then
        softDepth = softDepth - 1
    end
    el:clearStencilRect()

    -- Popping a stencil only lowers the reference value; the pixels inside the
    -- popped rectangle keep the higher value written by `setStencilRect`. Any
    -- drawing that follows with the parent's reference level (table border,
    -- header divider, scrollbars) is then rejected inside that rectangle while
    -- the area outside it still passes. That produced a border visible only in
    -- the scrollbar gutter. Repaint the remaining (intersected) parent clip at
    -- the new level so the whole parent area passes again; native components do
    -- the same via `repaintStencilRect` after a nested render.
    local top = topSoft()
    if top ~= nil and top.empty ~= true and top.stencil == true
        and el.repaintStencilRect ~= nil then
        el:repaintStencilRect(top.x, top.y, top.x2 - top.x, top.y2 - top.y)
    end
    return true
end

--- Temporarily disables stencil and alpha tests without changing clip depth.
--- Useful for drawing a diagnostic mark outside the current clip.
--- @param el ISUIElement Target element.
--- @return boolean suspended False when already suspended or invalid.
function Pallid.UI.clipSuspend(el)
    if not I.hasJava(el) or el._pallidClipSuspended then
        return false
    end
    el._pallidClipSuspended = true
    el:suspendStencil()
    return true
end

--- Re-enables the stencil state suspended by Pallid.UI.clipSuspend.
--- @param el ISUIElement Target element.
--- @return boolean resumed False when nothing was suspended.
function Pallid.UI.clipResume(el)
    if not I.hasJava(el) or not el._pallidClipSuspended then
        return false
    end
    el._pallidClipSuspended = nil
    el:resumeStencil()
    return true
end

--- Returns the element's current Pallid clip depth.
--- @param el ISUIElement|nil Target element.
--- @return integer depth 0 when no clip is active or the element is invalid.
function Pallid.UI.clipDepth(el)
    if type(el) ~= "table" then
        return 0
    end
    return el._pallidClipDepth or 0
end
