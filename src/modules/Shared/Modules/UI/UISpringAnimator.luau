--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)
local Spring = require(script:FindFirstAncestor("game").Shared.Modules.Math.Spring)

local RunService = game:GetService("RunService")

local UISpringAnimator = {}
UISpringAnimator.__index = UISpringAnimator

export type SpringConfig = {
	dampingRatio: number?,
	frequency: number?,
	mass: number?,
	precision: number?,
}

export type AnimationHandle = {
	instance: Instance,
	property: string,
	cancel: () -> (),
}

export type AnimatorConfig = {
	tickScheduler: any?,
	updateHz: number?,
	defaultConfig: SpringConfig?,
	profileHook: ((stats: { [string]: number }) -> ())?,
}

export type UISpringAnimator = typeof(setmetatable({} :: any, UISpringAnimator))

local function clampNumber(valueRaw: any, fallback: number, minValue: number, maxValue: number): number
	local value = if typeof(valueRaw) == "number" then valueRaw else fallback
	if value < minValue then
		return minValue
	end
	if value > maxValue then
		return maxValue
	end
	return value
end

local function safeDisconnect(connection: any?)
	if connection == nil then
		return
	end
	pcall(function()
		connection:Disconnect()
	end)
end

local function clearArray(array: { any })
	for index = #array, 1, -1 do
		array[index] = nil
	end
end

local function typeIsSupported(kind: string): boolean
	return kind == "number" or kind == "UDim2" or kind == "Vector2" or kind == "Vector3" or kind == "Color3" or kind == "UDim"
end

local function componentCountFor(kind: string): number
	if kind == "number" then
		return 1
	end
	if kind == "UDim" then
		return 2
	end
	if kind == "Vector2" then
		return 2
	end
	if kind == "Vector3" then
		return 3
	end
	if kind == "Color3" then
		return 3
	end
	if kind == "UDim2" then
		return 4
	end
	return 0
end

local function fillComponents(kind: string, value: any, out: { number })
	if kind == "number" then
		out[1] = value
		return
	end
	if kind == "UDim" then
		out[1] = value.Scale
		out[2] = value.Offset
		return
	end
	if kind == "Vector2" then
		out[1] = value.X
		out[2] = value.Y
		return
	end
	if kind == "Vector3" then
		out[1] = value.X
		out[2] = value.Y
		out[3] = value.Z
		return
	end
	if kind == "Color3" then
		out[1] = value.R
		out[2] = value.G
		out[3] = value.B
		return
	end
	if kind == "UDim2" then
		out[1] = value.X.Scale
		out[2] = value.X.Offset
		out[3] = value.Y.Scale
		out[4] = value.Y.Offset
		return
	end
end

local function fromComponents(kind: string, components: { number }): any
	if kind == "number" then
		return components[1]
	end
	if kind == "UDim" then
		return UDim.new(components[1], components[2])
	end
	if kind == "Vector2" then
		return Vector2.new(components[1], components[2])
	end
	if kind == "Vector3" then
		return Vector3.new(components[1], components[2], components[3])
	end
	if kind == "Color3" then
		return Color3.new(components[1], components[2], components[3])
	end
	if kind == "UDim2" then
		return UDim2.new(components[1], components[2], components[3], components[4])
	end
	return nil
end

local function springStep(position: number, velocity: number, target: number, dt: number, frequency: number, dampingRatio: number, mass: number): (number, number)
	local nextState = Spring.step({
		value = position,
		velocity = velocity,
	}, target, frequency, dampingRatio, dt, mass)
	return nextState.value, nextState.velocity
end

function UISpringAnimator.New(configRaw: AnimatorConfig?): UISpringAnimator
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local defaultConfig = if typeof(config.defaultConfig) == "table" then config.defaultConfig else {}
	local self = setmetatable({
		tickScheduler = config.tickScheduler,
		updateHz = clampNumber(config.updateHz, 60, 1, 360),
		defaultDampingRatio = clampNumber(defaultConfig.dampingRatio, 1, 0.01, 10),
		defaultFrequency = clampNumber(defaultConfig.frequency, 6, 0.01, 60),
		defaultMass = clampNumber(defaultConfig.mass, 1, 0.001, 1000),
		defaultPrecision = clampNumber(defaultConfig.precision, 0.001, 1e-6, 1),
		profileHook = config.profileHook,
		activeByInstance = {} :: { [Instance]: { [string]: any } },
		activeInstances = {} :: { Instance },
		instancePresence = {} :: { [Instance]: boolean },
		instanceConnections = {} :: { [Instance]: { any? } },
		isRunning = false,
		loopToken = nil,
		heartbeatConnection = nil,
		profileStats = {
			active = 0,
			processed = 0,
			dt = 0,
			costMs = 0,
		},
	}, UISpringAnimator)
	return self
end

function UISpringAnimator.SetProfileHook(self: UISpringAnimator, callbackRaw: any)
	if callbackRaw == nil then
		self.profileHook = nil
		return
	end
	if typeof(callbackRaw) == "function" then
		self.profileHook = callbackRaw
	end
