--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ImageIds = require(script:FindFirstAncestor("game").Client.UI.core.ImageIds)
local React = require(ReplicatedStorage.Packages.React)
local miningProgressSlice =
	require(script:FindFirstAncestor("game").Client.UI.features.mining.state.miningProgressSlice)
local miningProgressThunks =
	require(script:FindFirstAncestor("game").Client.UI.features.mining.state.miningProgressThunks)
local useProgressBarSmoothing =
	require(script:FindFirstAncestor("game").Client.UI.features.mining.hooks.useProgressBarSmoothing)
local useStore = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useStore)

type MiningProgressState = miningProgressSlice.MiningProgressState

type MiningProgressScreenProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

local e: typeof(React.createElement) = React.createElement

local FRAME_IMAGE_ID = if typeof(ImageIds.miningProgressFrame) == "string" then ImageIds.miningProgressFrame else ""
local BAR_IMAGE_ID = if typeof(ImageIds.miningProgressBar) == "string" then ImageIds.miningProgressBar else ""
local DISPLAY_SCALE = 0.2
local BASE_FRAME_WIDTH = 270
local BASE_FRAME_HEIGHT = 30
local BASE_INSET_X = 3
local BASE_INSET_Y = 3

local function scalePixels(value: number): number
	return math.max(1, math.floor((value * DISPLAY_SCALE) + 0.5))
end

local FRAME_WIDTH = scalePixels(BASE_FRAME_WIDTH)
local FRAME_HEIGHT = scalePixels(BASE_FRAME_HEIGHT)
local BAR_INSET_X = scalePixels(BASE_INSET_X)
local BAR_INSET_Y = scalePixels(BASE_INSET_Y)
local BAR_WIDTH = math.max(1, FRAME_WIDTH - (BAR_INSET_X * 2))
local BAR_HEIGHT = math.max(1, FRAME_HEIGHT - (BAR_INSET_Y * 2))

return function(props: MiningProgressScreenProps?): React.ReactNode
	local resolvedProps: MiningProgressScreenProps = if props ~= nil then props else {}
	local miningProgressState = (useStore(miningProgressSlice.miningProgressStateAtom) :: MiningProgressState?)
		or miningProgressSlice.miningProgressStateAtom()
	local billboardRef = React.useRef(nil :: BillboardGui?)

	React.useEffect(function()
		local stop = miningProgressThunks.start()

		return function()
			stop()
		end
	end, {})

	React.useEffect(function()
		miningProgressThunks.bindBillboardGui(billboardRef.current)
		return function()
			miningProgressThunks.bindBillboardGui(nil)
		end
	end, {})

	if resolvedProps.visible == false then
		return nil
	end

	local zIndex = resolvedProps.zIndex or 170
	local isVisible = miningProgressState.visible == true
	local progressScale = useProgressBarSmoothing({
		progress = miningProgressState.progress,
		visible = isVisible,
		gainRate = 28,
		depletionRate = 7,
	})
	local progressWidth = math.floor((BAR_WIDTH * progressScale) + 0.5)

	return e("BillboardGui", {
		ref = billboardRef,
		Enabled = isVisible,
		AlwaysOnTop = true,
		ResetOnSpawn = false,
		LightInfluence = 0,
		MaxDistance = 140,
		Size = UDim2.fromOffset(FRAME_WIDTH, FRAME_HEIGHT),
		StudsOffsetWorldSpace = Vector3.new(0, 0, 0),
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		FrameImage = e("ImageLabel", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = FRAME_IMAGE_ID,
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromScale(0, 0),
			ZIndex = zIndex + 2,
		}, {
			BarClip = e("Frame", {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				Position = UDim2.fromOffset(BAR_INSET_X, BAR_INSET_Y),
				Size = UDim2.fromOffset(progressWidth, BAR_HEIGHT),
				ZIndex = zIndex + 1,
			}, {
				BarImage = e("ImageLabel", {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Image = BAR_IMAGE_ID,
					Position = UDim2.fromOffset(0, 0),
					Size = UDim2.fromOffset(BAR_WIDTH, BAR_HEIGHT),
					ZIndex = zIndex + 1,
				}),
			}),
		}),
	})
end
