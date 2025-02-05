--
-- main
--
-- Author: Wopster
-- Description:  Main script to handle all sources for Manual Attach.
-- Name: main
-- Hide: yes
--
-- Copyright (c) Wopster, 2021

---@type string directory of the mod.
local modDirectory = g_currentModDirectory or ""
---@type string name of the mod.
local modName = g_currentModName or "unknown"

---@type ManualAttach current manual attach instance
local modEnvironment

source(modDirectory .. "src/ManualAttach.lua")
source(modDirectory .. "src/events/ManualAttachPowerTakeOffEvent.lua")
source(modDirectory .. "src/events/ManualAttachConnectionHosesEvent.lua")
source(modDirectory .. "src/utils/ManualAttachUtil.lua")
source(modDirectory .. "src/misc/ManualAttachDetectionHandler.lua")

---Fix for registering the savegame schema (perhaps this can be better).
g_manualAttachModName = modName

local function load(mission)
    assert(mission.manualAttach == nil)
    modEnvironment = ManualAttach:new(mission, g_inputBinding, g_i18n, g_inputDisplayManager, g_soundManager, modDirectory, modName)
    mission.manualAttach = modEnvironment
    addModEventListener(modEnvironment)
end

local function unload()
    if modEnvironment ~= nil then
        removeModEventListener(modEnvironment)
        modEnvironment:delete()
        modEnvironment = nil -- Allows garbage collecting

        if g_currentMission ~= nil then
            g_currentMission.manualAttach = nil
        end
    end
end

local function startMission(mission)
    modEnvironment:onMissionStart(mission)
end

local function initSpecialization(typeManager)
    if typeManager.typeName == "vehicle" then
        ManualAttach.installSpecializations(g_vehicleTypeManager, g_specializationManager, modDirectory, modName)
    end
end

local function init()
    FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, unload)

    Mission00.load = Utils.prependedFunction(Mission00.load, load)
    Mission00.onStartMission = Utils.appendedFunction(Mission00.onStartMission, startMission)

    TypeManager.validateTypes = Utils.prependedFunction(TypeManager.validateTypes, initSpecialization)

    Player.onEnterVehicle = Utils.appendedFunction(Player.onEnterVehicle, ManualAttach.inj_onEnter)
    Player.onLeaveVehicle = Utils.appendedFunction(Player.onLeaveVehicle, ManualAttach.inj_onLeave)
    Player.onEnterVehicleAsPassenger = Utils.appendedFunction(Player.onEnterVehicleAsPassenger, ManualAttach.inj_onEnter)
    Player.onLeaveVehicleAsPassenger = Utils.appendedFunction(Player.onLeaveVehicleAsPassenger, ManualAttach.inj_onLeave)
    Player.load = Utils.appendedFunction(Player.load, ManualAttach.inj_load)
    Player.delete = Utils.prependedFunction(Player.delete, ManualAttach.inj_delete)

    -- InGameMenuGeneralSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuGeneralSettingsFrame.onFrameOpen, ManualAttach.initGui)
    -- InGameMenuGeneralSettingsFrame.updateGameSettings = Utils.appendedFunction(InGameMenuGeneralSettingsFrame.updateGameSettings, ManualAttach.updateGui)
end

init()
