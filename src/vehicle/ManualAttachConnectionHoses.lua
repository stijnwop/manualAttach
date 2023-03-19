--
-- ManualAttachConnectionHoses
--
-- Author: Wopster
-- Description: ConnectionHoses extension for Manual Attach.
-- Name: ManualAttachConnectionHoses
-- Hide: yes
--
-- Copyright (c) Wopster, 2021

---@class ManualAttachConnectionHoses
ManualAttachConnectionHoses = {}
ManualAttachConnectionHoses.TYPE_ELECTRIC = "electric"
ManualAttachConnectionHoses.TYPE_HYDRAULIC = "hydraulic"
ManualAttachConnectionHoses.TYPE_AIR = "air"
ManualAttachConnectionHoses.TYPE_ISOBUS = "isobus"

ManualAttachConnectionHoses.TYPES = {
    [ManualAttachConnectionHoses.TYPE_ELECTRIC] = 1,
    [ManualAttachConnectionHoses.TYPE_HYDRAULIC] = 2,
    [ManualAttachConnectionHoses.TYPE_AIR] = 2,
    [ManualAttachConnectionHoses.TYPE_ISOBUS] = 3,
}

ManualAttachConnectionHoses.TYPES_TO_INTERNAL = {
    [ManualAttachConnectionHoses.TYPE_HYDRAULIC] = {
        ["HYDRAULICIN"] = true,
        ["HYDRAULICOUT"] = true
    },
    [ManualAttachConnectionHoses.TYPE_AIR] = {
        ["AIRDOUBLERED"] = true,
        ["AIRDOUBLEYELLOW"] = true
    },
    [ManualAttachConnectionHoses.TYPE_ELECTRIC] = {
        ["ELECTRIC"] = true
    },
    [ManualAttachConnectionHoses.TYPE_ISOBUS] = {
        ["ISOBUS"] = true
    }
}

function ManualAttachConnectionHoses.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(ConnectionHoses, specializations)
end

function ManualAttachConnectionHoses.initSpecialization()
    local schemaSavegame = Vehicle.xmlSchemaSavegame
    schemaSavegame:register(XMLValueType.BOOL, ("vehicles.vehicle(?).%s.manualAttachConnectionHoses#hasAttachedConnectionHoses"):format(g_manualAttachModName), "State of initial connection hoses")
end

function ManualAttachConnectionHoses.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "disconnectHoses", ManualAttachConnectionHoses.disconnectHoses)
    SpecializationUtil.registerFunction(vehicleType, "setUpdateLightsState", ManualAttachConnectionHoses.setUpdateLightsState)
    SpecializationUtil.registerFunction(vehicleType, "toggleLightStates", ManualAttachConnectionHoses.toggleLightStates)
    SpecializationUtil.registerFunction(vehicleType, "isHoseAttached", ManualAttachConnectionHoses.isHoseAttached)
    SpecializationUtil.registerFunction(vehicleType, "hasAttachedHoses", ManualAttachConnectionHoses.hasAttachedHoses)
    SpecializationUtil.registerFunction(vehicleType, "hasAttachedHosesOfType", ManualAttachConnectionHoses.hasAttachedHosesOfType)
    SpecializationUtil.registerFunction(vehicleType, "playHoseAttachSound", ManualAttachConnectionHoses.playHoseAttachSound)
end

function ManualAttachConnectionHoses.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "connectHosesToAttacherVehicle", ManualAttachConnectionHoses.inj_connectHosesToAttacherVehicle)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setLightsTypesMask", ManualAttachConnectionHoses.inj_setLightsTypesMask)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setBeaconLightsVisibility", ManualAttachConnectionHoses.inj_setBeaconLightsVisibility)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setTurnLightState", ManualAttachConnectionHoses.inj_setTurnLightState)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setBrakeLightsVisibility", ManualAttachConnectionHoses.inj_setBrakeLightsVisibility)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setReverseLightsVisibility", ManualAttachConnectionHoses.inj_setReverseLightsVisibility)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsFoldAllowed", ManualAttachConnectionHoses.inj_getIsFoldAllowed)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsMovingToolActive", ManualAttachConnectionHoses.inj_getIsMovingToolActive)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanBeTurnedOn", ManualAttachConnectionHoses.inj_getCanBeTurnedOn)
    -- Todo: bugs on planters..
    --SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsFoldMiddleAllowed", ManualAttachConnectionHoses.inj_getIsFoldMiddleAllowed)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "canFoldRidgeMarker", ManualAttachConnectionHoses.inj_canFoldRidgeMarker)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanDischargeToObject", ManualAttachConnectionHoses.inj_getCanDischargeToObject)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanDischargeToGround", ManualAttachConnectionHoses.inj_getCanDischargeToGround)
