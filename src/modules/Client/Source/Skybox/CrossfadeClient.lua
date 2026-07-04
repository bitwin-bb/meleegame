local require = require(script.Parent.loader).load(script)

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CrossfadeShared = require("CrossfadeShared")
local Fusion: any = require(ReplicatedStorage.Packages.Fusion)
local Maid = require("Maid")
local Promise: any = require("Promise")

type MaidClass = any

local CrossfadeClient = {}

local Children = Fusion.Children

local runtime = {
	fadeMaid = nil :: MaidClass?,
	fadeId = 0,
}

local SKYBOX_NORMALS = {
	Enum.NormalId.Top,
	Enum.NormalId.Bottom,
	Enum.NormalId.Right,
	Enum.NormalId.Left,
	Enum.NormalId.Front,
	Enum.NormalId.Back,
}

local SKY_PROPERTIES = {
	"CelestialBodiesShown",
	"MoonAngularSize",
	"MoonTextureId",
	"SkyboxBk",
	"SkyboxDn",
	"SkyboxFt",
	"SkyboxLf",
	"SkyboxRt",
	"SkyboxUp",
	"SkyboxOrientation",
	"StarCount",
	"SunAngularSize",
	"SunTextureId",
}

local function copyPropertyIfPossible(source: Instance, target: Instance, propertyName: string)
	local okRead, value = pcall(function()
		return (source :: any)[propertyName]
	end)
	if not okRead then
		return
	end

	pcall(function()
		(target :: any)[propertyName] = value
	end)
end

local function GetSkySource(skyRaw: any): Sky?
	if typeof(skyRaw) == "Instance" and skyRaw:IsA("Sky") then
		return skyRaw
	end

	local sky = Lighting:FindFirstChildWhichIsA("Sky")
	if sky ~= nil then
		return sky
	end

	return nil
end

local function createSkySnapshot(scope: any, skyRaw: any): Sky
	local source = GetSkySource(skyRaw)
	local sky = (scope:New("Sky"))({
		Name = "SkyboxCrossfadeSky",
	})

	if source ~= nil then
		for _, propertyName in SKY_PROPERTIES do
			copyPropertyIfPossible(source, sky, propertyName)
		end
	else
		for propertyName, image in CrossfadeShared.DEFAULT_SKYBOX_IMAGE_MAP do
			(sky :: any)[propertyName] = image
		end
	end

	return sky
end

local function getSkyImage(sky: Sky, normal: Enum.NormalId): string
	local propertyName = CrossfadeShared.SKYBOX_PROPERTY_IMAGE_MAP[normal]
	if propertyName == nil then
		return ""
	end

	local ok, value = pcall(function()
		return (sky :: any)[propertyName]
	end)
	if not ok or typeof(value) ~= "string" then
		return ""
	end
	return value
end

local function GetSkyboxOrientation(sky: Sky): CFrame
	local orientation = sky.SkyboxOrientation
	return CFrame.Angles(0, math.rad(orientation.Y), 0)
		* CFrame.Angles(math.rad(orientation.X), 0, math.rad(orientation.Z))
end

local function GetFaceOffset(normal: Enum.NormalId): CFrame
	local direction = Vector3.FromNormalId(normal)
	local offset = direction * CrossfadeShared.SKYBOX_DEPTH / 2
	local relativeOffset = CFrame.new(direction * (CrossfadeShared.SKYBOX_WIDTH / 2) + offset)
		* CFrame.new(Vector3.zero, -direction)

	if normal == Enum.NormalId.Bottom then
		relativeOffset *= CFrame.Angles(0, 0, math.pi)
	end

	return relativeOffset
end

