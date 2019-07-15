---
-- ManualAttachDetectionHandler
--
-- Main class for handling the vehicle detection.
--
-- Copyright (c) Wopster, 2019

---@class ManualAttachDetectionHandler @parent class
ManualAttachDetectionHandler = {}

---@type number The clear timer threshold in MS.
ManualAttachDetectionHandler.CLEAR_TIME_THRESHOLD = 5000 --ms

local ManualAttachDetectionHandler_mt = Class(ManualAttachDetectionHandler)

---Creates a new instance of ManualAttachDetectionHandler.
---@param isServer boolean
---@param isClient boolean
---@param mission table
---@param modDirectory string
---@return ManualAttachDetectionHandler returns ManualAttachDetectionHandler instance
function ManualAttachDetectionHandler:new(isServer, isClient, mission, modDirectory)
    local self = setmetatable({}, ManualAttachDetectionHandler_mt)

    self.isServer = isServer
    self.isClient = isClient
    self.mission = mission
    self.modDirectory = modDirectory

    self.lastDetectedTime = 0
    self.lastDetectedVehicle = nil
    self.triggerCloneNode = nil
    self.detectedVehiclesInTrigger = {}
    self.detectedVehiclesOnLeaveTimes = {}
    self.listeners = {}

    return self
end

---Called on load.
---@param player table the current player
function ManualAttachDetectionHandler:load(player)
    self:loadCloneableTrigger()
    -- Add trigger on initial load.
    self:addTrigger(player)
end

---Called on delete.
function ManualAttachDetectionHandler:delete()
    delete(self.triggerCloneNode)
end

---Main update function called every frame.
---@param dt number
function ManualAttachDetectionHandler:update(dt)
    local lastAmount = #self.detectedVehiclesInTrigger
    local currentTime = self.mission.time
    if lastAmount ~= 0 and
        (currentTime - self.lastDetectedTime) > ManualAttachDetectionHandler.CLEAR_TIME_THRESHOLD then
        for vehicle, lastDetectedTime in pairs(self.detectedVehiclesOnLeaveTimes) do
            if (currentTime - lastDetectedTime) > ManualAttachDetectionHandler.CLEAR_TIME_THRESHOLD then
                if vehicle ~= self.lastDetectedVehicle then
                    ListUtil.removeElementFromList(self.detectedVehiclesInTrigger, vehicle)
                    self.detectedVehiclesOnLeaveTimes[vehicle] = nil -- GC
                end
            end
        end

        if lastAmount ~= #self.detectedVehiclesInTrigger then
            self:notifyVehicleListChanged(self.detectedVehiclesInTrigger)
        end
    end
end

---Adds listener from the list.
---@param listener table
function ManualAttachDetectionHandler:addDetectionListener(listener)
    if listener ~= nil then
        ListUtil.addElementToList(self.listeners, listener)
    end
end

---Removes listener from the list.
---@param listener table
function ManualAttachDetectionHandler:removeDetectionListener(listener)
    if listener ~= nil then
        ListUtil.removeElementFromList(self.listeners, listener)
    end
end

---Notifies listeners that the vehicle list has changed.
---@param vehicles table
function ManualAttachDetectionHandler:notifyVehicleListChanged(vehicles)
    for _, listener in ipairs(self.listeners) do
        listener:onVehicleListChanged(vehicles)
    end
end

---Notifies listeners that the trigger has been added or removed.
---@param isRemoved boolean
function ManualAttachDetectionHandler:notifyVehicleTriggerChange(isRemoved)
    for _, listener in ipairs(self.listeners) do
        listener:onTriggerChanged(isRemoved)
    end
end

---Ghost remove node to physics.
function ManualAttachDetectionHandler:onGhostRemove(nodeId)
    setVisibility(nodeId, false)
    removeFromPhysics(nodeId)
end

---Ghost add node to physics.
function ManualAttachDetectionHandler:onGhostAdd(nodeId)
    setVisibility(nodeId, true)
    addToPhysics(nodeId)
end

---Loads the trigger from the i3d file.
function ManualAttachDetectionHandler:loadCloneableTrigger()
    local filename = Utils.getFilename("resources/detectionTrigger.i3d", self.modDirectory)
    local rootNode = loadI3DFile(filename, false, false, false)
    local trigger = I3DUtil.indexToObject(rootNode, "0")

    unlink(trigger)
    delete(rootNode)

    self.triggerCloneNode = trigger
    link(getRootNode(), self.triggerCloneNode)
end

