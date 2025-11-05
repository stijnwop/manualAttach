--
-- DetectionHandler
--
-- Author: Wopster
-- Description: Main class for handling the vehicle detection.
-- Name: DetectionHandler
-- Hide: yes
--
-- Copyright (c) Wopster

---@class DetectionHandler
DetectionHandler = {}
local DetectionHandler_mt = Class(DetectionHandler)

DetectionHandler.CLEAR_TIME_THRESHOLD = 5000 --ms

type DetectionHandlerData = {
    isServer: boolean,
    isClient: boolean,

    mission: BaseMission,
    modDirectory: string,

    triggerNode: number?,
    triggerCloneNode: number?,
    lastDetectedTime: number,
    lastDetectedVehicle: Vehicle?,
    detectedVehicles: { Vehicle },
    vehicleLeaveTimes: { [Vehicle]: number },
    listeners: { any },
}

export type DetectionHandler = typeof(setmetatable({} :: DetectionHandlerData, DetectionHandler_mt))

---Creates a new instance of DetectionHandler.
function DetectionHandler.new(mission: BaseMission, modDirectory: string, customMt: any): DetectionHandler
    local self = {}

    self.isServer = mission:getIsServer()
    self.isClient = mission:getIsClient()

    self.mission = mission
    self.modDirectory = modDirectory

    self.triggerNode = nil
    self.triggerCloneNode = nil
    self.lastDetectedTime = 0
    self.lastDetectedVehicle = nil
    self.detectedVehicles = {}
    self.vehicleLeaveTimes = {}
    self.listeners = {}

    return setmetatable(self :: DetectionHandlerData, customMt or DetectionHandler_mt)
end

---Called on delete.
function DetectionHandler:delete(): ()
    if self.triggerNode ~= nil then
        removeTrigger(self.triggerNode)
        if entityExists(self.triggerNode) then
            delete(self.triggerNode)
        end
    end
    delete(self.triggerCloneNode)
end

---Main update function called every frame.
function DetectionHandler:update(dt: number): ()
    self:cleanupStaleVehicles()
end

---Cleans up vehicles that have left the trigger area
function DetectionHandler:cleanupStaleVehicles(): ()
    local numDetectedVehicles = #self.detectedVehicles
    if numDetectedVehicles == 0 then
        return
    end

    local currentTime = self.mission.time
    local timeSinceLastDetection = currentTime - self.lastDetectedTime

    if timeSinceLastDetection <= DetectionHandler.CLEAR_TIME_THRESHOLD then
        return
    end

    local vehiclesRemoved = false

    for vehicle, leaveTime in pairs(self.vehicleLeaveTimes) do
        local timeSinceLeave = currentTime - leaveTime
        local isNotLastDetected = vehicle ~= self.lastDetectedVehicle

        if timeSinceLeave > DetectionHandler.CLEAR_TIME_THRESHOLD and isNotLastDetected then
            if not self:isVehicleStillInRange(vehicle) then
                local index = table.find(self.detectedVehicles, vehicle)
                if index ~= nil then
                    table.remove(self.detectedVehicles, index)
                    vehiclesRemoved = true
                end

                self.vehicleLeaveTimes[vehicle] = nil -- GC
            end
        end
    end

    if vehiclesRemoved then
        self:onDetectedVehiclesChanged(self.detectedVehicles)
    end
end

function DetectionHandler:isVehicleStillInRange(vehicle: Vehicle): boolean
    if self.triggerNode == nil or vehicle == nil or vehicle.rootNode == nil then
        return false
    end

    local x, y, z = getWorldTranslation(self.triggerNode)
    local rx, ry, rz = getWorldRotation(self.triggerNode)

    local width, height, length = 1, 1, 1

    self.overlapCheckVehicle = vehicle
    self.vehicleFoundInOverlap = false

    overlapBox(x, y, z, rx, ry, rz, width, height, length, "vehicleOverlapCallback", self, CollisionFlag.VEHICLE, true, false, true)

    local foundInOverlap = self.vehicleFoundInOverlap
    self.overlapCheckVehicle = nil
    self.vehicleFoundInOverlap = false

    if foundInOverlap then
        self.lastDetectedTime = self.mission.time
    end

    return foundInOverlap
