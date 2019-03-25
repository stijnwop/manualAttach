ManualAttach = {}

ManualAttach.PLAYER_MIN_DISTANCE = 9

-- Todo: whats still used
ManualAttach.COSANGLE_THRESHOLD = math.cos(math.rad(70))
ManualAttach.TIMER_THRESHOLD = 300 -- ms
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

function ManualAttach:new(mission, input, i18n, modDirectory, modName)
    local self = setmetatable({}, ManualAttach_mt)

    self.isServer = mission:getIsServer()
    self.isClient = mission:getIsClient()
    self.mission = mission
    self.input = input
    self.i18n = i18n
    self.modDirectory = modDirectory
    self.modName = modName

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
end

function ManualAttach:setActionEventText(id, text, priority, visibility)
    self.input:setActionEventText(id, text)
    self.input:setActionEventTextPriority(id, priority)
    self.input:setActionEventTextVisibility(id, visibility)
end

function ManualAttach:draw(dt)
    if not self.isClient then
        return
    end

    if not self:hasVehicles() then
        return
    end

    local attachEventVisibility = false
    local attachEventPrio = GS_PRIO_VERY_LOW
    local attachEventText = ""

    local ptoEventVisibility = false
    local ptoEventText = ""
    local hoseEventVisibility = false
    local hoseEventText = ""

    local object = self.attachedImplement
    local isValidPlayer = self:isValidPlayer()

    if not isValidPlayer then
        object = self.controlledVehicle:getSelectedVehicle()
    end

    if object ~= nil and not object.isDeleted and object.getAttacherVehicle ~= nil then
        local attacherVehicle = object:getAttacherVehicle()
        local canDraw = attacherVehicle ~= nil
        if canDraw
                and not isValidPlayer
                and not ManualAttachUtil.isAutoDetachable(attacherVehicle, object) then
            canDraw = false
        end

        if canDraw then
            if object.isDetachAllowed ~= nil and object:isDetachAllowed() then
                attachEventVisibility = true
                attachEventText = self.i18n:getText("action_detach")
            end

            -- Below is player handling only.
            if isValidPlayer then
                if object.getInputPowerTakeOffs ~= nil then
                    if ManualAttachUtil.hasAttachedPowerTakeOffs(object, attacherVehicle) then
                        ptoEventText = self.i18n:getText("action_detach_pto")
                    else
                        ptoEventText = self.i18n:getText("action_attach_pto")
                    end

                    ptoEventVisibility = true
                end

                if object.getIsConnectionHoseUsed ~= nil then
                    if ManualAttachUtil.hasAttachedConnectionHoses(object) then
                        hoseEventText = self.i18n:getText("info_detach_hose")
                    else
                        hoseEventText = self.i18n:getText("info_attach_hose")
                    end

                    self.mission:addExtraPrintText(hoseEventText)

                    hoseEventVisibility = true
                end
            end
        end
    end

    if self.attachable ~= nil then
        if self.mission.accessHandler:canFarmAccess(self.attacherVehicle:getActiveFarm(), self.attachable) then
            attachEventVisibility = true
            attachEventText = self.i18n:getText("action_attach")
            attachEventPrio = GS_PRIO_VERY_HIGH
            self.mission:showAttachContext(self.attachable)
        end
    end

    self:setActionEventText(self.attachEvent, attachEventText, attachEventPrio, attachEventVisibility)
    self:setActionEventText(self.handleEventId, ptoEventText, GS_PRIO_VERY_LOW, ptoEventVisibility)
end

function ManualAttach:hasVehicles()
    return #self.vehicles ~= 0
end

function ManualAttach:resetAttachValues()
    -- Inrange values
    self.attacherVehicle = nil
    self.attacherVehicleJointDescIndex = nil
    self.attachable = nil
    self.attachableJointDescIndex = nil
    self.attachedImplement = nil

    self.input:setActionEventTextVisibility(self.attachEvent, false)
    self.input:setActionEventTextVisibility(self.handleEventId, false)
end

function ManualAttach:onVehicleListChanged(vehicles)
    self.vehicles = vehicles

    if not self:hasVehicles() then
        self:resetAttachValues()
    end
end

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

---Attaches the object to the vehicle.
---@param vehicle table
---@param object table
---@param inputJointDescIndex number
---@param jointDescIndex number
function ManualAttach:attachImplement(vehicle, object, inputJointDescIndex, jointDescIndex)
    if self.mission.accessHandler:canFarmAccess(vehicle:getActiveFarm(), object) then
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
    local detachAllowed, warning, showWarning = object:isDetachAllowed()
    local vehicle = object:getAttacherVehicle()
    local jointDesc = vehicle:getAttacherJointDescFromObject(object)

    if ManualAttachUtil.isManualJointType(jointDesc) then
        local allowsLowering = object:getAllowsLowering()

        if allowsLowering and jointDesc.allowsLowering then
            if not jointDesc.moveDown then
                detachAllowed = false
                warning = self.i18n:getText("info_lower_warning"):format(object:getName())
            end
        end
    end

    if detachAllowed then
        if ManualAttachUtil.hasAttachedPowerTakeOffs(object, vehicle) then
            detachAllowed = false
            warning = self.i18n:getText("info_detach_pto_warning"):format(object:getName())
        end
    end

    if detachAllowed then
        if ManualAttachUtil.hasAttachedConnectionHoses(object) then
            detachAllowed = false
            warning = self.i18n:getText("info_detach_hoses_warning"):format(object:getName())
        end
    end

    if detachAllowed then
        if vehicle ~= nil then
            vehicle:detachImplementByObject(object)
        end
    elseif showWarning == nil or showWarning then
        self.mission:showBlinkingWarning(warning or self.i18n:getText("warning_detachNotAllowed"), 2000)
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
    if self.allowPtoEvent then
        local object = self.attachedImplement
        if object ~= nil then
            if object.getIsTurnedOn ~= nil and object:getIsTurnedOn() then
                return
            end

            if object.getInputPowerTakeOffs ~= nil then
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
end

function ManualAttach:onConnectionHoseEvent()
    local object = self.attachedImplement
    if object ~= nil then
        local attacherVehicle = object:getAttacherVehicle()
        if ManualAttachUtil.hasAttachedConnectionHoses(object) then
            self:detachConnectionHoses(attacherVehicle, object, false)
        else
            self:attachConnectionHoses(attacherVehicle, object, false)
        end
    end
end

function ManualAttach:onPowerTakeOffAndConnectionHoseEvent(actionName, inputValue)
    self.hasHoseEventInput = inputValue
end

function ManualAttach:registerActionEvents()
    local _, attachEventId = self.input:registerActionEvent(InputAction.MA_ATTACH_VEHICLE, self, self.onAttachEvent, false, true, false, true)
    self.input:setActionEventTextVisibility(attachEventId, false)

    local _, handleEventId = self.input:registerActionEvent(InputAction.MA_ATTACH_HOSE, self, self.onPowerTakeOffAndConnectionHoseEvent, false, true, true, true)
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
