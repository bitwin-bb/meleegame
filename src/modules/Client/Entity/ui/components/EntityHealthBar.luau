local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

export type EntityHealthBarProps = {
	healthSize: any,
	healthColor: any,
	trackTransparency: number?,
	zIndex: number,
}

local e: typeof(React.createElement) = React.createElement

return function(props: EntityHealthBarProps): React.ReactNode
	return e("Frame", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = Color3.fromRGB(35, 41, 55),
		BackgroundTransparency = props.trackTransparency or 0.06,
		BorderSizePixel = 0,
		ZIndex = props.zIndex,
	}, {
		e("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}),
		e("Frame", {
			Size = props.healthSize,
			BackgroundColor3 = props.healthColor,
			BorderSizePixel = 0,
			ZIndex = props.zIndex + 1,
		}, {
			e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			e("UIGradient", {
				Color = props.healthColor:map(function(color: Color3)
					return ColorSequence.new({
						ColorSequenceKeypoint.new(0, color:Lerp(Color3.fromRGB(255, 255, 255), 0.35)),
						ColorSequenceKeypoint.new(1, color),
					})
				end),
			}),
		}),
	})
end
