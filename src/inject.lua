--
-- Inject
--
-- Author: Wopster
-- Description: Inject functions into the base game.
-- Name: inject
-- Hide: yes
--
-- Copyright (c) Wopster

local isRunByTool: boolean = g_iconGenerator ~= nil or false
local modName: string = g_currentModName
local modDirectory: string = g_currentModDirectory

local function isLoaded(): boolean
    return g_modIsLoaded[modName]
end

local function inj_playerLoad(self: Player): ()
    if not isLoaded() then
        return
    end

    local manualAttach: ManualAttach = g_manualAttach
    manualAttach:onPlayerLoad(self)
end

local function inj_playerDelete(self: Player): ()
    if not isLoaded() then
        return
    end

    local manualAttach: ManualAttach = g_manualAttach
    manualAttach:onPlayerDelete(self)
end

local function installSpecializations(vehicleTypeManager, specializationManager, modDirectory, modName)
    specializationManager:addSpecialization("manualAttachVehicle", "ManualAttachVehicle", Utils.getFilename("src/vehicle/specializations/ManualAttachVehicle.lua", modDirectory), nil)

    specializationManager:addSpecialization(
        "manualAttachAttachable",
        "ManualAttachAttachable",
        Utils.getFilename("src/vehicle/specializations/ManualAttachAttachable.lua", modDirectory),
        nil
    )

    specializationManager:addSpecialization(
        "manualAttachPowerTakeOff",
        "ManualAttachPowerTakeOff",
        Utils.getFilename("src/vehicle/specializations/ManualAttachPowerTakeOff.lua", modDirectory),
        nil
    )

    specializationManager:addSpecialization(
        "manualAttachConnectionHoses",
        "ManualAttachConnectionHoses",
        Utils.getFilename("src/vehicle/specializations/ManualAttachConnectionHoses.lua", modDirectory),
        nil
    )

    for typeName, typeEntry in pairs(vehicleTypeManager:getTypes()) do
        if SpecializationUtil.hasSpecialization(AttacherJoints, typeEntry.specializations) then
            vehicleTypeManager:addSpecialization(typeName, modName .. ".manualAttachVehicle")
        end

        if SpecializationUtil.hasSpecialization(Attachable, typeEntry.specializations) then
            vehicleTypeManager:addSpecialization(typeName, modName .. ".manualAttachAttachable")
        end

        if SpecializationUtil.hasSpecialization(PowerTakeOffs, typeEntry.specializations) then
            vehicleTypeManager:addSpecialization(typeName, modName .. ".manualAttachPowerTakeOff")
        end

        if SpecializationUtil.hasSpecialization(ConnectionHoses, typeEntry.specializations) and SpecializationUtil.hasSpecialization(Attachable, typeEntry.specializations) then
            local hasEnterable = SpecializationUtil.hasSpecialization(Enterable, typeEntry.specializations)
            local isEnterableException = SpecializationUtil.hasSpecialization(LogGrab, typeEntry.specializations)
                or SpecializationUtil.hasSpecialization(BaleLoader, typeEntry.specializations)
                or SpecializationUtil.hasSpecialization(Roller, typeEntry.specializations)

            if not hasEnterable or (hasEnterable and isEnterableException) then
                vehicleTypeManager:addSpecialization(typeName, modName .. ".manualAttachConnectionHoses")
            end
        end
    end
end

local function inj_initSpecialization(typeManager)
    if typeManager.typeName == "vehicle" then
        installSpecializations(g_vehicleTypeManager, g_specializationManager, modDirectory, modName)
    end
end

local function init(): ()
    Player.load = Utils.appendedFunction(Player.load, inj_playerLoad)
    Player.delete = Utils.prependedFunction(Player.delete, inj_playerDelete)

    TypeManager.validateTypes = Utils.prependedFunction(TypeManager.validateTypes, inj_initSpecialization)
end

if not isRunByTool then
    init()
end
