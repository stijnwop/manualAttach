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
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanDischargeToGround", ManualAttachPowerTakeOff.inj_getCanDischargeToGround)
end

function ManualAttachPowerTakeOff.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", ManualAttachPowerTakeOff)
    SpecializationUtil.registerEventListener(vehicleType, "onPostAttach", ManualAttachPowerTakeOff)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", ManualAttachPowerTakeOff)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", ManualAttachPowerTakeOff)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", ManualAttachPowerTakeOff)
end

function ManualAttachPowerTakeOff:onLoad(savegame)
    self.spec_manualAttachPowerTakeOff = ManualAttachUtil.getSpecTable(self, "manualAttachPowerTakeOff")
end

function ManualAttachPowerTakeOff:onPostLoad(savegame)
    local spec = self.spec_manualAttachPowerTakeOff
    spec.isBlockingInitialPtoDetach = false

    if savegame ~= nil then
        local key = savegame.key .. "." .. g_manualAttach.modName
        spec.isBlockingInitialPtoDetach = Utils.getNoNil(getXMLBool(savegame.xmlFile, key .. ".manualAttachPowerTakeOff#hasAttachedPowerTakeOffs"), false)
    end
end

---Called on client side on join
---@param streamId number
---@param connection number
function ManualAttachPowerTakeOff:onReadStream(streamId, connection)
    local isPtoAttached = streamReadBool(streamId)

    if not isPtoAttached then
        local attacherVehicle = self:getAttacherVehicle()
        if attacherVehicle ~= nil and attacherVehicle.detachPowerTakeOff ~= nil then
            local implement = attacherVehicle:getImplementByObject(self)
            attacherVehicle:detachPowerTakeOff(attacherVehicle, implement)
        end
    end
end

---Called on server side on join
---@param streamId number
---@param connection number
function ManualAttachPowerTakeOff:onWriteStream(streamId, connection)
    streamWriteBool(streamId, self:isPtoAttached())
end

function ManualAttachPowerTakeOff:saveToXMLFile(xmlFile, key, usedModNames)
    if self.getAttacherVehicle ~= nil then
        local attacherVehicle = self:getAttacherVehicle()

        if attacherVehicle ~= nil and ManualAttachUtil.hasPowerTakeOffs(self, attacherVehicle) then
            setXMLBool(xmlFile, key .. "#hasAttachedPowerTakeOffs", ManualAttachUtil.hasAttachedPowerTakeOffs(self, attacherVehicle))
        end
    end
end

---Returns true when the vehicle doesn't have a pto or when the vehicle has a pto and the pto is attached, false otherwise.
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
    local spec = self.spec_manualAttachPowerTakeOff
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

function ManualAttachPowerTakeOff.inj_getCanDischargeToGround(vehicle, superFunc, dischargeNode)
    if not vehicle:isPtoAttached() then
        return false
    end

    return superFunc(vehicle, dischargeNode)
end
