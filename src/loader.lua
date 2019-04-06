---
-- loader
--
-- Loader script to handle all sources for Manual Attach.
--
-- Copyright (c) Wopster, 2019

local directory = g_currentModDirectory
local modName = g_currentModName

source(directory .. "src/ManualAttach.lua")
source(directory .. "src/events/ManualAttachPowerTakeOffEvent.lua")
source(directory .. "src/events/ManualAttachConnectionHosesEvent.lua")
source(directory .. "src/utils/Logger.lua")
source(directory .. "src/utils/ManualAttachUtil.lua")
source(directory .. "src/misc/ManualAttachDetectionHandler.lua")

local manualAttach

function init()
    FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, unload)

    Mission00.load = Utils.prependedFunction(Mission00.load, load)
    Mission00.onStartMission = Utils.appendedFunction(Mission00.onStartMission, startMission)

    VehicleTypeManager.validateVehicleTypes = Utils.prependedFunction(VehicleTypeManager.validateVehicleTypes, validateVehicleTypes)

    FSBaseMission.registerActionEvents = Utils.appendedFunction(FSBaseMission.registerActionEvents, ManualAttach.inj_registerActionEvents)
    BaseMission.unregisterActionEvents = Utils.appendedFunction(BaseMission.unregisterActionEvents, ManualAttach.inj_unregisterActionEvents)

    Player.onEnter = Utils.appendedFunction(Player.onEnter, ManualAttach.inj_onEnter)
    Player.onLeave = Utils.appendedFunction(Player.onLeave, ManualAttach.inj_onLeave)
    Player.delete = Utils.prependedFunction(Player.delete, ManualAttach.inj_delete)

    -- Noop AttacherJoints function
    AttacherJoints.findVehicleInAttachRange = function(...)
        return nil, nil, nil, nil
    end
end

function load(mission)
    assert(g_manualAttach == nil)

    manualAttach = ManualAttach:new(mission, g_inputBinding, g_i18n, g_inputDisplayManager, directory, modName)

    getfenv(0)["g_manualAttach"] = manualAttach

    addModEventListener(manualAttach)
end

function startMission(mission)
    manualAttach:onMissionStart(mission)
end

function unload()
    removeModEventListener(manualAttach)
    manualAttach:delete()
    manualAttach = nil -- Allows garbage collecting
    getfenv(0)["g_manualAttach"] = nil
end

function validateVehicleTypes(vehicleTypeManager)
    ManualAttach.installSpecializations(g_vehicleTypeManager, g_specializationManager, directory, modName)
end

init()
