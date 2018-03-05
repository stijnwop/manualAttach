--
-- DynamicHoseRef
--
-- Authors: Xentro (Marcus@Xentro.se) and Wopster
-- Description: The reference specialization for the DynamicHoses
-- History:
--      - v1.0 - 2017-01-08 - Initial implementation
--      - v1.1 - 2017-10-25 - Refactor by Wopster
--
--[[
<dynamicHose>
	<set>
		<!-- if you have an node in the I3D -->
		<ref type="hydraulic" index="0>0" />

		<!-- if you want to use object change -->
		<ref type="hydraulic" index="0>0">
		    <objectChange ... />
		</ref>

		<!-- If you don't have the above then the below will create them for you. -->
		<ref type="hydraulic" create="true" linkNode="0>" position="0.139 1.463 -2.114" rotation="0 0 0" />
	</set>
</dynamicHose>
]] --

DynamicHoseRef = {}
DynamicHoseRef.TYPE_HYDRAULIC = 'hydraulic'
DynamicHoseRef.TYPE_ELECTRIC = 'electric'
DynamicHoseRef.TYPE_AIR = 'air'
DynamicHoseRef.TYPE_ISOBUS = 'isobus'

DynamicHoseRef.TYPES = {
    [DynamicHoseRef.TYPE_HYDRAULIC] = true,
    [DynamicHoseRef.TYPE_ELECTRIC] = true,
    [DynamicHoseRef.TYPE_AIR] = true,
    [DynamicHoseRef.TYPE_ISOBUS] = true
}

---
-- @param specializations
--
function DynamicHoseRef.prerequisitesPresent(specializations)
    return true
end

---
-- @param saveGame
--
function DynamicHoseRef:preLoad(saveGame)
    self.getDynamicRefSet = DynamicHoseRef.getDynamicRefSet
    self.canWeAttachHose = DynamicHoseRef.canWeAttachHose
    self.getCanAttachHose = DynamicHoseRef.getCanAttachHose
    self.setDynamicRefSetObjectChanges = DynamicHoseRef.setDynamicRefSetObjectChanges
    self.resetDynamicRefSetObjectChanges = DynamicHoseRef.resetDynamicRefSetObjectChanges
    self.loadAttacherJointFromXML = Utils.overwrittenFunction(self.loadAttacherJointFromXML, DynamicHoseRef.loadExtraAttacherJoints)

    self.dynamicHoseSupport = true

    -- For the future..
    if g_currentMission.dynamicHose ~= nil then
        g_currentMission.dynamicHose:addRefVehicle(self)
    end
end

---
-- @param saveGame
--
function DynamicHoseRef:load(saveGame)
    self.activeHoseTypes = {}
    self.hoseRefSets = {}

    local i = 0
    while true do
        local key = ('vehicle.dynamicHose.set(%d)'):format(i)

        if not hasXMLProperty(self.xmlFile, key) then
            break
        end

        local set = {}
        local r = 0
        while true do
            local refKey = ('%s.ref(%d)'):format(key, r)

            if not hasXMLProperty(self.xmlFile, refKey) then
                break
            end

            local node = Utils.indexToObject(self.components, getXMLString(self.xmlFile, refKey .. "#index"))
            local create = Utils.getNoNil(getXMLBool(self.xmlFile, refKey .. "#create"), false)

            if (node ~= nil or create) then
                local hoseType = Utils.getNoNil(getXMLString(self.xmlFile, refKey .. "#type"), "hydraulic"):lower()

                if DynamicHoseRef.TYPES[hoseType] then
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

                    if set[hoseType] == nil then
                        set[hoseType] = {}
                    end

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

        if set ~= nil and r > 0 then
            set.changeObjects = {}
            ObjectChangeUtil.loadObjectChangeFromXML(self.xmlFile, key, set.changeObjects, self.components, self)

            table.insert(self.hoseRefSets, set)
        end

        i = i + 1
    end

    -- Make sure we have valid indices
    for _, joint in ipairs(self.attacherJoints) do
        if joint.dynamicHoseIndice ~= nil then
            if self.hoseRefSets[joint.dynamicHoseIndice] == nil then
                print("DynamicHose - Error: Invalid dynamicHoseIndice (" .. (joint.dynamicHoseIndice - 1) .. ") in " .. self.configFileName)
                joint.dynamicHoseIndice = nil
            end
        end
    end
end

---
--
function DynamicHoseRef:delete()
    if g_currentMission.dynamicHose ~= nil then
        g_currentMission.dynamicHose:removeRefVehicle(self)
    end
end

---
-- @param ...
--
function DynamicHoseRef:mouseEvent(...)
end

---
-- @param ...
--
function DynamicHoseRef:keyEvent(...)
end

---
-- @param dt
--
function DynamicHoseRef:update(dt)
end

---
--
function DynamicHoseRef:draw()
end

---
-- @param setId
--
function DynamicHoseRef:getDynamicRefSet(setId)
    return self.hoseRefSets[setId]
end

---
-- @param visibility
-- @param setId
--
function DynamicHoseRef:setDynamicRefSetObjectChanges(visibility, setId)
    local set = self.hoseRefSets[setId]

    if set ~= nil then
        ObjectChangeUtil.setObjectChanges(set.changeObjects, visibility, self, self.setMovingToolDirty)
    end
end

---
-- @param setId
--
function DynamicHoseRef:resetDynamicRefSetObjectChanges(setId)
    local set = self.hoseRefSets[setId]

    if set ~= nil then
        ObjectChangeUtil.setObjectChanges(set.changeObjects, false, self, self.setMovingToolDirty)
    end
end

---
-- @param name
--
function DynamicHoseRef:canWeAttachHose(name)
    return self:getCanAttachHose(name)
end

---
-- @param name
--
function DynamicHoseRef:getCanAttachHose(name)
    if not self.activeHoseTypes[name] then
        return false
    end

    return true
end

---
-- @param oldFunc
-- @param attacherJoint
-- @param xmlFile
-- @param key
-- @param index
--
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