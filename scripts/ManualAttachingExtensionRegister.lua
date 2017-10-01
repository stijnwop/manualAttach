--
--	Manual Attaching: Extension Register
--
--	@author: 	 Wopster
--	@descripion: Register for the ManualAttachingExtension
--	@history:	 v1.0 - 2015-4-11 - Initial implementation
--				 v1.1 - 2016-4-29 - Update see changes in changelog
--

ManualAttachingExtensionRegister = {
    isLoaded = false
}

if SpecializationUtil.specializations['ManualAttachingExtension'] == nil then
    SpecializationUtil.registerSpecialization('ManualAttachingExtension', 'ManualAttachingExtension', g_currentModDirectory .. 'scripts/ManualAttachingExtension.lua')
    ManualAttachingExtensionRegister.isLoaded = false
end

---
-- @param name
--
function ManualAttachingExtensionRegister:loadMap(name)
    if not g_currentMission.manualAttachingExtensionLoaded then
        if not ManualAttachingExtensionRegister.isLoaded then
            self:register()
        end

        g_currentMission.manualAttachingExtensionLoaded = true
    else
        print("ManualAttaching - error: The ManualAttachingExtension have been loaded already! Remove one of the copy's!")
    end
end

---
--
function ManualAttachingExtensionRegister:deleteMap()
    g_currentMission.manualAttachingExtensionLoaded = nil
end

---
-- @param ...
--
function ManualAttachingExtensionRegister:keyEvent(...)
end

---
-- @param ...
--
function ManualAttachingExtensionRegister:mouseEvent(...)
end

---
-- @param dt
--
function ManualAttachingExtensionRegister:update(dt)
end

---
--
function ManualAttachingExtensionRegister:draw()
end

---
--
function ManualAttachingExtensionRegister:register()
    for _, vehicle in pairs(VehicleTypeUtil.vehicleTypes) do
        if vehicle ~= nil then
            table.insert(vehicle.specializations, SpecializationUtil.getSpecialization('ManualAttachingExtension'))
        end
    end

    ManualAttachingExtensionRegister.isLoaded = true
end

addModEventListener(ManualAttachingExtensionRegister)