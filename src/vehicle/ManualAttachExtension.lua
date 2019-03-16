
ManualAttachExtension = {}

function ManualAttachExtension.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Attachable, specializations) or
            SpecializationUtil.hasSpecialization(AttacherJoints, specializations)
end

function ManualAttachExtension.registerEvents(vehicleType)
    -- SpecializationUtil.registerEvent(vehicleType, "onBrake")
end

function ManualAttachExtension.registerFunctions(vehicleType)
end

function ManualAttachExtension.registerOverwrittenFunctions(vehicleType)
end

function ManualAttachExtension.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", ManualAttachExtension)
end

function ManualAttachExtension.initSpecialization()
end

function ManualAttachExtension:onLoad(savegame)
end

function ManualAttachExtension:onLoadFinished(savegame)
end
