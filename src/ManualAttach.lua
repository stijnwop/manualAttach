ManualAttach = {}

ManualAttach.PLAYER_MIN_DISTANCE = 9
ManualAttach.EMPTY_TEXT = ""
ManualAttach.TIMER_THRESHOLD = 300 -- ms

-- Todo: whats still used
ManualAttach.COSANGLE_THRESHOLD = math.cos(math.rad(70))
ManualAttach.DETACHING_NOT_ALLOWED_TIME = 50 -- ms
ManualAttach.DETACHING_PRIORITY_NOT_ALLOWED = 6
ManualAttach.ATTACHING_PRIORITY_ALLOWED = 1
ManualAttach.DEFAULT_JOINT_DISTANCE = 1.3
ManualAttach.JOINT_DISTANCE = ManualAttach.DEFAULT_JOINT_DISTANCE
ManualAttach.JOINT_SEQUENCE = 0.5 * 0.5
ManualAttach.FORCED_ACTIVE_TIME_INCREASMENT = 600 -- ms

local function mapJointTypeNameToInt(typeName)
    local jointType = AttacherJoints.jointTypeNameToInt[typeName]
    -- Custom joints need a check if it exists in the game
    return jointType ~= nil and jointType or -1
end

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
    self.context = ContextActionDisplay.new(self.hudAtlasPath, inputDisplayManager)
    self.detectionHandler = ManualAttachDetectionHandler:new(self.isServer, self.isClient, self.mission, modDirectory)

    if self.isClient then
        self.detectionHandler:addDetectionListener(self)
    end

    return self
end

function ManualAttach:onMissionStart(mission)
    self.detectionHandler:load()

    self.vehicles = {}
    self.controlledVehicle = nil

    self.hasHoseEventInput = 0
    self.allowPtoEvent = true
    self.hoseEventCurrentDelay = ManualAttach.TIMER_THRESHOLD

    self:resetAttachValues()
end

function ManualAttach:delete()
    self.detectionHandler:delete()
end

function ManualAttach:update(dt)
    if not self.isClient then
        return
    end

    local lastHasHoseEventInput = self.hasHoseEventInput
    self.hasHoseEventInput = 0

    if lastHasHoseEventInput ~= 0 then
        self.hoseEventCurrentDelay = self.hoseEventCurrentDelay - dt

        if self.hoseEventCurrentDelay < 0 then
            self.hoseEventCurrentDelay = ManualAttach.TIMER_THRESHOLD
            self.allowPtoEvent = false

            self:onConnectionHoseEvent()
        end
    else
        if self.allowPtoEvent then
            if self.hoseEventCurrentDelay ~= ManualAttach.TIMER_THRESHOLD and self.hoseEventCurrentDelay ~= 0 then
                self:onPowerTakeOffEvent()
            end
        end

        self.hoseEventCurrentDelay = ManualAttach.TIMER_THRESHOLD
        self.allowPtoEvent = true
    end

    local isValidPlayer = self:isValidPlayer()
    if self:hasVehicles() then
        self.attacherVehicle, self.attacherVehicleJointDescIndex, self.attachable, self.attachableJointDescIndex, self.attachedImplement = ManualAttachUtil.findVehicleInAttachRange(self.vehicles, AttacherJoints.MAX_ATTACH_DISTANCE_SQ, AttacherJoints.MAX_ATTACH_ANGLE, isValidPlayer)
    end

    if not isValidPlayer then
        if self.controlledVehicle ~= self.mission.controlledVehicle then
            self.controlledVehicle = self.mission.controlledVehicle
            self.vehicles = { self.controlledVehicle }
        end
    end

    self.context:update(dt)
end

---Builds an initial event draw helper.
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

---Returns key string "attached when true, "detached" otherwise.
---@param isAttached boolean
local function getAttachKey(isAttached)
    return isAttached and "attach" or "detach"
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

---Returns true if we can draw, false otherwise.
---@param vehicle table
---@param object table
---@param jointIndex number optional
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
    if not isValidPlayer then
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
            local hasPowerTakeOffs = ManualAttachUtil.hasPowerTakeOffs(object)
            local handleText = ManualAttach.EMPTY_TEXT

            if hasPowerTakeOffs then
                local isAttached = ManualAttachUtil.hasAttachedPowerTakeOffs(object, attacherVehicle)
                handleText = self.i18n:getText(("action_%s_pto"):format(getAttachKey(isAttached)))
            end

            if ManualAttachUtil.hasConnectionHoses(object) then
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
                --self.mission:showAttachContext(self.attachable)
                self.context:setContext(InputAction.MA_ATTACH_VEHICLE, ContextActionDisplay.CONTEXT_ICON.ATTACH, self.attachable:getFullName())
            end
        end
    end

    self:setActionEventText(self.attachEvent, attachEvent.text, attachEvent.priority, attachEvent.visibility)
    self:setActionEventText(self.handleEventId, handleEvent.text, handleEvent.priority, handleEvent.visibility)
    self.context:draw()
end

---Returns true when the current vehicles table is not empty, false otherwise.
function ManualAttach:hasVehicles()
    return #self.vehicles ~= 0
end

---Resets all in range values and hides the action events.
function ManualAttach:resetAttachValues()
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
function ManualAttach:isValidPlayer()
    local player = self.mission.player
    return player ~= nil
            and self.mission.controlPlayer
            and not player.isCarryingObject
            and not player:hasHandtoolEquipped()
end

---Returns true when the given object is valid, false otherwise.
---@param object table
function ManualAttach:isValidObject(object)
    return object ~= nil and not object.isDeleted and object.getAttacherVehicle ~= nil
