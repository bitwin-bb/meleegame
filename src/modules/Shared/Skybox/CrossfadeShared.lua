local require = require(script.Parent.loader).load(script)

local Math = require("Math")

local CrossfadeShared = {}

CrossfadeShared.CROSSFADE_GUI_NAME = "SkyboxCrossfade"
CrossfadeShared.MIN_TRANSITION_SECONDS = 0.05
CrossfadeShared.MAX_TRANSITION_SECONDS = 20
CrossfadeShared.CLEANUP_BUFFER_SECONDS = 0.75
CrossfadeShared.SKYBOX_WIDTH = 2000
CrossfadeShared.SKYBOX_DEPTH = 1
CrossfadeShared.CANVAS_SIZE = Vector2.new(512, 512)

local DEFAULT_TRANSITION_SECONDS = 0

CrossfadeShared.SKYBOX_PROPERTY_IMAGE_MAP = table.freeze({
	[Enum.NormalId.Top] = "SkyboxUp",
	[Enum.NormalId.Bottom] = "SkyboxDn",
	[Enum.NormalId.Right] = "SkyboxLf",
	[Enum.NormalId.Left] = "SkyboxRt",
	[Enum.NormalId.Front] = "SkyboxFt",
	[Enum.NormalId.Back] = "SkyboxBk",
})

CrossfadeShared.DEFAULT_SKYBOX_IMAGE_MAP = table.freeze({
	SkyboxUp = "rbxasset://textures/sky/sky512_up.tex",
	SkyboxDn = "rbxasset://textures/sky/sky512_dn.tex",
	SkyboxLf = "rbxasset://textures/sky/sky512_lf.tex",
	SkyboxRt = "rbxasset://textures/sky/sky512_rt.tex",
	SkyboxFt = "rbxasset://textures/sky/sky512_ft.tex",
	SkyboxBk = "rbxasset://textures/sky/sky512_bk.tex",
})

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and not Math.isNaN(valueRaw) and Math.isFinite(valueRaw) then
		value = valueRaw
	end
	if minimum ~= nil then
		value = math.max(value, minimum)
	end
	if maximum ~= nil then
		value = math.min(value, maximum)
	end
	return value
end

function CrossfadeShared.ResolveTransitionSeconds(transitionSecondsRaw: any): number
	return sanitizeNumber(transitionSecondsRaw, DEFAULT_TRANSITION_SECONDS, 0, CrossfadeShared.MAX_TRANSITION_SECONDS)
end

function CrossfadeShared.ResolveCleanupDelaySeconds(transitionSecondsRaw: any): number
	return CrossfadeShared.ResolveTransitionSeconds(transitionSecondsRaw) + CrossfadeShared.CLEANUP_BUFFER_SECONDS
end

CrossfadeShared.resolveTransitionSeconds = CrossfadeShared.ResolveTransitionSeconds
CrossfadeShared.resolveCleanupDelaySeconds = CrossfadeShared.ResolveCleanupDelaySeconds

return CrossfadeShared
