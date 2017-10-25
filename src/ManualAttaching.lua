--
-- ManualAttaching
--
-- Authors: Wopster
-- Description: The main specilization for Manual Attaching
--
-- Copyright (c) Wopster, 2015 - 2017

ManualAttaching = {
    debug = false,
    baseDirectory = g_currentModDirectory,
    message = {
        attach = g_i18n:getText('MANUAL_ATTACHING_ATTACH'),
        detach = g_i18n:getText('MANUAL_ATTACHING_DETACH'),
        attachPto = g_i18n:getText('MANUAL_ATTACHING_ATTACHPTO'),
        detachPto = g_i18n:getText('MANUAL_ATTACHING_DETACHPTO'),
        attachPtoWarning = g_i18n:getText('MANUAL_ATTACHING_ATTACHPTO_WARNING'),
        detachPtoWarning = g_i18n:getText('MANUAL_ATTACHING_DETACHPTO_WARNING'),
        attachDynamicHoses = g_i18n:getText('MANUAL_ATTACHING_ATTACHDYNAMICHOSES'),
        detachDynamicHoses = g_i18n:getText('MANUAL_ATTACHING_DETACHDYNAMICHOSES'),
        turnOffWarning = g_i18n:getText('MANUAL_ATTACHING_TURNOFF_WARNING'),
        dynamicHosesWarning = g_i18n:getText('MANUAL_ATTACHING_DYNAMICHOSES_WARNING'),
        cutterWarning = g_i18n:getText('MANUAL_ATTACHING_CUT_WARNING'),
        lowerWarning = g_i18n:getText('MANUAL_ATTACHING_LOWER_WARNING')
    },
    ptoTypes = {
        pto = '', -- in lua we cannot simply put a nil in a table..
        pto2 = '',
        movingPto = 'pto'
    }
}

ManualAttaching.COSANGLE_THRESHOLD = math.cos(math.rad(70))
ManualAttaching.PLAYER_MIN_DISTANCE = 9
ManualAttaching.PLAYER_DISTANCE = math.huge
ManualAttaching.TIMER_THRESHOLD = 200 -- ms
ManualAttaching.DETACHING_NOT_ALLOWED_TIME = 50 -- ms
ManualAttaching.DETACHING_PRIORITY_NOT_ALLOWED = 6
ManualAttaching.ATTACHING_PRIORITY_ALLOWED = 1
ManualAttaching.JOINT_DISTANCE = 1.3
ManualAttaching.JOINT_SEQUENCE = 0.6 * 0.6
ManualAttaching.FORCED_ACTIVE_TIME_INCREASMENT = 600 -- ms

local function jointTypeNameToInt(typeName)
    local jointType = AttacherJoints.jointTypeNameToInt[typeName]

    -- Custom joints needs a check if it exists in the game
    return jointType ~= nil and jointType or -1
end

ManualAttaching.MANUAL_JOINTYPES = {
    [jointTypeNameToInt('skidSteer')] = true,
    [jointTypeNameToInt('cutter')] = true,
    [jointTypeNameToInt('cutterHarvester')] = true,
    [jointTypeNameToInt('wheelLoader')] = true,
    [jointTypeNameToInt('frontloader')] = true,
    [jointTypeNameToInt('telehandler')] = true,
    [jointTypeNameToInt('hookLift')] = true,
    [jointTypeNameToInt('semitrailer')] = true,
    [jointTypeNameToInt('semitrailerHook')] = true,
    [jointTypeNameToInt('fastCoupler')] = true
}

source(ManualAttaching.baseDirectory .. 'src/events/ManualAttachingPTOEvent.lua')
source(ManualAttaching.baseDirectory .. 'src/events/ManualAttachingDynamicHosesEvent.lua')

---
-- @param filename
--
function ManualAttaching:loadMap(filename)
    self.inRangeManual = {
        attachedVehicle = nil,
        vehicle = nil,
        attachedImplement = nil,
        attachedImplementIndex = nil,
        attachedImplementInputJoint = nil,
        attachableInMountRange = nil,
        attachableInMountRangeInputJointIndex = nil,
        attachableInMountRangeJointIndex = nil,
        attachableInMountRangeInputJoint = nil,
        attachableInMountRangeJoint = nil
    }

    self.inRangeNonManual = {
        vehicle = nil,
        attachedImplement = nil,
        attachableInMountRange = nil,
        attachableInMountRangeInputJointIndex = nil,
        attachableInMountRangeJointIndex = nil,
        attachableInMountRangeInputJoint = nil,
        attachableInMountRangeJoint = nil
    }

    self.currentSoundPlayer = nil
    self.playerDistance = ManualAttaching.PLAYER_DISTANCE
    self.attachedPlayerDistance = ManualAttaching.PLAYER_DISTANCE
    self.attachAllowed = false
    self.detachAllowed = false

    self.resetInRangeManualTable = true
    self.resetInRangeAttachedManualTable = true

    g_currentMission.dynamicHoseIsManual = true
    g_currentMission.callbackManualAttaching = self
end

---
--
function ManualAttaching:deleteMap()
    g_currentMission.callbackManualAttaching = nil
end

---
-- @param ...
--
function ManualAttaching:mouseEvent(...)
end

---
-- @param ...
--
function ManualAttaching:keyEvent(...)
end

