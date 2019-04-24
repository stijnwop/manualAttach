---
-- ManualAttach
--
-- Main class for Manual Attach.
--
-- Copyright (c) Wopster, 2019

---@class ManualAttach
---@field public detectionHandler ManualAttachDetectionHandler
ManualAttach = {}

---Maps given name to the joint int.
---@param typeName string
---@return number the int joint type.
local function mapJointTypeNameToInt(typeName)
    local jointType = AttacherJoints.jointTypeNameToInt[typeName]
    -- Custom joints need a check if it exists in the game
    return jointType ~= nil and jointType or -1
end

---@type string Empty string placeholder.
ManualAttach.EMPTY_TEXT = ""
---@type number Minimum player distance.
ManualAttach.PLAYER_MIN_DISTANCE = 8 -- sq
---@type number The handle timer threshold in MS.
ManualAttach.TIMER_THRESHOLD = 300 -- ms
---@type number The warning timer threshold in MS.
ManualAttach.WARNING_TIMER_THRESHOLD = 2000 -- ms
---@type table<number, boolean> The automatic attach joint types.
ManualAttach.AUTO_ATTACH_JOINTYPES = {
    [mapJointTypeNameToInt("skidSteer")] = true,
    [mapJointTypeNameToInt("cutter")] = true,
    [mapJointTypeNameToInt("cutterHarvester")] = true,
    [mapJointTypeNameToInt("wheelLoader")] = true,
    [mapJointTypeNameToInt("frontloader")] = true,
    [mapJointTypeNameToInt("telehandler")] = true,
    [mapJointTypeNameToInt("loaderFork")] = true,
    [mapJointTypeNameToInt("hookLift")] = true,
    [mapJointTypeNameToInt("semitrailer")] = true,
    [mapJointTypeNameToInt("semitrailerHook")] = true,
    [mapJointTypeNameToInt("fastCoupler")] = true
}

local ManualAttach_mt = Class(ManualAttach)

---Creates a new instance of ManualAttach.
---@param mission table
---@param input table
---@param i18n table
---@param inputDisplayManager table
---@param modDirectory string
---@param modName string
---@return ManualAttach
function ManualAttach:new(mission, input, i18n, inputDisplayManager, modDirectory, modName)
    local self = setmetatable({}, ManualAttach_mt)

    self.isServer = mission:getIsServer()
    self.isClient = mission:getIsClient()
    self.mission = mission
    self.input = input
    self.i18n = i18n
    self.modDirectory = modDirectory
    self.modName = modName

    self.hudAtlasPath = g_baseHUDFilename

    self.vehicles = {}
    self.controlledVehicle = nil

    self.hasHoseEventInput = 0
    self.allowPtoEvent = true
    self.handleEventCurrentDelay = ManualAttach.TIMER_THRESHOLD

    self.context = ContextActionDisplay.new(self.hudAtlasPath, inputDisplayManager)

    self.detectionHandler = ManualAttachDetectionHandler:new(self.isServer, self.isClient, self.mission, modDirectory)

    if self.isClient then
        self.detectionHandler:addDetectionListener(self)
    end

    return self
end

---Called when player clicks start.
---@param mission table
function ManualAttach:onMissionStart(mission)
    self.detectionHandler:load()

    self.handleEventCurrentDelay = ManualAttach.TIMER_THRESHOLD

    self:resetAttachValues()
end

---Called on delete.
function ManualAttach:delete()
    self.detectionHandler:delete()
    self.context:delete()
end

---Main update function called every frame.
---@param dt number
function ManualAttach:update(dt)
    if not self.isClient then
        return
    end

    local lastHasHoseEventInput = self.hasHoseEventInput
    self.hasHoseEventInput = 0

    if lastHasHoseEventInput ~= 0 then
        self.handleEventCurrentDelay = self.handleEventCurrentDelay - dt

        if self.handleEventCurrentDelay < 0 then
            self.handleEventCurrentDelay = ManualAttach.TIMER_THRESHOLD
            self.allowPtoEvent = false

            self:onConnectionHoseEvent()
        end
    else
        if self.allowPtoEvent then
            if self.handleEventCurrentDelay ~= ManualAttach.TIMER_THRESHOLD and self.handleEventCurrentDelay ~= 0 then
                self:onPowerTakeOffEvent()
            end
        end

        self.handleEventCurrentDelay = ManualAttach.TIMER_THRESHOLD
        self.allowPtoEvent = true
    end

    local isValidPlayer = self:isValidPlayer()
    if self:hasVehicles() then
        self.attacherVehicle, self.attacherVehicleJointDescIndex, self.attachable, self.attachableJointDescIndex, self.attachedImplement = ManualAttachUtil.findVehicleInAttachRange(self.vehicles, AttacherJoints.MAX_ATTACH_DISTANCE_SQ, AttacherJoints.MAX_ATTACH_ANGLE, isValidPlayer)
    end

    if not isValidPlayer then
        self:addControllingVehicle()
    end

    self.context:update(dt)
