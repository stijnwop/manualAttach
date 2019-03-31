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
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getAllowsLowering", ManualAttachConnectionHoses.inj_getAllowsLowering)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsFoldMiddleAllowed", ManualAttachConnectionHoses.inj_getIsFoldMiddleAllowed)
end

function ManualAttachConnectionHoses.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", ManualAttachConnectionHoses)
    SpecializationUtil.registerEventListener(vehicleType, "onPostAttach", ManualAttachConnectionHoses)
    SpecializationUtil.registerEventListener(vehicleType, "onPostUpdateTick", ManualAttachConnectionHoses)
end

function ManualAttachConnectionHoses:onLoad(savegame)
    local spec = ManualAttachUtil.getSpecTable(self, "manualAttachConnectionHoses")
    spec.doLightsUpdate = false
end

function ManualAttachConnectionHoses:onPostUpdateTick(dt)
    if self.isServer then
        if self:isHoseAttached() then
            local spec = ManualAttachUtil.getSpecTable(self, "manualAttachConnectionHoses")

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
    local spec = ManualAttachUtil.getSpecTable(self, "manualAttachConnectionHoses")
    spec.doLightsUpdate = state
end

---Returns true if hoses are attached, false otherwise.
function ManualAttachConnectionHoses:isHoseAttached()
    local attacherVehicle = self:getAttacherVehicle()
    if attacherVehicle ~= nil then
        if not ManualAttachUtil.hasConnectionHoses(self, attacherVehicle) then
            return true
        end
    end

    return ManualAttachUtil.hasAttachedConnectionHoses(self)
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
end

---Called on post attache event.
---@param attacherVehicle table
---@param inputJointDescIndex number
---@param jointDescIndex number
function ManualAttachConnectionHoses:onPostAttach(attacherVehicle, inputJointDescIndex, jointDescIndex)
    self:disconnectHoses(attacherVehicle)
end

---
--- Injections.
---

function ManualAttachConnectionHoses.inj_setLightsTypesMask(vehicle, superFunc, lightsTypesMask, force, noEventSend)
    if not vehicle:isHoseAttached() then
        vehicle:setUpdateLightsState(lightsTypesMask > 0)

        return false
    end

    return superFunc(vehicle, lightsTypesMask, force, noEventSend)
end

function ManualAttachConnectionHoses.inj_setBeaconLightsVisibility(vehicle, superFunc, visibility, force, noEventSend)
    if not vehicle:isHoseAttached() then
        vehicle:setUpdateLightsState(visibility)

        return false
    end

    return superFunc(vehicle, visibility, force, noEventSend)
end

function ManualAttachConnectionHoses.inj_setTurnLightState(vehicle, superFunc, state, force, noEventSend)
    if not vehicle:isHoseAttached() then
        vehicle:setUpdateLightsState(state ~= 0)

        return false
    end

    return superFunc(vehicle, state, force, noEventSend)
end

function ManualAttachConnectionHoses.inj_setBrakeLightsVisibility(vehicle, superFunc, visibility)
    if not vehicle:isHoseAttached() then
        vehicle:setUpdateLightsState(visibility)

        return false
    end

    return superFunc(vehicle, visibility)
end

function ManualAttachConnectionHoses.inj_setReverseLightsVisibility(vehicle, superFunc, visibility)
    if not vehicle:isHoseAttached() then
        vehicle:setUpdateLightsState(visibility)

        return false
    end

    return superFunc(vehicle, visibility)
end

function ManualAttachConnectionHoses.inj_connectHosesToAttacherVehicle(vehicle, superFunc, attacherVehicle, inputJointDescIndex, jointDescIndex, updateToolConnections, excludeVehicle)
    superFunc(vehicle, attacherVehicle, inputJointDescIndex, jointDescIndex, updateToolConnections, excludeVehicle)
    vehicle:toggleLightStates(true, true)
end

function ManualAttachConnectionHoses.inj_getIsFoldAllowed(vehicle, superFunc, direction, onAiTurnOn)
    if not vehicle:isHoseAttached() then
        return false
    end

    return superFunc(vehicle, direction, onAiTurnOn)
end

function ManualAttachConnectionHoses.inj_getIsMovingToolActive(vehicle, superFunc, movingTool)
    if not vehicle:isHoseAttached() then
        return false
    end

    return superFunc(vehicle, movingTool)
end

function ManualAttachConnectionHoses.inj_getCanBeTurnedOn(vehicle, superFunc)
    if not vehicle:isHoseAttached() then
        return false
    end

    return superFunc(vehicle)
end

function ManualAttachConnectionHoses.inj_getAllowsLowering(vehicle, superFunc)
    if not vehicle:isHoseAttached() then
        return false
    end

    return superFunc(vehicle)
end

function ManualAttachConnectionHoses.inj_getIsFoldMiddleAllowed(vehicle, superFunc)
    if not vehicle:isHoseAttached() then
        return false
    end

    return superFunc(vehicle)
end
