---
-- ManualAttachConnectionHoses
--
-- ConnectionHoses extension for Manual Attach.
--
-- Copyright (c) Wopster, 2019

ManualAttachConnectionHoses = {}

function ManualAttachConnectionHoses.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(ConnectionHoses, specializations)
end

function ManualAttachConnectionHoses.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "disconnectHoses", ManualAttachConnectionHoses.disconnectHoses)
    SpecializationUtil.registerFunction(vehicleType, "setUpdateLightsState", ManualAttachConnectionHoses.setUpdateLightsState)
    SpecializationUtil.registerFunction(vehicleType, "toggleLightStates", ManualAttachConnectionHoses.toggleLightStates)
    SpecializationUtil.registerFunction(vehicleType, "isHoseAttached", ManualAttachConnectionHoses.isHoseAttached)
    SpecializationUtil.registerFunction(vehicleType, "hasAttachedHoses", ManualAttachConnectionHoses.hasAttachedHoses)
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
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsFoldMiddleAllowed", ManualAttachConnectionHoses.inj_getIsFoldMiddleAllowed)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "canFoldRidgeMarker", ManualAttachConnectionHoses.inj_canFoldRidgeMarker)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanDischargeToGround", ManualAttachConnectionHoses.inj_getCanDischargeToGround)
end

function ManualAttachConnectionHoses.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", ManualAttachConnectionHoses)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", ManualAttachConnectionHoses)
    SpecializationUtil.registerEventListener(vehicleType, "onPostAttach", ManualAttachConnectionHoses)
    SpecializationUtil.registerEventListener(vehicleType, "onPostUpdateTick", ManualAttachConnectionHoses)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", ManualAttachConnectionHoses)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", ManualAttachConnectionHoses)
end

function ManualAttachConnectionHoses:onLoad(savegame)
    self.spec_manualAttachConnectionHoses = ManualAttachUtil.getSpecTable(self, "manualAttachConnectionHoses")
end

function ManualAttachConnectionHoses:onPostLoad(savegame)
    local spec = self.spec_manualAttachConnectionHoses

    spec.doLightsUpdate = false
    spec.isBlockingInitialHoseDetach = false
    spec.hasAttachedHoses = false

    if savegame ~= nil then
        local key = savegame.key .. "." .. g_manualAttach.modName
        spec.isBlockingInitialHoseDetach = Utils.getNoNil(getXMLBool(savegame.xmlFile, key .. ".manualAttachConnectionHoses#hasAttachedConnectionHoses"), false)
    end
end

---Called on client side on join
---@param streamId number
---@param connection number
function ManualAttachConnectionHoses:onReadStream(streamId, connection)
    local spec = self.spec_manualAttachConnectionHoses

    local hasAttachedHoses = streamReadBool(streamId)
    spec.hasAttachedHoses = hasAttachedHoses

    if not hasAttachedHoses then
        local attacherVehicle = self:getAttacherVehicle()
        if attacherVehicle ~= nil then
            self:disconnectHoses(attacherVehicle)
        end
    end
end

---Called on server side on join
---@param streamId number
---@param connection number
function ManualAttachConnectionHoses:onWriteStream(streamId, connection)
    local spec = self.spec_manualAttachConnectionHoses
    streamWriteBool(streamId, spec.hasAttachedHoses)
end

function ManualAttachConnectionHoses:saveToXMLFile(xmlFile, key, usedModNames)
    if self.getAttacherVehicle ~= nil then
        local attacherVehicle = self:getAttacherVehicle()

        if attacherVehicle ~= nil and ManualAttachUtil.hasConnectionHoses(self, attacherVehicle) then
            setXMLBool(xmlFile, key .. "#hasAttachedConnectionHoses", ManualAttachUtil.hasAttachedConnectionHoses(self))
        end
    end
end

function ManualAttachConnectionHoses:onPostUpdateTick(dt)
    local spec = self.spec_manualAttachConnectionHoses
    if self.brake ~= nil and not spec.hasAttachedHoses then
        self:brake(1, true)
    end

    if self.isServer then
        if self:hasAttachedHoses() then

            if spec.doLightsUpdate then
                self:toggleLightStates(true, false)
                spec.doLightsUpdate = false
            end
        end
    end
end

---Set if mod needs to force update the state.
---@param state boolean
function ManualAttachConnectionHoses:setUpdateLightsState(state)
    local spec = self.spec_manualAttachConnectionHoses
    spec.doLightsUpdate = state
end

