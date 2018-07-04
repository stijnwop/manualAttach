--
-- ManualAttachUtil
--
-- Authors: Wopster
-- Description: Utility for Manual Attach
--
-- Copyright (c) Wopster, 2018

ManualAttachUtil = {}

---
-- @param p1
-- @param p2
--
function ManualAttachUtil:getCosAngle(p1, p2)
    local x1, y1, z1 = localDirectionToWorld(p1, 1, 0, 0)
    local x2, y2, z2 = localDirectionToWorld(p2, 1, 0, 0)

    return x1 * x2 + y1 * y2 + z1 * z2
end

-- Todo: cleanup
function ManualAttachUtil:getIsValidPlayer()
    local hasHoseSystem = false

    if g_currentMission.player.hoseSystem ~= nil then
        hasHoseSystem = g_currentMission.player.hoseSystem.index ~= nil
    end

    return not hasHoseSystem and
            g_currentMission.controlPlayer and
            g_currentMission.player ~= nil and
            g_currentMission.player.currentTool == nil and
            not g_currentMission.player.hasHPWLance and
            not g_currentMission.player.isCarryingObject and
            not g_currentMission.isPlayerFrozen and
            not g_gui:getIsGuiVisible()
end

function ManualAttachUtil:print_r(t, name, indent)
    local tableList = {}

    function table_r(t, name, indent, full)
        local id = not full and name or type(name) ~= "number" and tostring(name) or '[' .. name .. ']'
        local tag = indent .. id .. ' : '
        local out = {}

        if type(t) == "table" then
            if tableList[t] ~= nil then
                table.insert(out, tag .. '{} -- ' .. tableList[t] .. ' (self reference)')
            else
                tableList[t] = full and (full .. '.' .. id) or id

                if next(t) then -- If table not empty.. fill it further
                    table.insert(out, tag .. '{')

                    for key, value in pairs(t) do
                        table.insert(out, table_r(value, key, indent .. '|  ', tableList[t]))
                    end

                    table.insert(out, indent .. '}')
                else
                    table.insert(out, tag .. '{}')
                end
            end
        else
            local val = type(t) ~= "number" and type(t) ~= "boolean" and '"' .. tostring(t) .. '"' or tostring(t)
            table.insert(out, tag .. val)
        end

        return table.concat(out, '\n')
    end

    return table_r(t, name or 'Value', indent or '')
end