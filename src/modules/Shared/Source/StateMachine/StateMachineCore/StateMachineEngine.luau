local require = require(script.Parent.loader).load(script)

local Nevermore = require("StateMachineNevermore")
local Brio = Nevermore.Get("Brio")
local Maid = Nevermore.Get("Maid")
local Promise = Nevermore.Get("Promise")

local function fulfilledPromise(...): any
	local args = table.pack(...)
	return Promise.new(function(fulfill)
		fulfill(table.unpack(args, 1, args.n))
	end)
end
local RxSignal = Nevermore.Get("RxSignal")
local Signal = Nevermore.Get("Signal")
local Table = Nevermore.Get("Table")
local ValueObject = Nevermore.Get("ValueObject")

local Blackboard = require("StateMachineBlackboard")
local StateStack = require("StateMachineStateStack")
local StateTree = require("StateTree")

local WILDCARD_STATE = "*"

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
	_order: number?,
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

export type TransitionObject = {
	From: string?,
	To: string?,
	Guard: ((machine: any) -> boolean)?,
	Action: ((machine: any) -> ())?,
	Priority: number?,
	AllowSelfTransition: boolean?,
	_order: number?,
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
	transition: TransitionObject?,
}

export type StateMachine = typeof(setmetatable({} :: any, StateMachine))

