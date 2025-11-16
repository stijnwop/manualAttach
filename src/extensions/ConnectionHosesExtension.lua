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

---Returns true when object has attached connection hoses, false otherwise.
function ConnectionHosesExtension.hasAttachedConnectionHoses(object: any, type: string?): boolean
    local spec = object.spec_attachable
    if spec == nil then
        return false
    end

    return ConnectionHosesExtension.hasAttachedTypedConnectionHoses(object, type) or ConnectionHosesExtension.hasAttachedCustomHoses(object, type)
end

---Returns true when object has attached connection hoses for given type, false otherwise.
function ConnectionHosesExtension.hasAttachedTypedConnectionHoses(object: any, type: string?): boolean
    local spec = object.spec_attachable
    if spec == nil then
        return false
    end

    local typeMap = type and ManualAttachConnectionHoses.TYPES_TO_INTERNAL[type]
    local hasTypeMatch = false

    local hoses = object:getConnectionHosesByInputAttacherJoint(spec.inputAttacherJointDescIndex)
    for i = 1, #hoses do
        local hose = hoses[i]
        if hose ~= nil then
            local isConnected = object:getIsConnectionHoseUsed(hose)
            if type == nil and isConnected then
                return true
            end

            if type ~= nil then
                if not hasTypeMatch then
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
    local spec = object.spec_attachable
    if spec == nil then
        return false
    end

    local typeMap = type and ManualAttachConnectionHoses.TYPES_TO_INTERNAL[type]
    local hasTypeMatch = false

    local customHoses = object.spec_connectionHoses.customHosesByInputAttacher[spec.inputAttacherJointDescIndex]
    if customHoses ~= nil then
        for i = 1, #customHoses do
            local customHose = customHoses[i]
            if type == nil and customHose.isActive then
                return true
            end

            if type ~= nil then
                if not hasTypeMatch then
                    hasTypeMatch = typeMap[customHose.type:upper()]
                end

                if hasTypeMatch and customHose.isActive then
                    return true
                end
            end
        end
    end

    local customTargets = object.spec_connectionHoses.customHoseTargetsByInputAttacher[spec.inputAttacherJointDescIndex]
    if customTargets ~= nil then
        for i = 1, #customTargets do
            local customTarget = customTargets[i]
            if type == nil and customTarget.isActive then
                return true
            end

            if type ~= nil then
                if not hasTypeMatch then
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
    local spec = vehicle.spec_connectionHoses
    if spec == nil then
        return false
    end

    if type ~= nil then
        local typeMap = ManualAttachConnectionHoses.TYPES_TO_INTERNAL[type]
        local hasMatchingType = false

        for _, node in ipairs(spec.targetNodes) do
            if typeMap[node.type:upper()] ~= nil then
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
    local spec = object.spec_attachable
    if spec == nil or object.getConnectionHosesByInputAttacherJoint == nil or not SpecializationUtil.hasSpecialization(ManualAttachConnectionHoses, object.specializations) then
        return false
    end

    local attacherJointIndex = vehicle:getAttacherJointIndexFromObject(object)
    if type == nil or not ConnectionHosesExtension.hasConnectionTarget(vehicle, attacherJointIndex, type) then
        return false
    end

    local hoses = object:getConnectionHosesByInputAttacherJoint(spec.inputAttacherJointDescIndex)
    local typeMap = ManualAttachConnectionHoses.TYPES_TO_INTERNAL[type]

    for i = 1, #hoses do
        local hose = hoses[i]
        if hose and typeMap[hose.type:upper()] ~= nil then
            return true
        end
    end

    return false
end

function ConnectionHosesExtension.hasCustomHoseMatch(customHoseTargets: any, customHoses, type: string?): boolean
    local typeMap = type and ManualAttachConnectionHoses.TYPES_TO_INTERNAL[type]

    for _, customHose in ipairs(customHoses) do
        if type == nil or typeMap[customHose.type:upper()] ~= nil then
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
    local spec = object.spec_attachable
    if spec == nil or object.getConnectionHosesByInputAttacherJoint == nil or not SpecializationUtil.hasSpecialization(ManualAttachConnectionHoses, object.specializations) then
        return false
    end

    local attacherJointIndex = vehicle:getAttacherJointIndexFromObject(object)
    local customHoseTargetsByInputAttacher = object.spec_connectionHoses.customHoseTargetsByInputAttacher[spec.inputAttacherJointDescIndex] or {}
    local customHosesOfVehicle = vehicle.spec_connectionHoses.customHosesByAttacher[attacherJointIndex] or {}

    if ConnectionHosesExtension.hasCustomHoseMatch(customHoseTargetsByInputAttacher, customHosesOfVehicle, type) then
        return true
    end

    local customHosesOfObject = object.spec_connectionHoses.customHosesByInputAttacher[spec.inputAttacherJointDescIndex] or {}
    local customHoseTargetsByAttacher = vehicle.spec_connectionHoses.customHoseTargetsByAttacher[attacherJointIndex] or {}

    return ConnectionHosesExtension.hasCustomHoseMatch(customHoseTargetsByAttacher, customHosesOfObject, type)
end
