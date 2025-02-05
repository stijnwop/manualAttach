--
-- ManualAttachDetectionHandler
--
-- Author: Wopster
-- Description: Main class for handling the vehicle detection.
-- Name: ManualAttachDetectionHandler
-- Hide: yes
--
-- Copyright (c) Wopster, 2021

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

    self.lastTrigger = nil
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
    if self.lastTrigger ~= nil then
        removeTrigger(self.lastTrigger)
        if entityExists(self.lastTrigger) then
            delete(self.lastTrigger)
        end
    end
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
                    table.removeElement(self.detectedVehiclesInTrigger, vehicle)
                    self.detectedVehiclesOnLeaveTimes[vehicle] = nil -- GC
                end
            end
        end

        if lastAmount ~= #self.detectedVehiclesInTrigger then
            self:notifyVehicleListChanged(self.detectedVehiclesInTrigger)
        end
    end
end

---Clears all detection values.
function ManualAttachDetectionHandler:clear()
    self.lastDetectedTime = 0
    self.lastDetectedVehicle = nil
    self.detectedVehiclesInTrigger = {}
    self.detectedVehiclesOnLeaveTimes = {}
    self:notifyVehicleListChanged(self.detectedVehiclesInTrigger)
end

---Adds listener from the list.
---@param listener table
function ManualAttachDetectionHandler:addDetectionListener(listener)
    if listener ~= nil then
        table.addElement(self.listeners, listener)
    end
end

---Removes listener from the list.
---@param listener table
function ManualAttachDetectionHandler:removeDetectionListener(listener)
    if listener ~= nil then
        table.removeElement(self.listeners, listener)
    end
end

---Handles detection of a vehicle.
---@param vehicle table
function ManualAttachDetectionHandler:detectVehicle(vehicle)
    if vehicle ~= nil then
        if not table.hasElement(self.detectedVehiclesInTrigger, vehicle) then
            table.addElement(self.detectedVehiclesInTrigger, vehicle)
        end

        self.detectedVehiclesOnLeaveTimes[vehicle] = self.lastDetectedTime
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
    local filename = Utils.getFilename("data/shared/detectionTrigger.i3d", self.modDirectory)
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
    if self.isClient and self.triggerCloneNode ~= nil and player == g_localPlayer then
        if self.lastTrigger ~= nil then
            removeTrigger(self.lastTrigger)
            delete(self.lastTrigger)
        end

        self.lastTrigger = clone(self.triggerCloneNode, false, false, false)
        player.manualAttachDetectionTrigger = self.lastTrigger

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
    if self.isClient and player == g_localPlayer then
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
function ManualAttachDetectionHandler:removeTrigger(player, force)
    force = force or false

    if self.isClient and player == g_localPlayer or force then
        local trigger = player.manualAttachDetectionTrigger
        if trigger ~= nil then
            unlink(trigger)
            removeTrigger(trigger)

            player.manualAttachDetectionTrigger = nil
            self:notifyVehicleTriggerChange(true)

            self.lastTrigger = nil
            self.lastDetectedTime = 0
            self.lastDetectedVehicle = nil
            self.detectedVehiclesInTrigger = {}
            self.detectedVehiclesOnLeaveTimes = {}

            delete(trigger)
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
        local lastAmount = #self.detectedVehiclesInTrigger
        local nodeVehicle = self.mission:getNodeObject(otherId)

        if ManualAttachDetectionHandler.getIsValidVehicle(nodeVehicle) then
            self.lastDetectedTime = self.mission.time
            -- Only save the last vehicle with attacher joints.
            if ManualAttachDetectionHandler.getHasAttacherJoints(nodeVehicle) then
                self.lastDetectedVehicle = nodeVehicle
            end

            if onEnter then
                self:detectVehicle(nodeVehicle)

                if nodeVehicle.getAttacherVehicle ~= nil then
                    self:detectVehicle(nodeVehicle:getAttacherVehicle())
                end

                if nodeVehicle.getAttachedImplements ~= nil then
                    for _, implement in pairs(nodeVehicle:getAttachedImplements()) do
                        local object = implement.object
                        if object ~= nil then
                            self:detectVehicle(object)
                        end
                    end
                end
            end
        end

        if lastAmount ~= #self.detectedVehiclesInTrigger then
            self:notifyVehicleListChanged(self.detectedVehiclesInTrigger)
        end
    end
end