end

---Builds an initial event draw helper.
---@return table
local function getInitialDrawEventValues()
    local event = {}

    event.text = ManualAttach.EMPTY_TEXT
    event.priority = GS_PRIO_VERY_LOW
    event.visibility = false

    return event
end

---Sets the draw values for the event.
---@param event table
---@param text string
---@param priority number
local function setDrawEventValues(event, text, priority)
    event.text = text
    event.priority = priority or event.priority
    event.visibility = text ~= ManualAttach.EMPTY_TEXT
end

---Returns key string "attach" when true, "detach" otherwise.
---@param isAttached boolean
---@return string The attach key.
local function getAttachKey(isAttached)
    return isAttached and "detach" or "attach"
end

---Handles the input manager action event functions.
---@param id number
---@param text string
---@param priority boolean
---@param visibility boolean
function ManualAttach:setActionEventText(id, text, priority, visibility)
    self.input:setActionEventText(id, text)
    self.input:setActionEventTextPriority(id, priority)
    self.input:setActionEventTextVisibility(id, visibility)
end

---Returns true if we can handle, false otherwise.
---@param vehicle table
---@param object table
---@param jointIndex number optional
---@return boolean
function ManualAttach:canHandle(vehicle, object, jointIndex)
    local isValidPlayer = self:isValidPlayer()
    local isAutoDetachable = ManualAttachUtil.isAutoDetachable(vehicle, object, jointIndex)

    return (isValidPlayer and not isAutoDetachable) or (not isValidPlayer and isAutoDetachable)
end

---Draw called on every frame.
function ManualAttach:draw()
    if not self.isClient
            or not self:hasVehicles() then
        return
    end

    local attachEvent = getInitialDrawEventValues()
    local handleEvent = getInitialDrawEventValues()

    local isValidPlayer = self:isValidPlayer()

    local object = self.attachedImplement
    if not isValidPlayer and self.controlledVehicle ~= nil then
        object = self.controlledVehicle:getSelectedVehicle()
    end

    if self:isValidObject(object) then
        local attacherVehicle = object:getAttacherVehicle()

        if self:canHandle(attacherVehicle, object) then
            if object.isDetachAllowed ~= nil and object:isDetachAllowed() then
                setDrawEventValues(attachEvent, self.i18n:getText("action_detach"))
            end
        end

        if isValidPlayer then
            local hasPowerTakeOffs = ManualAttachUtil.hasPowerTakeOffs(object, attacherVehicle)
            local handleText = ManualAttach.EMPTY_TEXT

            if hasPowerTakeOffs then
                local isAttached = ManualAttachUtil.hasAttachedPowerTakeOffs(object, attacherVehicle)
                handleText = self.i18n:getText(("action_%s_pto"):format(getAttachKey(isAttached)))
            end

            if ManualAttachUtil.hasConnectionHoses(object, attacherVehicle) then
                local isAttached = ManualAttachUtil.hasAttachedConnectionHoses(object)
                local hoseText = self.i18n:getText(("action_%s_hose"):format(getAttachKey(isAttached)))

                if not hasPowerTakeOffs then
                    handleText = hoseText
                else
                    self.mission:addExtraPrintText(hoseText)
                end
            end

            setDrawEventValues(handleEvent, handleText)
        end
    end

    if self.attachable ~= nil then
        if self:canHandle(self.attacherVehicle, self.attachable, self.attacherVehicleJointDescIndex) then
            if self.mission.accessHandler:canFarmAccess(self.attacherVehicle:getActiveFarm(), self.attachable) then
                setDrawEventValues(attachEvent, self.i18n:getText("action_attach"), GS_PRIO_VERY_HIGH)
                self.context:setContext(InputAction.MA_ATTACH_VEHICLE, ContextActionDisplay.CONTEXT_ICON.ATTACH, self.attachable:getFullName())
            end
        end
    end

    self:setActionEventText(self.attachEvent, attachEvent.text, attachEvent.priority, attachEvent.visibility)
    self:setActionEventText(self.handleEventId, handleEvent.text, handleEvent.priority, handleEvent.visibility)
    self.context:draw()
