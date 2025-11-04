--
-- BaseAttachment
--
-- Author: Wopster
-- Description: Base class for attachment type handlers
-- Name: BaseAttachment
-- Hide: yes
--
-- Copyright (c) Wopster

---@class BaseAttachment
BaseAttachment = {}
local BaseAttachment_mt = Class(BaseAttachment)

type ActionEventInfo = {
    id: number?,
    text: string?,
    priority: number,
    visibility: boolean,
    isExtraInfo: boolean,
}

type BaseAttachmentData = {
    mission: FSBaseMission,
    i18n: I18N,
    contextIcon: number,
    inputActionEventId: number?,
}

export type BaseAttachment = typeof(setmetatable({} :: BaseAttachmentData, BaseAttachment_mt))

function BaseAttachment.new(mission: FSBaseMission, i18n: I18N, contextIcon: number, customMt: any): BaseAttachment
    local self = {}

    self.mission = mission
    self.i18n = i18n
    self.contextIcon = contextIcon
    self.inputActionEventId = nil

    return setmetatable(self :: BaseAttachmentData, customMt or BaseAttachment_mt)
end

function BaseAttachment:delete() end

---Check if this attachment type can be performed
function BaseAttachment:canPerformAttachment(attacherVehicle: Vehicle?, attachable: Vehicle?, jointDescIndex: number?): boolean
    return false -- Override in subclass
end

---Check if this detachment type can be performed
function BaseAttachment:canPerformDetachment(attachedImplement: Vehicle?): boolean
    return false -- Override in subclass
end

---Perform the attachment type
function BaseAttachment:performAttachment(
    attacherVehicle: Vehicle?,
    attachable: Vehicle?,
    attachedImplement: Vehicle?,
    attacherJointDescIndex: number?,
    attachableJointDescIndex: number?,
    playerCanPerformManualAttachment: boolean
)
    -- Override in subclass
end

---Get action event info (text, priority, visibility)
function BaseAttachment:getActionEventInfo(
    attacherVehicle: Vehicle?,
    attachable: Vehicle?,
    attachedImplement: Vehicle?,
    jointDescIndex: number?,
    playerCanPerformManualAttachment: boolean
): ActionEventInfo
    return {
        id = self.inputActionEventId,
        text = nil,
        priority = GS_PRIO_VERY_LOW,
        visibility = false,
        isExtraInfo = false,
    }
end

---Get context display info
function BaseAttachment:getContextInfo(
    attacherVehicle: Vehicle?,
    attachable: Vehicle?,
    attachedImplement: Vehicle?,
    jointDescIndex: number?,
    playerCanPerformManualAttachment: boolean
): (string?, number)
    return nil, 0 -- Override in subclass
end

function BaseAttachment:setInputActionEventId(actionEventId: number): ()
    self.inputActionEventId = actionEventId
end