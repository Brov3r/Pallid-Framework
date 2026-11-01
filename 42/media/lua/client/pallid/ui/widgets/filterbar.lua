require "pallid/ui/internal"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/searchfield"
require "pallid/ui/widgets/combobox"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

--- Horizontal filter bar: a debounced search field plus one dropdown per
--- configured filter. It is a lightweight composite for tables, lists and
--- admin panels, not a query language. Use QueryBuilder when the caller needs
--- combinable rules.
--- @class PallidFilterBar : PallidWidget
--- @field search PallidSearchField Search field child.
--- @field fields table[] Normalised filter field descriptors.
--- @field combos PallidComboBox[] One combo per filter field.
--- @field gap number Gap between controls in pixels.
--- @field onChange fun(bar: PallidFilterBar, filters: PallidFilterState)|nil Called after any filter changes.
--- @class PallidFilterState
--- @field query string Search text.
--- @field values table<string, any> Active values keyed by field key.
--- @field count integer Number of active filters including a non-empty query.
local FilterBar = Widgets.class("FilterBar")

--- Creates a new `FilterBar` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels; defaults to 26.
--- @param opts table|nil Search and field settings.
--- @field opts.placeholder string|nil Search placeholder.
--- @field opts.debounce number|nil Search debounce in seconds.
--- @field opts.fields table[]|nil Filter fields: `{ key, label, options, width?, allLabel? }`.
--- @field opts.gap number|nil Gap between controls, defaults to 6.
--- @field opts.onChange fun(bar: PallidFilterBar, filters: PallidFilterState)|nil Filter callback.
--- @return PallidFilterBar bar New filter bar.
function FilterBar.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, FilterBar)
    self:init(x, y, w or 0, h or 26)
    self.gap = math.max(0, opts.gap or 6)
    self.onChange = opts.onChange
    self.fields = {}
    self.combos = {}
    self._controls = {}

    self.search = Widgets.searchField(0, 0, self.w, self.h, {
        placeholder = opts.placeholder or Pallid.UI.translate("UI_Pallid_Search", "Search..."),
        debounce    = opts.debounce or 0,
        onSearch    = function()
            self:_emitChange()
        end,
    })
    self:add(self.search)
    self._controls[#self._controls + 1] = self.search

    self:setFields(opts.fields, true)
    return self
end

--- Factory shortcut for `FilterBar.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Search and field settings; see `FilterBar.new`.
--- @return PallidFilterBar bar New filter bar.
function Widgets.filterBar(x, y, w, h, opts)
    return FilterBar.new(x, y, w, h, opts)
end

--- Replaces the filter fields and rebuilds the combos.
--- @param fields table[]|nil New field descriptors.
--- @param silent boolean|nil True skips the initial `onChange`.
--- @return PallidFilterBar self For chaining.
function FilterBar:setFields(fields, silent)
    for i = #self.combos, 1, -1 do
        local combo = self.combos[i]
        self:remove(combo)
        for j = #self._controls, 1, -1 do
            if self._controls[j] == combo then
                table.remove(self._controls, j)
            end
        end
    end
    self.fields = {}
    self.combos = {}

    local source = type(fields) == "table" and fields or {}
    for i = 1, #source do
        local field = source[i]
        if type(field) == "table" and field.key ~= nil then
            local options = {}
            options[1] = field.allLabel or Pallid.UI.translate("UI_Pallid_All", "All")
            for j = 1, #(field.options or {}) do
                options[#options + 1] = field.options[j]
            end
            local combo = Widgets.comboBox(0, 0, field.width or 140, self.h, options, {
                onChange = function()
                    self:_emitChange()
                end,
            })
            self.fields[#self.fields + 1] = field
            self.combos[#self.combos + 1] = combo
            self:add(combo)
            self._controls[#self._controls + 1] = combo
        end
    end

    self:layout()
    if not silent then
        self:_emitChange()
    end
    return self
end

--- Positions the search field and the filter combos in one row.
function FilterBar:layout()
    local gap = self.gap
    local comboWidth = 0
    for i = 1, #self.combos do
        comboWidth = comboWidth + (self.fields[i].width or 140) + gap
    end
    local searchW = math.max(80, self.w - comboWidth)
    self.search:setBounds(0, 0, searchW, self.h)
    local x = searchW + gap
    for i = 1, #self.combos do
        local width = self.fields[i].width or 140
        self.combos[i]:setBounds(x, 0, width, self.h)
        x = x + width + gap
    end
end

--- Resizes the bar and re-runs the row layout.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidFilterBar self For chaining.
function FilterBar:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    self:layout()
    return self
end

--- Returns the current filter state.
--- @return PallidFilterState filters New state table.
function FilterBar:getFilters()
    local values = {}
    local count = 0
    local query = self.search:getText()
    if query ~= "" then
        count = count + 1
    end
    for i = 1, #self.fields do
        local index = self.combos[i]:getIndex()
        if index ~= nil and index > 1 then
            local field = self.fields[i]
            local option = nil
            local label = self.combos[i]:getValue()
            -- Keep the original option value when it is a table descriptor.
            local source = field.options and field.options[index - 1]
            if type(source) == "table" and source.value ~= nil then
                option = source.value
            else
                option = label
            end
            values[field.key] = option
            count = count + 1
        end
    end
    return { query = query, values = values, count = count }
end

--- Clears the search and every combo.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidFilterBar self For chaining.
function FilterBar:clear(silent)
    self.search:setText("")
    for i = 1, #self.combos do
        self.combos[i]:setValue(nil, true)
    end
    if not silent then
        self:_emitChange()
    end
    return self
end

--- Sets one field value programmatically.
--- @param key string Field key.
--- @param value any Option value to select.
--- @return PallidFilterBar self For chaining.
function FilterBar:setFilter(key, value)
    for i = 1, #self.fields do
        if self.fields[i].key == key then
            self.combos[i]:setValue(value, true)
            break
        end
    end
    self:_emitChange()
    return self
end

--- Emits the current filter state.
function FilterBar:_emitChange()
    if self.onChange ~= nil then
        self.onChange(self, self:getFilters())
    end
end
