--
-- DynamicHoseRef
--
-- @author:    	Xentro (Marcus@Xentro.se)
-- @website:	www.Xentro.se
-- @history:	v1.0 - 2017-01-08 - Initial implementation
-- 
--[[
<dynamicHose>
	<set>
		<!-- if you have an node in the I3D -->
		<ref type="hydraulic" index="0>0" />
		
		<!-- If you don't have the above then the below will create them for you. -->
		<ref type="hydraulic" create="true" linkNode="0>" position="0.139 1.463 -2.114" rotation="0 0 0" />
	</set>
</dynamicHose>
]] --

DynamicHoseRef = {}

function DynamicHoseRef.prerequisitesPresent(specializations)
    return true
end

function DynamicHoseRef:preLoad(saveGame)
    if g_currentMission.dynamicHoseTypes == nil then
        g_currentMission.dynamicHoseTypes = {}

        g_currentMission.dynamicHoseTypes["hydraulic"] = true
        g_currentMission.dynamicHoseTypes["electric"] = true
        g_currentMission.dynamicHoseTypes["air"] = true
    end

    self.getDynamicRefSet = DynamicHoseRef.getDynamicRefSet
    self.canWeAttachHose = DynamicHoseRef.canWeAttachHose
    self.loadAttacherJointFromXML = Utils.overwrittenFunction(self.loadAttacherJointFromXML, DynamicHoseRef.loadExtraAttacherJoints)

    self.dynamicHoseSupport = true

    -- For the future..
    if g_currentMission.dynamicHose ~= nil then
        g_currentMission.dynamicHose:addRefVehicle(self, 1.0)
    end
end

function DynamicHoseRef:load(saveGame)
    self.activeHoseTypes = {}
    self.hoseRefSets = {}

    local i = 0
    while true do
        local key = string.format("vehicle.dynamicHose.set(%d)", i)
        if not hasXMLProperty(self.xmlFile, key) then break end

        local set
        local r = 0
        while true do
            local refKey = string.format(key .. ".ref(%d)", r)
            if not hasXMLProperty(self.xmlFile, refKey) then break end

            local node = Utils.indexToObject(self.components, getXMLString(self.xmlFile, refKey .. "#index"))
            local create = Utils.getNoNil(getXMLBool(self.xmlFile, refKey .. "#create"), false)

            if (node ~= nil or create) then
                local hoseType = string.lower(Utils.getNoNil(getXMLString(self.xmlFile, refKey .. "#type"), "hydraulic"))

                if g_currentMission.dynamicHoseTypes[hoseType] then
                    if create then
                        local linkNode = Utils.indexToObject(self.components, Utils.getNoNil(getXMLString(self.xmlFile, refKey .. "#linkNode"), "0>"))
                        node = createTransformGroup("DynamicHose_Set_" .. i .. "_Ref_" .. r)

                        local x, y, z = Utils.getVectorFromString(getXMLString(self.xmlFile, refKey .. "#position"))
                        if x ~= nil and y ~= nil and z ~= nil then
                            setTranslation(node, x, y, z)
                        end

                        local rotX, rotY, rotZ = Utils.getVectorFromString(getXMLString(self.xmlFile, refKey .. "#rotation"))
                        if rotX ~= nil and rotY ~= nil and rotZ ~= nil then
                            setRotation(node, Utils.degToRad(rotX), Utils.degToRad(rotY), Utils.degToRad(rotZ))
                        end

                        link(linkNode, node)
                    end

                    if set == nil then set = {} end
                    if set[hoseType] == nil then set[hoseType] = {} end

                    self.activeHoseTypes[hoseType] = true
                    table.insert(set[hoseType], node)
                    r = r + 1
                else
                    print("DynamicHose - Error: " .. hoseType .. " is not an valid type. " .. self.configFileName)
                    break
                end
            else
                print("DynamicHose - Error: Index is nil. " .. self.configFileName)
                break
            end
        end

        if set ~= nil then
            table.insert(self.hoseRefSets, set)
        end

        i = i + 1
    end

    -- Make sure we have valid indices
    for i, joint in ipairs(self.attacherJoints) do
        if joint.dynamicHoseIndice ~= nil then
            if self.hoseRefSets[joint.dynamicHoseIndice] == nil then
                print("DynamicHose - Error: Invalid dynamicHoseIndice (" .. (joint.dynamicHoseIndice - 1) .. ") in " .. self.configFileName)
                joint.dynamicHoseIndice = nil
            end
        end
    end
end

function DynamicHoseRef:delete()
    if g_currentMission.dynamicHose ~= nil then
        g_currentMission.dynamicHose:removeRefVehicle(self)
    end
end

function DynamicHoseRef:readStream(streamId, connection)
end

function DynamicHoseRef:writeStream(streamId, connection)
end

function DynamicHoseRef:mouseEvent(posX, posY, isDown, isUp, button)
end

function DynamicHoseRef:keyEvent(unicode, sym, modifier, isDown)
end

function DynamicHoseRef:update(dt)
end

function DynamicHoseRef:updateTick(dt)
end

function DynamicHoseRef:draw()
end

function DynamicHoseRef:getDynamicRefSet(id)
    return self.hoseRefSets[id]
end

function DynamicHoseRef:canWeAttachHose(name)
    if not self.activeHoseTypes[name] then
        return false
    else
        return true
    end
end

function DynamicHoseRef:loadExtraAttacherJoints(oldFunc, attacherJoint, xmlFile, key, index)
    if oldFunc ~= nil then
        if not oldFunc(self, attacherJoint, xmlFile, key, index) then
            return false
        end
    end

    local hoseSetId = getXMLInt(xmlFile, key .. "#dynamicHoseIndice")
    if hoseSetId ~= nil then
        attacherJoint.dynamicHoseIndice = hoseSetId + 1
    end

    return true
end