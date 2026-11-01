require "pallid/ui/internal"
require "pallid/ui/api/color"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/panel"
require "pallid/ui/widgets/label"
require "pallid/ui/widgets/checkbox"
require "pallid/ui/widgets/combobox"
require "pallid/ui/widgets/inputtext"
require "pallid/ui/widgets/button"
require "pallid/ui/widgets/searchfield"
require "pallid/ui/widgets/scrollpanel"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local DEFAULT_ROW = 28
local DEFAULT_GROUP = 22
local DEFAULT_LABEL_W = 150
local SEARCH_H = 26
local RESET_H = 26
local GAP = 4

--- Property inspector / settings grid. Each property is a row with a label and
--- an editor chosen by `type`; rows are placed in a ScrollPanel and can be
--- filtered by a search field. Boolean, text, number and select editors are
--- supported; custom values remain owned by the property descriptors.
--- @class PallidPropertyGrid : PallidWidget
--- @field properties table[] Property descriptors.
--- @field groups table<string, boolean> Group names in first-seen order.
--- @field values table<string, any> Current values keyed by property key.
--- @field scroll PallidScrollPanel Scroll container for the rows.
--- @field content PallidPanel Row container.
--- @field search PallidSearchField|nil Search field when enabled.
--- @field resetButton PallidButton|nil Reset button when enabled.
--- @field onChange fun(grid: PallidPropertyGrid, key: string, value: any, property: table)|nil Change callback.
--- @field striped boolean True draws alternating row fills.
local PropertyGrid = Widgets.class("PropertyGrid")

--- Creates a new `PropertyGrid` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Properties and appearance.
--- @field opts.properties table[]|nil Property descriptors.
--- @field opts.showSearch boolean|nil True draws the search field, defaults to true.
--- @field opts.searchPlaceholder string|nil Search placeholder.
--- @field opts.showReset boolean|nil True draws a reset button.
--- @field opts.labelWidth number|nil Label column width, defaults to 150.
--- @field opts.rowHeight number|nil Row height, defaults to 28.
--- @field opts.groupHeight number|nil Group header height, defaults to 22.
--- @field opts.striped boolean|nil True draws alternating row fills, defaults to false.
--- @field opts.onChange fun(grid: PallidPropertyGrid, key: string, value: any, property: table)|nil Change callback.
--- @return PallidPropertyGrid grid New property grid.
function PropertyGrid.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, PropertyGrid)
    self:init(x, y, w or 0, h or 0)
    self.properties = {}
    self.values = {}
    self.groups = {}
    self.showSearch = opts.showSearch ~= false
    self.showReset = opts.showReset == true
    self.labelWidth = math.max(60, opts.labelWidth or DEFAULT_LABEL_W)
    self.rowHeight = math.max(20, opts.rowHeight or DEFAULT_ROW)
    self.groupHeight = math.max(16, opts.groupHeight or DEFAULT_GROUP)
    self.striped = opts.striped == true
    self.onChange = opts.onChange
    self._filterText = ""

    self.rowFill = Pallid.UI.Color.surface
    self.rowAltFill = Pallid.UI.Color.surfaceMuted
    self.borderColor = Pallid.UI.Color.border
    self.labelStyle = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.textMuted,
        alignH = "left",
        alignV = "middle",
        ellipsis = "...",
    }
    self.groupStyle = {
        font = Pallid.UI.Fonts.small,
        color = Pallid.UI.Color.textPrimary,
        alignH = "left",
        alignV = "middle",
    }

    local searchH = self.showSearch and (SEARCH_H + GAP) or 0
    local resetH = self.showReset and (RESET_H + GAP) or 0
    if self.showSearch then
        self.search = Widgets.searchField(0, 0, self.w, SEARCH_H, {
            placeholder = opts.searchPlaceholder or Pallid.UI.translate("UI_Pallid_Search", "Search..."),
            onSearch = function(_, text)
                self._filterText = text
                self:_rebuild()
            end,
        })
        self:add(self.search)
    end

    self.scroll = Widgets.scrollPanel(0, searchH, self.w, math.max(1, self.h - searchH - resetH), {
        background = Pallid.UI.Color.surface,
        border     = self.borderColor,
        radius     = 4,
        vertical   = true,
        horizontal = false,
        barSize    = 10,
        barGap     = 4,
    })
    self.content = self.scroll.content
    self.content.hittable = false
    self:add(self.scroll)

    if self.showReset then
        self.resetButton = Widgets.button(0, self.h - RESET_H, self.w, RESET_H, {
            text    = Pallid.UI.translate("UI_Pallid_Reset", "Reset"),
            icon    = "media/assets/ui/pallid/icons/restore.png",
            sound   = false,
            onClick = function()
                self:reset()
            end,
        })
        self:add(self.resetButton)
    end

    self:setProperties(opts.properties)
    return self
