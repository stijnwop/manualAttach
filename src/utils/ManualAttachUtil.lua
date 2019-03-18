ManualAttachUtil = {}

function ManualAttachUtil:getSpecTable(vehicle, name)
    return vehicle["spec_" .. name]
end

function ManualAttachUtil.isManualJointType(jointDesc)
    if not ManualAttach.AUTO_ATTACH_JOINTYPES[jointDesc.jointType] then
        if jointDesc.isManual ~= nil and not jointDesc.isManual then
            return false
        end

        return true
    end

    return false
end

function ManualAttachUtil:getCosAngle(p1, p2)
    local x1, y1, z1 = localDirectionToWorld(p1, 1, 0, 0)
    local x2, y2, z2 = localDirectionToWorld(p2, 1, 0, 0)

    return x1 * x2 + y1 * y2 + z1 * z2
end

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

function ManualAttachUtil.hasAttachedConnectionHoses(object)
    local inputJointDescIndex = object.spec_attachable.inputAttacherJointDescIndex
    local hoses = object:getConnectionHosesByInputAttacherJoint(inputJointDescIndex)
    for _, hose in ipairs(hoses) do
        if object:getIsConnectionHoseUsed(hose) then
            return true
        end
    end

    return false
end

function ManualAttachUtil.getAttachableInJointRange(vehicle, attacherJoint, maxDistanceSq, maxAngle, minDist, minDistY)
    local attachableInRange
    local attachableJointDescIndex

    for _, attachable in pairs(g_currentMission.vehicles) do
        if attachable ~= vehicle and attachable.getInputAttacherJoints ~= nil then
            if attachable:getActiveInputAttacherJointDescIndex() == nil then
                local inputAttacherJoints = attachable:getInputAttacherJoints()
                if inputAttacherJoints ~= nil then
                    for inputAttacherJointIndex, inputAttacherJoint in pairs(inputAttacherJoints) do
                        if attacherJoint.jointType == inputAttacherJoint.jointType then
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

    return attachableInRange, attachableJointDescIndex, minDist, minDistY
end

function ManualAttachUtil.findVehicleInAttachRange(vehicles, maxDistanceSq, maxAngle, isPlayerBased)
    local attacherVehicle
    local attacherVehicleJointDescIndex
    local attachable
    local attachableJointDescIndex
    local attachedImplement

    local minDist = math.huge
    local minDistY = math.huge
    local minPlayerDist = math.huge
    local minPlayerAttachedImplDist = math.huge

    for _, vehicle in ipairs(vehicles) do
        local spec = vehicle.spec_attacherJoints

        if spec ~= nil then
            if vehicle.getAttachedImplements ~= nil then
                for _, implement in pairs(vehicle:getAttachedImplements()) do
                    local object = implement.object
                    if object ~= nil then
                        if isPlayerBased then
                            local attacherJoint = spec.attacherJoints[implement.jointDescIndex]
                            local x, _, z = localToLocal(g_currentMission.player.rootNode, attacherJoint.jointTransform, 0, 0, 0)
                            local distSq = MathUtil.vector2LengthSq(x, z)

                            if attachedImplement ~= object
                                    and distSq < ManualAttach.PLAYER_MIN_DISTANCE
                                    and distSq < minPlayerAttachedImplDist then
                                minPlayerAttachedImplDist = distSq
                                attachedImplement = object
                            end
                        else
                            attacherVehicle, attacherVehicleJointDescIndex, attachable, attachableJointDescIndex, attachedImplement = ManualAttachUtil.findVehicleInAttachRange(object, maxDistanceSq, maxAngle, isPlayerBased)

                            if attacherVehicle ~= nil then
                                return attacherVehicle, attacherVehicleJointDescIndex, attachable, attachableJointDescIndex, attachedImplement
                            end
                        end
                    end
                end
            end

            for attacherJointIndex, attacherJoint in ipairs(spec.attacherJoints) do
                if not attacherJoint.jointIndex ~= 0 then
                    local isInRange = true
                    if isPlayerBased then
                        local x, _, z = localToLocal(g_currentMission.player.rootNode, attacherJoint.jointTransform, 0, 0, 0)
                        local distSq = MathUtil.vector2LengthSq(x, z)

                        if distSq > ManualAttach.PLAYER_MIN_DISTANCE
                                and distSq > minPlayerDist then
                            isInRange = false
                        else
                            minPlayerDist = distSq
                        end
                    end

                    if isInRange then
                        attachable, attachableJointDescIndex, minDist, minDistY = ManualAttachUtil.getAttachableInJointRange(vehicle, attacherJoint, maxDistanceSq, maxAngle, minDist, minDistY)

                        if attachable ~= nil then
                            attacherVehicle = vehicle
                            attacherVehicleJointDescIndex = attacherJointIndex
                            break
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