end

function DetectionHandler:vehicleOverlapCallback(transformId: number): boolean
    if transformId == 0 or not getHasClassId(transformId, ClassIds.SHAPE) then
        return true
    end

    local nodeVehicle = self.mission:getNodeObject(transformId)

    if not DetectionHandler.canHandleVehicle(nodeVehicle) then
        return true
    end

    local isTargetVehicle = nodeVehicle == self.overlapCheckVehicle
    if isTargetVehicle then
        self.vehicleFoundInOverlap = true
        self:detectVehicleWithAttachments(nodeVehicle)
        return false
    end

    return true
end

---Handles detection of a vehicle.
function DetectionHandler:detectVehicle(vehicle: Vehicle): ()
    if vehicle == nil then
        return
    end

    if table.find(self.detectedVehicles, vehicle) == nil then
        table.insert(self.detectedVehicles, vehicle)
    end

    self.vehicleLeaveTimes[vehicle] = self.lastDetectedTime
end

---Detects a vehicle and all its attached implements and attacher vehicle
function DetectionHandler:detectVehicleWithAttachments(vehicle: Vehicle): ()
    if vehicle == nil then
        return
    end

    self:detectVehicle(vehicle)

    if vehicle.getAttacherVehicle ~= nil then
        self:detectVehicle(vehicle:getAttacherVehicle())
    end

    if vehicle.getAttachedImplements ~= nil then
        for _, implement in pairs(vehicle:getAttachedImplements()) do
            if implement.object ~= nil then
                self:detectVehicle(implement.object)
            end
        end
    end
end

---Checks if the detected vehicle is valid.
function DetectionHandler.canHandleVehicle(vehicle: Vehicle): boolean
    return vehicle ~= nil
        and vehicle.isa ~= nil
        and vehicle:isa(Vehicle)
        and not vehicle:isa(StationCrane)
        and not SpecializationUtil.hasSpecialization(SplineVehicle, vehicle.specializations)
        and (SpecializationUtil.hasSpecialization(AttacherJoints, vehicle.specializations) or SpecializationUtil.hasSpecialization(Attachable, vehicle.specializations))
end

---Checks if the given vehicle has attacherJoints.
function DetectionHandler.hasAttacherJoints(vehicle: Vehicle): boolean
    return vehicle.getAttacherJoints ~= nil and next(vehicle:getAttacherJoints()) ~= nil
end

---Callback when trigger changes state.
function DetectionHandler:vehicleDetectionCallback(triggerId: number, otherId: number, onEnter: boolean, onLeave: boolean, onStay: boolean): ()
    if not (onEnter or onLeave) then
        return
    end

    local numVehiclesBefore = #self.detectedVehicles
    local nodeVehicle = self.mission:getNodeObject(otherId)

    if not DetectionHandler.canHandleVehicle(nodeVehicle) then
        return
    end

    self.lastDetectedTime = self.mission.time

    -- Only save the last vehicle with attacher joints
    if DetectionHandler.hasAttacherJoints(nodeVehicle) then
        self.lastDetectedVehicle = nodeVehicle
    end

    if onEnter then
        self:detectVehicleWithAttachments(nodeVehicle)
    end

    if numVehiclesBefore ~= #self.detectedVehicles then
        self:onDetectedVehiclesChanged(self.detectedVehicles)
    end
end

---Clears all detection values.
function DetectionHandler:clear(): ()
    self.lastDetectedTime = 0
    self.lastDetectedVehicle = nil
    table.clear(self.detectedVehicles)
    table.clear(self.vehicleLeaveTimes)
    self:onDetectedVehiclesChanged(self.detectedVehicles)
