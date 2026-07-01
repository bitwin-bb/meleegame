local require = require(script.Parent.loader).load(script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Flipbook = require("Flipbook")
local FlipbookPlayer = require("FlipbookPlayer")
local Maid = require("Maid")

local React = require(ReplicatedStorage.Packages.React)

export type BreakAnimOptions = {
	image: string,
	frameIndex: number,
	columns: number,
	rows: number,
	frameSize: Vector2,
}

local function CoerceInteger(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return fallback
	end
	return math.clamp(math.floor(valueRaw), minimum, maximum)
end

local function useBreakAnim(imageRef: { current: ImageLabel? }, options: BreakAnimOptions)
	local image = if typeof(options.image) == "string" then options.image else ""
	local columns = CoerceInteger(options.columns, 1, 1, 128)
	local rows = CoerceInteger(options.rows, 1, 1, 128)
	local frameCount = math.max(1, columns * rows)
	local frameIndex = CoerceInteger(options.frameIndex, 1, 1, frameCount)
	local frameSize = if typeof(options.frameSize) == "Vector2" then options.frameSize else Vector2.new(1, 1)

	React.useEffect(
		function()
			local imageLabel = imageRef.current
			if imageLabel == nil or image == "" then
				return
			end

			local maid = Maid.new()
			local flipbook = Flipbook.new({
				image = image,
				frameCount = frameCount,
				rows = rows,
				columns = columns,
				imageRectSize = frameSize,
				frameRate = 60,
				restFrame = frameIndex,
			})
			local player = FlipbookPlayer.new(imageLabel)
			maid:GiveTask(player)
			player:SetFlipbook(flipbook)
			player:Stop()

			return function()
				maid:DoCleaning()
			end
		end,
		{
			imageRef,
			image,
			frameIndex,
			columns,
			rows,
			frameCount,
			frameSize.X,
			frameSize.Y,
		} :: { any }
	)
end

return useBreakAnim
