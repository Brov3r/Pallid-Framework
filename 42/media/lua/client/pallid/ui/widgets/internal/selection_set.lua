require "pallid/ui/internal"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

--- Shared helpers for widgets backed by `selected[index] = true` tables.
--- @class PallidSelectionSet
local SelectionSet = {}

--- Removes indexes that no longer exist or became disabled.
--- @param widget table Widget with `selected` and `items` fields.
function SelectionSet.clamp(widget)
    local stale = {}
    for index in pairs(widget.selected) do
        local item = widget.items[index]
        if item == nil or item.disabled then
            stale[#stale + 1] = index
        end
    end
    for i = 1, #stale do
        widget.selected[stale[i]] = nil
    end
end

--- Checks or clears every enabled option through `widget:setSelected`.
--- @param widget table Widget with `items` and a `setSelected` method.
--- @param checked boolean New state.
--- @param silent boolean|nil True skips callbacks.
function SelectionSet.setAll(widget, checked, silent)
    for i = 1, #widget.items do
        if not widget.items[i].disabled then
            widget:setSelected(i, checked, silent)
        end
    end
end

return SelectionSet
