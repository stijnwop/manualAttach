--
-- VehicleAttachmentHandler
--
-- Author: Wopster
-- Description: Manages vehicle detection and attach range finding
-- Name: VehicleAttachmentHandler
-- Hide: yes
--
-- Copyright (c) Wopster

---@class VehicleAttachmentHandler
VehicleAttachmentHandler = {}
local VehicleAttachmentHandler_mt = Class(VehicleAttachmentHandler)

VehicleAttachmentHandler.PLAYER_MIN_DISTANCE_SQ = 8

local AXIS_LOOKUP = table.freeze({
    table.freeze({ 1, 0, 0 }), -- X axis
    table.freeze({ 0, 1, 0 }), -- Y axis
    table.freeze({ 0, 0, 1 }), -- Z axis
})

type VehicleAttachmentHandlerData = {
    isServer: boolean,
    isClient: boolean,

    mission: BaseMission,
    modDirectory: string,

    i18n: I18N,
    input: InputBinding,

    detectionHandler: DetectionHandler,
    contextDisplay: ContextActionDisplay,

    vehicleJointAttachment: VehicleJointAttachment,
    powerTakeOffAttachment: PowerTakeOffAttachment,
    connectionHosesAttachment: ConnectionHosesAttachment,

    attachments: { BaseAttachment },

    detectedVehicles: { Vehicle },
    controlledVehicle: Vehicle?,

    attacherVehicle: Vehicle?,
    attacherVehicleJointDescIndex: number?,
    attachable: Vehicle?,
    attachableJointDescIndex: number?,
    attachedImplement: Vehicle?,
}

export type VehicleAttachmentHandler = typeof(setmetatable({} :: VehicleAttachmentHandlerData, VehicleAttachmentHandler_mt))

---Creates a new instance of VehicleAttachmentHandler.
function VehicleAttachmentHandler.new(
    mission: BaseMission,
    modDirectory: string,
    i18n: I18N,
    input: InputBinding,
    inputDisplayManager: InputDisplayManager,
    gameSettings: GameSettings,
    customMt: any
): VehicleAttachmentHandler
    local self = {}

    self.isServer = mission:getIsServer()
    self.isClient = mission:getIsClient()

    self.mission = mission
    self.modDirectory = modDirectory

    self.input = input
    self.i18n = i18n

    self.detectionHandler = DetectionHandler.new(mission, modDirectory)
    self.detectionHandler:addDetectionListener(self)

    self.contextDisplay = ContextActionDisplay.new()
    local scale = gameSettings:getValue(GameSettings.SETTING.UI_SCALE)
    self.contextDisplay:setScale(scale)

    self.vehicleJointAttachment = VehicleJointAttachment.new(mission, i18n)
    self.powerTakeOffAttachment = PowerTakeOffAttachment.new(mission, i18n)
    self.connectionHosesAttachment = ConnectionHosesAttachment.new(mission, i18n)

    self.attachments = {
        self.vehicleJointAttachment,
        self.powerTakeOffAttachment,
        self.connectionHosesAttachment,
    }

    self.actionGroups = ActionGroups.new(self.input)

    self.playerCanPerformManualAttachment = false

    self.detectedVehicles = {}
    self.controlledVehicle = nil

    self.attacherVehicle = nil
    self.attacherVehicleJointDescIndex = nil
    self.attachable = nil
    self.attachableJointDescIndex = nil
    self.attachedImplement = nil

    return setmetatable(self :: VehicleAttachmentHandlerData, customMt or VehicleAttachmentHandler_mt)
end

function VehicleAttachmentHandler:delete(): ()
    local self = self :: VehicleAttachmentHandler

    for _, attachment in ipairs(self.attachments) do
        attachment:delete()
    end

    self.detectionHandler:delete()
    self.contextDisplay:delete()
end

function VehicleAttachmentHandler:onPlayerLoad(player: Player): ()
    if self.isClient and g_localPlayer == player and player.isOwner then
        self:registerActionEvents()
    end

    self.detectionHandler:onPlayerLoad(player)
end

function VehicleAttachmentHandler:onPlayerDelete(player: Player): ()
    if g_localPlayer == player and player.isOwner then
        self:unregisterActionEvents()
    end

    self.detectionHandler:onPlayerDelete(player)
end

function VehicleAttachmentHandler:update(dt: number): ()
    local self = self :: VehicleAttachmentHandler

    if #self.detectedVehicles > 0 then
        self.attacherVehicle, self.attacherVehicleJointDescIndex, self.attachable, self.attachableJointDescIndex, self.attachedImplement =
            VehicleAttachmentHandler.getCandidatesInAttachRange(
                self.mission.vehicleSystem,
                self.detectedVehicles,
                AttacherJoints.MAX_ATTACH_DISTANCE_SQ,
                AttacherJoints.MAX_ATTACH_ANGLE,
                self.playerCanPerformManualAttachment
            )
    end

    self.contextDisplay:update(dt)
    self.detectionHandler:update(dt)
