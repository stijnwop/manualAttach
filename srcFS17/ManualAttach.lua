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
ManualAttach.DEFAULT_JOINT_DISTANCE = 1.3
ManualAttach.JOINT_DISTANCE = ManualAttach.DEFAULT_JOINT_DISTANCE
ManualAttach.JOINT_SEQUENCE = 0.5 * 0.5
ManualAttach.FORCED_ACTIVE_TIME_INCREASMENT = 600 -- ms

ManualAttach._PTO_TYPES = {
    "pto",
    "pto2",
    "movingPto",
}

---
--
function ManualAttach:preLoadManualAttach()
    getfenv(0)["g_manualAttach"] = self

    self.debug = true --<%=debug %>

    --    ManualAttachUtil:registerSpecialization("manualAttachingExtension")
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

    g_manualAttach.connectionHosesAreManual = true

    local difficulty = g_currentMission.missionInfo.difficulty / 3

    ManualAttach.JOINT_DISTANCE = ManualAttach.DEFAULT_JOINT_DISTANCE - (difficulty * 0.9)
    if g_currentMission.missionInfo.difficulty ~= 1 then
        ManualAttach.JOINT_SEQUENCE = ManualAttach.JOINT_SEQUENCE - (ManualAttach.JOINT_SEQUENCE / 1.5 * difficulty)
    end

    self.allowAttach = true

    if g_currentMission:getIsClient() then
        local uiScale = g_gameSettings:getValue("uiScale")

        self.attachImplementOverlayWidth, self.attachImplementOverlayHeight = getNormalizedScreenValues(46 * uiScale, 40 * uiScale)
        self.attachImplementOverlay = Overlay:new("pickedUpObjectOverlay", g_baseUIFilename, 0.5, 0.5, self.attachImplementOverlayWidth, self.attachImplementOverlayHeight)
        self.attachImplementOverlay:setAlignment(Overlay.ALIGN_VERTICAL_MIDDLE, Overlay.ALIGN_HORIZONTAL_CENTER)

        self.attachImplementGrabUVs = getNormalizedUVs({ 947, 280, 69, 60 })
        self.attachImplementAttachUVs = getNormalizedUVs({ 698, 510, 33, 18 })

        self.attachImplementOverlay:setDimension(self.attachImplementOverlayWidth, self.attachImplementOverlayHeight)
        self.attachImplementOverlay:setUVs(self.attachImplementGrabUVs)
        self.attachImplementOverlay:setColor(1, 1, 1, 0.3)
    end
end

---
--
function ManualAttach:deleteMap()
    getfenv(0)["g_manualAttach"] = nil

    ManualAttachUtil:unregisterSpecialization("manualAttachingExtension")
    -- Todo: reset nooped function
end

---
-- @param t
--
local function resetInRangeTable(t)
    for _, field in pairs(t) do
        t[field] = nil
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

    self:drawHud(isPlayerControlled)
end

