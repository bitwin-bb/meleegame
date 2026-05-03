--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = require(loaderUtils.Parent).load(script)

local Flipbook = loader("Flipbook")
local FlipbookPlayer = loader("FlipbookPlayer")
local Maid = loader("Maid")
local React = require(ReplicatedStorage.Packages.React)

type FrameSlice = {
	offset: Vector2,
	size: Vector2,
}

export type GifProps = {
	image: string,
	frameSize: Vector2,
	frameCount: number,
	columns: number,
	frameOrigin: Vector2?,
	framePadding: Vector2?,
	frameRects: { Rect }?,
	fps: number?,
	playing: boolean?,
	looped: boolean?,
	startFrame: number?,
	startFrameIndex: number?,
	onLooped: ((loopCount: number) -> ())?,
	onCompleted: (() -> ())?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	backgroundColor3: Color3?,
	backgroundTransparency: number?,
	borderSizePixel: number?,
	clipsDescendants: boolean?,
	imageColor3: Color3?,
	imageTransparency: number?,
	scaleType: Enum.ScaleType?,
	sliceCenter: Rect?,
	sliceScale: number?,
	resampleMode: Enum.ResamplerMode?,
	preferNevermoreFlipbook: boolean?,
	native: { [any]: any }?,
	children: { [string]: React.ReactNode }?,
}

local e: typeof(React.createElement) = React.createElement

local DEFAULT_FPS = 12
local DEFAULT_BACKGROUND_TRANSPARENCY = 1
local DEFAULT_FRAME_SIZE = Vector2.new(32, 32)

local function sanitizeNumber(value: any, fallback: number, minimum: number?, maximum: number?): number
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end

	local result = value
	if minimum ~= nil and result < minimum then
		result = minimum
	end
	if maximum ~= nil and result > maximum then
		result = maximum
	end
	return result
end

local function sanitizeVector2PositivePixels(value: any, fallback: Vector2): Vector2
	if typeof(value) ~= "Vector2" then
		return fallback
	end
	if value.X ~= value.X or value.Y ~= value.Y then
		return fallback
	end

	return Vector2.new(math.max(1, math.floor(value.X + 0.5)), math.max(1, math.floor(value.Y + 0.5)))
end

local function sanitizeVector2NonNegativePixels(value: any, fallback: Vector2): Vector2
	if typeof(value) ~= "Vector2" then
		return fallback
	end
	if value.X ~= value.X or value.Y ~= value.Y then
		return fallback
	end

	return Vector2.new(math.max(0, math.floor(value.X + 0.5)), math.max(0, math.floor(value.Y + 0.5)))
end

local function clampFrameIndex(frameIndexRaw: any, frameCount: number): number
	local frameIndex = math.floor(sanitizeNumber(frameIndexRaw, 0, 0, frameCount - 1))
	return math.clamp(frameIndex, 0, frameCount - 1)
end

local function resolveExplicitFrameSlices(frameRectsRaw: any): { FrameSlice }
	if typeof(frameRectsRaw) ~= "table" then
		return {}
	end

	local slices: { FrameSlice } = {}
	for _, rectRaw in frameRectsRaw do
		if typeof(rectRaw) ~= "Rect" then
			continue
		end

		local rect = rectRaw :: Rect
		local rectOffset = rect.Min
		local rectSize = rect.Max - rect.Min
		local width = math.max(0, math.floor(rectSize.X + 0.5))
		local height = math.max(0, math.floor(rectSize.Y + 0.5))
		if width <= 0 or height <= 0 then
			continue
		end

		table.insert(slices, {
			offset = Vector2.new(math.floor(rectOffset.X + 0.5), math.floor(rectOffset.Y + 0.5)),
			size = Vector2.new(width, height),
		})
	end

	return slices
end

local function resolveComputedFrameSlice(
	frameIndex: number,
	columns: number,
	frameSize: Vector2,
	frameOrigin: Vector2,
	framePadding: Vector2
): FrameSlice
	local column = frameIndex % columns
	local row = math.floor(frameIndex / columns)
	local stride = frameSize + framePadding
	local offset = frameOrigin + Vector2.new(column * stride.X, row * stride.Y)

	return {
		offset = offset,
		size = frameSize,
	}
