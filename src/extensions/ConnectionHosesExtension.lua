--
-- ConnectionHosesExtension
--
-- Author: Wopster
-- Description: Extension for handling connection hoses
-- Name: ConnectionHosesExtension
-- Hide: yes
--
-- Copyright (c) Wopster

---@class ConnectionHosesExtension
ConnectionHosesExtension = {}

---Returns the attachable spec when the object supports connection hose lookups, nil otherwise.
---Not every attachable has the connection hoses specialization, so the functions it provides can be missing.
local function getSupportedAttachableSpec(object: any): any
    if object == nil then
        return nil
    end

    local spec = object.spec_attachable
    if spec == nil or object.spec_connectionHoses == nil then
        return nil
    end

    if object.getConnectionHosesByInputAttacherJoint == nil or object.getIsConnectionHoseUsed == nil then
        return nil
    end

    return spec
end

---Returns true when object has attached connection hoses, false otherwise.
function ConnectionHosesExtension.hasAttachedConnectionHoses(object: any, type: string?): boolean
    if getSupportedAttachableSpec(object) == nil then
        return false
    end

    return ConnectionHosesExtension.hasAttachedTypedConnectionHoses(object, type) or ConnectionHosesExtension.hasAttachedCustomHoses(object, type)
end

---Returns true when object has attached connection hoses for given type, false otherwise.
function ConnectionHosesExtension.hasAttachedTypedConnectionHoses(object: any, type: string?): boolean
    local spec = getSupportedAttachableSpec(object)
    if spec == nil then
        return false
    end

    local typeMap = type and ManualAttachConnectionHoses.TYPES_TO_INTERNAL[type]
    local hasTypeMatch = false

    local hoses = object:getConnectionHosesByInputAttacherJoint(spec.inputAttacherJointDescIndex) or {}
    for i = 1, #hoses do
        local hose = hoses[i]
        if hose ~= nil then
            local isConnected = object:getIsConnectionHoseUsed(hose)
            if type == nil and isConnected then
                return true
            end

            if type ~= nil then
                if not hasTypeMatch and typeMap ~= nil then
                    hasTypeMatch = typeMap[hose.type:upper()]
                end

                if hasTypeMatch and isConnected then
                    return true
                end
            end
        end
    end

    return false
end

---Returns true when object has attached custom connection hoses, false otherwise.
function ConnectionHosesExtension.hasAttachedCustomHoses(object: any, type: string?): boolean
    local spec = getSupportedAttachableSpec(object)
    if spec == nil then
        return false
    end

    local typeMap = type and ManualAttachConnectionHoses.TYPES_TO_INTERNAL[type]
    local hasTypeMatch = false

    local hosesSpec = object.spec_connectionHoses
    local customHoses = hosesSpec.customHosesByInputAttacher ~= nil and hosesSpec.customHosesByInputAttacher[spec.inputAttacherJointDescIndex] or nil
    if customHoses ~= nil then
        for i = 1, #customHoses do
            local customHose = customHoses[i]
            if type == nil and customHose.isActive then
                return true
            end

            if type ~= nil then
                if not hasTypeMatch and typeMap ~= nil then
                    hasTypeMatch = typeMap[customHose.type:upper()]
                end

                if hasTypeMatch and customHose.isActive then
                    return true
                end
            end
        end
    end

    local customTargets = hosesSpec.customHoseTargetsByInputAttacher ~= nil and hosesSpec.customHoseTargetsByInputAttacher[spec.inputAttacherJointDescIndex] or nil
    if customTargets ~= nil then
        for i = 1, #customTargets do
            local customTarget = customTargets[i]
            if type == nil and customTarget.isActive then
                return true
            end

            if type ~= nil then
                if not hasTypeMatch and typeMap ~= nil then
                    hasTypeMatch = typeMap[customTarget.type:upper()]
                end

                if hasTypeMatch and customTarget.isActive then
                    return true
                end
            end
        end
    end

    return false
end

---Checks if vehicle has connection targets for the attacherJoints.
function ConnectionHosesExtension.hasConnectionTarget(vehicle: any, attacherJointIndex: number, type: string?): boolean
    local spec = vehicle ~= nil and vehicle.spec_connectionHoses or nil
    if spec == nil or spec.targetNodes == nil or attacherJointIndex == nil then
        return false
    end

    if type ~= nil then
        local typeMap = ManualAttachConnectionHoses.TYPES_TO_INTERNAL[type]
        local hasMatchingType = false

        for _, node in ipairs(spec.targetNodes) do
            if typeMap ~= nil and typeMap[node.type:upper()] ~= nil then
                hasMatchingType = true
                break
            end
        end

        if not hasMatchingType then
            return false
        end
    end

    for _, node in ipairs(spec.targetNodes) do
        if node.attacherJointIndices[attacherJointIndex] ~= nil then
            return true
        end
    end

    return false
