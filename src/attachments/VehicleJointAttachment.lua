--
-- VehicleJointAttachment
--
-- Author: Wopster
-- Description: Handles vehicle attach/detach operations
-- Name: VehicleJointAttachment
-- Hide: yes
--
-- Copyright (c) Wopster

---@class VehicleJointAttachment
VehicleJointAttachment = {}
local VehicleJointAttachment_mt = Class(VehicleJointAttachment, BaseAttachment)

export type VehicleJointAttachment = typeof(setmetatable({} :: BaseAttachmentData, VehicleJointAttachment_mt))

---
--- Private Functions
---

---Check whether or not ManualAttach can detach the object.
local function isDetachAllowed(self: VehicleJointAttachment, implement, vehicle, jointDesc): (boolean, string, boolean)
    local detachAllowed, warning, showWarning = implement:isDetachAllowed()

    if not detachAllowed then
        return detachAllowed, warning, showWarning
    end

    local warningKey, warningArg = nil, nil
    detachAllowed, warningKey, warningArg = ManualAttach.isDetachAllowedForManualHandling(implement, vehicle, jointDesc)

    if not detachAllowed and warningKey then
        warning = self.i18n:getText(warningKey):format(warningArg)
    end

    return detachAllowed, warning, showWarning
end

function handleActivatedOnLoweredObject(implement, spec)
    if spec ~= nil and spec.activateOnLowering then
        if implement.setIsTurnedOn ~= nil then
            implement:setIsTurnedOn(false)
        else
            local attacherVehicle = implement:getAttacherVehicle()
            if attacherVehicle.setIsTurnedOn ~= nil then
                attacherVehicle:setIsTurnedOn(false)
            end
        end
    end
end

---Handles lowering the implement if needed after attachment.
local function handleLoweringIfNeeded(self: VehicleJointAttachment, vehicle: any, implement: any, jointDesc: any, jointDescIndex: number, forceLowering: boolean): ()
    if forceLowering then
        vehicle:setJointMoveDown(jointDescIndex, true, false)
    end

    local canBeLowered = implement:getAllowsLowering() and jointDesc.allowsLowering and not implement:getIsFoldMiddleAllowed()
    if not canBeLowered then
        return
    end

    handleActivatedOnLoweredObject(implement, implement.spec_sprayer)
end

---Handles the attachment of the implement and lowering if needed.
local function attachImplement(self: VehicleJointAttachment, vehicle: any, implement: any, inputJointDescIndex: number?, jointDescIndex: number?): ()
    if vehicle.spec_attacherJoints == nil or jointDescIndex == nil then
        return
    end

    local jointDesc = vehicle.spec_attacherJoints.attacherJoints[jointDescIndex]
    if jointDesc == nil or jointDesc.jointIndex ~= 0 then
        return
    end

    local startLowered = implement:getAllowsLowering() and jointDesc.allowsLowering and not implement:getIsFoldMiddleAllowed()
    vehicle:attachImplement(implement, inputJointDescIndex, jointDescIndex, false, nil, startLowered)
    handleLoweringIfNeeded(self, vehicle, implement, jointDesc, jointDescIndex, startLowered)
end

---Handles the detachment of the implement.
local function detachImplement(self: VehicleJointAttachment, attacherVehicle: any, implement: any): ()
    local jointDesc = attacherVehicle:getAttacherJointDescFromObject(implement)

    handleLoweringIfNeeded(self, attacherVehicle, implement, jointDesc, 0, false)

    local detachAllowed, warning, showWarning = isDetachAllowed(self, implement, attacherVehicle, jointDesc)
    if detachAllowed then
        attacherVehicle:detachImplementByObject(implement)
    elseif showWarning ~= false then
        self.mission:showBlinkingWarning(warning or self.i18n:getText("warning_detachNotAllowed"), ManualAttach.WARNING_TIMER_THRESHOLD)
    end
end

---
--- Public Methods
---

---Creates a new VehicleJointAttachment instance.
function VehicleJointAttachment.new(mission: FSBaseMission, i18n: I18N): VehicleJointAttachment
    return BaseAttachment.new(mission, i18n, ContextActionDisplay.CONTEXT_ICON.ATTACH, VehicleJointAttachment_mt)
