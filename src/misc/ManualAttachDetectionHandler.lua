ManualAttachDetectionHandler = {}

local ManualAttachDetectionHandler_mt = Class(ManualAttachDetectionHandler)

function ManualAttachDetectionHandler:new(isServer, isClient, modDirectory)
    local instance = setmetatable({}, ManualAttachDetectionHandler_mt)

    instance.isServer = isServer
    instance.isClient = isClient
    instance.modDirectory = modDirectory
    instance.detectedVehicleInTrigger = {}
    instance.listeners = {}

    Player.onEnter = Utils.appendedFunction(Player.onEnter, ManualAttachDetectionHandler.inj_onEnter)
    Player.onLeave = Utils.appendedFunction(Player.onLeave, ManualAttachDetectionHandler.inj_onLeave)

    return instance
end

function ManualAttachDetectionHandler.inj_onEnter(player, isControlling)
    if isControlling then
        g_manualAttach.detectionHandler:loadTrigger()
    end
end

function ManualAttachDetectionHandler.inj_onLeave(player)
    g_manualAttach.detectionHandler:unloadTrigger()
end

function ManualAttachDetectionHandler:load()
end

function ManualAttachDetectionHandler:delete()
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

function ManualAttachDetectionHandler:notifyVehicleListChanged(vehicles)
    for _, listener in ipairs(self.listeners) do
        listener:onVehicleListChanged(vehicles)
    end
end

function ManualAttachDetectionHandler:notifyVehicleTriggerChange(isRemoved)
    for _, listener in ipairs(self.listeners) do
        listener:onTriggerChanged(isRemoved)
    end
end

function ManualAttachDetectionHandler:loadTrigger()
    if self.isClient then
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

        self:notifyVehicleTriggerChange(false)
    end
end

function ManualAttachDetectionHandler:unloadTrigger()
    if self.isClient then
        self:notifyVehicleTriggerChange(true)

        if self.detectionTrigger ~= nil then
            removeFromPhysics(self.detectionTrigger)
            removeTrigger(self.detectionTrigger)
            delete(self.detectionTrigger)
            self.detectionTrigger = nil
        end


        self.detectedVehicleInTrigger = {}
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
            self:notifyVehicleListChanged(self.detectedVehicleInTrigger)
        end
    end
end