local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Workspace = game:GetService("Workspace")

local Flipbook = require("Flipbook")
local FlipbookPlayer = require("FlipbookPlayer")
local Maid = require("Maid")
local Sprite = require("Sprite")

local NpcServiceUtils = require("NpcServiceUtils")
local NpcSlice = require("NpcSlice")
local React: any = require(ReplicatedStorage.Packages.React)
local SlimeSpriteSheet = require("SlimeSpriteSheet")
local SlimeTints = require("SlimeTints")
local WorkspaceFolders = require("WorkspaceFolders")

type NpcSnapshot = NpcServiceUtils.NpcSnapshot
type SlimeGoreSprite = NpcSlice.SlimeGoreSprite

export type SlimeProps = {
	snapshot: NpcSnapshot?,
	gore: SlimeGoreSprite?,
	renderClock: number,
	surfaceGui: boolean?,
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement
local FRAME_COUNT = math.max(1, SlimeSpriteSheet.frameCount or (SlimeSpriteSheet.columns * SlimeSpriteSheet.rows))
local NPC_RUNTIME_FOLDER_NAME = "NpcRuntime"
local FALLBACK_ROOT_SIZE = Vector3.new(4, 3, 4)
local CONTENT_BOUNDS_MIN = SlimeSpriteSheet.contentBounds.min
local CONTENT_BOUNDS_MAX = SlimeSpriteSheet.contentBounds.max
local GORE_ANCHOR_POINT = Vector2.new(0.5, 0.5)
local runtimeRootPartCache: { [string]: BasePart? } = {}

type SpritePlayback = {
	playing: boolean,
	restFrame: number,
	frameRate: number,
}

type SpriteImageProps = {
	position: Vector3,
	rootSize: Vector3?,
	playback: SpritePlayback,
	imageColor: Color3,
	scale: number,
	facingSign: number?,
	surfaceGui: boolean?,
	zIndex: number,
	anchorPoint: Vector2?,
}

local function getAnimation(animationName: string): any
	return SlimeSpriteSheet.animations[animationName]
end

local function CoerceFrame(frameRaw: any): number
	if typeof(frameRaw) ~= "number" or frameRaw ~= frameRaw then
		return 1
	end
	return math.clamp(math.floor(frameRaw), 1, FRAME_COUNT)
end

local function CoerceFrameRate(frameRateRaw: any, fallback: number): number
	if typeof(frameRateRaw) ~= "number" or frameRateRaw ~= frameRateRaw then
		return fallback
	end
	return math.clamp(frameRateRaw, 0.01, 120)
end

local function getSnapshotPhaseElapsed(snapshot: NpcSnapshot, renderClock: number): number
	local phaseElapsed = if typeof(snapshot.spritePhaseElapsed) == "number" then snapshot.spritePhaseElapsed else 0
	local receivedAt = if typeof(snapshot.spriteReceivedAt) == "number" then snapshot.spriteReceivedAt else renderClock
	return math.max(0, phaseElapsed + math.max(0, renderClock - receivedAt))
end

local function getAnimationFrameRate(animationName: string, key: string, fallback: number): number
	local animation = getAnimation(animationName)
	local value = animation[key]
	if typeof(value) == "number" and value == value then
		return value
	end
	return fallback
end

local function getAnimationFrame(animationName: string, frameOffset: number?): number
	local animation = getAnimation(animationName)
	local frames = animation.frames
	local frameCount = #frames
	local offset = if typeof(frameOffset) == "number" then frameOffset else 0
	local index = offset % frameCount + 1
	return CoerceFrame(frames[index])
end

local function GetAcceleratingAnimationFrame(
	animationName: string,
	elapsed: number,
	duration: number,
	minFrameRate: number,
	maxFrameRate: number
): number
	local animation = getAnimation(animationName)
	local frames = animation.frames
	local frameCount = #frames
	local safeDuration = math.max(0.001, duration)
	local safeElapsed = math.clamp(elapsed, 0, safeDuration)
	local frameProgress = minFrameRate * safeElapsed
		+ (maxFrameRate - minFrameRate) * (safeElapsed ^ 3) / (3 * safeDuration * safeDuration)
	local index = math.floor(frameProgress) % frameCount + 1
	return CoerceFrame(frames[index])
end

local function getFrameOffset(frameIndex: number, flipX: boolean?): Vector2
	local frameSize = SlimeSpriteSheet.frameSize
	local zeroBased = math.max(0, CoerceFrame(frameIndex) - 1)
	local column = zeroBased % SlimeSpriteSheet.columns
	local row = math.floor(zeroBased / SlimeSpriteSheet.columns)
	local x = column * frameSize.X
	if flipX == true then
		x += frameSize.X
	end
	return Vector2.new(x, row * frameSize.Y)
end

local function GetImageRectSize(flipX: boolean?): Vector2
	local frameSize = SlimeSpriteSheet.frameSize
	if flipX == true then
		return Vector2.new(-frameSize.X, frameSize.Y)
	end
	return frameSize
end

local function createFlipbook(frameRate: number, restFrame: number, flipX: boolean?): any
	local flipbook = Flipbook.new({
		image = SlimeSpriteSheet.image,
		frameCount = FRAME_COUNT,
		rows = SlimeSpriteSheet.rows,
		columns = SlimeSpriteSheet.columns,
		imageRectSize = SlimeSpriteSheet.frameSize,
		frameRate = frameRate,
		restFrame = restFrame,
	})

	if flipX == true then
		local frameSize = SlimeSpriteSheet.frameSize
		local spriteSize = Vector2.new(-frameSize.X, frameSize.Y)
		for index = 1, FRAME_COUNT do
			(flipbook :: any):SetSpriteAtIndex(
				index,
				Sprite.new({
					Texture = SlimeSpriteSheet.image,
					Size = spriteSize,
					Position = getFrameOffset(index, true),
					Name = `Slime_{index}`,
				})
			)
		end
	end

	return flipbook
end

local function GetModelRootPart(model: Model): BasePart?
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

local function GetUntimeRootPart(runtimeId: string): BasePart?
	local cachedRootPart = runtimeRootPartCache[runtimeId]
	if cachedRootPart ~= nil and cachedRootPart:IsDescendantOf(Workspace) then
		return cachedRootPart
	end
	runtimeRootPartCache[runtimeId] = nil

	local runtimeFolder = WorkspaceFolders.FindFolderInGameOrWorkspace(NPC_RUNTIME_FOLDER_NAME)
	if runtimeFolder == nil then
		return nil
	end

	for _, child in runtimeFolder:GetChildren() do
		if not child:IsA("Model") then
			continue
		end
		if child:GetAttribute(NpcServiceUtils.RUNTIME_ID_ATTRIBUTE) ~= runtimeId then
			continue
		end

		local rootPart = GetModelRootPart(child)
		if rootPart ~= nil then
			runtimeRootPartCache[runtimeId] = rootPart
		end
		return rootPart
	end

	return nil
end

local function GetSnapshotSpritePlacement(snapshot: NpcSnapshot): (Vector3?, Vector3?)
	local rootPart = GetUntimeRootPart(snapshot.id)
	if rootPart ~= nil then
		return rootPart.Position, rootPart.Size
	end

	if snapshot.position == nil then
		return nil, nil
	end
	return snapshot.position, FALLBACK_ROOT_SIZE
end

local function GetSnapshotPlayback(snapshot: NpcSnapshot, renderClock: number): SpritePlayback
	if not snapshot.isAlive or snapshot.state == "Dead" then
		local animation = getAnimation("Dead")
		return {
			playing = false,
			restFrame = CoerceFrame(snapshot.spriteFrame or getAnimationFrame("Dead", nil)),
			frameRate = CoerceFrameRate(snapshot.spriteFrameRate, animation.frameRate),
		}
	end

	local phase = if typeof(snapshot.spritePhase) == "string" and snapshot.spritePhase ~= ""
		then snapshot.spritePhase
		else "Idle"
	local animation = getAnimation(phase)
	local frameRate = CoerceFrameRate(snapshot.spriteFrameRate, animation.frameRate)
	if typeof(snapshot.spriteFrame) == "number" then
		return {
			playing = false,
			restFrame = CoerceFrame(snapshot.spriteFrame),
			frameRate = frameRate,
		}
	end

	if phase == "Idle" then
		local minFrameRate = getAnimationFrameRate("Idle", "minFrameRate", frameRate)
		local maxFrameRate = getAnimationFrameRate("Idle", "maxFrameRate", frameRate)
		local phaseDuration = if typeof(snapshot.spritePhaseDuration) == "number"
			then snapshot.spritePhaseDuration
			else nil
		local restFrame = getAnimationFrame("Idle", nil)
		if phaseDuration ~= nil and phaseDuration > 0 then
			local phaseElapsed = getSnapshotPhaseElapsed(snapshot, renderClock)
			local phaseAlpha = math.clamp(phaseElapsed / phaseDuration, 0, 1)
			frameRate = minFrameRate + (maxFrameRate - minFrameRate) * phaseAlpha * phaseAlpha
			restFrame =
				GetAcceleratingAnimationFrame("Idle", phaseElapsed, phaseDuration, minFrameRate, maxFrameRate)
		end

		return {
			playing = false,
			restFrame = restFrame,
			frameRate = frameRate,
		}
	end

	if phase == "Hop" then
		return {
			playing = false,
			restFrame = getAnimationFrame("Hop", nil),
			frameRate = frameRate,
		}
	end

	return {
		playing = false,
		restFrame = getAnimationFrame(phase, nil),
		frameRate = frameRate,
	}
end

local function GetGorePlayback(frameOffset: number?): SpritePlayback
	local animation = getAnimation("Gore")
	return {
		playing = true,
		restFrame = getAnimationFrame("Gore", frameOffset),
		frameRate = CoerceFrameRate(animation.frameRate, 12),
	}
end

local function GetContentWidth(): number
	return math.max(1, CONTENT_BOUNDS_MAX.X - CONTENT_BOUNDS_MIN.X)
end

local function GetContentAnchorPoint(): Vector2
	local frameSize = SlimeSpriteSheet.frameSize
	return Vector2.new(
		((CONTENT_BOUNDS_MIN.X + CONTENT_BOUNDS_MAX.X) * 0.5) / frameSize.X,
		((CONTENT_BOUNDS_MIN.Y + CONTENT_BOUNDS_MAX.Y) * 0.5) / frameSize.Y
	)
end

local function GetProjectedRootWidth(position: Vector3, rootSize: Vector3): number
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return 0
	end

	local cameraRight = camera.CFrame.RightVector
	local widthStuds = math.abs(cameraRight.X) * rootSize.X + math.abs(cameraRight.Z) * rootSize.Z
	if widthStuds <= 0 then
		widthStuds = math.max(rootSize.X, rootSize.Z)
	end

	local leftPoint = position - cameraRight * widthStuds * 0.5
	local rightPoint = position + cameraRight * widthStuds * 0.5
	local leftViewportPoint = camera:WorldToViewportPoint(leftPoint)
	local rightViewportPoint = camera:WorldToViewportPoint(rightPoint)
	return math.abs(rightViewportPoint.X - leftViewportPoint.X)
end

local function GetScreenPosition(position: Vector3, rootSize: Vector3?): (UDim2?, number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil, 0
	end

	local viewportPoint, visible = camera:WorldToViewportPoint(position)
	if not visible or viewportPoint.Z <= 0 then
		return nil, 0
	end

	if rootSize ~= nil then
		local projectedRootWidth = GetProjectedRootWidth(position, rootSize)
		local frameHeight = projectedRootWidth * (SlimeSpriteSheet.frameSize.Y / GetContentWidth())
		return UDim2.fromOffset(viewportPoint.X, viewportPoint.Y), math.clamp(frameHeight, 24, 176)
	end

	local distance = math.max(1, (camera.CFrame.Position - position).Magnitude)
	local size = math.clamp((SlimeSpriteSheet.pixelsPerStud * 6) / math.max(0.35, distance / 24), 54, 176)
	return UDim2.fromOffset(viewportPoint.X, viewportPoint.Y), size
end

local function GetSpriteSize(baseSize: number, scale: number): UDim2
	local frameSize = SlimeSpriteSheet.frameSize
	local height = math.max(1, baseSize * scale)
	local width = height
	if frameSize.Y > 0 then
		width = math.max(1, height * (frameSize.X / frameSize.Y))
	end
	return UDim2.fromOffset(width, height)
end

local function SpriteImage(props: SpriteImageProps)
	local imageRef = React.useRef(nil :: ImageLabel?)
	local playerRef = React.useRef(nil :: any)
	local flipbookRef = React.useRef(nil :: any)
	local screenPosition, baseSize = GetScreenPosition(props.position, props.rootSize)
	local isSurfaceGui = props.surfaceGui == true
	local visible = isSurfaceGui or screenPosition ~= nil
	local playback = props.playback
	local restFrame = CoerceFrame(playback.restFrame)
	local frameRate = CoerceFrameRate(playback.frameRate, 1)
	local flipX = if typeof(props.facingSign) == "number" then props.facingSign < 0 else false

	React.useEffect(
		function()
			local imageLabel = imageRef.current
			if imageLabel == nil then
				return
			end

			local maid = Maid.new()
			local flipbook = createFlipbook(frameRate, restFrame, flipX)
			local player = FlipbookPlayer.new(imageLabel)
			flipbookRef.current = flipbook
			playerRef.current = player
			maid:GiveTask(player)
			player:SetFlipbook(flipbook)
			if playback.playing then
				player:Play()
			else
				player:Stop()
			end

			return function()
				playerRef.current = nil
				flipbookRef.current = nil
				maid:DoCleaning()
			end
		end,
		{
			SlimeSpriteSheet.image,
			FRAME_COUNT,
			SlimeSpriteSheet.rows,
			SlimeSpriteSheet.columns,
			SlimeSpriteSheet.frameSize.X,
			SlimeSpriteSheet.frameSize.Y,
			restFrame,
			flipX,
		} :: { any }
	)

	React.useEffect(
		function()
			local flipbook = flipbookRef.current
			if flipbook ~= nil then
				flipbook:SetFrameRate(frameRate)
			end
		end,
		{
			frameRate,
		} :: { any }
	)

	React.useEffect(
		function()
			local player = playerRef.current
			if player == nil then
				return
			end
			if playback.playing then
				player:Play()
			else
				player:Stop()
			end
		end,
		{
			playback.playing,
		} :: { any }
	)

	local children = nil
	if isSurfaceGui then
		children = {
			e("UIAspectRatioConstraint", {
				AspectRatio = SlimeSpriteSheet.frameSize.X / math.max(1, SlimeSpriteSheet.frameSize.Y),
				DominantAxis = Enum.DominantAxis.Height,
			}),
		}
	end

	return e("ImageLabel", {
		ref = imageRef,
		AnchorPoint = if isSurfaceGui then Vector2.new(0.5, 0.5) else props.anchorPoint or GetContentAnchorPoint(),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = SlimeSpriteSheet.image,
		ImageColor3 = props.imageColor,
		ImageRectOffset = getFrameOffset(restFrame, flipX),
		ImageRectSize = GetImageRectSize(flipX),
		Position = if isSurfaceGui
			then UDim2.fromScale(0.5, 0.5)
			else screenPosition or UDim2.fromOffset(-10000, -10000),
		ResampleMode = Enum.ResamplerMode.Pixelated,
		ScaleType = Enum.ScaleType.Stretch,
		Size = if isSurfaceGui then UDim2.fromScale(1, 1) else GetSpriteSize(baseSize, props.scale),
		Visible = visible,
		ZIndex = props.zIndex,
	}, children)
end

return function(props: SlimeProps)
	local renderClock = props.renderClock
	local zIndex = if typeof(props.zIndex) == "number" then props.zIndex else 1

	if props.gore ~= nil then
		local gore = props.gore :: SlimeGoreSprite
		local age = math.max(0, renderClock - gore.createdAt)
		local position = gore.position + gore.velocity * age + Vector3.new(0, -8 * age * age, 0)
		return e(SpriteImage, {
			position = position,
			rootSize = nil,
			playback = GetGorePlayback(gore.frameOffset),
			imageColor = gore.imageColor,
			scale = gore.scale,
			facingSign = 1,
			surfaceGui = props.surfaceGui,
			zIndex = zIndex,
			anchorPoint = GORE_ANCHOR_POINT,
		})
	end

	local snapshot = props.snapshot
	if snapshot == nil or not snapshot.isAlive then
		return nil
	end
	local position, rootSize = GetSnapshotSpritePlacement(snapshot)
	if position == nil then
		return nil
	end

	return e(SpriteImage, {
		position = position,
		rootSize = rootSize,
		playback = GetSnapshotPlayback(snapshot, renderClock),
		imageColor = SlimeTints.Green,
		scale = 1,
		facingSign = snapshot.spriteFacingSign,
		surfaceGui = props.surfaceGui,
		zIndex = zIndex,
	})
end
