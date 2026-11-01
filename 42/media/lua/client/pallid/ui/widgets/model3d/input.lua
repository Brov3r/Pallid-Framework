Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

-- Vanilla ISUI3DModel turns one step per 40 px of horizontal drag.
local DRAG_STEP = 40
-- UI3DModel renders at size - zoom, so a positive wheel step zooms out. One
-- step is intentionally large enough to be visible on a 300 px preview.
local WHEEL_STEP = 1

--- Adds drag rotation, wheel zoom and auto-rotation to the model class.
--- @param Model3D table PallidModel3D class.
--- @return fun Augmenter that installs the methods.
return function(Model3D)
    --- Cancels the active drag and restarts the auto-rotate timer.
    function Model3D:_cancelDrag()
        self._dragging = false
        self._dragAccum = 0
        self._lastMouseX = nil
        self._lastMouseY = nil
        self._rotateT = 0
    end

    --- Advances state once per frame.
    --- @param now number Current time in seconds.
    --- @param dt number Seconds since the previous frame.
    function Model3D:onUpdate(now, dt) -- luacheck: ignore
        if self._dragging or not self.autoRotate or self.rotateInterval <= 0 or not self.enabled then
            self._rotateT = 0
            return
        end
        -- A frozen model that keeps turning looks broken. The native animation
        -- is stopped by prerender while paused, so the rotation follows it.
        if not self.animateWhilePaused and type(isGamePaused) == "function" and isGamePaused() then
            self._rotateT = 0
            return
        end
        self._rotateT = self._rotateT + dt
        while self._rotateT >= self.rotateInterval do
            self._rotateT = self._rotateT - self.rotateInterval
            self:_rotate(1)
        end
    end

    --- Turns the model one 45-degree step. IsoDirectionSet.rotate is the same
    --- helper the vanilla ISUI3DModel drag uses.
    --- @param sign integer -1 counter-clockwise, 1 clockwise.
    function Model3D:_rotate(sign)
        if self._nativeKind == "vehicle" then
            self._vehicleYaw = ((self._vehicleYaw or 90) + sign * 45) % 360
            self:_applyVehicleRotation()
            return
        end

        local direction = self.direction
        if direction == nil and IsoDirections ~= nil then
            direction = IsoDirections.E
        end
        if direction == nil or IsoDirectionSet == nil or IsoDirectionSet.rotate == nil then
            return
        end

        local model = self.model
        if model ~= nil and model.javaObject ~= nil and model.getDirection ~= nil then
            -- Read the model back so a setDirection() from outside is not undone
            -- by a stale cached value.
            local current = model:getDirection()
            if current ~= nil then
                direction = current
            end
        end

        self:setDirection(IsoDirectionSet.rotate(direction, sign))
    end

    --- Drag horizontally to rotate. The root keeps the capture, so the drag keeps
    --- working outside the widget.
    --- @param px number Pointer X in local coordinates.
    --- @param py number Pointer Y in local coordinates.
    --- @param button string|nil "left" or "right".
    --- @return boolean True when the press was handled.
    function Model3D:onDown(px, py, button)
        if not self.enabled or not self.interactive or not self.dragRotate or button == "right" then
            return false
        end
        self._dragging = true
        self._dragAccum = 0
        self._lastMouseX = px
        self._lastMouseY = py
        self._rotateT = 0
        return true
    end

    --- Handles pointer movement.
    --- @param px number Pointer X in local coordinates.
    --- @param py number Pointer Y in local coordinates.
    function Model3D:onMove(px, py)
        if not self._dragging then
            return
        end
        local last = self._lastMouseX
        local lastY = self._lastMouseY
        self._lastMouseX = px
        self._lastMouseY = py
        if last == nil then
            return
        end

        local dx = px - last
        local dy = lastY ~= nil and (py - lastY) or 0
        self._dragAccum = self._dragAccum + dx
        if self._nativeKind == "vehicle" then
            self._vehicleYaw = ((self._vehicleYaw or 90) + dx * 0.5) % 360
            self._vehiclePitch = math.max(-80, math.min(80, (self._vehiclePitch or 0) + dy * 0.5))
            self:_applyVehicleRotation()
            self._dragAccum = 0
            return
        end
        -- Consume whole steps so a fast flick turns several times instead of once.
        while self._dragAccum >= DRAG_STEP or self._dragAccum <= -DRAG_STEP do
            local step = self._dragAccum > 0 and DRAG_STEP or -DRAG_STEP
            self._dragAccum = self._dragAccum - step
            self:_rotate(step > 0 and 1 or -1)
        end
    end

    --- Handles a pointer release.
    --- @param px number Pointer X in local coordinates.
    --- @param py number Pointer Y in local coordinates.
    function Model3D:onUp(px, py) -- luacheck: ignore
        self:_cancelDrag()
    end

    --- Handles a mouse-wheel event.
    --- @param delta number UIManager convention: positive is wheel down.
    --- @return boolean handled True when the event was handled.
    function Model3D:onWheel(delta)
        if not self.enabled or not self.interactive or not self.wheelZoom then
            return false
        end
        if self._nativeKind == "vehicle" then
            local vehicle = self.model
            if vehicle ~= nil and vehicle.javaObject ~= nil and vehicle.javaObject.fromLua1 ~= nil then
                vehicle.javaObject:fromLua1("zoom", delta)
            end
            return true
        end
        self:setZoom(self.zoom + delta * WHEEL_STEP)
        return true
    end

    --- Enables or disables auto-rotation.
    --- @param enabled boolean Whether the feature is enabled.
    --- @return PallidModel3D self The same instance, for chaining.
    function Model3D:setAutoRotate(enabled)
        self.autoRotate = enabled == true
        self._rotateT = 0
        return self
    end

    --- Sets the auto-rotation interval.
    --- @param seconds number Seconds between auto-rotate steps; zero disables the timer.
    --- @return PallidModel3D self The same instance, for chaining.
    function Model3D:setRotateInterval(seconds)
        if type(seconds) ~= "number" or seconds < 0 then
            return self
        end
        self.rotateInterval = seconds
        self._rotateT = 0
        return self
    end
end
