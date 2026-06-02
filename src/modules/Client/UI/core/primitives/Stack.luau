--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

export type StackProps = {
	fillDirection: Enum.FillDirection?,
	horizontalAlignment: Enum.HorizontalAlignment?,
	verticalAlignment: Enum.VerticalAlignment?,
	sortOrder: Enum.SortOrder?,
	padding: UDim?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: StackProps): React.ReactNode
	return e("UIListLayout", {
		FillDirection = props.fillDirection,
		HorizontalAlignment = props.horizontalAlignment,
		VerticalAlignment = props.verticalAlignment,
		SortOrder = props.sortOrder,
		Padding = props.padding,
	})
end
