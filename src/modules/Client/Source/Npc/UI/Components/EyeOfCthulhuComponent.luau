local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Workspace = game:GetService("Workspace")

local Flipbook = require("Flipbook")
local FlipbookPlayer = require("FlipbookPlayer")
local Maid = require("Maid")
local Sprite = require("Sprite")

local BossServiceUtils = require("BossServiceUtils")
local EyeOfCthulhuSpriteSheet = require("EyeOfCthulhuSpriteSheet")
local React: any = require(ReplicatedStorage.Packages.React)
local WorkspaceFolders = require("WorkspaceFolders")

type BossSnapshot = BossServiceUtils.BossSnapshot

export type EyeOfCthulhuProps = {
	snapshot: BossSnapshot,
	renderClock: number,
	surfaceGui: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement
local BOSS_RUNTIME_FOLDER_NAME = "BossRuntime"
local DEFAULT_ROOT_SIZE = Vector3.new(14, 14, 14)
local FRAME_COUNT =
	math.max(1, EyeOfCthulhuSpriteSheet.frameCount or (EyeOfCthulhuSpriteSheet.columns * EyeOfCthulhuSpriteSheet.rows))
local runtimeRootPartCache: { [string]: BasePart? } = {}

type PhasePlayback = {
	phaseName: string,
	frameRate: number,
	frames: { number },
	restFrame: number,
}

local function coerceFrame(frameRaw: any): number
	if typeof(frameRaw) ~= "number" or frameRaw ~= frameRaw then
		return 1
	end
	return math.clamp(math.floor(frameRaw), 1, FRAME_COUNT)
end

local function coerceFrameRate(frameRateRaw: any): number
	if typeof(frameRateRaw) ~= "number" or frameRateRaw ~= frameRateRaw then
		return 1
	end
	return math.clamp(frameRateRaw, 0.01, 120)
end

local function getAnimation(animationName: string): any
	return EyeOfCthulhuSpriteSheet.animations[animationName]
end

local function getAnimationFrame(animationName: string, frameOffset: number?): number
	local animation = getAnimation(animationName)
	local frames = animation.frames
	local frameCount = #frames
	local offset = if typeof(frameOffset) == "number" then frameOffset else 0
	local index = offset % frameCount + 1
	return coerceFrame(frames[index])
end

local function getPhaseName(snapshot: BossSnapshot): string
	if snapshot.phase >= 2 or string.lower(snapshot.presentation.phaseModel) == "phase2" then
		return "Phase2"
	end
	return "Phase1"
end

local function getPlayback(snapshot: BossSnapshot): PhasePlayback
	local phaseName = getPhaseName(snapshot)
	local animation = getAnimation(phaseName)
	return {
		phaseName = phaseName,
		frameRate = coerceFrameRate(animation.frameRate),
		frames = animation.frames,
		restFrame = getAnimationFrame(phaseName, nil),
	}
end

local function getModelRootPart(model: Model): BasePart?
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

local function getRuntimeRootPart(runtimeId: string): BasePart?
	local cachedRootPart = runtimeRootPartCache[runtimeId]
	if cachedRootPart ~= nil and cachedRootPart:IsDescendantOf(Workspace) then
		return cachedRootPart
	end
	runtimeRootPartCache[runtimeId] = nil

	local runtimeFolder = WorkspaceFolders.FindFolderInGameOrWorkspace(BOSS_RUNTIME_FOLDER_NAME)
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

		local rootPart = getModelRootPart(child)
		if rootPart ~= nil then
			runtimeRootPartCache[runtimeId] = rootPart
		end
		return rootPart
	end

	return nil
end

local function getPresentationPosition(snapshot: BossSnapshot): Vector3?
	local rootPart = getRuntimeRootPart(snapshot.id)
	local basePosition = if rootPart ~= nil then rootPart.Position else snapshot.position
	if basePosition == nil then
		basePosition = snapshot.motion.position
	end
	if basePosition == nil then
		return nil
	end

	local stateTime = snapshot.stateTime
	local hoverLift = if snapshot.state == "SpawnIntro"
		then math.sin(stateTime * 2.1) * 0.55
		else if snapshot.state == "Phase1Hover" or snapshot.state == "Phase1ServantBurst"
			then math.sin(stateTime * 3.9) * 0.22
			else if snapshot.state == "Phase2HoverIdle" or snapshot.state == "Phase2Hover"
				then math.sin(stateTime * 5.1) * 0.14
				else 0
	local suggestedOffset = snapshot.motion.localPresentationOffset or Vector3.zero
	return basePosition + suggestedOffset + Vector3.new(0, hoverLift, 0)
end

local function getRootSize(snapshot: BossSnapshot): Vector3
	local rootPart = getRuntimeRootPart(snapshot.id)
	if rootPart ~= nil then
		return rootPart.Size
	end
	return DEFAULT_ROOT_SIZE
end

local function getScreenPosition(position: Vector3, rootSize: Vector3): (UDim2?, number)
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
	local size = math.clamp(projectedRootHeight, 72, 360)
	return UDim2.fromOffset(viewportPoint.X, viewportPoint.Y), size
end

local function getSpriteSize(baseSize: number): UDim2
	local frameSize = EyeOfCthulhuSpriteSheet.frameSize
	local height = math.max(1, baseSize)
	local width = height
	if frameSize.Y > 0 then
		width = math.max(1, height * (frameSize.X / frameSize.Y))
	end
	return UDim2.fromOffset(width, height)
end

local function createPhaseFlipbook(playback: PhasePlayback): any
	local frameSize = EyeOfCthulhuSpriteSheet.frameSize
	local flipbook = Flipbook.new({
		image = EyeOfCthulhuSpriteSheet.image,
		frameCount = #playback.frames,
		rows = #playback.frames,
		columns = 1,
		imageRectSize = frameSize,
		frameRate = playback.frameRate,
		restFrame = 1,
	})

	for index, absoluteFrame in playback.frames do
		local frame = coerceFrame(absoluteFrame)
		local zeroBasedFrame = frame - 1
		(flipbook :: any):SetSpriteAtIndex(
			index,
			Sprite.new({
				Texture = EyeOfCthulhuSpriteSheet.image,
				Size = frameSize,
				Position = Vector2.new(0, zeroBasedFrame * frameSize.Y),
				Name = `EyeOfCthulhu_{playback.phaseName}_{index}`,
			})
		)
	end

	return flipbook
end

local function getFrameOffset(frameIndex: number): Vector2
	local zeroBased = math.max(0, coerceFrame(frameIndex) - 1)
	return Vector2.new(0, zeroBased * EyeOfCthulhuSpriteSheet.frameSize.Y)
end

return function(props: EyeOfCthulhuProps): React.ReactNode
	local snapshot = props.snapshot
	local playback = getPlayback(snapshot)
	local imageRef = React.useRef(nil :: ImageLabel?)
	local playerRef = React.useRef(nil :: any)
	local position = getPresentationPosition(snapshot)
	local isSurfaceGui = props.surfaceGui == true
	local screenPosition = nil :: UDim2?
	local baseSize = 0
	if position ~= nil then
		screenPosition, baseSize = getScreenPosition(position, getRootSize(snapshot))
	end
	local visible = isSurfaceGui or screenPosition ~= nil

	React.useEffect(function()
		local imageLabel = imageRef.current
		if imageLabel == nil then
			return
		end

		local maid = Maid.new()
		local player = FlipbookPlayer.new(imageLabel)
		playerRef.current = player
		maid:GiveTask(player)

		return function()
			playerRef.current = nil
			maid:DoCleaning()
		end
	end, {})

	React.useEffect(
		function()
			local player = playerRef.current
			if player == nil then
				return
			end

			player:SetFlipbook(createPhaseFlipbook(playback))
			player:Play()
		end,
		{
			EyeOfCthulhuSpriteSheet.image,
			EyeOfCthulhuSpriteSheet.frameSize.X,
			EyeOfCthulhuSpriteSheet.frameSize.Y,
			playback.phaseName,
			playback.frameRate,
		} :: { any }
	)

	local children = nil
	if isSurfaceGui then
		children = {
			e("UIAspectRatioConstraint", {
				AspectRatio = EyeOfCthulhuSpriteSheet.frameSize.X / math.max(1, EyeOfCthulhuSpriteSheet.frameSize.Y),
				DominantAxis = Enum.DominantAxis.Height,
			}),
		}
	end

	return e("ImageLabel", {
		ref = imageRef,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = EyeOfCthulhuSpriteSheet.image,
		ImageRectOffset = getFrameOffset(playback.restFrame),
		ImageRectSize = EyeOfCthulhuSpriteSheet.frameSize,
		Position = if isSurfaceGui
			then UDim2.fromScale(0.5, 0.5)
			else screenPosition or UDim2.fromOffset(-10000, -10000),
		ResampleMode = Enum.ResamplerMode.Pixelated,
		ScaleType = Enum.ScaleType.Stretch,
		Size = if isSurfaceGui then UDim2.fromScale(1, 1) else getSpriteSize(baseSize),
		Visible = visible,
		ZIndex = props.zIndex or 1,
	}, children)
end