end

function ManualAttachConnectionHoses.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", ManualAttachConnectionHoses)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", ManualAttachConnectionHoses)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", ManualAttachConnectionHoses)
    SpecializationUtil.registerEventListener(vehicleType, "onPostAttach", ManualAttachConnectionHoses)
    SpecializationUtil.registerEventListener(vehicleType, "onPostUpdateTick", ManualAttachConnectionHoses)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", ManualAttachConnectionHoses)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", ManualAttachConnectionHoses)
end

function ManualAttachConnectionHoses:onLoad(savegame)
    self.spec_manualAttachConnectionHoses = ManualAttachUtil.getSpecTable(self, "manualAttachConnectionHoses")
    local spec = self.spec_manualAttachConnectionHoses

    spec.hoseStateChanged = false
    spec.attachedHosesByType = {
        [ManualAttachConnectionHoses.TYPE_ELECTRIC] = false,
        [ManualAttachConnectionHoses.TYPE_AIR] = false,
        [ManualAttachConnectionHoses.TYPE_HYDRAULIC] = false
    }

    if self.isClient then
        spec.samples = {}

        local sampleAttach = g_soundManager:loadSampleFromXML(self.xmlFile, "vehicle.attacherJoints.sounds", "attachHoses", self.baseDirectory, self.components, 1, AudioGroup.VEHICLE, self.i3dMappings, self)
        if sampleAttach == nil then
            sampleAttach = g_soundManager:cloneSample(g_currentMission.manualAttach.samples.hosesAttach, self.components[1].node, self)
        end

        spec.samples.attach = sampleAttach
    end
end

function ManualAttachConnectionHoses:onPostLoad(savegame)
    local spec = self.spec_manualAttachConnectionHoses

    spec.doLightsUpdate = false
    spec.isBlockingInitialHoseDetach = false -- always block detach because we don't have attached hoses at first load.

    if savegame ~= nil then
        local key = savegame.key .. "." .. g_currentMission.manualAttach.modName
        spec.isBlockingInitialHoseDetach = savegame.xmlFile:getValue(key .. ".manualAttachConnectionHoses#hasAttachedConnectionHoses") or false
    end
end

function ManualAttachConnectionHoses:onDelete()
    local spec = self.spec_manualAttachConnectionHoses

    if self.isClient then
        g_soundManager:deleteSample(spec.samples.attach)
    end
end

---Called on client side on join
---@param streamId number
---@param connection number
function ManualAttachConnectionHoses:onReadStream(streamId, connection)
    if streamReadBool(streamId) then
        local hasAttachedConnectionHoses = streamReadBool(streamId)
        if hasAttachedConnectionHoses then
            local attacherVehicle = self:getAttacherVehicle()
            if attacherVehicle ~= nil then
                local implement = attacherVehicle:getImplementByObject(self)
                local inputJointDescIndex = self.spec_attachable.inputAttacherJointDescIndex
                local jointDescIndex = implement.jointDescIndex

                self:connectHosesToAttacherVehicle(attacherVehicle, inputJointDescIndex, jointDescIndex)
                self:updateAttachedConnectionHoses(attacherVehicle) -- update once
            end
        end
    end
end

---Called on server side on join
---@param streamId number
---@param connection number
function ManualAttachConnectionHoses:onWriteStream(streamId, connection)
    local hasAttacherVehicle = self.getAttacherVehicle ~= nil
    streamWriteBool(streamId, hasAttacherVehicle)
    if hasAttacherVehicle then
        streamWriteBool(streamId, self:hasAttachedHoses())
    end
