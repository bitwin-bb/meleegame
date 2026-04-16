--!strict

local Resolve = {}
Resolve.__index = Resolve

export type ViewConfig = {
	distance: number,
	height: number,
	lookHeight: number,
	fieldOfView: number,
}

export type Settings = {
	sideSign: number,
	movementBackAmount: number,
	movementSpeedForMaxBack: number,
	movementBackSign: number,
	mouseInfluenceX: number,
	mouseInfluenceY: number,
}

export type ResolutionResult = {
	state: { [string]: any },
	override: { [string]: any }?,
	subject: { [string]: any }?,
	predicted: { [string]: any },
	targetPosition: Vector3?,
	baseTargetPosition: Vector3?,
	lookPosition: Vector3?,
	viewConfig: ViewConfig,
	settings: Settings,
	cameraCFrame: CFrame?,
	fieldOfView: number,
}

export type Resolve = typeof(setmetatable(
	{} :: {
		cache: any,
		predictor: any,
		stack: any,
		state: any,
		target: any,
	},
	Resolve
))

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then valueRaw else fallback
	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function sanitizeSign(valueRaw: any, fallback: number): number
	local sign = math.sign(sanitizeNumber(valueRaw, fallback, -1, 1))
	if sign == 0 then
		return if fallback < 0 then -1 else 1
	end
	return sign
end

local function cloneViewConfig(viewConfig: ViewConfig): ViewConfig
	return {
		distance = viewConfig.distance,
		height = viewConfig.height,
		lookHeight = viewConfig.lookHeight,
		fieldOfView = viewConfig.fieldOfView,
	}
end

local function cloneSettings(settings: Settings): Settings
	return {
		sideSign = settings.sideSign,
		movementBackAmount = settings.movementBackAmount,
		movementSpeedForMaxBack = settings.movementSpeedForMaxBack,
		movementBackSign = settings.movementBackSign,
		mouseInfluenceX = settings.mouseInfluenceX,
		mouseInfluenceY = settings.mouseInfluenceY,
	}
end

local function resolveViewConfig(baseViewConfig: ViewConfig, overrideRaw: any): ViewConfig
	local override = if typeof(overrideRaw) == "table" then overrideRaw else {}
	local overrideViewConfig = if typeof((override :: any).viewConfig) == "table" then (override :: any).viewConfig else nil
	local nextViewConfig = cloneViewConfig(baseViewConfig)

	local source = if overrideViewConfig ~= nil then overrideViewConfig else override
	if typeof((source :: any).distance) == "number" then
		nextViewConfig.distance = math.max((source :: any).distance, 0)
	end
	if typeof((source :: any).height) == "number" then
		nextViewConfig.height = (source :: any).height
	end
	if typeof((source :: any).lookHeight) == "number" then
		nextViewConfig.lookHeight = (source :: any).lookHeight
	end
	if typeof((override :: any).fieldOfView) == "number" then
		nextViewConfig.fieldOfView = sanitizeNumber((override :: any).fieldOfView, nextViewConfig.fieldOfView, 1, 120)
	elseif typeof((source :: any).fieldOfView) == "number" then
		nextViewConfig.fieldOfView = sanitizeNumber((source :: any).fieldOfView, nextViewConfig.fieldOfView, 1, 120)
	end

	return nextViewConfig
end

local function resolveSettings(baseSettings: Settings, overrideRaw: any): Settings
	local override = if typeof(overrideRaw) == "table" then overrideRaw else {}
	local settings = cloneSettings(baseSettings)

	settings.sideSign = sanitizeSign((override :: any).sideSign, settings.sideSign)

	if typeof((override :: any).movementBackAmount) == "number" then
		settings.movementBackAmount = math.max((override :: any).movementBackAmount, 0)
	end
	if typeof((override :: any).movementSpeedForMaxBack) == "number" then
		settings.movementSpeedForMaxBack = math.max((override :: any).movementSpeedForMaxBack, 0.01)
	end
	if typeof((override :: any).movementBackSign) == "number" then
		settings.movementBackSign = sanitizeSign((override :: any).movementBackSign, settings.movementBackSign)
	end
	if typeof((override :: any).mouseInfluenceX) == "number" then
		settings.mouseInfluenceX = math.max((override :: any).mouseInfluenceX, 0)
	end
	if typeof((override :: any).mouseInfluenceY) == "number" then
		settings.mouseInfluenceY = math.max((override :: any).mouseInfluenceY, 0)
	end

	if (override :: any).disableMovementBack == true then
		settings.movementBackAmount = 0
	end
	if (override :: any).disableMouseInfluence == true then
		settings.mouseInfluenceX = 0
		settings.mouseInfluenceY = 0
	end

	return settings
end

