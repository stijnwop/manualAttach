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
    self.triggerCloneNode = nil
    self.detectedVehicleInTrigger = {}
    self.listeners = {}

    return self
end

---Called on load.
function ManualAttachDetectionHandler:load()
    self:loadCloneableTrigger()
end

---Called on delete.
function ManualAttachDetectionHandler:delete()
    delete(self.triggerCloneNode)
end

---Main update function called every frame.
---@param dt number
function ManualAttachDetectionHandler:update(dt)
    if #self.detectedVehicleInTrigger ~= 0 and
            (self.mission.time - self.lastDetectedTime) > ManualAttachDetectionHandler.CLEAR_TIME_THRESHOLD then
        self.detectedVehicleInTrigger = {}
        self:notifyVehicleListChanged(self.detectedVehicleInTrigger)
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

---Loads the trigger from the i3d file.
function ManualAttachDetectionHandler:loadCloneableTrigger()
    local filename = Utils.getFilename("resources/detectionTrigger.i3d", self.modDirectory)
    local rootNode = loadI3DFile(filename, false, false, false)
    local trigger = I3DUtil.indexToObject(rootNode, "0")

    unlink(trigger)
    delete(rootNode)

    self.triggerCloneNode = trigger
    link(getRootNode(), self.triggerCloneNode)

    -- Add trigger on initial load.
    self:addTrigger()
end

---Adds the trigger to the player.
function ManualAttachDetectionHandler:addTrigger()
    if self.isClient and self.triggerCloneNode ~= nil then
        self.trigger = clone(self.triggerCloneNode, false, false, true)

        -- Link trigger to player
        link(self.mission.player.rootNode, self.trigger)
        setTranslation(self.trigger, 0, 0, -2.5)
        setRotation(self.trigger, 0, math.rad(25), 0)

        addTrigger(self.trigger, "vehicleDetectionCallback", self)

        self:notifyVehicleTriggerChange(false)
    end
end

---Removes the trigger from the player.
function ManualAttachDetectionHandler:removeTrigger()
    if self.isClient then
        if self.trigger ~= nil then
            removeTrigger(self.trigger)
            delete(self.trigger)
            self.trigger = nil
        end

        self.detectedVehicleInTrigger = {}
        self:notifyVehicleTriggerChange(true)
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

---Callback when trigger changes state.
---@param triggerId number
---@param otherId number
---@param onEnter boolean
---@param onLeave boolean
---@param onStay boolean
function ManualAttachDetectionHandler:vehicleDetectionCallback(triggerId, otherId, onEnter, onLeave, onStay)
    if (onEnter or onLeave) then
        local lastAmount = #self.detectedVehicleInTrigger
        local nodeVehicle = self.mission:getNodeObject(otherId)

        if ManualAttachDetectionHandler.getIsValidVehicle(nodeVehicle) then
            self.lastDetectedTime = self.mission.time

            if onEnter or onStay then
                if not ListUtil.hasListElement(self.detectedVehicleInTrigger, nodeVehicle) then
                    ListUtil.addElementToList(self.detectedVehicleInTrigger, nodeVehicle)
                end

                if nodeVehicle.getAttacherVehicle ~= nil then
                    local attacherVehicle = nodeVehicle:getAttacherVehicle()
                    if attacherVehicle ~= nil and not ListUtil.hasListElement(self.detectedVehicleInTrigger, attacherVehicle) then
                        ListUtil.addElementToList(self.detectedVehicleInTrigger, attacherVehicle)
                    end
                end

                if nodeVehicle.getAttachedImplements ~= nil then
                    for _, implement in pairs(nodeVehicle:getAttachedImplements()) do
                        local object = implement.object
                        if object ~= nil then
                            if not ListUtil.hasListElement(self.detectedVehicleInTrigger, object) then
                                ListUtil.addElementToList(self.detectedVehicleInTrigger, object)
                            end
                        end
                    end
                end
            end
        end

        if lastAmount ~= #self.detectedVehicleInTrigger then
            self:notifyVehicleListChanged(self.detectedVehicleInTrigger)
        end
    end
end
