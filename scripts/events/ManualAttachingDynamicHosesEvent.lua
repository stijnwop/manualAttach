--
--	Manual Attaching: DynamicHose Event
--
--	@author: 	 Wopster
--	@descripion: This script enforces you to attach/detach tools and trailers manually. 
--	@history:	 v1.0 - 2016-4-10 - Initial implementation
--

ManualAttachingDynamicHosesEvent = {}
ManualAttachingDynamicHosesEvent_mt = Class(ManualAttachingDynamicHosesEvent, Event)

InitEventClass(ManualAttachingDynamicHosesEvent, 'ManualAttachingDynamicHosesEvent')

function ManualAttachingDynamicHosesEvent:emptyNew()
    local self = Event:new(ManualAttachingDynamicHosesEvent_mt)

    return self
end

function ManualAttachingDynamicHosesEvent:new(attachable, vehicle, jointDescIndex, doAttach)
    local self = ManualAttachingDynamicHosesEvent:emptyNew()

    self.attachable = attachable
    self.vehicle = vehicle
    self.jointDescIndex = jointDescIndex
    self.doAttach = doAttach

    return self
end

function ManualAttachingDynamicHosesEvent:writeStream(streamId, connection)
    writeNetworkNodeObject(streamId, self.attachable)
    writeNetworkNodeObject(streamId, self.vehicle)
    streamWriteInt32(streamId, self.jointDescIndex)
    streamWriteBool(streamId, self.doAttach)
end

function ManualAttachingDynamicHosesEvent:readStream(streamId, connection)
    self.attachable = readNetworkNodeObject(streamId)
    self.vehicle = readNetworkNodeObject(streamId)
    self.jointDescIndex = streamReadInt32(streamId)
    self.doAttach = streamReadBool(streamId)

    self:run(connection)
end

function ManualAttachingDynamicHosesEvent:run(connection)
    if self.doAttach then
        g_currentMission.callbackManualAttaching:attachDynamicHoses(self.attachable, self.vehicle, self.jointDescIndex, true)
    else
        g_currentMission.callbackManualAttaching:detachDynamicHoses(self.attachable, self.vehicle, self.jointDescIndex, true)
    end

    if not connection:getIsServer() then
        g_server:broadcastEvent(ManualAttachingDynamicHosesEvent:new(self.attachable, self.vehicle, self.jointDescIndex, self.doAttach), nil, connection, self.attachable)
    end
end

function ManualAttachingDynamicHosesEvent.sendEvent(attachable, vehicle, jointDescIndex, doAttach, noEventSend)
    if noEventSend == nil or noEventSend == false then
        if g_server ~= nil then
            g_server:broadcastEvent(ManualAttachingDynamicHosesEvent:new(attachable, vehicle, jointDescIndex, doAttach), nil, nil, attachable)
        else
            g_client:getServerConnection():sendEvent(ManualAttachingDynamicHosesEvent:new(attachable, vehicle, jointDescIndex, doAttach))
        end
    end
end