end

function VehicleAttachmentHandler:draw(): ()
    local self = self :: VehicleAttachmentHandler

    if #self.detectedVehicles == 0 then
        return
    end

    local attachedImplement = self:getTargetImplement()

    local prevEventInfo = nil
    for i, attachment in ipairs(self.attachments) do
        local eventInfo =
            attachment:getActionEventInfo(self.attacherVehicle, self.attachable, self.attachedImplement, self.attacherVehicleJointDescIndex, self.playerCanPerformManualAttachment)

        -- Perhaps at some point render this based on the action groups to avoid these checks, it only works cause the attachments are in order.
        local shouldUseExtraInfo = eventInfo.isExtraInfo and eventInfo.text ~= nil
        if shouldUseExtraInfo and prevEventInfo ~= nil and not prevEventInfo.visibility then
            shouldUseExtraInfo = false
        end

        if shouldUseExtraInfo then
            self.mission:addExtraPrintText(eventInfo.text)
        else
            self.input:setActionEventText(eventInfo.id, eventInfo.text)
            self.input:setActionEventTextPriority(eventInfo.id, eventInfo.priority)
            self.input:setActionEventTextVisibility(eventInfo.id, eventInfo.visibility)
        end

        local text, priority =
            attachment:getContextInfo(self.attacherVehicle, self.attachable, self.attachedImplement, self.attacherVehicleJointDescIndex, self.playerCanPerformManualAttachment)

        if text ~= nil then
            self.contextDisplay:setContext(InputAction.MA_ATTACH_VEHICLE, attachment.contextIcon, text, priority, self.i18n:getText("input_ATTACH"))
        end

        prevEventInfo = eventInfo
    end

    self.contextDisplay:draw()
end

function VehicleAttachmentHandler:isCurrentAttachableManual(): boolean
    return self:isAttachableManual(self.attachable)
end

function VehicleAttachmentHandler:isAttachableManual(attachable: Vehicle?): boolean
    return self:isVehicleAttachableManual(self.attacherVehicle, attachable, self.attacherVehicleJointDescIndex)
end

function VehicleAttachmentHandler:isVehicleAttachableManual(vehicle: Vehicle?, attachable: Vehicle?, attacherVehicleJointDescIndex: number?): boolean
    if vehicle == nil or attachable == nil then
        return false
    end

    return ManualAttach.shouldHandleJoint(vehicle, attachable, attacherVehicleJointDescIndex, self.playerCanPerformManualAttachment)
end

---Called when player's capability to perform manual attachments changes
function VehicleAttachmentHandler:onPlayerCapabilityChanged(player: Player, canPerform: boolean): ()
    local self = self :: VehicleAttachmentHandler
    self.playerCanPerformManualAttachment = canPerform
end

---Updates the controlled vehicle for manual attachment
function VehicleAttachmentHandler:updateControlledVehicle(vehicle: Vehicle?): ()
    local self = self :: VehicleAttachmentHandler

    if self.controlledVehicle ~= vehicle then
        self:resetCandidates()

        if vehicle ~= nil and DetectionHandler.canHandleVehicle(vehicle) then
            self.controlledVehicle = vehicle
            self:onVehicleListChanged({ vehicle })
        else
            self.controlledVehicle = nil
        end
    end
end

---Called by DetectionHandler when vehicle list changes
function VehicleAttachmentHandler:onVehicleListChanged(vehicles: { Vehicle }): ()
    self.detectedVehicles = vehicles

    if #vehicles == 0 then
        self:resetCandidates()
    end
end

---Called by DetectionHandler when trigger state changes
function VehicleAttachmentHandler:onTriggerChanged(isRemoved: boolean): ()
    if isRemoved then
        self:resetCandidates()
    end
end

