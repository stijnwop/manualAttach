--
-- ManualAttachingRegistrationHelper
--
-- Authors: Wopster
-- Description: The register class to load the specialization
--
-- Copyright (c) Wopster, 2015 - 2017

ManualAttachingRegistrationHelper = {
    baseDirectory = g_currentModDirectory
}

local function noopFunction()
end

-- replace the base mission function with a noop.. we don't want to use unnecessary resources
BaseMission.getAttachableInRange = Utils.overwrittenFunction(BaseMission.getAttachableInRange, noopFunction)

source(ManualAttachingRegistrationHelper.baseDirectory .. 'src/ManualAttaching.lua')

if SpecializationUtil.specializations['manualAttachingExtension'] == nil then
    SpecializationUtil.registerSpecialization('manualAttachingExtension', 'ManualAttachingExtension', ManualAttachingRegistrationHelper.baseDirectory .. 'src/vehicles/ManualAttachExtension.lua')
end

---
-- @param name
--
function ManualAttachingRegistrationHelper:loadMap(name)
    if not g_currentMission.manualAttachingRegistrationHelperIsLoaded then
        self:register()
        g_currentMission.manualAttachingRegistrationHelperIsLoaded = true
    else
        print("ManualAttaching - error: The ManualAttachingRegistrationHelper have been loaded already! Remove one of the copy's!")
    end
end

---
--
function ManualAttachingRegistrationHelper:deleteMap()
    if g_currentMission.manualAttachingRegistrationHelperIsLoaded then
        self:unregister()
        g_currentMission.manualAttachingRegistrationHelperIsLoaded = false
    end
end

---
-- @param ...
--
function ManualAttachingRegistrationHelper:keyEvent(...)
end

---
-- @param ...
--
function ManualAttachingRegistrationHelper:mouseEvent(...)
end

---
-- @param dt
--
function ManualAttachingRegistrationHelper:update(dt)
end

---
--
function ManualAttachingRegistrationHelper:draw()
end

---
--
function ManualAttachingRegistrationHelper:register()
    local extensionSpec = SpecializationUtil.getSpecialization('manualAttachingExtension')

    for _, vehicleType in pairs(VehicleTypeUtil.vehicleTypes) do
        if vehicleType ~= nil
                and SpecializationUtil.hasSpecialization(Attachable, vehicleType.specializations)
                or SpecializationUtil.hasSpecialization(AttacherJoints, vehicleType.specializations) then
            table.insert(vehicleType.specializations, extensionSpec)
        end
    end
end

---
--
function ManualAttachingRegistrationHelper:unregister()
    local extensionSpec = SpecializationUtil.getSpecialization('manualAttachingExtension')

    for _, vehicleType in pairs(VehicleTypeUtil.vehicleTypes) do
        if vehicleType ~= nil then
            for i, spec in ipairs(vehicleType.specializations) do
                if spec == extensionSpec then
                    table.remove(vehicleType.specializations, i)
                    break
                end
            end
        end
    end
end

addModEventListener(ManualAttachingRegistrationHelper)