end

---Adds the current controlled vehicle to the list if valid.
function ManualAttach:addControllingVehicle()
    if self.controlledVehicle ~= self.mission.controlledVehicle then
        local vehicles = {}
        if self.detectionHandler.getIsValidVehicle(self.mission.controlledVehicle) then
            self.controlledVehicle = self.mission.controlledVehicle
            ListUtil.addElementToList(vehicles, self.controlledVehicle)
        else
            self.controlledVehicle = nil
        end

        self:onVehicleListChanged(vehicles)
    end
end

---Returns true when the current vehicles table is not empty, false otherwise.
---@return boolean
function ManualAttach:hasVehicles()
    return #self.vehicles ~= 0
end

---Resets all in range values and hides the action events.
function ManualAttach:resetAttachValues()
    self.vehicles = {}
    self.attacherVehicle = nil
    self.attacherVehicleJointDescIndex = nil
    self.attachable = nil
    self.attachableJointDescIndex = nil
    self.attachedImplement = nil

    self.input:setActionEventTextVisibility(self.attachEvent, false)
    self.input:setActionEventTextVisibility(self.handleEventId, false)
end

---Called by the detection handler when the vehicle list has changed.
---@param vehicles table
function ManualAttach:onVehicleListChanged(vehicles)
    self.vehicles = vehicles

    if not self:hasVehicles() then
        self:resetAttachValues()
    end
end

---Called by the detection handler when the trigger has been removed or added.
---@param isDeleted boolean
function ManualAttach:onTriggerChanged(isDeleted)
    if isDeleted then
        self.controlledVehicle = nil
    end
end

---Returns true when the player is valid, false otherwise.
---@return boolean
function ManualAttach:isValidPlayer()
    local player = self.mission.player
    return player ~= nil
            and self.mission.controlPlayer
            and not player.isCarryingObject
            and not player:hasHandtoolEquipped()
end

---Returns true when the given object is valid, false otherwise.
---@param object table
---@return boolean
function ManualAttach:isValidObject(object)
    return object ~= nil and not object.isDeleted and object.getAttacherVehicle ~= nil and object:getAttacherVehicle() ~= nil
end

---Returns true if allowed, false otherwise.
---Returns optional warning
---Returns optional boolean that forces if the warning should be shown.
---@param object table
---@param vehicle table
---@param jointDesc table
---@return boolean, string, boolean
function ManualAttach:isDetachAllowed(object, vehicle, jointDesc)
    local detachAllowed, warning, showWarning = object:isDetachAllowed()

    if not detachAllowed then
        return detachAllowed, warning, showWarning
    end

    if ManualAttachUtil.isManualJointType(jointDesc) then
        local allowsLowering = object:getAllowsLowering()

        if allowsLowering and jointDesc.allowsLowering then
            if not jointDesc.moveDown then
                detachAllowed = false
                warning = self.i18n:getText("info_lower_warning"):format(object:getFullName())
            end
        end
    end

    if detachAllowed then
        if ManualAttachUtil.hasPowerTakeOffs(object, vehicle)
                and ManualAttachUtil.hasAttachedPowerTakeOffs(object, vehicle) then
            detachAllowed = false
            warning = self.i18n:getText("info_detach_pto_warning"):format(object:getFullName())
        end
    end

    if detachAllowed then
        if ManualAttachUtil.hasConnectionHoses(object, vehicle)
                and ManualAttachUtil.hasAttachedConnectionHoses(object) then
            detachAllowed = false
            warning = self.i18n:getText("info_detach_hoses_warning"):format(object:getFullName())
        end
    end

    return detachAllowed, warning, showWarning
end

---Attaches the object to the vehicle.
---@param vehicle table
---@param object table
---@param inputJointDescIndex number
---@param jointDescIndex number
function ManualAttach:attachImplement(vehicle, object, inputJointDescIndex, jointDescIndex)
    if self.mission.accessHandler:canFarmAccess(vehicle:getActiveFarm(), object)
            and self:canHandle(vehicle, object, jointDescIndex) then
        local jointDesc = vehicle.spec_attacherJoints.attacherJoints[jointDescIndex]

        if not jointDesc.jointIndex ~= 0 then
            vehicle:attachImplement(object, inputJointDescIndex, jointDescIndex)

            local allowsLowering = object:getAllowsLowering()
            if allowsLowering and jointDesc.allowsLowering then
                vehicle:handleLowerImplementByAttacherJointIndex(jointDescIndex)
            end
        end
    end
end

