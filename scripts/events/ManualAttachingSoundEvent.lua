--
--	Manual Attaching: Sound Event
--
--	@author: 	 Wopster
--	@descripion: This script enforces you to attach/detach tools and trailers manually. 
--	@history:	 v1.0 - 2017-1-31 - Initial implementation
--

ManualAttachingSoundEvent = {}
ManualAttachingSoundEvent_mt = Class(ManualAttachingSoundEvent, Event)

InitEventClass(ManualAttachingSoundEvent, 'ManualAttachingSoundEvent')

function ManualAttachingSoundEvent:emptyNew()
    local self = Event:new(ManualAttachingSoundEvent_mt)

    return self
end

function ManualAttachingSoundEvent:new(vehicle, jointDesc, player)
    local self = ManualAttachingSoundEvent:emptyNew()

    self.vehicle = vehicle
    self.jointDesc = jointDesc
    self.player = player

    return self
end

function ManualAttachingSoundEvent:writeStream(streamId, connection)
    writeNetworkNodeObject(streamId, self.vehicle)
    writeNetworkNodeObject(streamId, self.jointDesc)
    writeNetworkNodeObject(streamId, self.player)
end

function ManualAttachingSoundEvent:readStream(streamId, connection)
    self.vehicle = readNetworkNodeObject(streamId)
    self.jointDesc = readNetworkNodeObject(streamId)
    self.player = readNetworkNodeObject(streamId)

    self:run(connection)
end

function ManualAttachingSoundEvent:run(connection)
    g_currentMission.callbackManualAttaching:playSound(self.vehicle, self.jointDesc, self.player, true)

    if not connection:getIsServer() then
        g_server:broadcastEvent(ManualAttachingSoundEvent:new(self.vehicle, self.jointDesc, self.player), nil, connection, self.vehicle)
    end
end

function ManualAttachingSoundEvent.sendEvent(vehicle, jointDesc, player, noEventSend)
    if noEventSend == nil or noEventSend == false then
        if g_server ~= nil then
            g_server:broadcastEvent(ManualAttachingSoundEvent:new(vehicle, jointDesc, player), nil, nil, vehicle)
        else
            g_client:getServerConnection():sendEvent(ManualAttachingSoundEvent:new(vehicle, jointDesc, player))
        end
    end
end