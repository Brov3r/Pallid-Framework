require "pallid/ui/internal"
require "pallid/ui/widgets/widget"
require "pallid/ui/widgets/panel"
require "pallid/ui/widgets/button"
require "pallid/ui/widgets/combobox"
require "pallid/ui/widgets/inputtext"

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

local Widgets = Pallid.UI.Widgets

local ROW_HEIGHT = 26
local ROW_GAP = 4
local FIELD_W = 150
local OP_W = 116
local REMOVE_W = 26

--- Simple rule builder: rows of field / operator / value joined by AND or OR.
--- It is a UI composite, not a query parser: callers receive the rule list and
--- translate it into their own filtering logic.
--- @class PallidQueryBuilder : PallidWidget
--- @field fields table[] Normalised field descriptors.
--- @field rules table[] Rule records: `{ field = key, op = string, value = any }`.
--- @field combinator "and"|"or" Current join mode.
--- @field onChange fun(builder: PallidQueryBuilder, rules: table[], combinator: string)|nil Change callback.
--- @field autoHeight boolean True grows the widget to fit its rows.
local QueryBuilder = Widgets.class("QueryBuilder")

--- @param key string Operator key.
--- @param fallback string English label.
--- @return string label Localised operator label.
local function opLabel(key, fallback)
    return Pallid.UI.translate("UI_Pallid_Op" .. key, fallback)
end

--- Creates a new `QueryBuilder` instance.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number|nil Height in pixels; nil or 0 fits the current rows.
--- @param opts table|nil Fields and initial rules.
--- @field opts.fields table[]|nil Field descriptors: `{ key, label, type?, options?, operators? }`.
--- @field opts.rules table[]|nil Initial rules.
--- @field opts.combinator "and"|"or"|nil Initial join mode.
--- @field opts.autoHeight boolean|nil True fits the height to the rows.
--- @field opts.onChange fun(builder: PallidQueryBuilder, rules: table[], combinator: string)|nil Change callback.
--- @return PallidQueryBuilder builder New query builder.
function QueryBuilder.new(x, y, w, h, opts)
    opts = opts or {}
    local self = setmetatable({}, QueryBuilder)
    self:init(x, y, w or 0, h or 0)
    self.fields = type(opts.fields) == "table" and opts.fields or {}
    self.rules = {}
    self.combinator = opts.combinator == "or" and "or" or "and"
    self.onChange = opts.onChange
    self.autoHeight = (h == nil or h <= 0) or opts.autoHeight == true
    self._rows = {}
    self._rebuildPending = false

    if type(opts.rules) == "table" then
        for i = 1, #opts.rules do
            local rule = opts.rules[i]
            self.rules[i] = {
                field = rule.field,
                op    = rule.op or self:_defaultOperator(rule.field),
                value = rule.value,
            }
        end
    end
    self:_rebuild()
    return self
end

--- Factory shortcut for `QueryBuilder.new`.
--- @param x number Offset X from the parent's origin.
--- @param y number Offset Y from the parent's origin.
--- @param w number Width in pixels.
--- @param h number|nil Height in pixels.
--- @param opts table|nil Fields and initial rules; see `QueryBuilder.new`.
--- @return PallidQueryBuilder builder New query builder.
function Widgets.queryBuilder(x, y, w, h, opts)
    return QueryBuilder.new(x, y, w, h, opts)
end

--- @param key string|nil Field key.
--- @return table|nil field Field descriptor.
function QueryBuilder:_field(key)
    for i = 1, #self.fields do
        if self.fields[i].key == key then
            return self.fields[i]
        end
    end
    return nil
end

--- @param key string|nil Field key.
--- @return string operator Default operator for the field type.
function QueryBuilder:_defaultOperator(key)
    local field = self:_field(key)
    if field ~= nil and field.type == "number" then
        return "eq"
    end
    if field ~= nil and field.type == "select" then
        return "is"
    end
    return "contains"
end

