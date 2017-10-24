--
-- DynamicHose
--
-- @author:    	Xentro (Marcus@Xentro.se)
-- @website:	www.Xentro.se
-- @history:	v1.0 - 2017-01-08 - Initial implementation
-- 				v1.1 - 2017-02-15 - Pickup override by Wopster
-- 
--[[
<dynamicHose>
	<set toolIndices="0">
		<hose type="hydraulic" attached="0>0" detached="0>1" lastHoseIKNode="0>2"/>
	</set>
</dynamicHose>
]] --

DynamicHose = {}

function DynamicHose.prerequisitesPresent(specializations)
    if not SpecializationUtil.hasSpecialization(Cylindered, specializations) then print("Warning: Specialization DynamicHose needs the specialization Cylindered.") end

    return SpecializationUtil.hasSpecialization(Cylindered, specializations)
end

function DynamicHose:preLoad(savegame)
    if g_currentMission.dynamicHoseTypes == nil then
        g_currentMission.dynamicHoseTypes = {}
        g_currentMission.dynamicHoseTypes["hydraulic"] = true
        g_currentMission.dynamicHoseTypes["electric"] = true
        g_currentMission.dynamicHoseTypes["air"] = true
    end

    self.attachDynamicHose = SpecializationUtil.callSpecializationsFunction("attachDynamicHose")
    self.detachDynamicHose = SpecializationUtil.callSpecializationsFunction("detachDynamicHose")
    self.setHoseVisible = SpecializationUtil.callSpecializationsFunction("setHoseVisible")
    self.setHoseAttached = SpecializationUtil.callSpecializationsFunction("setHoseAttached")
    self.getIsHoseAttached = DynamicHose.getIsHoseAttached
    self.updateMovingToolCouplings = DynamicHose.updateMovingToolCouplings
    self.updateHydraulicInputs = DynamicHose.updateHydraulicInputs
    self.updateLightStates = DynamicHose.updateLightStates
    self.loadInputAttacherJoint = Utils.overwrittenFunction(self.loadInputAttacherJoint, DynamicHose.loadExtraAttacherJoints)

    self.gameExtensionDifficultyUpdate = DynamicHose.gameExtensionDifficultyUpdate

    -- Use to override the attaching/detaching of hoses.
    -- g_currentMission.dynamicHoseIsManual = true

    self.dynamicHoseSupport = true

    -- For the future..
    if g_currentMission.dynamicHose ~= nil then
        g_currentMission.dynamicHose:addHoseVehicle(self, 0.5)
    end
end