---Adds the trigger to the player.
---@param player table the current player
function ManualAttachDetectionHandler:addTrigger(player)
    if self.isClient and self.triggerCloneNode ~= nil and player == self.mission.player then
        player.manualAttachDetectionTrigger = clone(self.triggerCloneNode, false, false, false)
        local trigger = player.manualAttachDetectionTrigger

        -- Link trigger to player
        link(player.rootNode, trigger)
        setTranslation(trigger, 0, 0, -2.5)
        setRotation(trigger, 0, math.rad(25), 0)

        addTrigger(trigger, "vehicleDetectionCallback", self)

        self:onGhostAdd(trigger)
        self:notifyVehicleTriggerChange(false)
    end
end

---Disables the trigger from the player.
---@param player table the current player
function ManualAttachDetectionHandler:disableTrigger(player)
    if self.isClient and player == self.mission.player then
        local trigger = player.manualAttachDetectionTrigger

        self:onGhostRemove(trigger)
        self:notifyVehicleTriggerChange(true)

        self.lastDetectedTime = 0
        self.lastDetectedVehicle = nil
        self.detectedVehiclesInTrigger = {}
        self.detectedVehiclesOnLeaveTimes = {}
    end
end

---Removes the trigger from the player.
---@param player table the current player
function ManualAttachDetectionHandler:removeTrigger(player)
    if self.isClient and player == self.mission.player then
        local trigger = player.manualAttachDetectionTrigger
        if trigger ~= nil then
            removeTrigger(trigger)
            delete(trigger)
            player.manualAttachDetectionTrigger = nil
        end
    end
end

---Checks if the detected vehicle is valid.
---@param vehicle table
---@return boolean true if valid, false otherwise.
function ManualAttachDetectionHandler.getIsValidVehicle(vehicle)
    return vehicle ~= nil
        and vehicle.isa ~= nil
        and vehicle:isa(Vehicle)
        and not vehicle:isa(StationCrane) -- Dismiss the station cranes
        and not SpecializationUtil.hasSpecialization(SplineVehicle, vehicle.specializations)
        and (SpecializationUtil.hasSpecialization(AttacherJoints, vehicle.specializations)
        or SpecializationUtil.hasSpecialization(Attachable, vehicle.specializations))
end

---Checks if the given vehicle has attacherJoints.
---@param vehicle table
---@return boolean Returns true when the given vehicle has actual attacherJoints in the table, false otherwise.
function ManualAttachDetectionHandler.getHasAttacherJoints(vehicle)
    return vehicle.getAttacherJoints ~= nil and next(vehicle:getAttacherJoints()) ~= nil
end

---Callback when trigger changes state.
---@param triggerId number
---@param otherId number
---@param onEnter boolean
---@param onLeave boolean
---@param onStay boolean
function ManualAttachDetectionHandler:vehicleDetectionCallback(triggerId, otherId, onEnter, onLeave, onStay)
    if (onEnter or onLeave) then
        local lastAmount = #self.detectedVehiclesInTriggerk
        local nodeVehicle = self.mission:getNodeObject(otherId)

        if ManualAttachDetectionHandler.getIsValidVehicle(nodeVehicle) then
            self.lastDetectedTime = self.mission.time
            -- Only save the last vehicle with attacher joints.
            if ManualAttachDetectionHandler.getHasAttacherJoints(nodeVehicle) then
                self.lastDetectedVehicle = nodeVehicle
            end

            if onEnter then
                if not ListUtil.hasListElement(self.detectedVehiclesInTrigger, nodeVehicle) then
                    ListUtil.addElementToList(self.detectedVehiclesInTrigger, nodeVehicle)
                end

                if nodeVehicle.getAttacherVehicle ~= nil then
                    local attacherVehicle = nodeVehicle:getAttacherVehicle()
                    if attacherVehicle ~= nil and not ListUtil.hasListElement(self.detectedVehiclesInTrigger, attacherVehicle) then
                        ListUtil.addElementToList(self.detectedVehiclesInTrigger, attacherVehicle)
                    end
                end

                if nodeVehicle.getAttachedImplements ~= nil then
                    for _, implement in pairs(nodeVehicle:getAttachedImplements()) do
                        local object = implement.object
                        if object ~= nil then
                            if not ListUtil.hasListElement(self.detectedVehiclesInTrigger, object) then
                                ListUtil.addElementToList(self.detectedVehiclesInTrigger, object)
                            end
                        end
                    end
                end
            else
                self.detectedVehiclesOnLeaveTimes[nodeVehicle] = self.lastDetectedTime
            end
        end

        if lastAmount ~= #self.detectedVehiclesInTrigger then
            self:notifyVehicleListChanged(self.detectedVehiclesInTrigger)
        end
    end
end
