--
-- ManualAttachUtil
--
-- Utility for Manual Attach
--
-- Copyright (c) Wopster, 2019

---@class ManualAttachUtil
ManualAttachUtil = {}

---Gets the spec table for the given spec.
---@param vehicle table
---@param name string
---@return table
function ManualAttachUtil.getSpecTable(vehicle, name)
    local modName = g_manualAttach.modName
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
    local inputs = object:getInputPowerTakeOffs()

    return #outputs ~= 0 and #inputs ~= 0
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
function ManualAttach.hasConnectionTarget(vehicle, attacherJointIndex)
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

---Returns true when vehicle supports all hose types, false otherwise.
---@param vehicle table
---@param attacherJointIndex number
---@param hoses table
function ManualAttach.doesVehicleSupportAllHoseTypes(vehicle, attacherJointIndex, hoses)
    for _, hose in ipairs(hoses) do
        if vehicle:getConnectionTarget(attacherJointIndex, hose.type, true) == nil then
            return false
        end
    end

    return true
end

---Returns true when object has connection hoses, false otherwise.
---@param object table
---@param vehicle table
---@return boolean
function ManualAttachUtil.hasConnectionHoses(object, vehicle)
    local attacherJointIndex = vehicle:getAttacherJointIndexFromObject(object)
    local hasTarget = ManualAttach.hasConnectionTarget(vehicle, attacherJointIndex)

    if not hasTarget or object.getConnectionHosesByInputAttacherJoint == nil then
        return false
    end

    local inputJointDescIndex = object.spec_attachable.inputAttacherJointDescIndex
    local hoses = object:getConnectionHosesByInputAttacherJoint(inputJointDescIndex)

    return #hoses ~= 0 and ManualAttach.doesVehicleSupportAllHoseTypes(vehicle, attacherJointIndex, hoses)
end

---Todo: Check when this dirty hack can be deleted in the next patch.
---Checks weather or not we are dealing with an edge case scenario for the connection hoses.
---Returns true when we are dealing with an edge case scenario, false otherwise.
---@param object table
---@return boolean
function ManualAttachUtil.hasEdgeCaseHose(object)
    if object.spec_attachable == nil then
        return false
    end

    local inputJointDescIndex = object.spec_attachable.inputAttacherJointDescIndex
    local hoses = object:getConnectionHosesByInputAttacherJoint(inputJointDescIndex)

    local hose = hoses[1]
    -- Total edge case with the Amazone Catros.. needs a proper fix from Giants.
    if hose ~= nil and #hoses == 1 then
        if hose.type == "TOOL_CONNECTOR_TOP_RIGHT" then
            return true
        end
    end

    return false
end

---Returns true when object has attached connection hoses, false otherwise.
---@param object table
---@return boolean
function ManualAttachUtil.hasAttachedConnectionHoses(object)
    if object.spec_attachable == nil then
        return false
    end

    local inputJointDescIndex = object.spec_attachable.inputAttacherJointDescIndex
    local hoses = object:getConnectionHosesByInputAttacherJoint(inputJointDescIndex)

    local hose = hoses[1]
    return hose ~= nil and object:getIsConnectionHoseUsed(hose)
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

    for _, attachable in pairs(g_currentMission.vehicles) do
        if attachable ~= vehicle and attachable.getInputAttacherJoints ~= nil then
            if attachable:getActiveInputAttacherJointDescIndex() == nil then
                local inputAttacherJoints = attachable:getInputAttacherJoints()
                if inputAttacherJoints ~= nil then
                    for inputAttacherJointIndex, inputAttacherJoint in pairs(inputAttacherJoints) do
                        if attacherJoint.jointType == inputAttacherJoint.jointType then
                            local allowPlayerHandling = ManualAttachUtil.isManualJointType(inputAttacherJoint)
                            local isValid = (not isPlayerBased and not allowPlayerHandling) or (isPlayerBased and allowPlayerHandling)

                            if isValid then
                                local x, y, z = localToLocal(inputAttacherJoint.node, attacherJoint.jointTransform, 0, 0, 0)
                                local distSq = MathUtil.vector2LengthSq(x, z)
                                local distSqY = y * y

                                -- we check x-z-distance plus an extra check in y (doubled distance) to better handle height differences
                                if distSq < maxDistanceSq and distSq < minDist and distSqY < maxDistanceSq * 2 and distSqY < minDistY then
                                    local dx, _, _ = localDirectionToLocal(inputAttacherJoint.node, attacherJoint.jointTransform, 1, 0, 0)
                                    if dx > maxAngle then
                                        minDist = distSq
                                        minDistY = distSqY
                                        attachableInRange = attachable
                                        attachableJointDescIndex = inputAttacherJointIndex
                                    end
                                end
                            end
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
                if not attacherJoint.jointIndex ~= 0 then
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
