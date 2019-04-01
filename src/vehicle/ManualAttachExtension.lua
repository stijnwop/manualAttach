ManualAttachVehicle = {}

---
-- ManualAttachVehicle
--
-- AttacherJoints extension for Manual Attach.
--
-- Copyright (c) Wopster, 2019

function ManualAttachVehicle.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(AttacherJoints, specializations)
end

function ManualAttachVehicle.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanToggleAttach", ManualAttachVehicle.inj_getCanToggleAttach)
end

---
--- Injections.
---

function ManualAttachVehicle.inj_getCanToggleAttach(vehicle, superFunc)
    return false
end