---Registers action events for attachments
function VehicleAttachmentHandler:registerActionEvents(): ()
    local self = self :: VehicleAttachmentHandler

    if not self.isClient then
        return
    end

    local vehicleJointAttachmentHandler = ActionGroups.createImmediateHandler(function()
        self:executeAttachment(self.vehicleJointAttachment)
    end)

    local powerTakeOffAttachmentHandler = ActionGroups.createShortPressHandler(function()
        self:executeAttachment(self.powerTakeOffAttachment)
    end, 150) -- ms

    local connectionHosesAttachmentHandler = ActionGroups.createLongPressHandler(function()
        self:executeAttachment(self.connectionHosesAttachment)
    end, 500) -- ms

    local handlers = {
        { inputAction = InputAction.MA_ATTACH_VEHICLE, attachment = self.vehicleJointAttachment, handler = vehicleJointAttachmentHandler },
        { inputAction = InputAction.MA_ATTACH_PTO_HOSE, attachment = self.powerTakeOffAttachment, handler = powerTakeOffAttachmentHandler },
        { inputAction = InputAction.MA_ATTACH_PTO_HOSE, attachment = self.connectionHosesAttachment, handler = connectionHosesAttachmentHandler },
    }

    for _, entry in ipairs(handlers) do
        self.actionGroups:registerHandler(entry.inputAction, entry.handler)
    end

    self.actionGroups:registerActionEvents(PlayerInputComponent.INPUT_CONTEXT_NAME)

    for _, entry in ipairs(handlers) do
        entry.attachment:setInputActionEventId(self.actionGroups:getEventId(entry.inputAction))
    end
end

function VehicleAttachmentHandler:executeAttachment(attachment: BaseAttachment): ()
    local attachedImplement = self:getTargetImplement()

    attachment:performAttachment(
        self.attacherVehicle,
        self.attachable,
        attachedImplement,
        self.attacherVehicleJointDescIndex,
        self.attachableJointDescIndex,
        self.playerCanPerformManualAttachment
    )
end

---Gets the target attached implement
function VehicleAttachmentHandler:getTargetImplement(): Vehicle?
    if not self.playerCanPerformManualAttachment and self.controlledVehicle ~= nil then
        return self.controlledVehicle:getSelectedVehicle()
    end

    return self.attachedImplement
end

---Unregisters action events for attachments
function VehicleAttachmentHandler:unregisterActionEvents(): ()
    local self = self :: VehicleAttachmentHandler

    self.actionGroups:unregisterAll(PlayerInputComponent.INPUT_CONTEXT_NAME)

    for _, attachment in ipairs(self.attachments) do
        attachment.inputActionEventId = nil
    end
end

function VehicleAttachmentHandler:resetCandidates(): ()
    self.attacherVehicle = nil
    self.attacherVehicleJointDescIndex = nil
    self.attachable = nil
    self.attachableJointDescIndex = nil
    self.attachedImplement = nil
end

---Gets closest attachable in joint range.
function VehicleAttachmentHandler.getAttachableInJointRange(
    vehicleSystem: VehicleSystem,
    vehicle: Vehicle,
    attacherJoint: any,
    maxDistanceSq: number,
    maxAngle: number,
    isPlayerBased: boolean
): (Vehicle?, number?)
    local attachableInRange = nil
    local attachableJointDescIndex = nil
    local minDist = math.huge
    local minDistY = math.huge

    local x, y, z = getWorldTranslation(attacherJoint.jointTransform)
    local inputAttacherJoints = vehicleSystem.inputAttacherJoints
    local maxDistanceSq4 = maxDistanceSq * 4

    for i = 1, #inputAttacherJoints do
        local jointInfo = inputAttacherJoints[i]
        local jointVehicle = jointInfo.vehicle

        if jointVehicle == vehicle or attacherJoint.jointType ~= jointInfo.jointType then
            continue
        end

        if not jointVehicle:getIsInputAttacherActive(jointInfo.inputAttacherJoint) then
            continue
        end

        local inputAttacherJoint = jointInfo.inputAttacherJoint
        local allowPlayerHandling = ManualAttach.isManualJointType(inputAttacherJoint)
        local isValid = (not isPlayerBased and not allowPlayerHandling) or (isPlayerBased and allowPlayerHandling)

        if not isValid then
            continue
        end

        local translation = jointInfo.translation
        local dx = x - translation[1]
        local dz = z - translation[3]
        local distSq = dx * dx + dz * dz

        if distSq >= maxDistanceSq or distSq >= minDist then
            continue
        end

        local distY = y - translation[2]
        local distSqY = distY * distY

        if distSqY >= maxDistanceSq4 or distSqY >= minDistY then
            continue
        end

        local activeJointIndex = jointVehicle:getActiveInputAttacherJointDescIndex()
        if activeJointIndex ~= nil and not jointVehicle:getAllowMultipleAttachments() then
            continue
        end

        local attachAngleLimitAxis = inputAttacherJoint.attachAngleLimitAxis
        local axis = AXIS_LOOKUP[attachAngleLimitAxis]

        local dx, dy, dz = localDirectionToLocal(jointInfo.node, attacherJoint.jointTransform, axis[1], axis[2], axis[3])
        local d = { dx, dy, dz }

        if d[attachAngleLimitAxis] > maxAngle then
            minDist = distSq
            minDistY = distSqY
            attachableInRange = jointVehicle
            attachableJointDescIndex = jointInfo.jointIndex
        end
    end

    return attachableInRange, attachableJointDescIndex
