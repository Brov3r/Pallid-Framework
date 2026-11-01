require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/api/draw"
require "pallid/ui/api/text"
require "pallid/ui/widgets/widget"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local PREV = "\226\128\185"
local NEXT = "\226\128\186"
local ELLIPSIS = "\226\128\166"

--- Compact pager: previous, page numbers with ellipses, next. The slots are
--- painted and hit-tested directly, without child buttons.
---
--- `maxButtons` limits the number of page slots (numbers and ellipses). The
--- previous/next arrows are always drawn in addition, so the default of 7 page
--- slots produces at most 9 visible buttons.
--- @class PallidPagination : PallidWidget
--- @field page integer Current page; 0 when there are no pages.
--- @field pageCount integer Total number of pages.
--- @field maxButtons integer Maximum page/ellipsis slots, excluding the arrows.
--- @field onChange fun(pager: PallidPagination, page: integer)|nil Called after the page changes.
--- @field slots table[] Cached slot descriptors, rebuilt only when the page or count changes.
--- @field hoverSlot integer Hovered visual slot, 0 when none.
local Pagination = Widgets.class("Pagination")

--- Creates a new `Pagination` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Behaviour and appearance.
--- @field opts.page integer|nil Initial page, defaults to 1.
--- @field opts.pageCount integer|nil Total pages, defaults to 0.
--- @field opts.maxButtons integer|nil Maximum number/ellipsis slots, defaults to 7.
--- @field opts.onChange fun(pager: PallidPagination, page: integer)|nil Page callback.
--- @return PallidPagination pager New pagination control.
function Pagination.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, Pagination)
    self:init(x, y, w or 0, h or 0)
    self.pageCount = math.max(0, math.floor(opts.pageCount or 0))
    self.page = self.pageCount > 0 and math.max(1, math.min(opts.page or 1, self.pageCount)) or 0
    self.maxButtons = math.max(1, math.floor(opts.maxButtons or 7))
    self.onChange = opts.onChange
    self.hoverSlot = 0
    self.slots = {}

    self.style = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.text,
        alignH = "center",
        alignV = "middle",
    }
    self.fill = Pallid.UI.Color.surfaceMuted
    self.hoverFill = Pallid.UI.Color.accentSoft
    self.activeFill = Pallid.UI.Color.primarySoft
    self.borderColor = Pallid.UI.Color.border
    self.disabledColor = Pallid.UI.Color.textDisabled

    self:_rebuild()
    return self
end

