require "utils/logger"
require "pallid/events/core"

Pallid = Pallid or {}

--- Event emitted when the local player sends a chat message.
--- Parameters: stream name and raw text.
local EVENT_SENT = "Pallid_ChatMessageSent"

--- Event emitted when the local player sends a slash command.
--- Parameters: raw command.
local EVENT_COMMAND = "Pallid_ChatCommandSent"

--- Event emitted when a chat message is added to a tab.
--- Parameters: author, text and tab id.
local EVENT_RECEIVED = "Pallid_ChatMessageReceived"

--- Event emitted when a server alert is added to a tab.
--- Parameters: text and tab id.
local EVENT_ALERT = "Pallid_ChatAlertReceived"

--- Chat events emitted by the framework.
---
--- The module wraps the native chat senders and the two chat message events.
--- All four events fire on the client only: the engine has no server-side Lua
--- event for incoming chat, and the chat senders are client globals.
---
--- Side: client.
local internal = Pallid.Events._internal
internal.chat = internal.chat or {}

if not internal.chat.installed then
    Pallid.Events.ensure(EVENT_SENT)
    Pallid.Events.ensure(EVENT_COMMAND)
    Pallid.Events.ensure(EVENT_RECEIVED)
    Pallid.Events.ensure(EVENT_ALERT)

    --- Wraps one chat stream sender so a sent message is reported.
    ---@param globalName string Name of the global sender function.
    ---@param stream string Chat stream name reported with the event.
    ---@return boolean ok True when the global was wrapped.
    local function wrapStream(globalName, stream)
        local original = _G[globalName]
        if type(original) ~= "function" then
            return false
        end

        --- Reports the message, then forwards the call to the native sender.
        ---@param text string Raw input typed by the player.
        ---@return any result Value returned by the native sender.
        local function wrapped(text)
            local result = original(text)
            Pallid.Events.emit(EVENT_SENT, stream, text)
            return result
        end

        _G[globalName] = wrapped
        return true
    end

    --- Wraps the whisper sender, which also returns the parsed target name.
    ---@return boolean ok True when the global was wrapped.
    local function wrapWhisper()
        local original = _G.proceedPM
        if type(original) ~= "function" then
            return false
        end

        --- Reports the whisper only when the target name was parsed.
        ---@param command string Raw input typed by the player.
        ---@return any result Parsed target name or the native result.
        local function wrapped(command)
            local result = original(command)
            if result ~= nil then
                Pallid.Events.emit(EVENT_SENT, "whisper", command)
            end
            return result
        end

        _G.proceedPM = wrapped
        return true
    end

    --- Wraps the slash command sender.
    ---@return boolean ok True when the global was wrapped.
    local function wrapCommand()
        local original = _G.SendCommandToServer
        if type(original) ~= "function" then
            return false
        end

        --- Reports the command, then forwards the call to the native sender.
        ---@param command string Raw slash command.
        ---@return any result Value returned by the native sender.
        local function wrapped(command)
            local result = original(command)
            Pallid.Events.emit(EVENT_COMMAND, command)
            return result
        end

        _G.SendCommandToServer = wrapped
        return true
    end

    local missing = {}

    if not wrapStream("processSayMessage", "say") then
        missing[#missing + 1] = "processSayMessage"
    end

    if not wrapStream("processShoutMessage", "yell") then
        missing[#missing + 1] = "processShoutMessage"
    end

    if not wrapStream("proceedFactionMessage", "faction") then
        missing[#missing + 1] = "proceedFactionMessage"
    end

    if not wrapStream("processSafehouseMessage", "safehouse") then
        missing[#missing + 1] = "processSafehouseMessage"
    end

    if not wrapStream("processAdminChatMessage", "admin") then
        missing[#missing + 1] = "processAdminChatMessage"
    end

    if not wrapStream("processGeneralMessage", "general") then
        missing[#missing + 1] = "processGeneralMessage"
    end

    if not wrapWhisper() then
        missing[#missing + 1] = "proceedPM"
    end

    if not wrapCommand() then
        missing[#missing + 1] = "SendCommandToServer"
    end

    if #missing > 0 then
        Pallid.error("chat senders unavailable:", table.concat(missing, ", "))
    end

    --- Reports a chat message that was added to a tab.
    ---@param message ChatMessage|nil Message object supplied by the engine.
    ---@param tabId integer Tab the message was added to.
    local function onAddMessage(message, tabId)
        if message == nil then
            return
        end

        Pallid.Events.emit(EVENT_RECEIVED, message:getAuthor(), message:getText(), tabId)
    end

    --- Reports a server alert that was added to a tab.
    ---@param message ChatMessage|nil Alert message supplied by the engine.
    ---@param tabId integer Tab the alert was added to.
    local function onAlertMessage(message, tabId)
        if message == nil then
            return
        end

        Pallid.Events.emit(EVENT_ALERT, message:getText(), tabId)
    end

    Pallid.Events.add("OnAddMessage", onAddMessage)
    Pallid.Events.add("OnAlertMessage", onAlertMessage)

    internal.chat.installed = true
end

return Pallid
