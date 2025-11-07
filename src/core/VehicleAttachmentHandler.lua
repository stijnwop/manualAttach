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

VehicleAttachmentHandler.MAX_ATTACH_DISTANCE_SQ = 0.7 * 0.7
VehicleAttachmentHandler.MAX_ATTACH_ANGLE = 0.34202
VehicleAttachmentHandler.PLAYER_MIN_DISTANCE_SQ = 8

VehicleAttachmentHandler.AUTO_ATTACH_DISTANCE_SQ = 0.5 * 0.5
VehicleAttachmentHandler.AUTO_ATTACH_ANGLE = 0.17452
VehicleAttachmentHandler.AUTO_ATTACH_CHECK_INTERVAL = 1000 -- ms

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
    actionGroups: ActionGroups,

    detectedVehicles: { Vehicle },
    controlledVehicle: Vehicle?,

    attacherVehicle: Vehicle?,
    attacherVehicleJointDescIndex: number?,
    attachable: Vehicle?,
    attachableJointDescIndex: number?,
    attachedImplement: Vehicle?,

    playerCanPerformManualAttachment: boolean,
    autoAttachTimer: number,
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
    self.contextDisplay:setScale(gameSettings:getValue(GameSettings.SETTING.UI_SCALE))

    self.vehicleJointAttachment = VehicleJointAttachment.new(mission, i18n)
    self.powerTakeOffAttachment = PowerTakeOffAttachment.new(mission, i18n)
    self.connectionHosesAttachment = ConnectionHosesAttachment.new(mission, i18n)

    self.attachments = {
        self.vehicleJointAttachment,
        self.powerTakeOffAttachment,
        self.connectionHosesAttachment,
    }

    self.actionGroups = ActionGroups.new(input)

    self.playerCanPerformManualAttachment = false
    self.detectedVehicles = {}
    self.controlledVehicle = nil
    self.autoAttachTimer = 0

    return setmetatable(self :: VehicleAttachmentHandlerData, customMt or VehicleAttachmentHandler_mt)
end

function VehicleAttachmentHandler:delete(): ()
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
    self:updateCandidates()

    if self.isServer then
        self:checkAutoAttach(dt)
    end

    self.contextDisplay:update(dt)
    self.detectionHandler:update(dt)
end

function VehicleAttachmentHandler:updateCandidates(): ()
    if #self.detectedVehicles == 0 then
        return
    end

    self.attacherVehicle, self.attacherVehicleJointDescIndex, self.attachable, self.attachableJointDescIndex, self.attachedImplement = VehicleAttachmentHandler.getCandidatesInAttachRange(
        self.mission.vehicleSystem,
        self.detectedVehicles,
        VehicleAttachmentHandler.MAX_ATTACH_DISTANCE_SQ,
        VehicleAttachmentHandler.MAX_ATTACH_ANGLE,
        self.playerCanPerformManualAttachment
    )
end

function VehicleAttachmentHandler:draw(): ()
    if #self.detectedVehicles == 0 or not self.playerCanPerformManualAttachment then
        return
    end

    local attachedImplement = self:getTargetImplement()
    local prevEventInfo = nil

    for _, attachment in ipairs(self.attachments) do
        local eventInfo = attachment:getActionEventInfo(self.attacherVehicle, self.attachable, attachedImplement, self.attacherVehicleJointDescIndex, self.playerCanPerformManualAttachment)

        self:updateActionEventDisplay(eventInfo, prevEventInfo)
        self:updateContextDisplay(attachment, attachedImplement)

        prevEventInfo = eventInfo
    end

    self.contextDisplay:draw()
end

function VehicleAttachmentHandler:updateActionEventDisplay(eventInfo: any, prevEventInfo: any?): ()
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
end

function VehicleAttachmentHandler:updateContextDisplay(attachment: BaseAttachment, attachedImplement: Vehicle?): ()
    local text, priority = attachment:getContextInfo(self.attacherVehicle, self.attachable, attachedImplement, self.attacherVehicleJointDescIndex, self.playerCanPerformManualAttachment)

    if text ~= nil then
        self.contextDisplay:setContext(InputAction.MA_ATTACH_VEHICLE, attachment.contextIcon, text, priority, self.i18n:getText("input_ATTACH"))
    end