end

function ManualAttachConnectionHoses:saveToXMLFile(xmlFile, key, usedModNames)
    if self.getAttacherVehicle ~= nil then
        local attacherVehicle = self:getAttacherVehicle()

        if attacherVehicle ~= nil and ManualAttachUtil.hasConnectionHoses(self, attacherVehicle) then
            xmlFile:setValue(key .. "#hasAttachedConnectionHoses", ManualAttachUtil.hasAttachedConnectionHoses(self))
        end
    end
end

function ManualAttachConnectionHoses:onPostUpdateTick(dt)
    local spec = self.spec_manualAttachConnectionHoses
    if self.brake ~= nil and not self:hasAttachedHosesOfType(ManualAttachConnectionHoses.TYPE_AIR) then
        self:brake(1, true)
    end

    if self.isServer then
        if self:hasAttachedHosesOfType(ManualAttachConnectionHoses.TYPE_ELECTRIC) then

            if spec.doLightsUpdate then
                self:toggleLightStates(true, false)
                spec.doLightsUpdate = false
            end
        end
    end

    if self.finishedFirstUpdate and spec.hoseStateChanged then
        for type, _ in pairs(ManualAttachConnectionHoses.TYPES) do
            spec.attachedHosesByType[type] = self:isHoseAttached(type)
        end

        spec.hoseStateChanged = false
    end
end

---Set if mod needs to force update the state.
---@param state boolean
function ManualAttachConnectionHoses:setUpdateLightsState(state)
    local spec = self.spec_manualAttachConnectionHoses
    spec.doLightsUpdate = state
end

---Returns true if vehicle has attached hoses, false otherwise.
function ManualAttachConnectionHoses:isHoseAttached(type)
    type = type or ManualAttachConnectionHoses.TYPE_HYDRAULIC

    local attacherVehicle = self:getAttacherVehicle()
    if attacherVehicle ~= nil then
        if not ManualAttachUtil.hasConnectionHoses(self, attacherVehicle) then
            return true
        end
    end

    return ManualAttachUtil.hasAttachedConnectionHoses(self, type)
end

---Returns true if hoses are attached, false otherwise.
function ManualAttachConnectionHoses:hasAttachedHoses()
    if self.getAttacherVehicle ~= nil then
        local attacherVehicle = self:getAttacherVehicle()
        if attacherVehicle ~= nil
            and attacherVehicle.hasAttachedHoses ~= nil
            and not attacherVehicle:hasAttachedHoses() then
            return false
        end
    end

    local spec = self.spec_manualAttachConnectionHoses
    -- Weird check, however spec table might be injected to nil..
    if spec == nil then
        return true
    end

    for _, isAttached in pairs(spec.attachedHosesByType) do
        if isAttached then
            return true
        end
    end

    return false
end

---Returns true if hoses of type are attached, false otherwise.
function ManualAttachConnectionHoses:hasAttachedHosesOfType(type)
    type = type or ManualAttachConnectionHoses.TYPE_HYDRAULIC

    if not self.finishedFirstUpdate then
        return true
    end

    if self.getAttacherVehicle ~= nil then
        local attacherVehicle = self:getAttacherVehicle()
        if attacherVehicle ~= nil
            and attacherVehicle.hasAttachedHosesOfType ~= nil
            and not attacherVehicle:hasAttachedHosesOfType(type) then
            return false
        end
    end

    local spec = self.spec_manualAttachConnectionHoses
    -- Weird check, however spec table might be injected to nil..
    if spec == nil then
        return true
    end

    return spec.attachedHosesByType[type]
end

---Toggles the lights states.
---@param isActive boolean
---@param noEventSend boolean
function ManualAttachConnectionHoses:toggleLightStates(isActive, noEventSend)
    local spec = self.spec_lights
    if spec == nil then
        return
    end

    if not isActive then
        self:deactivateLights()
    else
        local rootVehicle = self:getRootVehicle()
        self:setLightsTypesMask(rootVehicle.spec_lights.lightsTypesMask, true, noEventSend)
        self:setBeaconLightsVisibility(rootVehicle.spec_lights.beaconLightsActive, true, noEventSend)
        self:setTurnLightState(rootVehicle.spec_lights.turnLightState, true, noEventSend)
    end