---Returns true if vehicle has attached hoses, false otherwise.
function ManualAttachConnectionHoses:isHoseAttached()
    local attacherVehicle = self:getAttacherVehicle()
    if attacherVehicle ~= nil then
        if not ManualAttachUtil.hasConnectionHoses(self, attacherVehicle) then
            return true
        end
    end

    return ManualAttachUtil.hasEdgeCaseHose(self) or ManualAttachUtil.hasAttachedConnectionHoses(self)
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
    return spec.hasAttachedHoses
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

        local hoses = self:getConnectionHosesByInputAttacherJoint(self:getActiveInputAttacherJointDescIndex())

        for _, hose in ipairs(hoses) do
            self:disconnectHose(hose)
        end

        for _, hose in ipairs(spec.updateableHoses) do
            if hose.connectedObject == attacherVehicle then
                self:disconnectHose(hose)
            end
        end

        -- remove delayed mounting if we detach the implement
        local attacherVehicleSpec = attacherVehicle.spec_connectionHoses
        if attacherVehicleSpec ~= nil then
            for _, toolConnector in pairs(attacherVehicleSpec.toolConnectorHoses) do
                if toolConnector.delayedMounting ~= nil then
                    if toolConnector.delayedMounting.sourceObject == self then
                        toolConnector.delayedMounting = nil
                    end
                end
            end
        end
    end

    local spec_manualAttach = self.spec_manualAttachConnectionHoses
    spec_manualAttach.hasAttachedHoses = self:isHoseAttached()
end

---Called on post attache event.
---@param attacherVehicle table
---@param inputJointDescIndex number
---@param jointDescIndex number
function ManualAttachConnectionHoses:onPostAttach(attacherVehicle, inputJointDescIndex, jointDescIndex)
    local spec = self.spec_manualAttachConnectionHoses
    if not spec.isBlockingInitialHoseDetach then
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
        local spec_manualAttach = vehicle.spec_manualAttachConnectionHoses
        spec_manualAttach.hasAttachedHoses = vehicle:isHoseAttached()
    end
end

function ManualAttachConnectionHoses.inj_setLightsTypesMask(vehicle, superFunc, lightsTypesMask, force, noEventSend)
    if not vehicle:hasAttachedHoses() then
        vehicle:setUpdateLightsState(lightsTypesMask > 0)

        return false
    end

    return superFunc(vehicle, lightsTypesMask, force, noEventSend)
end

function ManualAttachConnectionHoses.inj_setBeaconLightsVisibility(vehicle, superFunc, visibility, force, noEventSend)
    if not vehicle:hasAttachedHoses() then
        vehicle:setUpdateLightsState(visibility)

        return false
    end

    return superFunc(vehicle, visibility, force, noEventSend)
end

function ManualAttachConnectionHoses.inj_setTurnLightState(vehicle, superFunc, state, force, noEventSend)
    if not vehicle:hasAttachedHoses() then
        vehicle:setUpdateLightsState(state ~= 0)

        return false
    end

    return superFunc(vehicle, state, force, noEventSend)
end

function ManualAttachConnectionHoses.inj_setBrakeLightsVisibility(vehicle, superFunc, visibility)
    if not vehicle:hasAttachedHoses() then
        vehicle:setUpdateLightsState(visibility)

        return false
    end

    return superFunc(vehicle, visibility)
end

function ManualAttachConnectionHoses.inj_setReverseLightsVisibility(vehicle, superFunc, visibility)
    if not vehicle:hasAttachedHoses() then
        vehicle:setUpdateLightsState(visibility)

        return false
    end

    return superFunc(vehicle, visibility)
end

function ManualAttachConnectionHoses.inj_getIsFoldAllowed(vehicle, superFunc, direction, onAiTurnOn)
    if not vehicle:hasAttachedHoses() then
        return false
    end

    return superFunc(vehicle, direction, onAiTurnOn)
end

function ManualAttachConnectionHoses.inj_getIsMovingToolActive(vehicle, superFunc, movingTool)
    if not vehicle:hasAttachedHoses() then
        return false
    end

    return superFunc(vehicle, movingTool)
end

function ManualAttachConnectionHoses.inj_getCanBeTurnedOn(vehicle, superFunc)
    if not vehicle:hasAttachedHoses() then
        return false
    end

    return superFunc(vehicle)
end

function ManualAttachConnectionHoses.inj_getIsFoldMiddleAllowed(vehicle, superFunc)
    if not vehicle:hasAttachedHoses() then
        return false
    end

    return superFunc(vehicle)
end

function ManualAttachConnectionHoses.inj_canFoldRidgeMarker(vehicle, superFunc, state)
    if not vehicle:hasAttachedHoses() then
        return false
    end

    return superFunc(vehicle, state)
end

function ManualAttachConnectionHoses.inj_getCanDischargeToGround(vehicle, superFunc, dischargeNode)
    if not vehicle:hasAttachedHoses() then
        return false
    end

    return superFunc(vehicle, dischargeNode)
end
