require "utils/logger"
require "pallid/events/core"

Pallid = Pallid or {}

--- Event emitted when a character finishes eating or drinking an item.
--- Parameters: character, item and kind (`"eat"` or `"drink"`).
local EVENT_CONSUMED = "Pallid_ItemConsumed"

--- Event emitted when a character starts reading a book.
--- Parameters: character and book item.
local EVENT_BOOK_STARTED = "Pallid_BookReadStarted"

--- Event emitted when a character finishes reading a book.
--- Parameters: character and book item.
local EVENT_BOOK_FINISHED = "Pallid_BookReadFinished"

--- Consumption and reading events emitted by the framework.
---
--- The engine has no event for eating, drinking or reading, so the module wraps
--- the matching timed actions. Wrappers are installed on `OnGameBoot` when the
--- action classes are not defined yet at load time.
---
--- Side: shared.
local internal = Pallid.Events._internal
internal.consumables = internal.consumables or {}

--- Installs the wrappers once the action classes are available.
local function install()
    if internal.consumables.installed then
        return
    end

    internal.consumables.installed = true

    Pallid.Events.ensure(EVENT_CONSUMED)
    Pallid.Events.ensure(EVENT_BOOK_STARTED)
    Pallid.Events.ensure(EVENT_BOOK_FINISHED)

    --- Reports a finished meal.
    ---@param self table Finished action instance.
    local function reportEat(self)
        Pallid.Events.emit(EVENT_CONSUMED, self.character, self.item, "eat")
    end

    --- Reports a finished drink.
    ---@param self table Finished action instance.
    local function reportDrink(self)
        Pallid.Events.emit(EVENT_CONSUMED, self.character, self.item, "drink")
    end

    --- Reports a reading session that has started.
    ---@param self table Started action instance.
    local function reportBookStarted(self)
        Pallid.Events.emit(EVENT_BOOK_STARTED, self.character, self.item)
    end

    --- Reports a finished reading session.
    ---@param self table Finished action instance.
    local function reportBookFinished(self)
        Pallid.Events.emit(EVENT_BOOK_FINISHED, self.character, self.item)
    end

    local missing = {}

    if not Pallid.Events.wrapAction(ISEatFoodAction, "perform", reportEat) then
        missing[#missing + 1] = "ISEatFoodAction.perform"
    end
    if not Pallid.Events.wrapAction(ISDrinkFromBottle, "perform", reportDrink) then
        missing[#missing + 1] = "ISDrinkFromBottle.perform"
    end
    if not Pallid.Events.wrapAction(ISReadABook, "start", reportBookStarted) then
        missing[#missing + 1] = "ISReadABook.start"
    end
    if not Pallid.Events.wrapAction(ISReadABook, "perform", reportBookFinished) then
        missing[#missing + 1] = "ISReadABook.perform"
    end

    if #missing > 0 then
        Pallid.error("consumption actions unavailable:", table.concat(missing, ", "))
    end
end

--- Returns whether every wrapped action class is already defined.
---@return boolean ok True when all action classes are available.
local function actionsReady()
    return type(ISEatFoodAction) == "table"
        and type(ISDrinkFromBottle) == "table"
        and type(ISReadABook) == "table"
end

if not internal.consumables.installed and not internal.consumables.scheduled then
    if actionsReady() then
        install()
    else
        internal.consumables.scheduled = true
        Pallid.Events.once("OnGameBoot", install)
    end
end

return Pallid
