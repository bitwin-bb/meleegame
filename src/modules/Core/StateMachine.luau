--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)


local StateMachine = {}
StateMachine.__index = StateMachine

export type GuardCallback = (context: any, eventName: string?, eventPayload: any?, machine: any) -> boolean
export type HookCallback = (context: any, stateId: string, machine: any, payload: any?) -> ()
export type UpdateCallback = (context: any, stateId: string, dt: number, machine: any) -> ()

export type TransitionDefinition = {
	to: string,
	event: string?,
	after: number?,
	guard: GuardCallback?,
	priority: number?,
	interruptPriority: number?,
}

export type StateDefinition = {
	id: string,
	parent: string?,
	onEnter: HookCallback?,
	onExit: HookCallback?,
	onUpdate: UpdateCallback?,
	interruptPriority: number?,
	transitions: { TransitionDefinition }?,
}

export type TransitionCandidate = {
	from: string,
	to: string,
	depth: number,
	priority: number,
	interruptPriority: number,
	order: number,
	event: string?,
	after: number?,
	guard: GuardCallback?,
}

export type StateMachine = typeof(setmetatable({} :: any, StateMachine))

local function clampPriority(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" then
		return fallback
	end
	local value = math.floor(valueRaw)
	if value < -1000000 then
		return -1000000
	end
	if value > 1000000 then
		return 1000000
	end
	return value
end

local function sortCandidates(a: TransitionCandidate, b: TransitionCandidate): boolean
	if a.priority ~= b.priority then
		return a.priority > b.priority
	end
	if a.depth ~= b.depth then
		return a.depth > b.depth
	end
	return a.order < b.order
end

local function buildPath(stateMap: { [string]: StateDefinition }, stateId: string): { string }
	local out = {}
	local cursor = stateId
	local guard = 0
	while cursor ~= "" and cursor ~= nil do
		guard += 1
		if guard > 1024 then
			error("StateMachine parent chain is too deep")
		end
		local state = stateMap[cursor]
		if state == nil then
			error(string.format("StateMachine unknown state '%s'", tostring(cursor)))
		end
		table.insert(out, 1, cursor)
		cursor = state.parent or ""
	end
	return out
end

local function findCommonPrefixLength(a: { string }, b: { string }): number
	local maxShared = math.min(#a, #b)
	local index = 0
	while index < maxShared do
		if a[index + 1] ~= b[index + 1] then
			break
		end
		index += 1
	end
	return index
end

local function tableContainsPath(path: { string }, target: string): boolean
	for index = 1, #path do
		if path[index] == target then
			return true
		end
	end
	return false
end

function StateMachine.new(statesRaw: { StateDefinition }, initialStateIdRaw: any, context: any): StateMachine
	local stateMap = {} :: { [string]: StateDefinition }
	local transitionOrder = 0
	for _, state in statesRaw do
		if typeof(state) ~= "table" or typeof(state.id) ~= "string" or state.id == "" then
			error("StateMachine state definition must include a non-empty id")
		end
		if stateMap[state.id] ~= nil then
			error(string.format("StateMachine duplicate state id '%s'", state.id))
		end
		stateMap[state.id] = state

		if state.transitions ~= nil then
			for _, transition in state.transitions do
				transitionOrder += 1
				(transition :: any)._order = transitionOrder
			end
		end
	end

	for id, state in stateMap do
		if state.parent ~= nil and stateMap[state.parent] == nil then
			error(string.format("StateMachine state '%s' parent '%s' is missing", id, tostring(state.parent)))
		end
	end

	local initialStateId = if typeof(initialStateIdRaw) == "string" and stateMap[initialStateIdRaw] ~= nil then initialStateIdRaw else statesRaw[1].id
	local initialPath = buildPath(stateMap, initialStateId)

	local self = setmetatable({
		states = stateMap,
		activeStateId = initialStateId,
		activePath = initialPath,
		stateElapsed = {} :: { [string]: number },
		context = context,
		elapsed = 0,
		transitionCount = 0,
		disabled = false,
	}, StateMachine)

	for _, pathStateId in initialPath do
		self.stateElapsed[pathStateId] = 0
	end

	for _, pathStateId in initialPath do
		local state = self.states[pathStateId]
		if state.onEnter ~= nil then
			state.onEnter(self.context, pathStateId, self, nil)
		end
	end

	return self
end

function StateMachine.getContext(self: StateMachine): any
	return self.context
end

function StateMachine.setContext(self: StateMachine, context: any)
	self.context = context
end

function StateMachine.getActiveState(self: StateMachine): string
	return self.activeStateId
end

function StateMachine.getActivePath(self: StateMachine): { string }
	return Sift.Dictionary.copy(self.activePath)
end

function StateMachine.getStateElapsed(self: StateMachine, stateIdRaw: any): number
	if typeof(stateIdRaw) ~= "string" then
		return 0
	end
	return self.stateElapsed[stateIdRaw] or 0
end

function StateMachine.getElapsed(self: StateMachine): number
	return self.elapsed
end

function StateMachine.setEnabled(self: StateMachine, enabledRaw: any)
	self.disabled = enabledRaw == false
end

function StateMachine._currentInterruptThreshold(self: StateMachine): number
	local threshold = 0
	for _, stateId in self.activePath do
		local state = self.states[stateId]
		local level = clampPriority(state.interruptPriority, 0)
		if level > threshold then
			threshold = level
		end
	end
	return threshold
end

function StateMachine._collectCandidates(self: StateMachine, eventName: string?, eventPayload: any?): { TransitionCandidate }
	local threshold = self:_currentInterruptThreshold()
	local candidates = {}

	for depth = #self.activePath, 1, -1 do
		local stateId = self.activePath[depth]
		local state = self.states[stateId]
		local transitions = state.transitions
		if transitions == nil then
			continue
		end

		for _, transition in transitions do
			local matchesEvent = false
			if eventName ~= nil then
				matchesEvent = transition.event == eventName
			else
				matchesEvent = transition.event == nil and transition.after ~= nil
			end
			if not matchesEvent then
				continue
			end

			local priority = clampPriority(transition.priority, 0)
			local interruptPriority = clampPriority(transition.interruptPriority, priority)
			if interruptPriority < threshold then
				continue
			end

			if transition.after ~= nil then
				local elapsed = self.stateElapsed[stateId] or 0
				if elapsed < transition.after then
					continue
				end
			end

			if transition.guard ~= nil then
				local ok, passed = pcall(transition.guard, self.context, eventName, eventPayload, self)
				if not ok or not passed then
					continue
				end
			end

			candidates[#candidates + 1] = {
				from = stateId,
				to = transition.to,
				depth = depth,
				priority = priority,
				interruptPriority = interruptPriority,
				order = (transition :: any)._order or 0,
				event = transition.event,
				after = transition.after,
				guard = transition.guard,
			}
		end
	end

	table.sort(candidates, sortCandidates)
	return candidates
end

function StateMachine._transition(self: StateMachine, targetStateId: string, payload: any?): boolean
	if self.states[targetStateId] == nil then
		return false
	end
	if targetStateId == self.activeStateId then
		return true
	end

	local fromPath = self.activePath
	local toPath = buildPath(self.states, targetStateId)
	local sharedLength = findCommonPrefixLength(fromPath, toPath)

	for index = #fromPath, sharedLength + 1, -1 do
		local stateId = fromPath[index]
		local state = self.states[stateId]
		if state.onExit ~= nil then
			state.onExit(self.context, stateId, self, payload)
		end
		self.stateElapsed[stateId] = nil
	end

	for index = sharedLength + 1, #toPath do
		local stateId = toPath[index]
		self.stateElapsed[stateId] = 0
		local state = self.states[stateId]
		if state.onEnter ~= nil then
			state.onEnter(self.context, stateId, self, payload)
		end
	end

	self.activePath = toPath
	self.activeStateId = targetStateId
	self.transitionCount += 1
	return true
end

function StateMachine.transitionTo(self: StateMachine, stateIdRaw: any, payload: any?, interruptPriorityRaw: any): boolean
	if self.disabled then
		return false
	end
	if typeof(stateIdRaw) ~= "string" then
		return false
	end
	if self.states[stateIdRaw] == nil then
		return false
	end
	local interruptPriority = clampPriority(interruptPriorityRaw, 0)
	if interruptPriority < self:_currentInterruptThreshold() then
		return false
	end
	return self:_transition(stateIdRaw, payload)
end

function StateMachine.dispatch(self: StateMachine, eventNameRaw: any, eventPayload: any?): boolean
	if self.disabled then
		return false
	end
	if typeof(eventNameRaw) ~= "string" or eventNameRaw == "" then
		return false
	end

	local candidates = self:_collectCandidates(eventNameRaw, eventPayload)
	local selected = candidates[1]
	if selected == nil then
		return false
	end
	return self:_transition(selected.to, {
		event = eventNameRaw,
		payload = eventPayload,
		from = selected.from,
	})
end

function StateMachine.update(self: StateMachine, dtRaw: any): boolean
	if self.disabled then
		return false
	end
	local dt = if typeof(dtRaw) == "number" and dtRaw > 0 then dtRaw else 0
	if dt <= 0 then
		return false
	end

	self.elapsed += dt
	for _, stateId in self.activePath do
		self.stateElapsed[stateId] = (self.stateElapsed[stateId] or 0) + dt
		local state = self.states[stateId]
		if state.onUpdate ~= nil then
			state.onUpdate(self.context, stateId, dt, self)
		end
	end

	local timedCandidates = self:_collectCandidates(nil, nil)
	local selected = timedCandidates[1]
	if selected ~= nil then
		return self:_transition(selected.to, {
			after = selected.after,
			from = selected.from,
		})
	end
	return false
end

function StateMachine.isInState(self: StateMachine, stateIdRaw: any): boolean
	if typeof(stateIdRaw) ~= "string" then
		return false
	end
	if stateIdRaw == self.activeStateId then
		return true
	end
	return tableContainsPath(self.activePath, stateIdRaw)
end

function StateMachine.getTransitionCount(self: StateMachine): number
	return self.transitionCount
end

return StateMachine
