--
-- PowerTakeOffExtension
--
-- Author: Wopster
-- Description: Extension for handling PTO operations
-- Name: PowerTakeOffExtension
-- Hide: yes
--
-- Copyright (c) Wopster

---@class PowerTakeOffExtension
PowerTakeOffExtension = {}

---Check if object and vehicle have PTO compatibility
function PowerTakeOffExtension.hasPowerTakeOffs(object: any, vehicle: any): boolean
    if object == nil or vehicle == nil then
        return false
    end

    if vehicle.getOutputPowerTakeOffs == nil or object.getInputPowerTakeOffs == nil then
        return false
    end

    if object.getInputPowerTakeOffsByJointDescIndexAndName == nil then
        return false
    end

    -- Not every object with power take offs is an attachable.
    local spec = object.spec_attachable
    if spec == nil or spec.inputAttacherJointDescIndex == nil then
        return false
    end

    local outputs = vehicle:getOutputPowerTakeOffs() or {}
    if #outputs == 0 then
        return false
    end

    for i = 1, #outputs do
        local output = outputs[i]
        local inputs = object:getInputPowerTakeOffsByJointDescIndexAndName(spec.inputAttacherJointDescIndex, output.ptoName) or {}
        if #inputs > 0 then
            return true
        end
    end

    return false
end

---Check if object has PTO attached to specific vehicle
function PowerTakeOffExtension.hasAttachedPowerTakeOffs(object: any, attacherVehicle: any): boolean
    local spec = object ~= nil and object.spec_powerTakeOffs or nil
    if spec == nil then
        return false
    end

    local inputs = spec.inputPowerTakeOffs
    if inputs == nil then
        return false
    end

    for _, input in pairs(inputs) do
        if input.connectedVehicle == attacherVehicle then
            return true
        end
    end

    return false
end
