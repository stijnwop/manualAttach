--
-- ManualAttachPowerTakeOffEvent
--
-- Author: Wopster
-- Description: Event for handling the attach/detach for power take offs.
-- Name: ManualAttachPowerTakeOffEvent
-- Hide: yes
--
-- Copyright (c) Wopster

---@class ManualAttachPowerTakeOffEvent
ManualAttachPowerTakeOffEvent = {}

local ManualAttachPowerTakeOffEvent_mt = Class(ManualAttachPowerTakeOffEvent, Event)

type ManualAttachPowerTakeOffEventData = {
    manualAttach: ManualAttach,

    vehicle: Vehicle,
    object: Vehicle,
    doAttach: boolean,
}

export type ManualAttachPowerTakeOffEvent = typeof(setmetatable({} :: ManualAttachPowerTakeOffEventData, ManualAttachPowerTakeOffEvent_mt))

InitEventClass(ManualAttachPowerTakeOffEvent, "ManualAttachPowerTakeOffEvent")

function ManualAttachPowerTakeOffEvent.emptyNew(): ManualAttachPowerTakeOffEvent
    local self = Event.new(ManualAttachPowerTakeOffEvent_mt)

    self.manualAttach = g_manualAttach

    return self
end

function ManualAttachPowerTakeOffEvent.new(vehicle, object, doAttach): ManualAttachPowerTakeOffEvent
    local self = ManualAttachPowerTakeOffEvent.emptyNew()

    self.vehicle = vehicle
    self.object = object
    self.doAttach = doAttach

    return self
end

function ManualAttachPowerTakeOffEvent:writeStream(streamId, connection): ()
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    NetworkUtil.writeNodeObject(streamId, self.object)
    streamWriteBool(streamId, self.doAttach)
end

function ManualAttachPowerTakeOffEvent:readStream(streamId, connection): ()
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.object = NetworkUtil.readNodeObject(streamId)
    self.doAttach = streamReadBool(streamId)

    self:run(connection)
end

function ManualAttachPowerTakeOffEvent:run(connection): ()
    local self = self :: ManualAttachPowerTakeOffEvent

    if self.doAttach then
        self.manualAttach:attachPowerTakeOff(self.vehicle, self.object, true)
    else
        self.manualAttach:detachPowerTakeOff(self.vehicle, self.object, true)
    end

    if not connection:getIsServer() then
        g_server:broadcastEvent(self, false, connection, self.vehicle)
    end
end

function ManualAttachPowerTakeOffEvent.sendEvent(vehicle, object, doAttach, noEventSend): ()
    if noEventSend == nil or not noEventSend then
        if g_server ~= nil then
            g_server:broadcastEvent(ManualAttachPowerTakeOffEvent.new(vehicle, object, doAttach), nil, nil, vehicle)
        else
            g_client:getServerConnection():sendEvent(ManualAttachPowerTakeOffEvent.new(vehicle, object, doAttach))
        end
    end
end
