--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)

local CloudServiceUtils = {}

export type ServiceState = {
	initialized: boolean,
	activeCloudCount: number,
	pooledCloudCount: number,
}

export type CloudAssetDefinition = {
	id: string,
	image: string,
	imageAspectRatio: number,
	tint: Color3,
}

export type CloudView = {
	id: string,
	image: string,
	imageColor: Color3,
	imageTransparency: number,
	position: UDim2,
	size: UDim2,
	zIndex: number,
}

export type CloudSurfaceState = {
	visible: boolean,
	adornee: BasePart?,
	face: Enum.NormalId,
	brightness: number,
	canvasSize: Vector2,
	clouds: { CloudView },
}

local DEFAULT_SERVICE_STATE: ServiceState = {
	initialized = false,
	activeCloudCount = 0,
	pooledCloudCount = 0,
}

local DEFAULT_SURFACE_STATE: CloudSurfaceState = {
	visible = false,
	adornee = nil,
	face = Enum.NormalId.Right,
	brightness = 0.5,
	canvasSize = Vector2.new(1, 1),
	clouds = {},
}

local serviceStateAtom: Charm.Atom<ServiceState> = Charm.atom(DEFAULT_SERVICE_STATE)
local surfaceStateAtom: Charm.Atom<CloudSurfaceState> = Charm.atom(DEFAULT_SURFACE_STATE)

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw and valueRaw ~= math.huge and valueRaw ~= -math.huge then
		value = valueRaw
	end
	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function sanitizeImage(valueRaw: any): string
	local image = trim(valueRaw)
	while string.find(image, "rbxassetid://rbxassetid://", 1, true) ~= nil do
		image = string.gsub(image, "rbxassetid://rbxassetid://", "rbxassetid://")
	end
	return image
end

local function collectSortedNumericKeys(source: { [any]: any }): { number }
	local keys = {}
	for key in source do
		if typeof(key) == "number" and key % 1 == 0 then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	return keys
end

local function appendAssetDefinition(
	output: { CloudAssetDefinition },
	sourceRaw: any,
	fallbackId: string,
	seen: { [string]: boolean }
)
	if typeof(sourceRaw) == "string" then
		local image = sanitizeImage(sourceRaw)
		if image == "" or seen[image] then
			return
		end
		seen[image] = true
		table.insert(output, {
			id = fallbackId,
			image = image,
			imageAspectRatio = 2.75,
			tint = Color3.new(1, 1, 1),
		})
		return
	end

	if typeof(sourceRaw) ~= "table" then
		return
	end

	local source = sourceRaw :: { [any]: any }
	local image = sanitizeImage(source.image or source.asset)
	if image ~= "" then
		if seen[image] then
			return
		end
		seen[image] = true
		table.insert(output, {
			id = trim(source.id) ~= "" and trim(source.id) or fallbackId,
			image = image,
			imageAspectRatio = sanitizeNumber(source.imageAspectRatio or source.aspectRatio, 2.75, 0.1, 32),
			tint = if typeof(source.tint) == "Color3" then source.tint else Color3.new(1, 1, 1),
		})
		return
	end

	for _, key in collectSortedNumericKeys(source) do
		appendAssetDefinition(output, source[key], `{fallbackId}_{key}`, seen)
	end
end

local function cloneCloudView(view: CloudView): CloudView
	return {
		id = view.id,
		image = view.image,
		imageColor = view.imageColor,
		imageTransparency = view.imageTransparency,
		position = view.position,
		size = view.size,
		zIndex = view.zIndex,
	}
end

local function cloneSurfaceState(state: CloudSurfaceState): CloudSurfaceState
	local clouds = table.create(#state.clouds)
	for index, cloud in state.clouds do
		clouds[index] = cloneCloudView(cloud)
	end

	return {
		visible = state.visible,
		adornee = state.adornee,
		face = state.face,
		brightness = state.brightness,
		canvasSize = state.canvasSize,
		clouds = clouds,
	}
end

local function cloneServiceState(state: ServiceState): ServiceState
	return {
		initialized = state.initialized,
		activeCloudCount = state.activeCloudCount,
		pooledCloudCount = state.pooledCloudCount,
	}
end

function CloudServiceUtils.NormalizeAssetDefinitions(rawAssets: any): { CloudAssetDefinition }
	local output: { CloudAssetDefinition } = {}
	local seen: { [string]: boolean } = {}
	appendAssetDefinition(output, rawAssets, "Cloud", seen)
	return output
end

function CloudServiceUtils.CollectAssetIds(assets: { CloudAssetDefinition }): { string }
	local assetIds = table.create(#assets)
	for _, asset in assets do
		if asset.image ~= "" then
			table.insert(assetIds, asset.image)
		end
	end
	return assetIds
end

function CloudServiceUtils.GetSurfaceState(): CloudSurfaceState
	return cloneSurfaceState(surfaceStateAtom())
end

function CloudServiceUtils.SetSurfaceState(stateRaw: CloudSurfaceState)
	surfaceStateAtom(cloneSurfaceState(stateRaw))
end

function CloudServiceUtils.ClearSurfaceState()
	surfaceStateAtom(cloneSurfaceState(DEFAULT_SURFACE_STATE))
end

function CloudServiceUtils.GetServiceState(): ServiceState
	return cloneServiceState(serviceStateAtom())
end

function CloudServiceUtils.SetServiceState(stateRaw: ServiceState)
	serviceStateAtom(cloneServiceState(stateRaw))
end

function CloudServiceUtils.ClearServiceState()
	serviceStateAtom(cloneServiceState(DEFAULT_SERVICE_STATE))
end

CloudServiceUtils.serviceStateAtom = serviceStateAtom
CloudServiceUtils.surfaceStateAtom = surfaceStateAtom
CloudServiceUtils.normalizeAssetDefinitions = CloudServiceUtils.NormalizeAssetDefinitions
CloudServiceUtils.collectAssetIds = CloudServiceUtils.CollectAssetIds
CloudServiceUtils.getSurfaceState = CloudServiceUtils.GetSurfaceState
CloudServiceUtils.setSurfaceState = CloudServiceUtils.SetSurfaceState
CloudServiceUtils.clearSurfaceState = CloudServiceUtils.ClearSurfaceState
CloudServiceUtils.getServiceState = CloudServiceUtils.GetServiceState
CloudServiceUtils.setServiceState = CloudServiceUtils.SetServiceState
CloudServiceUtils.clearServiceState = CloudServiceUtils.ClearServiceState

return CloudServiceUtils