local function clampPriority(valueRaw: any, fallback: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	local value = math.floor(valueRaw)
	return math.clamp(value, -1000000, 1000000)
end

local function coerceStateName(stateNameRaw: any): string?
	if typeof(stateNameRaw) ~= "string" or stateNameRaw == "" then
		return nil
	end
	return stateNameRaw
end

local function isLegacyStateList(valueRaw: any): boolean
	if typeof(valueRaw) ~= "table" then
		return false
	end
	local first = (valueRaw :: any)[1]
	return typeof(first) == "table" and typeof((first :: any).id) == "string"
end

local function getPathParent(stateId: string): string?
	local lastDot = string.find(stateId, "%.[^%.]*$")
	if lastDot == nil or lastDot <= 1 then
		return nil
	end
	return string.sub(stateId, 1, lastDot - 1)
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

local function callStateCanEnter(stateObject: any, machine: StateMachine): boolean
	if stateObject == nil or typeof(stateObject.CanEnter) ~= "function" then
		return true
	end
	local ok, result = pcall(stateObject.CanEnter, stateObject, machine)
	return ok and result == true
end

local function callStateCanExit(stateObject: any, machine: StateMachine): boolean
	if stateObject == nil or typeof(stateObject.CanExit) ~= "function" then
		return true
	end
	local ok, result = pcall(stateObject.CanExit, stateObject, machine)
	return ok and result == true
end

local function callStateEnter(stateObject: any, machine: StateMachine)
	if stateObject == nil or typeof(stateObject.Enter) ~= "function" then
		return
	end
	stateObject.Enter(stateObject, machine)
end

local function callStateExit(stateObject: any, machine: StateMachine)
	if stateObject == nil or typeof(stateObject.Exit) ~= "function" then
		return
	end
	stateObject.Exit(stateObject, machine)
end

local function callStateUpdate(stateObject: any, machine: StateMachine, dt: number)
	if stateObject == nil or typeof(stateObject.Update) ~= "function" then
		return
	end
	stateObject.Update(stateObject, machine, dt)
end

local function callStateDestroy(stateObject: any)
	if stateObject == nil or typeof(stateObject.Destroy) ~= "function" then
		return
	end
	stateObject.Destroy(stateObject)
end

local function createMachine(context: any?, blackboard: any?): StateMachine
	local blackboardObject = if blackboard ~= nil then blackboard else Blackboard.new()
	local machine = setmetatable({
		states = {} :: { [string]: StateDefinition },
		stateObjects = {} :: { [string]: any },
		activeStateId = nil :: string?,
		previousStateId = nil :: string?,
		activePath = {} :: { string },
		stateElapsed = {} :: { [string]: number },
		context = context,
		blackboard = blackboardObject,
		stateStack = StateStack.new(),
		stateTree = StateTree.new(),
		registeredTransitions = {} :: { TransitionObject },
		StateChanged = Signal.new(),
		Transitioned = Signal.new(),
		TransitionRejected = Signal.new(),
		Started = Signal.new(),
		Stopped = Signal.new(),
		Destroyed = Signal.new(),
		activeStateValue = ValueObject.new(nil),
		activeStateSignal = nil :: any?,
		activeStateBrio = nil :: any?,
		elapsed = 0,
		transitionCount = 0,
		transitionOrder = 0,
		disabled = false,
		running = false,
		destroyed = false,
		maid = Maid.new(),
	}, StateMachine)

	machine.activeStateSignal = RxSignal.new(function()
		return machine.activeStateValue:Observe()
	end)
	machine.maid:GiveTask(machine.StateChanged)
	machine.maid:GiveTask(machine.Transitioned)
	machine.maid:GiveTask(machine.TransitionRejected)
	machine.maid:GiveTask(machine.Started)
	machine.maid:GiveTask(machine.Stopped)
	machine.maid:GiveTask(machine.Destroyed)
	machine.maid:GiveTask(machine.activeStateValue)
	machine.maid:GiveTask(machine.stateStack)
	machine.maid:GiveTask(machine.stateTree)
	if blackboard == nil or typeof(blackboardObject.Destroy) == "function" then
		machine.maid:GiveTask(blackboardObject)
	end

	return machine
end

function StateMachine.New(statesRaw: any?, initialStateIdRaw: any?, context: any?): StateMachine
	local blackboard = nil
	if typeof(statesRaw) == "table" and not isLegacyStateList(statesRaw) then
		blackboard = (statesRaw :: any).Blackboard or (statesRaw :: any).blackboard
		context = if context ~= nil then context else ((statesRaw :: any).Context or (statesRaw :: any).context)
	end

	local self = createMachine(context, blackboard)

	if isLegacyStateList(statesRaw) then
		local states = statesRaw :: { StateDefinition }
		for _, state in states do
			self:_registerStateDefinition(state :: StateDefinition)
		end
		local initialStateId = coerceStateName(initialStateIdRaw)
		if initialStateId == nil or self.states[initialStateId] == nil then
			initialStateId = states[1].id
		end
		self:Start(initialStateId :: string)
	end

	return self
end

function StateMachine._ensureStateDefinition(self: StateMachine, stateId: string, parentRaw: any?)
	if self.states[stateId] ~= nil then
		return
	end

	local parent = if typeof(parentRaw) == "string" and parentRaw ~= "" then parentRaw else getPathParent(stateId)
	if parent ~= nil then
		self:_ensureStateDefinition(parent, getPathParent(parent))
	end

	self.states[stateId] = {
		id = stateId,
		parent = parent,
	}
	self.stateTree:Register(stateId, parent)
end

function StateMachine._registerStateDefinition(self: StateMachine, state: StateDefinition)
	if typeof(state) ~= "table" or typeof(state.id) ~= "string" or state.id == "" then
		error("StateMachine state definition must include a non-empty id")
	end
	if self.states[state.id] ~= nil then
		error(string.format("StateMachine duplicate state id '%s'", state.id))
	end
	if state.parent ~= nil then
		self:_ensureStateDefinition(state.parent, getPathParent(state.parent))
	end

	self.states[state.id] = state
	self.stateTree:Register(state.id, state.parent)

	if state.transitions ~= nil then
		for _, transition in state.transitions do
			self.transitionOrder += 1
			transition._order = self.transitionOrder
		end
	end
end

function StateMachine.GetContext(self: StateMachine): any
	return self.context
end

function StateMachine.SetContext(self: StateMachine, context: any)
	self.context = context
end

function StateMachine.GetActiveState(self: StateMachine): string?
	return self.activeStateId
end

function StateMachine.GetCurrentState(self: StateMachine): string?
	return self.activeStateId
end

function StateMachine.GetPreviousState(self: StateMachine): string?
	return self.previousStateId
end

function StateMachine.GetActivePath(self: StateMachine): { string }
	return Table.copy(self.activePath)
end

function StateMachine.GetStateElapsed(self: StateMachine, stateIdRaw: any): number
	if typeof(stateIdRaw) ~= "string" then
		return 0
	end
	return self.stateElapsed[stateIdRaw] or 0
end

function StateMachine.GetElapsed(self: StateMachine): number
	return self.elapsed
end

function StateMachine.GetBlackboard(self: StateMachine): any
	return self.blackboard
end

function StateMachine.IsRunning(self: StateMachine): boolean
	return self.running and not self.destroyed
end

function StateMachine.GetStateChangedSignal(self: StateMachine): any
	return self.StateChanged
end

function StateMachine.GetTransitionedSignal(self: StateMachine): any
	return self.Transitioned
end

function StateMachine.GetTransitionRejectedSignal(self: StateMachine): any
	return self.TransitionRejected
end

function StateMachine.GetActiveStateSignal(self: StateMachine): any
	return self.activeStateSignal
end

function StateMachine.ObserveState(self: StateMachine): any
	return self.activeStateValue:Observe()
end

function StateMachine.ObserveStateBrio(self: StateMachine): any
	return self.activeStateValue:ObserveBrio(function(value)
		return value ~= nil
	end)
end

function StateMachine.PromiseState(self: StateMachine, stateNameRaw: any, timeoutRaw: any?): any
	local stateName = coerceStateName(stateNameRaw)
	if stateName == nil then
		return Promise.rejected("bad state name")
	end
	if self.activeStateId == stateName then
		return fulfilledPromise(stateName)
	end

	local promise = Promise.new()
	local maid = Maid.new()
	maid:GiveTask(promise)
	maid:GiveTask(self.StateChanged:Connect(function(currentStateId)
		if currentStateId == stateName then
			promise:Get(currentStateId)
		end
	end))

	if typeof(timeoutRaw) == "number" and timeoutRaw > 0 then
		maid:GiveTask(task.delay(timeoutRaw, function()
			promise:Reject(string.format("timed out waiting for state '%s'", stateName))
		end))
	end

	promise:Finally(function()
		maid:DoCleaning()
	end)

	return promise
end

function StateMachine.SetEnabled(self: StateMachine, enabledRaw: any)
	self.disabled = enabledRaw == false
end

function StateMachine._currentInterruptThreshold(self: StateMachine): number
	local threshold = 0
	for _, stateId in self.activePath do
		local state = self.states[stateId]
		local level = if state ~= nil then clampPriority(state.interruptPriority, 0) else 0
		if level > threshold then
			threshold = level
		end
	end
	return threshold
end

function StateMachine._collectCandidates(
	self: StateMachine,
	eventName: string?,
	eventPayload: any?
): { TransitionCandidate }
	local threshold = self:_currentInterruptThreshold()
	local candidates = {}

	for depth = #self.activePath, 1, -1 do
		local stateId = self.activePath[depth]
		local state = self.states[stateId]
		local transitions = if state ~= nil then state.transitions else nil
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
				order = transition._order or 0,
				event = transition.event,
				after = transition.after,
				guard = transition.guard,
				transition = nil,
			}
		end
	end

	table.sort(candidates, sortCandidates)
	return candidates