--- Factory shortcut for `Pagination.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Behaviour and appearance; see `Pagination.new`.
--- @return PallidPagination pager New pagination control.
function Widgets.pagination(x, y, w, h, opts)
    return Pagination.new(x, y, w, h, opts)
end

--- Rebuilds the visible slot list. Called only after a page/count change.
function Pagination:_rebuild()
    local slots = self.slots
    for i = #slots, 1, -1 do
        slots[i] = nil
    end

    local total = self.pageCount
    if total <= 0 then
        self.page = 0
        return
    end
    local page = math.max(1, math.min(self.page, total))
    self.page = page
    local limit = math.max(1, self.maxButtons)

    --- Appends one slot descriptor to the layout being built.
    --- @param kind string Slot kind: "page" or "ellipsis".
    --- @param value integer|nil Page number used by page slots.
    local function add(kind, value)
        slots[#slots + 1] = {
            kind  = kind,
            page  = value,
            label = kind == "page" and tostring(value) or nil,
        }
    end

    if total <= limit then
        for i = 1, total do
            add("page", i)
        end
        return
    end
    if limit == 1 then
        add("page", page)
        return
    end
    if limit == 2 then
        add("page", 1)
        add("page", total)
        return
    end
    if limit == 3 then
        add("page", 1)
        if page > 1 and page < total then
            add("page", page)
        end
        add("page", total)
        return
    end

    -- First and last are always present; the middle window shrinks until the
    -- two possible ellipses fit inside the limit.
    local middle = limit - 2
    local start, finish, leftEllipsis, rightEllipsis
    while true do
        start = math.max(2, page - math.floor((middle - 1) * 0.5))
        finish = math.min(total - 1, start + middle - 1)
        start = math.max(2, finish - middle + 1)
        if finish < start then
            finish = start - 1
        end
        leftEllipsis = start > 2
        rightEllipsis = finish < total - 1
        local count = finish >= start and (finish - start + 1) or 0
        local used = 2 + count + (leftEllipsis and 1 or 0) + (rightEllipsis and 1 or 0)
        if used <= limit or middle <= 0 then
            break
        end
        middle = middle - 1
    end

    add("page", 1)
    if leftEllipsis then
        add("ellipsis")
    end
    for i = start, finish do
        add("page", i)
    end
    if rightEllipsis then
        add("ellipsis")
    end
    add("page", total)
end

--- Total number of visual slots, including the two arrows.
--- @return integer count Visual slot count.
function Pagination:slotCount()
    return #self.slots + 2
end

--- Returns the visual slot index under a root-local point.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @return integer index One-based visual slot, or 0 when outside.
function Pagination:slotAt(px, py)
    if not self:isInside(px, py) then
        return 0
    end
    local count = self:slotCount()
    if count <= 0 or self.w <= 0 then
        return 0
    end
    local index = math.floor((px - self:originX()) / (self.w / count)) + 1
    if index < 1 then
        index = 1
    elseif index > count then
        index = count
    end
    return index
end

--- Changes the current page.
--- @param page integer New page, clamped to 1..pageCount.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidPagination self For chaining.
function Pagination:setPage(page, silent)
    if self.pageCount <= 0 then
        self.page = 0
        return self
    end
    page = math.max(1, math.min(self.pageCount, math.floor(page or 1)))
    if page == self.page then
        return self
    end
    self.page = page
    self:_rebuild()
    if not silent and self.onChange ~= nil then
        self.onChange(self, page)
    end
    return self
end

--- Changes the total page count and clamps the current page.
--- @param count integer New page count; values below 0 are clamped.
--- @param silent boolean|nil True skips `onChange` when the page is clamped.
--- @return PallidPagination self For chaining.
function Pagination:setPageCount(count, silent)
    count = math.max(0, math.floor(count or 0))
    local oldPage = self.page
    self.pageCount = count
    if count <= 0 then
        self.page = 0
    else
        self.page = math.max(1, math.min(oldPage > 0 and oldPage or 1, count))
    end
    self:_rebuild()
    if not silent and self.page ~= oldPage and self.onChange ~= nil then
        self.onChange(self, self.page)
    end
    return self
end

--- Returns the current page.
--- @return integer page Current page, or 0 when there are no pages.
function Pagination:getPage()
    return self.page
end

--- Handles a page or arrow click.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
--- @param button string|nil "left" or "right".
--- @return boolean handled True when the press landed inside the pager.
function Pagination:onDown(px, py, button)
    if not self.enabled or button == "right" then
        return false
    end
    local index = self:slotAt(px, py)
    if index == 0 then
        return false
    end
    local count = self:slotCount()
    if index == 1 then
        self:setPage(self.page - 1)
    elseif index == count then
        self:setPage(self.page + 1)
    else
        local slot = self.slots[index - 1]
        if slot ~= nil and slot.kind == "page" then
            self:setPage(slot.page)
        end
    end
    return true
end

--- Tracks the hovered slot.
--- @param px number Cursor X in root-local coordinates.
--- @param py number Cursor Y in root-local coordinates.
function Pagination:onHoverMove(px, py)
    self.hoverSlot = self:slotAt(px, py)
end

--- Clears the hovered slot.
function Pagination:onHoverEnd()
    self.hoverSlot = 0
    Widgets.Widget.onHoverEnd(self)
end

--- Draws the cached slots centred in the widget box.
--- @param el ISUIElement Host element the tree is rendered into.
function Pagination:drawSelf(el)
    if self.pageCount <= 0 or self.w <= 0 or self.h <= 0 then
        return
    end
    local count = self:slotCount()
    local slotW = self.w / count
    local x, y = self:originX(), self:originY()
    local style = self.style
    local radius = 3

    for visual = 1, count do
        local slotX = x + (visual - 1) * slotW
        local slot = nil
        local label
        local kind
        if visual == 1 then
            label = PREV
            kind = "prev"
        elseif visual == count then
            label = NEXT
            kind = "next"
        else
            slot = self.slots[visual - 1]
            kind = slot ~= nil and slot.kind or "ellipsis"
            label = kind == "page" and (slot.label or "") or ELLIPSIS
        end

        local disabled = (kind == "prev" and self.page <= 1)
            or (kind == "next" and self.page >= self.pageCount)
        local active = kind == "page" and slot ~= nil and slot.page == self.page
        local hovered = visual == self.hoverSlot and not disabled and kind ~= "ellipsis"

        if active then
            Pallid.UI.roundedRect(el, slotX + 1, y + 1, slotW - 2, self.h - 2, radius, self:shade(self.activeFill))
        elseif hovered then
            Pallid.UI.roundedRect(el, slotX + 1, y + 1, slotW - 2, self.h - 2, radius, self:shade(self.hoverFill))
        end

        style.color = self:shade(
            disabled and self.disabledColor
                or (active and Pallid.UI.Color.textPrimary or Pallid.UI.Color.textMuted)
        )
        Pallid.UI.text(el, label, slotX + slotW * 0.5, y + self.h * 0.5, style)
    end
end
