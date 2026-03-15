--!strict

local TickScheduler = {}
TickScheduler.__index = TickScheduler

TickScheduler.Priority = {
	HIGH = 200,
	NORMAL = 100,
	LOW = 0,
}

export type CancellationToken = {
	id: number,
	cancelled: boolean,
	group: string,
	cancel: (self: CancellationToken) -> (),
}

export type TaskRecord = {
	id: number,
	order: number,
	priority: number,
	group: string,
	callback: (dt: number, now: number, token: CancellationToken) -> (),
	nextRun: number,
	interval: number,
	repeatCount: number,
	useFixedClock: boolean,
	catchUp: boolean,
	token: CancellationToken,
}

export type ScheduleOptions = {
	interval: number?,
	repeatCount: number?,
	priority: number?,
	group: string?,
	fixed: boolean?,
	catchUp: boolean?,
}

export type SchedulerConfig = {
	fixedStep: number?,
}

export type TickScheduler = typeof(setmetatable({} :: any, TickScheduler))

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

local function clampPositiveNumber(valueRaw: any, fallback: number, minValue: number, maxValue: number): number
	local value = if typeof(valueRaw) == "number" then valueRaw else fallback
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function compareDue(a: TaskRecord, b: TaskRecord): boolean
	if a.priority ~= b.priority then
		return a.priority > b.priority
	end
	if a.nextRun ~= b.nextRun then
		return a.nextRun < b.nextRun
	end
	if a.order ~= b.order then
		return a.order < b.order
	end
	return a.id < b.id
end

local function clearArray(array: { any })
	for index = #array, 1, -1 do
		array[index] = nil
	end
end

function TickScheduler.new(configRaw: SchedulerConfig?): TickScheduler
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local fixedStep = clampPositiveNumber(config.fixedStep, 1 / 60, 1 / 240, 1)
	local self = setmetatable({
		now = 0,
		fixedNow = 0,
		fixedStep = fixedStep,
		fixedAccumulator = 0,
		nextTaskId = 0,
		nextOrder = 0,
		tasks = {} :: { [number]: TaskRecord },
		pausedGroups = {} :: { [string]: boolean },
		dueBuffer = {} :: { TaskRecord },
	}, TickScheduler)
	return self
end

function TickScheduler._isGroupPaused(self: TickScheduler, group: string): boolean
	return self.pausedGroups[group] == true
end

function TickScheduler._createToken(self: TickScheduler, id: number, group: string): CancellationToken
	local token = {
		id = id,
		cancelled = false,
		group = group,
	} :: CancellationToken

	function token.cancel(selfToken: CancellationToken)
		if selfToken.cancelled then
			return
		end
		selfToken.cancelled = true
		self:cancel(selfToken)
	end

	return token
end

function TickScheduler.schedule(self: TickScheduler, callbackRaw: any, delayRaw: any, optionsRaw: ScheduleOptions?): CancellationToken
	if typeof(callbackRaw) ~= "function" then
		error("TickScheduler.schedule expects a callback")
	end

	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	local delay = clampPositiveNumber(delayRaw, 0, 0, 1e9)
	local interval = clampPositiveNumber(options.interval, 0, 0, 1e9)
	local repeatCount = if typeof(options.repeatCount) == "number" then math.floor(options.repeatCount) else 1
	if repeatCount < -1 then
		repeatCount = -1
	end
	if repeatCount == 0 then
		repeatCount = 1
	end

	local group = if typeof(options.group) == "string" and options.group ~= "" then options.group else "default"
	local useFixedClock = options.fixed == true
	local priority = clampPriority(options.priority, TickScheduler.Priority.NORMAL)
	local nowBase = if useFixedClock then self.fixedNow else self.now

	self.nextTaskId += 1
	self.nextOrder += 1
	local taskId = self.nextTaskId
	local token = self:_createToken(taskId, group)

	local task = {
		id = taskId,
		order = self.nextOrder,
		priority = priority,
		group = group,
		callback = callbackRaw,
		nextRun = nowBase + delay,
		interval = interval,
		repeatCount = repeatCount,
		useFixedClock = useFixedClock,
		catchUp = options.catchUp == true,
		token = token,
	} :: TaskRecord
	self.tasks[taskId] = task
	return token
end

function TickScheduler.scheduleEvery(self: TickScheduler, callbackRaw: any, intervalRaw: any, optionsRaw: ScheduleOptions?): CancellationToken
	local options = if typeof(optionsRaw) == "table" then table.clone(optionsRaw) else {}
	options.interval = intervalRaw
	options.repeatCount = -1
	return self:schedule(callbackRaw, intervalRaw, options)
end

function TickScheduler.scheduleFixed(self: TickScheduler, callbackRaw: any, stepsRaw: any, optionsRaw: ScheduleOptions?): CancellationToken
	local steps = if typeof(stepsRaw) == "number" then math.max(1, math.floor(stepsRaw)) else 1
	local options = if typeof(optionsRaw) == "table" then table.clone(optionsRaw) else {}
	options.fixed = true
	options.interval = self.fixedStep * steps
	if options.repeatCount == nil then
		options.repeatCount = -1
	end
	return self:schedule(callbackRaw, options.interval, options)
end

