--
--	Manual Attaching: PowerTakeOff Event
--
--	@author: 	 Wopster
--	@descripion: This script enforces you to attach/detach tools and trailers manually. 
--	@history:	 v1.0 - 2015-4-11 - Initial implementation
--

ManualAttachingPTOEvent = {}
ManualAttachingPTOEvent_mt = Class(ManualAttachingPTOEvent, Event)

InitEventClass(ManualAttachingPTOEvent, 'ManualAttachingPTOEvent')

function ManualAttachingPTOEvent:emptyNew()
    local self = Event:new(ManualAttachingPTOEvent_mt)
	
    return self
end

function ManualAttachingPTOEvent:new(vehicle, object, doAttach)
    local self = ManualAttachingPTOEvent:emptyNew()
	
    self.vehicle = vehicle
	self.object = object
	self.doAttach = doAttach
	
	return self
end

function ManualAttachingPTOEvent:writeStream(streamId, connection)
	writeNetworkNodeObject(streamId, self.vehicle)
	writeNetworkNodeObject(streamId, self.object)
	streamWriteBool(streamId, self.doAttach)
end

function ManualAttachingPTOEvent:readStream(streamId, connection)
    self.vehicle = readNetworkNodeObject(streamId)
    self.object = readNetworkNodeObject(streamId)
	self.doAttach = streamReadBool(streamId)
	
    self:run(connection)
end

function ManualAttachingPTOEvent:run(connection)
	if self.doAttach then
		g_currentMission.callbackManualAttaching:attachPowerTakeOff(self.vehicle, self.object, true)
	else
		g_currentMission.callbackManualAttaching:detachPowerTakeOff(self.vehicle, self.object, true)
	end
	
	if not connection:getIsServer() then
		g_server:broadcastEvent(ManualAttachingPTOEvent:new(self.vehicle, self.object, self.doAttach), nil, connection, self.vehicle)
	end
end

function ManualAttachingPTOEvent.sendEvent(vehicle, object, doAttach, noEventSend)
	if noEventSend == nil or noEventSend == false then
		if g_server ~= nil then
			g_server:broadcastEvent(ManualAttachingPTOEvent:new(vehicle, object, doAttach), nil, nil, vehicle)
		else
			g_client:getServerConnection():sendEvent(ManualAttachingPTOEvent:new(vehicle, object, doAttach))
		end
	end
end