end

function StateMachine._collectRegisteredCandidates(self: StateMachine): { TransitionCandidate }
	local activeStateId = self.activeStateId
	if activeStateId == nil then
		return {}
	end

	local candidates = {}
	for _, transition in self.registeredTransitions do
		local from = if typeof(transition.From) == "string" and transition.From ~= ""
			then transition.From
			else WILDCARD_STATE
		local to = coerceStateName(transition.To)
		if to == nil then
			continue
		end
		if from ~= WILDCARD_STATE and not self:IsInState(from) then
			continue
		end
		if to == activeStateId and transition.AllowSelfTransition ~= true then
			continue
		end

		local guard = transition.Guard
		if guard ~= nil then
			local ok, passed = pcall(guard, self)
			if not ok or not passed then
				continue
			end
		end

		candidates[#candidates + 1] = {
			from = from,
			to = to,
			depth = if from == WILDCARD_STATE then 0 else #self.activePath,
			priority = clampPriority(transition.Priority, 0),
			interruptPriority = clampPriority(transition.Priority, 0),
			order = transition._order or 0,
			event = nil,
			after = nil,
			guard = nil,
			transition = transition,
		}
	end

	table.sort(candidates, sortCandidates)
	return candidates
end

function StateMachine._canExitTo(self: StateMachine, fromPath: { string }, sharedLength: number): boolean
	for index = #fromPath, sharedLength + 1, -1 do
		if not callStateCanExit(self.stateObjects[fromPath[index]], self) then
			return false
		end
	end
	return true
end

function StateMachine._canEnterTo(self: StateMachine, toPath: { string }, sharedLength: number): boolean
	for index = sharedLength + 1, #toPath do
		if not callStateCanEnter(self.stateObjects[toPath[index]], self) then
			return false
		end
	end
	return true
end

