--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

export type StackAmountLabelProps = {
	amount: number?,
	text: string?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	font: Enum.Font?,
	textSize: number?,
	textColor3: Color3?,
	textStrokeColor3: Color3?,
	textTransparency: number?,
	textStrokeTransparency: number?,
	textXAlignment: Enum.TextXAlignment?,
	textYAlignment: Enum.TextYAlignment?,
	automaticSize: Enum.AutomaticSize?,
	native: { [any]: any }?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: StackAmountLabelProps): React.ReactNode
	local labelText = props.text
	if labelText == nil and props.amount ~= nil then
		labelText = tostring(props.amount)
	end

	local labelProps: { [any]: any } = {
		Size = props.size or UDim2.fromOffset(0, 0),
		AutomaticSize = props.automaticSize or Enum.AutomaticSize.XY,
		Position = props.position or UDim2.new(1, -6, 1, -5),
		AnchorPoint = props.anchorPoint or Vector2.new(1, 1),
		LayoutOrder = props.layoutOrder,
		Visible = props.visible,
		BackgroundTransparency = 1,
		Text = labelText or "",
		Font = props.font or Enum.Font.GothamBold,
		TextSize = props.textSize or 13,
		TextColor3 = props.textColor3 or Color3.fromRGB(248, 253, 255),
		TextStrokeColor3 = props.textStrokeColor3 or Color3.fromRGB(0, 0, 0),
		TextTransparency = props.textTransparency,
		TextStrokeTransparency = if props.textStrokeTransparency ~= nil then props.textStrokeTransparency else 0.3,
		TextXAlignment = props.textXAlignment or Enum.TextXAlignment.Right,
		TextYAlignment = props.textYAlignment or Enum.TextYAlignment.Bottom,
		ZIndex = props.zIndex,
	}

	if props.native ~= nil then
		for key, value in props.native do
			labelProps[key] = value
		end
	end

	return e("TextLabel", labelProps)
end
