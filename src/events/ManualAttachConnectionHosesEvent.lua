---
-- ManualAttachConnectionHosesEvent
--
-- Event for handling the attach/detach for connection hoses.
--
-- Copyright (c) Wopster, 2019

---@class ManualAttachConnectionHosesEvent
---@field public manualAttach ManualAttach
ManualAttachConnectionHosesEvent = {}

local ManualAttachConnectionHosesEvent_mt = Class(ManualAttachConnectionHosesEvent, Event)

InitEventClass(ManualAttachConnectionHosesEvent, 'ManualAttachConnectionHosesEvent')

---@return ManualAttachConnectionHosesEvent
function ManualAttachConnectionHosesEvent:emptyNew()
    local self = Event:new(ManualAttachConnectionHosesEvent_mt)

    self.manualAttach = g_manualAttach

    return self
end

function ManualAttachConnectionHosesEvent:new(vehicle, object, doAttach)
    local self = ManualAttachConnectionHosesEvent:emptyNew()

    self.vehicle = vehicle
    self.object = object
    self.doAttach = doAttach

    return self
end

function ManualAttachConnectionHosesEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    NetworkUtil.writeNodeObject(streamId, self.object)
    streamWriteBool(streamId, self.doAttach)
end

function ManualAttachConnectionHosesEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.object = NetworkUtil.readNodeObject(streamId)
    self.doAttach = streamReadBool(streamId)

    self:run(connection)
end

function ManualAttachConnectionHosesEvent:run(connection)
    if self.doAttach then
        self.manualAttach:attachDynamicHoses(self.vehicle, self.object, true)
    else
        self.manualAttach:detachDynamicHoses(self.vehicle, self.object, true)
    end

    if not connection:getIsServer() then
        g_server:broadcastEvent(self, false, connection, self.vehicle)
    end
end

function ManualAttachConnectionHosesEvent.sendEvent(vehicle, object, doAttach, noEventSend)
    if noEventSend == nil or not noEventSend then
        if g_server ~= nil then
            g_server:broadcastEvent(ManualAttachConnectionHosesEvent:new(vehicle, object, doAttach), nil, nil, vehicle)
        else
            g_client:getServerConnection():sendEvent(ManualAttachConnectionHosesEvent:new(vehicle, object, doAttach))
        end
    end
end
