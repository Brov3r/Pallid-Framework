require "pallid/ui/internal"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

--- Shared popover mechanics for searchable dropdowns. ComboBox and
--- MultiSelectComboBox differ only in their selection model, so the filter row,
--- popover sizing, keyboard polling and open/close toggle live here.
--- @class PallidPopupComboUtil
local PopupCombo = {}

local FILTER_HEIGHT = 22
local FILTER_GAP = 4
local POPOVER_PAD = 4

--- Resizes the popover to the current filtered row count.
--- @param combo table ComboBox-like instance.
function PopupCombo.resize(combo)
    local count = #combo._filtered
    local listHeight = math.min(combo.maxHeight, math.max(combo.rowHeight, count * combo.rowHeight))
    local contentH = FILTER_HEIGHT + FILTER_GAP + listHeight
    local width = math.max(160, combo.w)
    local height = contentH + POPOVER_PAD * 2
    combo.popover:setSize(width, height)
    if combo.popover.visible then
        combo.popover:reposition()
    end
    local content = combo.content
    combo.filterInput:setBounds(0, 0, math.max(1, content.w), FILTER_HEIGHT)
    combo.list:setBounds(
        0,
        FILTER_HEIGHT + FILTER_GAP,
        math.max(1, content.w),
        math.max(1, content.h - FILTER_HEIGHT - FILTER_GAP)
    )
end

--- Opens the popover, rebuilds the filter and focuses the field.
--- @param combo table ComboBox-like instance.
function PopupCombo.show(combo)
    if combo.open then
        return
    end
    local root = combo:getRoot()
    if root == nil then
        return
    end
    combo.open = true
    combo:_applyFilter(combo.filterText, false)
    combo.popover:show(combo, "bottom")
    combo.filterInput:focus()
end

--- Scrolls the list so a filtered row is visible.
--- @param combo table ComboBox-like instance.
--- @param index integer One-based filtered row index.
function PopupCombo.scrollToRow(combo, index)
    local top = combo.list:rowOffset(index)
    local bottom = top + combo.rowHeight
    local scroll = combo.list:getScroll()
    if top < scroll then
        combo.list:scrollTo(top)
    elseif bottom > scroll + combo.list.viewH then
        combo.list:scrollTo(bottom - combo.list.viewH)
    end
end

--- Polls navigation keys while native text entry suppresses OnKeyPressed.
--- @param combo table ComboBox-like instance.
--- @param now number Current game-tick time in seconds.
--- @param dt number Seconds since the previous tick, 0..0.1.
function PopupCombo.onUpdate(combo, now, dt)
    if not combo.open or Keyboard == nil or Keyboard.isKeyDown == nil then
        return
    end
    local keyboard = Keyboard
    local up = keyboard.isKeyDown(keyboard.KEY_UP)
    if up and not combo._pollUp then
        combo:_onFilterKey(keyboard.KEY_UP)
    end
    combo._pollUp = up
    local down = keyboard.isKeyDown(keyboard.KEY_DOWN)
    if down and not combo._pollDown then
        combo:_onFilterKey(keyboard.KEY_DOWN)
    end
    combo._pollDown = down
    local enter = keyboard.isKeyDown(keyboard.KEY_RETURN) or keyboard.isKeyDown(keyboard.KEY_NUMPADENTER)
    if enter and not combo._pollReturn then
        combo:_onFilterKey(keyboard.KEY_RETURN)
    end
    combo._pollReturn = enter
    local escape = keyboard.isKeyDown(keyboard.KEY_ESCAPE)
    if escape and not combo._pollEscape then
        combo:_onFilterKey(keyboard.KEY_ESCAPE)
    end
    combo._pollEscape = escape
end

--- Toggles the popover from a field click.
--- @param combo table ComboBox-like instance.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when accepted.
function PopupCombo.onDown(combo, button)
    if not combo.enabled or button == "right" then
        return false
    end
    if combo.open then
        combo:close()
    else
        combo:show()
    end
    return true
end

return PopupCombo