end

---Returns true when object has connection hoses, false otherwise.
function ConnectionHosesExtension.hasConnectionHoses(object: any, vehicle: any, type: string?): boolean
    if type ~= nil then
        if ConnectionHosesExtension.hasTypedConnectionHoses(object, vehicle, type) then
            return true
        end

        if ConnectionHosesExtension.hasConnectionCustomHoses(object, vehicle, type) then
            return true
        end

        return false
    end

    local allTypes = ManualAttachConnectionHoses.ALL_TYPES
    for i = 1, #allTypes do
        if ConnectionHosesExtension.hasTypedConnectionHoses(object, vehicle, allTypes[i]) then
            return true
        end
    end

    return ConnectionHosesExtension.hasConnectionCustomHoses(object, vehicle)
end

---Returns true when object has connection hoses for given type, false otherwise.
function ConnectionHosesExtension.hasTypedConnectionHoses(object: any, vehicle: any, type: string?): boolean
    local spec = getSupportedAttachableSpec(object)
    if spec == nil or not SpecializationUtil.hasSpecialization(ManualAttachConnectionHoses, object.specializations) then
        return false
    end

    if vehicle == nil or vehicle.getAttacherJointIndexFromObject == nil then
        return false
    end

    local attacherJointIndex = vehicle:getAttacherJointIndexFromObject(object)
    if type == nil or not ConnectionHosesExtension.hasConnectionTarget(vehicle, attacherJointIndex, type) then
        return false
    end

    local hoses = object:getConnectionHosesByInputAttacherJoint(spec.inputAttacherJointDescIndex) or {}
    local typeMap = ManualAttachConnectionHoses.TYPES_TO_INTERNAL[type]

    for i = 1, #hoses do
        local hose = hoses[i]
        if hose and typeMap ~= nil and typeMap[hose.type:upper()] ~= nil then
            return true
        end
    end

    return false
end

function ConnectionHosesExtension.hasCustomHoseMatch(customHoseTargets: any, customHoses, type: string?): boolean
    local typeMap = type and ManualAttachConnectionHoses.TYPES_TO_INTERNAL[type]

    for _, customHose in ipairs(customHoses) do
        if type == nil or (typeMap ~= nil and typeMap[customHose.type:upper()] ~= nil) then
            for _, customTarget in ipairs(customHoseTargets) do
                if customHose.type == customTarget.type and customHose.specType == customTarget.specType then
                    return true
                end
            end
        end
    end

    return false
end

function ConnectionHosesExtension.hasConnectionCustomHoses(object: any, vehicle: any, type: string?): boolean
    local spec = getSupportedAttachableSpec(object)
    if spec == nil or not SpecializationUtil.hasSpecialization(ManualAttachConnectionHoses, object.specializations) then
        return false
    end

    if vehicle == nil or vehicle.getAttacherJointIndexFromObject == nil or vehicle.spec_connectionHoses == nil then
        return false
    end

    local objectSpec = object.spec_connectionHoses
    local vehicleSpec = vehicle.spec_connectionHoses
    local attacherJointIndex = vehicle:getAttacherJointIndexFromObject(object)
    if attacherJointIndex == nil then
        return false
    end

    local customHoseTargetsByInputAttacher = objectSpec.customHoseTargetsByInputAttacher ~= nil and objectSpec.customHoseTargetsByInputAttacher[spec.inputAttacherJointDescIndex] or {}
    local customHosesOfVehicle = vehicleSpec.customHosesByAttacher ~= nil and vehicleSpec.customHosesByAttacher[attacherJointIndex] or {}

    if ConnectionHosesExtension.hasCustomHoseMatch(customHoseTargetsByInputAttacher, customHosesOfVehicle, type) then
        return true
    end

    local customHosesOfObject = objectSpec.customHosesByInputAttacher ~= nil and objectSpec.customHosesByInputAttacher[spec.inputAttacherJointDescIndex] or {}
    local customHoseTargetsByAttacher = vehicleSpec.customHoseTargetsByAttacher ~= nil and vehicleSpec.customHoseTargetsByAttacher[attacherJointIndex] or {}

    return ConnectionHosesExtension.hasCustomHoseMatch(customHoseTargetsByAttacher, customHosesOfObject, type)
end
