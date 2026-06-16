local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

export type GridProps = {
	cellSize: UDim2?,
	cellPadding: UDim2?,
	fillDirection: Enum.FillDirection?,
	fillDirectionMaxCells: number?,
	horizontalAlignment: Enum.HorizontalAlignment?,
	verticalAlignment: Enum.VerticalAlignment?,
	sortOrder: Enum.SortOrder?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: GridProps): React.ReactNode
	return e("UIGridLayout", {
		CellSize = props.cellSize,
		CellPadding = props.cellPadding,
		FillDirection = props.fillDirection,
		FillDirectionMaxCells = props.fillDirectionMaxCells,
		HorizontalAlignment = props.horizontalAlignment,
		VerticalAlignment = props.verticalAlignment,
		SortOrder = props.sortOrder,
	})
end