function ManualAttach:drawHud(isPlayerControlled)
    local inRange = isPlayerControlled and self.playerControlledInRange or self.vehicleControlledInRange
    local inMountRange = self.allowAttach and inRange.attachedImplement == nil and inRange.attachableInMountRange ~= nil
    local player = g_currentMission.player

    if isPlayerControlled and not player.pickedUpObjectOverlay.visible then
        player.pickedUpObjectOverlay:setIsVisible(true)
    end

    if not inMountRange then
        local inUnMountRange = inRange.attachedImplement ~= nil and inRange.attachedImplement.attacherVehicle ~= nil

        if inUnMountRange then
            if isPlayerControlled then
            else
                g_currentMission:enableHudIcon('detachingNotAllowed', ManualAttach.DETACHING_PRIORITY_NOT_ALLOWED)
            end
        end
    else
        if isPlayerControlled then
            player.pickedUpObjectOverlay:setIsVisible(false)
            self.attachImplementOverlay:render()
        else
            g_currentMission:enableHudIcon('attach', ManualAttach.ATTACHING_PRIORITY_ALLOWED)
        end
    end
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

    local attachableInRange = inRange.vehicle ~= nil or inRange.attachedVehicle ~= nil
    local attachedVehicleInRange = inRange.attachedVehicle ~= nil and inRange.attachedImplement ~= nil
    local vehicle = inRange.vehicle
    local attacherJointDesc = inRange.attachableInMountRangeJointIndex
    local inputJointDesc = inRange.attachableInMountRangeInputJoint


    if attachableInRange then
        if vehicle == nil then
            vehicle = inRange.attachedVehicle

            local implement = vehicle:getImplementByObject(inRange.attachedImplement)
            attacherJointDesc = implement.jointDescIndex
            inputJointDesc = inRange.attachedImplementInputJoint
        end

        vehicle:setControllableAttacherJoint(attacherJointDesc, inputJointDesc)

        self.allowAttach = true

        -- draw helpers
        if inRange.attachableInMountRangeJoint ~= nil and inRange.attachableInMountRangeInputJoint ~= nil then
            local helperPoint = "O"
            local x0, y0, z0 = getWorldTranslation(inRange.attachableInMountRangeInputJoint.node)
            local x1, y1, z1 = getWorldTranslation(inRange.attachableInMountRangeJoint.jointTransform)
            local jointDistanceY = math.abs(y0 - y1)
            local textSize = getCorrectTextSize(.018)

            if inRange.attachableInMountRangeJoint.jointType == AttacherJoints.jointTypeNameToInt['trailer'] then
                self.allowAttach = jointDistanceY < .01

                if self.allowAttach then
                    drawDebugLine(x0, y0, z0, 0.5, 1.0, 0.5, x1, y1, z1, 0.5, 1.0, 0.5)
                end
            end

            Utils.renderTextAtWorldPosition(x0, y0, z0, helperPoint, textSize, 0)
            Utils.renderTextAtWorldPosition(x1, y1, z1, helperPoint, textSize, 0)
        end

        if self.allowAttach and InputBinding.hasEvent(InputBinding.ATTACH) then -- Todo: register our own input bindings
            self:handleAttachEvent()
        end
    end

    if attachedVehicleInRange then
        local implement = inRange.attachedVehicle:getImplementByObject(inRange.attachedImplement)

        if implement ~= nil then
            local jointDesc = inRange.attachedVehicle.attacherJoints[implement.jointDescIndex]

            --inRange.attachedImplement.dynamicHoseIsManual = self:getIsDynamicHoseManualControlled(jointDesc)

            if InputBinding.isPressed(InputBinding.IMPLEMENT_EXTRA4) then
                if player.manualAttachTimer.time < ManualAttach.TIMER_THRESHOLD then
                    player.manualAttachTimer.time = player.manualAttachTimer.time + dt
                else
                    --                        self:handleDynamicHoses(jointDesc)
                end
            else
                if player.manualAttachTimer.time > 0 then
                    if player.manualAttachTimer.time < ManualAttach.TIMER_THRESHOLD then
                        self:handlePowerTakeOffEvent(jointDesc)
                    end

                    player.manualAttachTimer.time = 0
                    player.manualAttachTimer.longEnough = false
                end
            end
        end
    end
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
                        print(distanceSequence)
                        local jointDistance = Utils.getNoNil(inputAttacherJoint.inRangeDistance, ManualAttach.JOINT_DISTANCE)
                        local jointDistanceY = math.abs(inputJointTrans[2] - jointTrans[2])

                        print("distanceJointsY: " .. jointDistanceY)

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

            if distance < ManualAttach.PLAYER_MIN_DISTANCE and distance < playerDistance then
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

function ManualAttach:handleAttachEvent()
    local inRange = self.playerControlledInRange

    --    self:setSoundPlayer(g_currentMission.player)

    if inRange.attachableInMountRange ~= nil then
        self:attachImplement(inRange.vehicle, inRange.attachableInMountRange, inRange.attachableInMountRangeJointIndex, inRange.attachableInMountRangeInputJointIndex)
    elseif inRange.attachedImplement ~= nil then
        --        self:detachImplement(inRange.attachedVehicle, inRange.attachedImplement, inRange.attachedImplementIndex)
    end
end

function ManualAttach:handlePowerTakeOffEvent(jointDesc)
    local inRange = self.playerControlledInRange
    local vehicle = inRange.attachedVehicle
    local object = inRange.attachedImplement
    local player = g_currentMission.player
    --    self:setSoundPlayer(g_currentMission.player)

    if vehicle ~= nil and object ~= nil then
        if ManualAttachUtil:getHasPowerTakeOff(object) and ManualAttachUtil:getIsPowerTakeOffManual(jointDesc) then
            if ManualAttachUtil:getIsPowerTakeOffActive(jointDesc, 'pto')
                    or ManualAttachUtil:getIsPowerTakeOffActive(jointDesc, 'pto2')
                    or ManualAttachUtil:getIsPowerTakeOffActive(jointDesc, 'movingPto') then
                self:detachPowerTakeOff(vehicle, object)
            else
                self:attachPowerTakeOff(vehicle, object)
                --                self:playSound(vehicle, jointDesc, self.currentSoundPlayer)
            end
        end
    end
