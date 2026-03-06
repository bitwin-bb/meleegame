--!strict

local HapticService = game:GetService("HapticService")
local UserInputService = game:GetService("UserInputService")

local Haptics = {}
Haptics.__index = Haptics

export type PulseConfig = {
	inputType: Enum.UserInputType?,
	large: number?,
	small: number?,
	duration: number?,
	intensityScale: number?,
	durationScale: number?,
}

export type HapticsConfig = {
	eventBus: any?,
	eventChannel: string?,
	tickScheduler: any?,
	enabled: boolean?,
}

export type Haptics = typeof(setmetatable({} :: any, Haptics))

local PATTERN_BY_KEY = {
	selection = {
		large = 0.12,
		small = 0.18,
		duration = 0.045,
	},
	confirm = {
		large = 0.22,
		small = 0.3,
		duration = 0.08,
	},
	warning = {
		large = 0.38,
		small = 0.18,
		duration = 0.1,
	},
	["error"] = {
		large = 0.5,
		small = 0.35,
		duration = 0.12,
	},
	impactLight = {
		large = 0.25,
		small = 0.14,
		duration = 0.06,
	},
	impactHeavy = {
		large = 0.55,
		small = 0.28,
		duration = 0.1,
	},
}

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

local function normalizeEventName(valueRaw: any, fallback: string): string
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end
	return fallback
end

local function resolveInputType(inputTypeRaw: any): Enum.UserInputType
	if typeof(inputTypeRaw) == "EnumItem" and string.sub((inputTypeRaw :: Enum.UserInputType).Name, 1, 7) == "Gamepad" then
		return inputTypeRaw
	end

	local ok, connected = pcall(function()
		return UserInputService:GetConnectedGamepads()
	end)
	if ok and typeof(connected) == "table" then
		for _, gamepadInputType in connected do
			if typeof(gamepadInputType) == "EnumItem" then
				return gamepadInputType :: Enum.UserInputType
			end
		end
	end
	return Enum.UserInputType.Gamepad1
end

function Haptics.new(configRaw: HapticsConfig?): Haptics
	local config = if typeof(configRaw) == "table" then configRaw else {}
	local self = setmetatable({
		eventBus = config.eventBus,
		eventChannel = normalizeEventName(config.eventChannel, "haptics"),
		tickScheduler = config.tickScheduler,
		enabled = if config.enabled == nil then true else config.enabled == true,
		activeStopByInput = {} :: { [string]: () -> () },
		isInitialized = false,
	}, Haptics)
	return self
end

function Haptics._setMotor(self: Haptics, inputType: Enum.UserInputType, motor: Enum.VibrationMotor, valueRaw: any)
	local value = clampNumber(valueRaw, 0, 0, 1)
	local okSupport, supported = pcall(function()
		return HapticService:IsVibrationSupported(inputType) and HapticService:IsMotorSupported(inputType, motor)
	end)
	if not okSupport or not supported then
		return
	end
	pcall(function()
		HapticService:SetMotor(inputType, motor, value)
	end)
end

function Haptics._stop(self: Haptics, inputType: Enum.UserInputType)
	self:_setMotor(inputType, Enum.VibrationMotor.Large, 0)
	self:_setMotor(inputType, Enum.VibrationMotor.Small, 0)
end

function Haptics._cancelPending(self: Haptics, inputType: Enum.UserInputType)
	local key = inputType.Name
	local cancel = self.activeStopByInput[key]
	if cancel ~= nil then
		cancel()
		self.activeStopByInput[key] = nil
	end
end

function Haptics.pulse(self: Haptics, patternRaw: any, configRaw: PulseConfig?): boolean
	if not self.enabled then
		return false
	end

	local config = if typeof(configRaw) == "table" then configRaw else {}
	local pattern = if typeof(patternRaw) == "table" then patternRaw else PATTERN_BY_KEY[if typeof(patternRaw) == "string" then patternRaw else "selection"]
	if typeof(pattern) ~= "table" then
		return false
	end

	local inputType = resolveInputType(config.inputType)
	local intensityScale = clampNumber(config.intensityScale, 1, 0, 4)
	local durationScale = clampNumber(config.durationScale, 1, 0, 4)
	local large = clampNumber(config.large, if typeof(pattern.large) == "number" then pattern.large else 0.2, 0, 1) * intensityScale
	local small = clampNumber(config.small, if typeof(pattern.small) == "number" then pattern.small else 0.2, 0, 1) * intensityScale
	local duration = clampNumber(config.duration, if typeof(pattern.duration) == "number" then pattern.duration else 0.06, 0.01, 2) * durationScale

	self:_cancelPending(inputType)
	self:_setMotor(inputType, Enum.VibrationMotor.Large, large)
	self:_setMotor(inputType, Enum.VibrationMotor.Small, small)

	local cancelled = false
	local function stopPulse()
		if cancelled then
			return
		end
		cancelled = true
		self:_stop(inputType)
		self.activeStopByInput[inputType.Name] = nil
	end

	if self.tickScheduler ~= nil and typeof((self.tickScheduler :: any).schedule) == "function" then
		local token = (self.tickScheduler :: any):schedule(function()
			stopPulse()
		end, duration, {
			group = "haptics.stop",
			priority = 250,
		})
		self.activeStopByInput[inputType.Name] = function()
			cancelled = true
			if typeof(token.cancel) == "function" then
				token:cancel()
			elseif typeof((self.tickScheduler :: any).cancel) == "function" then
				local schedulerAny = self.tickScheduler :: any
				schedulerAny:cancel(token)
			end
			self:_stop(inputType)
		end
	else
		self.activeStopByInput[inputType.Name] = function()
			cancelled = true
			self:_stop(inputType)
		end
		task.delay(duration, function()
			stopPulse()
		end)
	end

	if self.eventBus ~= nil and typeof((self.eventBus :: any).publish) == "function" then
		local eventBusAny = self.eventBus :: any
		eventBusAny:publish(self.eventChannel, "pulse", {
			inputType = inputType,
			large = large,
			small = small,
			duration = duration,
		})
	end

	return true
end

function Haptics.selection(self: Haptics): boolean
	return self:pulse("selection")
end

function Haptics.confirm(self: Haptics): boolean
	return self:pulse("confirm")
end

function Haptics.warning(self: Haptics): boolean
	return self:pulse("warning")
end

function Haptics.error(self: Haptics): boolean
	return self:pulse("error")
end

function Haptics.impactLight(self: Haptics): boolean
	return self:pulse("impactLight")
end

function Haptics.impactHeavy(self: Haptics): boolean
	return self:pulse("impactHeavy")
end

function Haptics.setEnabled(self: Haptics, enabledRaw: any)
	self.enabled = enabledRaw == true
	if not self.enabled then
		for inputName, cancel in self.activeStopByInput do
			cancel()
			self.activeStopByInput[inputName] = nil
		end
	end
end

function Haptics.init(self: Haptics)
	self.isInitialized = true
end

function Haptics.destroy(self: Haptics)
	for inputName, cancel in self.activeStopByInput do
		cancel()
		self.activeStopByInput[inputName] = nil
	end
	self.isInitialized = false
end

Haptics.Pulse = Haptics.pulse
Haptics.Selection = Haptics.selection
Haptics.Confirm = Haptics.confirm
Haptics.Warning = Haptics.warning
Haptics.Error = Haptics.error
Haptics.ImpactLight = Haptics.impactLight
Haptics.ImpactHeavy = Haptics.impactHeavy
Haptics.SetEnabled = Haptics.setEnabled
Haptics.Init = Haptics.init
Haptics.Destroy = Haptics.destroy

return Haptics