--- @param field table|nil Field descriptor.
--- @return table[] operators Operator descriptors `{ key, label }`.
function QueryBuilder:_operatorsFor(field)
    if field ~= nil and type(field.operators) == "table" then
        local result = {}
        for i = 1, #field.operators do
            local entry = field.operators[i]
            if type(entry) == "table" then
                result[i] = { key = entry.key or entry.value or entry[1], label = entry.label or entry[2] }
            else
                result[i] = { key = tostring(entry), label = tostring(entry) }
            end
        end
        return result
    end

    if field ~= nil and field.type == "number" then
        return {
            { key = "eq",  label = opLabel("Equals", "equals") },
            { key = "ne",  label = opLabel("NotEquals", "not equals") },
            { key = "lt",  label = opLabel("Less", "<") },
            { key = "lte", label = opLabel("LessEqual", "<=") },
            { key = "gt",  label = opLabel("Greater", ">") },
            { key = "gte", label = opLabel("GreaterEqual", ">=") },
        }
    end
    if field ~= nil and field.type == "select" then
        return {
            { key = "is",     label = opLabel("Is", "is") },
            { key = "is_not", label = opLabel("IsNot", "is not") },
        }
    end
    return {
        { key = "contains",    label = opLabel("Contains", "contains") },
        { key = "eq",          label = opLabel("Equals", "equals") },
        { key = "ne",          label = opLabel("NotEquals", "not equals") },
        { key = "starts_with", label = opLabel("StartsWith", "starts with") },
        { key = "ends_with",   label = opLabel("EndsWith", "ends with") },
    }
end

--- Replaces the rules.
--- @param rules table[]|nil New rules.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidQueryBuilder self For chaining.
function QueryBuilder:setRules(rules, silent)
    self.rules = {}
    if type(rules) == "table" then
        for i = 1, #rules do
            local rule = rules[i]
            self.rules[i] = {
                field = rule.field,
                op    = rule.op or self:_defaultOperator(rule.field),
                value = rule.value,
            }
        end
    end
    self:_rebuild()
    if not silent then
        self:_emit()
    end
    return self
end

--- Returns the current rules.
--- @return table[] rules Live rule list.
function QueryBuilder:getRules()
    return self.rules
end

--- Adds an empty rule using the first field.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidQueryBuilder self For chaining.
function QueryBuilder:addRule(silent)
    local field = self.fields[1]
    if field == nil then
        return self
    end
    self.rules[#self.rules + 1] = {
        field = field.key,
        op    = self:_defaultOperator(field.key),
        value = "",
    }
    self:_rebuild()
    if not silent then
        self:_emit()
    end
    return self
end

--- Removes a rule.
--- @param index integer One-based rule index.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidQueryBuilder self For chaining.
function QueryBuilder:removeRule(index, silent)
    if self.rules[index] == nil then
        return self
    end
    table.remove(self.rules, index)
    self:_rebuild()
    if not silent then
        self:_emit()
    end
    return self
end

--- Changes the join mode.
--- @param combinator "and"|"or" New mode.
--- @param silent boolean|nil True skips `onChange`.
--- @return PallidQueryBuilder self For chaining.
function QueryBuilder:setCombinator(combinator, silent)
    self.combinator = combinator == "or" and "or" or "and"
    if not silent then
        self:_emit()
    end
    return self
end