end

function VehicleJointAttachment:canPerformAttachment(attacherVehicle: Vehicle?, attachable: Vehicle?, jointDescIndex: number?): boolean
    local self = self :: VehicleJointAttachment

    if attacherVehicle == nil or attachable == nil then
        return false
    end

    return self.mission.accessHandler:canFarmAccess(attacherVehicle:getActiveFarm(), attachable)
end

function VehicleJointAttachment:canPerformDetachment(attachedImplement: Vehicle?): boolean
    if attachedImplement == nil or attachedImplement.getAttacherVehicle == nil then
        return false
    end

    local attacherVehicle = attachedImplement:getAttacherVehicle()
    if attacherVehicle == nil then
        return false
    end

    return attachedImplement.isDetachAllowed == nil or attachedImplement:isDetachAllowed()
end

function VehicleJointAttachment:performAttachment(
    attacherVehicle: Vehicle?,
    attachable: Vehicle?,
    attachedImplement: Vehicle?,
    attacherJointDescIndex: number?,
    attachableJointDescIndex: number?,
    playerCanPerformManualAttachment: boolean
): ()
    local self = self :: VehicleJointAttachment

    -- Attach case
    if
        attacherVehicle ~= nil
        and attachable ~= nil
        and self:canPerformAttachment(attacherVehicle, attachable, attacherJointDescIndex)
        and ManualAttach.shouldHandleJoint(attacherVehicle, attachable, attacherJointDescIndex, playerCanPerformManualAttachment)
    then
        attachImplement(self, attacherVehicle, attachable, attachableJointDescIndex, attacherJointDescIndex)
        return
    end

    -- Detach case
    if attachedImplement == nil or attachedImplement.getAttacherVehicle == nil then
        return
    end

    local detachAttacherVehicle = attachedImplement:getAttacherVehicle()
    if
        detachAttacherVehicle == nil
        or not self:canPerformDetachment(attachedImplement)
        or not ManualAttach.shouldHandleJoint(detachAttacherVehicle, attachedImplement, nil, playerCanPerformManualAttachment)
    then
        return
    end

    detachImplement(self, detachAttacherVehicle, attachedImplement)
end

function VehicleJointAttachment:getActionEventInfo(
    attacherVehicle: Vehicle?,
    attachable: Vehicle?,
    attachedImplement: Vehicle?,
    jointDescIndex: number?,
    playerCanPerformManualAttachment: boolean
): ActionEventInfo
    local self = self :: VehicleJointAttachment

    local info = {
        id = self.inputActionEventId,
        text = nil,
        priority = GS_PRIO_VERY_LOW,
        visibility = false,
        isExtraInfo = false,
    }

    -- Attach action
    if
        self:canPerformAttachment(attacherVehicle, attachable, jointDescIndex)
        and ManualAttach.shouldHandleJoint(attacherVehicle, attachable, jointDescIndex, playerCanPerformManualAttachment)
    then
        info.text = self.i18n:getText("action_attach")
        info.priority = GS_PRIO_VERY_HIGH
        info.visibility = true
        return info
    end

    -- Detach action
    if self:canPerformDetachment(attachedImplement) then
        local detachAttacherVehicle = attachedImplement:getAttacherVehicle()

        if ManualAttach.shouldHandleJoint(detachAttacherVehicle, attachedImplement, nil, playerCanPerformManualAttachment) then
            info.text = self.i18n:getText("action_detach")
            info.priority = GS_PRIO_VERY_HIGH
            info.visibility = true
        end
    end

    return info
end

function VehicleJointAttachment:getContextInfo(
    attacherVehicle: Vehicle?,
    attachable: Vehicle?,
    attachedImplement: Vehicle?,
    jointDescIndex: number?,
    playerCanPerformManualAttachment: boolean
): (string?, number)
    local self = self :: VehicleJointAttachment

    if not ManualAttach.shouldHandleJoint(attacherVehicle, attachable, jointDescIndex, playerCanPerformManualAttachment) then
        return nil, 0
    end

    if self:canPerformAttachment(attacherVehicle, attachable, jointDescIndex) then
        return attachable:getUppercaseName(), HUD.CONTEXT_PRIORITY.LOW
    end

    return nil, 0
end
