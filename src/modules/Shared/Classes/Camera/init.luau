local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SideView = require(script.SideView)
local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)

local Camera = {}
Camera.__index = Camera

export type SideViewNewConfig = {
	config: SideView.SideViewConfig?,
	target: any?,
	character: Model?,
	autoEnable: boolean?,
	snapToTargetOnInit: boolean?,
}

export type CameraNewConfig = {
	SideView: SideViewNewConfig?,
}

export type Camera = typeof(setmetatable(
	{} :: {
		SideView: SideView.SideView,
	},
	Camera
))

local function mergeNestedTable(
	merged: SideView.SideViewConfig,
	base: SideView.SideViewConfig?,
	override: SideView.SideViewConfig?,
	key: string
)
	local baseValue = if base then (base :: any)[key] else nil
	local overrideValue = if override then (override :: any)[key] else nil
	if typeof(baseValue) ~= "table" and typeof(overrideValue) ~= "table" then
		return
	end

	(merged :: any)[key] = {}
	if typeof(baseValue) == "table" then
		for nestedKey, nestedValue in baseValue do
			((merged :: any)[key] :: any)[nestedKey] = nestedValue
		end
	end
	if typeof(overrideValue) == "table" then
		for nestedKey, nestedValue in overrideValue do
			((merged :: any)[key] :: any)[nestedKey] = nestedValue
		end
	end
end

local function mergeSideViewConfig(
	base: SideView.SideViewConfig?,
	override: SideView.SideViewConfig?
): SideView.SideViewConfig
	local merged: SideView.SideViewConfig = {}

	if base then
		for key, value in base do
			(merged :: any)[key] = value
		end
	end

	if override then
		for key, value in override do
			(merged :: any)[key] = value
		end
	end

	if base and base.cameraSpring then
		merged.cameraSpring = {}
		for key, value in base.cameraSpring do
			(merged.cameraSpring :: any)[key] = value
		end
	end
	if override and override.cameraSpring then
		if not merged.cameraSpring then
			merged.cameraSpring = {}
		end
		for key, value in override.cameraSpring do
			(merged.cameraSpring :: any)[key] = value
		end
	end

	if base and base.fovSpring then
		merged.fovSpring = {}
		for key, value in base.fovSpring do
			(merged.fovSpring :: any)[key] = value
		end
	end
	if override and override.fovSpring then
		if not merged.fovSpring then
			merged.fovSpring = {}
		end
		for key, value in override.fovSpring do
			(merged.fovSpring :: any)[key] = value
		end
	end

	mergeNestedTable(merged, base, override, "room")
	mergeNestedTable(merged, base, override, "catchUpPlayer")
	mergeNestedTable(merged, base, override, "predict")

	return merged
end

function Camera.New(config: CameraNewConfig?): Camera
	local sideViewNewConfig = if config then config.SideView else nil
	local sideViewBaseConfig = Configs.cameraData :: SideView.SideViewConfig
	local sideViewConfig =
		mergeSideViewConfig(sideViewBaseConfig, if sideViewNewConfig then sideViewNewConfig.config else nil)
	local sideView = SideView.new(sideViewConfig)

	if sideViewNewConfig and sideViewNewConfig.character then
		sideView:setCharacter(sideViewNewConfig.character)
	end

	if sideViewNewConfig and sideViewNewConfig.target ~= nil then
		if sideViewNewConfig.autoEnable == false then
			sideView:setTarget(sideViewNewConfig.target)
		else
			sideView:init(sideViewNewConfig.target, nil, {
				snapToTarget = if sideViewNewConfig.snapToTargetOnInit ~= nil
					then sideViewNewConfig.snapToTargetOnInit
					else true,
			})
		end
	end

	return setmetatable({
		SideView = sideView,
	}, Camera)
end

function Camera.Init(self: Camera) end

function Camera.UseSideView(
	self: Camera,
	target: any?,
	config: SideView.SideViewConfig?,
	snapToTarget: boolean?
): SideView.SideView
	self.SideView:init(target, config, {
		snapToTarget = if snapToTarget ~= nil then snapToTarget else not self.SideView.enabled,
	})
	return self.SideView
end

function Camera.ConfigureSideView(self: Camera, config: SideView.SideViewConfig): SideView.SideView
	self.SideView:applyConfig(config)
	return self.SideView
end

function Camera.SetSideViewCharacter(self: Camera, character: Model?)
	self.SideView:setCharacter(character)
	return self.SideView
end

function Camera.PushSideViewOverride(self: Camera, overrideRaw: any): number
	return self.SideView:pushOverride(overrideRaw)
end

function Camera.UpdateSideViewOverride(self: Camera, idRaw: any, patchRaw: any): boolean
	return self.SideView:updateOverride(idRaw, patchRaw)
end

function Camera.RemoveSideViewOverride(self: Camera, idRaw: any): boolean
	return self.SideView:removeOverride(idRaw)
end

function Camera.ClearSideViewOverrides(self: Camera)
	self.SideView:clearOverrides()
	return self.SideView
end

function Camera.SetTemporarySideViewTarget(self: Camera, targetRaw: any?, durationSecondsRaw: any?)
	self.SideView:setTemporaryTargetOverride(targetRaw, durationSecondsRaw)
	return self.SideView
end

function Camera.ClearTemporarySideViewTarget(self: Camera)
	self.SideView:clearTemporaryTargetOverride()
	return self.SideView
end

function Camera.GetSideViewBackendState(self: Camera): { [string]: any }
	return self.SideView:getBackendState()
end

function Camera.DisableSideView(self: Camera)
	self.SideView:disable()
end

function Camera.Destroy(self: Camera)
	self.SideView:destroy()
end

Camera.new = Camera.New
Camera.init = Camera.Init
Camera.useSideView = Camera.UseSideView
Camera.configureSideView = Camera.ConfigureSideView
Camera.setSideViewCharacter = Camera.SetSideViewCharacter
Camera.pushSideViewOverride = Camera.PushSideViewOverride
Camera.updateSideViewOverride = Camera.UpdateSideViewOverride
Camera.removeSideViewOverride = Camera.RemoveSideViewOverride
Camera.clearSideViewOverrides = Camera.ClearSideViewOverrides
Camera.setTemporarySideViewTarget = Camera.SetTemporarySideViewTarget
Camera.clearTemporarySideViewTarget = Camera.ClearTemporarySideViewTarget
Camera.getSideViewBackendState = Camera.GetSideViewBackendState
Camera.disableSideView = Camera.DisableSideView
Camera.destroy = Camera.Destroy

return Camera