function DynamicHose:load(savegame)
    self.hoseIsAttached = {} -- Only add hoseTypes we support for this vehicle.

    self.hydraulicEnabled = false
    self.electricEnabled = false
    self.airBrakeEnabled = false

    self.hoseSets = {}
    local i = 0
    while true do
        local key = string.format("vehicle.dynamicHose.set(%d)", i)
        if not hasXMLProperty(self.xmlFile, key) then break end

        local set
        local r = 0
        while true do
            local key2 = string.format(key .. ".hose(%d)", r)
            if not hasXMLProperty(self.xmlFile, key2) then break end

            local hoseType = string.lower(Utils.getNoNil(getXMLString(self.xmlFile, key2 .. "#type"), "hydraulic"))
            if g_currentMission.dynamicHoseTypes[hoseType] then
                local hose1 = Utils.indexToObject(self.components, getXMLString(self.xmlFile, key2 .. "#attached"))
                local hose2 = Utils.indexToObject(self.components, getXMLString(self.xmlFile, key2 .. "#detached"))
                local ikNode = Utils.indexToObject(self.components, getXMLString(self.xmlFile, key2 .. "#lastHoseIKNode"))

                if ikNode ~= nil then
                    if set == nil then set = {} end
                    if set[hoseType] == nil then set[hoseType] = {} end

                    self.hoseIsAttached[hoseType] = { false, false }

                    if hoseType == "hydraulic" then
                        self.hydraulicEnabled = true
                    elseif hoseType == "electric" then
                        self.electricEnabled = true
                    elseif hoseType == "air" then
                        self.airBrakeEnabled = true
                    end

                    local entry = {}
                    entry.attachedHose = hose1
                    entry.detachedHose = hose2
                    entry.ikNode = ikNode

                    if entry.attachedHose ~= nil then
                        setVisibility(entry.attachedHose, false)
                    end
                    if entry.detachedHose ~= nil then
                        setVisibility(entry.detachedHose, true)
                    end

                    table.insert(set[hoseType], entry)
                else
                    print("DynamicHose - Error: lastHoseIKNode is nil in " .. self.configFileName)
                    break
                end
            end

            r = r + 1
        end

        if set ~= nil then
            set.movingToolCouplings = {}
            local toolIds = Utils.getVectorNFromString(getXMLString(self.xmlFile, key .. "#toolIndices"))
            if toolIds ~= nil then
                for _, i in pairs(toolIds) do
                    if self.movingTools[i + 1] ~= nil then
                        table.insert(set.movingToolCouplings, i + 1)
                    end
                end
            end

            table.insert(self.hoseSets, set)
        end

        i = i + 1
    end

    -- Make sure we have valid indices
    for i, joint in ipairs(self.inputAttacherJoints) do
        if joint.dynamicHoseIndice ~= nil then
            if self.hoseSets[joint.dynamicHoseIndice] == nil then
                print("DynamicHose - Error: Invalid dynamicHoseIndice (" .. (joint.dynamicHoseIndice - 1) .. ") in " .. self.configFileName)
                joint.dynamicHoseIsAttached = nil
                joint.dynamicHoseIndice = nil
            end
        end
    end

    if self.hydraulicEnabled then
        if self.getIsFoldAllowed ~= nil then
            self.getIsFoldAllowed = Utils.overwrittenFunction(self.getIsFoldAllowed, DynamicHose.getIsFoldAllowed)
        end

        self.setJointMoveDown = Utils.overwrittenFunction(self.setJointMoveDown, DynamicHose.setJointMoveDown)
    end

    if self.electricEnabled then
        self.setLightsTypesMask = Utils.overwrittenFunction(self.setLightsTypesMask, DynamicHose.updatedSetLightsTypesMask)
        self.setBeaconLightsVisibility = Utils.overwrittenFunction(self.setBeaconLightsVisibility, DynamicHose.updatedSetBeaconLightsVisibility)
        self.setTurnLightState = Utils.overwrittenFunction(self.setTurnLightState, DynamicHose.updatedSetTurnLightState)
        self.setBrakeLightsVisibility = Utils.overwrittenFunction(self.setBrakeLightsVisibility, DynamicHose.updatedSetBrakeLightsVisibility)
        self.setReverseLightsVisibility = Utils.overwrittenFunction(self.setReverseLightsVisibility, DynamicHose.updatedSetReverseLightsVisibility)

        self.updateCurrentLightState = {}
    end

    if self.airBrakeEnabled then
        self.onBrake = Utils.overwrittenFunction(self.onBrake, DynamicHose.updatedOnBrake)
        self.onReleaseBrake = Utils.overwrittenFunction(self.onReleaseBrake, DynamicHose.updatedOnReleaseBrake)

        self.airBrakeActive = false
    end
end

function DynamicHose:postLoad(savegame)
    -- setup an movingPart for the IK node, should reduce the problem to find the correct indice for it...
    for key, value in ipairs(self.hoseSets) do
        for hoseType, allowed in pairs(g_currentMission.dynamicHoseTypes) do
            if value[hoseType] ~= nil then
                for i, v in pairs(value[hoseType]) do
                    local entry = {}

                    entry.node = v.ikNode
                    entry.referenceFrame = self.components[1].node
                    entry.oldRefFrame = entry.referenceFrame
                    entry.invertZ = false
                    entry.scaleZ = false
                    entry.playSound = false

                    entry.moveToReferenceFrame = true
                    entry.referenceFrameOffset = { 0, 0, 0 }

                    entry.doDirectionAlignment = true
                    entry.doRotationAlignment = false
                    entry.rotMultiplier = 0

                    entry.alignToWorldY = false
                    entry.isDirty = false

                    entry.dependentPartNodes = {}
                    if self.isServer then
                        entry.componentJoints = {}
                    end
                    entry.inputAttacherJoint = false
                    entry.copyLocalDirectionParts = {}
                    entry.dependentParts = {}

                    table.insert(self.movingParts, entry)
                    table.insert(self.activeDirtyMovingParts, entry)
                    -- self.nodesToMovingParts[entry.node] = entry
                    v.movingPartIndice = #self.movingParts
                end
            end
        end
    end

    if self.isServer then
        if savegame ~= nil and not savegame.resetVehicles then
            local hoseIsAttached = getXMLBool(savegame.xmlFile, savegame.key .. "#hoseIsAttached")

            if not hoseIsAttached then
                self.hoseIsPendingDetach = true
            end
        end
    end
