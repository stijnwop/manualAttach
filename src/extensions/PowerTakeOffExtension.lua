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
    if vehicle.getOutputPowerTakeOffs == nil or object.getInputPowerTakeOffs == nil then
        return false
    end

    if object.getInputPowerTakeOffsByJointDescIndexAndName == nil then
        return false
    end

    local outputs = vehicle:getOutputPowerTakeOffs()
    if #outputs == 0 then
        return false
    end

    local inputJointDescIndex = object.spec_attachable.inputAttacherJointDescIndex

    for i = 1, #outputs do
        local output = outputs[i]
        local inputs = object:getInputPowerTakeOffsByJointDescIndexAndName(inputJointDescIndex, output.ptoName)
        if #inputs > 0 then
            return true
        end
    end

    return false
end

---Check if object has PTO attached to specific vehicle
function PowerTakeOffExtension.hasAttachedPowerTakeOffs(object: any, attacherVehicle: any): boolean
    local spec = object.spec_powerTakeOffs
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
