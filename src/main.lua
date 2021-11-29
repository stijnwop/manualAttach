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
    assert(g_manualAttach == nil)

    modEnvironment = ManualAttach:new(mission, g_inputBinding, g_i18n, g_inputDisplayManager, g_soundManager, modDirectory, modName)

    getfenv(0)["g_manualAttach"] = modEnvironment

    addModEventListener(modEnvironment)
end

local function unload()
    removeModEventListener(modEnvironment)
    modEnvironment:delete()
    modEnvironment = nil -- Allows garbage collecting
    getfenv(0)["g_manualAttach"] = nil
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

    Player.onEnter = Utils.appendedFunction(Player.onEnter, ManualAttach.inj_onEnter)
    Player.onLeave = Utils.appendedFunction(Player.onLeave, ManualAttach.inj_onLeave)
    Player.load = Utils.appendedFunction(Player.load, ManualAttach.inj_load)
    Player.delete = Utils.prependedFunction(Player.delete, ManualAttach.inj_delete)

    InGameMenuGameSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuGameSettingsFrame.onFrameOpen, ManualAttach.initGui)
    InGameMenuGameSettingsFrame.updateGameSettings = Utils.appendedFunction(InGameMenuGameSettingsFrame.updateGameSettings, ManualAttach.updateGui)
end

init()
