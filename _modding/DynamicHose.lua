--
-- DynamicHose
--
-- Authors: Xentro (Marcus@Xentro.se) and Wopster
-- Description: The hose specialization for the DynamicHoses
-- History:
--      - v1.0 - 2017-01-08 - Initial implementation
--      - v1.1 - 2017-02-15 - Pickup override by Wopster
--      - v1.2 - 2017-10-25 - Refactor by Wopster
--
--[[
<dynamicHose>
	<set toolIndices="0">
		<hose type="hydraulic" attached="0>0" detached="0>1" lastHoseIKNode="0>2"/>
	</set>
</dynamicHose>
]] --

DynamicHose = {}

DynamicHose.TYPE_HYDRAULIC = 'hydraulic'
DynamicHose.TYPE_ELECTRIC = 'electric'
DynamicHose.TYPE_AIR = 'air'
DynamicHose.TYPE_ISOBUS = 'isobus'
DynamicHose.WARNING_TIME = 1000 -- ms

DynamicHose.TYPES = {
    [DynamicHose.TYPE_HYDRAULIC] = true,
    [DynamicHose.TYPE_ELECTRIC] = true,
    [DynamicHose.TYPE_AIR] = true,
    [DynamicHose.TYPE_ISOBUS] = true
}

---
-- @param specializations
--
function DynamicHose.prerequisitesPresent(specializations)
    if not SpecializationUtil.hasSpecialization(Cylindered, specializations) then
        print("Warning: Specialization DynamicHose needs the specialization Cylindered.")

        return false
    end

    return true
end

---
-- @param savegame
--
function DynamicHose:preLoad(savegame)
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
    self.enableLimitationsByType = DynamicHose.enableLimitationsByType

    -- Use to override the attaching/detaching of hoses.
    -- g_currentMission.dynamicHoseIsManual = true

    self.dynamicHoseSupport = true

    self.hydraulicEnabled = false
    self.electricEnabled = false
    self.airBrakeEnabled = false
    self.isobusEnabled = false

    -- Game extension
    if g_currentMission.dynamicHose ~= nil then
        g_currentMission.dynamicHose:addHoseVehicle(self)
    end
end

---
-- @param savegame
--
function DynamicHose:load(savegame)
    self.hoseIsAttached = {} -- Only add hoseTypes we support for this vehicle.
    self.hoseSets = {}

    local i = 0

    while true do
        local key = ('vehicle.dynamicHose.set(%d)'):format(i)

        if not hasXMLProperty(self.xmlFile, key) then
            break
        end

        local set = {}
        local r = 0

        while true do
            local entryKey = ('%s.hose(%d)'):format(key, r)

            if not hasXMLProperty(self.xmlFile, entryKey) then
                break
            end
			
            local type = Utils.getNoNil(getXMLString(self.xmlFile, entryKey .. '#type'), DynamicHose.TYPE_HYDRAULIC):lower()

            if DynamicHose.TYPES[type] then
                local attachedHoseNode = Utils.indexToObject(self.components, getXMLString(self.xmlFile, entryKey .. '#attached'))
                local detachedHoseNode = Utils.indexToObject(self.components, getXMLString(self.xmlFile, entryKey .. '#detached'))
                local ikNode = Utils.indexToObject(self.components, getXMLString(self.xmlFile, entryKey .. '#lastHoseIKNode'))

                if ikNode ~= nil and attachedHoseNode ~= nil and detachedHoseNode ~= nil then
                    if set[type] == nil then
                        set[type] = {}
                    end

                    self.hoseIsAttached[type] = { state = false, realState = false }

                    self:enableLimitationsByType(type)

                    if attachedHoseNode ~= nil and getVisibility(attachedHoseNode) then
                        setVisibility(attachedHoseNode, false)
                    end

                    if detachedHoseNode ~= nil and not getVisibility(detachedHoseNode) then
                        setVisibility(detachedHoseNode, true)
                    end

                    table.insert(set[type], {
                        attachedHose = attachedHoseNode,
                        detachedHose = detachedHoseNode,
                        ikNode = ikNode
                    })
                else
                    print("DynamicHose - Error: lastHoseIKNode is nil in " .. self.configFileName)
                    break
                end
            end

            r = r + 1
        end

        if set ~= nil and r > 0 then
            set.movingToolCouplings = {}

            local toolIds = Utils.getVectorNFromString(getXMLString(self.xmlFile, key .. '#toolIndices'))

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

    -- Make sure we don't have invalid indices
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

        self.updateCurrentLightStates = false
    end

    if self.airBrakeEnabled then
        self.onBrake = Utils.prependedFunction(self.onBrake, DynamicHose.updatedOnBrake)
        self.onReleaseBrake = Utils.overwrittenFunction(self.onReleaseBrake, DynamicHose.updatedOnReleaseBrake)

        self.airBrakeActive = false
    end

    if self.isobusEnabled then
        self.getFillLevelInformation = Utils.overwrittenFunction(self.getFillLevelInformation, DynamicHose.getFillLevelInformation)
    end
