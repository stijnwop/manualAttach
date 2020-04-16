---
-- ManualAttachVehicle
--
-- AttacherJoints extension for Manual Attach.
--
-- Copyright (c) Wopster, 2019

ManualAttachVehicle = {}

function ManualAttachVehicle.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(AttacherJoints, specializations)
end

function ManualAttachVehicle.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanToggleAttach", ManualAttachVehicle.inj_getCanToggleAttach)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "loadAttacherJointFromXML", ManualAttachVehicle.loadAttacherJointFromXML)
end

---
--- Injections.
---

function ManualAttachVehicle.inj_getCanToggleAttach()
    return false
end

---Load hose and pto samples on the attacherJoint.
function ManualAttachVehicle:loadAttacherJointFromXML(superFunc, attacherJoint, xmlFile, baseName, index)
    if not superFunc(self, attacherJoint, xmlFile, baseName, index) then
        return false
    end

    if self.isClient then
        local sampleAttachHoses = g_soundManager:loadSampleFromXML(xmlFile, baseName, "attachHoses", self.baseDirectory, self.components, 1, AudioGroup.VEHICLE, self.i3dMappings, self)
        if sampleAttachHoses == nil then
            sampleAttachHoses = g_soundManager:cloneSample(g_manualAttach.samples.hosesAttach, attacherJoint.jointTransform, self)
        end

        attacherJoint.sampleAttachHoses = sampleAttachHoses

        local sampleAttachPto = g_soundManager:loadSampleFromXML(xmlFile, baseName, "attachPto", self.baseDirectory, self.components, 1, AudioGroup.VEHICLE, self.i3dMappings, self)
        if sampleAttachPto == nil then
            sampleAttachPto = g_soundManager:cloneSample(g_manualAttach.samples.ptoAttach, attacherJoint.jointTransform, self)
        end

        attacherJoint.sampleAttachPto = sampleAttachPto
    end

    return true
end