end

function ManualAttach:attachImplement(vehicle, object, jointDescIndex, inputJointDescIndex, force)
    if vehicle ~= nil and object ~= nil then
        local jointDesc = vehicle.attacherJoints[jointDescIndex]
        local inputJointDesc = object.inputAttacherJoints[inputJointDescIndex]

        if jointDesc ~= nil and inputJointDesc ~= nil then
            if ManualAttach:getIsManualControlled(object, inputJointDesc) or force then
                local startLowered = ManualAttach:getIsJointMoveDownAllowed(object, inputJointDesc)

                vehicle:attachImplement(object, inputJointDescIndex, jointDescIndex)

                if startLowered then
                    vehicle:setJointMoveDown(jointDescIndex, true)

                    if vehicle.attacherJoint ~= nil then
                        for _, dependentAttacherJointIndex in pairs(vehicle.attacherJoint.dependentAttacherJoints) do
                            if vehicle.attacherJoints[dependentAttacherJointIndex] ~= nil then
                                vehicle:setJointMoveDown(dependentAttacherJointIndex, true, true)
                            end
                        end
                    end
                end

                if ManualAttachUtil:getHasPowerTakeOff(object) and
                        ManualAttachUtil:getIsPowerTakeOffManual(jointDesc) then
                    self:detachPowerTakeOff(vehicle, object)
                end

                --
                --                -- detach dynamic hoses
                --                if g_currentMission.dynamicHoseIsManual then
                --                    if object.detachDynamicHose ~= nil then
                --                        object:detachDynamicHose()
                --                    end
                --                end

                -- force update, due to smooth attach
                vehicle.manualAttachingForcedActiveTime = g_currentMission.time + ManualAttach.FORCED_ACTIVE_TIME_INCREASMENT
                --                self:playSound(vehicle, jointDesc, self.currentSoundPlayer)
            end
        end
    end
end

function ManualAttach:attachPowerTakeOff(vehicle, object, noEventSend)
    --    ManualAttachingPTOEvent.sendEvent(vehicle, object, true, noEventSend)

    local implement = vehicle:getImplementByObject(object)

    if implement ~= nil then
        local jointDesc = vehicle.attacherJoints[implement.jointDescIndex]
        local object = implement.object

        local attachPto = function(object, jointDesc, type, overwriteOutput)
            if not jointDesc[('%sActive'):format(type)] then
                local input = object[('%sInput'):format(type)]

                local outputJointDesc = overwriteOutput ~= '' and jointDesc[('%sOutput'):format(overwriteOutput)] or jointDesc[('%sOutput'):format(type)]
                local outputObject = overwriteOutput ~= '' and object[('%sOutput'):format(overwriteOutput)] or object[('%sOutput'):format(type)]

                if input ~= nil then
                    local isActive = false

                    if input.rootNode ~= nil then
                        if input.isNonScalable ~= nil and input.isNonScalable then
                            if object.attachMovingPowerTakeOff ~= nil then
                                object:attachMovingPowerTakeOff(object, input, outputJointDesc)
                                isActive = true
                            end
                        else
                            link(outputJointDesc.node, input.rootNode)
                            link(input.node, input.attachNode)

                            if object.addWashableNode ~= nil then
                                object:addWashableNode(input.rootNode)
                                object:addWashableNode(input.attachNode)
                                object:addWashableNode(input.dirAndScaleNode)
                                object:setDirtAmount(object:getDirtAmount(), true)
                            end

                            isActive = true
                        end
                    else
                        if outputJointDesc ~= nil then
                            local player = g_currentMission.player

                            --                            link(outputJointDesc.node, outputJointDesc.rootNode)
                            player.ptoRootNode = createTransformGroup("ptoRootNode");

                            link(player.toolsRootNode, player.ptoRootNode)
                            setTranslation(player.ptoRootNode, -0.35, -0.15, 0.45) -- fixed location
                            setRotation(player.ptoRootNode, 0, math.deg(180), 0)

                            link(player.ptoRootNode, outputJointDesc.rootNode)
                            link(input.node, outputJointDesc.attachNode)
                            --                            link(player.toolsRootNode, outputJointDesc.attachNode)

                            if object.addWashableNode ~= nil then
                                object:addWashableNode(outputJointDesc.rootNode)
                                object:addWashableNode(outputJointDesc.attachNode)
                                object:addWashableNode(outputJointDesc.dirAndScaleNode)
                                object:setDirtAmount(object:getDirtAmount(), true)
                            end

                            isActive = true
                        end
                    end

                    jointDesc[('%sActive'):format(type)] = isActive
                    -- Only works if tool has powerConsumer spec, tool also needs neededPtoPower and ptoRpm to be > 0.
                    if isActive then
                        jointDesc.canTurnOnImplement = jointDesc.canTurnOnImplementBackUp
                    end
                end
            end
        end

        for _, type in pairs(ManualAttach._PTO_TYPES) do
            attachPto(object, jointDesc, type)
        end

        -- attachPto(object, jointDesc, 'movingPto', 'pto') -- future update on the moving pto script
        -- attachPto(object, jointDesc, 'pto')
        -- attachPto(object, jointDesc, 'pto2')

        vehicle:updatePowerTakeoff(implement, 0, 'pto')
        vehicle:updatePowerTakeoff(implement, 0, 'pto2')
        -- vehicle:updatePowerTakeoff(implement, 0, 'movingPto') -- future update on the moving pto script
    end
