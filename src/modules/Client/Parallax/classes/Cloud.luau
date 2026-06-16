local require = require(script.Parent.loader).load(script)

local Maid = require("Maid")
local Rx = require("Rx")
local RxSignal = require("RxSignal")
local Signal = require("Signal")

local CloudScroll = require("CloudScroll")
local CloudServiceUtils = require("CloudServiceUtils")

type CloudAssetDefinition = CloudServiceUtils.CloudAssetDefinition

type MaidClass = {
	GiveTask: (self: MaidClass, task: any) -> any,
	DoCleaning: (self: MaidClass) -> (),
	Destroy: (self: MaidClass) -> (),
}
type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> any,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}
type ObservableObject = {
	Subscribe: (
		self: ObservableObject,
		fireCallback: ((...any) -> ())?,
		failCallback: ((...any) -> ())?,
		completeCallback: ((...any) -> ())?
	) -> any,
	Pipe: (self: ObservableObject, transformers: { any }) -> ObservableObject,
}
type RxSignalObject = {
	Connect: (self: RxSignalObject, callback: (...any) -> ()) -> any,
	Once: (self: RxSignalObject, callback: (...any) -> ()) -> any,
	Wait: (self: RxSignalObject) -> ...any,
}

export type CloudPhase = "Inactive" | "FadingIn" | "Visible" | "FadingOut"

export type CloudConfig = {
	id: string,
	asset: CloudAssetDefinition,
	scale: number,
	baseOffsetZ: number,
	verticalAlpha: number,
	spawnCameraZ: number,
	windSpeed: number,
	fadeSeconds: number,
	minScale: number,
	maxScale: number,
	minDepthFactor: number,
	maxDepthFactor: number,
}

local Cloud = {}
Cloud.__index = Cloud

export type Cloud = typeof(setmetatable(
	{} :: {
		maid: MaidClass,
		id: string,
		asset: CloudAssetDefinition?,
		scale: number,
		depthFactor: number,
		baseOffsetZ: number,
		currentOffsetZ: number,
		verticalAlpha: number,
		spawnCameraZ: number,
		windSpeed: number,
		spawnedAt: number,
		alpha: number,
		startAlpha: number,
		fadeSeconds: number,
		phaseStartedAt: number,
		phase: CloudPhase,
		_phaseChangedSignal: SignalObject,
		phaseChangedSignal: RxSignalObject,
		phaseObservable: ObservableObject?,
	},
	Cloud
))

local function setPhase(self: Cloud, nextPhase: CloudPhase)
	if self.phase == nextPhase then
		return
	end
	self.phase = nextPhase
	self._phaseChangedSignal:Fire(nextPhase)
end

function Cloud.new(): Cloud
	local self: Cloud = setmetatable({
		maid = Maid.new(),
		id = "",
		asset = nil,
		scale = 1,
		depthFactor = 0,
		baseOffsetZ = 0,
		currentOffsetZ = 0,
		verticalAlpha = 0.5,
		spawnCameraZ = 0,
		windSpeed = 0,
		spawnedAt = 0,
		alpha = 0,
		startAlpha = 0,
		fadeSeconds = 1,
		phaseStartedAt = 0,
		phase = "Inactive" :: CloudPhase,
		_phaseChangedSignal = Signal.new() :: SignalObject,
		phaseChangedSignal = nil :: any,
		phaseObservable = nil,
	}, Cloud) :: any
	self.phaseChangedSignal = RxSignal.new(function(): ObservableObject
		return self:ObservePhase()
	end) :: RxSignalObject
	self.maid:GiveTask(self._phaseChangedSignal)
	return (self :: any) :: Cloud
end

function Cloud.Reset(self: Cloud, config: CloudConfig, now: number)
	self.id = config.id
	self.asset = config.asset
	self.scale = math.max(config.scale, 0.01)
	self.depthFactor = CloudScroll.resolveDepthFactor(
		self.scale,
		config.minScale,
		config.maxScale,
		config.minDepthFactor,
		config.maxDepthFactor
	)
	self.baseOffsetZ = config.baseOffsetZ
	self.currentOffsetZ = config.baseOffsetZ
	self.verticalAlpha = math.clamp(config.verticalAlpha, 0, 1)
	self.spawnCameraZ = config.spawnCameraZ
	self.windSpeed = config.windSpeed
	self.spawnedAt = now
	self.alpha = 0
	self.startAlpha = 0
	self.fadeSeconds = math.max(config.fadeSeconds, 0.001)
	self.phaseStartedAt = now
	setPhase(self, "FadingIn")
end

function Cloud.BeginFadeOut(self: Cloud, now: number)
	if self.phase == "Inactive" or self.phase == "FadingOut" then
		return
	end

	self.startAlpha = self.alpha
	self.phaseStartedAt = now
	setPhase(self, "FadingOut")
end

function Cloud.Step(
	self: Cloud,
	now: number,
	cameraZ: number,
	widthStuds: number,
	retireHalfWidthStuds: number,
	offscreenMarginStuds: number
): boolean
	if self.phase == "Inactive" then
		return false
	end

	local windOffsetZ = (now - self.spawnedAt) * self.windSpeed
	self.currentOffsetZ =
		CloudScroll.computeHorizonOffset(self.baseOffsetZ + windOffsetZ, cameraZ - self.spawnCameraZ, self.depthFactor)

	local progress = math.clamp((now - self.phaseStartedAt) / self.fadeSeconds, 0, 1)
	if self.phase == "FadingIn" then
		self.alpha = progress
		if progress >= 1 then
			self.alpha = 1
			setPhase(self, "Visible")
		end
	elseif self.phase == "FadingOut" then
		self.alpha = self.startAlpha * (1 - progress)
		if progress >= 1 then
			self.alpha = 0
			setPhase(self, "Inactive")
			return false
		end
	else
		self.alpha = 1
	end

	if
		self.phase ~= "FadingOut"
		and CloudScroll.isHorizontallyOffscreen(
			self.currentOffsetZ,
			widthStuds,
			retireHalfWidthStuds,
			offscreenMarginStuds
		)
	then
		self:BeginFadeOut(now)
	end

	return true
end

function Cloud.IsActive(self: Cloud): boolean
	return self.phase ~= "Inactive"
end

function Cloud.IsRetiring(self: Cloud): boolean
	return self.phase == "FadingOut"
end

function Cloud.ObservePhase(self: Cloud): ObservableObject
	if self.phaseObservable == nil then
		self.phaseObservable = Rx.fromSignal(self._phaseChangedSignal):Pipe({
			Rx.startWith({ self.phase }),
			Rx.shareReplay(1),
		}) :: ObservableObject
	end
	return self.phaseObservable :: ObservableObject
end

function Cloud.GetPhaseChangedSignal(self: Cloud): RxSignalObject
	return self.phaseChangedSignal
end

function Cloud.Destroy(self: Cloud)
	setPhase(self, "Inactive")
	self.phaseObservable = nil
	self.maid:DoCleaning()
end

Cloud.reset = Cloud.Reset
Cloud.beginFadeOut = Cloud.BeginFadeOut
Cloud.step = Cloud.Step
Cloud.isActive = Cloud.IsActive
Cloud.isRetiring = Cloud.IsRetiring
Cloud.observePhase = Cloud.ObservePhase
Cloud.getPhaseChangedSignal = Cloud.GetPhaseChangedSignal
Cloud.destroy = Cloud.Destroy

return Cloud
