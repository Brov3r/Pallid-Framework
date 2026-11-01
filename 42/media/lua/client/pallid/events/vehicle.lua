require "utils/logger"
require "pallid/events/core"

Pallid = Pallid or {}

--- Event emitted when a character enters a vehicle.
--- Parameters: character and vehicle.
local EVENT_ENTERED = "Pallid_VehicleEntered"

--- Event emitted when a character exits a vehicle.
--- Parameters: character and vehicle.
local EVENT_EXITED = "Pallid_VehicleExited"

--- Event emitted when a vehicle door is opened or closed.
--- Parameters: character, vehicle, part and open flag.
local EVENT_DOOR = "Pallid_VehicleDoorToggled"

--- Vehicle events emitted by the framework on the client.
---
--- The native `OnExitVehicle` fires after the character has already left the
--- vehicle, so `character:getVehicle()` is nil in its handlers. The module wraps
--- the timed actions instead, where both the character and the vehicle are
--- still available.
---
--- Side: client.
local internal = Pallid.Events._internal
internal.vehicle = internal.vehicle or {}

--- Installs the wrappers once the action classes are available.
local function install()
    if internal.vehicle.installed then
        return
    end

    internal.vehicle.installed = true

    Pallid.Events.ensure(EVENT_ENTERED)
    Pallid.Events.ensure(EVENT_EXITED)
    Pallid.Events.ensure(EVENT_DOOR)

    --- Reports a completed entry.
    ---@param self table Finished action instance.
    local function reportEntered(self)
        Pallid.Events.emit(EVENT_ENTERED, self.character, self.vehicle)
    end

    --- Reports a completed exit.
    ---@param self table Finished action instance.
    local function reportExited(self)
        Pallid.Events.emit(EVENT_EXITED, self.character, self.vehicle)
    end

    --- Reports an opened door.
    ---@param self table Finished action instance.
    local function reportOpened(self)
        Pallid.Events.emit(EVENT_DOOR, self.character, self.vehicle, self.part, true)
    end

    --- Reports a closed door.
    ---@param self table Finished action instance.
    local function reportClosed(self)
        Pallid.Events.emit(EVENT_DOOR, self.character, self.vehicle, self.part, false)
    end

    local missing = {}

    if not Pallid.Events.wrapAction(ISEnterVehicle, "perform", reportEntered) then
        missing[#missing + 1] = "ISEnterVehicle.perform"
    end
    if not Pallid.Events.wrapAction(ISExitVehicle, "perform", reportExited) then
        missing[#missing + 1] = "ISExitVehicle.perform"
    end
    if not Pallid.Events.wrapAction(ISOpenVehicleDoor, "perform", reportOpened) then
        missing[#missing + 1] = "ISOpenVehicleDoor.perform"
    end
    if not Pallid.Events.wrapAction(ISCloseVehicleDoor, "perform", reportClosed) then
        missing[#missing + 1] = "ISCloseVehicleDoor.perform"
    end

    if #missing > 0 then
        Pallid.error("vehicle actions unavailable:", table.concat(missing, ", "))
    end
end

--- Returns whether every wrapped action class is already defined.
---@return boolean ok True when all action classes are available.
local function actionsReady()
    return type(ISEnterVehicle) == "table"
        and type(ISExitVehicle) == "table"
        and type(ISOpenVehicleDoor) == "table"
        and type(ISCloseVehicleDoor) == "table"
end

if not internal.vehicle.installed and not internal.vehicle.scheduled then
    if actionsReady() then
        install()
    else
        internal.vehicle.scheduled = true
        Pallid.Events.once("OnGameBoot", install)
    end
end

return Pallid
