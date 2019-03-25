ManualAttachExtension = {}

function ManualAttachExtension.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Attachable, specializations) or
            SpecializationUtil.hasSpecialization(AttacherJoints, specializations)
end

function ManualAttachExtension.registerEvents(vehicleType)
end

function ManualAttachExtension.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "onPowerTakeOffChanged", ManualAttachExtension.onPowerTakeOffChanged)
    SpecializationUtil.registerFunction(vehicleType, "handlePowerTakeOffPostAttach", ManualAttachExtension.handlePowerTakeOffPostAttach)
end

function ManualAttachExtension.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanToggleAttach", ManualAttachExtension.inj_getCanToggleAttach)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanBeTurnedOn", ManualAttachExtension.inj_getCanBeTurnedOn)
end

function ManualAttachExtension.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", ManualAttachExtension)
    SpecializationUtil.registerEventListener(vehicleType, "onPostAttach", ManualAttachExtension)
end

function ManualAttachExtension.initSpecialization()
end

function ManualAttachExtension:onLoad(savegame)
end

function ManualAttachExtension:onLoadFinished(savegame)
end

function ManualAttachExtension:onPowerTakeOffChanged(isActive)
    local inputAttacherJoint = self:getActiveInputAttacherJoint()
    if inputAttacherJoint ~= nil then
        inputAttacherJoint.canBeTurnedOn = isActive
    end
end

function ManualAttachExtension.inj_getCanToggleAttach(vehicle, superFunc)
    if g_manualAttach ~= nil then
        return false
    end

    return superFunc(vehicle)
end

function ManualAttachExtension.inj_getCanBeTurnedOn(vehicle, superFunc)
    local inputAttacherJoint = vehicle:getActiveInputAttacherJoint()
    if inputAttacherJoint ~= nil
            and inputAttacherJoint.canBeTurnedOn ~= nil
            and not inputAttacherJoint.canBeTurnedOn then
        return false
    end

    return superFunc(vehicle)
end

function ManualAttachExtension:handlePowerTakeOffPostAttach(jointDescIndex)
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

function ManualAttachExtension:onPostAttach(attacherVehicle, inputJointDescIndex, jointDescIndex)
    if g_manualAttach ~= nil then
        if attacherVehicle.detachPowerTakeOff ~= nil then
            local implement = attacherVehicle:getImplementByObject(self)
            attacherVehicle:detachPowerTakeOff(attacherVehicle, implement)
            self:onPowerTakeOffChanged(false)
        end
    end
end