function Resolve.New(dependenciesRaw: any?): Resolve
	local dependencies = if typeof(dependenciesRaw) == "table" then dependenciesRaw else {}
	return setmetatable({
		cache = (dependencies :: any).cache,
		predictor = (dependencies :: any).predictor,
		stack = (dependencies :: any).stack,
		state = (dependencies :: any).state,
		target = (dependencies :: any).target,
	}, Resolve)
end

function Resolve.Resolve(self: Resolve, contextRaw: any): ResolutionResult
	local context = if typeof(contextRaw) == "table" then contextRaw else {}
	local now = sanitizeNumber((context :: any).now, os.clock(), 0, nil)
	local deltaTime = sanitizeNumber((context :: any).deltaTime, 1 / 60, 0, 1)

	local baseViewConfig = resolveViewConfig({
		distance = sanitizeNumber((context :: any).distance, 38, 0, 4096),
		height = sanitizeNumber((context :: any).height, 8, -4096, 4096),
		lookHeight = sanitizeNumber((context :: any).lookHeight, 3, -4096, 4096),
		fieldOfView = sanitizeNumber((context :: any).fieldOfView, 60, 1, 120),
	}, nil)
	local baseSettings = resolveSettings({
		sideSign = sanitizeSign((context :: any).sideSign, 1),
		movementBackAmount = math.max(sanitizeNumber((context :: any).movementBackAmount, 0, 0, 4096), 0),
		movementSpeedForMaxBack = math.max(
			sanitizeNumber((context :: any).movementSpeedForMaxBack, 1, 0.01, 4096),
			0.01
		),
		movementBackSign = sanitizeSign((context :: any).movementBackSign, 1),
		mouseInfluenceX = math.max(sanitizeNumber((context :: any).mouseInfluenceX, 0, 0, 256), 0),
		mouseInfluenceY = math.max(sanitizeNumber((context :: any).mouseInfluenceY, 0, 0, 256), 0),
	}, nil)

	local override = nil
	if typeof(self.stack) == "table" and typeof((self.stack :: any).resolve) == "function" then
		override = (self.stack :: any):resolve(now)
	end

	local subject = nil
	if typeof(self.target) == "table" and typeof((self.target :: any).resolve) == "function" then
		subject = (self.target :: any):resolve({
			override = override,
			character = (context :: any).character,
			localPlayer = (context :: any).localPlayer,
			now = now,
		})
	end

	local predicted = {
		active = false,
		position = if subject ~= nil then (subject :: any).position else nil,
		basePosition = if subject ~= nil then (subject :: any).position else nil,
		velocity = if subject ~= nil and typeof((subject :: any).velocity) == "Vector3"
			then (subject :: any).velocity
			else Vector3.zero,
		speed = 0,
		leadTime = 0,
		offset = Vector3.zero,
	}
	if subject ~= nil and typeof(self.predictor) == "table" and typeof((self.predictor :: any).resolve) == "function" then
		predicted = (self.predictor :: any):resolve(subject, self.cache, {
			now = now,
			deltaTime = deltaTime,
			config = if override ~= nil then (override :: any).predict else (context :: any).predictConfig,
			leadTime = (context :: any).predictionLeadTime,
		})
	end

	local targetPosition = if predicted.active == true and typeof(predicted.position) == "Vector3"
		then predicted.position
		else if subject ~= nil and typeof((subject :: any).position) == "Vector3" then (subject :: any).position else nil
	local baseTargetPosition = if subject ~= nil and typeof((subject :: any).position) == "Vector3"
		then (subject :: any).position
		else nil

	local resolvedViewConfig = cloneViewConfig(baseViewConfig)
	if targetPosition ~= nil and override ~= nil and (override :: any).disableRoom ~= true then
		local roomBehavior = (context :: any).roomBehavior
		if typeof(roomBehavior) == "table" and typeof((roomBehavior :: any).resolveViewConfig) == "function" then
			resolvedViewConfig = (roomBehavior :: any):resolveViewConfig(resolvedViewConfig, targetPosition)
		end
	elseif targetPosition ~= nil and override == nil then
		local roomBehavior = (context :: any).roomBehavior
		if typeof(roomBehavior) == "table" and typeof((roomBehavior :: any).resolveViewConfig) == "function" then
			resolvedViewConfig = (roomBehavior :: any):resolveViewConfig(resolvedViewConfig, targetPosition)
		end
	end
	resolvedViewConfig = resolveViewConfig(resolvedViewConfig, override)

	local resolvedSettings = resolveSettings(baseSettings, override)
	local lookPosition = if override ~= nil and typeof((override :: any).lookPosition) == "Vector3"
		then (override :: any).lookPosition
		else if subject ~= nil and typeof((subject :: any).lookPosition) == "Vector3"
			then (subject :: any).lookPosition
			else if targetPosition ~= nil then targetPosition + Vector3.new(0, resolvedViewConfig.lookHeight, 0) else nil

	local fieldOfView = resolvedViewConfig.fieldOfView
	local cameraCFrame = nil :: CFrame?
	local overrideCameraCFrame = if override ~= nil and typeof((override :: any).cameraCFrame) == "CFrame"
		then (override :: any).cameraCFrame
		else nil
	local overrideCameraPosition = if override ~= nil and typeof((override :: any).cameraPosition) == "Vector3"
		then (override :: any).cameraPosition
		else nil

	if overrideCameraCFrame ~= nil then
		cameraCFrame = overrideCameraCFrame
	elseif overrideCameraPosition ~= nil then
		local fallbackLookPosition = if lookPosition ~= nil
			then lookPosition
			else overrideCameraPosition + Vector3.new(-resolvedSettings.sideSign, 0, 0)
		cameraCFrame = CFrame.lookAt(overrideCameraPosition, fallbackLookPosition)
	elseif targetPosition ~= nil and lookPosition ~= nil then
		local velocity = if predicted ~= nil and typeof(predicted.velocity) == "Vector3"
			then predicted.velocity
			else if subject ~= nil and typeof((subject :: any).velocity) == "Vector3" then (subject :: any).velocity else Vector3.zero
		local sidewaysSpeed = math.abs(velocity.Z)
		local speedAlpha = if resolvedSettings.movementSpeedForMaxBack > 0
			then math.clamp(sidewaysSpeed / resolvedSettings.movementSpeedForMaxBack, 0, 1)
			else 0
		local movementBackOffset = resolvedSettings.movementBackAmount * speedAlpha * resolvedSettings.movementBackSign

		local baseCameraPosition =
			targetPosition + Vector3.new(resolvedViewConfig.distance * resolvedSettings.sideSign, resolvedViewConfig.height, 0)
		local cameraToLook = baseCameraPosition - lookPosition
		local backDirection = if cameraToLook.Magnitude > 0
			then cameraToLook.Unit
			else Vector3.new(resolvedSettings.sideSign, 0, 0)
		local cameraPositionWithMovementBack = baseCameraPosition + (backDirection * movementBackOffset)
		local baseCFrame = CFrame.lookAt(baseCameraPosition, lookPosition)

		local mouseNormalized = if typeof((context :: any).mouseNormalized) == "Vector2"
			then (context :: any).mouseNormalized
			else Vector2.zero
		local mouseOffset = (baseCFrame.RightVector * (mouseNormalized.X * resolvedSettings.mouseInfluenceX))
			+ (baseCFrame.UpVector * (-mouseNormalized.Y * resolvedSettings.mouseInfluenceY))
		local cameraPosition = cameraPositionWithMovementBack + mouseOffset
		local finalLookPosition = lookPosition + mouseOffset
		cameraCFrame = CFrame.lookAt(cameraPosition, finalLookPosition)
		lookPosition = finalLookPosition
	end

	local stateSnapshot = {}
	if typeof(self.state) == "table" and typeof((self.state :: any).resolve) == "function" then
		stateSnapshot = (self.state :: any):resolve({
			target = subject,
			override = override,
			now = now,
		})
	end

	if subject ~= nil and typeof(self.cache) == "table" and typeof((self.cache :: any).rememberSubject) == "function" then
		(self.cache :: any):rememberSubject(
			(subject :: any).cacheKey,
			(subject :: any).kind,
			(subject :: any).position,
			(subject :: any).velocity,
			now
		)
	end

	if typeof(self.cache) == "table" and typeof((self.cache :: any).storeFrame) == "function" then
		(self.cache :: any):storeFrame({
			updatedAt = now,
			deltaTime = deltaTime,
			mode = (stateSnapshot :: any).mode,
			reason = (stateSnapshot :: any).reason,
			subjectKey = if subject ~= nil then (subject :: any).cacheKey else nil,
			subjectKind = if subject ~= nil then (subject :: any).kind else nil,
			targetPosition = baseTargetPosition,
			predictedPosition = if predicted.active == true then targetPosition else nil,
			cameraCFrame = cameraCFrame,
			fieldOfView = fieldOfView,
			hasOverride = override ~= nil,
		})
	end

	return {
		state = stateSnapshot,
		override = override,
		subject = subject,
		predicted = predicted,
		targetPosition = targetPosition,
		baseTargetPosition = baseTargetPosition,
		lookPosition = lookPosition,
		viewConfig = resolvedViewConfig,
		settings = resolvedSettings,
		cameraCFrame = cameraCFrame,
		fieldOfView = fieldOfView,
	}
end

Resolve.new = Resolve.New
Resolve.resolve = Resolve.Resolve

return Resolve
