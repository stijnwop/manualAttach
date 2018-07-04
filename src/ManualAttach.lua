--
-- ManualAttach
--
-- Authors: Wopster
-- Description: The main specilization for Manual Attach
--
-- Copyright (c) Wopster, 2015 - 2018

ManualAttach = {}

ManualAttach.COSANGLE_THRESHOLD = math.cos(math.rad(70))
ManualAttach.PLAYER_MIN_DISTANCE = 9
ManualAttach.PLAYER_DISTANCE = math.huge
ManualAttach.TIMER_THRESHOLD = 200 -- ms
ManualAttach.DETACHING_NOT_ALLOWED_TIME = 50 -- ms
ManualAttach.DETACHING_PRIORITY_NOT_ALLOWED = 6
ManualAttach.ATTACHING_PRIORITY_ALLOWED = 1
ManualAttach.JOINT_DISTANCE = 1.3
ManualAttach.JOINT_SEQUENCE = 0.6 * 0.6
ManualAttach.FORCED_ACTIVE_TIME_INCREASMENT = 600 -- ms

---
--
function ManualAttach:preLoadManualAttach()
    getfenv(0)["g_manualAttach"] = self

    self.debug = true --<%=debug %>

    -- handle vehicle insert
end

---
-- @param typeName
--
local function mapJointTypeNameToInt(typeName)
    local jointType = AttacherJoints.jointTypeNameToInt[typeName]
    -- Custom joints need a check if it exists in the game
    return jointType ~= nil and jointType or -1
end

ManualAttach.AUTO_ATTACH_JOINTYPES = {
    [mapJointTypeNameToInt("skidSteer")] = true,
    [mapJointTypeNameToInt("cutter")] = true,
    [mapJointTypeNameToInt("cutterHarvester")] = true,
    [mapJointTypeNameToInt("wheelLoader")] = true,
    [mapJointTypeNameToInt("frontloader")] = true,
    [mapJointTypeNameToInt("telehandler")] = true,
    [mapJointTypeNameToInt("hookLift")] = true,
    [mapJointTypeNameToInt("semitrailer")] = true,
    [mapJointTypeNameToInt("semitrailerHook")] = true,
    [mapJointTypeNameToInt("fastCoupler")] = true
}

---
-- @param ...
--
local function initInRangeTable(...)
    local t = {}
    local f = {}

    for _, v in pairs({ ... }) do
        for _, field in pairs(v) do
            table.insert(f, field)
        end
    end

    for _, field in pairs(f) do
        t[field] = nil
    end

    return f
end

---
--
function ManualAttach:loadMap()
    local _genericFields = {
        "vehicle",
        "attachableInMountRange",
        "attachableInMountRangeInputJointIndex",
        "attachableInMountRangeJointIndex",
        "attachableInMountRangeInputJoint",
        "attachableInMountRangeJoint",
        "attachedImplement",
    }

    local _playerSpecificFields = {
        "attachedVehicle",
        "attachedImplementIndex",
        "attachedImplementInputJoint",
    }

    self.playerControlledInRange = initInRangeTable(_genericFields, _playerSpecificFields)
    self.vehicleControlledInRange = initInRangeTable(_genericFields)

    g_currentMission.dynamicHoseIsManual = true -- Todo: remove in future and use own global
end

---
--
function ManualAttach:deleteMap()
    getfenv(0)["g_manualAttach"] = nil
    g_currentMission.dynamicHoseIsManual = false
end

---
-- @param t
--
local function resetInRangeTable(t)
    for i = #t, 1, -1 do
        t[i] = nil
    end
end

---
-- @param dt
--
function ManualAttach:update(dt)
    if not g_currentMission:getIsClient() then
        return
    end

    resetInRangeTable(self.playerControlledInRange)
    resetInRangeTable(self.vehicleControlledInRange)

    local isPlayerControlled = ManualAttachUtil:getIsValidPlayer()

    if isPlayerControlled then
        self:handlePlayerControlled(dt)
    else
        self:handleVehicleControlled(dt)
    end

    -- Todo: draw
end

---
-- @param vehicle
--
local function getIsValidVehicle(vehicle)
    return vehicle ~= nil and vehicle.isa ~= nil and vehicle:isa(Vehicle) and not vehicle:isa(StationCrane) -- Dismiss trains and the station cranes
end

---
-- @param dt
--
function ManualAttach:handlePlayerControlled(dt)
    for _, vehicle in pairs(g_currentMission.vehicles) do
        if getIsValidVehicle(vehicle) then
            self:getIsManualAttachableInRange(vehicle)
        end
    end

    local player = g_currentMission.player
    if player.manualAttachTimer == nil then
        player.manualAttachTimer = { time = 0, longEnough = false }
    end

    local inRange = self.playerControlledInRange
end

---
-- @param dt
--
function ManualAttach:handleVehicleControlled(dt)
end