---
-- @param dt
--
function ManualAttaching:update(dt)
    if not g_currentMission:getIsClient() then
        return
    end

    if self.resetInRangeManualTable then
        self:resetManualAttachableTable()
    end

    if self.resetInRangeAttachedManualTable then
        self:resetManualAttachedTable()
    end

    --    self:resetManualTable()
    self:resetNonManualTable()

    self.resetInRangeManualTable = true
    self.resetInRangeAttachedManualTable = true

    if ManualAttaching:getIsValidPlayer() then
        for _, vehicle in pairs(g_currentMission.vehicles) do
            if ManualAttaching:getIsValidVehicle(vehicle) then
                self:getIsManualAttachableInRange(vehicle)
            end
        end

        local ir = self.inRangeManual
        local player = g_currentMission.player

        if player.manualAttachingTimer == nil then
            player.manualAttachingTimer = { time = 0, longEnough = false }
        end

        if ir.vehicle ~= nil or ir.attachedVehicle ~= nil then
            -- Handle attach / detach
            if InputBinding.hasEvent(InputBinding.ATTACH) then
                self:handleAttachDetach()
            end
        end

        if ir.attachedVehicle ~= nil then
            if ir.attachedImplement ~= nil then
                local implement = ir.attachedVehicle:getImplementByObject(ir.attachedImplement)

                if implement ~= nil then
                    local jointDesc = ir.attachedVehicle.attacherJoints[implement.jointDescIndex]

                    ir.attachedImplement.dynamicHoseIsManual = self:isDynamicHosesManual(jointDesc)

                    if InputBinding.isPressed(InputBinding.IMPLEMENT_EXTRA4) then
                        if player.manualAttachingTimer.time < ManualAttaching.TIMER_THRESHOLD then
                            player.manualAttachingTimer.time = player.manualAttachingTimer.time + dt
                        else
                            self:handleDynamicHoses(jointDesc)
                        end
                    else
                        self:handlePowerTakeOff(jointDesc)
                    end
                end
            end
        end
    else
        self:setInRangeNonManual(g_currentMission.controlledVehicle)

        local ir = self.inRangeNonManual

        if ir.vehicle ~= nil then
            if ir.attachableInMountRange ~= nil then
                if InputBinding.hasEvent(InputBinding.ATTACH) then
                    if self.attachAllowed then
                        local jointDesc = ir.vehicle.attacherJoints[ir.attachableInMountRangeJointIndex]

                        ir.attachableInMountRange.dynamicHoseIsManual = self:isDynamicHosesManual(jointDesc)

                        self:attachImplement(ir.vehicle, ir.attachableInMountRange, ir.attachableInMountRangeJointIndex, ir.attachableInMountRangeInputJointIndex, true)
                    end
                end

                self.attachAllowed = true

                if #ir.vehicle.attachedImplements > 0 then
                    if ir.vehicle:getImplementByObject(ir.attachableInMountRange) ~= nil then
                        self.attachAllowed = false
                    end
                end
            end
        end

        -- reduce disable looping
        self.detachAllowed = true

        if not g_currentMission.isPlayerFrozen then -- that somehow prevented an error.. can't remember
            if self.detachAllowed then
                if g_currentMission.controlledVehicle ~= nil then
                    self:disableDetachRecursively(g_currentMission.controlledVehicle)
                end
            end

            self.detachAllowed = false
        end

        if not self.detachAllowed then
            g_currentMission.attachableInMountRange = nil
        end
    end

    self:drawHud()
end

---
--
function ManualAttaching:draw()
end

---
-- @param vehicle
--
function ManualAttaching:getIsValidVehicle(vehicle)
    return vehicle.isa ~= nil and vehicle:isa(Vehicle) and not vehicle:isa(StationCrane) -- dismiss trains and the station crane
end

---
--
function ManualAttaching:resetManualAttachableTable()
    local ir = self.inRangeManual

    if ir.vehicle ~= nil then
        ir.vehicle = nil
    end

    if ir.attachableInMountRange ~= nil then
        ir.attachableInMountRange = nil
    end

    if ir.attachableInMountRangeInputJointIndex ~= nil then
        ir.attachableInMountRangeInputJointIndex = nil
    end

    if ir.attachableInMountRangeJointIndex ~= nil then
        ir.attachableInMountRangeJointIndex = nil
    end

    if ir.attachableInMountRangeInputJoint ~= nil then
        ir.attachableInMountRangeInputJoint = nil
    end


    if ir.attachableInMountRangeJoint ~= nil then
        ir.attachableInMountRangeJoint = nil
    end

    self.playerDistance = ManualAttaching.PLAYER_DISTANCE
end

---
--
function ManualAttaching:resetManualAttachedTable()
    local ir = self.inRangeManual

    if ir.attachedVehicle ~= nil then
        ir.attachedVehicle = nil
    end

    if ir.attachedImplement ~= nil then
        ir.attachedImplement = nil
    end

    if ir.attachedImplementIndex ~= nil then
        ir.attachedImplementIndex = nil
    end

    if ir.attachedImplementInputJoint ~= nil then
        ir.attachedImplementInputJoint = nil
    end

    self.attachedPlayerDistance = ManualAttaching.PLAYER_DISTANCE
end

---
--
function ManualAttaching:resetNonManualTable()
    local ir = self.inRangeNonManual

    ir.vehicle = nil
    ir.attachedImplement = nil
    ir.attachableInMountRange = nil
    ir.attachableInMountRangeInputJointIndex = nil
    ir.attachableInMountRangeJointIndex = nil
    ir.attachableInMountRangeInputJoint = nil
    ir.attachableInMountRangeJoint = nil
end

