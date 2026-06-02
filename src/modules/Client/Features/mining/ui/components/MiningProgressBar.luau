--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local gameRoot = assert(script:FindFirstAncestor("game"), "Missing Nevermore game root.")

local ProgressBar = require(gameRoot.Client.UI.core.components.ProgressBar)
local React = require(ReplicatedStorage.Packages.React)

export type MiningProgressBarProps = {
	progress: number,
	frameImage: string,
	barImage: string,
	frameWidth: number,
	frameHeight: number,
	barWidth: number,
	barHeight: number,
	barInsetX: number,
	barInsetY: number,
	zIndex: number,
}

return function(props: MiningProgressBarProps): React.ReactNode
	local progressWidth = math.floor((props.barWidth * math.clamp(props.progress, 0, 1)) + 0.5)

	return React.createElement(ProgressBar, {
		progress = props.progress,
		size = UDim2.fromOffset(props.frameWidth, props.frameHeight),
		trackImage = props.frameImage,
		fillImage = props.barImage,
		zIndex = props.zIndex + 2,
		fillInset = Vector2.new(props.barInsetX, props.barInsetY),
		fillSize = UDim2.fromOffset(progressWidth, props.barHeight),
		nativeFillClip = {
			ZIndex = props.zIndex + 1,
		},
		nativeFill = {
			Size = UDim2.fromOffset(props.barWidth, props.barHeight),
			ZIndex = props.zIndex + 1,
		},
	})
end
