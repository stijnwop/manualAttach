--
-- ManualAttachingExtension
--
-- Authors: Wopster & fruktor
-- Description: Vehicle extension needed for Manual Attaching
--
-- Copyright (c) Wopster, 2015 - 2017

ManualAttachingExtension = {}

ManualAttachingExtension.GRAPHICS_END_TIME_INCREASMENT = 1000 -- ms

---
-- @param specializations
--
function ManualAttachingExtension.prerequisitesPresent(specializations)
    return true
end

---
-- @param savegame
--
function ManualAttachingExtension:preLoad(savegame)
    self.loadAttacherJointFromXML = Utils.overwrittenFunction(self.loadAttacherJointFromXML, ManualAttachingExtension.loadAttacherJointFromXML)
    self.loadInputAttacherJoint = Utils.overwrittenFunction(self.loadInputAttacherJoint, ManualAttachingExtension.loadInputAttacherJoint)
end

---
-- @param savegame
--
function ManualAttachingExtension:load(savegame)
    self.getIsActive = Utils.overwrittenFunction(self.getIsActive, ManualAttachingExtension.getIsActive)
    self.getIsActiveForSound = Utils.overwrittenFunction(self.getIsActiveForSound, ManualAttachingExtension.getIsActiveForSound)

    self.manualAttachingForcedActiveTime = 0
    self.manualAttachingForcedActiveSound = false
end

---
-- @param xmlFile
-- @param key
-- @param inputAttacherJoint
-- @param index
--
function ManualAttachingExtension:loadInputAttacherJoint(super, xmlFile, key, inputAttacherJoint, index)
    if super ~= nil then
        if not super(self, xmlFile, key, inputAttacherJoint, index) then
            return false
        end
    end

    inputAttacherJoint.isManual = Utils.getNoNil(getXMLBool(xmlFile, key .. '#isManual'), true)
    inputAttacherJoint.inRangeDistance = Utils.getNoNil(getXMLFloat(xmlFile, key .. '#inRangeDistance'), 1.3)

    return true
end

---
-- @param attacherJoint
-- @param xmlFile
-- @param key
-- @param index
--
function ManualAttachingExtension:loadAttacherJointFromXML(super, attacherJoint, xmlFile, key, index)
    if super ~= nil then
        if not super(self, attacherJoint, xmlFile, key, index) then
            return false
        end
    end

    attacherJoint.ptoIsManual = Utils.getNoNil(getXMLBool(xmlFile, key .. '#ptoIsManual'), true)
    attacherJoint.dynamicHosesIsManual = Utils.getNoNil(getXMLBool(xmlFile, key .. '#dynamicHosesIsManual'), true)

    return true
end

---
--
function ManualAttachingExtension:delete()
end

---
-- @param ...
--
function ManualAttachingExtension:mouseEvent(...)
end

---
-- @param ...
--
function ManualAttachingExtension:keyEvent(...)
end

---
-- @param dt
--
function ManualAttachingExtension:update(dt)
    if self.doUpdateAttacherGraphics then
        local reset = true

        if self.attachedImplements ~= nil then
            for _, implement in pairs(self.attachedImplements) do
                if implement.updateAttacherGraphicsEndTime ~= nil and implement.updateAttacherGraphicsEndTime > g_currentMission.time then
                    self:updateAttacherJointGraphics(implement, dt)
                    reset = false
                end
            end
        end

        if reset then
            self.doUpdateAttacherGraphics = false
        end
    end
end

---
--
function ManualAttachingExtension:draw()
end

---
-- @param implement
--
function ManualAttachingExtension:attachImplement(implement)
    implement.updateAttacherGraphicsEndTime = g_currentMission.time + ManualAttachingExtension.GRAPHICS_END_TIME_INCREASMENT
    self.doUpdateAttacherGraphics = true
end

---
-- @param implementIndex
-- @param noEventSend
--
function ManualAttachingExtension:detachImplement(implementIndex, noEventSend)
    self.attachedImplements[implementIndex].updateAttacherGraphicsEndTime = nil
end

---
-- @param super
--
function ManualAttachingExtension:getIsActive(super)
    if g_currentMission.time < self.manualAttachingForcedActiveTime then
        return true
    end

    return super(self)
end

---
-- @param super
--
function ManualAttachingExtension:getIsActiveForSound(super)
    if self.manualAttachingForcedActiveSound then
        return false
    end

    return super(self)
end