end

---Returns true if allowed, false otherwise.
---Returns optional warning
---Returns optional boolean that forces if the warning should be shown.
---@param object table
---@param vehicle table
---@param jointDesc table
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
        if ManualAttachUtil.hasAttachedPowerTakeOffs(object, vehicle) then
            detachAllowed = false
            warning = self.i18n:getText("info_detach_pto_warning"):format(object:getFullName())
        end
    end

    if detachAllowed then
        if ManualAttachUtil.hasAttachedConnectionHoses(object) then
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
            self.mission:showBlinkingWarning(warning or self.i18n:getText("warning_detachNotAllowed"), 2000)
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

function ManualAttach:onAttachEvent()
    if self.attachable ~= nil then
        self:attachImplement(self.attacherVehicle, self.attachable, self.attachableJointDescIndex, self.attacherVehicleJointDescIndex)
    else
        -- detach
        local object = self.attachedImplement

        if not self:isValidPlayer() then
            local selectedVehicle = self.controlledVehicle:getSelectedVehicle()
            if selectedVehicle ~= nil and selectedVehicle.getAttacherVehicle ~= nil then
                local attacherVehicle = selectedVehicle:getAttacherVehicle()
                if ManualAttachUtil.isAutoDetachable(attacherVehicle, selectedVehicle) then
                    object = selectedVehicle
                end
            end
        end

        if object ~= nil and object ~= self.attacherVehicle and object.isDetachAllowed ~= nil then
            self:detachImplement(object)
        end
    end
end

function ManualAttach:onPowerTakeOffEvent()
    if not self.allowPtoEvent then
        return
    end

    local object = self.attachedImplement
    if object ~= nil then
        if ManualAttachUtil.hasPowerTakeOffs(object) then
            if object.getIsTurnedOn ~= nil and object:getIsTurnedOn() then
                self.mission:showBlinkingWarning(self.i18n:getText("info_turn_off_warning"):format(object:getFullName()), 2000)
                return
            end

            local attacherVehicle = object:getAttacherVehicle()
            local hasAttachedPowerTakeOffs = ManualAttachUtil.hasAttachedPowerTakeOffs(object, attacherVehicle)

            if hasAttachedPowerTakeOffs then
                self:detachPowerTakeOff(attacherVehicle, object, false)
            else
                self:attachPowerTakeOff(attacherVehicle, object, false)
            end

            object:onPowerTakeOffChanged(not hasAttachedPowerTakeOffs)
        end
    end
end

function ManualAttach:onConnectionHoseEvent()
    local object = self.attachedImplement
    if object ~= nil then
        if ManualAttachUtil.hasConnectionHoses(object) then
            if object.getIsTurnedOn ~= nil and object:getIsTurnedOn() then
                self.mission:showBlinkingWarning(self.i18n:getText("info_turn_off_warning"):format(object:getFullName()), 2000)
                return
            end

            local attacherVehicle = object:getAttacherVehicle()
            if ManualAttachUtil.hasAttachedConnectionHoses(object) then
                self:detachConnectionHoses(attacherVehicle, object, false)
            else
                self:attachConnectionHoses(attacherVehicle, object, false)
            end
        end
    end
end

function ManualAttach:onPowerTakeOffAndConnectionHoseEvent(actionName, inputValue)
    self.hasHoseEventInput = inputValue
end

function ManualAttach:registerActionEvents()
    local _, attachEventId = self.input:registerActionEvent(InputAction.MA_ATTACH_VEHICLE, self, self.onAttachEvent, false, true, false, true)
    self.input:setActionEventTextVisibility(attachEventId, false)

    local _, handleEventId = self.input:registerActionEvent(InputAction.MA_ATTACH_PTO_HOSE, self, self.onPowerTakeOffAndConnectionHoseEvent, false, true, true, true)
    self.input:setActionEventTextVisibility(handleEventId, false)

    self.attachEvent = attachEventId
    self.handleEventId = handleEventId
end

function ManualAttach:unregisterActionEvents()
    self.input:removeActionEventsByTarget(self)
end

function ManualAttach.inj_registerActionEvents(mission)
    g_manualAttach:registerActionEvents()
end

function ManualAttach.inj_unregisterActionEvents(mission)
    g_manualAttach:unregisterActionEvents()
end

function ManualAttach.installSpecializations(vehicleTypeManager, specializationManager, modDirectory, modName)
    specializationManager:addSpecialization("manualAttachExtension", "ManualAttachExtension", Utils.getFilename("src/vehicle/ManualAttachExtension.lua", modDirectory), nil)
    specializationManager:addSpecialization("manualAttachConnectionHoses", "ManualAttachConnectionHoses", Utils.getFilename("src/vehicle/ManualAttachConnectionHoses.lua", modDirectory), nil)

    for typeName, typeEntry in pairs(vehicleTypeManager:getVehicleTypes()) do
        if SpecializationUtil.hasSpecialization(Attachable, typeEntry.specializations)
                or SpecializationUtil.hasSpecialization(AttacherJoints, typeEntry.specializations) then
            vehicleTypeManager:addSpecialization(typeName, modName .. ".manualAttachExtension")
        end

        if SpecializationUtil.hasSpecialization(ConnectionHoses, typeEntry.specializations) and SpecializationUtil.hasSpecialization(Attachable, typeEntry.specializations) then
            vehicleTypeManager:addSpecialization(typeName, modName .. ".manualAttachConnectionHoses")
        end
    end
end
