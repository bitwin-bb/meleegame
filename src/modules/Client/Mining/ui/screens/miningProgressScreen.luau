local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")


local BillboardCard = require("BillboardCard")
local ImageIds = require("ImageIds")
local MiningProgressBar = require("MiningProgressBar")
local React = require(ReplicatedStorage.Packages.React)
local miningProgressSlice = require("miningProgressSlice")
local miningProgressThunks = require("miningProgressThunks")
local useProgressBarSmoothing = require("useProgressBarSmoothing")
local useStore = require("useCoreStore")

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
	local resolvedProps: MiningProgressScreenProps = if props ~= nil then props else {} :: any
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

	return e(BillboardCard, {
		enabled = isVisible,
		alwaysOnTop = true,
		lightInfluence = 0,
		maxDistance = 140,
		size = UDim2.fromOffset(FRAME_WIDTH, FRAME_HEIGHT),
		studsOffset = Vector3.zero,
		studsOffsetWorldSpace = Vector3.zero,
		zIndexBehavior = Enum.ZIndexBehavior.Sibling,
		billboardKey = "Mining",
		cardVisible = false,
		nativeBillboard = {
			ref = billboardRef,
			ResetOnSpawn = false,
		},
	}, {
		e(MiningProgressBar, {
			progress = progressScale,
			frameImage = FRAME_IMAGE_ID,
			barImage = BAR_IMAGE_ID,
			frameWidth = FRAME_WIDTH,
			frameHeight = FRAME_HEIGHT,
			barWidth = BAR_WIDTH,
			barHeight = BAR_HEIGHT,
			barInsetX = BAR_INSET_X,
			barInsetY = BAR_INSET_Y,
			zIndex = zIndex,
		}),
	})
end
