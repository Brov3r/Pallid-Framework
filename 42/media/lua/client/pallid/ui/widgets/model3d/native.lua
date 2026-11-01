require "pallid/ui/internal"

-- Both wrappers are plain ISUIElement subclasses. ISUI3DScene is the same
-- vehicle preview surface used by the vanilla vehicle editor, so it can render
-- a vehicle from its script name without spawning one in the world.
if ISUI3DModel == nil then
    pcall(require, "ISUI/ISUI3DModel")
end
if ISUI3DScene == nil then
    pcall(require, "Vehicles/ISUI/ISUI3DScene")
end

Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

-- A failed native setup is retried occasionally: OutfitManager can be
-- unavailable on the main menu or during a reload, and a permanent latch would
-- leave the widget in the 2D fallback for the rest of the session.
local NATIVE_RETRY_SECONDS = 2

--- True when a game world is loaded. Used for the named-outfit path, which is
--- the only source that depends on AnimatedModel.update dressing it later.
--- @return boolean available True when the native API is available.
local function gameCellAvailable()
    if type(getCell) ~= "function" then
        return false
    end
    local ok, cell = pcall(getCell)
    return ok and cell ~= nil
end

--- Returns the game timestamp in seconds when the Lua host exposes it.
--- @return number|nil seconds Seconds, or nil.
local function nowSeconds()
    if type(getTimestamp) == "function" then
        local ok, value = pcall(getTimestamp)
        if ok and type(value) == "number" then
            return value
        end
    end
    return nil
end

--- Declines every native mouse event. The model is an always-on-top UIManager
--- widget, so without this its own handlers would capture drags and the Pallid
--- host underneath would never see the press. Returning false, together with
--- javaObject:setConsumeMouseEvents(false), makes UIManager fall through.
--- @param ... any Arguments forwarded to the wrapped call.
--- @return boolean handled True when the event was handled.
local function nativeDecline(...) -- luacheck: ignore
    return false
end

--- Mirrors Input's subtree check: an overlay must not hide its own children.
--- @param element PallidWidget Widget to test.
--- @param overlay PallidWidget Overlay widget involved in the check.
--- @return boolean True when the element belongs to the overlay's subtree.
local function isInsideOverlay(element, overlay)
    local node = element
    while node ~= nil do
        if node == overlay then
            return true
        end
        node = node.parent
    end
    return false
end

--- Builds and registers the native model. Kept outside the class so the whole
--- setup can be pcall'd: a broken OutfitManager or a headless Lua host must fall
--- back to the 2D placeholder instead of aborting the UI frame. The event
--- handlers are replaced because ISUI3DModel captures drags itself; with
--- consumeMouseEvents cleared, UIManager passes the same press to the Pallid
--- host below the always-on-top model.
--- @param w number Width in pixels.
--- @param h number Height in pixels.
--- @param isVehicle boolean Selects ISUI3DScene instead of ISUI3DModel.
--- @return ISUI3DModel|ISUI3DScene Native model or scene instance.
local function createNative(w, h, isVehicle)
    local class
    if isVehicle then
        class = ISUI3DScene
    else
        class = ISUI3DModel
    end
    if class == nil then
        error(isVehicle and "ISUI3DScene is unavailable" or "ISUI3DModel is unavailable", 0)
    end
    local model = class:new(0, 0, w, h)
    -- ISUIElement clamps a root element to the screen; a model inside a window
    -- that is dragged partly off-screen must follow the window instead.
    model.keepOnScreen = false

    local added = false
    local ok, err = pcall(function()
        model:initialise()
        model:instantiate()
        model:addToUIManager()
        added = true
        model:setVisible(false)
        if model.setAlwaysOnTop ~= nil then
            model:setAlwaysOnTop(true)
        end

        model.onMouseDown        = nativeDecline
        model.onMouseUp          = nativeDecline
        model.onMouseMove        = nativeDecline
        model.onMouseMoveOutside = nativeDecline
        model.onMouseUpOutside   = nativeDecline
        -- The vehicle scene has its own working wheel zoom; let it consume the
        -- wheel so zoom does not depend on host routing. Character wheel input
        -- stays with the Pallid widget because UI3DModel has no zoom handler.
        if not isVehicle then
            model.onMouseWheel = nativeDecline
        end
        model.mouseDown          = false
        if model.javaObject ~= nil and model.javaObject.setConsumeMouseEvents ~= nil then
            model.javaObject:setConsumeMouseEvents(false)
        end

        if isVehicle then
            -- Mirror the vanilla vehicle-editor preview: one script-driven
            -- vehicle, no grid, geometry overlays or gizmos.
            model.background = false
            local java = model.javaObject
            java:fromLua1("setDrawGrid", false)
            java:fromLua1("setDrawGridAxes", false)
            java:fromLua1("setDrawGeometry", false)
            java:fromLua1("setGizmoVisible", "none")
            java:fromLua1("setGizmoOrigin", "none")
            java:fromLua1("createVehicle", "vehicle")
            java:fromLua1("setZoom", 5)
        end
    end)

    if not ok then
        -- pcall cannot roll back a registration that already happened. Leaving
        -- the half-built element in UIManager would draw a ghost preview.
        if added and model.removeFromUIManager ~= nil then
            pcall(model.removeFromUIManager, model)
        end
        error(err, 0)
    end

    return model