end

--- Factory shortcut for `PropertyGrid.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param opts table|nil Properties and appearance; see `PropertyGrid.new`.
--- @return PallidPropertyGrid grid New property grid.
function Widgets.propertyGrid(x, y, w, h, opts)
    return PropertyGrid.new(x, y, w, h, opts)
end

--- Replaces the property descriptors.
--- @param properties table[]|nil New properties.
--- @return PallidPropertyGrid self For chaining.
function PropertyGrid:setProperties(properties)
    self.properties = type(properties) == "table" and properties or {}
    self.values = {}
    self.groups = {}
    for i = 1, #self.properties do
        local property = self.properties[i]
        if property.default == nil then
            property.default = property.value
        end
        self.values[property.key] = property.value
        local group = property.group
        if group ~= nil and group ~= "" and not self.groups[group] then
            self.groups[group] = true
        end
    end
    self:_rebuild()
    return self
end

--- @param property table Property descriptor.
--- @return boolean visible True when it matches the search filter.
function PropertyGrid:_matches(property)
    if self._filterText == "" then
        return true
    end
    local query = string.lower(self._filterText)
    local label = string.lower(tostring(property.label or property.key or ""))
    local key = string.lower(tostring(property.key or ""))
    return string.find(label, query, 1, true) ~= nil or string.find(key, query, 1, true) ~= nil
end

--- Updates a value without rebuilding the editor.
--- @param property table Property descriptor.
--- @param value any New value.
function PropertyGrid:_setValue(property, value)
    property.value = value
    self.values[property.key] = value
    if self.onChange ~= nil then
        self.onChange(self, property.key, value, property)
    end
    if property.onChange ~= nil then
        property.onChange(self, value, property)
    end
end

--- Builds one editor control for a property.
--- @param property table Property descriptor.
--- @param x number Editor left.
--- @param y number Editor top.
--- @param w number Editor width.
--- @param h number Editor height.
--- @return PallidWidget|nil editor Editor widget.
function PropertyGrid:_editor(property, x, y, w, h)
    local kind = property.type or "text"
    if kind == "boolean" then
        local checkbox = Widgets.checkbox(x, y + (h - 18) * 0.5, {
            checked  = property.value == true,
            width    = 34,
            height   = 18,
            sound    = false,
            onChange = function(_, state)
                self:_setValue(property, state == true)
            end,
        })
        return checkbox
    end
    if kind == "select" then
        local combo = Widgets.comboBox(x, y, w, h, property.options or {}, {
            placeholder = property.placeholder,
            onChange    = function(_, value)
                self:_setValue(property, value)
            end,
        })
        combo:setValue(property.value, true)
        return combo
    end

    local input = Widgets.inputText(x, y, w, h, {
        text     = property.value ~= nil and tostring(property.value) or "",
        numeric  = kind == "number",
        readOnly = property.readOnly == true,
        onChange = function(_, text)
            local value = text
            if kind == "number" then
                value = tonumber(text)
                if value == nil then
                    return
                end
            end
            self:_setValue(property, value)
        end,
    })
    return input
end

--- Rebuilds the visible rows from the properties and the current filter.
function PropertyGrid:_rebuild()
    if self.content == nil then
        return
    end
    -- Rebuilding removes and recreates native editor boxes. Some engine builds
    -- drop text-entry focus when a text box is detached, so remember the search
    -- field state and restore it after the new rows are in place.
    local keepSearchFocus = self.search ~= nil and self.search.box ~= nil
        and self.search.box:isFocused()
    local list = self.content.children
    if list ~= nil then
        for i = #list, 1, -1 do
            self.content:remove(list[i])
        end
    end

    local contentW = math.max(80, self.w - 18)
    local y = 0
    local lastGroup = nil
    local visibleIndex = 0

    for i = 1, #self.properties do
        local property = self.properties[i]
        if self:_matches(property) then
            local group = property.group
            if group ~= nil and group ~= "" and group ~= lastGroup then
                local header = Widgets.label(group, 8, y, contentW - 16, self.groupHeight, {
                    style = self.groupStyle,
                })
                self.content:add(header)
                y = y + self.groupHeight
                lastGroup = group
            end

            local row = Widgets.panel(0, y, contentW, self.rowHeight, {
                background = self.striped
                    and ((visibleIndex % 2 == 0) and self.rowFill or self.rowAltFill)
                    or nil,
                radius     = 3,
            })
            row.hittable = false
            local label = Widgets.label(
                property.label or property.key or "",
                8, 0, math.max(0, self.labelWidth - 16), self.rowHeight,
                { style = self.labelStyle }
            )
            row:add(label)

            local editorX = self.labelWidth
            local editorW = math.max(60, contentW - editorX - 8)
            local editor = self:_editor(property, editorX, 2, editorW, self.rowHeight - 4)
            if editor ~= nil then
                row:add(editor)
            end
            self.content:add(row)
            visibleIndex = visibleIndex + 1
            y = y + self.rowHeight + 2
        end
    end

    self.scroll:setContentSize(contentW, math.max(0, y))
    self.scroll:scrollTo(0, 0, true)
    if keepSearchFocus then
        -- Call the native box directly. Widget:focus() short-circuits when
        -- root.focused already points at the search field, but the engine's
        -- Core.currentTextEntryBox has just been stolen by the freshly created
        -- editor boxes; only box:focus() restores actual text entry.
        local box = self.search.box
        if box ~= nil then
            box:focus()
            local root = self:getRoot()
            if root ~= nil then
                root.focused = self.search
            end
        end
    end
end

--- Returns the current value of a property.
--- @param key string Property key.
--- @return any value Current value.
function PropertyGrid:getValue(key)
    return self.values[key]
end

--- Sets a value and rebuilds the row editors.
--- @param key string Property key.
--- @param value any New value.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidPropertyGrid self For chaining.
function PropertyGrid:setValue(key, value, silent)
    for i = 1, #self.properties do
        local property = self.properties[i]
        if property.key == key then
            property.value = value
            self.values[key] = value
            if not silent and self.onChange ~= nil then
                self.onChange(self, key, value, property)
            end
            break
        end
    end
    self:_rebuild()
    return self
end

--- Returns every current value keyed by property.
--- @return table<string, any> values Value map.
function PropertyGrid:getValues()
    return self.values
end

--- Restores every property to its initial value.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidPropertyGrid self For chaining.
function PropertyGrid:reset(silent)
    for i = 1, #self.properties do
        local property = self.properties[i]
        property.value = property.default
        self.values[property.key] = property.default
    end
    self:_rebuild()
    if not silent and self.onChange ~= nil then
        self.onChange(self, nil, nil, nil)
    end
    return self
end

--- Resizes the grid and re-runs its sections.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels.
--- @return PallidPropertyGrid self For chaining.
function PropertyGrid:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    local searchH = self.showSearch and (SEARCH_H + GAP) or 0
    local resetH = self.showReset and (RESET_H + GAP) or 0
    if self.search ~= nil then
        self.search:setBounds(0, 0, w, SEARCH_H)
    end
    self.scroll:setBounds(0, searchH, w, math.max(1, h - searchH - resetH))
    if self.resetButton ~= nil then
        self.resetButton:setBounds(0, h - RESET_H, w, RESET_H)
    end
    self:_rebuild()
    return self
end