--- Removes and recreates every row control from `self.rules`.
function QueryBuilder:_rebuild()
    for i = #self._rows, 1, -1 do
        self:remove(self._rows[i])
        self._rows[i] = nil
    end

    local y = 0
    local width = math.max(1, self.w)
    for i = 1, #self.rules do
        local rule = self.rules[i]
        if rule.field == nil and self.fields[1] ~= nil then
            rule.field = self.fields[1].key
            rule.op = self:_defaultOperator(rule.field)
        end
        local row = Widgets.panel(0, y, width, ROW_HEIGHT)
        row.hittable = false

        local fieldOptions = self:_fieldOptions()
        local fieldCombo = Widgets.comboBox(0, 0, FIELD_W, ROW_HEIGHT, fieldOptions, {
            onChange = function(_, value, index)
                local field = self.fields[index]
                if field ~= nil then
                    rule.field = field.key
                    rule.op = self:_defaultOperator(field.key)
                    rule.value = ""
                    self._rebuildPending = true
                end
                self:_emit()
            end,
        })
        local field = self:_field(rule.field)
        if field ~= nil then
            fieldCombo:setValue(field.label or field.key, true)
        end
        row:add(fieldCombo)

        local operators = self:_operatorsFor(self:_field(rule.field))
        local opOptions = {}
        local opIndex = 1
        for j = 1, #operators do
            opOptions[j] = operators[j].label
            if operators[j].key == rule.op then
                opIndex = j
            end
        end
        local opCombo = Widgets.comboBox(FIELD_W + ROW_GAP, 0, OP_W, ROW_HEIGHT, opOptions, {
            onChange = function(_, _, index)
                local entry = operators[index]
                if entry ~= nil then
                    rule.op = entry.key
                end
                self:_emit()
            end,
        })
        opCombo:setValue(operators[opIndex] and operators[opIndex].label or nil, true)
        row:add(opCombo)

        local valueX = FIELD_W + OP_W + ROW_GAP * 2
        local valueW = math.max(60, width - valueX - REMOVE_W - ROW_GAP)
        local field = self:_field(rule.field)
        local valueControl
        if field ~= nil and field.type == "select" then
            valueControl = Widgets.comboBox(valueX, 0, valueW, ROW_HEIGHT, field.options or {}, {
                onChange = function(_, value)
                    rule.value = value
                    self:_emit()
                end,
            })
            valueControl:setValue(rule.value, true)
        else
            valueControl = Widgets.inputText(valueX, 0, valueW, ROW_HEIGHT, {
                text = tostring(rule.value or ""),
                numeric = field ~= nil and field.type == "number",
                onChange = function(_, text)
                    rule.value = text
                    self:_emit()
                end,
            })
        end
        row:add(valueControl)

        local remove = Widgets.button(width - REMOVE_W, 0, REMOVE_W, ROW_HEIGHT, {
            icon    = "media/assets/ui/pallid/icons/cross.png",
            sound   = false,
            flat    = true,
            onClick = function()
                self:removeRule(i)
            end,
        })
        row:add(remove)

        self:add(row)
        self._rows[i] = row
        y = y + ROW_HEIGHT + ROW_GAP
    end

    local controls = Widgets.panel(0, y, width, ROW_HEIGHT)
    controls.hittable = false
    local combinator = Widgets.comboBox(0, 0, 90, ROW_HEIGHT, {
        Pallid.UI.translate("UI_Pallid_And", "AND"),
        Pallid.UI.translate("UI_Pallid_Or", "OR"),
    }, {
        onChange = function(_, _, index)
            self.combinator = index == 2 and "or" or "and"
            self:_emit()
        end,
    })
    combinator:setValue(
        self.combinator == "or" and Pallid.UI.translate("UI_Pallid_Or", "OR")
            or Pallid.UI.translate("UI_Pallid_And", "AND"),
        true
    )
    controls:add(combinator)
    controls:add(Widgets.button(96, 0, math.max(100, width - 96), ROW_HEIGHT, {
        text    = Pallid.UI.translate("UI_Pallid_AddRule", "Add rule"),
        icon    = "media/assets/ui/pallid/icons/plus.png",
        sound   = false,
        onClick = function()
            self:addRule()
        end,
    }))
    self:add(controls)
    self._rows[#self._rows + 1] = controls

    if self.autoHeight then
        self.h = y + ROW_HEIGHT
    end
end

--- @return string[] options Field labels.
function QueryBuilder:_fieldOptions()
    local options = {}
    for i = 1, #self.fields do
        options[i] = self.fields[i].label or self.fields[i].key
    end
    return options
end

--- Emits the current rules.
function QueryBuilder:_emit()
    if self.onChange ~= nil then
        self.onChange(self, self.rules, self.combinator)
    end
end

--- Applies deferred rebuilds after a value-type change.
--- @param now number Current game-tick time in seconds.
--- @param dt number Seconds since the previous tick, 0..0.1.
function QueryBuilder:onUpdate(now, dt)
    if self._rebuildPending then
        self._rebuildPending = false
        self:_rebuild()
    end
end

--- Resizes the builder and re-runs the row layout.
--- @param x number New offset X from the parent's origin.
--- @param y number New offset Y from the parent's origin.
--- @param w number New width in pixels.
--- @param h number New height in pixels; 0 keeps automatic height.
--- @return PallidQueryBuilder self For chaining.
function QueryBuilder:setBounds(x, y, w, h)
    Widgets.Widget.setBounds(self, x, y, w, h)
    if h == nil or h <= 0 then
        self.autoHeight = true
    end
    self:_rebuild()
    return self
end
