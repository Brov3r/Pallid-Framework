require "pallid/ui/internal"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local createGhost = require "pallid/ui/widgets/dragdrop/ghost"

--- Payload consumed by a drag session. Every hook is optional; `onDrop` may
--- return true to mark the drop as handled, which skips the DropZone under the
--- pointer (used by lists that reorder themselves).
--- @class PallidDragPayload
--- @field label string|nil Ghost label.
--- @field icon string|Texture|nil Ghost icon: a texture path, a registered name or a Texture.
--- @field iconSize number|nil Icon box in pixels; defaults to 14.
--- @field color PallidColor|nil Accent used for the ghost border and icon tint.
--- @field border PallidColor|nil Explicit ghost border; overrides `color`.
--- @field width number|nil Ghost width; measured from the label when nil.
--- @field height number|nil Ghost height; defaults to 28.
--- @field offsetX number|nil Cursor offset X; defaults to 12.
--- @field offsetY number|nil Cursor offset Y; defaults to 8.
--- @field kind string|nil Caller-defined payload kind, for `DropZone.accepts`.
--- @field dragData table|nil Caller-defined data, for list-to-list transfers.
--- @field onDragMove fun(px: number, py: number)|nil Called with root-local coordinates.
--- @field onDrop fun(px: number, py: number): boolean|nil Return true when the drop was handled.
--- @field onCancel fun()|nil Called when the session is cancelled.
--- @field onDragEnd fun(dropped: boolean)|nil Called exactly once at the end.

--- Process-wide drag session. Handles start a drag, DropZones observe the
--- pointer while it is active. The module is a singleton: only one drag can
--- exist at a time, which matches a single mouse capture.
---
--- Hooks are called with root-local coordinates, the same space the capturing
--- handle receives from `onMove`/`onUp`.
---
--- The ghost is not part of the widget tree. It is painted by the root's
--- overlay pass, so it stays above modals, menus and popovers and never
--- affects hit testing.
--- @class PallidDragDropModule
--- @field active table|nil Current session, nil when idle.
--- @field _zones PallidDropZone[] Attached zones in registration order.
local DragDrop = {}
Pallid.UI.DragDrop = DragDrop

DragDrop.active = nil
DragDrop._zones = {}
DragDrop._hoverZone = nil

-- Kahlua does not implement weak tables (`__mode` is never read by
-- KahluaTableImpl.setMetatable), so the registry must be pruned explicitly.
-- Zones register on attach and unregister on detach; both paths are O(n) and
-- happen only on structural changes.

