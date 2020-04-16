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
    SpecializationUtil.registerFunction(vehicleType, "playPtoAttachSound", ManualAttachPowerTakeOff.playPtoAttachSound)
end

function ManualAttachPowerTakeOff.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanBeTurnedOn", ManualAttachPowerTakeOff.inj_getCanBeTurnedOn)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanDischargeToObject", ManualAttachPowerTakeOff.inj_getCanDischargeToObject)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanDischargeToGround", ManualAttachPowerTakeOff.inj_getCanDischargeToGround)
end

function ManualAttachPowerTakeOff.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", ManualAttachPowerTakeOff)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", ManualAttachPowerTakeOff)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", ManualAttachPowerTakeOff)
    SpecializationUtil.registerEventListener(vehicleType, "onPostAttach", ManualAttachPowerTakeOff)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", ManualAttachPowerTakeOff)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", ManualAttachPowerTakeOff)
end

function ManualAttachPowerTakeOff:onLoad(savegame)
    self.spec_manualAttachPowerTakeOff = ManualAttachUtil.getSpecTable(self, "manualAttachPowerTakeOff")
    local spec = self.spec_manualAttachPowerTakeOff

    if self.isClient then
        spec.samples = {}

        local sampleAttach = g_soundManager:loadSampleFromXML(self.xmlFile, "vehicle.attacherJoints.sounds", "attachPto", self.baseDirectory, self.components, 1, AudioGroup.VEHICLE, self.i3dMappings, self)
        if sampleAttach == nil then
            sampleAttach = g_soundManager:cloneSample(g_manualAttach.samples.ptoAttach, self.components[1].node, self)
        end

        spec.samples.attach = sampleAttach
    end
end

function ManualAttachPowerTakeOff:onPostLoad(savegame)
    local spec = self.spec_manualAttachPowerTakeOff
    spec.isBlockingInitialPtoDetach = false -- always block detach because we don't have an attached PTO at first load.

    if savegame ~= nil then
        local key = savegame.key .. "." .. g_manualAttach.modName
        spec.isBlockingInitialPtoDetach = Utils.getNoNil(getXMLBool(savegame.xmlFile, key .. ".manualAttachPowerTakeOff#hasAttachedPowerTakeOffs"), false)
    end
end

function ManualAttachPowerTakeOff:onDelete()
    local spec = self.spec_manualAttachPowerTakeOff

    if self.isClient then
        g_soundManager:deleteSample(spec.samples.attach)
    end
end

---Called on client side on join
---@param streamId number
---@param connection number
function ManualAttachPowerTakeOff:onReadStream(streamId, connection)
    if streamReadBool(streamId) then
        local isPtoAttached = streamReadBool(streamId)
        if isPtoAttached then
            local attacherVehicle = self:getAttacherVehicle()
            if attacherVehicle ~= nil and attacherVehicle.attachPowerTakeOff ~= nil then
                local implement = attacherVehicle:getImplementByObject(self)
                local inputJointDescIndex = self.spec_attachable.inputAttacherJointDescIndex
                local jointDescIndex = implement.jointDescIndex
                attacherVehicle:attachPowerTakeOff(self, inputJointDescIndex, jointDescIndex)
                attacherVehicle:handlePowerTakeOffPostAttach(jointDescIndex)
            end
        end
    end
end

---Called on server side on join
---@param streamId number
---@param connection number
function ManualAttachPowerTakeOff:onWriteStream(streamId, connection)
    local hasAttacherVehicle = self.getAttacherVehicle ~= nil
    streamWriteBool(streamId, hasAttacherVehicle)
    if hasAttacherVehicle then
        streamWriteBool(streamId, self:isPtoAttached())
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

---Play attach sound for the given jointDesc.
function ManualAttachPowerTakeOff:playPtoAttachSound(jointDesc)
    local spec = self.spec_manualAttachPowerTakeOff

    if self.isClient then
        if jointDesc ~= nil and jointDesc.sampleAttachPto ~= nil then
            g_soundManager:playSample(jointDesc.sampleAttachPto)
        else
            g_soundManager:playSample(spec.samples.attach)
        end
    end

    return true
end

---Called on post attach event.
---@param attacherVehicle table
---@param inputJointDescIndex number
---@param jointDescIndex number
function ManualAttachPowerTakeOff:onPostAttach(attacherVehicle, inputJointDescIndex, jointDescIndex)
    local spec = self.spec_manualAttachPowerTakeOff
    if not spec.isBlockingInitialPtoDetach then
        if attacherVehicle.detachPowerTakeOff ~= nil then
            if ManualAttachUtil.hasPowerTakeOffs(self, attacherVehicle) then
                local implement = attacherVehicle:getImplementByObject(self)
                attacherVehicle:detachPowerTakeOff(attacherVehicle, implement)
            end
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

function ManualAttachPowerTakeOff.inj_getCanDischargeToObject(vehicle, superFunc, dischargeNode)
    if not vehicle:isPtoAttached() then
        return false
    end

    return superFunc(vehicle, dischargeNode)
end

function ManualAttachPowerTakeOff.inj_getCanDischargeToGround(vehicle, superFunc, dischargeNode)
    if not vehicle:isPtoAttached() then
        return false
    end

    return superFunc(vehicle, dischargeNode)
end
