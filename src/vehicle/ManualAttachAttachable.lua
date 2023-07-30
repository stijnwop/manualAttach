--
-- ManualAttachAttachable
--
-- Author: Wopster
-- Description: Attachable extension for Manual Attach.
-- Name: ManualAttachAttachable
-- Hide: yes
--
-- Copyright (c) Wopster, 2021

---@class ManualAttachAttachable
ManualAttachAttachable = {}

function ManualAttachAttachable.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Attachable, specializations)
end

function ManualAttachAttachable.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "isDetachAllowed", ManualAttachAttachable.isDetachAllowed)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "loadInputAttacherJoint", ManualAttachAttachable.loadInputAttacherJoint)
end

---
--- Injections.
---

function ManualAttachAttachable:isDetachAllowed(superFunc)
    if g_currentMission.manualAttach:canOperate()
        and not self:getIsAIActive() then
        if self.getAttacherVehicle ~= nil then
            local vehicle = self:getAttacherVehicle()
            if vehicle ~= nil and g_currentMission.manualAttach:canHandle(vehicle, self) then
                local jointDesc = vehicle:getAttacherJointDescFromObject(self)
                local detachAllowed, warning, showWarning = superFunc(self)

                if not detachAllowed then
                    return detachAllowed, warning, showWarning
                end

                detachAllowed, warning = g_currentMission.manualAttach:isDetachAllowedByManualAttach(self, vehicle, jointDesc)

                return detachAllowed, warning, showWarning
            end
        end

        return false, nil, false
    end

    return superFunc(self)
end

function ManualAttachAttachable:loadInputAttacherJoint(superFunc, xmlFile, key, inputAttacherJoint, index)
    if not superFunc(self, xmlFile, key, inputAttacherJoint, index) then
        return false
    end

    local isManualJointDesc = xmlFile:getBool(key .. "#isManual")
    if isManualJointDesc ~= nil then
        inputAttacherJoint.isManual = isManualJointDesc
    end

    return true
end