end

---Finds the attachable in range based on player or controlled vehicle.
function VehicleAttachmentHandler.getCandidatesInAttachRange(
    vehicleSystem: VehicleSystem,
    vehicles: { Vehicle },
    maxDistanceSq: number,
    maxAngle: number,
    isPlayerBased: boolean
): (Vehicle?, number?, Vehicle?, number?, Vehicle?)
    local attacherVehicle = nil
    local attacherVehicleJointDescIndex = nil
    local attachable = nil
    local attachableJointDescIndex = nil
    local attachedImplement = nil

    local minPlayerDist = math.huge
    local minPlayerAttachedImplDist = math.huge
    local player = isPlayerBased and g_localPlayer or nil
    local playerRootNode = player and player.rootNode or nil

    for i = 1, #vehicles do
        local vehicle = vehicles[i]

        if vehicle.isDeleted then
            continue
        end

        local spec = vehicle.spec_attacherJoints
        if spec == nil then
            continue
        end

        if vehicle.getAttachedImplements ~= nil then
            local implements = vehicle:getAttachedImplements()

            for j = 1, #implements do
                local implement = implements[j]
                local object = implement.object

                if object == nil then
                    continue
                end

                if isPlayerBased then
                    local attacherJoint = spec.attacherJoints[implement.jointDescIndex]
                    local x, y, z = localToLocal(attacherJoint.jointTransform, playerRootNode, 0, 0, 0)
                    local distSq = x * x + y * y + z * z

                    if attachedImplement ~= object and distSq < VehicleAttachmentHandler.PLAYER_MIN_DISTANCE_SQ and distSq < minPlayerAttachedImplDist then
                        minPlayerAttachedImplDist = distSq
                        attachedImplement = object
                    end
                else
                    local aVehicle, aJointIndex, aAttachable, aAttachJointIndex, aImplement =
                        VehicleAttachmentHandler.getCandidatesInAttachRange(vehicleSystem, { object }, maxDistanceSq, maxAngle, isPlayerBased)

                    if aVehicle ~= nil then
                        return aVehicle, aJointIndex, aAttachable, aAttachJointIndex, aImplement
                    end
                end
            end
        end

        local attacherJoints = spec.attacherJoints
        for k = 1, #attacherJoints do
            local attacherJoint = attacherJoints[k]

            if attacherJoint.jointIndex ~= 0 then
                continue
            end

            local isInRange = not isPlayerBased
            local distSq = math.huge

            if isPlayerBased then
                local x, y, z = localToLocal(attacherJoint.jointTransform, playerRootNode, 0, 0, 0)
                distSq = x * x + y * y + z * z
                isInRange = distSq < VehicleAttachmentHandler.PLAYER_MIN_DISTANCE_SQ and distSq < minPlayerDist
            end

            if isInRange then
                local attachableInRange, attachableJointDescIndexInRange =
                    VehicleAttachmentHandler.getAttachableInJointRange(vehicleSystem, vehicle, attacherJoint, maxDistanceSq, maxAngle, isPlayerBased)

                if attachableInRange ~= nil then
                    attacherVehicle = vehicle
                    attacherVehicleJointDescIndex = k
                    attachable = attachableInRange
                    attachableJointDescIndex = attachableJointDescIndexInRange

                    if isPlayerBased then
                        minPlayerDist = distSq
                    end
                end
            end
        end
    end

    return attacherVehicle, attacherVehicleJointDescIndex, attachable, attachableJointDescIndex, attachedImplement
end

---------------------------
--- Multiplayer support ---
---------------------------

function VehicleAttachmentHandler:attachPowerTakeOff(vehicle, object, noEventSend): ()
    local self = self :: VehicleAttachmentHandler
    self.powerTakeOffAttachment:attachPowerTakeOff(vehicle, object, noEventSend)
end

function VehicleAttachmentHandler:detachPowerTakeOff(vehicle, object, noEventSend): ()
    local self = self :: VehicleAttachmentHandler
    self.powerTakeOffAttachment:detachPowerTakeOff(vehicle, object, noEventSend)
end

function VehicleAttachmentHandler:attachConnectionHoses(vehicle, object, noEventSend): ()
    local self = self :: VehicleAttachmentHandler
    self.connectionHosesAttachment:attachConnectionHoses(vehicle, object, noEventSend)
end

function VehicleAttachmentHandler:detachConnectionHoses(vehicle, object, noEventSend): ()
    local self = self :: VehicleAttachmentHandler
    self.connectionHosesAttachment:detachConnectionHoses(vehicle, object, noEventSend)
end