end

---Disconnect attached hoses, moved to function because vanilla handles this in the postDetach event.
---@param attacherVehicle table
function ManualAttachConnectionHoses:disconnectHoses(attacherVehicle)
    local spec = self.spec_connectionHoses

    if spec ~= nil then
        -- before the actual hoses are detached.
        self:toggleLightStates(false, true)

        local inputJointDescIndex = self:getActiveInputAttacherJointDescIndex()
        local hoses = self:getConnectionHosesByInputAttacherJoint(inputJointDescIndex)

        for _, hose in ipairs(hoses) do
            self:disconnectHose(hose)
        end

        for i = #spec.updateableHoses, 1, -1 do
            local hose = spec.updateableHoses[i]

            if hose.connectedObject == attacherVehicle then
                self:disconnectHose(hose)
            end
        end

        local attacherVehicleSpec = attacherVehicle.spec_connectionHoses

        if attacherVehicleSpec ~= nil then
            for _, toolConnector in pairs(attacherVehicleSpec.toolConnectorHoses) do
                if toolConnector.delayedMounting ~= nil and toolConnector.delayedMounting.sourceObject == self then
                    toolConnector.delayedMounting = nil
                end
            end
        end

        local customHoses = spec.customHosesByInputAttacher[inputJointDescIndex]
        if customHoses ~= nil then
            for i = 1, #customHoses do
                local customHose = customHoses[i]

                if customHose.isActive then
                    self:disconnectCustomHoseNode(customHose, customHose.connectedTarget)
                end
            end
        end

        local customTargets = spec.customHoseTargetsByInputAttacher[inputJointDescIndex]
        if customTargets ~= nil then
            for i = 1, #customTargets do
                local customTarget = customTargets[i]

                if customTarget.isActive then
                    self:disconnectCustomHoseNode(customTarget.connectedHose, customTarget)
                end
            end
        end
    end

    self.spec_manualAttachConnectionHoses.hoseStateChanged = true
    self:raiseActive()
end

---Play attach sound for the given jointDesc.
function ManualAttachConnectionHoses:playHoseAttachSound(jointDesc)
    local spec = self.spec_manualAttachConnectionHoses

    if self.isClient then
        if jointDesc ~= nil and jointDesc.sampleAttachHoses ~= nil then
            g_soundManager:playSample(jointDesc.sampleAttachHoses)
        else
            g_soundManager:playSample(spec.samples.attach)
        end
    end

    return true
end

---Called on post attache event.
---@param attacherVehicle table
---@param inputJointDescIndex number
---@param jointDescIndex number
function ManualAttachConnectionHoses:onPostAttach(attacherVehicle, inputJointDescIndex, jointDescIndex)
    local spec = self.spec_manualAttachConnectionHoses

    if not spec.isBlockingInitialHoseDetach and g_currentMission.manualAttach.isEnabled then
        self:disconnectHoses(attacherVehicle)
    else
        spec.isBlockingInitialHoseDetach = false
    end
end

---
--- Injections.
---

function ManualAttachConnectionHoses.inj_connectHosesToAttacherVehicle(vehicle, superFunc, attacherVehicle, inputJointDescIndex, jointDescIndex, updateToolConnections, excludeVehicle)
    superFunc(vehicle, attacherVehicle, inputJointDescIndex, jointDescIndex, updateToolConnections, excludeVehicle)
    vehicle:toggleLightStates(true, true)

    if attacherVehicle.getConnectionTarget ~= nil then
        vehicle.spec_manualAttachConnectionHoses.hoseStateChanged = true
        vehicle:raiseActive()
    end

end

