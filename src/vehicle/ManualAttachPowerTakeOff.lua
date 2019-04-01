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
    SpecializationUtil.registerFunction(vehicleType, "isPtoAttached", ManualAttachPowerTakeOff.isPtoAttached)
end

function ManualAttachPowerTakeOff.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanBeTurnedOn", ManualAttachPowerTakeOff.inj_getCanBeTurnedOn)
end

function ManualAttachPowerTakeOff.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onPostAttach", ManualAttachPowerTakeOff)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", ManualAttachPowerTakeOff)
end

function ManualAttachPowerTakeOff:onPostLoad(savegame)
    local spec = ManualAttachUtil.getSpecTable(self, "manualAttachPowerTakeOff")
    spec.isBlockingInitialPtoDetach = false

    if savegame ~= nil then
        local key = savegame.key .. "." .. g_manualAttach.modName
        spec.isBlockingInitialPtoDetach = Utils.getNoNil(getXMLBool(savegame.xmlFile, key .. ".manualAttachPowerTakeOff#hasAttachedPowerTakeOffs"), false)
    end
end

function ManualAttachPowerTakeOff:saveToXMLFile(xmlFile, key, usedModNames)
    if self.getAttacherVehicle ~= nil then
        local attacherVehicle = self:getAttacherVehicle()

        if attacherVehicle ~= nil and ManualAttachUtil.hasPowerTakeOffs(self, attacherVehicle) then
            setXMLBool(xmlFile, key .. "#hasAttachedPowerTakeOffs", ManualAttachUtil.hasAttachedPowerTakeOffs(self, attacherVehicle))
        end
    end
end

function ManualAttachPowerTakeOff:isPtoAttached()
    if self.getAttacherVehicle ~= nil then
        local attacherVehicle = self:getAttacherVehicle()

        if attacherVehicle ~= nil then
            if not ManualAttachUtil.hasPowerTakeOffs(self, attacherVehicle) then
                return true
            end

            return ManualAttachUtil.hasAttachedPowerTakeOffs(self, attacherVehicle)
        end
    end

    return true
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
    local spec = ManualAttachUtil.getSpecTable(self, "manualAttachPowerTakeOff")
    if not spec.isBlockingInitialPtoDetach then
        if attacherVehicle.detachPowerTakeOff ~= nil then
            local implement = attacherVehicle:getImplementByObject(self)
            attacherVehicle:detachPowerTakeOff(attacherVehicle, implement)
        end
    else
        spec.isBlockingInitialPtoDetach = false
    end
end

---
--- Injections.
---

function ManualAttachPowerTakeOff.inj_getCanBeTurnedOn(vehicle, superFunc)
    if not vehicle:isPtoAttached() then
        return false
    end

    return superFunc(vehicle)
end