--
-- PowerTakeOffAttachment
--
-- Author: Wopster
-- Description: Handles power take-off (PTO) connect/disconnect operations
-- Name: PowerTakeOffAttachment
-- Hide: yes
--
-- Copyright (c) Wopster

---@class PowerTakeOffAttachment
PowerTakeOffAttachment = {}
local PowerTakeOffAttachment_mt = Class(PowerTakeOffAttachment, BaseAttachment)

export type PowerTakeOffAttachment = typeof(setmetatable({} :: BaseAttachmentData, PowerTakeOffAttachment_mt))

---
--- Private Functions
---

---Check if PTO can be connected
local function canConnectPTO(attacherVehicle: Vehicle?, attachable: Vehicle?): boolean
    if attacherVehicle == nil or attachable == nil then
        return false
    end

    -- Check if both vehicles support PTO
    if not PowerTakeOffExtension.hasPowerTakeOffs(attachable, attacherVehicle) then
        return false
    end

    -- Check if not already attached
    return not PowerTakeOffExtension.hasAttachedPowerTakeOffs(attachable, attacherVehicle)
end

---Check if PTO can be disconnected
local function canDisconnectPTO(attacherVehicle: Vehicle?, attachedImplement: Vehicle?): boolean
    if attacherVehicle == nil or attachedImplement == nil then
        return false
    end

    -- Check if PTO is currently attached
    return PowerTakeOffExtension.hasAttachedPowerTakeOffs(attachedImplement, attacherVehicle)
end

---Attaches the PTO from the given object to the vehicle
function PowerTakeOffAttachment:attachPowerTakeOff(vehicle: Vehicle, object: Vehicle, noEventSend: boolean): ()
    ManualAttachPowerTakeOffEvent.sendEvent(vehicle, object, true, noEventSend)

    local implement = vehicle:getImplementByObject(object)
    if implement == nil then
        return
    end

    local inputJointDescIndex = object.spec_attachable.inputAttacherJointDescIndex
    local jointDescIndex = implement.jointDescIndex

    vehicle:attachPowerTakeOff(object, inputJointDescIndex, jointDescIndex)
    vehicle:handlePowerTakeOffPostAttach(jointDescIndex)

    local jointDesc = vehicle:getAttacherJointByJointDescIndex(jointDescIndex)
    vehicle:playPtoAttachSound(jointDesc)
end

---Detaches the PTO from the given object from the vehicle
function PowerTakeOffAttachment:detachPowerTakeOff(vehicle: Vehicle, object: Vehicle, noEventSend: boolean): ()
    ManualAttachPowerTakeOffEvent.sendEvent(vehicle, object, false, noEventSend)

    local implement = vehicle:getImplementByObject(object)
    if implement == nil then
        return
    end

    vehicle:detachPowerTakeOff(vehicle, implement)

    local jointDesc = vehicle:getAttacherJointByJointDescIndex(implement.jointDescIndex)
    vehicle:playPtoAttachSound(jointDesc)
end

---
--- Public Methods
---

---Creates a new PowerTakeOffAttachment instance.
function PowerTakeOffAttachment.new(mission: FSBaseMission, i18n: I18N): PowerTakeOffAttachment
    return BaseAttachment.new(mission, i18n, ContextActionDisplay.CONTEXT_ICON.ATTACH, PowerTakeOffAttachment_mt)
end

function PowerTakeOffAttachment:canPerformAttachment(attacherVehicle: Vehicle?, attachable: Vehicle?): boolean
    return canConnectPTO(attacherVehicle, attachable)
end

function PowerTakeOffAttachment:canPerformDetachment(attacherVehicle: Vehicle?, attachedImplement: Vehicle?): boolean
    return canDisconnectPTO(attacherVehicle, attachedImplement)
end

function PowerTakeOffAttachment:performAttachment(_, _, attachedImplement: Vehicle?, _, _, playerCanPerformManualAttachment: boolean): ()
    local self = self :: PowerTakeOffAttachment

    if attachedImplement == nil or not playerCanPerformManualAttachment then
        return
    end

    local attacherVehicle = attachedImplement:getAttacherVehicle()

    if self:canPerformAttachment(attacherVehicle, attachedImplement) then
        self:attachPowerTakeOff(attacherVehicle, attachedImplement)
        return
    end

    if self:canPerformDetachment(attacherVehicle, attachedImplement) then
        self:detachPowerTakeOff(attacherVehicle, attachedImplement)
    end
end

function PowerTakeOffAttachment:getActionEventInfo(_, _, attachedImplement: Vehicle?, _, playerCanPerformManualAttachment: boolean): ActionEventInfo
    local self = self :: PowerTakeOffAttachment

    local info = {
        id = self.inputActionEventId,
        text = nil,
        priority = GS_PRIO_VERY_LOW,
        visibility = false,
        isExtraInfo = false,
    }

    if attachedImplement == nil or not playerCanPerformManualAttachment then
        return info
    end

    local attacherVehicle = attachedImplement:getAttacherVehicle()

    if self:canPerformAttachment(attacherVehicle, attachedImplement) then
        info.text = self.i18n:getText("action_attach_pto")
        info.priority = GS_PRIO_HIGH
        info.visibility = true
        return info
    end

    if self:canPerformDetachment(attacherVehicle, attachedImplement) then
        info.text = self.i18n:getText("action_detach_pto")
        info.priority = GS_PRIO_HIGH
        info.visibility = true
    end

    return info
end