---Detaches the object from the attacher vehicle.
---@param object table
function ManualAttach:detachImplement(object)
    local vehicle = object:getAttacherVehicle()
    if vehicle ~= nil and self:canHandle(vehicle, object) then
        local jointDesc = vehicle:getAttacherJointDescFromObject(object)
        local detachAllowed, warning, showWarning = self:isDetachAllowed(object, vehicle, jointDesc)

        if detachAllowed then
            vehicle:detachImplementByObject(object)
        elseif showWarning == nil or showWarning then
            self.mission:showBlinkingWarning(warning or self.i18n:getText("warning_detachNotAllowed"), ManualAttach.WARNING_TIMER_THRESHOLD)
        end
    end
end

---Attaches the pto from the given object to the vehicle.
---@param vehicle table
---@param object table
---@param noEventSend boolean
function ManualAttach:attachPowerTakeOff(vehicle, object, noEventSend)
    ManualAttachPowerTakeOffEvent.sendEvent(vehicle, object, false, noEventSend)

    local implement = vehicle:getImplementByObject(object)
    local inputJointDescIndex = object.spec_attachable.inputAttacherJointDescIndex
    local jointDescIndex = implement.jointDescIndex

    vehicle:attachPowerTakeOff(object, inputJointDescIndex, jointDescIndex)
    vehicle:handlePowerTakeOffPostAttach(jointDescIndex)
end

---Detaches the pto from the given object from the vehicle.
---@param vehicle table
---@param object table
---@param noEventSend boolean
function ManualAttach:detachPowerTakeOff(vehicle, object, noEventSend)
    ManualAttachPowerTakeOffEvent.sendEvent(vehicle, object, true, noEventSend)

    local implement = vehicle:getImplementByObject(object)
    vehicle:detachPowerTakeOff(vehicle, implement)
end

---Attaches the connection hoses from the given object to the vehicle.
---@param vehicle table
---@param object table
---@param noEventSend boolean
function ManualAttach:attachConnectionHoses(vehicle, object, noEventSend)
    ManualAttachConnectionHosesEvent.sendEvent(vehicle, object, true, noEventSend)

    local implement = vehicle:getImplementByObject(object)
    local inputJointDescIndex = object.spec_attachable.inputAttacherJointDescIndex
    local jointDescIndex = implement.jointDescIndex

    object:connectHosesToAttacherVehicle(vehicle, inputJointDescIndex, jointDescIndex)
    object:updateAttachedConnectionHoses(vehicle) -- update once
end

---Detaches the connection hoses from the given object from the vehicle.
---@param vehicle table
---@param object table
---@param noEventSend boolean
function ManualAttach:detachConnectionHoses(vehicle, object, noEventSend)
    ManualAttachConnectionHosesEvent.sendEvent(vehicle, object, false, noEventSend)

    object:disconnectHoses(vehicle)
end

---Handles attach event.
function ManualAttach:onAttachEvent()
    if self.attachable ~= nil then
        self:attachImplement(self.attacherVehicle, self.attachable, self.attachableJointDescIndex, self.attacherVehicleJointDescIndex)
    else
        -- detach
        local object = self.attachedImplement
        if not self:isValidPlayer() and self.controlledVehicle ~= nil then
            object = self.controlledVehicle:getSelectedVehicle()
        end

        if self:isValidObject(object) then
            self:detachImplement(object)
        end
    end
end

---Handles pto event.
function ManualAttach:onPowerTakeOffEvent()
    if not self.allowPtoEvent then
        return
    end

    local object = self.attachedImplement
    if object ~= nil then
        local attacherVehicle = object:getAttacherVehicle()

        if ManualAttachUtil.hasPowerTakeOffs(object, attacherVehicle) then
            if object.getIsTurnedOn ~= nil and object:getIsTurnedOn() then
                self.mission:showBlinkingWarning(self.i18n:getText("info_turn_off_warning"):format(object:getFullName()), ManualAttach.WARNING_TIMER_THRESHOLD)
                return
            end

            local hasAttachedPowerTakeOffs = ManualAttachUtil.hasAttachedPowerTakeOffs(object, attacherVehicle)
            if hasAttachedPowerTakeOffs then
                self:detachPowerTakeOff(attacherVehicle, object, false)
            else
                self:attachPowerTakeOff(attacherVehicle, object, false)
            end
        end
    end
end