end

---Adds listener from the list.
function DetectionHandler:addDetectionListener(listener: any): ()
    if listener ~= nil then
        table.insert(self.listeners, listener)
    end
end

---Removes listener from the list.
function DetectionHandler:removeDetectionListener(listener: any): ()
    if listener ~= nil then
        local index = table.find(self.listeners, listener)
        if index ~= nil then
            table.remove(self.listeners, index)
        end
    end
end

---Called when detected vehicles list changes.
function DetectionHandler:onDetectedVehiclesChanged(vehicles: { Vehicle }): ()
    for _, listener in ipairs(self.listeners) do
        listener:onVehicleListChanged(vehicles)
    end
end

---Called when trigger state changes.
function DetectionHandler:onTriggerStateChanged(isRemoved: boolean): ()
    for _, listener in ipairs(self.listeners) do
        listener:onTriggerChanged(isRemoved)
    end
end

---Ghost remove node to physics.
function DetectionHandler:onGhostRemove(nodeId: number): ()
    setVisibility(nodeId, false)
    removeFromPhysics(nodeId)
end

---Ghost add node to physics.
function DetectionHandler:onGhostAdd(nodeId: number): ()
    setVisibility(nodeId, true)
    addToPhysics(nodeId)
end

---Called on player load.
function DetectionHandler:onPlayerLoad(player: Player): ()
    self:loadCloneableTrigger()
    self:addTrigger(player)
end

---Called on player delete.
function DetectionHandler:onPLayerDelete(player: Player): ()
    self:removeTrigger(player, true)
end

---Loads the trigger from the i3d file.
function DetectionHandler:loadCloneableTrigger(): ()
    local filename = Utils.getFilename("data/shared/detectionTrigger.i3d", self.modDirectory)
    local rootNode = loadI3DFile(filename, false, false, false)
    local trigger = I3DUtil.indexToObject(rootNode, "0")

    unlink(trigger)
    delete(rootNode)

    self.triggerCloneNode = trigger
    link(getRootNode(), self.triggerCloneNode)
end

---Adds the trigger to the player.
function DetectionHandler:addTrigger(player: Player): ()
    if not self.isClient or self.triggerCloneNode == nil or player ~= g_localPlayer then
        return
    end

    if self.triggerNode ~= nil then
        removeTrigger(self.triggerNode)
        delete(self.triggerNode)
    end

    self.triggerNode = clone(self.triggerCloneNode, false, false, false)

    -- Link trigger to player
    link(player.rootNode, self.triggerNode)
    setTranslation(self.triggerNode, 0, 0, -2.5)
    setRotation(self.triggerNode, 0, math.rad(25), 0)

    addTrigger(self.triggerNode, "vehicleDetectionCallback", self)

    self:onGhostAdd(self.triggerNode)
    self:onTriggerStateChanged(false)
end

---Disables the trigger from the player.
function DetectionHandler:disableTrigger(player: Player): ()
    if not self.isClient or player ~= g_localPlayer or self.triggerNode == nil then
        return
    end

    self:onGhostRemove(self.triggerNode)
    self:onTriggerStateChanged(true)

    self.lastDetectedTime = 0
    self.lastDetectedVehicle = nil
    table.clear(self.detectedVehicles)
    table.clear(self.vehicleLeaveTimes)
end

---Removes the trigger from the player.
function DetectionHandler:removeTrigger(player: Player, force: boolean?): ()
    force = force or false

    if not (self.isClient and player == g_localPlayer or force) then
        return
    end

    if self.triggerNode ~= nil then
        unlink(self.triggerNode)
        removeTrigger(self.triggerNode)
        delete(self.triggerNode)

        self.triggerNode = nil
        self:onTriggerStateChanged(true)

        self.lastDetectedTime = 0
        self.lastDetectedVehicle = nil
        table.clear(self.detectedVehicles)
        table.clear(self.vehicleLeaveTimes)
    end
end