function ManualAttachConnectionHoses.inj_setLightsTypesMask(vehicle, superFunc, lightsTypesMask, force, noEventSend)
    if not vehicle:hasAttachedHosesOfType(ManualAttachConnectionHoses.TYPE_ELECTRIC) then
        vehicle:setUpdateLightsState(lightsTypesMask > 0)

        return false
    end

    return superFunc(vehicle, lightsTypesMask, force, noEventSend)
end

function ManualAttachConnectionHoses.inj_setBeaconLightsVisibility(vehicle, superFunc, visibility, force, noEventSend)
    if not vehicle:hasAttachedHosesOfType(ManualAttachConnectionHoses.TYPE_ELECTRIC) then
        vehicle:setUpdateLightsState(visibility)

        return false
    end

    return superFunc(vehicle, visibility, force, noEventSend)
end

function ManualAttachConnectionHoses.inj_setTurnLightState(vehicle, superFunc, state, force, noEventSend)
    if not vehicle:hasAttachedHosesOfType(ManualAttachConnectionHoses.TYPE_ELECTRIC) then
        vehicle:setUpdateLightsState(state ~= 0)

        return false
    end

    return superFunc(vehicle, state, force, noEventSend)
end

function ManualAttachConnectionHoses.inj_setBrakeLightsVisibility(vehicle, superFunc, visibility)
    if not vehicle:hasAttachedHosesOfType(ManualAttachConnectionHoses.TYPE_ELECTRIC) then
        vehicle:setUpdateLightsState(visibility)

        return false
    end

    return superFunc(vehicle, visibility)
end

function ManualAttachConnectionHoses.inj_setReverseLightsVisibility(vehicle, superFunc, visibility)
    if not vehicle:hasAttachedHosesOfType(ManualAttachConnectionHoses.TYPE_ELECTRIC) then
        vehicle:setUpdateLightsState(visibility)

        return false
    end

    return superFunc(vehicle, visibility)
end

function ManualAttachConnectionHoses.inj_getIsFoldAllowed(vehicle, superFunc, direction, onAiTurnOn)
    if not vehicle:hasAttachedHosesOfType(ManualAttachConnectionHoses.TYPE_HYDRAULIC) then
        return false
    end

    return superFunc(vehicle, direction, onAiTurnOn)
end

function ManualAttachConnectionHoses.inj_getIsMovingToolActive(vehicle, superFunc, movingTool)
    if not vehicle:hasAttachedHosesOfType(ManualAttachConnectionHoses.TYPE_HYDRAULIC) then
        return false
    end

    return superFunc(vehicle, movingTool)
end

function ManualAttachConnectionHoses.inj_getCanBeTurnedOn(vehicle, superFunc)
    if not vehicle:hasAttachedHosesOfType(ManualAttachConnectionHoses.TYPE_HYDRAULIC) then
        return false
    end

    return superFunc(vehicle)
end

function ManualAttachConnectionHoses.inj_getIsFoldMiddleAllowed(vehicle, superFunc)
    if not vehicle:hasAttachedHosesOfType(ManualAttachConnectionHoses.TYPE_HYDRAULIC) then
        return false
    end

    return superFunc(vehicle)
end

function ManualAttachConnectionHoses.inj_canFoldRidgeMarker(vehicle, superFunc, state)
    if not vehicle:hasAttachedHosesOfType(ManualAttachConnectionHoses.TYPE_HYDRAULIC) then
        return false
    end

    return superFunc(vehicle, state)
end

function ManualAttachConnectionHoses.inj_getCanDischargeToObject(vehicle, superFunc, dischargeNode)
    if vehicle.spec_shovel == nil -- dismiss shovels
        and not vehicle:hasAttachedHosesOfType(ManualAttachConnectionHoses.TYPE_HYDRAULIC) then
        return false
    end

    return superFunc(vehicle, dischargeNode)
end

function ManualAttachConnectionHoses.inj_getCanDischargeToGround(vehicle, superFunc, dischargeNode)
    if vehicle.spec_shovel == nil -- dismiss shovels
        and not vehicle:hasAttachedHosesOfType(ManualAttachConnectionHoses.TYPE_HYDRAULIC) then
        return false
    end

    return superFunc(vehicle, dischargeNode)
end
