Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

--- Domains the engine lets Lua hand to the operating system. `openUrl` in
--- LuaManager is guarded by `LuaManager.isIndieStoneUrl`
--- (LuaManager.java:1273-1275), and `activateSteamOverlayToWebPage` uses the
--- same whitelist (LuaManager.java:7601-7606). Anything else is ignored by the
--- engine, so Pallid copies it to the clipboard instead of silently doing
--- nothing.
local ALLOWED = {
    "https://steamcommunity.com",
    "https://projectzomboid.com",
    "https://theindiestone.com",
    "https://pzwiki.net",
}

--- @param url string URL to check.
--- @return boolean True when the engine will hand the URL to the browser.
local function isAllowed(url)
    for i = 1, #ALLOWED do
        local prefix = ALLOWED[i]
        if url == prefix or string.sub(url, 1, #prefix + 1) == prefix .. "/" then
            return true
        end
    end
    return false
end

--- Opens a hyperlink from Lua.
---
--- The only browser bridge exported to Lua is the global `openUrl`, and it
--- refuses every non-Indie-Stone URL. There is no exposed `java.awt.Desktop`
--- or `Runtime.exec` (LuaManager's exposure list has neither), so a mod cannot
--- open an arbitrary site. This helper:
---   1. opens whitelisted URLs in the system browser via `openUrl`;
---   2. tries the Steam overlay when it is available and the URL is allowed;
---   3. otherwise copies the URL to the clipboard and reports "clipboard".
--- The caller can show that status to the player.
--- @param url string|nil URL to open; nil is rejected.
--- @return boolean opened True when the browser (or Steam overlay) accepted it.
--- @return string how "browser"|"overlay"|"clipboard"|"invalid"|"unsupported".
function Pallid.UI.openUrl(url)
    if type(url) ~= "string" or url == "" then
        return false, "invalid"
    end

    if isAllowed(url) then
        if isDesktopOpenSupported ~= nil and isDesktopOpenSupported() and openUrl ~= nil then
            local ok = pcall(openUrl, url)
            if ok then
                return true, "browser"
            end
        end
        -- No SteamUtils guard here: SteamUtils is not exposed to Lua. The
        -- engine's activateSteamOverlayToWebPage already checks
        -- SteamUtils.isOverlayEnabled() itself (LuaManager.java:7603) and
        -- quietly ignores the call when the overlay is off.
        if activateSteamOverlayToWebPage ~= nil then
            local ok = pcall(activateSteamOverlayToWebPage, url)
            if ok then
                return true, "overlay"
            end
        end
    end

    if Clipboard ~= nil and Clipboard.setClipboard ~= nil then
        local ok = pcall(Clipboard.setClipboard, url)
        if ok then
            return false, "clipboard"
        end
    end
    return false, "unsupported"
end
