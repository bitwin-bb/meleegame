--!strict

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")
local packageRoot = assert(gameRoot.Parent, "Missing AquariaBackup package root.")
local quentyPackages = assert(packageRoot.node_modules:FindFirstChild("@quenty"), "Missing @quenty packages.")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Flipbook = require(quentyPackages.flipbook.Client.Flipbook)
local FlipbookPlayer = require(quentyPackages.flipbook.Client.Player.FlipbookPlayer)
local Maid = require(quentyPackages.maid.Shared.Maid)

local React = require(ReplicatedStorage.Packages.React)
local ServantSpriteSheet = require(gameRoot.Shared.Features.npc.modules.ServantSpriteSheet)

export type EyeOfCthulhuServantProps = {
	zIndex: number?,
}

local e: typeof(React.createElement) = React.createElement

local FRAME_COUNT = math.max(1, ServantSpriteSheet.frameCount or (ServantSpriteSheet.columns * ServantSpriteSheet.rows))

local function createFlipbook(): any
	return Flipbook.new({
		image = ServantSpriteSheet.image,
		frameCount = FRAME_COUNT,
		rows = ServantSpriteSheet.rows,
		columns = ServantSpriteSheet.columns,
		imageRectSize = ServantSpriteSheet.frameSize,
		frameRate = ServantSpriteSheet.frameRate,
		restFrame = 1,
	})
end

return function(props: EyeOfCthulhuServantProps): React.ReactNode
	local imageRef = React.useRef(nil :: ImageLabel?)

	React.useEffect(
		function()
			local imageLabel = imageRef.current
			if imageLabel == nil then
				return
			end

			local maid = Maid.new()
			local player = FlipbookPlayer.new(imageLabel)
			maid:GiveTask(player)
			player:SetFlipbook(createFlipbook())
			player:Play()

			return function()
				maid:DoCleaning()
			end
		end,
		{
			ServantSpriteSheet.image,
			ServantSpriteSheet.frameSize.X,
			ServantSpriteSheet.frameSize.Y,
			ServantSpriteSheet.rows,
			ServantSpriteSheet.columns,
			FRAME_COUNT,
			ServantSpriteSheet.frameRate,
		} :: { any }
	)

	return e("ImageLabel", {
		ref = imageRef,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = ServantSpriteSheet.image,
		ImageRectOffset = Vector2.zero,
		ImageRectSize = ServantSpriteSheet.frameSize,
		Position = UDim2.fromScale(0.5, 0.5),
		ResampleMode = Enum.ResamplerMode.Pixelated,
		ScaleType = Enum.ScaleType.Stretch,
		Size = UDim2.fromScale(1, 1),
		ZIndex = props.zIndex or 1,
	}, {
		e("UIAspectRatioConstraint", {
			AspectRatio = ServantSpriteSheet.frameSize.X / math.max(1, ServantSpriteSheet.frameSize.Y),
			DominantAxis = Enum.DominantAxis.Height,
		}),
	})
end
