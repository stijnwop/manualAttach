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
function ConnectionHosesExtension.hasAttachedConnectionHoses(object, type)
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

    --We don't have a hose with the type in question
    if type ~= nil and not hasTypeMatch then
        return true
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
        return ConnectionHosesExtension.hasTypedConnectionHoses(object, vehicle, type)
    end

    local allTypes = ManualAttachConnectionHoses.ALL_TYPES
    for i = 1, #allTypes do
        if ConnectionHosesExtension.hasTypedConnectionHoses(object, vehicle, allTypes[i]) then
            return true
        end
    end

    return false
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