local function createSkyboxFace(
	scope: any,
	folder: Folder,
	sky: Sky,
	normal: Enum.NormalId,
	imageTransparency: any
): (any?, CFrame?)
	local image = getSkyImage(sky, normal)
	if image == "" then
		return nil, nil
	end

	local cframeValue = scope:Value(CFrame.identity)
	local newPart = scope:New("Part")
	local newSurfaceGui = scope:New("SurfaceGui")
	local newImageLabel = scope:New("ImageLabel")

	newPart({
		Name = `{normal.Name}SkyboxCrossfadeFace`,
		Anchored = true,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Size = Vector3.new(CrossfadeShared.SKYBOX_WIDTH, CrossfadeShared.SKYBOX_WIDTH, CrossfadeShared.SKYBOX_DEPTH),
		CFrame = cframeValue,
		Parent = folder,

		[Children] = {
			newSurfaceGui({
				Name = "SkyboxCrossfadeSurface",
				AlwaysOnTop = false,
				AutoLocalize = false,
				Brightness = 1,
				CanvasSize = CrossfadeShared.CANVAS_SIZE,
				Face = Enum.NormalId.Front,
				LightInfluence = 0,
				SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,

				[Children] = {
					newImageLabel({
						Name = "SkyboxCrossfadeImage",
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Image = image,
						ImageTransparency = imageTransparency,
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(1, 1),
					}),
				},
			}),
		},
	})

	return cframeValue, GetFaceOffset(normal)
end

local function cleanupFade()
	if runtime.fadeMaid ~= nil then
		runtime.fadeMaid:Destroy()
		runtime.fadeMaid = nil
	end
end

function CrossfadeClient.PlaySkyCrossfade(
	_self: any,
	fromSkyRaw: any,
	_fromAtmosphereRaw: any,
	transitionSecondsRaw: any
): boolean
	local transitionSeconds = CrossfadeShared.GetTransitionSeconds(transitionSecondsRaw)
	if transitionSeconds < CrossfadeShared.MIN_TRANSITION_SECONDS then
		return false
	end

	local camera = Workspace.CurrentCamera
	if camera == nil then
		return false
	end

	cleanupFade()
	runtime.fadeId += 1
	local fadeId = runtime.fadeId

	local maid = Maid.new()
	runtime.fadeMaid = maid
	local scope = Fusion.scoped(Fusion)
	maid:GiveTask(function()
		Fusion.doCleanup(scope)
	end)

	local sky = createSkySnapshot(scope, fromSkyRaw)
	local folderParent = scope:Value(camera)
	local folder = (scope:New("Folder"))({
		Name = CrossfadeShared.CROSSFADE_GUI_NAME,
		Parent = folderParent,
	})
	local orientation = GetSkyboxOrientation(sky)
	local faceCFrames = {}
	local faceOffsets = {}
	local transparencyTarget = scope:Value(0)
	local imageTransparency = scope:Tween(
		transparencyTarget,
		TweenInfo.new(transitionSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	)

	for _, normal in SKYBOX_NORMALS do
		local faceCFrame, faceOffset = createSkyboxFace(scope, folder, sky, normal, imageTransparency)
		if faceCFrame ~= nil and faceOffset ~= nil then
			table.insert(faceCFrames, faceCFrame)
			table.insert(faceOffsets, faceOffset)
		end
	end

	if #faceCFrames <= 0 then
		cleanupFade()
		return false
	end

	local function updateFaces()
		local activeCamera = Workspace.CurrentCamera
		if activeCamera == nil then
			return
		end
		if Fusion.peek(folderParent) ~= activeCamera then
			folderParent:set(activeCamera)
		end

		local baseCFrame = CFrame.new(activeCamera.CFrame.Position) * orientation
		for index, faceCFrame in faceCFrames do
			faceCFrame:set(baseCFrame * faceOffsets[index])
		end
	end

	updateFaces()
	maid:GiveTask(RunService.RenderStepped:Connect(updateFaces))
	transparencyTarget:set(1)

	maid:GivePromise(Promise.delay(CrossfadeShared.GetCleanupDelaySeconds(transitionSeconds), function(fulfill)
		if runtime.fadeId == fadeId then
			cleanupFade()
		end
		fulfill(true)
	end))

	return true
end

function CrossfadeClient.Cleanup(_self: any)
	cleanupFade()
end
return CrossfadeClient
