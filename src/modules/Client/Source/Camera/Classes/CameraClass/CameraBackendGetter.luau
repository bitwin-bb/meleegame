local require = require(script.Parent.loader).load(script)

local CameraBackendGetter = {}
CameraBackendGetter.__index = CameraBackendGetter

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

export type CameraBackendGetter = typeof(setmetatable(
	{} :: {
		cache: any,
		predictor: any,
		stack: any,
	state: any,
	target: any,
	},
	CameraBackendGetter
))

local function coerceNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then valueRaw else fallback
	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function coerceSign(valueRaw: any, fallback: number): number
	local sign = math.sign(coerceNumber(valueRaw, fallback, -1, 1))
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

local function getViewConfig(baseViewConfig: ViewConfig, overrideRaw: any): ViewConfig
	local override = if typeof(overrideRaw) == "table" then overrideRaw else {} :: any
	local overrideViewConfig = if typeof((override :: any).viewConfig) == "table"
		then (override :: any).viewConfig
		else nil
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
		nextViewConfig.fieldOfView = coerceNumber((override :: any).fieldOfView, nextViewConfig.fieldOfView, 1, 120)
	elseif typeof((source :: any).fieldOfView) == "number" then
		nextViewConfig.fieldOfView = coerceNumber((source :: any).fieldOfView, nextViewConfig.fieldOfView, 1, 120)
	end

	return nextViewConfig
end

local function getSettings(baseSettings: Settings, overrideRaw: any): Settings
	local override = if typeof(overrideRaw) == "table" then overrideRaw else {} :: any
	local settings = cloneSettings(baseSettings)

	settings.sideSign = coerceSign((override :: any).sideSign, settings.sideSign)

	if typeof((override :: any).movementBackAmount) == "number" then
		settings.movementBackAmount = math.max((override :: any).movementBackAmount, 0)
	end
	if typeof((override :: any).movementSpeedForMaxBack) == "number" then
		settings.movementSpeedForMaxBack = math.max((override :: any).movementSpeedForMaxBack, 0.01)
	end
	if typeof((override :: any).movementBackSign) == "number" then
		settings.movementBackSign = coerceSign((override :: any).movementBackSign, settings.movementBackSign)
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

function CameraBackendGetter.new(dependenciesRaw: any?): CameraBackendGetter
	local dependencies = if typeof(dependenciesRaw) == "table" then dependenciesRaw else {} :: any
	return setmetatable({
		cache = (dependencies :: any).cache,
		predictor = (dependencies :: any).predictor,
		stack = (dependencies :: any).stack,
		state = (dependencies :: any).state,
		target = (dependencies :: any).target,
	}, CameraBackendGetter)
end

