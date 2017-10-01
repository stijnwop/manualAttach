--
--	Manual Attaching: Extension
--
--	@author: 	 Wopster & Fruktor
--	@descripion: Extension on AttacherJointGraphics and for custom Manual Attaching settings
--	@history:	 v1.0 - 2015-4-11 - Initial implementation
--				 v1.1 - 2016-4-29 - Update see changes in changelog
--

ManualAttachingExtension = {}

function ManualAttachingExtension.prerequisitesPresent(specializations)
	return true
end

function ManualAttachingExtension:load(savegame)
	--[[
		<inputAttacherJoints>
			<inputAttacherJoint index="x" isManual="boolean" />
		</inputAttacherJoints>
		
		<attacherJoints>
			<attacherJoint index="x" dynamicHosesIsManual="boolean" ptoIsManual="boolean" />
		</attacherJoints>
	]]
			
	local i = 0
	while true do
		local key = string.format('vehicle.inputAttacherJoints.inputAttacherJoint(%d)', i)
		
		if not hasXMLProperty(self.xmlFile, key) then
			break
		end
		
		if self.inputAttacherJoints ~= nil then 
			if self.inputAttacherJoints[i + 1] ~= nil then
				local inputJoint = self.inputAttacherJoints[i + 1]
				
				if inputJoint ~= nil then
					inputJoint.isManual = getXMLBool(self.xmlFile, key .. '#isManual')		
				end
			end
		end
		
		i = i + 1
	end
	
	local i = 0
	while true do
		local key = string.format('vehicle.attacherJoints.attacherJoint(%d)', i)
		
		if not hasXMLProperty(self.xmlFile, key) then
			break
		end
		
		if self.attacherJoints ~= nil then
			if self.attacherJoints[i + 1] ~= nil then
				local attachJoint = self.attacherJoints[i + 1]
				
				if attachJoint ~= nil then
					attachJoint.ptoIsManual = getXMLBool(self.xmlFile, key .. '#ptoIsManual')
					attachJoint.dynamicHosesIsManual = getXMLBool(self.xmlFile, key .. '#dynamicHosesIsManual')
				end
			end
		end
		
		i = i + 1
	end
    
    self.getIsActive = Utils.overwrittenFunction(self.getIsActive, ManualAttachingExtension.getIsActive)
    self.getIsActiveForSound = Utils.overwrittenFunction(self.getIsActiveForSound, ManualAttachingExtension.getIsActiveForSound)
    self.manualAttachingForcedActiveTime = 0
    self.manualAttachingForcedActiveSound = false
end

function ManualAttachingExtension:delete()
end

function ManualAttachingExtension:readStream(streamId, connection)
end

function ManualAttachingExtension:writeStream(streamId, connection)
end

function ManualAttachingExtension:mouseEvent(posX, posY, isDown, isUp, button)
end

function ManualAttachingExtension:keyEvent(unicode, sym, modifier, isDown)
end

function ManualAttachingExtension:update(dt)	
	if self.doUpdateAttacherGraphics then
		local i = 0
		
		for _,implement in pairs(self.attachedImplements) do
			if implement.updateAttacherGraphicsEndTime ~= nil and implement.updateAttacherGraphicsEndTime > g_currentMission.time then
				self:updateAttacherJointGraphics(implement, dt)
				i = i + 1
			end
		end
		
		if i <= 0 then
			self.doUpdateAttacherGraphics = false
		end
	end
end

function ManualAttachingExtension:updateTick(dt)
end

function ManualAttachingExtension:draw()
end

function ManualAttachingExtension:onAttach(attacherVehicle, jointDescIndex)
end

function ManualAttachingExtension:onDetach()
end

function ManualAttachingExtension:attachImplement(implement)
	implement.updateAttacherGraphicsEndTime = g_currentMission.time + 1000
	self.doUpdateAttacherGraphics = true
end

function ManualAttachingExtension:detachImplement(implementIndex, noEventSend)
	self.attachedImplements[implementIndex].updateAttacherGraphicsEndTime = nil
end

function ManualAttachingExtension:getIsActive(superFunc)
    if g_currentMission.time < self.manualAttachingForcedActiveTime then
        return true
    end
	
	return superFunc(self)
end

function ManualAttachingExtension:getIsActiveForSound(superFunc)
	if self.manualAttachingForcedActiveSound then
		return false
	end
	
	return superFunc(self)
end