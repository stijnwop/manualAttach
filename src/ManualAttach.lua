--
-- ManualAttach
--
-- Author: Wopster
-- Description: base class for the Manual Attach mod.
-- Name: ManualAttach
-- Hide: yes
--
-- Copyright (c) Wopster

---@class ManualAttach
ManualAttach = {}
local ManualAttach_mt = Class(ManualAttach)

---Maps given name to the joint int.
---@param typeName string
---@return number the int joint type.
local function mapJointTypeNameToInt(typeName)
    local jointType = AttacherJoints.jointTypeNameToInt[typeName]
    -- Custom joints need a check if it exists in the game
    return jointType ~= nil and jointType or -1
end

ManualAttach.WARNING_TIMER_THRESHOLD = 2000 -- ms

-- Joint types that should NOT be manually attached (attach from controller vehicle only)
ManualAttach.NON_MANUAL_ATTACH_JOINTYPES = table.freeze({
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
    [mapJointTypeNameToInt("semitrailerCar")] = true,
    [mapJointTypeNameToInt("bigBag")] = true,
    -- Mods
    [mapJointTypeNameToInt("fastCoupler")] = true,
})

-- Joint types that should auto-attach when in close proximity
ManualAttach.AUTO_ATTACH_JOINTYPES = table.freeze({
    [mapJointTypeNameToInt("trailer")] = true,
})

type ManualAttachData = {
    isServer: boolean,
    isClient: boolean,

    modName: string,
    modDirectory: string,

    mission: BaseMission,
    i18n: I18N,
    soundManager: SoundManager,

    vehicleAttachmentHandler: VehicleAttachmentHandler,
    canPlayerPerformManualAttachment: boolean,
}

export type ManualAttach = typeof(setmetatable({} :: ManualAttachData, ManualAttach_mt))

---Creates a new instance of ManualAttach.
function ManualAttach.new(
    modName: string,
    modDirectory: string,
    mission: BaseMission,
    i18n: I18N,
    input: InputBinding,
    soundManager: SoundManager,
    inputDisplayManager: InputDisplayManager,
    gameSettings: GameSettings,
    customMt: any
): ManualAttach
    local self = {}

    self.isServer = mission:getIsServer()
    self.isClient = mission:getIsClient()
    self.modName = modName
    self.modDirectory = modDirectory
    self.mission = mission
    self.i18n = i18n
    self.soundManager = soundManager

    self.vehicleAttachmentHandler = VehicleAttachmentHandler.new(mission, modDirectory, i18n, input, inputDisplayManager, gameSettings)
    self.canPlayerPerformManualAttachment = false

    self.samples = {}

    if self.isClient then
        local xmlFile = loadXMLFile("ManualAttachSamples", Utils.getFilename("data/sounds/sounds.xml", self.modDirectory))
        if xmlFile ~= nil then
            local soundsNode = getRootNode()

            self.samples.hosesAttach = self.soundManager:loadSampleFromXML(xmlFile, "vehicle.sounds", "hosesAttach", self.modDirectory, soundsNode, 1, AudioGroup.VEHICLE, nil, nil)
            self.samples.ptoAttach = self.soundManager:loadSampleFromXML(xmlFile, "vehicle.sounds", "ptoAttach", self.modDirectory, soundsNode, 1, AudioGroup.VEHICLE, nil, nil)

            delete(xmlFile)
        end
    end

    return setmetatable(self :: ManualAttachData, customMt or ManualAttach_mt)
end

-- Called on delete.
function ManualAttach:delete(): ()
    local self = self :: ManualAttach
    self.vehicleAttachmentHandler:delete()
end

---Called on delete map by modEventListener
function ManualAttach:deleteMap(): ()
    local self = self :: ManualAttach

    if not g_modIsLoaded[self.modName] then
        return
    end

    self:delete()
end

---Called on update by modEventListener
function ManualAttach:update(dt: number): ()
    local self = self :: ManualAttach

    if not self.isClient then
        return
    end

    local player = self:getLocalPlayer()
    local canPerform = self:checkPlayerCanPerformManualAttachment(player)
    if canPerform ~= self.canPlayerPerformManualAttachment then
        self.canPlayerPerformManualAttachment = canPerform
        self.vehicleAttachmentHandler:onPlayerCapabilityChanged(player, canPerform)
    end

    if not canPerform then
        local controlledVehicle = player:getCurrentVehicle() --!nocheck
        self.vehicleAttachmentHandler:updateControlledVehicle(controlledVehicle)
    end

    self.vehicleAttachmentHandler:update(dt, canPerform)
end

---Called on draw by modEventListener
function ManualAttach:draw(): ()
    local self = self :: ManualAttach

    if not self.isClient then
        return
    end

    self.vehicleAttachmentHandler:draw()
end

---Gets the local player instance
function ManualAttach:getLocalPlayer(): Player?
    return g_localPlayer
end

---Returns true when manual attach is enabled and we are controlling a vehicle.
function ManualAttach:isPlayerControllingVehicle(): boolean
    local player = self:getLocalPlayer()

    if player == nil then
        return false
    end

    if player.getCurrentVehicle == nil then
        return false
    end

    local controlledVehicle = player:getCurrentVehicle()
    return controlledVehicle ~= nil
end

---Returns true if the current vehicle should be handled by manual attach.
function ManualAttach:isCurrentVehicleManual(): boolean
    local self = self :: ManualAttach
    return self.vehicleAttachmentHandler:isCurrentAttachableManual()
end

