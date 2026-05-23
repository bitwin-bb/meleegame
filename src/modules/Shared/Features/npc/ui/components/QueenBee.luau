--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = require(loaderUtils.Parent).load(script)

local Flipbook = loader("Flipbook")
local Sprite = loader("Sprite")

local BossServiceUtils = require(script:FindFirstAncestor("game").Shared.Features.npc.BossServiceUtils)
local QueenBeeSpriteSheet = require(script:FindFirstAncestor("game").Shared.Features.npc.modules.QueenBeeSpriteSheet)
local React = require(ReplicatedStorage.Packages.React)
local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Core.WorkspaceFolders)

type BossSnapshot = BossServiceUtils.BossSnapshot

export type QueenBeeProps = {
	snapshot: BossSnapshot,
	renderClock: number,
	surfaceGui: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement
local BOSS_RUNTIME_FOLDER_NAME = "BossRuntime"
local DEFAULT_ROOT_SIZE = Vector3.new(6, 13.5, 18)
local FRAME_COUNT = math.max(1, QueenBeeSpriteSheet.frameCount or (QueenBeeSpriteSheet.columns * QueenBeeSpriteSheet.rows))
local runtimeRootPartCache: { [string]: BasePart } = {}

type AnimationPlayback = {
	animationName: string,
	frameRate: number,
	frames: { number },
	restFrame: number,
}

local function sanitizeFrame(frameRaw: any): number
	if typeof(frameRaw) ~= "number" or frameRaw ~= frameRaw then
		return 1
	end
	return math.clamp(math.floor(frameRaw), 1, FRAME_COUNT)
end

local function sanitizeFrameRate(frameRateRaw: any): number
	if typeof(frameRateRaw) ~= "number" or frameRateRaw ~= frameRateRaw then
		return 1
	end
	return math.clamp(frameRateRaw, 0.01, 120)
end

local function getAnimation(animationName: string): any
	return QueenBeeSpriteSheet.animations[animationName]
end

local function resolveAnimationName(snapshot: BossSnapshot): string
	if string.find(snapshot.state, "Charge", 1, true) ~= nil then
		return "Charge"
	end
	return "Idle"
end

local function resolvePlayback(snapshot: BossSnapshot): AnimationPlayback
	local animationName = resolveAnimationName(snapshot)
	local animation = getAnimation(animationName)
	local frames = animation.frames
	local restFrame = sanitizeFrame(frames[1])
	return {
		animationName = animationName,
		frameRate = sanitizeFrameRate(animation.frameRate),
		frames = frames,
		restFrame = restFrame,
	}
end

local function getFrameOffset(frameIndex: number): Vector2
	local frameSize = QueenBeeSpriteSheet.frameSize
	local zeroBased = math.max(0, sanitizeFrame(frameIndex) - 1)
	local column = zeroBased % QueenBeeSpriteSheet.columns
	local row = math.floor(zeroBased / QueenBeeSpriteSheet.columns)
	return Vector2.new(column * frameSize.X, row * frameSize.Y)
end

local function createAnimationFlipbook(playback: AnimationPlayback): any
	local frameSize = QueenBeeSpriteSheet.frameSize
	local flipbook = Flipbook.new({
		image = QueenBeeSpriteSheet.image,
		frameCount = #playback.frames,
		rows = #playback.frames,
		columns = 1,
		imageRectSize = frameSize,
		frameRate = playback.frameRate,
		restFrame = 1,
	})
	local flipbookAny = flipbook :: any

	for index, absoluteFrame in playback.frames do
		local frame = sanitizeFrame(absoluteFrame)
		flipbookAny:SetSpriteAtIndex(
			index,
			Sprite.new({
				Texture = QueenBeeSpriteSheet.image,
				Size = frameSize,
				Position = getFrameOffset(frame),
				Name = `QueenBee_{playback.animationName}_{index}`,
			})
		)
	end

	return flipbook
end

local function sanitizeClock(clockRaw: any): number
	if typeof(clockRaw) ~= "number" or clockRaw ~= clockRaw then
		return 0
	end
	return math.max(0, clockRaw)
end

local function resolvePlaybackIndex(playback: AnimationPlayback, renderClock: number): number
	local frameCount = #playback.frames
	if frameCount <= 0 then
		return 1
	end

	return math.floor(sanitizeClock(renderClock) * playback.frameRate) % frameCount + 1
end

local function resolveSheetPosition(frameOffset: Vector2): UDim2
	local frameSize = QueenBeeSpriteSheet.frameSize
	local xScale = if frameSize.X > 0 then -(frameOffset.X / frameSize.X) else 0
	local yScale = if frameSize.Y > 0 then -(frameOffset.Y / frameSize.Y) else 0
	return UDim2.fromScale(xScale, yScale)
end

local function resolveActiveFrameOffset(flipbook: any, playback: AnimationPlayback, renderClock: number): Vector2
	local sprite = flipbook:GetSprite(resolvePlaybackIndex(playback, renderClock))
	if sprite ~= nil and typeof(sprite.Position) == "Vector2" then
		return sprite.Position
	end
	return getFrameOffset(playback.restFrame)
end

local function resolveModelRootPart(model: Model): BasePart?
	local rootPart = model:FindFirstChild("RootPart")
	if rootPart ~= nil and rootPart:IsA("BasePart") then
		return rootPart
	end
	if model.PrimaryPart ~= nil then
		return model.PrimaryPart
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function resolveRuntimeRootPart(runtimeId: string): BasePart?
	local cachedRootPart = runtimeRootPartCache[runtimeId]
	if cachedRootPart ~= nil and cachedRootPart:IsDescendantOf(Workspace) then
		return cachedRootPart
	end
	runtimeRootPartCache[runtimeId] = nil

	local runtimeFolder = WorkspaceFolders.findFolderInGameOrWorkspace(BOSS_RUNTIME_FOLDER_NAME)
	if runtimeFolder == nil then
		return nil
	end

	for _, child in runtimeFolder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		if child:GetAttribute(BossServiceUtils.RUNTIME_ID_ATTRIBUTE) ~= runtimeId then
			continue
		end

		local rootPart = resolveModelRootPart(child)
		if rootPart ~= nil then
			runtimeRootPartCache[runtimeId] = rootPart
		end
		return rootPart
	end

	return nil
end

local function resolvePresentationPosition(snapshot: BossSnapshot, renderClock: number): Vector3?
	local rootPart = resolveRuntimeRootPart(snapshot.id)
	local basePosition = if rootPart ~= nil then rootPart.Position else snapshot.position
	if basePosition == nil then
		basePosition = snapshot.motion.position
	end
	if basePosition == nil then
		return nil
	end

	local hoverLift = math.sin((renderClock + snapshot.stateTime) * 4.5) * 0.18
	return basePosition + (snapshot.motion.localPresentationOffset or Vector3.zero) + Vector3.new(0, hoverLift, 0)
end

local function resolveRootSize(snapshot: BossSnapshot): Vector3
	local rootPart = resolveRuntimeRootPart(snapshot.id)
	if rootPart ~= nil then
		return rootPart.Size
	end
	return DEFAULT_ROOT_SIZE
end

local function resolveScreenPosition(position: Vector3, rootSize: Vector3): (UDim2?, number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil, 0
	end

	local viewportPoint, visible = camera:WorldToViewportPoint(position)
	if not visible or viewportPoint.Z <= 0 then
		return nil, 0
	end

	local topViewportPoint = camera:WorldToViewportPoint(position + Vector3.new(0, rootSize.Y * 0.5, 0))
	local bottomViewportPoint = camera:WorldToViewportPoint(position - Vector3.new(0, rootSize.Y * 0.5, 0))
	local projectedRootHeight = math.abs(topViewportPoint.Y - bottomViewportPoint.Y)
	return UDim2.fromOffset(viewportPoint.X, viewportPoint.Y), math.clamp(projectedRootHeight, 96, 420)
end

local function resolveSpriteSize(baseSize: number): UDim2
	local frameSize = QueenBeeSpriteSheet.frameSize
	local height = math.max(1, baseSize)
	local width = height
	if frameSize.Y > 0 then
		width = math.max(1, height * (frameSize.X / frameSize.Y))
	end
	return UDim2.fromOffset(width, height)
end

return function(props: QueenBeeProps): React.ReactNode
	local snapshot = props.snapshot
	local playback = resolvePlayback(snapshot)
	local isSurfaceGui = props.surfaceGui == true
	local zIndex = props.zIndex or 1
	local position = resolvePresentationPosition(snapshot, props.renderClock)
	local screenPosition = nil :: UDim2?
	local baseSize = 0
	if position ~= nil then
		screenPosition, baseSize = resolveScreenPosition(position, resolveRootSize(snapshot))
	end
	local visible = isSurfaceGui or screenPosition ~= nil

	local flipbook = React.useMemo(function()
		return createAnimationFlipbook(playback)
	end, {
		QueenBeeSpriteSheet.image,
		QueenBeeSpriteSheet.frameSize.X,
		QueenBeeSpriteSheet.frameSize.Y,
		playback.animationName,
		playback.frameRate,
	})
	local frameOffset = resolveActiveFrameOffset(flipbook, playback, props.renderClock)

	local children: { [string]: React.ReactNode } = {
		SpriteSheet = e("ImageLabel", {
			AnchorPoint = Vector2.zero,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = QueenBeeSpriteSheet.image,
			ImageRectOffset = Vector2.zero,
			ImageRectSize = Vector2.zero,
			Position = resolveSheetPosition(frameOffset),
			ResampleMode = Enum.ResamplerMode.Pixelated,
			ScaleType = Enum.ScaleType.Stretch,
			Size = UDim2.fromScale(QueenBeeSpriteSheet.columns, QueenBeeSpriteSheet.rows),
			ZIndex = zIndex,
		}),
	}
	if isSurfaceGui then
		children.AspectRatio = e("UIAspectRatioConstraint", {
			AspectRatio = QueenBeeSpriteSheet.frameSize.X / math.max(1, QueenBeeSpriteSheet.frameSize.Y),
			DominantAxis = Enum.DominantAxis.Height,
		})
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = if isSurfaceGui
			then UDim2.fromScale(0.5, 0.5)
			else screenPosition or UDim2.fromOffset(-10000, -10000),
		Size = if isSurfaceGui then UDim2.fromScale(0.92, 0.86) else resolveSpriteSize(baseSize),
		Visible = visible,
		ZIndex = zIndex,
	}, children)
end