---
-- @param attacherJoint
-- @param jointTrans
-- @param distanceSequence
--
function ManualAttaching:getAttachableInJointRange(attacherJoint, jointTrans, distanceSequence)
    if #g_currentMission.attachables <= 0 or attacherJoint == nil or jointTrans == nil then
        return nil, nil, nil, distanceSequence
    end

    if distanceSequence == nil then
        distanceSequence = ManualAttaching.JOINT_SEQUENCE
    end

    for _, attachable in pairs(g_currentMission.attachables) do
        if attachable.attacherVehicle == nil then
            for i, inputAttacherJoint in pairs(attachable.inputAttacherJoints) do
                if attachable:getIsInputAttacherActive(inputAttacherJoint) and inputAttacherJoint.jointType == attacherJoint.jointType then
                    local inputJointTrans = { getWorldTranslation(inputAttacherJoint.node) }
                    local distanceJoints = Utils.vector2LengthSq(inputJointTrans[1] - jointTrans[1], inputJointTrans[3] - jointTrans[3])

                    if distanceJoints < distanceSequence then
                        if (math.abs(inputJointTrans[2] - jointTrans[2])) < ManualAttaching.JOINT_DISTANCE then
                            local cosAngle = ManualAttaching:calculateCosAngle(inputAttacherJoint.node, attacherJoint.jointTransform)

                            if cosAngle > ManualAttaching.COSANGLE_THRESHOLD or ManualAttaching:getDoesNotNeedCosAngleValidation(attacherJoint) then
                                return attachable, inputAttacherJoint, i, distanceJoints
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
-- @param sq
--
function ManualAttaching:getIsManualAttachableInRange(vehicle, sq)
    if vehicle == nil then
        return
    end

    local playerTrans = { getWorldTranslation(g_currentMission.player.rootNode) }
    local ir = self.inRangeManual
    local distanceSequence = ManualAttaching.JOINT_SEQUENCE

    if vehicle.attachedImplements ~= nil and vehicle.attacherJoints ~= nil then
        for i, implement in pairs(vehicle.attachedImplements) do
            if implement.jointDescIndex ~= nil then
                local jointTrans = { getWorldTranslation(vehicle.attacherJoints[implement.jointDescIndex].jointTransform) }
                local distance = Utils.vector3LengthSq(jointTrans[1] - playerTrans[1], jointTrans[2] - playerTrans[2], jointTrans[3] - playerTrans[3])

                if distance < ManualAttaching.PLAYER_MIN_DISTANCE and distance < self.attachedPlayerDistance then
                    if ir.attachedImplement ~= implement.object then
                        ir.attachedVehicle = vehicle
                        ir.attachedImplement = implement.object
                        ir.attachedImplementIndex = i
                        ir.attachedImplementInputJoint = implement.object.inputAttacherJoints[implement.object.inputAttacherJointDescIndex]
                        self.attachedPlayerDistance = distance
                        self.resetInRangeAttachedManualTable = false
                    end
                end
            end
        end
    end

    if vehicle.attacherJoints ~= nil then
        for j, attacherJoint in pairs(vehicle.attacherJoints) do
            if attacherJoint.jointIndex == 0 then -- prevent double
                local jointTrans = { getWorldTranslation(attacherJoint.jointTransform) }
                local distance = Utils.vector3LengthSq(jointTrans[1] - playerTrans[1], jointTrans[2] - playerTrans[2], jointTrans[3] - playerTrans[3])

                if distance < ManualAttaching.PLAYER_MIN_DISTANCE and distance < self.playerDistance then
                    local attachable, inputAttacherJoint, inputAttacherJointIndex, distanceSq = self:getAttachableInJointRange(attacherJoint, jointTrans)

                    if attachable ~= nil and attachable ~= ir.attachableInMountRange or
                            inputAttacherJoint ~= nil and inputAttacherJoint ~= ir.attachableInMountRangeInputJoint or
                            inputAttacherJointIndex ~= nil and inputAttacherJointIndex ~= ir.attachableInMountRangeInputJointIndex then
                        ir.vehicle = vehicle
                        -- ir.attachedImplement = nil
                        ir.attachableInMountRange = attachable
                        ir.attachableInMountRangeInputJoint = inputAttacherJoint
                        ir.attachableInMountRangeInputJointIndex = inputAttacherJointIndex
                        ir.attachableInMountRangeJoint = attacherJoint
                        ir.attachableInMountRangeJointIndex = j

                        self.playerDistance = distance
                        distanceSequence = distanceSq
                        -- disable reset since we should have set this vehicle already
                        self.resetInRangeManualTable = false
                    end
                end
            end
        end
    end
end

---
-- @param vehicle
--
function ManualAttaching:setInRangeNonManual(vehicle)
    local ir = self.inRangeNonManual

    if vehicle ~= nil then
        if vehicle.attacherJoints ~= nil then -- add this to exclude if someone doesn't have an attacherJoint to a vehicle.. dunno why though..
            for j, attacherJoint in pairs(vehicle.attacherJoints) do
                if attacherJoint.jointIndex == 0 then -- prevent double
                    local jointTrans = { getWorldTranslation(attacherJoint.jointTransform) }
                    local nearestDisSequence = ManualAttaching.JOINT_SEQUENCE

                    for _, attachable in pairs(g_currentMission.attachables) do
                        if attachable.attacherVehicle == nil then
                            for i, inputAttacherJoint in pairs(attachable.inputAttacherJoints) do
                                local ix, iy, iz = getWorldTranslation(inputAttacherJoint.node)
                                local inputJointTrans = { getWorldTranslation(inputAttacherJoint.node) }

                                if attachable:getIsInputAttacherActive(inputAttacherJoint) and inputAttacherJoint.jointType == attacherJoint.jointType then
                                    local distance = Utils.vector2LengthSq(inputJointTrans[1] - jointTrans[1], inputJointTrans[3] - jointTrans[3])

                                    if distance < nearestDisSequence then
                                        if (math.abs(inputJointTrans[2] - jointTrans[2])) < ManualAttaching.JOINT_DISTANCE then
                                            local cosAngle = ManualAttaching:calculateCosAngle(inputAttacherJoint.node, attacherJoint.jointTransform)

                                            if cosAngle > ManualAttaching.COSANGLE_THRESHOLD or ManualAttaching:getDoesNotNeedCosAngleValidation(attacherJoint) then
                                                if not self:isManual(attachable, inputAttacherJoint) then
                                                    ir.vehicle = vehicle
                                                    ir.attachableInMountRange = attachable
                                                    ir.attachableInMountRangeInputJoint = inputAttacherJoint
                                                    ir.attachableInMountRangeInputJointIndex = i
                                                    ir.attachableInMountRangeJoint = attacherJoint
                                                    ir.attachableInMountRangeJointIndex = j

                                                    nearestDisSequence = distance
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                else
                    if vehicle.attachedImplements ~= nil then
                        local implementIndex = vehicle:getImplementIndexByJointDescIndex(j)

                        if implementIndex ~= nil then
                            local object = vehicle.attachedImplements[implementIndex].object

                            if object ~= nil then
                                self:setInRangeNonManual(object)
                            end
                        end
                    end
                end
            end
        end
    end