end

function DynamicHose:delete()
    if g_currentMission.dynamicHose ~= nil then
        g_currentMission.dynamicHose:removeHoseVehicle(self)
    end
end

function DynamicHose:readStream(streamId, connection)
end

function DynamicHose:writeStream(streamId, connection)
end

function DynamicHose:getSaveAttributesAndNodes(nodeIdent)
    local isAttached = false

    for hoseType, attached in pairs(self.hoseIsAttached) do
        if attached[1] then
            isAttached = true
            break
        end
    end

    return 'hoseIsAttached="' .. tostring(isAttached) .. '"'
end

function DynamicHose:mouseEvent(posX, posY, isDown, isUp, button)
end

function DynamicHose:keyEvent(unicode, sym, modifier, isDown)
end

function DynamicHose:update(dt)
    if self:getIsActive() then
        if self.isServer then
            if self.airBrakeEnabled and self.attacherVehicle ~= nil then
                if self.onBrake ~= nil and self.onReleaseBrake ~= nil then
                    if not self:getIsHoseAttached("air") and not self.airBrakeActive then
                        self:onBrake(1, true)
                        self.airBrakeActive = true
                    end
                end
            end
        end
    end
end

function DynamicHose:updateTick(dt)
    if self.isServer then
        if self.electricEnabled then
            if self:getIsHoseAttached("electric") then
                if (self.updateCurrentLightState["LIGHTS"] ~= nil or self.updateCurrentLightState["BEACONS"] ~= nil or self.updateCurrentLightState["TURN_LIGHT"] ~= nil or self.updateCurrentLightState["REVERSE"] ~= nil) then
                    self:updateLightStates(true)
                    self.updateCurrentLightState["LIGHTS"] = nil
                    self.updateCurrentLightState["BEACONS"] = nil
                    self.updateCurrentLightState["TURN_LIGHT"] = nil
                    self.updateCurrentLightState["REVERSE"] = nil
                end
            end
        end
    end
end

function DynamicHose:draw()
end

function DynamicHose:onAttach(vehicle, jointDescIndex)
    if not vehicle.dynamicHoseSupport then
        for i, set in pairs(self.hoseSets) do
            self:setHoseVisible(set, false, true)
        end
    else
        if not g_currentMission.dynamicHoseIsManual or (not self.firstTimeRun and not self.hoseIsPendingDetach) then
            self:attachDynamicHose(vehicle, jointDescIndex, true)
        else
            -- manual attach, stop the tool from functioning.
            self:updateMovingToolCouplings(false)

            -- Confirm that detach hose is visible, need newer version of manual attach
            if not self.firstTimeRun then
                for i, set in pairs(self.hoseSets) do
                    self:setHoseVisible(set, false, true)
                end
            end
        end

        self.hoseIsPendingDetach = nil
    end
end

function DynamicHose:onDetach(vehicle)
    if not vehicle.dynamicHoseSupport then
        for i, set in pairs(self.hoseSets) do
            self:setHoseVisible(set, false, true)
        end
    else
        if not g_currentMission.dynamicHoseIsManual then
            self:detachDynamicHose(true)
        end

        self:updateMovingToolCouplings(true)
    end
end