end

---
-- @param type
--
function DynamicHose:enableLimitationsByType(type)
    if type == DynamicHose.TYPE_HYDRAULIC and not self.hydraulicEnabled then
        self.hydraulicEnabled = true
    elseif type == DynamicHose.TYPE_ELECTRIC and not self.electricEnabled then
        self.electricEnabled = true
    elseif type == DynamicHose.TYPE_AIR and not self.airBrakeEnabled then
        self.airBrakeEnabled = true
    elseif type == DynamicHose.TYPE_ISOBUS and not self.isobusEnabled then
        self.isobusEnabled = true
    end
end

---
-- @param savegame
--
function DynamicHose:postLoad(savegame)
    -- setup an movingPart for the IK node, should reduce the problem to find the correct indice for it...
    for key, value in ipairs(self.hoseSets) do
        for hoseType, allowed in pairs(DynamicHose.TYPES) do
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

---
--
function DynamicHose:delete()
    if g_currentMission.dynamicHose ~= nil then
        g_currentMission.dynamicHose:removeHoseVehicle(self)
    end
end

---
-- @param nodeIdent
--
function DynamicHose:getSaveAttributesAndNodes(nodeIdent)
    local isAttached = false

    for hoseType, hose in pairs(self.hoseIsAttached) do
        if hose.state then
            isAttached = true
            break
        end
    end

    return 'hoseIsAttached="' .. tostring(isAttached) .. '"'
end

function DynamicHose:mouseEvent(...)
end

function DynamicHose:keyEvent(...)
end

---
-- @param dt
--
function DynamicHose:update(dt)
    if self.isServer and self:getIsActive() then
        if self.airBrakeEnabled and self.attacherVehicle ~= nil then
            if self.onBrake ~= nil and self.onReleaseBrake ~= nil then
                if not self:getIsHoseAttached(DynamicHose.TYPE_AIR) and not self.airBrakeActive then
                    self:onBrake(1, true)
                    self.airBrakeActive = true
                end
            end
        end
    end
end

---
-- @param dt
--
function DynamicHose:updateTick(dt)
    if self.isServer and self.electricEnabled then
        if self:getIsHoseAttached(DynamicHose.TYPE_ELECTRIC) then
            if self.updateCurrentLightStates then
                self:updateLightStates(true)
                self.updateCurrentLightStates = false
            end
        end
    end
end

---
--
function DynamicHose:draw()
end

---
-- @param vehicle
-- @param jointDescIndex
--
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

---
-- @param vehicle
-- @param jointDescIndex
--
function DynamicHose:onDetach(vehicle, jointDescIndex)
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

---
-- @param vehicle
-- @param jointDescIndex
-- @param noEventSend
--
function DynamicHose:attachDynamicHose(vehicle, jointDescIndex, noEventSend)
    local setId = vehicle.attacherJoints[jointDescIndex].dynamicHoseIndice

    if setId ~= nil then
        local joint = self.attacherJoint
        local refs = vehicle:getDynamicRefSet(setId)
        local hoses = self.hoseSets[joint.dynamicHoseIndice]

        joint.dynamicHoseIsAttached = true

        for hoseType, allowed in pairs(DynamicHose.TYPES) do
            if allowed and (vehicle.getCanAttachHose ~= nil and vehicle:getCanAttachHose(hoseType)) or (vehicle.canWeAttachHose ~= nil and vehicle:canWeAttachHose(hoseType)) then				
				local selectedRefs = refs[hoseType]
                local selectedHoses = hoses[hoseType]

                if selectedHoses ~= nil then
                    for i, v in pairs(selectedHoses) do
                        local part = self.movingParts[v.movingPartIndice]
                        local attachHose = selectedRefs ~= nil and selectedRefs[i] ~= nil

                        if attachHose then
                            self:setHoseAttached(hoseType, true, true)
							
							local node = selectedRefs[i]
							if type(selectedRefs[i]) == "table" then
								node = selectedRefs[i].node
							end
							
                            part.referenceFrame = node

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
				
		if vehicle.setDynamicRefSetObjectChanges ~= nil then
			vehicle:setDynamicRefSetObjectChanges(true, setId)
		end

        self:updateLightStates(true, true)
        self:updateMovingToolCouplings(true)
        self:updateHydraulicInputs()

        DynamicHoseEvent.sendEvent(self, DynamicHoseEvent.ATTACH_HOSE, vehicle, jointDescIndex, noEventSend)
    end
