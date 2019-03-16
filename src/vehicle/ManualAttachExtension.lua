ManualAttachExtension = {}

function ManualAttachExtension.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Attachable, specializations) or
            SpecializationUtil.hasSpecialization(AttacherJoints, specializations)
end

function ManualAttachExtension.registerEvents(vehicleType)
end

function ManualAttachExtension.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "disconnectHoses", ManualAttachExtension.disconnectHoses)
    SpecializationUtil.registerFunction(vehicleType, "handlePowerTakeOffPostAttach", ManualAttachExtension.handlePowerTakeOffPostAttach)
end

function ManualAttachExtension.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanToggleAttach", ManualAttachExtension.inj_getCanToggleAttach)
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

function ManualAttachExtension.inj_getCanToggleAttach(superFunc, vehicle)
    if g_manualAttach ~= nil then
        return false
    end

    return superFunc(vehicle)
end

function ManualAttachExtension:disconnectHoses(attacherVehicle)
    local spec = self.spec_connectionHoses
    if spec ~= nil then
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
        end

        self:disconnectHoses(attacherVehicle)
    end
end