end

function ManualAttach:detachPowerTakeOff(vehicle, object, noEventSend)
    --    ManualAttachingPTOEvent.sendEvent(vehicle, object, false, noEventSend)

    local implement = vehicle:getImplementByObject(object)

    if implement ~= nil then
        local jointDesc = vehicle.attacherJoints[implement.jointDescIndex]
        local object = implement.object

        local detachPto = function(object, jointDesc, type, overwriteOutput)
            -- Only works if tool has powerConsumer spec, tool also needs neededPtoPower and ptoRpm to be > 0.
            if jointDesc.canTurnOnImplementBackUp == nil then
                jointDesc.canTurnOnImplementBackUp = jointDesc.canTurnOnImplement
            end

            local overwriteType = overwriteOutput ~= '' and overwriteOutput or type
            local isActive = false

            if jointDesc[('%sActive'):format(type)] then
                local input = object[('%sInput'):format(type)]
                local outputJointDesc = overwriteOutput ~= '' and jointDesc[('%sOutput'):format(overwriteOutput)] or jointDesc[('%sOutput'):format(type)]
                local outputObject = overwriteOutput ~= '' and object[('%sOutput'):format(overwriteOutput)] or object[('%sOutput'):format(type)]

                isActive = true

                if input ~= nil and input.rootNode ~= nil then
                    if input.isNonScalable ~= nil and input.isNonScalable then
                        if object.detachMovingPowerTakeOff ~= nil then
                            object:detachMovingPowerTakeOff(object, input)
                            isActive = false
                        end
                    else
                        unlink(input.rootNode)
                        unlink(input.attachNode)

                        if object.removeWashableNode ~= nil then
                            object:removeWashableNode(outputObject.rootNode)
                            object:removeWashableNode(outputObject.attachNode)
                            object:removeWashableNode(outputObject.dirAndScaleNode)
                        end

                        isActive = false
                    end
                else
                    unlink(outputJointDesc.rootNode)
                    unlink(outputJointDesc.attachNode)

                    if object.removeWashableNode ~= nil then
                        object:removeWashableNode(outputJointDesc.rootNode)
                        object:removeWashableNode(outputJointDesc.attachNode)
                        object:removeWashableNode(outputJointDesc.dirAndScaleNode)
                    end

                    isActive = false
                end
            end

            jointDesc[('%sActive'):format(type)] = isActive

            if not isActive then
                jointDesc.canTurnOnImplement = false
            end
        end

        for _, type in pairs(ManualAttach._PTO_TYPES) do
            detachPto(object, jointDesc, type)
        end

        -- detachPto(object, jointDesc, 'movingPto', 'pto') -- future update on the moving pto script
        -- detachPto(object, jointDesc, 'pto')
        -- detachPto(object, jointDesc, 'pto2')
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


---
-- @param object
-- @param jointDesc
--
function ManualAttach:getIsJointMoveDownAllowed(object, jointDesc)
    if object ~= nil then
        if object.mountDynamic ~= nil and object.dynamicMountObject ~= nil then
            return false
        end

        -- ignore vehicles which unfold at lowering state
        if object.foldMiddleAnimTime ~= nil then
            return false
        end
    end

    return true
end