function StateMachine._transition(
	self: StateMachine,
	targetStateId: string,
	payload: any?,
	allowSelfTransition: boolean?
): boolean
	if self.destroyed or self.states[targetStateId] == nil then
		self.TransitionRejected:Fire(self.activeStateId, targetStateId, payload, "UnknownState")
		return false
	end
	if targetStateId == self.activeStateId and allowSelfTransition ~= true then
		return true
	end

	local fromPath = self.activePath
	local toPath = buildPath(self.states, targetStateId)
	local sharedLength = findCommonPrefixLength(fromPath, toPath)
	if targetStateId == self.activeStateId and allowSelfTransition == true then
		sharedLength = math.max(0, #fromPath - 1)
	end

	if not self:_canExitTo(fromPath, sharedLength) or not self:_canEnterTo(toPath, sharedLength) then
		self.TransitionRejected:Fire(self.activeStateId, targetStateId, payload, "StateRejected")
		return false
	end

	local previousStateId = self.activeStateId
	for index = #fromPath, sharedLength + 1, -1 do
		local stateId = fromPath[index]
		callStateExit(self.stateObjects[stateId], self)
		local state = self.states[stateId]
		if state ~= nil and state.onExit ~= nil then
			state.onExit(self.context, stateId, self, payload)
		end
		self.stateElapsed[stateId] = nil
	end

	for index = sharedLength + 1, #toPath do
		local stateId = toPath[index]
		self.stateElapsed[stateId] = 0
		callStateEnter(self.stateObjects[stateId], self)
		local state = self.states[stateId]
		if state ~= nil and state.onEnter ~= nil then
			state.onEnter(self.context, stateId, self, payload)
		end
	end

	self.activePath = toPath
	self.previousStateId = previousStateId
	self.activeStateId = targetStateId
	if self.activeStateBrio ~= nil then
		self.activeStateBrio:Kill()
	end
	self.activeStateBrio = Brio.new(targetStateId)
	self.activeStateValue.Value = targetStateId
	self.transitionCount += 1
	self.StateChanged:Fire(targetStateId, previousStateId, payload)
	self.Transitioned:Fire(previousStateId, targetStateId, payload)
	return true
end

function StateMachine.Start(self: StateMachine, initialStateNameRaw: any): boolean
	if self.destroyed then
		return false
	end
	local initialStateName = coerceStateName(initialStateNameRaw)
	if initialStateName == nil or self.states[initialStateName] == nil then
		return false
	end
	if self.running then
		return self:ChangeState(initialStateName)
	end

	self.running = true
	self.activeStateId = nil
	self.previousStateId = nil
	self.activePath = {}
	self.stateElapsed = {}
	local transitioned = self:_transition(initialStateName, nil, false)
	if transitioned then
		self.transitionCount = math.max(0, self.transitionCount - 1)
		self.Started:Fire(initialStateName)
	end
	return transitioned
end

function StateMachine.Stop(self: StateMachine)
	if not self.running or self.destroyed then
		return
	end

	local fromPath = self.activePath
	for index = #fromPath, 1, -1 do
		local stateId = fromPath[index]
		callStateExit(self.stateObjects[stateId], self)
		local state = self.states[stateId]
		if state ~= nil and state.onExit ~= nil then
			state.onExit(self.context, stateId, self, {
				reason = "Stop",
			})
		end
	end

	self.previousStateId = self.activeStateId
	self.activeStateId = nil
	self.activePath = {}
	self.stateElapsed = {}
	self.stateStack:Clear()
	self.running = false
	if self.activeStateBrio ~= nil then
		self.activeStateBrio:Kill()
		self.activeStateBrio = nil
	end
	self.activeStateValue.Value = nil
	self.StateChanged:Fire(nil, self.previousStateId, {
		reason = "Stop",
	})
	self.Stopped:Fire(self.previousStateId)
end

function StateMachine.ChangeState(self: StateMachine, stateNameRaw: any): boolean
	if self.disabled or not self.running then
		return false
	end
	local stateName = coerceStateName(stateNameRaw)
	if stateName == nil then
		self.TransitionRejected:Fire(self.activeStateId, nil, nil, "BadStateName")
		return false
	end
	return self:_transition(stateName, nil, false)
end

function StateMachine.PushState(self: StateMachine, stateNameRaw: any): boolean
	if self.activeStateId == nil then
		return self:ChangeState(stateNameRaw)
	end
	self.stateStack:Push(self.activeStateId)
	if self:ChangeState(stateNameRaw) then
		return true
	end
	self.stateStack:Pop()
	return false
end

function StateMachine.PopState(self: StateMachine): boolean
	local stateName = self.stateStack:Pop()
	if stateName == nil then
		return false
	end
	return self:ChangeState(stateName)
end

function StateMachine.RegisterState(self: StateMachine, stateNameRaw: any, stateObjectRaw: any): boolean
	if self.destroyed then
		return false
	end
	local stateName = coerceStateName(stateNameRaw)
	if stateName == nil then
		return false
	end

	local stateObject = if typeof(stateObjectRaw) == "table" then stateObjectRaw else {}
	if typeof(stateObject.Name) ~= "string" or stateObject.Name == "" then
		stateObject.Name = stateName
	end

	local parent = if typeof(stateObject.Parent) == "string" and stateObject.Parent ~= ""
		then stateObject.Parent
		else nil
	self:_ensureStateDefinition(stateName, parent)
	self.stateObjects[stateName] = stateObject
	return true
end

function StateMachine.RegisterTransition(self: StateMachine, transitionRaw: any): boolean
	if self.destroyed or typeof(transitionRaw) ~= "table" then
		return false
	end

	local to = coerceStateName((transitionRaw :: TransitionObject).To)
	if to == nil then
		return false
	end

	self.transitionOrder += 1
	(transitionRaw :: TransitionObject)._order = self.transitionOrder
	table.insert(self.registeredTransitions, transitionRaw :: TransitionObject)
	return true
end

function StateMachine.TransitionTo(
	self: StateMachine,
	stateIdRaw: any,
	payload: any?,
	interruptPriorityRaw: any
): boolean
	if self.disabled or not self.running then
		return false
	end
	local stateId = coerceStateName(stateIdRaw)
	if stateId == nil or self.states[stateId] == nil then
		return false
	end
	local interruptPriority = clampPriority(interruptPriorityRaw, 0)
	if interruptPriority < self:_currentInterruptThreshold() then
		return false
	end
	return self:_transition(stateId, payload, false)
end

function StateMachine.Dispatch(self: StateMachine, eventNameRaw: any, eventPayload: any?): boolean
	if self.disabled or not self.running then
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
	}, false)
