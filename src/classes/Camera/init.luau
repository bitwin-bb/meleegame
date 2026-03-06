local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SideView = require(script.SideView)
local Configs = require(ReplicatedStorage.Shared.Modules.Core.Configs)

local Camera = {}
Camera.__index = Camera

export type SideViewNewConfig = {
	config: SideView.SideViewConfig?,
	target: BasePart?,
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

	return merged
end

function Camera.new(config: CameraNewConfig?): Camera
	local sideViewNewConfig = if config then config.SideView else nil
	local sideViewBaseConfig = Configs.cameraData :: SideView.SideViewConfig
	local sideViewConfig =
		mergeSideViewConfig(sideViewBaseConfig, if sideViewNewConfig then sideViewNewConfig.config else nil)
	local sideView = SideView.new(sideViewConfig)

	if sideViewNewConfig and sideViewNewConfig.target then
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

function Camera.init(self: Camera) end

function Camera.useSideView(
	self: Camera,
	target: BasePart,
	config: SideView.SideViewConfig?,
	snapToTarget: boolean?
): SideView.SideView
	self.SideView:init(target, config, {
		snapToTarget = if snapToTarget ~= nil then snapToTarget else not self.SideView.enabled,
	})
	return self.SideView
end

function Camera.configureSideView(self: Camera, config: SideView.SideViewConfig): SideView.SideView
	self.SideView:applyConfig(config)
	return self.SideView
end

function Camera.disableSideView(self: Camera)
	self.SideView:disable()
end

function Camera.destroy(self: Camera)
	self.SideView:destroy()
end

return Camera