function DynamicHose:attachDynamicHose(vehicle, jointDescIndex, noEventSend)
    local setId = vehicle.attacherJoints[jointDescIndex].dynamicHoseIndice

    if setId ~= nil then
        local joint = self.attacherJoint
        local refs = vehicle:getDynamicRefSet(setId)
        local hoses = self.hoseSets[joint.dynamicHoseIndice]

        joint.dynamicHoseIsAttached = true

        for hoseType, allowed in pairs(g_currentMission.dynamicHoseTypes) do
            if allowed and vehicle:canWeAttachHose(hoseType) then
                local selectedRefs = refs[hoseType]
                local selectedHoses = hoses[hoseType]

                if selectedHoses ~= nil then
                    for i, v in pairs(selectedHoses) do
                        local part = self.movingParts[v.movingPartIndice]
                        local attachHose = selectedRefs ~= nil and selectedRefs[i] ~= nil

                        if attachHose then
                            self:setHoseAttached(hoseType, true, true)
                            part.referenceFrame = selectedRefs[i]

                            if g_currentMission.dynamicHoseIsManual ~= nil and g_currentMission.dynamicHoseIsManual then
                                Cylindered.setDirty(self, part)
                            end
                        else
                            self:setHoseAttached(hoseType, true, false) -- not all hoses are attached, keep it functioning. Make it an toggleable setting.
                        end

                        if v.attachedHose ~= nil then
                            setVisibility(v.attachedHose, attachHose)
                        end
                        if v.detachedHose ~= nil then
                            setVisibility(v.detachedHose, not attachHose)
                        end
                    end
                end
            end
        end

        self:updateLightStates(true, true)
        self:updateMovingToolCouplings(true)
        self:updateHydraulicInputs()

        DynamicHoseEvent.sendEvent(self, DynamicHoseEvent.ATTACH_HOSE, vehicle, jointDescIndex, noEventSend)
    end
end

function DynamicHose:detachDynamicHose(noEventSend)
    local joint = self.attacherJoint

    if joint ~= nil then
        if joint.dynamicHoseIsAttached ~= nil and joint.dynamicHoseIsAttached then
            self:updateLightStates(false, true)

            local hoses = self.hoseSets[joint.dynamicHoseIndice]
            joint.dynamicHoseIsAttached = false

            for hoseType, allowed in pairs(g_currentMission.dynamicHoseTypes) do
                self:setHoseAttached(hoseType, false, false)
            end

            self:setHoseVisible(hoses, false, true, true)
            self:updateMovingToolCouplings(true)
            self:updateHydraulicInputs()

            DynamicHoseEvent.sendEvent(self, DynamicHoseEvent.DETACH_HOSE, nil, nil, noEventSend)
        end
    end
end

function DynamicHose:setHoseVisible(types, attachState, detachState, cleanUpDetach)
    for i, hoses in pairs(types) do
        if i ~= "movingToolCouplings" then
            for k, h in pairs(hoses) do
                if h.attachedHose ~= nil then
                    setVisibility(h.attachedHose, attachState)
                end
                if h.detachedHose ~= nil then
                    setVisibility(h.detachedHose, detachState)
                end

                -- reduce table looping..
                if cleanUpDetach ~= nil and cleanUpDetach then
                    self.movingParts[h.movingPartIndice].referenceFrame = self.movingParts[h.movingPartIndice].oldRefFrame
                end
            end
        end
    end
end

function DynamicHose:setHoseAttached(hoseType, state, realState)
    if self.hoseIsAttached[hoseType] ~= nil then
        self.hoseIsAttached[hoseType][1] = state
        self.hoseIsAttached[hoseType][2] = realState
    end
end

function DynamicHose:getIsHoseAttached(hoseType)
    if self.attacherVehicle ~= nil then
        if not self.attacherVehicle.dynamicHoseSupport then
            return true -- Vehicle don't support hoses, make it work anyway
        else
            if g_currentMission.dynamicHose ~= nil then -- GameExtension is activated
                if not g_currentMission.dynamicHose:getHoseSetting("alwaysFunction") then
                    if g_currentMission.dynamicHose:getHoseSetting("missingOneHoseFunctionAnyway") then
                        return self.hoseIsAttached[hoseType][1]
                    else
                        return self.hoseIsAttached[hoseType][2] -- real state
                    end
                else
                    return true
                end
            else
                return self.hoseIsAttached[hoseType][1] -- We could just return true if tractor is missing an ref type etc
            end
        end
    end

    return false
end