end

---Checks for auto-attach opportunities and performs attachment if conditions are met
function VehicleAttachmentHandler:checkAutoAttach(dt: number): ()
    self.autoAttachTimer += dt
    if self.autoAttachTimer < VehicleAttachmentHandler.AUTO_ATTACH_CHECK_INTERVAL then
        return
    end

    self.autoAttachTimer = 0

    if self.controlledVehicle == nil or self.controlledVehicle:getLastSpeed() < 1 or self.controlledVehicle.movingDirection > 0 then
        return
    end

    self:checkVehicleAutoAttach(self.controlledVehicle)
end

---Checks if a specific vehicle can auto-attach to nearby implements
function VehicleAttachmentHandler:checkVehicleAutoAttach(vehicle: Vehicle): ()
    local spec = vehicle.spec_attacherJoints
    if spec == nil then
        return
    end

    if vehicle.getAttachedImplements ~= nil then
        local implements = vehicle:getAttachedImplements()
        for i = 1, #implements do
            local implement = implements[i]
            if implement.object ~= nil then
                self:checkVehicleAutoAttach(implement.object)
            end
        end
    end

    local attacherJoints = spec.attacherJoints
    for i = 1, #attacherJoints do
        local attacherJoint = attacherJoints[i]

        if attacherJoint.jointIndex == 0 and ManualAttach.isAutoJointType(attacherJoint) then
            self:tryAutoAttach(vehicle, attacherJoint, i)
        end
    end
end

---Attempts to auto-attach an implement to a vehicle if conditions are met
function VehicleAttachmentHandler:tryAutoAttach(vehicle: Vehicle, attacherJoint: any, attacherJointIndex: number): ()
    local attachableInRange, attachableJointDescIndex = VehicleAttachmentHandler.getAttachableInJointRange(
        self.mission.vehicleSystem,
        vehicle,
        attacherJoint,
        VehicleAttachmentHandler.AUTO_ATTACH_DISTANCE_SQ,
        VehicleAttachmentHandler.AUTO_ATTACH_ANGLE,
        false
    )

    if attachableInRange ~= nil and attachableJointDescIndex ~= nil then
        self.vehicleJointAttachment:performAttachment(vehicle, attachableInRange, nil, attacherJointIndex, attachableJointDescIndex, false)
    end
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
    self.playerCanPerformManualAttachment = canPerform
end