end

---
-- @param noEventSend
--
function DynamicHose:detachDynamicHose(noEventSend)
    local joint = self.attacherJoint

    if joint ~= nil then
        if joint.dynamicHoseIsAttached ~= nil and joint.dynamicHoseIsAttached then
            self:updateLightStates(false, true)

            local hoses = self.hoseSets[joint.dynamicHoseIndice]
            joint.dynamicHoseIsAttached = false

            for hoseType, allowed in pairs(DynamicHose.TYPES) do
                self:setHoseAttached(hoseType, false, false)
            end

            self:setHoseVisible(hoses, false, true, true)
            self:updateMovingToolCouplings(true)
            self:updateHydraulicInputs()

            if self.attacherVehicle ~= nil then
                local implement = self.attacherVehicle:getImplementByObject(self)

                if self.attacherVehicle.resetDynamicRefSetObjectChanges ~= nil then
                    self.attacherVehicle:resetDynamicRefSetObjectChanges(self.attacherVehicle.attacherJoints[implement.jointDescIndex].dynamicHoseIndice)
                end
            end

            DynamicHoseEvent.sendEvent(self, DynamicHoseEvent.DETACH_HOSE, nil, nil, noEventSend)
        end
    end
end

---
-- @param types
-- @param attachState
-- @param detachState
-- @param cleanUpDetach
--
function DynamicHose:setHoseVisible(types, attachState, detachState, cleanUpDetach)
    for type, hoses in pairs(types) do
        if DynamicHose.TYPES[type] then
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

---
-- @param hoseType
-- @param state
-- @param realState
--
function DynamicHose:setHoseAttached(hoseType, state, realState)
    if self.hoseIsAttached[hoseType] ~= nil then
        self.hoseIsAttached[hoseType].state = state
        self.hoseIsAttached[hoseType].realState = realState
    end
end

---
-- @param hoseType
--
function DynamicHose:getIsHoseAttached(hoseType)
    if self.attacherVehicle ~= nil then
        if not self.attacherVehicle.dynamicHoseSupport then
            return true -- Vehicle don't support hoses, make it work anyway
        else
            if g_currentMission.dynamicHose ~= nil then -- GameExtension is activated
                if not g_currentMission.dynamicHose:getHoseSetting('alwaysFunction') then
                    if g_currentMission.dynamicHose:getHoseSetting('missingOneHoseFunctionAnyway') then
                        return self.hoseIsAttached[hoseType].state
                    else
                        return self.hoseIsAttached[hoseType].realState -- real state
                    end
                else
                    return true
                end
            else
                return self.hoseIsAttached[hoseType].state -- We could just return true if tractor is missing an ref type etc
            end
        end
    end

    return false
end

---
-- @param isHardLevel
--
function DynamicHose:gameExtensionDifficultyUpdate(isHardLevel)
    if self.electricEnabled then
        if isHardLevel then
            -- Update light states before "missingOneHoseFunctionAnyway" is set to false
            if not self.hoseIsAttached[DynamicHose.TYPE_ELECTRIC].realState then
                self:updateLightStates(false, true)
            end
        else
            self:updateLightStates(true, true)
        end
    end
end

-- Hydraulics
---
-- @param superFunc
-- @param onAiTurnOn
--
function DynamicHose:getIsFoldAllowed(superFunc, onAiTurnOn)
    if not self:getIsHoseAttached(DynamicHose.TYPE_HYDRAULIC) then
        return false
    end

    return superFunc(self, onAiTurnOn)
end

---
-- @param superFunc
-- @param jointDescIndex
-- @param moveDown
-- @param noEventSend
--
function DynamicHose:setJointMoveDown(superFunc, jointDescIndex, moveDown, noEventSend)
    if not self:getIsHoseAttached(DynamicHose.TYPE_HYDRAULIC) then
        if g_i18n:hasText("COUPLING_ERROR") and self:getIsActiveForInput() then
            g_currentMission:showBlinkingWarning(g_i18n:getText("COUPLING_ERROR"), DynamicHose.WARNING_TIME)
        end

        return false
    end

    return superFunc(self, jointDescIndex, moveDown, noEventSend)