---
-- @param attacherJoint
-- @param jointTrans
-- @param distanceSequence
-- @param isManualCheck
--
local function getAttachableInJointRange(attacherJoint, jointTrans, distanceSequence, isManualCheck)
    if distanceSequence == nil then
        distanceSequence = ManualAttach.JOINT_SEQUENCE
    end

    for _, attachable in pairs(g_currentMission.attachables) do
        if attachable.attacherVehicle == nil then
            for i, inputAttacherJoint in pairs(attachable.inputAttacherJoints) do
                if attachable:getIsInputAttacherActive(inputAttacherJoint) and inputAttacherJoint.jointType == attacherJoint.jointType then
                    local inputJointTrans = { getWorldTranslation(inputAttacherJoint.node) }
                    local distanceJoints = Utils.vector2LengthSq(inputJointTrans[1] - jointTrans[1], inputJointTrans[3] - jointTrans[3])

                    if distanceJoints < distanceSequence then
                        local jointDistance = Utils.getNoNil(inputAttacherJoint.inRangeDistance, ManualAttach.JOINT_DISTANCE)
                        local jointDistanceY = math.abs(inputJointTrans[2] - jointTrans[2])

                        if jointDistanceY < jointDistance then
                            local cosAngle = ManualAttachUtil:getCosAngle(inputAttacherJoint.node, attacherJoint.jointTransform)

                            if cosAngle > ManualAttach.COSANGLE_THRESHOLD or ManualAttach:getIsCosAngleValidationException(attacherJoint) then
                                local isManual = ManualAttach:getIsManualControlled(attachable, inputAttacherJoint)

                                if (isManualCheck and isManual) or (not isManualCheck and not isManual) then
                                    return attachable, inputAttacherJoint, i, distanceJoints
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return nil, nil, nil, distanceSequence
end

---
-- @param vehicle
--
function ManualAttach:getIsManualAttachableInRange(vehicle)
    if vehicle.attacherJoints == nil then
        return
    end

    local inRange = self.playerControlledInRange
    local playerTrans = { getWorldTranslation(g_currentMission.player.rootNode) }
    local distanceSequence = ManualAttach.JOINT_SEQUENCE
    local playerDistanceAttached = ManualAttach.PLAYER_DISTANCE
    local playerDistance = ManualAttach.PLAYER_DISTANCE

    if vehicle.attachedImplements ~= nil then
        for i, implement in pairs(vehicle.attachedImplements) do
            if implement.jointDescIndex ~= nil then
                local jointTrans = { getWorldTranslation(vehicle.attacherJoints[implement.jointDescIndex].jointTransform) }
                local distance = Utils.vector3LengthSq(jointTrans[1] - playerTrans[1], jointTrans[2] - playerTrans[2], jointTrans[3] - playerTrans[3])
                local object = implement.object

                if distance < ManualAttach.PLAYER_MIN_DISTANCE
                        and distance < playerDistanceAttached
                        and inRange.attachedImplement ~= object then
                    inRange.attachedVehicle = vehicle
                    inRange.attachedImplement = object
                    inRange.attachedImplementIndex = i
                    inRange.attachedImplementInputJoint = object.inputAttacherJoints[object.inputAttacherJointDescIndex]

                    playerDistanceAttached = distance
                end
            end
        end
    end

    for j, attacherJoint in pairs(vehicle.attacherJoints) do
        if not attacherJoint.jointIndex ~= 0 then -- prevent double
            local jointTrans = { getWorldTranslation(attacherJoint.jointTransform) }
            local distance = Utils.vector3LengthSq(jointTrans[1] - playerTrans[1], jointTrans[2] - playerTrans[2], jointTrans[3] - playerTrans[3])

            if distance < ManualAttaching.PLAYER_MIN_DISTANCE and distance < playerDistance then
                local attachable, inputAttacherJoint, inputAttacherJointIndex, distanceSq = getAttachableInJointRange(attacherJoint, jointTrans, distanceSequence, true)

                if attachable ~= nil and attachable ~= inRange.attachableInMountRange
                        or inputAttacherJoint ~= nil and inputAttacherJoint ~= inRange.attachableInMountRangeInputJoint
                        or inputAttacherJointIndex ~= nil and inputAttacherJointIndex ~= inRange.attachableInMountRangeInputJointIndex then
                    inRange.vehicle = vehicle
                    inRange.attachableInMountRange = attachable
                    inRange.attachableInMountRangeInputJoint = inputAttacherJoint
                    inRange.attachableInMountRangeInputJointIndex = inputAttacherJointIndex
                    inRange.attachableInMountRangeJoint = attacherJoint
                    inRange.attachableInMountRangeJointIndex = j

                    playerDistance = distance
                    distanceSequence = distanceSq
                end
            end
        end
    end
end

---
-- @param jointDesc
--
function ManualAttach:getIsCosAngleValidationException(jointDesc)
    return jointDesc.jointType == AttacherJoints.jointTypeNameToInt['conveyor']
end

---
-- @param vehicle
-- @param jointDesc
--
function ManualAttach:getIsManualControlled(vehicle, jointDesc)
    if not ManualAttach.AUTO_ATTACH_JOINTYPES[jointDesc.jointType] then
        if jointDesc.isManual ~= nil and not jointDesc.isManual then
            return false
        end

        return true
    end

    return false
end

---
-- @param jointDesc
--
function ManualAttach:getIsDynamicHoseManualControlled(jointDesc)
    if jointDesc.dynamicHosesIsManual ~= nil and not jointDesc.dynamicHosesIsManual then
        return false
    end

    return true
end

---
-- @param jointDesc
--
function ManualAttach:getIsPtoManualControlled(jointDesc)
    if jointDesc.ptoIsManual ~= nil and not jointDesc.ptoIsManual then
        return false
    end

    return true
end