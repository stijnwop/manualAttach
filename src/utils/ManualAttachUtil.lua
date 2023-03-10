--
-- ManualAttachUtil
--
-- Author: Wopster
-- Description: Utility for Manual Attach
-- Name: ManualAttachUtil
-- Hide: yes
--
-- Copyright (c) Wopster, 2021

---@class ManualAttachUtil
ManualAttachUtil = {}

---Gets the spec table for the given spec.
---@param vehicle table
---@param name string
---@return table
function ManualAttachUtil.getSpecTable(vehicle, name)
    local modName = g_currentMission.manualAttach.modName
    local spec = vehicle["spec_" .. modName .. "." .. name]
    if spec ~= nil then
        return spec
    end

    return vehicle["spec_" .. name]
end

---Return true if given joint desc should be manually controlled, false otherwise.
---@param jointDesc number
---@return boolean
function ManualAttachUtil.isManualJointType(jointDesc)
    if not ManualAttach.AUTO_ATTACH_JOINTYPES[jointDesc.jointType] then
        if jointDesc.isManual ~= nil and not jointDesc.isManual then
            return false
        end

        return true
    end

    return false
end

---Returns true when object has power take offs, false otherwise.
---@param object table
---@param vehicle table
---@return boolean
function ManualAttachUtil.hasPowerTakeOffs(object, vehicle)
    if vehicle.getOutputPowerTakeOffs == nil
        or object.getInputPowerTakeOffs == nil then
        return false
    end

    local outputs = vehicle:getOutputPowerTakeOffs()
    if not (#outputs ~= 0) then
        return false
    end

    local inputJointDescIndex = object.spec_attachable.inputAttacherJointDescIndex
    for _, output in ipairs(outputs) do
        if object.getInputPowerTakeOffsByJointDescIndexAndName ~= nil then
            local inputs = object:getInputPowerTakeOffsByJointDescIndexAndName(inputJointDescIndex, output.ptoName)

            if #inputs ~= 0 then
                return true
            end
        end
    end

    return false
end

---Returns true when object has attached power take offs, false otherwise.
---@param object table
---@param attacherVehicle table
---@return boolean
function ManualAttachUtil.hasAttachedPowerTakeOffs(object, attacherVehicle)
    local spec = object.spec_powerTakeOffs

    for _, input in pairs(spec.inputPowerTakeOffs) do
        if input.connectedVehicle ~= nil then
            if input.connectedVehicle == attacherVehicle then
                return true
            end
        end
    end

    return false
end

---Checks if vehicle has connection targets for the attacherJoints.
---@param vehicle table
---@param attacherJointIndex number
---@return boolean
function ManualAttachUtil.hasConnectionTarget(vehicle, attacherJointIndex)
    local hoses = vehicle.spec_connectionHoses
    if hoses ~= nil then
        for _, node in ipairs(hoses.targetNodes) do
            if node.attacherJointIndices[attacherJointIndex] ~= nil then
                return true
            end
        end
    end

    return false
end

---Returns true when object has connection hoses, false otherwise.
---@param object table
---@param vehicle table
---@return boolean
function ManualAttachUtil.hasConnectionHoses(object, vehicle)
    if not SpecializationUtil.hasSpecialization(ManualAttachConnectionHoses, object.specializations) then
        return false
    end

    local attacherJointIndex = vehicle:getAttacherJointIndexFromObject(object)
    local hasTarget = ManualAttachUtil.hasConnectionTarget(vehicle, attacherJointIndex)

    if not hasTarget or object.getConnectionHosesByInputAttacherJoint == nil then
        return false
    end

    local inputJointDescIndex = object.spec_attachable.inputAttacherJointDescIndex
    local hoses = object:getConnectionHosesByInputAttacherJoint(inputJointDescIndex)
    return #hoses ~= 0
end

---Returns true when object has attached connection hoses, false otherwise.
---@param object table
---@return boolean
function ManualAttachUtil.hasAttachedConnectionHoses(object, type)
    if object.spec_attachable == nil then
        return false
    end

    local inputJointDescIndex = object.spec_attachable.inputAttacherJointDescIndex
    local hoses = object:getConnectionHosesByInputAttacherJoint(inputJointDescIndex)

    local hasTypeMatch = false
    for _, hose in ipairs(hoses) do
        if hose ~= nil then
            local isConnected = object:getIsConnectionHoseUsed(hose)
            if type == nil and isConnected then
                return true
            end

            if type ~= nil then
                hasTypeMatch = ManualAttachConnectionHoses.TYPES_TO_INTERNAL[type][(hose.type):upper()]

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

---Returns true when the jointDesc is not manually handled, false otherwise.¶
---@param vehicle table
---@param object table
---@param jointIndex number
---@return boolean
function ManualAttachUtil.isAutoDetachable(vehicle, object, jointIndex)
    local jointDesc = vehicle:getAttacherJointDescFromObject(object)
    if jointIndex ~= nil then
        jointDesc = vehicle:getAttacherJointByJointDescIndex(jointIndex)
    end
    return jointDesc ~= nil and not ManualAttachUtil.isManualJointType(jointDesc)
end

---Gets closest attachable in joint range.
---@param vehicle table
---@param attacherJoint table
---@param maxDistanceSq number
---@param maxAngle number
---@param isPlayerBased boolean when player controlled.
---@return table, number
function ManualAttachUtil.getAttachableInJointRange(vehicle, attacherJoint, maxDistanceSq, maxAngle, isPlayerBased)
    local attachableInRange
    local attachableJointDescIndex
    local minDist = math.huge
    local minDistY = math.huge

    local x, y, z = getWorldTranslation(attacherJoint.jointTransform)

    for _, jointInfo in pairs(g_currentMission.inputAttacherJoints) do
        if jointInfo.vehicle ~= vehicle and attacherJoint.jointType == jointInfo.jointType then
            local allowPlayerHandling = ManualAttachUtil.isManualJointType(jointInfo.inputAttacherJoint)
            local isValid = (not isPlayerBased and not allowPlayerHandling) or (isPlayerBased and allowPlayerHandling)

            if isValid then
                local distSq = MathUtil.vector2LengthSq(x - jointInfo.translation[1], z - jointInfo.translation[3])

                if distSq < maxDistanceSq and distSq < minDist then
                    local distY = y - jointInfo.translation[2]
                    local distSqY = distY * distY

                    -- we check x-z-distance plus an extra check in y (doubled distance) to better handle height differences
                    if distSqY < maxDistanceSq * 4
                        and distSqY < minDistY
                        and (jointInfo.vehicle:getActiveInputAttacherJointDescIndex() == nil or jointInfo.vehicle:getAllowMultipleAttachments())
                    then
                        local attachAngleLimitAxis = jointInfo.inputAttacherJoint.attachAngleLimitAxis
                        local axis = { 0, 0, 0 }
                        axis[attachAngleLimitAxis] = 1

                        local d = { localDirectionToLocal(jointInfo.node, attacherJoint.jointTransform, axis[1], axis[2], axis[3]) }
                        if d[attachAngleLimitAxis] > maxAngle then
                            minDist = distSq
                            minDistY = distSqY
                            attachableInRange = jointInfo.vehicle
                            attachableJointDescIndex = jointInfo.jointIndex
                        end
                    end
                end
            end
        end
    end

    return attachableInRange, attachableJointDescIndex
end

---Finds the attachable in range based on player or controlled vehicle.
---@param vehicles table
---@param maxDistanceSq number
---@param maxAngle number
---@param isPlayerBased boolean when player controlled.
---@return table, number, table, number, table
function ManualAttachUtil.findVehicleInAttachRange(vehicles, maxDistanceSq, maxAngle, isPlayerBased)
    local attacherVehicle
    local attacherVehicleJointDescIndex
    local attachable
    local attachableJointDescIndex
    local attachedImplement

    local minPlayerDist = math.huge
    local minPlayerAttachedImplDist = math.huge

    for _, vehicle in ipairs(vehicles) do
        local spec = vehicle.spec_attacherJoints

        if not vehicle.isDeleted and spec ~= nil then
            if vehicle.getAttachedImplements ~= nil then
                for _, implement in pairs(vehicle:getAttachedImplements()) do
                    local object = implement.object
                    if object ~= nil then
                        if isPlayerBased then
                            local attacherJoint = spec.attacherJoints[implement.jointDescIndex]
                            local x, y, z = localToLocal(attacherJoint.jointTransform, g_currentMission.player.rootNode, 0, 0, 0)
                            local distSq = MathUtil.vector3LengthSq(x, y, z)

                            if attachedImplement ~= object
                                and distSq < ManualAttach.PLAYER_MIN_DISTANCE
                                and distSq < minPlayerAttachedImplDist then
                                minPlayerAttachedImplDist = distSq
                                attachedImplement = object
                            end
                        else
                            attacherVehicle, attacherVehicleJointDescIndex, attachable, attachableJointDescIndex, attachedImplement = ManualAttachUtil.findVehicleInAttachRange({ object }, maxDistanceSq, maxAngle, isPlayerBased)

                            if attacherVehicle ~= nil then
                                return attacherVehicle, attacherVehicleJointDescIndex, attachable, attachableJointDescIndex, attachedImplement
                            end
                        end
                    end
                end
            end

            for attacherJointIndex, attacherJoint in ipairs(spec.attacherJoints) do
                if attacherJoint.jointIndex == 0 then
                    local isInRange = not isPlayerBased
                    local distSq = math.huge

                    if isPlayerBased then
                        local x, y, z = localToLocal(attacherJoint.jointTransform, g_currentMission.player.rootNode, 0, 0, 0)
                        distSq = MathUtil.vector3LengthSq(x, y, z)
                        isInRange = distSq < ManualAttach.PLAYER_MIN_DISTANCE and distSq < minPlayerDist
                    end

                    if isInRange then
                        local attachableInRange, attachableJointDescIndexInRange = ManualAttachUtil.getAttachableInJointRange(vehicle, attacherJoint, maxDistanceSq, maxAngle, isPlayerBased)

                        if attachableInRange ~= nil then
                            attacherVehicle = vehicle
                            attacherVehicleJointDescIndex = attacherJointIndex
                            attachable = attachableInRange
                            attachableJointDescIndex = attachableJointDescIndexInRange
                            minPlayerDist = isPlayerBased and distSq or minPlayerDist
                        end
                    end
                end
            end
        end
    end

    return attacherVehicle,
    attacherVehicleJointDescIndex,
    attachable,
    attachableJointDescIndex,
    attachedImplement
end
