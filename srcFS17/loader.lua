--
-- loader
--
-- Authors: Wopster
-- Description: Loads the Manual Attach mod
--
-- Copyright (c) Wopster, 2018

local srcDirectory = g_currentModDirectory .. "src"

---
-- Compatibility: Lua-5.1
-- http://lua-users.org/wiki/SplitJoin
--
local function split(str, pat)
    local t = {} -- NOTE: use {n = 0} in Lua-5.0
    local fpat = "(.-)" .. pat
    local last_end = 1
    local s, e, cap = str:find(fpat, 1)

    while s do
        if s ~= 1 or cap ~= "" then
            table.insert(t, cap)
        end
        last_end = e + 1
        s, e, cap = str:find(fpat, last_end)
    end

    if last_end <= #str then
        cap = str:sub(last_end)
        table.insert(t, cap)
    end

    return t
end

-- Variables controlled by the farmsim tool
local debugRendering = true --<%=debug %>
local isNoRestart = false --<%=norestart %>

-- Source files
local files = {
    -- utilities
    ('%s/utils/%s'):format(srcDirectory, 'ManualAttachUtil'),
    -- main
    ('%s/%s'):format(srcDirectory, 'ManualAttach'),
    -- events
    ('%s/events/%s'):format(srcDirectory, 'ManualAttachingPTOEvent'),
    ('%s/events/%s'):format(srcDirectory, 'ManualAttachingDynamicHosesEvent'),
}

-- Insert class name to preload
local classes = {}

for _, directory in pairs(files) do
    local splittedPath = split(directory, "[\\/]+")
    table.insert(classes, splittedPath[#splittedPath])

    source(directory .. ".lua")
end

---
--
local function loadManualAttach()
    for i, _ in pairs(files) do
        local class = classes[i]

        if _G[class] ~= nil and _G[class].preLoadManualAttach ~= nil then
            _G[class]:preLoadManualAttach()
        end
    end
end

local function noopFunction() end

---
--
local function loadMapFinished()
    local requiredMethods = { "deleteMap", "mouseEvent", "keyEvent", "draw", "update" }

    -- Before loading the savegame, allow classes to set their default values
    -- and let the settings system know that they need values
    for _, k in pairs(classes) do
        if _G[k] ~= nil and _G[k].loadMap ~= nil then
            -- Set any missing functions with dummies. This is because it makes code in classes cleaner
            for _, method in pairs(requiredMethods) do
                if _G[k][method] == nil then
                    _G[k][method] = noopFunction
                end
            end

            addModEventListener(_G[k])
        end
    end
end

-- Vehicle specializations
local specializations = {
    ["manualAttachingExtension"] = ('%s/vehicles/'):format(srcDirectory)
}

---
-- @param str
--
local function mapToScClassname(str)
    return (str:gsub("^%l", string.upper))
end
--print(ManualAttachUtil:print_r(SpecializationUtil))
--for name, directory in pairs(specializations) do
--    local classname = mapToScClassname(name)
--    SpecializationUtil.registerSpecialization(name, classname, directory .. classname .. ".lua")
--end

-- Hook on early load
Mission00.load = Utils.prependedFunction(Mission00.load, loadManualAttach)

FSBaseMission.loadMapFinished = Utils.prependedFunction(FSBaseMission.loadMapFinished, loadMapFinished)

-- Replace the base mission function with a noop.. we don't want to use unnecessary resources
BaseMission.getAttachableInRange = Utils.overwrittenFunction(BaseMission.getAttachableInRange, noopFunction)