end

---
-- @param active
--
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

---
--
function DynamicHose:updateHydraulicInputs()
    if SpecializationUtil.hasSpecialization(Pickup, self.specializations) then
        if not self:getIsHoseAttached(DynamicHose.TYPE_HYDRAULIC) then
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
---
-- @param superFunc
-- @param state
-- @param force
-- @param noEventSend
--
function DynamicHose:updatedSetLightsTypesMask(superFunc, state, force, noEventSend)
    if not self:getIsHoseAttached(DynamicHose.TYPE_ELECTRIC) then
        self.updateCurrentLightStates = state > 0

        return false
    end

    return superFunc(self, state, force, noEventSend)
end

---
-- @param superFunc
-- @param visibility
-- @param force
-- @param noEventSend
--
function DynamicHose:updatedSetBeaconLightsVisibility(superFunc, visibility, force, noEventSend)
    if not self:getIsHoseAttached(DynamicHose.TYPE_ELECTRIC) then
        self.updateCurrentLightStates = visibility
        return false
    end

    return superFunc(self, visibility, force, noEventSend)
end

---
-- @param superFunc
-- @param visibility
-- @param force
-- @param noEventSend
--
function DynamicHose:updatedSetTurnLightState(superFunc, visibility, force, noEventSend)
    if not self:getIsHoseAttached(DynamicHose.TYPE_ELECTRIC) then
        self.updateCurrentLightStates = visibility

        return false
    end

    return superFunc(self, visibility, force, noEventSend)
end

---
-- @param superFunc
-- @param visibility
--
function DynamicHose:updatedSetBrakeLightsVisibility(superFunc, visibility)
    if not self:getIsHoseAttached(DynamicHose.TYPE_ELECTRIC) then
        return false
    end

    return superFunc(self, visibility)
end

---
-- @param superFunc
-- @param visibility
--
function DynamicHose:updatedSetReverseLightsVisibility(superFunc, visibility)
    if not self:getIsHoseAttached(DynamicHose.TYPE_ELECTRIC) then
        self.updateCurrentLightStates = visibility

        return false
    end

    return superFunc(self, visibility)
end

---
-- @param synch
-- @param event
--
function DynamicHose:updateLightStates(synch, event)
    if self.electricEnabled then
        local rootAttacherVehicle = self.attacherVehicle -- self:getRootAttacherVehicle()

        if synch and self:getIsHoseAttached(DynamicHose.TYPE_ELECTRIC) and rootAttacherVehicle ~= nil then
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
---
-- @param superFunc
-- @param brakePedal
-- @param force
--
function DynamicHose:updatedOnBrake(superFunc, brakePedal, force)
    if not self:getIsHoseAttached(DynamicHose.TYPE_AIR) then
        brakePedal = 1
        -- Possible problem here would be that the brake lights turn on..
    end
end

---
-- @param superFunc
--
function DynamicHose:updatedOnReleaseBrake(superFunc)
    if self:getIsHoseAttached(DynamicHose.TYPE_AIR) then
        self.airBrakeActive = false
        superFunc(self)
    end
end

-- ISO Bus
---
-- @param superFunc
-- @param fillLevelInformations
--
function DynamicHose:getFillLevelInformation(superFunc, fillLevelInformations)
    if not self:getIsHoseAttached(DynamicHose.TYPE_ISOBUS) then
        return fillLevelInformations
    end

    return superFunc(self, fillLevelInformations)
end

---
-- @param superFunc
-- @param xmlFile
-- @param key
-- @param inputAttacherJoint
-- @param index
--
function DynamicHose:loadExtraAttacherJoints(superFunc, xmlFile, key, inputAttacherJoint, index)
    if superFunc ~= nil then
        if not superFunc(self, xmlFile, key, inputAttacherJoint, index) then
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

InitEventClass(DynamicHoseEvent, 'DynamicHoseEvent')

function DynamicHoseEvent:emptyNew()
    local event = Event:new(DynamicHoseEvent_mt)
    return event
end

function DynamicHoseEvent:new(object, eventType, vehicle, jointDescIndex)
    local event = DynamicHoseEvent:emptyNew()

    event.object = object
    event.eventType = eventType
    event.vehicle = vehicle
    event.jointDescIndex = jointDescIndex

    return event
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