function DynamicHose:gameExtensionDifficultyUpdate(isHardLevel)
    if self.electricEnabled then
        if isHardLevel then
            -- Update light states before "missingOneHoseFunctionAnyway" is set to false
            if not self.hoseIsAttached["electric"][2] then
                self:updateLightStates(false, true)
            end
        else
            -- if self.hoseIsAttached["electric"][1] then
            self:updateLightStates(true, true)
            -- end
        end
    end
end



-- Hydraulics
function DynamicHose:getIsFoldAllowed(oldFunc)
    if self:getIsHoseAttached("hydraulic") then
        if oldFunc ~= nil then
            return oldFunc(self)
        end
    end

    return false
end

function DynamicHose:setJointMoveDown(oldFunc, jointDescIndex, moveDown, noEventSend)
    if self:getIsHoseAttached("hydraulic") then
        if oldFunc ~= nil then
            oldFunc(self, jointDescIndex, moveDown, noEventSend)
        end
    else
        if g_i18n:hasText("COUPLING_ERROR") and self:getIsActiveForInput() then
            g_currentMission:showBlinkingWarning(g_i18n:getText("COUPLING_ERROR"), 1000)
        end
    end
end

function DynamicHose:updateMovingToolCouplings(active)
    for key, t in ipairs(self.hoseSets) do
        for id, v in ipairs(t.movingToolCouplings) do
            local tool = self.movingTools[v]
            if tool.axisActionIndex ~= nil then
                tool.isActive = active

                if not active then
                    tool.lastRotSpeed = 0
                    tool.lastTransSpeed = 0
                end
            end
        end
    end
end

function DynamicHose:updateHydraulicInputs()
    if SpecializationUtil.hasSpecialization(Pickup, self.specializations) then
        if not self:getIsHoseAttached("hydraulic") then
            if self.pickupAnimationName ~= "" then
                if self.backupPickupAnimationName == nil then
                    self.backupPickupAnimationName = self.pickupAnimationName
                end

                self.pickupAnimationName = ''
            end
        else
            if self.backupPickupAnimationName ~= nil then
                self.pickupAnimationName = self.backupPickupAnimationName
            end
        end
    end
end

-- Electrics
function DynamicHose:updatedSetLightsTypesMask(oldFunc, state, force, noEventSend)
    if self:getIsHoseAttached("electric") then
        if oldFunc ~= nil then
            return oldFunc(self, state, force, noEventSend)
        end
    else
        self.updateCurrentLightState["LIGHTS"] = state > 0

        return false
    end
end

function DynamicHose:updatedSetBeaconLightsVisibility(oldFunc, state, force, noEventSend)
    if self:getIsHoseAttached("electric") then
        if oldFunc ~= nil then
            return oldFunc(self, state, force, noEventSend)
        end
    else
        self.updateCurrentLightState["BEACONS"] = state

        return false
    end
end

function DynamicHose:updatedSetTurnLightState(oldFunc, state, force, noEventSend)
    if self:getIsHoseAttached("electric") then
        if oldFunc ~= nil then
            return oldFunc(self, state, force, noEventSend)
        end
    else
        self.updateCurrentLightState["TURN_LIGHT"] = state

        return false
    end
end

function DynamicHose:updatedSetBrakeLightsVisibility(oldFunc, state, noEventSend)
    if self:getIsHoseAttached("electric") then
        if oldFunc ~= nil then
            return oldFunc(self, state, noEventSend)
        end
    else
        return false
    end
end

function DynamicHose:updatedSetReverseLightsVisibility(oldFunc, state)
    if self:getIsHoseAttached("electric") then
        if oldFunc ~= nil then
            return oldFunc(self, state)
        end
    else
        self.updateCurrentLightState["REVERSE"] = state

        return false
    end
end

