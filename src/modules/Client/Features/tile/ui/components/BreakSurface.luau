--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packageRoot = script:FindFirstAncestor("game").Parent
local loaderUtils = assert(packageRoot:FindFirstChild("LoaderUtils", true), "Missing LoaderUtils")
local loader = require(loaderUtils.Parent).load(packageRoot)

local Flipbook = loader("Flipbook")
local FlipbookPlayer = loader("FlipbookPlayer")
local Maid = loader("Maid")
local React = require(ReplicatedStorage.Packages.React)

local tileSlice = require(script:FindFirstAncestor("tile").tileSlice)
local useBreakAnim = require(script.Parent.Parent.hooks.useBreakAnim)

type BreakState = tileSlice.BreakState
type ShinySpeckState = tileSlice.ShinySpeckState

export type BreakProps = {
	state: BreakState,
	shinySpecks: { [string]: ShinySpeckState }?,
}

local e: typeof(React.createElement) = React.createElement

local SHINY_SURFACE_PIXELS_PER_STUD = 32
local SHINY_BRIGHTNESS = 4

local function BreakImage(props: BreakProps): React.ReactNode
	local state = props.state
	local imageRef = React.useRef(nil :: ImageLabel?)
	useBreakAnim(imageRef, {
		image = state.image,
		frameIndex = state.frameIndex,
		columns = state.columns,
		rows = state.rows,
		frameSize = state.frameSize,
	})

	return e("ImageLabel", {
		ref = imageRef,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = state.imagePosition,
		Size = state.imageSize,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = state.image,
		ImageTransparency = state.transparency,
		ResampleMode = Enum.ResamplerMode.Pixelated,
		ScaleType = Enum.ScaleType.Fit,
	})
end

local function ShinySpeck(props: { speck: ShinySpeckState }): React.ReactNode
	local speck = props.speck
	local imageRef = React.useRef(nil :: ImageLabel?)

	React.useEffect(function()
		local imageLabel = imageRef.current
		if imageLabel == nil or speck.image == "" then
			return
		end

		local maid = Maid.new()
		local flipbook = Flipbook.new({
			image = speck.image,
			frameCount = math.max(1, speck.columns * speck.rows),
			rows = speck.rows,
			columns = speck.columns,
			imageRectSize = speck.frameSize,
			frameRate = speck.frameRate,
			restFrame = 1,
		})
		local player = FlipbookPlayer.new(imageLabel)
		maid:GiveTask(player)
		player:SetFlipbook(flipbook)
		player:PromisePlayRepeat(1)

		return function()
			maid:DoCleaning()
		end
	end, {
		speck.id,
		speck.image,
		speck.columns,
		speck.rows,
		speck.frameSize.X,
		speck.frameSize.Y,
		speck.frameRate,
	})

	return e("SurfaceGui", {
		Adornee = speck.adornee,
		AlwaysOnTop = false,
		Brightness = SHINY_BRIGHTNESS,
		Enabled = speck.adornee ~= nil and speck.image ~= "",
		Face = speck.face,
		LightInfluence = 0,
		PixelsPerStud = SHINY_SURFACE_PIXELS_PER_STUD,
		ResetOnSpawn = false,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		e("ImageLabel", {
			ref = imageRef,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = speck.position,
			Size = speck.size,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = speck.image,
			ImageColor3 = Color3.new(1, 1, 1),
			ImageRectOffset = Vector2.zero,
			ImageRectSize = speck.frameSize,
			ImageTransparency = 0,
			ResampleMode = Enum.ResamplerMode.Pixelated,
			ScaleType = Enum.ScaleType.Stretch,
			ZIndex = 10,
		}),
	})
end

local function TileBreakSurface(props: BreakProps): React.ReactNode
	local state = props.state
	return e("SurfaceGui", {
		Adornee = state.adornee,
		AlwaysOnTop = false,
		Brightness = 1,
		CanvasSize = state.canvasSize,
		Enabled = state.visible and state.adornee ~= nil and state.image ~= "",
		Face = state.face,
		LightInfluence = 0,
		ResetOnSpawn = false,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		Crack = e(BreakImage, {
			state = state,
		}),
	})
end

return function(props: BreakProps): React.ReactNode
	local children = {
		Break = e(TileBreakSurface, {
			state = props.state,
		}),
	} :: { [any]: React.ReactNode }

	for _, speck in props.shinySpecks or {} do
		children[#children + 1] = e(ShinySpeck, {
			speck = speck,
		})
	end

	return e(React.Fragment, nil, children)
end