end

---
--
function ManualAttaching:drawHud()
    if self.inRangeManual ~= nil then
        local ir = self.inRangeManual

        -- Manual vehicles
        if ir.attachedImplement == nil and ir.attachableInMountRange ~= nil then
            -- Attach
            if self:isManual(ir.attachableInMountRange, ir.attachableInMountRangeInputJoint) then
                g_currentMission:addHelpButtonText(ManualAttaching.message.attach:format(self:getStoreName(ir.attachableInMountRange)), InputBinding.ATTACH)
                g_currentMission:enableHudIcon('attach', ManualAttaching.ATTACHING_PRIORITY_ALLOWED)
            end
        else
            if ir.attachedImplement ~= nil and ir.attachedImplement.attacherVehicle ~= nil then
                local vehicle = ir.attachedImplement.attacherVehicle
                local implement = vehicle:getImplementByObject(ir.attachedImplement)
                local jointDesc = vehicle.attacherJoints[implement.jointDescIndex]

                -- Detach
                if self:isManual(ir.attachedImplement, ir.attachedImplementInputJoint) then
                    g_currentMission:addHelpButtonText(ManualAttaching.message.detach:format(self:getStoreName(ir.attachedImplement)), InputBinding.ATTACH)
                end

                -- Powertakeoff
                if jointDesc.ptoOutput ~= nil then
                    if ManualAttaching:hasPowerTakeOff(implement.object) then
                        if self:isPtoManual(jointDesc) then
                            if jointDesc.ptoActive or jointDesc.movingPtoActive then
                                g_currentMission:addHelpButtonText(ManualAttaching.message.detachPto:format(self:getStoreName(ir.attachedImplement)), InputBinding.IMPLEMENT_EXTRA4)
                            else
                                g_currentMission:addHelpButtonText(ManualAttaching.message.attachPto:format(self:getStoreName(ir.attachedImplement)), InputBinding.IMPLEMENT_EXTRA4)
                                g_currentMission:enableHudIcon('attach', ManualAttaching.ATTACHING_PRIORITY_ALLOWED)
                            end
                        end
                    end
                end

                -- DynamicHoses
                if g_currentMission.dynamicHoseIsManual then
                    if vehicle.hoseRefSets ~= nil and ir.attachedImplement.hoseSets ~= nil then
                        if jointDesc.dynamicHoseIndice ~= nil then
                            if ir.attachedImplement.attacherJoint.dynamicHoseIndice ~= nil then
                                if ir.attachedImplement.attacherJoint.dynamicHoseIsAttached then
                                    if ir.attachedImplement.dynamicHoseIsManual then
                                        g_currentMission:addHelpButtonText(ManualAttaching.message.detachDynamicHoses:format(self:getStoreName(ir.attachedImplement)), InputBinding.IMPLEMENT_EXTRA4)
                                    end
                                else
                                    if ir.attachedImplement.dynamicHoseIsManual then
                                        g_currentMission:addHelpButtonText(ManualAttaching.message.attachDynamicHoses:format(self:getStoreName(ir.attachedImplement)), InputBinding.IMPLEMENT_EXTRA4)
                                        g_currentMission:enableHudIcon('attach', ManualAttaching.ATTACHING_PRIORITY_ALLOWED)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Non manual vehicles
    if self.inRangeNonManual ~= nil then
        local ir = self.inRangeNonManual

        if ir.vehicle ~= nil then
            if ir.attachableInMountRange ~= nil then
                g_currentMission:addHelpButtonText(ManualAttaching.message.attach:format(self:getStoreName(ir.attachableInMountRange)), InputBinding.ATTACH)
                g_currentMission:enableHudIcon('attach', ManualAttaching.ATTACHING_PRIORITY_ALLOWED)
            end
        end
    end
end

