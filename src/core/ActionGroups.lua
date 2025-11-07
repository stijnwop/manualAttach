--
-- ActionGroups
--
-- Author: Wopster
-- Description: Manages input actions with support for multiple handlers per action (short press, long press, etc.)
-- Name: ActionGroups
-- Hide: yes
--
-- Copyright (c) Wopster

---@class ActionGroups
ActionGroups = {}
local ActionGroups_mt = Class(ActionGroups)

type ActionHandler = {
    callback: any,
    shouldTrigger: (inputValue: number, dt: number) -> boolean,
    priority: number?,
    triggerAlways: boolean,
}

type InputActionGroup = {
    inputAction: string,
    handlers: { ActionHandler },
    triggerAlways: boolean,
    eventId: number?,
}

type ActionGroupsData = {
    input: InputBinding,
    actionGroups: { [string]: InputActionGroup },
}

export type ActionGroups = typeof(setmetatable({} :: ActionGroupsData, ActionGroups_mt))

---
--- Instance Methods
---

---Creates a new ActionGroups instance
function ActionGroups.new(input: InputBinding): ActionGroups
    local self = setmetatable({}, ActionGroups_mt)

    self.input = input
    self.actionGroups = {}

    return self :: ActionGroups
end

function ActionGroups:delete()
    self:unregisterAll()
end

---Registers a handler for an input action
function ActionGroups:registerHandler(inputAction: string, handler: any): ()
    if self.actionGroups[inputAction] == nil then
        self.actionGroups[inputAction] = {
            inputAction = inputAction,
            handlers = {},
            triggerAlways = true,
            eventId = nil,
        }
    end

    local group = self.actionGroups[inputAction]
    table.insert(group.handlers, handler)
    table.sort(group.handlers, function(a, b)
        return (a.priority or 0) > (b.priority or 0)
    end)

    local hasNonImmediate = false
    for _, h in ipairs(group.handlers) do
        if h.triggerAlways then
            hasNonImmediate = true
            break
        end
    end

    group.triggerAlways = hasNonImmediate
end

---Registers all action events with the input system
function ActionGroups:registerActionEvents(contextName: string): ()
    self.input:beginActionEventsModification(contextName)

    for _, group in pairs(self.actionGroups) do
        local _, eventId = self.input:registerActionEvent(group.inputAction, self, function(_, _, inputValue)
            self:handleInput(group, inputValue)
        end, true, true, group.triggerAlways, true)

        self.input:setActionEventTextVisibility(eventId, false)
        group.eventId = eventId
    end

    self.input:endActionEventsModification()
end

---Handles input for a specific action group
function ActionGroups:handleInput(group: InputActionGroup, inputValue: number): ()
    local dt = g_currentDt

    -- Execute handlers in priority order, stop after first match
    for _, handler in ipairs(group.handlers) do
        if handler.shouldTrigger(inputValue, dt) then
            handler.callback(inputValue, dt)

            if not group.triggerAlways then
                break
            end
        end
    end
end

---Unregisters all action events
function ActionGroups:unregisterAll(contextName: string): ()
    self.input:beginActionEventsModification(contextName)

    for _, group in pairs(self.actionGroups) do
        if group.eventId ~= nil then
            self.input:removeActionEvent(group.eventId)
            group.eventId = nil
        end
    end

    self.input:endActionEventsModification()
    self.actionGroups = {}
end

---Updates the visibility and text for an action event
function ActionGroups:setActionEventInfo(inputAction: string, text: string, visible: boolean): ()
    local group = self.actionGroups[inputAction]
    if group ~= nil and group.eventId ~= nil then
        self.input:setActionEventText(group.eventId, text)
        self.input:setActionEventTextVisibility(group.eventId, visible)
    end
end

---Gets the event ID for an input action
function ActionGroups:getEventId(inputAction: string): number?
    local group = self.actionGroups[inputAction]
    return group ~= nil and group.eventId or nil
end

---
--- Static functions
---

---Creates an immediate press handler (triggers when pressed)
function ActionGroups.createImmediateHandler(callback: any, priority: number?): any
    return {
        callback = callback,
        priority = priority or 0,
        triggerAlways = false,
        shouldTrigger = function(inputValue: number, dt: number): boolean
            return inputValue == 1
        end,
    }
end

---Creates a short press handler (triggers on release if pressed < threshold)
function ActionGroups.createShortPressHandler(callback: any, threshold: number?, priority: number?): any
    local pressedDuration = 0
    local pressThreshold = threshold or 150 -- ms

    return {
        callback = callback,
        priority = priority or 0,
        triggerAlways = true,
        shouldTrigger = function(inputValue: number, dt: number): boolean
            if inputValue == 1 then
                pressedDuration = pressedDuration + dt
                return false
            else
                local wasShortPress = pressedDuration > 0 and pressedDuration < pressThreshold
                pressedDuration = 0
                return wasShortPress
            end
        end,
    }
end

---Creates a long press handler (triggers on release if pressed >= threshold)
function ActionGroups.createLongPressHandler(callback: any, threshold: number?, priority: number?): any
    local pressedDuration = 0
    local pressThreshold = threshold or 500 -- ms
    local hasTriggered = false

    return {
        callback = callback,
        priority = priority or 0,
        triggerAlways = true,
        shouldTrigger = function(inputValue: number, dt: number): boolean
            if inputValue == 1 then
                pressedDuration = pressedDuration + dt

                if not hasTriggered and pressedDuration >= pressThreshold then
                    hasTriggered = true
                    return true
                end

                return false
            else
                pressedDuration = 0
                hasTriggered = false
                return false
            end
        end,
    }
end
