ManualAttach = {}

ManualAttach.PLAYER_MIN_DISTANCE = 8
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
    [mapJointTypeNameToInt("hookLift")] = true,
    [mapJointTypeNameToInt("semitrailer")] = true,
    [mapJointTypeNameToInt("semitrailerHook")] = true,
    [mapJointTypeNameToInt("fastCoupler")] = true
}

local ManualAttach_mt = Class(ManualAttach)

function ManualAttach:new(mission, modDirectory)
    local self = setmetatable({}, ManualAttach_mt)

    self.isServer = mission:getIsServer()
    self.isClient = mission:getIsClient()
    self.mission = mission
    self.modDirectory = modDirectory
    self.detectionHandler = ManualAttachDetectionHandler:new(self.isServer, self.isClient, modDirectory)

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
        if self.controlledVehicle ~= g_currentMission.controlledVehicle then
            self.controlledVehicle = g_currentMission.controlledVehicle
            self.vehicles = { self.controlledVehicle }
        end
    end
end

local function setActionEventText(id, text, priority, visibility)
    g_inputBinding:setActionEventText(id, text)
    g_inputBinding:setActionEventTextPriority(id, priority)
    g_inputBinding:setActionEventTextVisibility(id, visibility)
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
                attachEventText = g_i18n:getText("action_detach")
            end

            -- Below is player handling only.
            if isValidPlayer then
                if object.getInputPowerTakeOffs ~= nil then
                    if ManualAttachUtil.hasAttachedPowerTakeOffs(object, attacherVehicle) then
                        ptoEventText = g_i18n:getText("action_detach_pto")
                    else
                        ptoEventText = g_i18n:getText("action_attach_pto")
                    end

                    ptoEventVisibility = true
                end

                if object.getIsConnectionHoseUsed ~= nil then
                    if ManualAttachUtil.hasAttachedConnectionHoses(object) then
                        hoseEventText = g_i18n:getText("info_detach_hose")
                    else
                        hoseEventText = g_i18n:getText("info_attach_hose")
                    end

                    g_currentMission:addExtraPrintText(hoseEventText)

                    hoseEventVisibility = true
                end
            end
        end
    end

    if self.attachable ~= nil then
        if g_currentMission.accessHandler:canFarmAccess(self.attacherVehicle:getActiveFarm(), self.attachable) then
            attachEventVisibility = true
            attachEventText = g_i18n:getText("action_attach")
            attachEventPrio = GS_PRIO_VERY_HIGH
            g_currentMission:showAttachContext(self.attachable)
        end
    end

    setActionEventText(self.attachEvent, attachEventText, attachEventPrio, attachEventVisibility)
    setActionEventText(self.handleEventId, ptoEventText, GS_PRIO_VERY_LOW, ptoEventVisibility)
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

    g_inputBinding:setActionEventTextVisibility(self.attachEvent, false)
    g_inputBinding:setActionEventTextVisibility(self.handleEventId, false)
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

function ManualAttach:isValidPlayer()
    local player = g_currentMission.player
    return player ~= nil
            and g_currentMission.controlPlayer
            and not player.isCarryingObject
            and not player:hasHandtoolEquipped()
end

---Attaches the object to the vehicle.
---@param vehicle table
---@param object table
---@param inputJointDescIndex number
---@param jointDescIndex number
function ManualAttach:attachImplement(vehicle, object, inputJointDescIndex, jointDescIndex)
    if g_currentMission.accessHandler:canFarmAccess(vehicle:getActiveFarm(), object) then
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
                warning = g_i18n:getText("info_lower_warning"):format(object:getName())
            end
        end
    end

    if detachAllowed then
        if ManualAttachUtil.hasAttachedPowerTakeOffs(object, vehicle) then
            detachAllowed = false
            warning = g_i18n:getText("info_detach_pto_warning"):format(object:getName())
        end
    end

    if detachAllowed then
        if ManualAttachUtil.hasAttachedConnectionHoses(object) then
            detachAllowed = false
            warning = g_i18n:getText("info_detach_hoses_warning"):format(object:getName())
        end
    end

    if detachAllowed then
        if vehicle ~= nil then
            vehicle:detachImplementByObject(object)
        end
    elseif showWarning == nil or showWarning then
        g_currentMission:showBlinkingWarning(warning or g_i18n:getText("warning_detachNotAllowed"), 2000)
    end