---
-- @param vehicle
--
function ManualAttaching:disableDetachRecursively(vehicle)
    local numImplements = #vehicle.attachedImplements

    if numImplements > 0 then
        for i = 1, numImplements do
            local implement = vehicle.attachedImplements[i]

            if implement.object ~= nil or implement.jointDescIndex ~= nil then
                local object = implement.object
                local jointDesc = vehicle.attacherJoints[implement.jointDescIndex]
                local inputJointDesc = object.inputAttacherJoints ~= nil and object.inputAttacherJoints[object.inputAttacherJointDescIndex] or nil

                if jointDesc ~= nil then
                    if object ~= nil then
                        if inputJointDesc ~= nil and ManualAttaching:isManual(object, inputJointDesc) then
                            object.allowsDetaching = false
                            self:disableDetachRecursively(object)
                        else
                            -- local allows = self:scopeAllowsDetaching(implement.object, jointDesc)
                            object.allowsDetaching = self:scopeAllowsDetaching(object, jointDesc, false)

                            if InputBinding.hasEvent(InputBinding.ATTACH) then
                                --                                self:scopeAllowsDetaching(object, jointDesc)
                            end

                            -- Debug
                            -- if ManualAttaching.debug then
                            -- print(self:print_r(implement.object.allowsDetaching, 'allowsDetaching'))
                            -- print(self:print_r(scope, 'scope'))
                            -- end
                        end

                        local checkPto = function(vehicle, object, jointDesc, type, overwriteOutput)
                            if object[('%sInput'):format(type)] ~= nil and (jointDesc[('%sOutput'):format(type)] ~= nil or jointDesc[('%sOutput'):format(overwriteOutput)] ~= nil) then
                                if not jointDesc[('%sActive'):format(type)] then
                                    local canTurnOnVehicle, canTipVehicle = self:scopeAllowsInputVehicle(vehicle, object)

                                    if canTurnOnVehicle ~= nil then
                                        if canTurnOnVehicle:getIsTurnedOn() then
                                            if canTurnOnVehicle.setIsTurnedOn ~= nil then
                                                ManualAttaching:showWarning(ManualAttaching.message.attachPtoWarning, object)
                                                canTurnOnVehicle.manualAttachingForcedActiveSound = true -- dirty i know
                                                canTurnOnVehicle:setIsTurnedOn(false)
                                                canTurnOnVehicle.manualAttachingForcedActiveSound = false
                                            end

                                            -- Handle AI if not stopped already
                                            if canTurnOnVehicle.isHired ~= nil then
                                                if canTurnOnVehicle.isHired then
                                                    ManualAttaching:showWarning(ManualAttaching.message.attachPtoWarning, object)
                                                    canTurnOnVehicle:stopAIVehicle()
                                                end
                                            end
                                        end
                                    end

                                    if canTipVehicle ~= nil then
                                        if canTipVehicle.tipState ~= nil then
                                            if canTipVehicle.tipState == Trailer.TIPSTATE_OPEN or canTipVehicle.tipState == Trailer.TIPSTATE_OPENING then
                                                if canTipVehicle.tiltContainerOnDischarge ~= nil then
                                                    if not canTipVehicle.tiltContainerOnDischarge then
                                                        ManualAttaching:showWarning(ManualAttaching.message.attachPtoWarning, object)
                                                        canTipVehicle:onEndTip()
                                                    end
                                                else
                                                    ManualAttaching:showWarning(ManualAttaching.message.attachPtoWarning, object)
                                                    canTipVehicle:onEndTip()
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end

                        checkPto(vehicle, object, jointDesc, 'pto')
                        checkPto(vehicle, object, jointDesc, 'pto2')
                        checkPto(vehicle, object, jointDesc, 'movingPto', 'pto')

                        if inputJointDesc ~= nil then
                            if inputJointDesc.dependentAttacherJoints ~= nil then
                                for _, dependentAttacherJointIndex in pairs(inputJointDesc.dependentAttacherJoints) do
                                    if vehicle.attacherJoints[dependentAttacherJointIndex] ~= nil then
                                        local dependentObject = vehicle.attachedImplements[vehicle:getImplementIndexByJointDescIndex(dependentAttacherJointIndex)]

                                        if dependentObject ~= nil then
                                            checkPto(vehicle, dependentObject, vehicle.attacherJoints[dependentAttacherJointIndex], 'pto')
                                            checkPto(vehicle, dependentObject, vehicle.attacherJoints[dependentAttacherJointIndex], 'pto2')
                                            checkPto(vehicle, dependentObject, vehicle.attacherJoints[dependentAttacherJointIndex], 'movingPto', 'pto')
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    else
        -- Force to select the vehicle to prevent unwanted detach vehicles being in range
        if vehicle.setSelectedImplement ~= nil then
            vehicle:setSelectedImplement(nil)
        end
    end
end

---
-- @param object
-- @param jointDesc
-- @param showWarning
--
function ManualAttaching:scopeAllowsDetaching(object, jointDesc, showWarning)
    showWarning = showWarning == nil and true or showWarning

    local warning

    if g_currentMission.dynamicHoseIsManual then
        if object.hoseSets ~= nil and object.attacherVehicle ~= nil and object.attacherVehicle.hoseRefSets ~= nil then
            if object.attacherJoint.dynamicHoseIndice ~= nil then
                if object.dynamicHoseIsManual then
                    if object.attacherJoint.dynamicHoseIsAttached then
                        warning = ManualAttaching.message.dynamicHosesWarning
                    end
                end
            end
        end
    end

    if self:isPtoManual(jointDesc) then
        if ManualAttaching:hasPowerTakeOff(object) then
            for type, _ in pairs(ManualAttaching.ptoTypes) do
                if ManualAttaching:getCanDetachPowerTakeOff(jointDesc, type) then
                    warning = ManualAttaching.message.detachPtoWarning
                    break
                end
            end
        end
    end

    if warning ~= nil and showWarning then
        ManualAttaching:showWarning(warning, object)
        g_currentMission:enableHudIcon('detachingNotAllowed', ManualAttaching.DETACHING_PRIORITY_NOT_ALLOWED, ManualAttaching.DETACHING_NOT_ALLOWED_TIME)
    end

    -- When nothing blocks the flow return true (implement allows detaching)
    return warning == nil
end

---
-- @param vehicle
-- @param object
--
function ManualAttaching:scopeAllowsInputVehicle(vehicle, object)
    local canTurnOn, canTip

    if vehicle.getIsTurnedOn ~= nil then
        if vehicle:getCanBeTurnedOn() then
            canTurnOn = vehicle
        end
    end

    if vehicle.getIsTurnedOn == nil then
        if object.getIsTurnedOn ~= nil then
            if object:getCanBeTurnedOn() then
                canTurnOn = object
            end
        end
    end

    if object.tipState ~= nil then
        if object:getCanTip() then
            canTip = object
        end
    end

    for _, childAttachedImplement in pairs(object.attachedImplements) do
        if childAttachedImplement.object ~= nil then
            if childAttachedImplement.object.getIsTurnedOn ~= nil then
                if childAttachedImplement.object:getCanBeTurnedOn() then
                    canTurnOn = childAttachedImplement.object
                end
            end

            if childAttachedImplement.object.tipState ~= nil then
                if childAttachedImplement.object:getCanTip() then
                    canTip = childAttachedImplement.object
                end
            end
        end
    end

    return canTurnOn, canTip
end

