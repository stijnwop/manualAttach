ManualAttachDetectionHandler = {}

local ManualAttachDetectionHandler_mt = Class(ManualAttachDetectionHandler)

function ManualAttachDetectionHandler:new(isServer, modDirectory)
    local instance = setmetatable({}, ManualAttachDetectionHandler_mt)

    instance.isServer = isServer
    instance.modDirectory = modDirectory
    instance.detectedVehicleInTrigger = {}
    instance.listeners = {}

    return instance
end

function ManualAttachDetectionHandler:load()
    self:loadTrigger()
end

function ManualAttachDetectionHandler:delete()
    self:unloadTrigger()
end

function ManualAttachDetectionHandler:addDetectionListener(listener)
    if listener ~= nil then
        ListUtil.addElementToList(self.listeners, listener)
    end
end

function ManualAttachDetectionHandler:removeDetectionListener(listener)
    if listener ~= nil then
        ListUtil.removeElementFromList(self.listeners, listener)
    end
end

function ManualAttachDetectionHandler:updateListeners(vehicles)
    for _, listener in ipairs(self.listeners) do
        listener:onVehicleListChanged(vehicles)
    end
end

function ManualAttachDetectionHandler:loadTrigger()
    local detectionTriggerFilename = Utils.getFilename("resources/detectionTrigger.i3d", self.modDirectory)
    local rootNode = loadI3DFile(detectionTriggerFilename, false, false, false)
    local detectionTrigger = I3DUtil.indexToObject(rootNode, "0")

    unlink(detectionTrigger)
    delete(rootNode)

    self.detectionTrigger = detectionTrigger
    addToPhysics(self.detectionTrigger)
    link(getRootNode(), self.detectionTrigger)

    -- Link trigger to player
    link(g_currentMission.player.rootNode, self.detectionTrigger)
    --setTranslation(self.detectionTrigger, 0, 0, 0)

    addTrigger(self.detectionTrigger, "vehicleDetectionCallback", self)
end

function ManualAttachDetectionHandler:unloadTrigger()
    if self.detectionTrigger ~= nil then
        removeFromPhysics(self.detectionTrigger)
        removeTrigger(self.detectionTrigger)
        delete(self.detectionTrigger)
        self.detectionTrigger = nil
    end
end

function ManualAttachDetectionHandler:update(dt)
end

function ManualAttachDetectionHandler.getIsValidVehicle(vehicle)
    return vehicle ~= nil
            and vehicle.isa ~= nil
            and vehicle:isa(Vehicle)
            and not vehicle:isa(StationCrane) -- Dismiss trains and the station cranes
            and vehicle.getAttacherJoints ~= nil
end

function ManualAttachDetectionHandler:vehicleDetectionCallback(triggerId, otherId, onEnter, onLeave, onStay)
    if (onEnter or onLeave) then
        local amount = #self.detectedVehicleInTrigger
        local nodeVehicle = g_currentMission:getNodeObject(otherId)

        if ManualAttachDetectionHandler.getIsValidVehicle(nodeVehicle) then
            if onEnter then
                if not ListUtil.hasListElement(self.detectedVehicleInTrigger, nodeVehicle) then
                    ListUtil.addElementToList(self.detectedVehicleInTrigger, nodeVehicle)
                    Logger.info("Vehicle added: ", tostring(nodeVehicle:getName()))
                end
            else
                ListUtil.removeElementFromList(self.detectedVehicleInTrigger, nodeVehicle)
            end

            Logger.info("Amount in trigger", #self.detectedVehicleInTrigger)
        end

        if amount ~= #self.detectedVehicleInTrigger then
            self:updateListeners(self.detectedVehicleInTrigger)
        end
    end
end