function TickScheduler.cancel(self: TickScheduler, tokenOrIdRaw: any): boolean
	local taskId: number? = nil
	if typeof(tokenOrIdRaw) == "number" then
		taskId = math.floor(tokenOrIdRaw)
	elseif typeof(tokenOrIdRaw) == "table" and typeof(tokenOrIdRaw.id) == "number" then
		taskId = math.floor(tokenOrIdRaw.id)
		local token = tokenOrIdRaw :: CancellationToken
		token.cancelled = true
	end
	if taskId == nil then
		return false
	end
	local task = self.tasks[taskId]
	if task == nil then
		return false
	end
	task.token.cancelled = true
	self.tasks[taskId] = nil
	return true
end

function TickScheduler.pauseGroup(self: TickScheduler, groupRaw: any)
	if typeof(groupRaw) ~= "string" or groupRaw == "" then
		return
	end
	self.pausedGroups[groupRaw] = true
end

function TickScheduler.resumeGroup(self: TickScheduler, groupRaw: any)
	if typeof(groupRaw) ~= "string" or groupRaw == "" then
		return
	end
	self.pausedGroups[groupRaw] = nil
end

function TickScheduler.isGroupPaused(self: TickScheduler, groupRaw: any): boolean
	if typeof(groupRaw) ~= "string" or groupRaw == "" then
		return false
	end
	return self.pausedGroups[groupRaw] == true
end

function TickScheduler.cancelGroup(self: TickScheduler, groupRaw: any): number
	if typeof(groupRaw) ~= "string" or groupRaw == "" then
		return 0
	end
	local cancelled = 0
	for taskId, task in self.tasks do
		if task.group == groupRaw then
			self.tasks[taskId] = nil
			task.token.cancelled = true
			cancelled += 1
		end
	end
	return cancelled
end

function TickScheduler._runClock(self: TickScheduler, nowTime: number, dt: number, useFixedClock: boolean): number
	local due = self.dueBuffer
	clearArray(due)

	for _, task in self.tasks do
		if task == nil or typeof(task) ~= "table" then
			continue
		end
		if task.token == nil then
			continue
		end
		if task.useFixedClock ~= useFixedClock then
			continue
		end
		if task.token.cancelled then
			continue
		end
		if self:_isGroupPaused(task.group) then
			continue
		end
		if task.nextRun <= nowTime then
			due[#due + 1] = task
		end
	end

	if #due == 0 then
		return 0
	end

	table.sort(due, compareDue)
	local fired = 0
	for index = 1, #due do
		local task = due[index]
		if task == nil or typeof(task) ~= "table" then
			continue
		end
		if task.token == nil then
			continue
		end
		if task.token.cancelled then
			continue
		end
		if self.tasks[task.id] == nil then
			continue
		end

		fired += 1
		local ok, err = pcall(task.callback, dt, nowTime, task.token)
		if not ok then
			warn(string.format("[TickScheduler] task %d callback failed: %s", task.id, tostring(err)))
		end

		if task.token.cancelled then
			self.tasks[task.id] = nil
			continue
		end

		if task.interval <= 0 then
			self.tasks[task.id] = nil
			task.token.cancelled = true
			continue
		end

		if task.repeatCount > 0 then
			task.repeatCount -= 1
			if task.repeatCount <= 0 then
				self.tasks[task.id] = nil
				task.token.cancelled = true
				continue
			end
		end

		task.nextRun += task.interval
		if not task.catchUp and task.nextRun < nowTime then
			task.nextRun = nowTime + task.interval
		end
	end

	clearArray(due)
	return fired
end

function TickScheduler.update(self: TickScheduler, dtRaw: any): number
	local dt = if typeof(dtRaw) == "number" and dtRaw > 0 then dtRaw else 0
	if dt <= 0 then
		return 0
	end

	self.now += dt
	local fired = self:_runClock(self.now, dt, false)

	self.fixedAccumulator += dt
	while self.fixedAccumulator >= self.fixedStep do
		self.fixedAccumulator -= self.fixedStep
		self.fixedNow += self.fixedStep
		fired += self:_runClock(self.fixedNow, self.fixedStep, true)
	end

	return fired
end

function TickScheduler.flush(self: TickScheduler): number
	local fired = 0
	fired += self:_runClock(self.now, 0, false)
	fired += self:_runClock(self.fixedNow, self.fixedStep, true)
	return fired
end

function TickScheduler.getStats(self: TickScheduler): { [string]: number }
	local active = 0
	local fixed = 0
	local variable = 0
	for _, task in self.tasks do
		if task == nil or typeof(task) ~= "table" or task.token == nil then
			continue
		end
		if task.token.cancelled then
			continue
		end
		active += 1
		if task.useFixedClock then
			fixed += 1
		else
			variable += 1
		end
	end
	return {
		now = self.now,
		fixedNow = self.fixedNow,
		fixedAccumulator = self.fixedAccumulator,
		activeTasks = active,
		fixedTasks = fixed,
		variableTasks = variable,
	}
end

function TickScheduler.clear(self: TickScheduler)
	for _, task in self.tasks do
		if task == nil or typeof(task) ~= "table" or task.token == nil then
			continue
		end
		task.token.cancelled = true
	end
	table.clear(self.tasks)
	table.clear(self.pausedGroups)
end

return TickScheduler
