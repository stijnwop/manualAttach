---
-- ManualAttachPowerTakeOff
--
-- PowerTakeOffs extension for Manual Attach.
--
-- Copyright (c) Wopster, 2019

ManualAttachPowerTakeOff = {}

function ManualAttachPowerTakeOff.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(PowerTakeOffs, specializations)
end

function ManualAttachPowerTakeOff.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "handlePowerTakeOffPostAttach", ManualAttachPowerTakeOff.handlePowerTakeOffPostAttach)
end

function ManualAttachPowerTakeOff.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanToggleAttach", ManualAttachPowerTakeOff.inj_getCanToggleAttach)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanBeTurnedOn", ManualAttachPowerTakeOff.inj_getCanBeTurnedOn)
end

---Handles post attach in a function.
---@param jointDescIndex number
function ManualAttachPowerTakeOff:handlePowerTakeOffPostAttach(jointDescIndex)
    local spec = self.spec_powerTakeOffs
    for i = #spec.delayedPowerTakeOffsMountings, 1, -1 do
        local delayedMounting = spec.delayedPowerTakeOffsMountings[i]

        if delayedMounting.jointDescIndex == jointDescIndex then
            local input = delayedMounting.input
            local output = delayedMounting.output

            if input.attachFunc ~= nil then
                input.attachFunc(self, input, output)
            end

            ObjectChangeUtil.setObjectChanges(input.objectChanges, true)
            ObjectChangeUtil.setObjectChanges(output.objectChanges, true)

            table.remove(spec.delayedPowerTakeOffsMountings, i)
        end
    end
end

---Called on post attach event.
---@param attacherVehicle table
---@param inputJointDescIndex number
---@param jointDescIndex number
function ManualAttachPowerTakeOff:onPostAttach(attacherVehicle, inputJointDescIndex, jointDescIndex)
    if attacherVehicle.detachPowerTakeOff ~= nil then
        local implement = attacherVehicle:getImplementByObject(self)

        attacherVehicle:detachPowerTakeOff(attacherVehicle, implement)
    end
end

---
--- Injections.
---

function ManualAttachPowerTakeOff.inj_getCanToggleAttach(vehicle, superFunc)
    return false
end

function ManualAttachPowerTakeOff.inj_getCanBeTurnedOn(vehicle, superFunc)
    if vehicle.getAttacherVehicle ~= nil then
        local attacherVehicle = vehicle:getAttacherVehicle()
        if ManualAttachUtil.hasPowerTakeOffs(vehicle)
                and not ManualAttachUtil.hasAttachedPowerTakeOffs(vehicle, attacherVehicle) then
            return false
        end
    end

    return superFunc(vehicle)
end