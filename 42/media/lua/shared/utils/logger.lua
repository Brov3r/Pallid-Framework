Pallid = Pallid or {}

local ROOT_TAG = "Pallid"

--- Logger that writes prefixed lines through the game's DebugLog.
--- @class PallidLogger
--- @field tag string Prefix used for every line, e.g. "Pallid:Net".
local PallidLogger = {}
PallidLogger.__index = PallidLogger

--- Joins the arguments and writes one prefixed line through the game's DebugLog.
--- @param level string Label placed in the line, e.g. "INFO".
--- @param ... any Values to write on the line.
function PallidLogger:_write(level, ...)
    local parts = {}

    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end

    DebugLog.log(DebugType.Mod, "[" .. self.tag .. "] [" .. level .. "] " .. table.concat(parts, " "))
end

--- Writes an info line.
--- @param ... any Values to write on the line.
function PallidLogger:info(...)
    self:_write("INFO", ...)
end

--- Writes a warning line.
--- @param ... any Values to write on the line.
function PallidLogger:warn(...)
    self:_write("WARN", ...)
end

--- Only writes a line. Does not throw: use error() for broken invariants.
--- @param ... any Values to write on the line.
function PallidLogger:error(...)
    self:_write("ERROR", ...)
end

--- Creates a logger whose lines are prefixed with "[Pallid:<moduleName>]".
--- @param moduleName string Module name used in the prefix.
--- @return PallidLogger New logger.
function Pallid.getLogger(moduleName)
    local self = setmetatable({}, PallidLogger)
    self.tag = ROOT_TAG .. ":" .. tostring(moduleName)
    return self
end

-- Default logger behind the shortcuts below ("[Pallid]" prefix).
local defaultLogger = Pallid.getLogger("Core")

--- Writes an info line.
--- @param ... any Values to write on the line.
function Pallid.log(...)
    defaultLogger:info(...)
end

--- Writes a warning line.
--- @param ... any Values to write on the line.
function Pallid.warn(...)
    defaultLogger:warn(...)
end

--- Writes an error line.
--- @param ... any Values to write on the line.
function Pallid.error(...)
    defaultLogger:error(...)
end

return Pallid