function ManualAttach:isVehicleAttachableManual(vehicle: Vehicle?, attachable: Vehicle?): boolean
    local self = self :: ManualAttach
    return self.vehicleAttachmentHandler:isVehicleAttachableManual(vehicle, attachable, nil)
end

---Checks if the player can currently perform manual attachments.
function ManualAttach:checkPlayerCanPerformManualAttachment(player: Player): boolean
    return player.isControlled and not player:getAreHandsHoldingObject() and not player:getIsHoldingHandTool() and not player:getIsInVehicle()
end

---Called when the player is loaded.
function ManualAttach:onPlayerLoad(player: Player): ()
    local self = self :: ManualAttach
    self.vehicleAttachmentHandler:onPlayerLoad(player)
end

---Called when the player is deleted.
function ManualAttach:onPlayerDelete(player: Player): ()
    local self = self :: ManualAttach
    self.vehicleAttachmentHandler:onPlayerDelete(player)
end

---Called when player starts the mission.
function ManualAttach:onStartMission(mission: FSBaseMission): ()
    local self = self :: ManualAttach
    self.canPlayerPerformManualAttachment = false
end

---------------------------
--- Multiplayer support ---
---------------------------

function ManualAttach:attachPowerTakeOff(vehicle, object, noEventSend): ()
    local self = self :: ManualAttach
    self.vehicleAttachmentHandler:attachPowerTakeOff(vehicle, object, noEventSend)
end

function ManualAttach:detachPowerTakeOff(vehicle, object, noEventSend): ()
    local self = self :: ManualAttach
    self.vehicleAttachmentHandler:detachPowerTakeOff(vehicle, object, noEventSend)
end

function ManualAttach:attachConnectionHoses(vehicle, object, noEventSend): ()
    local self = self :: ManualAttach
    self.vehicleAttachmentHandler:attachConnectionHoses(vehicle, object, noEventSend)
end

function ManualAttach:detachConnectionHoses(vehicle, object, noEventSend): ()
    local self = self :: ManualAttach
    self.vehicleAttachmentHandler:detachConnectionHoses(vehicle, object, noEventSend)
end

------------------------
--- Static functions ---
------------------------

---Returns true if given joint desc should be manually controlled, false otherwise.
function ManualAttach.isManualJointType(jointDesc: any): boolean
    if jointDesc == nil then
        return false
    end

    if jointDesc.isManual ~= nil then
        return jointDesc.isManual
    end

    return not ManualAttach.NON_MANUAL_ATTACH_JOINTYPES[jointDesc.jointType]
end

---Returns true if given joint desc could be auto-attached, false otherwise.
function ManualAttach.isAutoJointType(jointDesc: any): boolean
    if jointDesc == nil then
        return false
    end

    if jointDesc.isAuto ~= nil then
        return jointDesc.isAuto
    end

    return ManualAttach.AUTO_ATTACH_JOINTYPES[jointDesc.jointType]
end

---Determines if the joint should be handled by manual attach.
function ManualAttach.shouldHandleJoint(vehicle: any, object: any, jointIndex: number, playerCanPerformManualAttachment: boolean, canToggleAttach: boolean): boolean
    if vehicle == nil or object == nil then
        return false
    end

    local jointDesc = jointIndex ~= nil and vehicle:getAttacherJointByJointDescIndex(jointIndex) or vehicle:getAttacherJointDescFromObject(object)

    if jointDesc == nil then
        return false
    end

    if jointDesc.jointIndex == 0 and not canToggleAttach then
        local isAutoJoint = ManualAttach.isAutoJointType(jointDesc)
        if isAutoJoint and not playerCanPerformManualAttachment then
            return true
        end
    end

    local isManualJoint = ManualAttach.isManualJointType(jointDesc)

    -- Handle manual joints when player can perform manual attachment
    -- Handle non-manual joints when player cannot perform manual attachment (auto-attach/detach)
    return isManualJoint == playerCanPerformManualAttachment
end

---Check whether or not ManualAttach can detach the object.
function ManualAttach.isDetachAllowedForManualHandling(object: any, vehicle: any, jointDesc: any): (boolean, string?, string?)
    local detachAllowed, warningKey, warningArg = true, nil, nil

    if ManualAttach.isManualJointType(jointDesc) then
        local allowsLowering = object:getAllowsLowering()

        if allowsLowering and jointDesc.allowsLowering and not object:getIsFoldMiddleAllowed() then
            -- Allow detaching of vehicles that are forced on turned on by lowering.
            local spec_sprayer = object.spec_sprayer
            local isActivatedOnLowering = spec_sprayer ~= nil and spec_sprayer.activateOnLowering

            if not jointDesc.moveDown and not isActivatedOnLowering then
                detachAllowed = false
                warningKey = "info_lower_warning"
                warningArg = object:getFullName()
            end
        end
    end

    if detachAllowed then
        if PowerTakeOffExtension.hasPowerTakeOffs(object, vehicle) and PowerTakeOffExtension.hasAttachedPowerTakeOffs(object, vehicle) then
            detachAllowed = false
            warningKey = "info_detach_pto_warning"
            warningArg = object:getFullName()
        end
    end

    if detachAllowed then
        if ConnectionHosesExtension.hasConnectionHoses(object, vehicle) and ConnectionHosesExtension.hasAttachedConnectionHoses(object) then
            detachAllowed = false
            warningKey = "info_detach_hoses_warning"
            warningArg = object:getFullName()
        end
    end

    return detachAllowed, warningKey, warningArg
end