function DynamicHose:updateLightStates(synch, event)
    if self.electricEnabled then
        local rootAttacherVehicle = self.attacherVehicle -- self:getRootAttacherVehicle()

        if synch and self:getIsHoseAttached("electric") and rootAttacherVehicle ~= nil then
            self:setLightsTypesMask(rootAttacherVehicle.lightsTypesMask, false, event)
            self:setTurnLightState(rootAttacherVehicle.turnLightState, false, event)
            self:setBeaconLightsVisibility(rootAttacherVehicle.beaconLightsActive, false, event)
            self:setReverseLightsVisibility(rootAttacherVehicle.reverseLightsVisibility)
        else
            self:setLightsTypesMask(0, true, event)
            self:setTurnLightState(0, true, event)
            self:setBrakeLightsVisibility(false, event)
            self:setBeaconLightsVisibility(false, true, event)
            self:setReverseLightsVisibility(false)
        end
    end
end



-- Air
function DynamicHose:updatedOnBrake(oldFunc, brakePedal, force)
    if not self:getIsHoseAttached("air") then
        brakePedal = 1
        -- Possible problem here would be that the brake lights turn on..
    end

    oldFunc(self, brakePedal, force)
end

function DynamicHose:updatedOnReleaseBrake(oldFunc)
    if self:getIsHoseAttached("air") then
        self.airBrakeActive = false
        oldFunc(self)
    end
end

function DynamicHose:loadExtraAttacherJoints(oldFunc, xmlFile, key, inputAttacherJoint, index)
    if oldFunc ~= nil then
        if not oldFunc(self, xmlFile, key, inputAttacherJoint, index) then
            return false
        end
    end

    inputAttacherJoint.dynamicHoseIsAttached = false
    inputAttacherJoint.dynamicHoseIndice = Utils.getNoNil(getXMLInt(xmlFile, key .. "#dynamicHoseIndice"), 0) + 1

    return true
end



-- Event
DynamicHoseEvent = {}

DynamicHoseEvent.ATTACH_HOSE = 0
DynamicHoseEvent.DETACH_HOSE = 1
DynamicHoseEvent.NUM_BITS = 1

DynamicHoseEvent_mt = Class(DynamicHoseEvent, Event)

InitEventClass(DynamicHoseEvent, "DynamicHoseEvent")

function DynamicHoseEvent:emptyNew()
    local self = Event:new(DynamicHoseEvent_mt)
    return self
end

function DynamicHoseEvent:new(object, eventType, vehicle, jointDescIndex)
    local self = DynamicHoseEvent:emptyNew()

    self.object = object
    self.eventType = eventType
    self.vehicle = vehicle
    self.jointDescIndex = jointDescIndex

    return self
end

function DynamicHoseEvent:readStream(streamId, connection)
    self.object = readNetworkNodeObject(streamId)
    self.eventType = streamReadUIntN(streamId, DynamicHoseEvent.NUM_BITS)

    if self.eventType == DynamicHoseEvent.ATTACH_HOSE then
        self.vehicle = readNetworkNodeObject(streamId)
        self.jointDescIndex = streamReadInt8(streamId)
    end

    self:run(connection)
end

function DynamicHoseEvent:writeStream(streamId, connection)
    writeNetworkNodeObject(streamId, self.object)
    streamWriteUIntN(streamId, self.eventType, DynamicHoseEvent.NUM_BITS)

    if self.eventType == DynamicHoseEvent.ATTACH_HOSE then
        writeNetworkNodeObject(streamId, self.vehicle)
        streamWriteInt8(streamId, self.jointDescIndex)
    end
end

function DynamicHoseEvent:run(connection)
    if self.eventType == DynamicHoseEvent.ATTACH_HOSE then
        self.object:attachDynamicHose(self.vehicle, self.jointDescIndex, true)
    elseif self.eventType == DynamicHoseEvent.DETACH_HOSE then
        self.object:detachDynamicHose(true)
    end

    if not connection:getIsServer() then
        g_server:broadcastEvent(DynamicHoseEvent:new(self.object, self.eventType, self.vehicle, self.jointDescIndex), nil, connection, self.object)
    end
end

function DynamicHoseEvent.sendEvent(object, eventType, vehicle, jointDescIndex, noEventSend)
    if noEventSend == nil or noEventSend == false then
        if g_server ~= nil then
            g_server:broadcastEvent(DynamicHoseEvent:new(object, eventType, vehicle, jointDescIndex), nil, nil, object)
        else
            g_client:getServerConnection():sendEvent(DynamicHoseEvent:new(object, eventType, vehicle, jointDescIndex))
        end
    end
end