end

function UISpringAnimator._watchInstance(self: UISpringAnimator, instance: Instance)
	if self.instanceConnections[instance] ~= nil then
		return
	end
	local destroyingConnection = nil
	if typeof((instance :: any).Destroying) == "RBXScriptSignal" then
		destroyingConnection = (instance :: any).Destroying:Connect(function()
			self:stopAllForInstance(instance)
		end)
	end
	local ancestryConnection = instance.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			self:stopAllForInstance(instance)
		end
	end)
	self.instanceConnections[instance] = { destroyingConnection, ancestryConnection }
end

function UISpringAnimator._unwatchInstance(self: UISpringAnimator, instance: Instance)
	local connections = self.instanceConnections[instance]
	if connections == nil then
		return
	end
	for _, connection in connections do
		safeDisconnect(connection)
	end
	self.instanceConnections[instance] = nil
end

function UISpringAnimator._ensureLoop(self: UISpringAnimator)
	if self.isRunning then
		return
	end
	self.isRunning = true
	if self.tickScheduler ~= nil and typeof((self.tickScheduler :: any).scheduleEvery) == "function" then
		self.loopToken = (self.tickScheduler :: any):scheduleEvery(function(dt: number)
			self:step(dt)
		end, 1 / self.updateHz, {
			group = "ui.spring",
			priority = 200,
			catchUp = false,
		})
		return
	end
	self.heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		self:step(dt)
	end)
end

function UISpringAnimator._stopLoop(self: UISpringAnimator)
	if not self.isRunning then
		return
	end
	self.isRunning = false
	if self.loopToken ~= nil then
		if typeof(self.loopToken.cancel) == "function" then
			self.loopToken:cancel()
		elseif self.tickScheduler ~= nil and typeof((self.tickScheduler :: any).cancel) == "function" then
			local schedulerAny = self.tickScheduler :: any
			schedulerAny:cancel(self.loopToken)
		end
		self.loopToken = nil
	end
	if self.heartbeatConnection ~= nil then
		safeDisconnect(self.heartbeatConnection)
		self.heartbeatConnection = nil
	end
end

function UISpringAnimator._cleanupInstanceSlot(self: UISpringAnimator, instance: Instance)
	local byProperty = self.activeByInstance[instance]
	if byProperty ~= nil and next(byProperty) ~= nil then
		return
	end
	self.activeByInstance[instance] = nil
	if self.instancePresence[instance] then
		self.instancePresence[instance] = nil
		for index = #self.activeInstances, 1, -1 do
			if self.activeInstances[index] == instance then
				table.remove(self.activeInstances, index)
				break
			end
		end
	end
	self:_unwatchInstance(instance)
	if #self.activeInstances == 0 then
		self:_stopLoop()
	end
end

