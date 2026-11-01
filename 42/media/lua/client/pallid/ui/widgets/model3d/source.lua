Pallid = Pallid or {}
Pallid.UI = Pallid.UI or {}

--- Checks whether a name matches an existing vehicle script.
--- @param name string|nil Vehicle script name, or nil.
--- @return boolean valid True when the script exists, or when ScriptManager is unavailable.
local function isVehicleScriptName(name)
    if type(name) ~= "string" or name:find("%S") == nil then
        return false
    end
    if type(getScriptManager) ~= "function" then
        return true
    end
    local ok, manager = pcall(getScriptManager)
    if not ok or manager == nil then
        return true
    end
    local okGet, script = pcall(manager.getVehicle, manager, name)
    return okGet and script ~= nil
end

--- Adds the source-selection setters to the model class. They all keep exactly
--- one renderable source, because ISUI3DModel and ISUI3DScene expose different
--- setters and cannot share one native.
--- @param Model3D table PallidModel3D class.
--- @param isNonBlank fun(value: any): boolean String check shared with the core.
--- @param isInstanceOf fun(value: any, className: string): boolean Java type check.
--- @return fun Augmenter that installs the methods.
return function(Model3D, isNonBlank, isInstanceOf)
    --- Shows the built-in character dummy: a named outfit without a live
    --- IsoGameCharacter. This is the fallback used by the constructor when no
    --- source is supplied.
    --- @param outfit string|nil Outfit name from clothing.xml. Defaults to the last dummy outfit.
    --- @param female boolean|nil True for a female model.
    --- @return PallidModel3D self The same instance, for chaining.
    function Model3D:setDummy(outfit, female)
        local name = isNonBlank(outfit) and outfit or self.dummyOutfit
        self.dummy = true
        self.dummyOutfit = name
        self.dummyFemale = female == true
        self.character = nil
        self.survivorDesc = nil
        self.vehicle = nil
        self.vehicleScript = nil
        self.outfitName = name
        self.outfitFemale = self.dummyFemale
        self.outfitZombie = false
        self:_prepareNativeKind("character")
        self:_applySource()
        return self
    end

    --- Sets the character source.
    --- @param character IsoGameCharacter|nil Live character source; nil clears it.
    --- @return PallidModel3D self The same instance, for chaining.
    function Model3D:setCharacter(character)
        if character ~= nil and not isInstanceOf(character, "IsoGameCharacter") then
            Pallid.warn("Model3D:setCharacter expects an IsoGameCharacter")
            return self
        end
        self.character = character
        self.outfitName = nil
        self.survivorDesc = nil
        self.vehicle = nil
        self.vehicleScript = nil
        self.dummy = false
        if character ~= nil then
            self:_prepareNativeKind("character")
        end
        self:_applySource()
        return self
    end

    --- Sets the outfit source.
    --- @param name string|nil Outfit name from clothing.xml; nil clears the source.
    --- @param female boolean|nil True for a female model.
    --- @param zombie boolean|nil True for a zombie model.
    --- @return PallidModel3D self The same instance, for chaining.
    function Model3D:setOutfit(name, female, zombie)
        if name ~= nil and not isNonBlank(name) then
            Pallid.warn("Model3D:setOutfit ignores a blank outfit name")
            name = nil
        end
        self.dummy = false
        self.outfitName = name
        self.outfitFemale = female == true
        self.outfitZombie = zombie == true
        self.character = nil
        self.survivorDesc = nil
        self.vehicle = nil
        self.vehicleScript = nil
        if name ~= nil then
            self:_prepareNativeKind("character")
        end
        self:_applySource()
        return self
    end

    --- Sets the survivor description.
    --- @param survivorDesc SurvivorDesc|nil Procedural survivor source; nil clears it.
    --- @return PallidModel3D self The same instance, for chaining.
    function Model3D:setSurvivorDesc(survivorDesc)
        if survivorDesc ~= nil and not isInstanceOf(survivorDesc, "SurvivorDesc") then
            Pallid.warn("Model3D:setSurvivorDesc expects a SurvivorDesc")
            return self
        end
        self.survivorDesc = survivorDesc
        self.character = nil
        self.outfitName = nil
        self.vehicle = nil
        self.vehicleScript = nil
        self.dummy = false
        if survivorDesc ~= nil then
            self:_prepareNativeKind("character")
        end
        self:_applySource()
        return self
    end

    --- Sets the vehicle source.
    --- @param vehicle BaseVehicle|nil Vehicle source; nil clears it.
    --- @return PallidModel3D self The same instance, for chaining.
    function Model3D:setVehicle(vehicle)
        if vehicle ~= nil and not isInstanceOf(vehicle, "BaseVehicle") then
            Pallid.warn("Model3D:setVehicle expects a BaseVehicle")
            return self
        end
        self.vehicle = vehicle
        self.vehicleScript = nil
        self.character = nil
        self.outfitName = nil
        self.survivorDesc = nil
        self.dummy = false
        if vehicle ~= nil then
            self:_prepareNativeKind("vehicle")
        end
        self:_applySource()
        return self
    end

    --- Shows a vehicle by script name, without spawning it in the world. This is
    --- the same script-driven path the vanilla vehicle editor uses.
    --- @param scriptName string|nil Vehicle script full name, e.g. "Base.CarNormal".
    --- @return PallidModel3D self The same instance, for chaining.
    function Model3D:setVehicleScript(scriptName)
        if scriptName ~= nil and not isVehicleScriptName(scriptName) then
            Pallid.warn("Model3D:setVehicleScript ignores an unknown vehicle script:", tostring(scriptName))
            scriptName = nil
        end
        self.vehicleScript = scriptName
        self.vehicle = nil
        self.character = nil
        self.outfitName = nil
        self.survivorDesc = nil
        self.dummy = false
        if scriptName ~= nil then
            self:_prepareNativeKind("vehicle")
        end
        self:_applySource()
        return self
    end

    --- Returns true for the placeholder model.
    --- @return boolean dummy True while the preview shows the built-in dummy.
    function Model3D:isDummy()
        return self.dummy == true
    end
end
