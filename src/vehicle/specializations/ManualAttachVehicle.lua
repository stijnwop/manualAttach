--
-- ManualAttachVehicle
--
-- Author: Wopster
-- Description: AttacherJoints extension for Manual Attach.
-- Name: ManualAttachVehicle
-- Hide: yes
--
-- Copyright (c) Wopster

---@class ManualAttachVehicle
ManualAttachVehicle = {}

function ManualAttachVehicle.prerequisitesPresent(specializations): boolean
    return SpecializationUtil.hasSpecialization(AttacherJoints, specializations)
end

function ManualAttachVehicle.registerOverwrittenFunctions(vehicleType): ()
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanToggleAttach", ManualAttachVehicle.inj_getCanToggleAttach)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "attachImplementFromInfo", ManualAttachVehicle.inj_attachImplementFromInfo)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "loadAttacherJointFromXML", ManualAttachVehicle.inj_loadAttacherJointFromXML)
end

function ManualAttachVehicle.registerEventListeners(vehicleType): ()
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", ManualAttachVehicle)
end

function ManualAttachVehicle:onDelete(): ()
    local spec = self.spec_attacherJoints
    if spec == nil then
        return
    end

    if self.isClient and spec.attacherJoints ~= nil then
        for _, jointDesc in pairs(spec.attacherJoints) do
            g_soundManager:deleteSample(jointDesc.sampleAttachHoses)
            g_soundManager:deleteSample(jointDesc.sampleAttachPto)
        end
    end
end

---
--- Injections
---

---Handles setting the default lowered state for attached implements by vanilla attach events.
function ManualAttachVehicle:inj_attachImplementFromInfo(superFunc, info)
    if info.attachable ~= nil then
        local attacherJoints = info.attacherVehicle.spec_attacherJoints.attacherJoints
        local jointDesc = attacherJoints[info.attacherVehicleJointDescIndex]
        local isFoldMiddleAllowed = info.attachable:getIsFoldMiddleAllowed()
        attacherJoints[info.attacherVehicleJointDescIndex].isDefaultLowered = jointDesc.allowsLowering and not isFoldMiddleAllowed
    end

    return superFunc(self, info)
end

---Checks whether or not the vehicle can perform an attach.
function ManualAttachVehicle:inj_getCanToggleAttach(superFunc): boolean
    local manualAttach: ManualAttach = g_manualAttach
    local isManualControl = manualAttach:isPlayerControllingVehicle()
    if isManualControl then
        return manualAttach:isCurrentVehicleManual()
    end

    return not isManualControl and superFunc(self)
end

---Load hose and pto samples on the attacherJoint.
function ManualAttachVehicle:inj_loadAttacherJointFromXML(superFunc, attacherJoint, xmlFile, baseName, index): boolean
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

    local isManualJointDesc = xmlFile:getBool(baseName .. "#isManual")
    if isManualJointDesc ~= nil then
        attacherJoint.isManual = isManualJointDesc
    end

    local isAutoJointDesc = xmlFile:getBool(baseName .. "#isAuto")
    if isAutoJointDesc ~= nil then
        attacherJoint.isAuto = isAutoJointDesc
    end

    return true
end