--- @param zone PallidDropZone Zone to register.
function DragDrop._registerZone(zone)
    if zone == nil then
        return
    end
    local zones = DragDrop._zones
    for i = 1, #zones do
        if zones[i] == zone then
            return
        end
    end
    zones[#zones + 1] = zone
end

--- @param zone PallidDropZone Zone to remove.
function DragDrop._unregisterZone(zone)
    local zones = DragDrop._zones
    for i = #zones, 1, -1 do
        if zones[i] == zone then
            table.remove(zones, i)
        end
    end
    if DragDrop._hoverZone == zone then
        DragDrop._hoverZone = nil
    end
end

--- Drops zones that are no longer reachable from any tree. Called once per
--- drag start, never per frame.
function DragDrop._pruneZones()
    local zones = DragDrop._zones
    for i = #zones, 1, -1 do
        local zone = zones[i]
        if zone == nil or zone.parent == nil then
            table.remove(zones, i)
        end
    end
end

--- Starts a drag session. Any previous session is cancelled first.
--- @param payload PallidDragPayload Payload; see the class docs.
--- @param source PallidWidget|nil Widget that owns the drag (a handle or a list).
--- @param root PallidWidget Root the ghost is painted by.
--- @param px number Root-local pointer X.
--- @param py number Root-local pointer Y.
--- @return boolean started True when the drag started.
function DragDrop.start(payload, source, root, px, py)
    if type(payload) ~= "table" or root == nil then
        return false
    end
    if DragDrop.active ~= nil then
        DragDrop.cancel()
        if DragDrop.active ~= nil then
            -- A hook started another session while cancelling; keep it.
            return false
        end
    end

    DragDrop._pruneZones()

    local ghost = createGhost(payload)
    ghost.x = (px or 0) + ghost.offsetX
    ghost.y = (py or 0) + ghost.offsetY

    DragDrop.active = {
        payload = payload,
        source  = source,
        root    = root,
        ghost   = ghost,
        px      = px or 0,
        py      = py or 0,
    }
    DragDrop._hoverZone = nil

    -- Run the first move right away so zones and payload state reflect the
    -- press position before the first real mouse event arrives.
    DragDrop.move(px or 0, py or 0)
    return DragDrop.active ~= nil
end

--- Moves the active drag and notifies the payload and the zone under it.
--- @param px number Root-local pointer X.
--- @param py number Root-local pointer Y.
--- @return boolean moved True when the drag moved.
function DragDrop.move(px, py)
    local active = DragDrop.active
    if active == nil then
        return false
    end

    px, py = px or 0, py or 0
    active.px, active.py = px, py
    active.ghost.x = px + active.ghost.offsetX
    active.ghost.y = py + active.ghost.offsetY

    -- The payload updates its own preview first (row insertion, auto-scroll),
    -- then zones are evaluated against the final geometry.
    local hook = active.payload.onDragMove
    if hook ~= nil then
        hook(px, py)
    end
    DragDrop.zoneAt(px, py)
    return true
end

--- Completes the active drag. The payload's `onDrop` runs first; returning
--- true consumes the drop and skips the DropZone. `onDragEnd(true)` always
--- closes the session.
--- @param px number Root-local pointer X.
--- @param py number Root-local pointer Y.
--- @return boolean dropped True when the drag was dropped.
function DragDrop.drop(px, py)
    local active = DragDrop.active
    if active == nil then
        return false
    end

    px, py = px or active.px, py or active.py
    active.px, active.py = px, py
    active.ghost.x = px + active.ghost.offsetX
    active.ghost.y = py + active.ghost.offsetY

    local payload = active.payload
    local consumed = false
    local dropHook = payload.onDrop
    if dropHook ~= nil then
        consumed = dropHook(px, py) == true
    end
    if DragDrop.active ~= active then
        return false
    end

    if not consumed then
        local zone = DragDrop.zoneAt(px, py)
        if zone ~= nil and zone:_accept(payload, active.source, px, py)
            and zone.onDrop ~= nil then
            zone.onDrop(payload, active.source, px, py)
        end
        if DragDrop.active ~= active then
            return false
        end
    end

    local endHook = payload.onDragEnd
    if endHook ~= nil then
        endHook(true)
    end
    if DragDrop.active ~= active then
        return false
    end

    DragDrop:_finish(true)
    return true
end

--- Cancels the active drag (Esc, right click, a lost mouse button or a new
--- drag replacing an old one).
--- @return boolean cancelled True when the drag was cancelled.
function DragDrop.cancel()
    local active = DragDrop.active
    if active == nil then
        return false
    end

    local hook = active.payload.onCancel
    if hook ~= nil then
        hook()
    end
    if DragDrop.active ~= active then
        return true
    end

    local endHook = active.payload.onDragEnd
    if endHook ~= nil then
        endHook(false)
    end
    if DragDrop.active ~= active then
        return true
    end

    DragDrop:_finish(false)
    return true
end

--- Returns true when the widget is active.
--- @param source PallidWidget|nil When supplied, only true for that source.
--- @return boolean active True when a drag session exists for the source.
function DragDrop.isActive(source)
    local active = DragDrop.active
    if active == nil then
        return false
    end
    return source == nil or active.source == source
end

--- Returns the topmost zone that accepts the payload; when no zone accepts,
--- returns the topmost zone under the pointer so it can show the invalid state.
--- A zone that rejects does not hide an accepting zone below it.
--- @param a number|PallidDragDropModule Pointer X, or the module in colon form.
--- @param b number Pointer Y, or pointer X in colon form.
--- @param c number|nil Pointer Y in colon form.
--- @return PallidDropZone|nil zone Drop zone under the point, or nil.
function DragDrop.zoneAt(a, b, c)
    local px, py
    if c ~= nil then
        px, py = b, c
    else
        px, py = a, b
    end

    DragDrop._pruneZones()

    local active  = DragDrop.active
    local payload = active and active.payload or nil
    local source  = active and active.source or nil
    local root    = active and active.root or nil
    local zones   = DragDrop._zones

    local hit, hitScore       = nil, nil
    local valid, validScore   = nil, nil

    for i = 1, #zones do
        local zone = zones[i]
        if zone.visible and zone.w > 0 and zone.h > 0
            and (root == nil or zone:getRoot() == root)
            and zone:isInside(px, py)
            and zone:isPointVisible(px, py) then
            local score = zone.priority or i
            if hit == nil or score > hitScore then
                hit, hitScore = zone, score
            end
            if payload ~= nil and zone:_accept(payload, source, px, py) then
                if valid == nil or score > validScore then
                    valid, validScore = zone, score
                end
            end
        end
    end

    local top = payload ~= nil and (valid or hit) or nil
    for i = 1, #zones do
        local zone = zones[i]
        if zone ~= top then
            zone._dragOver  = false
            zone._dragValid = false
        end
    end
    if top ~= nil then
        top._dragOver  = true
        top._dragValid = top == valid
    end

    local previous = DragDrop._hoverZone
    if previous ~= top then
        DragDrop._hoverZone = top
        if previous ~= nil and previous.onDragLeave ~= nil then
            previous:onDragLeave(payload, source)
        end
        if top ~= nil and top.onDragEnter ~= nil then
            top:onDragEnter(payload, source, px, py)
        end
    end
    if top ~= nil and top.onDragMove ~= nil then
        top:onDragMove(payload, source, px, py)
    end
    return top
end

--- Paints the ghost above every overlay layer. Called by the root's
--- `drawOverlay`; a root without an active session does nothing.
--- @param root PallidWidget Root that owns the session.
--- @param el ISUIElement Host element.
--- @param ox number Root origin X.
--- @param oy number Root origin Y.
function DragDrop.drawGhost(root, el, ox, oy)
    local active = DragDrop.active
    if active == nil or active.root ~= root then
        return
    end
    local ghost = active.ghost
    ghost._ox = ox
    ghost._oy = oy
    ghost:drawSelf(el)
end

--- Drops every session state without notifying a source that may already be
--- detached. Call it when a window or a test host is torn down.
function DragDrop.reset()
    if DragDrop.active ~= nil then
        DragDrop.cancel()
    end
    DragDrop._hoverZone = nil
    -- A host teardown removes the whole tree without walking every child, so
    -- detached zones would otherwise stay registered for the process lifetime.
    DragDrop._zones = {}
end

--- @param dropped boolean True when the drag was dropped.
function DragDrop:_finish(dropped) -- luacheck: ignore
    local active = DragDrop.active
    if active == nil then
        return
    end
    DragDrop.active = nil

    local hover = DragDrop._hoverZone
    DragDrop._hoverZone = nil
    if hover ~= nil then
        hover._dragOver  = false
        hover._dragValid = false
        if hover.onDragLeave ~= nil then
            hover:onDragLeave(active.payload, active.source)
        end
    end

    local zones = DragDrop._zones
    for i = 1, #zones do
        local zone = zones[i]
        if zone ~= nil then
            zone._dragOver  = false
            zone._dragValid = false
        end
    end

    local source = active.source
    if source ~= nil and source._onDragFinished ~= nil then
        source:_onDragFinished(dropped, active.payload)
    end
end

-- The handle and zone live in their own files; load them last so the module
-- above is available while their classes are defined.
require "pallid/ui/widgets/dragdrop/handle"
require "pallid/ui/widgets/dragdrop/zone"

return DragDrop
