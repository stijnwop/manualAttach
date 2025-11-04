--
-- ConnectionHosesAttachment
--
-- Author: Wopster
-- Description: Handles connection hoses connect/disconnect operations
-- Name: ConnectionHosesAttachment
-- Hide: yes
--
-- Copyright (c) Wopster

---@class ConnectionHosesAttachment
ConnectionHosesAttachment = {}
local ConnectionHosesAttachment_mt = Class(ConnectionHosesAttachment, BaseAttachment)

export type ConnectionHosesAttachment = typeof(setmetatable({} :: BaseAttachmentData, ConnectionHosesAttachment_mt))

---
--- Private Functions
---

---Check if connection hoses can be connected
local function canConnectHoses(attacherVehicle: Vehicle?, attachable: Vehicle?): boolean
    if attacherVehicle == nil or attachable == nil then
        return false
    end

    -- Check if both vehicles support connection hoses
    if not ConnectionHosesExtension.hasConnectionHoses(attachable, attacherVehicle) then
        return false
    end

    -- Check if not already attached
    return not ConnectionHosesExtension.hasAttachedConnectionHoses(attachable)
end

---Check if connection hoses can be disconnected
local function canDisconnectHoses(attacherVehicle: Vehicle?, attachedImplement: Vehicle?): boolean
    if attacherVehicle == nil or attachedImplement == nil then
        return false
    end

    -- Check if hoses are currently attached
    return ConnectionHosesExtension.hasAttachedConnectionHoses(attachedImplement)
end

---Attaches the connection hoses from the given object to the vehicle
function ConnectionHosesAttachment:attachConnectionHoses(vehicle: Vehicle, object: Vehicle, noEventSend: boolean): ()
    ManualAttachConnectionHosesEvent.sendEvent(vehicle, object, true, noEventSend)

    local implement = vehicle:getImplementByObject(object)
    local inputJointDescIndex = object.spec_attachable.inputAttacherJointDescIndex
    local jointDescIndex = implement.jointDescIndex

    object:connectHosesToAttacherVehicle(vehicle, inputJointDescIndex, jointDescIndex)
    object:connectCustomHosesToAttacherVehicle(vehicle, inputJointDescIndex, jointDescIndex)

    object:updateAttachedConnectionHoses(vehicle) -- update once

    local jointDesc = vehicle:getAttacherJointByJointDescIndex(jointDescIndex)
    object:playHoseAttachSound(jointDesc)
end

---Detaches the connection hoses from the given object from the vehicle
function ConnectionHosesAttachment:detachConnectionHoses(vehicle: Vehicle, object: Vehicle, noEventSend: boolean): ()
    ManualAttachConnectionHosesEvent.sendEvent(vehicle, object, false, noEventSend)

    object:disconnectHoses(vehicle)

    local implement = vehicle:getImplementByObject(object)
    local jointDesc = vehicle:getAttacherJointByJointDescIndex(implement.jointDescIndex)
    object:playHoseAttachSound(jointDesc)
end

---
--- Public Methods
---

---Creates a new ConnectionHosesAttachment instance.
function ConnectionHosesAttachment.new(mission: FSBaseMission, i18n: I18N): ConnectionHosesAttachment
    return BaseAttachment.new(mission, i18n, ContextActionDisplay.CONTEXT_ICON.ATTACH, ConnectionHosesAttachment_mt)
end

function ConnectionHosesAttachment:canPerformAttachment(attacherVehicle: Vehicle?, attachable: Vehicle?): boolean
    return canConnectHoses(attacherVehicle, attachable)
end

function ConnectionHosesAttachment:canPerformDetachment(attacherVehicle: Vehicle?, attachedImplement: Vehicle?): boolean
    return canDisconnectHoses(attacherVehicle, attachedImplement)
end

function ConnectionHosesAttachment:performAttachment(_, _, attachedImplement: Vehicle?, _, _, playerCanPerformManualAttachment: boolean): ()
    local self = self :: ConnectionHosesAttachment

    if attachedImplement == nil or not playerCanPerformManualAttachment then
        return
    end

    local attacherVehicle = attachedImplement:getAttacherVehicle()

    if self:canPerformAttachment(attacherVehicle, attachedImplement) then
        self:attachConnectionHoses(attacherVehicle, attachedImplement)
        return
    end

    if self:canPerformDetachment(attacherVehicle, attachedImplement) then
        self:detachConnectionHoses(attacherVehicle, attachedImplement)
    end
end

function ConnectionHosesAttachment:getActionEventInfo(_, _, attachedImplement: Vehicle?, _, playerCanPerformManualAttachment: boolean): ActionEventInfo
    local self = self :: ConnectionHosesAttachment

    local info = {
        id = self.inputActionEventId,
        text = nil,
        priority = GS_PRIO_VERY_LOW,
        visibility = false,
        isExtraInfo = true,
    }

    if attachedImplement == nil or not playerCanPerformManualAttachment then
        return info
    end

    local attacherVehicle = attachedImplement:getAttacherVehicle()

    -- Connect hoses action
    if self:canPerformAttachment(attacherVehicle, attachedImplement) then
        info.text = self.i18n:getText("action_attach_hose")
        info.priority = GS_PRIO_HIGH
        info.visibility = true
        return info
    end

    -- Disconnect hoses action
    if self:canPerformDetachment(attacherVehicle, attachedImplement) then
        info.text = self.i18n:getText("action_detach_hose")
        info.priority = GS_PRIO_HIGH
        info.visibility = true
    end

    return info
end