end

function StateMachine._applyRegisteredTransition(self: StateMachine): boolean
	local candidates = self:_collectRegisteredCandidates()
	local selected = candidates[1]
	if selected == nil then
		return false
	end

	local transition = selected.transition
	if transition ~= nil and transition.Action ~= nil then
		pcall(transition.Action, self)
	end

	return self:_transition(selected.to, {
		from = selected.from,
	}, transition ~= nil and transition.AllowSelfTransition == true)
end

function StateMachine.Update(self: StateMachine, dtRaw: any): boolean
	if self.disabled or not self.running or self.destroyed then
		return false
	end
	local dt = if typeof(dtRaw) == "number" and dtRaw > 0 and dtRaw == dtRaw then dtRaw else 0
	if dt <= 0 then
		return false
	end

	self.elapsed += dt
	for _, stateId in self.activePath do
		self.stateElapsed[stateId] = (self.stateElapsed[stateId] or 0) + dt
		callStateUpdate(self.stateObjects[stateId], self, dt)
		local state = self.states[stateId]
		if state ~= nil and state.onUpdate ~= nil then
			state.onUpdate(self.context, stateId, dt, self)
		end
	end

	if self:_applyRegisteredTransition() then
		return true
	end

	local timedCandidates = self:_collectCandidates(nil, nil)
	local selected = timedCandidates[1]
	if selected ~= nil then
		return self:_transition(selected.to, {
			after = selected.after,
			from = selected.from,
		}, false)
	end
	return false
end

function StateMachine.IsInState(self: StateMachine, stateIdRaw: any): boolean
	if typeof(stateIdRaw) ~= "string" then
		return false
	end
	if stateIdRaw == self.activeStateId then
		return true
	end
	return tableContainsPath(self.activePath, stateIdRaw)
end

function StateMachine.GetTransitionCount(self: StateMachine): number
	return self.transitionCount
end

function StateMachine.Destroy(self: StateMachine)
	if self.destroyed then
		return
	end
	self:Stop()
	self.destroyed = true

	for _, stateObject in self.stateObjects do
		callStateDestroy(stateObject)
	end

	table.clear(self.states)
	table.clear(self.stateObjects)
	table.clear(self.registeredTransitions)
	self.Destroyed:Fire()
	self.maid:DoCleaning()
end
return StateMachine