---
--
function ManualAttaching:handleAttachDetach()
    local ir = self.inRangeManual

    self:setSoundPlayer(g_currentMission.player)

    if ir.attachableInMountRange ~= nil then
        self:attachImplement(ir.vehicle, ir.attachableInMountRange, ir.attachableInMountRangeJointIndex, ir.attachableInMountRangeInputJointIndex)
    elseif ir.attachedImplement ~= nil then
        self:detachImplement(ir.attachedVehicle, ir.attachedImplement, ir.attachedImplementIndex)
    end
end

---
-- @param vehicle
-- @param object
-- @param jointDescIndex
-- @param inputJointDescIndex
-- @param force
--
function ManualAttaching:attachImplement(vehicle, object, jointDescIndex, inputJointDescIndex, force)
    if vehicle ~= nil and object ~= nil then
        local jointDesc = vehicle.attacherJoints[jointDescIndex]
        local inputJointDesc = object.inputAttacherJoints[inputJointDescIndex]

        if jointDesc ~= nil and inputJointDesc ~= nil then
            if ManualAttaching:isManual(object, inputJointDesc) or force then
                local startLowered = ManualAttaching:getIsJointMoveDownAllowed(object, inputJointDesc, true)

                vehicle:attachImplement(object, inputJointDescIndex, jointDescIndex, false, nil, startLowered, false)

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

                if ManualAttaching:hasPowerTakeOff(object) then
                    if ManualAttaching:isPtoManual(jointDesc) then
                        self:detachPowerTakeOff(vehicle, object)
                    end
                end

                -- detach dynamic hoses
                if g_currentMission.dynamicHoseIsManual then
                    if object.detachDynamicHose ~= nil then
                        object:detachDynamicHose()
                    end
                end

                -- force update, due to smooth attach
                vehicle.manualAttachingForcedActiveTime = g_currentMission.time + ManualAttaching.FORCED_ACTIVE_TIME_INCREASMENT
                self:playSound(vehicle, jointDesc, self.currentSoundPlayer)
            end
        end
    end

    return true
end

---
-- @param vehicle
-- @param object
-- @param implementIndex
-- @param force
--
function ManualAttaching:detachImplement(vehicle, object, implementIndex, force)
    if vehicle ~= nil and object ~= nil then
        local implement = vehicle.attachedImplements[implementIndex]
        local jointDesc = vehicle.attacherJoints[implement.jointDescIndex]

        if ManualAttaching:isManual(vehicle, jointDesc) or force then
            if jointDesc.allowsLowering then
                if not jointDesc.moveDown and not (jointDesc.jointType == AttacherJoints.jointTypeNameToInt['attachableFrontloader']) then
                    if (not ManualAttaching:getDoesNotNeedJointMovedown(jointDesc)) and (ManualAttaching:getIsJointMoveDownAllowed(object, jointDesc, false)) then
                        ManualAttaching:showWarning(ManualAttaching.message.lowerWarning, object)
                        g_currentMission:enableHudIcon('detachingNotAllowed', ManualAttaching.DETACHING_PRIORITY_NOT_ALLOWED, ManualAttaching.DETACHING_NOT_ALLOWED_TIME)

                        return false
                        -- else
                        -- handle moveDown exceptions
                    end
                end
            end

            if self:scopeAllowsDetaching(implement.object, jointDesc) then
                -- handle TurnOnVehicle exceptions
                if object.activateTankOnLowering ~= nil and object.activateTankOnLowering then
                    if object.setIsTurnedOn ~= nil then
                        object:setIsTurnedOn(false)
                    end

                    -- if vehicle.turnOnDueToLoweredImplement ~= nil then
                    -- if self.ma.targetVehicle.turnOnDueToLoweredImplement then
                    -- self.ma.targetVehicle:setIsTurnedOn(false)
                    -- self.ma.targetVehicle.turnOnDueToLoweredImplement = nil
                    -- end
                    -- if vehicle.turnOnDueToLoweredImplement.object.activateOnLowering then
                    -- if vehicle.turnOnDueToLoweredImplement.object:getIsTurnedOn() then
                    -- vehicle.turnOnDueToLoweredImplement.object:setIsTurnedOn(false)
                    -- end
                    -- end
                    -- end

                    -- todo: check this?
                    -- if self.ma.targetAttachable.attacherVehicle.attachedTool ~= nil then
                    -- if self.ma.targetAttachable.attacherVehicle.setIsTurnedOn ~= nil then
                    -- self.ma.targetAttachable.attacherVehicle:setIsTurnedOn(false)
                    -- end

                    -- self.ma.targetAttachable:aiTurnOff()
                    -- self.ma.targetAttachable.attacherVehicle:aiTurnOff()
                    -- end
                end

                if (vehicle.getIsTurnedOn ~= nil and vehicle:getIsTurnedOn()) or (object.getIsTurnedOn ~= nil and object:getIsTurnedOn()) then
                    ManualAttaching:showWarning(ManualAttaching.message.turnOffWarning, object)
                    g_currentMission:enableHudIcon('detachingNotAllowed', ManualAttaching.DETACHING_PRIORITY_NOT_ALLOWED, ManualAttaching.DETACHING_NOT_ALLOWED_TIME)

                    return false
                end
            else
                return false
            end

            vehicle:detachImplementByObject(object)
            self:playSound(vehicle, jointDesc, self.currentSoundPlayer)
        end
    end

    return true
end

