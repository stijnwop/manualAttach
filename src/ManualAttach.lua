ManualAttach = {}

ManualAttach.COSANGLE_THRESHOLD = math.cos(math.rad(70))
ManualAttach.PLAYER_MIN_DISTANCE = 9
ManualAttach.PLAYER_DISTANCE = math.huge
ManualAttach.TIMER_THRESHOLD = 200 -- ms
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
    self.detectionHandler = ManualAttachDetectionHandler:new(self.isServer, modDirectory)

    if self.isClient then
        self.detectionHandler:addDetectionListener(self)
    end

    FSBaseMission.registerActionEvents = Utils.appendedFunction(FSBaseMission.registerActionEvents, ManualAttach.inj_registerActionEvents)
    BaseMission.registerActionEvents = Utils.appendedFunction(BaseMission.unregisterActionEvents, ManualAttach.inj_unregisterActionEvents)

    --    self.vehicleHandler = ManualAttachVehicleHandler:new(self.isServer, self.detectionHandler)
    -- self.playerHandler = ManualAttachPlayerHandler:new(self.isServer, self.isClient, self.detectionHandler)

    return self
end

function ManualAttach:onMissionStart(mission)
    self.detectionHandler:load()

    self.vehicles = {}
    self:reset()
end

function ManualAttach:delete()
    self.detectionHandler:delete()
end

function ManualAttach:update(dt)
    self.attacherVehicle = nil

    if self.isClient and #self.vehicles ~= 0 then
        local visible = false

        local attacherVehicle, attacherVehicleJointDescIndex, attachable, attachableJointDescIndex, attachedImplement = ManualAttachUtil.findVehicleInAttachRange(self.vehicles, AttacherJoints.MAX_ATTACH_DISTANCE_SQ, AttacherJoints.MAX_ATTACH_ANGLE)

        self.attacherVehicle = attacherVehicle
        self.attacherVehicleJointDescIndex = attacherVehicleJointDescIndex
        self.attachable = attachable
        self.attachableJointDescIndex = attachableJointDescIndex
        self.attachedImplement = attachedImplement

        local text = ""
        local prio = GS_PRIO_VERY_LOW

        if attachedImplement ~= nil and not attachedImplement.isDeleted and attachedImplement.isDetachAllowed ~= nil and attachedImplement:isDetachAllowed() then
            if attachedImplement:getAttacherVehicle() ~= nil then
                visible = true
                text = g_i18n:getText("action_detach")
            end
        end

        if self.attacherVehicle ~= nil then
            if g_currentMission.accessHandler:canFarmAccess(self.attacherVehicle:getActiveFarm(), self.attachable) then
                visible = true
                text = g_i18n:getText("action_attach")
                g_currentMission:showAttachContext(self.attachable)
                prio = GS_PRIO_VERY_HIGH
            end
        end

        g_inputBinding:setActionEventText(self.attachEvent, text)
        g_inputBinding:setActionEventTextPriority(self.attachEvent, prio)
        g_inputBinding:setActionEventTextVisibility(self.attachEvent, visible)
    end
end

function ManualAttach:draw(dt)
end

function ManualAttach:reset()
    -- Inrange values
    self.attacherVehicle = nil
    self.attacherVehicleJointDescIndex = nil
    self.attachable = nil
    self.attachableJointDescIndex = nil
    self.attachedImplement = nil

    g_inputBinding:setActionEventTextVisibility(self.attachEvent, false)
end

function ManualAttach:onVehicleListChanged(vehicles)
    if #vehicles == 0 then
        self:reset()
    end

    self.vehicles = vehicles
end

function ManualAttach:getIsValidPlayer()
    return g_currentMission.controlPlayer
    --    self.mission.controlPlayer and
    --            self.mission.player ~= nil and
    --            self.mission.player.currentTool == nil and
    --            not self.mission.player.isCarryingObject and
    --            not self.mission.isPlayerFrozen
end

function ManualAttach:onAttachEvent()
    if self.attacherVehicle ~= nil then
        if self.attachable ~= nil and g_currentMission.accessHandler:canFarmAccess(self.attacherVehicle:getActiveFarm(), self.attachable) then
            -- attach
            print("OKe we should attach?")
            if self.attacherVehicle.spec_attacherJoints.attacherJoints[self.attacherVehicleJointDescIndex].jointIndex == 0 then
                self.attacherVehicle:attachImplement(self.attachable, self.attachableJointDescIndex, self.attacherVehicleJointDescIndex)
            end
        end
    end

    -- detach
    local object = self.attachedImplement
    if object ~= nil and object ~= self.attacherVehicle and object.isDetachAllowed ~= nil then
        local detachAllowed, warning, showWarning = object:isDetachAllowed()
        if detachAllowed then
            if object.getAttacherVehicle ~= nil then
                local attacherVehicle = object:getAttacherVehicle()
                if attacherVehicle ~= nil then
                    attacherVehicle:detachImplementByObject(object)
                end
            end
        elseif showWarning == nil or showWarning then
            g_currentMission:showBlinkingWarning(warning or g_i18n:getText("warning_detachNotAllowed"), 2000)
        end
    end
end

function ManualAttach:registerActionEvents()
    local _, eventId = g_inputBinding:registerActionEvent(InputAction.MA_ATTACH_VEHICLE, self, self.onAttachEvent, false, true, false, true)
    g_inputBinding:setActionEventTextVisibility(eventId, false)

    self.attachEvent = eventId
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
            --            vehicleTypeManager:addSpecialization(typeName, modName .. ".manualAttachExtension")
        end
    end
end