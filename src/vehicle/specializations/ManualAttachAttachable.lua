--
-- ManualAttachAttachable
--
-- Author: Wopster
-- Description: Attachable extension for Manual Attach.
-- Name: ManualAttachAttachable
-- Hide: yes
--
-- Copyright (c) Wopster

---@class ManualAttachAttachable
ManualAttachAttachable = {}

function ManualAttachAttachable.prerequisitesPresent(specializations): boolean
    return SpecializationUtil.hasSpecialization(Attachable, specializations)
end

function ManualAttachAttachable.registerOverwrittenFunctions(vehicleType): ()
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "isDetachAllowed", ManualAttachAttachable.inj_isDetachAllowed)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "loadInputAttacherJoint", ManualAttachAttachable.inj_loadInputAttacherJoint)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getAllowsLowering", ManualAttachAttachable.inj_getAllowsLowering)
end

---
--- Injections.
---

---Fix for vanilla workmode logic
function ManualAttachAttachable.inj_getAllowsLowering(vehicle, superFunc): (boolean, string?)
    local allowLowering, warning = superFunc(vehicle)

    local spec = vehicle.spec_workMode
    if spec == nil then
        return allowLowering, warning
    end

    -- Only allow lowering when we have workmodes with lowering animations, else it will block lowering for implements without workmodes lowering animations.
    if spec.workModes ~= nil and #spec.workModes > 0 then
        local hasLoweringAnimations = #spec.workModes[spec.state].loweringAnimations > 0
        if not allowLowering and hasLoweringAnimations then
            return true, nil
        end
    end

    return allowLowering, warning
end

function ManualAttachAttachable:inj_isDetachAllowed(superFunc): (boolean, string?, boolean)
    local manualAttach: ManualAttach = g_manualAttach
    local isManualControl = manualAttach:isPlayerControllingVehicle()
    if isManualControl and not self:getIsAIActive() then
        if self.getAttacherVehicle ~= nil then
            local vehicle = self:getAttacherVehicle()

            if vehicle ~= nil and manualAttach:isVehicleAttachableManual(vehicle, self) then
                local jointDesc = vehicle:getAttacherJointDescFromObject(self)
                local detachAllowed, warning, showWarning = superFunc(self)

                if not detachAllowed then
                    return detachAllowed, warning, showWarning
                end

                local warningKey, warningArg = nil, nil
                detachAllowed, warningKey, warningArg = ManualAttach.isDetachAllowedForManualHandling(self, vehicle, jointDesc)

                if not detachAllowed and warningKey then
                    warning = g_i18n:getText(warningKey):format(warningArg)
                end

                return detachAllowed, warning, showWarning
            end
        end

        return false, nil, false
    end

    return superFunc(self)
end

function ManualAttachAttachable:inj_loadInputAttacherJoint(superFunc, xmlFile, key, inputAttacherJoint, index): boolean
    if not superFunc(self, xmlFile, key, inputAttacherJoint, index) then
        return false
    end

    local isManualJointDesc = xmlFile:getBool(key .. "#isManual")
    if isManualJointDesc ~= nil then
        inputAttacherJoint.isManual = isManualJointDesc
    end

    local isAutoJointDesc = xmlFile:getBool(key .. "#isAuto")
    if isAutoJointDesc ~= nil then
        inputAttacherJoint.isAuto = isAutoJointDesc
    end

    return true
end