end

function ManualAttach:onAttachEvent()
    if self.attachable ~= nil then
        self:attachImplement(self.attacherVehicle, self.attachable, self.attachableJointDescIndex, self.attacherVehicleJointDescIndex)
    else
        -- detach
        local object = self.attachedImplement
        if not self:isValidPlayer() then
            local selectedVehicle = self.controlledVehicle:getSelectedVehicle()
            if selectedVehicle ~= nil then
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
            local attacherVehicle = object:getAttacherVehicle()
            local implement = attacherVehicle:getImplementByObject(object)
            if object.getInputPowerTakeOffs ~= nil then
                local inputJointDescIndex = object.spec_attachable.inputAttacherJointDescIndex
                local jointDescIndex = implement.jointDescIndex

                if ManualAttachUtil.hasAttachedPowerTakeOffs(object, attacherVehicle) then
                    attacherVehicle:detachPowerTakeOff(attacherVehicle, implement)
                else
                    attacherVehicle:attachPowerTakeOff(object, inputJointDescIndex, jointDescIndex)
                    attacherVehicle:handlePowerTakeOffPostAttach(jointDescIndex)
                end
            end
        end
    end
end

function ManualAttach:onConnectionHoseEvent()
    local object = self.attachedImplement
    if object ~= nil then
        local attacherVehicle = object:getAttacherVehicle()
        local implement = attacherVehicle:getImplementByObject(object)
        local inputJointDescIndex = object.spec_attachable.inputAttacherJointDescIndex
        local jointDescIndex = implement.jointDescIndex

        if ManualAttachUtil.hasAttachedConnectionHoses(object) then
            object:disconnectHoses(attacherVehicle)
        else
            object:connectHosesToAttacherVehicle(attacherVehicle, inputJointDescIndex, jointDescIndex)
            object:updateAttachedConnectionHoses(attacherVehicle) -- update once
        end
    end
end

function ManualAttach:onPowerTakeOffAndConnectionHoseEvent(actionName, inputValue)
    self.hasHoseEventInput = inputValue
end

function ManualAttach:registerActionEvents()
    local _, attachEventId = g_inputBinding:registerActionEvent(InputAction.MA_ATTACH_VEHICLE, self, self.onAttachEvent, false, true, false, true)
    g_inputBinding:setActionEventTextVisibility(attachEventId, false)

    local _, handleEventId = g_inputBinding:registerActionEvent(InputAction.MA_ATTACH_HOSE, self, self.onPowerTakeOffAndConnectionHoseEvent, false, true, true, true)
    g_inputBinding:setActionEventTextVisibility(handleEventId, false)

    self.attachEvent = attachEventId
    self.handleEventId = handleEventId
end

function ManualAttach:unregisterActionEvents()
    g_inputBinding:removeActionEventsByTarget(self)
end

function ManualAttach.inj_registerActionEvents(mission)
    g_manualAttach:registerActionEvents()
end

function ManualAttach.inj_unregisterActionEvents(mission)
    g_manualAttach:unregisterActionEvents()
end

function ManualAttach.installSpecializations(vehicleTypeManager, specializationManager, modDirectory, modName)
    specializationManager:addSpecialization("manualAttachExtension", "ManualAttachExtension", Utils.getFilename("src/vehicle/ManualAttachExtension.lua", modDirectory), nil)

    for typeName, typeEntry in pairs(vehicleTypeManager:getVehicleTypes()) do
        if SpecializationUtil.hasSpecialization(Attachable, typeEntry.specializations)
                or SpecializationUtil.hasSpecialization(AttacherJoints, typeEntry.specializations) then
            -- Make sure to namespace the spec again
            vehicleTypeManager:addSpecialization(typeName, modName .. ".manualAttachExtension")
        end
    end
end