---Handles connection hose event.
function ManualAttach:onConnectionHoseEvent()
    local object = self.attachedImplement
    if object ~= nil then
        local attacherVehicle = object:getAttacherVehicle()

        if ManualAttachUtil.hasConnectionHoses(object, attacherVehicle) then
            if object.getIsTurnedOn ~= nil and object:getIsTurnedOn() then
                self.mission:showBlinkingWarning(self.i18n:getText("info_turn_off_warning"):format(object:getFullName()), ManualAttach.WARNING_TIMER_THRESHOLD)
                return
            end

            if ManualAttachUtil.hasAttachedConnectionHoses(object) then
                self:detachConnectionHoses(attacherVehicle, object, false)
            else
                self:attachConnectionHoses(attacherVehicle, object, false)
            end
        end
    end
end

---Handles actual input for pto and connection hoses event.
function ManualAttach:onPowerTakeOffAndConnectionHoseEvent(actionName, inputValue)
    self.hasHoseEventInput = inputValue
end

---Register input actions.
function ManualAttach:registerActionEvents()
    if self.isClient then
        local _, attachEventId = self.input:registerActionEvent(InputAction.MA_ATTACH_VEHICLE, self, self.onAttachEvent, false, true, false, true)
        self.input:setActionEventTextVisibility(attachEventId, false)

        self.attachEvent = attachEventId
    end
end

---Register player input actions.
function ManualAttach:registerPlayerActionEvents()
    if self.isClient then
        local _, handleEventId = self.input:registerActionEvent(InputAction.MA_ATTACH_PTO_HOSE, self, self.onPowerTakeOffAndConnectionHoseEvent, false, true, true, true)
        self.input:setActionEventTextVisibility(handleEventId, false)

        self.handleEventId = handleEventId
    end
end

---Unregister input actions.
function ManualAttach:unregisterActionEvents()
    self.input:removeActionEventsByTarget(self)
end

---
--- Injections.
---

---Injects in the mission register action events.
function ManualAttach.inj_registerActionEvents(mission)
    g_manualAttach:registerActionEvents()
end

---Injects in the mission unregister action events.
function ManualAttach.inj_unregisterActionEvents(mission)
    g_manualAttach:unregisterActionEvents()
end

---Injects in the player onEnter function to load the trigger when controlling the player.
---@param player table
---@param isControlling boolean
function ManualAttach.inj_onEnter(player, isControlling)
    if isControlling then
        g_manualAttach:registerPlayerActionEvents()
        g_manualAttach.detectionHandler:addTrigger()
    end
end

---Injects in the player onLeave function
---@param player table
function ManualAttach.inj_onLeave(player)
    g_manualAttach:unregisterActionEvents()
    g_manualAttach.detectionHandler:removeTrigger()
end

---Injects in the player delete function
---@param player table
function ManualAttach.inj_delete(player)
    g_manualAttach.detectionHandler:removeTrigger()
end

---Early hook into adding vehicle specializations.
---@param vehicleTypeManager table
---@param specializationManager table
---@param modDirectory string
---@param modName string
function ManualAttach.installSpecializations(vehicleTypeManager, specializationManager, modDirectory, modName)
    specializationManager:addSpecialization("manualAttachPowerTakeOff", "ManualAttachPowerTakeOff", Utils.getFilename("src/vehicle/ManualAttachPowerTakeOff.lua", modDirectory), nil)
    specializationManager:addSpecialization("manualAttachConnectionHoses", "ManualAttachConnectionHoses", Utils.getFilename("src/vehicle/ManualAttachConnectionHoses.lua", modDirectory), nil)
    specializationManager:addSpecialization("manualAttachVehicle", "ManualAttachVehicle", Utils.getFilename("src/vehicle/ManualAttachVehicle.lua", modDirectory), nil)

    for typeName, typeEntry in pairs(vehicleTypeManager:getVehicleTypes()) do
        if SpecializationUtil.hasSpecialization(PowerTakeOffs, typeEntry.specializations) then
            vehicleTypeManager:addSpecialization(typeName, modName .. ".manualAttachPowerTakeOff")
        end

        if SpecializationUtil.hasSpecialization(ConnectionHoses, typeEntry.specializations)
                and SpecializationUtil.hasSpecialization(Attachable, typeEntry.specializations)
                and not SpecializationUtil.hasSpecialization(ConveyorBelt, typeEntry.specializations) then
            vehicleTypeManager:addSpecialization(typeName, modName .. ".manualAttachConnectionHoses")
        end

        if SpecializationUtil.hasSpecialization(AttacherJoints, typeEntry.specializations) then
            vehicleTypeManager:addSpecialization(typeName, modName .. ".manualAttachVehicle")
        end
    end
end