function UISpringAnimator.Animate(
	self: UISpringAnimator,
	instanceRaw: any,
	propertyRaw: any,
	targetValue: any,
	configRaw: SpringConfig?
): AnimationHandle?
	if typeof(instanceRaw) ~= "Instance" then
		return nil
	end
	if typeof(propertyRaw) ~= "string" or propertyRaw == "" then
		return nil
	end

	local instance = instanceRaw :: Instance
	local property = propertyRaw :: string
	local ok, currentValue = pcall(function()
		return (instance :: any)[property]
	end)
	if not ok then
		return nil
	end

	local kind = typeof(currentValue)
	if not typeIsSupported(kind) then
		return nil
	end
	if typeof(targetValue) ~= kind then
		return nil
	end

	local byProperty = self.activeByInstance[instance]
	if byProperty == nil then
		byProperty = {}
		self.activeByInstance[instance] = byProperty
	end
	local state = byProperty[property]
	if state == nil then
		local componentCount = componentCountFor(kind)
		local valueComponents = Sift.Array.create(componentCount, 0)
		local targetComponents = Sift.Array.create(componentCount, 0)
		local velocityComponents = Sift.Array.create(componentCount, 0)
		fillComponents(kind, currentValue, valueComponents)
		fillComponents(kind, targetValue, targetComponents)
		state = {
			kind = kind,
			componentCount = componentCount,
			value = valueComponents,
			target = targetComponents,
			velocity = velocityComponents,
			dampingRatio = self.defaultDampingRatio,
			frequency = self.defaultFrequency,
			mass = self.defaultMass,
			precision = self.defaultPrecision,
		}
		byProperty[property] = state
	else
		fillComponents(kind, targetValue, state.target)
	end

	local config = if typeof(configRaw) == "table" then configRaw else {}
	state.dampingRatio = clampNumber(config.dampingRatio, state.dampingRatio, 0.01, 10)
	state.frequency = clampNumber(config.frequency, state.frequency, 0.01, 60)
	state.mass = clampNumber(config.mass, state.mass, 0.001, 1000)
	state.precision = clampNumber(config.precision, state.precision, 1e-6, 100)

	if not self.instancePresence[instance] then
		self.instancePresence[instance] = true
		self.activeInstances[#self.activeInstances + 1] = instance
	end
	self:_watchInstance(instance)
	self:_ensureLoop()

	local handle = {
		instance = instance,
		property = property,
		cancel = function()
			self:stop(instance, property)
		end,
	}
	return handle
end

function UISpringAnimator.AnimateBatch(self: UISpringAnimator, requestsRaw: any)
	if typeof(requestsRaw) ~= "table" then
		return
	end
	for index = 1, #requestsRaw do
		local request = requestsRaw[index]
		if typeof(request) ~= "table" then
			continue
		end
		self:animate(request.instance, request.property, request.targetValue, request.config)
	end
end

function UISpringAnimator.Stop(self: UISpringAnimator, instanceRaw: any, propertyRaw: any?)
	if typeof(instanceRaw) ~= "Instance" then
		return
	end
	local byProperty = self.activeByInstance[instanceRaw]
	if byProperty == nil then
		return
	end
	if propertyRaw == nil then
		table.clear(byProperty)
		self:_cleanupInstanceSlot(instanceRaw)
		return
	end
	if typeof(propertyRaw) ~= "string" then
		return
	end
	byProperty[propertyRaw] = nil
	self:_cleanupInstanceSlot(instanceRaw)
end

function UISpringAnimator.StopAllForInstance(self: UISpringAnimator, instanceRaw: any)
	self:stop(instanceRaw, nil)
end

function UISpringAnimator.Step(self: UISpringAnimator, dtRaw: any)
	local dt = clampNumber(dtRaw, 0, 0, 0.25)
	if dt <= 0 then
		return
	end
	if #self.activeInstances == 0 then
		self:_stopLoop()
		return
	end

	local tickStart = os.clock()
	local processed = 0
	for index = #self.activeInstances, 1, -1 do
		local instance = self.activeInstances[index]
		local byProperty = self.activeByInstance[instance]
		if byProperty == nil then
			table.remove(self.activeInstances, index)
			self.instancePresence[instance] = nil
			self:_unwatchInstance(instance)
			continue
		end

		for property, state in byProperty do
			processed += 1
			local done = true
			for componentIndex = 1, state.componentCount do
				local nextValue, nextVelocity = springStep(
					state.value[componentIndex],
					state.velocity[componentIndex],
					state.target[componentIndex],
					dt,
					state.frequency,
					state.dampingRatio,
					state.mass
				)
				state.value[componentIndex] = nextValue
				state.velocity[componentIndex] = nextVelocity
				if math.abs(nextValue - state.target[componentIndex]) > state.precision or math.abs(nextVelocity) > state.precision then
					done = false
				end
			end

			local value = fromComponents(state.kind, state.value)
			if value ~= nil then
				local okWrite = pcall(function()
					(instance :: any)[property] = value
				end)
				if not okWrite then
					byProperty[property] = nil
					continue
				end
			end

			if done then
				local targetValue = fromComponents(state.kind, state.target)
				if targetValue ~= nil then
					pcall(function()
						(instance :: any)[property] = targetValue
					end)
				end
				byProperty[property] = nil
			end
		end

		if next(byProperty) == nil then
			self.activeByInstance[instance] = nil
			self.instancePresence[instance] = nil
			table.remove(self.activeInstances, index)
			self:_unwatchInstance(instance)
		end
	end

	if #self.activeInstances == 0 then
		self:_stopLoop()
	end

	if self.profileHook ~= nil then
		self.profileStats.active = #self.activeInstances
		self.profileStats.processed = processed
		self.profileStats.dt = dt
		self.profileStats.costMs = (os.clock() - tickStart) * 1000
		self.profileHook(self.profileStats)
	end
end

function UISpringAnimator.Destroy(self: UISpringAnimator)
	self:_stopLoop()
	for instance in self.instanceConnections do
		self:_unwatchInstance(instance)
	end
	table.clear(self.instanceConnections)
	table.clear(self.activeByInstance)
	table.clear(self.instancePresence)
	clearArray(self.activeInstances)
end

UISpringAnimator.Animate = UISpringAnimator.Animate
UISpringAnimator.AnimateBatch = UISpringAnimator.AnimateBatch
UISpringAnimator.Stop = UISpringAnimator.Stop
UISpringAnimator.StopAllForInstance = UISpringAnimator.StopAllForInstance
UISpringAnimator.Step = UISpringAnimator.Step

UISpringAnimator.new = UISpringAnimator.New
UISpringAnimator.setProfileHook = UISpringAnimator.SetProfileHook
UISpringAnimator.animate = UISpringAnimator.Animate
UISpringAnimator.animateBatch = UISpringAnimator.AnimateBatch
UISpringAnimator.stop = UISpringAnimator.Stop
UISpringAnimator.stopAllForInstance = UISpringAnimator.StopAllForInstance
UISpringAnimator.step = UISpringAnimator.Step
UISpringAnimator.destroy = UISpringAnimator.Destroy

return UISpringAnimator
