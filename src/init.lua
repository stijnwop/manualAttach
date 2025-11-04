--
-- Initialization
--
-- Author: Wopster
-- Description: Entry point for the Manual Attach mod.
-- Name: init
-- Hide: yes
--
-- Copyright (c) Wopster

local isRunByTool: boolean = g_iconGenerator ~= nil or false
local modDirectory: string = g_currentModDirectory
local modName: string = g_currentModName
local manualAttach: ManualAttach

---Loading order based on dependency order
local sourceFiles: { string } = {
    "src/events/ManualAttachPowerTakeOffEvent.lua",
    "src/events/ManualAttachConnectionHosesEvent.lua",

    "src/extensions/PowerTakeOffExtension.lua",
    "src/extensions/ConnectionHosesExtension.lua",

    "src/attachments/BaseAttachment.lua",
    "src/attachments/VehicleJointAttachment.lua",
    "src/attachments/PowerTakeOffAttachment.lua",
    "src/attachments/ConnectionHosesAttachment.lua",

    "src/core/ActionGroups.lua",
    "src/core/DetectionHandler.lua",
    "src/core/VehicleAttachmentHandler.lua",

    "src/ManualAttach.lua",
}

for _, file in ipairs(sourceFiles) do
    source(modDirectory .. file)
end

local function load(mission): ()
    manualAttach = ManualAttach.new(modName, modDirectory, mission, g_i18n, g_inputBinding, g_soundManager, g_inputDisplayManager, g_gameSettings)
    g_manualAttach = manualAttach
    addModEventListener(manualAttach)
end

local function startMission(mission): ()
    manualAttach:onStartMission(mission)
end

local function init(): ()
    Mission00.load = Utils.prependedFunction(Mission00.load, load)
    Mission00.onStartMission = Utils.appendedFunction(Mission00.onStartMission, startMission)
end

if not isRunByTool then
    init()
end

g_manualAttachModName = modName