---
-- @param jointDesc
--
function ManualAttaching:handleDynamicHoses(jointDesc)
    local ir = self.inRangeManual

    local vehicle = ir.attachedVehicle

    self:setSoundPlayer(g_currentMission.player)

    if not g_currentMission.player.manualAttachingTimer.longEnough and g_currentMission.dynamicHoseIsManual then
        local implement = vehicle:getImplementByObject(ir.attachedImplement)
        local implementJoint = ir.attachedImplement.attacherJoint

        if implement ~= nil then
            if jointDesc.dynamicHoseIndice ~= nil and implementJoint.dynamicHoseIndice ~= nil then
                if implementJoint.dynamicHoseIsAttached then
                    if ir.attachedImplement.dynamicHoseIsManual then
                        if not ((ir.attachedImplement.getIsTurnedOn ~= nil and ir.attachedImplement:getIsTurnedOn()) or (vehicle.getIsTurnedOn ~= nil and vehicle:getIsTurnedOn())) then
                            self:detachDynamicHoses(ir.attachedImplement, vehicle, implement.jointDescIndex)
                            self:playSound(vehicle, implementJoint, self.currentSoundPlayer)
                        else
                            self:showWarning(ManualAttaching.message.turnOffWarning, ir.attachedImplement)
                            g_currentMission:enableHudIcon('detachingNotAllowed', ManualAttaching.DETACHING_PRIORITY_NOT_ALLOWED, ManualAttaching.DETACHING_NOT_ALLOWED_TIME)
                        end
                    end
                else
                    if ir.attachedImplement.dynamicHoseIsManual then
                        self:attachDynamicHoses(ir.attachedImplement, vehicle, implement.jointDescIndex)
                        self:playSound(vehicle, implementJoint, self.currentSoundPlayer)
                    end
                end
            end
        end
    end

    g_currentMission.player.manualAttachingTimer.longEnough = true
end

---
-- @param object
-- @param vehicle
-- @param jointDescIndex
-- @param noEventSend
--
function ManualAttaching:attachDynamicHoses(object, vehicle, jointDescIndex, noEventSend)
    -- if not noEventSend then
    ManualAttachingDynamicHosesEvent.sendEvent(object, vehicle, jointDescIndex, true, noEventSend)
    -- end

    if object ~= nil and vehicle ~= nil and jointDescIndex ~= nil then
        object:attachDynamicHose(vehicle, jointDescIndex)
    end
end

---
-- @param object
-- @param vehicle
-- @param jointDescIndex
-- @param noEventSend
--
function ManualAttaching:detachDynamicHoses(object, vehicle, jointDescIndex, noEventSend)
    -- if not noEventSend then
    ManualAttachingDynamicHosesEvent.sendEvent(object, vehicle, jointDescIndex, false, noEventSend)
    -- end

    if object ~= nil and vehicle ~= nil and jointDescIndex ~= nil then
        object:detachDynamicHose()
    end
end

---
-- @param jointDesc
--
function ManualAttaching:handlePowerTakeOff(jointDesc)
    local ir = self.inRangeManual

    local vehicle = ir.attachedVehicle

    self:setSoundPlayer(g_currentMission.player)

    if g_currentMission.player.manualAttachingTimer.time > 0 then
        if g_currentMission.player.manualAttachingTimer.time < ManualAttaching.TIMER_THRESHOLD then
            if vehicle ~= nil and ir.attachedImplement ~= nil then
                if ManualAttaching:hasPowerTakeOff(ir.attachedImplement) then
                    if self:isPtoManual(jointDesc) then
                        if ManualAttaching:getCanDetachPowerTakeOff(jointDesc, 'pto') or ManualAttaching:getCanDetachPowerTakeOff(jointDesc, 'pto2') or ManualAttaching:getCanDetachPowerTakeOff(jointDesc, 'movingPto') then
                            if not ((ir.attachedImplement.getIsTurnedOn ~= nil and ir.attachedImplement:getIsTurnedOn()) or (vehicle.getIsTurnedOn ~= nil and vehicle:getIsTurnedOn())) then
                                self:detachPowerTakeOff(vehicle, ir.attachedImplement)
                                self:playSound(vehicle, jointDesc, self.currentSoundPlayer)
                            else
                                ManualAttaching:showWarning(ManualAttaching.message.turnOffWarning, ir.attachedImplement)
                                g_currentMission:enableHudIcon('detachingNotAllowed', ManualAttaching.DETACHING_PRIORITY_NOT_ALLOWED, ManualAttaching.DETACHING_NOT_ALLOWED_TIME)
                            end
                        else
                            self:attachPowerTakeOff(vehicle, ir.attachedImplement)
                            self:playSound(vehicle, jointDesc, self.currentSoundPlayer)
                        end
                    end
                end
            end
        end

        g_currentMission.player.manualAttachingTimer.time = 0
        g_currentMission.player.manualAttachingTimer.longEnough = false
    end
end

---
-- @param vehicle
-- @param object
-- @param noEventSend
--
function ManualAttaching:attachPowerTakeOff(vehicle, object, noEventSend)
    ManualAttachingPTOEvent.sendEvent(vehicle, object, true, noEventSend)

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
                            link(outputJointDesc.node, outputJointDesc.rootNode)
                            link(input.node, outputJointDesc.attachNode)

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

        for type, overwrite in pairs(ManualAttaching.ptoTypes) do
            attachPto(object, jointDesc, type, overwrite)
        end

        -- attachPto(object, jointDesc, 'movingPto', 'pto') -- future update on the moving pto script
        -- attachPto(object, jointDesc, 'pto')
        -- attachPto(object, jointDesc, 'pto2')

        vehicle:updatePowerTakeoff(implement, 0, 'pto')
        vehicle:updatePowerTakeoff(implement, 0, 'pto2')
        -- vehicle:updatePowerTakeoff(implement, 0, 'movingPto') -- future update on the moving pto script
    end
end

---
-- @param vehicle
-- @param object
-- @param noEventSend
--
function ManualAttaching:detachPowerTakeOff(vehicle, object, noEventSend)
    ManualAttachingPTOEvent.sendEvent(vehicle, object, false, noEventSend)

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

        for type, overwrite in pairs(ManualAttaching.ptoTypes) do
            detachPto(object, jointDesc, type, overwrite)
        end

        -- detachPto(object, jointDesc, 'movingPto', 'pto') -- future update on the moving pto script
        -- detachPto(object, jointDesc, 'pto')
        -- detachPto(object, jointDesc, 'pto2')
    end
end

