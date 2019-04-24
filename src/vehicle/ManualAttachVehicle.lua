---
-- ManualAttachVehicle
--
-- AttacherJoints extension for Manual Attach.
--
-- Copyright (c) Wopster, 2019

ManualAttachVehicle = {}

function ManualAttachVehicle.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(AttacherJoints, specializations)
end

function ManualAttachVehicle.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanToggleAttach", ManualAttachVehicle.inj_getCanToggleAttach)
end

---
--- Injections.
---

function ManualAttachVehicle.inj_getCanToggleAttach()
    return false
end