---Updates the controlled vehicle for manual attachment
function VehicleAttachmentHandler:updateControlledVehicle(vehicle: Vehicle?): ()
    local firstVehicle = self.detectedVehicles[1]
    local hasChanged = (self.controlledVehicle ~= vehicle) or (self.controlledVehicle ~= nil and firstVehicle ~= self.controlledVehicle)

    if not hasChanged then
        return
    end

    self:resetCandidates()

    if vehicle ~= nil and DetectionHandler.canHandleVehicle(vehicle) then
        self.detectionHandler:clear()
        self.controlledVehicle = vehicle
        self:onVehicleListChanged({ vehicle })
    else
        self.controlledVehicle = nil
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
    if not self.isClient then
        return
    end

    local handlers = {
        {
            inputAction = InputAction.MA_ATTACH_VEHICLE,
            attachment = self.vehicleJointAttachment,
            handler = ActionGroups.createImmediateHandler(function()
                self:executeAttachment(self.vehicleJointAttachment)
            end),
        },
        {
            inputAction = InputAction.MA_ATTACH_PTO_HOSE,
            attachment = self.powerTakeOffAttachment,
            handler = ActionGroups.createShortPressHandler(function()
                self:executeAttachment(self.powerTakeOffAttachment)
            end, 150),
        },
        {
            inputAction = InputAction.MA_ATTACH_PTO_HOSE,
            attachment = self.connectionHosesAttachment,
            handler = ActionGroups.createLongPressHandler(function()
                self:executeAttachment(self.connectionHosesAttachment)
            end, 350),
        },
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

        if not VehicleAttachmentHandler.isValidJointCandidate(vehicle, attacherJoint, jointVehicle, jointInfo, isPlayerBased) then
            continue
        end

        local translation = jointInfo.translation
        local distSq, distSqY = VehicleAttachmentHandler.calculateJointDistance(x, y, z, translation)

        if not VehicleAttachmentHandler.isWithinDistanceThresholds(distSq, distSqY, minDist, minDistY, maxDistanceSq, maxDistanceSq4) then
            continue
        end

        if not VehicleAttachmentHandler.canAcceptAttachment(jointVehicle) then
            continue
        end

        if VehicleAttachmentHandler.isWithinAngleLimit(jointInfo, attacherJoint, maxAngle) then
            minDist = distSq
            minDistY = distSqY
            attachableInRange = jointVehicle
            attachableJointDescIndex = jointInfo.jointIndex
        end
    end

    return attachableInRange, attachableJointDescIndex
end

function VehicleAttachmentHandler.isValidJointCandidate(vehicle: Vehicle, attacherJoint: any, jointVehicle: Vehicle, jointInfo: any, isPlayerBased: boolean): boolean
    if jointVehicle == vehicle or attacherJoint.jointType ~= jointInfo.jointType then
        return false
    end

    if not jointVehicle:getIsInputAttacherActive(jointInfo.inputAttacherJoint) then
        return false
    end

    local inputAttacherJoint = jointInfo.inputAttacherJoint
    local allowPlayerHandling = ManualAttach.isManualJointType(inputAttacherJoint)

    return (not isPlayerBased and ManualAttach.isAutoJointType(inputAttacherJoint)) or (not isPlayerBased and not allowPlayerHandling) or (isPlayerBased and allowPlayerHandling)
end

function VehicleAttachmentHandler.calculateJointDistance(x: number, y: number, z: number, translation: { number }): (number, number)
    local dx = x - translation[1]
    local dz = z - translation[3]
    local distSq = dx * dx + dz * dz

    local distY = y - translation[2]
    local distSqY = distY * distY

    return distSq, distSqY
end

function VehicleAttachmentHandler.isWithinDistanceThresholds(distSq: number, distSqY: number, minDist: number, minDistY: number, maxDistanceSq: number, maxDistanceSq4: number): boolean
    return distSq < maxDistanceSq and distSq < minDist and distSqY < maxDistanceSq4 and distSqY < minDistY
end

function VehicleAttachmentHandler.canAcceptAttachment(jointVehicle: Vehicle): boolean
    local activeJointIndex = jointVehicle:getActiveInputAttacherJointDescIndex()
    return activeJointIndex == nil or jointVehicle:getAllowMultipleAttachments()
end

function VehicleAttachmentHandler.isWithinAngleLimit(jointInfo: any, attacherJoint: any, maxAngle: number): boolean
    local attachAngleLimitAxis = jointInfo.inputAttacherJoint.attachAngleLimitAxis
    local axis = AXIS_LOOKUP[attachAngleLimitAxis]

    local dx, dy, dz = localDirectionToLocal(jointInfo.node, attacherJoint.jointTransform, axis[1], axis[2], axis[3])
    local d = { dx, dy, dz }

    return d[attachAngleLimitAxis] > maxAngle
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
            local aVehicle, aJointIndex, aAttachable, aAttachJointIndex, aImplement =
                VehicleAttachmentHandler.processAttachedImplements(vehicle, vehicleSystem, maxDistanceSq, maxAngle, isPlayerBased, playerRootNode, minPlayerAttachedImplDist)

            if aVehicle ~= nil then
                return aVehicle, aJointIndex, aAttachable, aAttachJointIndex, aImplement
            end

            if aImplement ~= nil then
                attachedImplement = aImplement
                minPlayerAttachedImplDist = math.min(minPlayerAttachedImplDist, VehicleAttachmentHandler.PLAYER_MIN_DISTANCE_SQ)
            end
        end

        local foundVehicle, foundJointIndex, foundAttachable, foundAttachableJointIndex =
            VehicleAttachmentHandler.processAttacherJoints(vehicle, spec.attacherJoints, vehicleSystem, maxDistanceSq, maxAngle, isPlayerBased, playerRootNode, minPlayerDist)

        if foundVehicle ~= nil then
            attacherVehicle = foundVehicle
            attacherVehicleJointDescIndex = foundJointIndex
            attachable = foundAttachable
            attachableJointDescIndex = foundAttachableJointIndex

            if isPlayerBased then
                local x, y, z = localToLocal(spec.attacherJoints[foundJointIndex].jointTransform, playerRootNode, 0, 0, 0)
                minPlayerDist = x * x + y * y + z * z
            end
        end
    end

    return attacherVehicle, attacherVehicleJointDescIndex, attachable, attachableJointDescIndex, attachedImplement
end

function VehicleAttachmentHandler.processAttachedImplements(
    vehicle: Vehicle,
    vehicleSystem: VehicleSystem,
    maxDistanceSq: number,
    maxAngle: number,
    isPlayerBased: boolean,
    playerRootNode: number?,
    minPlayerAttachedImplDist: number
): (Vehicle?, number?, Vehicle?, number?, Vehicle?)
    local implements = vehicle:getAttachedImplements()
    local closestImplement = nil

    for j = 1, #implements do
        local implement = implements[j]
        local object = implement.object

        if object == nil then
            continue
        end

        if isPlayerBased then
            local spec = vehicle.spec_attacherJoints
            local attacherJoint = spec.attacherJoints[implement.jointDescIndex]
            local x, y, z = localToLocal(attacherJoint.jointTransform, playerRootNode, 0, 0, 0)
            local distSq = x * x + y * y + z * z

            if distSq < VehicleAttachmentHandler.PLAYER_MIN_DISTANCE_SQ and distSq < minPlayerAttachedImplDist then
                closestImplement = object
                minPlayerAttachedImplDist = distSq
            end
        else
            local aVehicle, aJointIndex, aAttachable, aAttachJointIndex, aImplement =
                VehicleAttachmentHandler.getCandidatesInAttachRange(vehicleSystem, { object }, maxDistanceSq, maxAngle, isPlayerBased)

            if aVehicle ~= nil then
                return aVehicle, aJointIndex, aAttachable, aAttachJointIndex, aImplement
            end
        end
    end

    return nil, nil, nil, nil, closestImplement
end

function VehicleAttachmentHandler.processAttacherJoints(
    vehicle: Vehicle,
    attacherJoints: any,
    vehicleSystem: VehicleSystem,
    maxDistanceSq: number,
    maxAngle: number,
    isPlayerBased: boolean,
    playerRootNode: number?,
    minPlayerDist: number
): (Vehicle?, number?, Vehicle?, number?)
    for k = 1, #attacherJoints do
        local attacherJoint = attacherJoints[k]

        if attacherJoint.jointIndex ~= 0 then
            continue
        end

        local isInRange = not isPlayerBased

        if isPlayerBased then
            local x, y, z = localToLocal(attacherJoint.jointTransform, playerRootNode, 0, 0, 0)
            local distSq = x * x + y * y + z * z
            isInRange = distSq < VehicleAttachmentHandler.PLAYER_MIN_DISTANCE_SQ and distSq < minPlayerDist
        end

        if isInRange then
            local attachableInRange, attachableJointDescIndexInRange =
                VehicleAttachmentHandler.getAttachableInJointRange(vehicleSystem, vehicle, attacherJoint, maxDistanceSq, maxAngle, isPlayerBased)

            if attachableInRange ~= nil then
                return vehicle, k, attachableInRange, attachableJointDescIndexInRange
            end
        end
    end

    return nil, nil, nil, nil
end

---------------------------
--- Multiplayer support ---
---------------------------

function VehicleAttachmentHandler:attachPowerTakeOff(vehicle, object, noEventSend): ()
    self.powerTakeOffAttachment:attachPowerTakeOff(vehicle, object, noEventSend)
end

function VehicleAttachmentHandler:detachPowerTakeOff(vehicle, object, noEventSend): ()
    self.powerTakeOffAttachment:detachPowerTakeOff(vehicle, object, noEventSend)
end

function VehicleAttachmentHandler:attachConnectionHoses(vehicle, object, noEventSend): ()
    self.connectionHosesAttachment:attachConnectionHoses(vehicle, object, noEventSend)
end

function VehicleAttachmentHandler:detachConnectionHoses(vehicle, object, noEventSend): ()
    self.connectionHosesAttachment:detachConnectionHoses(vehicle, object, noEventSend)
end