function CameraBackendGetter.Get(self: CameraBackendGetter, contextRaw: any): ResolutionResult
	local context = if typeof(contextRaw) == "table" then contextRaw else {} :: any
	local now = coerceNumber((context :: any).now, os.clock(), 0, nil)
	local deltaTime = coerceNumber((context :: any).deltaTime, 1 / 60, 0, 1)

	local baseViewConfig = getViewConfig({
		distance = coerceNumber((context :: any).distance, 38, 0, 4096),
		height = coerceNumber((context :: any).height, 8, -4096, 4096),
		lookHeight = coerceNumber((context :: any).lookHeight, 3, -4096, 4096),
		fieldOfView = coerceNumber((context :: any).fieldOfView, 60, 1, 120),
	}, nil)
	local baseSettings = getSettings({
		sideSign = coerceSign((context :: any).sideSign, 1),
		movementBackAmount = math.max(coerceNumber((context :: any).movementBackAmount, 0, 0, 4096), 0),
		movementSpeedForMaxBack = math.max(
			coerceNumber((context :: any).movementSpeedForMaxBack, 1, 0.01, 4096),
			0.01
		),
		movementBackSign = coerceSign((context :: any).movementBackSign, 1),
		mouseInfluenceX = math.max(coerceNumber((context :: any).mouseInfluenceX, 0, 0, 256), 0),
		mouseInfluenceY = math.max(coerceNumber((context :: any).mouseInfluenceY, 0, 0, 256), 0),
	}, nil)

	local override = nil
	if typeof(self.stack) == "table" and typeof((self.stack :: any).Get) == "function" then
		override = (self.stack :: any):Get(now)
	end

	local subject = nil
	if typeof(self.target) == "table" and typeof((self.target :: any).Get) == "function" then
		subject = (self.target :: any):Get({
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
	if
		subject ~= nil
		and typeof(self.predictor) == "table"
		and typeof((self.predictor :: any).Get) == "function"
	then
		predicted = (self.predictor :: any):Get(subject, self.cache, {
			now = now,
			deltaTime = deltaTime,
			config = if override ~= nil then (override :: any).predict else (context :: any).predictConfig,
			leadTime = (context :: any).predictionLeadTime,
		})
	end

	local targetPosition = if predicted.active == true and typeof(predicted.position) == "Vector3"
		then predicted.position
		else if subject ~= nil and typeof((subject :: any).position) == "Vector3"
			then (subject :: any).position
			else nil
	local baseTargetPosition = if subject ~= nil and typeof((subject :: any).position) == "Vector3"
		then (subject :: any).position
		else nil

	local GotViewConfig = cloneViewConfig(baseViewConfig)
	if targetPosition ~= nil and (override == nil or (override :: any).disableRoom ~= true) then
		local roomBehavior = (context :: any).roomBehavior
		if typeof(roomBehavior) == "table" and typeof((roomBehavior :: any).GetViewConfig) == "function" then
			GotViewConfig = (roomBehavior :: any):GetViewConfig(GotViewConfig, targetPosition)
		end
	end
	GotViewConfig = getViewConfig(GotViewConfig, override)

	local GotSettings = getSettings(baseSettings, override)
	local lookPosition = if override ~= nil and typeof((override :: any).lookPosition) == "Vector3"
		then (override :: any).lookPosition
		else if subject ~= nil and typeof((subject :: any).lookPosition) == "Vector3"
			then (subject :: any).lookPosition
			else if targetPosition ~= nil
				then targetPosition + Vector3.new(0, GotViewConfig.lookHeight, 0)
				else nil

	local fieldOfView = GotViewConfig.fieldOfView
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
			else overrideCameraPosition + Vector3.new(-GotSettings.sideSign, 0, 0)
		cameraCFrame = CFrame.lookAt(overrideCameraPosition, fallbackLookPosition)
	elseif targetPosition ~= nil and lookPosition ~= nil then
		local velocity = if predicted ~= nil and typeof(predicted.velocity) == "Vector3"
			then predicted.velocity
			else if subject ~= nil and typeof((subject :: any).velocity) == "Vector3"
				then (subject :: any).velocity
				else Vector3.zero
		local sidewaysSpeed = math.abs(velocity.Z)
		local speedAlpha = if GotSettings.movementSpeedForMaxBack > 0
			then math.clamp(sidewaysSpeed / GotSettings.movementSpeedForMaxBack, 0, 1)
			else 0
		local movementBackOffset = GotSettings.movementBackAmount * speedAlpha * GotSettings.movementBackSign

		local baseCameraPosition = targetPosition
			+ Vector3.new(GotViewConfig.distance * GotSettings.sideSign, GotViewConfig.height, 0)
		local cameraToLook = baseCameraPosition - lookPosition
		local backDirection = if cameraToLook.Magnitude > 0
			then cameraToLook.Unit
			else Vector3.new(GotSettings.sideSign, 0, 0)
		local cameraPositionWithMovementBack = baseCameraPosition + (backDirection * movementBackOffset)
		local baseCFrame = CFrame.lookAt(baseCameraPosition, lookPosition)

		local mouseNormalized = if typeof((context :: any).mouseNormalized) == "Vector2"
			then (context :: any).mouseNormalized
			else Vector2.zero
		local mouseOffset = (baseCFrame.RightVector * (mouseNormalized.X * GotSettings.mouseInfluenceX))
			+ (baseCFrame.UpVector * (-mouseNormalized.Y * GotSettings.mouseInfluenceY))
		local cameraPosition = cameraPositionWithMovementBack + mouseOffset
		local finalLookPosition = lookPosition + mouseOffset
		cameraCFrame = CFrame.lookAt(cameraPosition, finalLookPosition)
		lookPosition = finalLookPosition
	end

	local stateSnapshot = {}
	if typeof(self.state) == "table" and typeof((self.state :: any).Get) == "function" then
		stateSnapshot = (self.state :: any):Get({
			target = subject,
			override = override,
			now = now,
		})
	end

	if
		subject ~= nil
		and typeof(self.cache) == "table"
		and typeof((self.cache :: any).RememberSubject) == "function"
	then
		(self.cache :: any):RememberSubject(
			(subject :: any).cacheKey,
			(subject :: any).kind,
			(subject :: any).position,
			(subject :: any).velocity,
			now
		)
	end

	if typeof(self.cache) == "table" and typeof((self.cache :: any).StoreFrame) == "function" then
		(self.cache :: any):StoreFrame({
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
		viewConfig = GotViewConfig,
		settings = GotSettings,
		cameraCFrame = cameraCFrame,
		fieldOfView = fieldOfView,
	}
end


return CameraBackendGetter