---
--
function ManualAttaching:getIsValidPlayer()
    local hasHoseSystem = false

    if g_currentMission.player.hoseSystem ~= nil then
        hasHoseSystem = g_currentMission.player.hoseSystem.index ~= nil
    end

    return not hasHoseSystem and
            g_currentMission.controlPlayer and
            g_currentMission.player ~= nil and
            g_currentMission.player.currentTool == nil and
            not g_currentMission.player.hasHPWLance and
            not g_currentMission.player.isCarryingObject and
            not g_currentMission.isPlayerFrozen and
            not g_gui:getIsGuiVisible()
end

---
-- @param vehicle
-- @param jointDesc
-- @param type
--
function ManualAttaching:isManual(vehicle, jointDesc, type)
    if not ManualAttaching.MANUAL_JOINTYPES[jointDesc.jointType] then
        if jointDesc.isManual ~= nil then
            if not jointDesc.isManual then
                return false
            end
        end

        if type ~= nil then
            if vehicle.manualAttaching ~= nil then
                if vehicle.manualAttaching[type] ~= nil then
                    if not vehicle.manualAttaching[type] then
                        return false
                    end
                end
            end
        end

        return true
    end

    return false
end

---
-- @param jointDesc
-- @param type
--
function ManualAttaching:getCanDetachPowerTakeOff(jointDesc, type)
    return jointDesc[('%sActive'):format(type)]
end

---
-- @param object
--
function ManualAttaching:hasPowerTakeOff(object)
    for type, _ in pairs(ManualAttaching.ptoTypes) do
        if object[('%sInput'):format(type)] ~= nil then
            return true
        end
    end

    return false
end

---
-- @param object
-- @param jointDesc
--
function ManualAttaching:getIsJointMoveDownAllowed(object, jointDesc, onAttach)
    if object ~= nil then
        if object.mountDynamic ~= nil and object.dynamicMountObject ~= nil then
            return false
        end

        if object.foldingParts ~= nil and #object.foldingParts > 0 then
            return false
        end
    end

    if onAttach then
        return jointDesc.isDefaultLowered
    end

    return true
end

---
-- @param jointDesc
--
function ManualAttaching:getDoesNotNeedJointMovedown(jointDesc)
    return (jointDesc.jointType == AttacherJoints.jointTypeNameToInt['cutter']) or (jointDesc.jointType == AttacherJoints.jointTypeNameToInt['cutterHarvester'])
end

---
-- @param jointDesc
---
function ManualAttaching:getDoesNotNeedCosAngleValidation(jointDesc)
    return jointDesc.jointType == AttacherJoints.jointTypeNameToInt['conveyor']
end

---
-- @param message
-- @param implement
--
function ManualAttaching:showWarning(message, implement)
    local implementName = ManualAttaching:getStoreName(implement)

    if implementName ~= nil then
        g_currentMission:showBlinkingWarning(string.format(message, implementName))
    end
end

---
-- @param implement
--
function ManualAttaching:getStoreName(implement)
    return StoreItemsUtil.storeItemsByXMLFilename[implement.configFileName:lower()].name
end

---
-- @param p1
-- @param p2
--
function ManualAttaching:calculateCosAngle(p1, p2)
    local x1, y1, z1 = localDirectionToWorld(p1, 1, 0, 0)
    local x2, y2, z2 = localDirectionToWorld(p2, 1, 0, 0)

    return x1 * x2 + y1 * y2 + z1 * z2
end

---
-- @param player
--
function ManualAttaching:setSoundPlayer(player)
    self.currentSoundPlayer = player
end

---
-- @param vehicle
-- @param jointDesc
-- @param player
-- @param noEventSend
--
function ManualAttaching:playSound(vehicle, jointDesc, player, noEventSend)
    if g_currentMission:getIsClient() and player ~= nil then
        -- if not noEventSend then
        -- ManualAttachingSoundEvent.sendEvent(vehicle, jointDesc, player, noEventSend)
        -- end

        if player == self.currentSoundPlayer then
            if jointDesc ~= nil and jointDesc.sampleAttach ~= nil then
                SoundUtil.playSample(jointDesc.sampleAttach, 1, 0, nil)
            else
                SoundUtil.playSample(vehicle.sampleAttach, 1, 0, nil)
            end

            -- self:setSoundPlayer(nil)
        end
    end
end

---
-- @param jointDesc
--
function ManualAttaching:isDynamicHosesManual(jointDesc)
    if jointDesc.dynamicHosesIsManual ~= nil then
        if not jointDesc.dynamicHosesIsManual then
            return false
        end
    end

    return true
end

---
-- @param jointDesc
--
function ManualAttaching:isPtoManual(jointDesc)
    if jointDesc.ptoIsManual ~= nil then
        if not jointDesc.ptoIsManual then
            return false
        end
    end

    return true
end

---
-- @param t
-- @param name
-- @param indent
--
function ManualAttaching:print_r(t, name, indent)
    local tableList = {}

    function table_r(t, name, indent, full)
        local id = not full and name or type(name) ~= "number" and tostring(name) or '[' .. name .. ']'
        local tag = indent .. id .. ' : '
        local out = {}

        if type(t) == "table" then
            if tableList[t] ~= nil then
                table.insert(out, tag .. '{} -- ' .. tableList[t] .. ' (self reference)')
            else
                tableList[t] = full and (full .. '.' .. id) or id

                if next(t) then -- If table not empty.. fill it further
                    table.insert(out, tag .. '{')

                    for key, value in pairs(t) do
                        table.insert(out, table_r(value, key, indent .. '|  ', tableList[t]))
                    end

                    table.insert(out, indent .. '}')
                else
                    table.insert(out, tag .. '{}')
                end
            end
        else
            local val = type(t) ~= "number" and type(t) ~= "boolean" and '"' .. tostring(t) .. '"' or tostring(t)
            table.insert(out, tag .. val)
        end

        return table.concat(out, '\n')
    end

    return table_r(t, name or 'Value', indent or '')
end

addModEventListener(ManualAttaching)