end

--- Adds native lifecycle, source application and overlay masking to the class.
--- @param Model3D table PallidModel3D class.
--- @param isNonBlank fun(value: any): boolean Shared string check.
--- @return fun Augmenter that installs the methods.
return function(Model3D, isNonBlank)
    --- Reports a failed native setup once per distinct error and schedules a
    --- retry. Repeated identical failures would otherwise flood the log.
    --- @param self PallidModel3D Model instance.
    --- @param err any Error value.
    function Model3D:_markNativeFailed(err)
        local text = tostring(err)
        if self._nativeLastError ~= text then
            self._nativeLastError = text
            Pallid.error("Model3D: native model setup failed:", text)
        end
        self._nativeFailed = true
        local now = nowSeconds()
        self._nativeRetryAt = now ~= nil and (now + NATIVE_RETRY_SECONDS) or nil
    end

    --- Removes the native entry from the root registry, if any.
    function Model3D:_unregisterRoot()
        local root = self._nativeRoot
        if root ~= nil then
            if root.unregisterNative ~= nil then
                root:unregisterNative(self)
            end
            self._nativeRoot = nil
        end
    end

    --- Hides the native model without destroying it. Safe when no model exists.
    function Model3D:_hideNative()
        local model = self.model
        if model ~= nil and model.javaObject ~= nil then
            model:setVisible(false)
        end
    end

    --- Detaches the native element from UIManager and drops every cached
    --- position. The Java clothing listener cannot be removed from Lua, so
    --- callers should reuse a model instead of creating one per window.
    function Model3D:_releaseNative()
        self:_unregisterRoot()
        local model = self.model
        self.model = nil
        self._nativeKind = nil
        self._nativeLocalX = nil
        self._nativeLocalY = nil
        self._nativeW = nil
        self._nativeH = nil
        if model == nil then
            return
        end
        pcall(function()
            if model.javaObject ~= nil then
                model:setVisible(false)
            end
            if model.removeFromUIManager ~= nil then
                local removed = model.isRemoved ~= nil and model:isRemoved()
                if not removed then
                    model:removeFromUIManager()
                end
            end
        end)
    end

    --- Releases a native of the wrong class before a source switch. The two
    --- wrappers expose different methods (setVehicle vs setCharacter), so a
    --- character cannot be pushed into a vehicle native or vice versa.
    --- @param kind string "character" or "vehicle".
    function Model3D:_prepareNativeKind(kind)
        if self.model == nil or self._nativeKind == kind then
            return
        end
        self:_releaseNative()
        self._nativeFailed = false
        self._nativeRetryAt = nil
        self._nativeLastError = nil
    end

    --- True when the native model can be rendered in the current context.
    --- A SurvivorDesc or a character calls setModelData synchronously, which is
    --- exactly what the character-creation preview uses on the main menu. A
    --- named outfit is dressed later by AnimatedModel.update, so it needs a
    --- live player and a loaded ModelManager; otherwise SetForceDir crashes on
    --- a null ModelInstance (UI3DModel.java render path). A vehicle script is
    --- rendered by ISUI3DScene and only needs a loaded cell.
    --- @return boolean available True when the native API is available.
    function Model3D:_nativeContextAvailable()
        if self.survivorDesc ~= nil or self.character ~= nil then
            return true
        end
        if self.vehicle ~= nil or isNonBlank(self.vehicleScript) then
            return true
        end
        if not gameCellAvailable() then
            return false
        end
        if type(getPlayer) ~= "function" then
            return false
        end
        local ok, player = pcall(getPlayer)
        return ok and player ~= nil
    end

    --- Creates the native model on first use. Returns nil on the main menu, in a
    --- headless harness, or when creation failed, so the caller draws the
    --- fallback instead of crashing.
    --- @return ISUI3DModel|ISUI3DScene|nil Native model on success, or nil.
    function Model3D:_ensureNative()
        local model = self.model
        if model ~= nil then
            return model
        end
        local isVehicle = self.vehicle ~= nil or isNonBlank(self.vehicleScript)
        local class
        if isVehicle then
            class = ISUI3DScene
        else
            class = ISUI3DModel
        end
        if class == nil then
            return nil
        end
        if not self:_nativeContextAvailable() then
            return nil
        end
        if self._nativeFailed then
            local now = nowSeconds()
            if self._nativeRetryAt == nil or now == nil or now < self._nativeRetryAt then
                return nil
            end
        end

        local ok, created = pcall(createNative, math.max(1, self.w), math.max(1, self.h), isVehicle)
        if not ok or created == nil then
            self:_markNativeFailed(created)
            return nil
        end

        self.model = created
        self._nativeKind = isVehicle and "vehicle" or "character"
        -- Option application is a separate failure boundary: a valid native
        -- with default options is still useful, but a Lua error must not abort
        -- the host frame.
        local applied, applyErr = pcall(function()
            self:_applySource()
            self:_applyOptions()
        end)
        if not applied then
            self:_releaseNative()
            self:_markNativeFailed(applyErr)
            return nil
        end

        self._nativeFailed = false
        self._nativeRetryAt = nil
        self._nativeLastError = nil
        return created
    end

    --- Resolves the vehicle script shown by ISUI3DScene. A script name is enough
    --- for a test preview; a live BaseVehicle is reduced to its script, because
    --- the editor scene renders the script model rather than damage state.
    --- @return string|nil scriptName Vehicle script name, or nil.
    function Model3D:_vehicleScriptName()
        if isNonBlank(self.vehicleScript) then
            return self.vehicleScript
        end
        local vehicle = self.vehicle
        if vehicle == nil or vehicle.getScript == nil then
            return nil
        end
        local ok, script = pcall(vehicle.getScript, vehicle)
        if not ok or script == nil or script.getFullName == nil then
            return nil
        end
        local okName, name = pcall(script.getFullName, script)
        if okName and isNonBlank(name) then
            return name
        end
        return nil
    end

    --- Pushes the current character/outfit/survivorDesc into an existing native.
    --- When the widget has no source, the native visual is cleared through
    --- setCharacter(nil): AnimatedModel.setCharacter releases the old visual,
    --- while setOutfitName(nil) alone would leave it in place.
    function Model3D:_applySource()
        local model = self.model
        if model == nil or model.javaObject == nil then
            return
        end
        if self._nativeKind == "vehicle" then
            local scriptName = self:_vehicleScriptName()
            if scriptName ~= nil then
                model.javaObject:fromLua2("setVehicleScript", "vehicle", scriptName)
            end
            return
        end
        if self.character ~= nil then
            model:setCharacter(self.character)
        elseif self.survivorDesc ~= nil then
            model:setSurvivorDesc(self.survivorDesc)
        elseif type(self.outfitName) == "string" and self.outfitName:find("%S") ~= nil then
            model:setOutfitName(self.outfitName, self.outfitFemale, self.outfitZombie)
        else
            -- UI3DModel.setCharacter(nil) is the only exposed way to clear a
            -- dressed visual; see AnimatedModel.setCharacter in the game jar.
            model:setCharacter(nil)
        end
    end

    --- Pushes playback and framing options into an existing native.
    function Model3D:_applyOptions()
        local model = self.model
        if model == nil or model.javaObject == nil then
            return
        end
        if self._nativeKind == "vehicle" then
            if self.interactive and self.wheelZoom then
                model.onMouseWheel = nil
            else
                model.onMouseWheel = nativeDecline
            end
            if self.vehicleView ~= nil and model.setView ~= nil then
                model:setView(self.vehicleView)
            elseif model.javaObject ~= nil then
                model.javaObject:fromLua1("setView", "UserDefined")
                model.javaObject:fromLua3(
                    "setViewRotation",
                    self._vehiclePitch or 0, self._vehicleYaw or 90, 0
                )
            end
            return
        end
        if type(self.animSet) == "string" and self.animSet:find("%S") ~= nil then
            model:setAnimSetName(self.animSet)
        end
        if self.state ~= nil then
            model:setState(self.state)
        end
        if self.isometric ~= nil then
            model:setIsometric(self.isometric)
        end
        model:setAnimateWhilePaused(self.animateWhilePaused)
        model:setZoom(self.zoom)
        model:setXOffset(self.xOffset)
        model:setYOffset(self.yOffset)
        if self.direction ~= nil then
            model:setDirection(self.direction)
        end
        if self.randomExtAnimations and model.setDoRandomExtAnimations ~= nil then
            model:setDoRandomExtAnimations(true)
        end
    end

    --- Applies the orbit angles to the vehicle scene. UI3DScene.dragView pans the
    --- camera, so rotation is done through the UserDefined view rotation instead.
    function Model3D:_applyVehicleRotation()
        local model = self.model
        if model ~= nil and model.javaObject ~= nil and model.javaObject.fromLua3 ~= nil then
            model.javaObject:fromLua1("setView", "UserDefined")
            model.javaObject:fromLua3(
                "setViewRotation",
                self._vehiclePitch or 0, self._vehicleYaw or 90, 0
            )
        end
    end

    --- Positions the native over the viewport and registers it on the root so
    --- overlays can mask it later in the frame.
    --- @param el ISUIElement Host element used for drawing.
    --- @param x number X coordinate.
    --- @param y number Y coordinate.
    --- @param w number Width in pixels.
    --- @param h number Height in pixels.
    function Model3D:_positionNative(el, x, y, w, h)
        local model = self.model
        if model == nil or model.javaObject == nil then
            return
        end
        local absoluteX = el:getAbsoluteX() + x
        local absoluteY = el:getAbsoluteY() + y

        model:setX(absoluteX)
        model:setY(absoluteY)
        model:setWidth(w)
        model:setHeight(h)
        model:setVisible(true)

        self._nativeLocalX = x
        self._nativeLocalY = y
        self._nativeW = w
        self._nativeH = h

        local root = self:getRoot()
        if root ~= nil and root ~= self and root.registerNative ~= nil and self._nativeRoot ~= root then
            self:_unregisterRoot()
            self._nativeRoot = root
            root:registerNative(self)
        end
    end

    --- Hides or shows the native model. The host calls this with false before a
    --- frame, so a tab or window that does not draw this widget leaves it hidden.
    --- @param visible boolean Whether the element is visible.
    function Model3D:setNativeVisible(visible)
        if not visible then
            self:_hideNative()
        end
    end

    --- The model has no text focus, but overlays call this on every registered
    --- native child; it must exist so a modal does not error here.
    function Model3D:blurNative()
    end

    --- Hides the native model when an overlay rectangle covers it. The overlay's
    --- own models stay visible.
    --- @param overlay PallidWidget Overlay that clips the native model.
    --- @param x number X coordinate.
    --- @param y number Y coordinate.
    --- @param w number Width in pixels.
    --- @param h number Height in pixels.
    function Model3D:maskNative(overlay, x, y, w, h)
        local model = self.model
        if model == nil or isInsideOverlay(self, overlay) then
            return
        end
        local mx, my = self._nativeLocalX, self._nativeLocalY
        local mw = self._nativeW or self.w
        local mh = self._nativeH or self.h
        if mx == nil or my == nil then
            return
        end
        if mx < x + w and mx + mw > x and my < y + h and my + mh > y then
            self:_hideNative()
        end
    end

    --- Hides the native model unless it belongs to the overlay's subtree. Used by
    --- the modal backdrop, which covers the whole root.
    --- @param overlay PallidWidget Overlay that stays unmasked.
    function Model3D:maskNativeExcept(overlay)
        if self.model ~= nil and not isInsideOverlay(self, overlay) then
            self:_hideNative()
        end
    end

    --- Hides the model when the widget leaves the tree. Keep the native object
    --- for a reparent; an explicit destroy() releases it for good.
    function Model3D:onDetach()
        self:_hideNative()
        self:_unregisterRoot()
        self._dragging = false
        self._dragAccum = 0
        self._lastMouseX = nil
        self._lastMouseY = nil
    end

    --- Releases the native element. The widget keeps drawing the 2D fallback and
    --- will not recreate the model, so this is safe to call from a close handler.
    --- @return PallidModel3D self The same instance, for chaining.
    function Model3D:destroy()
        self:_releaseNative()
        self._nativeKind = nil
        self._nativeFailed = true
        self._nativeRetryAt = nil
        self._nativeLastError = nil
        return self
    end
end