end

local function resolveGridRowCount(frameCount: number, columns: number): number
	return math.max(1, math.ceil(frameCount / columns))
end

local function resolveGridFrameSlice(frameIndex: number, columns: number, frameSize: Vector2): FrameSlice
	return resolveComputedFrameSlice(frameIndex, columns, frameSize, Vector2.zero, Vector2.zero)
end

local function Gif(props: GifProps)
	local fallbackFrameSize = sanitizeVector2PositivePixels(props.frameSize, DEFAULT_FRAME_SIZE)
	local frameOrigin = sanitizeVector2NonNegativePixels(props.frameOrigin, Vector2.zero)
	local framePadding = sanitizeVector2NonNegativePixels(props.framePadding, Vector2.zero)
	local columns = math.max(1, math.floor(sanitizeNumber(props.columns, 1, 1, nil)))
	local explicitSlices = resolveExplicitFrameSlices(props.frameRects)
	local frameCount = if #explicitSlices > 0
		then #explicitSlices
		else math.max(1, math.floor(sanitizeNumber(props.frameCount, 1, 1, nil)))
	local fps = sanitizeNumber(props.fps, DEFAULT_FPS, 0.01, 240)
	local frameDuration = 1 / fps
	local looped = props.looped ~= false
	local playing = props.playing ~= false
	local startFrameIndex = if props.startFrameIndex ~= nil
		then clampFrameIndex(props.startFrameIndex, frameCount)
		else clampFrameIndex(if props.startFrame ~= nil then props.startFrame - 1 else 0, frameCount)
	local imageRef = React.useRef(nil :: ImageLabel?)

	local frameIndex, setFrameIndex = React.useState(startFrameIndex)
	local frameIndexRef = React.useRef(startFrameIndex)
	local elapsedRef = React.useRef(0)
	local completedRef = React.useRef(startFrameIndex >= frameCount - 1)
	local loopCountRef = React.useRef(0)

	React.useEffect(function()
		local nextStartFrameIndex = if props.startFrameIndex ~= nil
			then clampFrameIndex(props.startFrameIndex, frameCount)
			else clampFrameIndex(if props.startFrame ~= nil then props.startFrame - 1 else 0, frameCount)
		frameIndexRef.current = nextStartFrameIndex
		elapsedRef.current = 0
		loopCountRef.current = 0
		completedRef.current = nextStartFrameIndex >= frameCount - 1
		setFrameIndex(nextStartFrameIndex)
	end, {
		props.image,
		props.startFrame,
		props.startFrameIndex,
		frameCount,
		columns,
		fallbackFrameSize.X,
		fallbackFrameSize.Y,
		frameOrigin.X,
		frameOrigin.Y,
		framePadding.X,
		framePadding.Y,
	})

	React.useEffect(function()
		if not playing or frameCount <= 1 then
			return
		end

		local connection = RunService.RenderStepped:Connect(function(deltaTime: number)
			elapsedRef.current += deltaTime
			if elapsedRef.current < frameDuration then
				return
			end

			local advancedFrames = math.floor(elapsedRef.current / frameDuration)
			elapsedRef.current -= advancedFrames * frameDuration
			if advancedFrames <= 0 then
				return
			end

			local previousFrameIndex = frameIndexRef.current
			local rawFrameIndex = previousFrameIndex + advancedFrames
			local nextFrameIndex = previousFrameIndex

			if looped then
				nextFrameIndex = rawFrameIndex % frameCount
				if rawFrameIndex >= frameCount and props.onLooped ~= nil then
					local loopsCompleted = math.floor(rawFrameIndex / frameCount)
					loopCountRef.current += loopsCompleted
					props.onLooped(loopCountRef.current)
				end
			else
				nextFrameIndex = math.min(rawFrameIndex, frameCount - 1)
				if nextFrameIndex >= frameCount - 1 and not completedRef.current then
					completedRef.current = true
					if props.onCompleted ~= nil then
						props.onCompleted()
					end
				end
			end

			if nextFrameIndex == previousFrameIndex then
				return
			end

			frameIndexRef.current = nextFrameIndex
			setFrameIndex(nextFrameIndex)
		end)

		return function()
			connection:Disconnect()
		end
	end, {
		playing,
		looped,
		frameCount,
		frameDuration,
		props.onLooped,
		props.onCompleted,
	})

	React.useEffect(function()
		frameIndexRef.current = frameIndex
	end, { frameIndex })

	local hasExplicitRects = #explicitSlices > 0
	local hasGridOffset = frameOrigin ~= Vector2.zero or framePadding ~= Vector2.zero
	-- Flipbook slices by absolute pixels, so a re-exported sheet can drift if its
	-- resolution changes but the grid layout stays the same. The viewport path only
	-- depends on rows/columns, so keep it as the default and make Flipbook opt-in.
	local useNevermoreFlipbook = props.preferNevermoreFlipbook == true
		and (not hasExplicitRects)
		and not hasGridOffset
		and props.onLooped == nil
	local useViewportMode = (not hasExplicitRects) and not hasGridOffset

	React.useEffect(function()
		if not useNevermoreFlipbook then
			return
		end

		local imageLabel = imageRef.current
		if imageLabel == nil then
			return
		end

		local maid = Maid.new()
		local flipbook = Flipbook.new({
			image = props.image,
			frameCount = frameCount,
			rows = resolveGridRowCount(frameCount, columns),
			columns = columns,
			imageRectSize = fallbackFrameSize,
			frameRate = fps,
			restFrame = startFrameIndex + 1,
		})
		local player = FlipbookPlayer.new(imageLabel)
		maid:GiveTask(player)
		player:SetFlipbook(flipbook)

		local alive = true
		if playing then
			if looped then
				player:Play()
			else
				player:PromisePlayRepeat(1):Then(function()
					if alive and props.onCompleted ~= nil then
						props.onCompleted()
					end
				end)
			end
		else
			player:Stop()
		end

		return function()
			alive = false
			maid:DoCleaning()
		end
	end, {
		useNevermoreFlipbook,
		props.image,
		frameCount,
		columns,
		fallbackFrameSize.X,
		fallbackFrameSize.Y,
		fps,
		playing,
		looped,
		startFrameIndex,
		props.onCompleted,
	})

	if useNevermoreFlipbook then
		local activeSlice = resolveGridFrameSlice(startFrameIndex, columns, fallbackFrameSize)
		local rootProps = {
			ref = imageRef,
			Size = props.size or UDim2.fromOffset(fallbackFrameSize.X, fallbackFrameSize.Y),
			Position = props.position or UDim2.fromScale(0, 0),
			AnchorPoint = props.anchorPoint or Vector2.new(0, 0),
			LayoutOrder = props.layoutOrder,
			Visible = props.visible ~= false,
			ZIndex = props.zIndex or 1,
			BackgroundColor3 = props.backgroundColor3,
			BackgroundTransparency = sanitizeNumber(
				props.backgroundTransparency,
				DEFAULT_BACKGROUND_TRANSPARENCY,
				0,
				1
			),
			BorderSizePixel = if props.borderSizePixel ~= nil then props.borderSizePixel else 0,
			ClipsDescendants = if props.clipsDescendants ~= nil then props.clipsDescendants else false,
			Image = props.image,
			ImageColor3 = props.imageColor3,
			ImageTransparency = sanitizeNumber(props.imageTransparency, 0, 0, 1),
			ImageRectOffset = activeSlice.offset,
			ImageRectSize = activeSlice.size,
			ScaleType = props.scaleType,
			SliceCenter = props.sliceCenter,
			SliceScale = props.sliceScale,
			ResampleMode = props.resampleMode,
		}

		if props.native then
			for index, value in props.native do
				(rootProps :: any)[index] = value
			end
		end

		local children: { [string]: React.ReactNode } = {}
		if props.children then
			for childName, child in props.children do
				children[childName] = child
			end
		end

		return e("ImageLabel", rootProps, children)
	end

	if useViewportMode then
		local rows = resolveGridRowCount(frameCount, columns)
		local column = frameIndex % columns
		local row = math.floor(frameIndex / columns)

		local rootProps = {
			Size = props.size or UDim2.fromOffset(fallbackFrameSize.X, fallbackFrameSize.Y),
			Position = props.position or UDim2.fromScale(0, 0),
			AnchorPoint = props.anchorPoint or Vector2.new(0, 0),
			LayoutOrder = props.layoutOrder,
			Visible = props.visible ~= false,
			ZIndex = props.zIndex or 1,
			BackgroundColor3 = props.backgroundColor3,
			BackgroundTransparency = sanitizeNumber(
				props.backgroundTransparency,
				DEFAULT_BACKGROUND_TRANSPARENCY,
				0,
				1
			),
			BorderSizePixel = if props.borderSizePixel ~= nil then props.borderSizePixel else 0,
			ClipsDescendants = true,
		}

		if props.native then
			for index, value in props.native do
				(rootProps :: any)[index] = value
			end
		end
		(rootProps :: any).ClipsDescendants = true

		local children: { [string]: React.ReactNode } = {
			SpriteSheet = e("ImageLabel", {
				Size = UDim2.fromScale(columns, rows),
				Position = UDim2.fromScale(-column, -row),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Image = props.image,
				ImageColor3 = props.imageColor3,
				ImageTransparency = sanitizeNumber(props.imageTransparency, 0, 0, 1),
				ScaleType = if props.scaleType ~= nil then props.scaleType else Enum.ScaleType.Stretch,
				SliceCenter = props.sliceCenter,
				SliceScale = props.sliceScale,
				ResampleMode = props.resampleMode,
				ZIndex = (props.zIndex or 1) + 1,
			}),
		}

		if props.children then
			for childName, child in props.children do
				children[childName] = child
			end
		end

		return e("Frame", rootProps, children)
	end

	local activeSlice = if hasExplicitRects
		then explicitSlices[frameIndex + 1]
		else resolveComputedFrameSlice(frameIndex, columns, fallbackFrameSize, frameOrigin, framePadding)
	local activeFrameSize = if activeSlice ~= nil then activeSlice.size else fallbackFrameSize

	local rootProps = {
		Size = props.size or UDim2.fromOffset(activeFrameSize.X, activeFrameSize.Y),
		Position = props.position or UDim2.fromScale(0, 0),
		AnchorPoint = props.anchorPoint or Vector2.new(0, 0),
		LayoutOrder = props.layoutOrder,
		Visible = props.visible ~= false,
		ZIndex = props.zIndex or 1,
		BackgroundColor3 = props.backgroundColor3,
		BackgroundTransparency = sanitizeNumber(props.backgroundTransparency, DEFAULT_BACKGROUND_TRANSPARENCY, 0, 1),
		BorderSizePixel = if props.borderSizePixel ~= nil then props.borderSizePixel else 0,
		ClipsDescendants = if props.clipsDescendants ~= nil then props.clipsDescendants else false,
		Image = props.image,
		ImageColor3 = props.imageColor3,
		ImageTransparency = sanitizeNumber(props.imageTransparency, 0, 0, 1),
		ImageRectOffset = if activeSlice ~= nil then activeSlice.offset else Vector2.zero,
		ImageRectSize = if activeSlice ~= nil then activeSlice.size else fallbackFrameSize,
		ScaleType = props.scaleType,
		SliceCenter = props.sliceCenter,
		SliceScale = props.sliceScale,
		ResampleMode = props.resampleMode,
	}

	if props.native then
		for index, value in props.native do
			(rootProps :: any)[index] = value
		end
	end

	local children: { [string]: React.ReactNode } = {}
	if props.children then
		for childName, child in props.children do
			children[childName] = child
		end
	end

	return e("ImageLabel", rootProps, children)
end

return Gif
