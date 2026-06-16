local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Buff = require("Buff")
local React = require(ReplicatedStorage.Packages.React)
local Table = require("Table")

export type BuffScreenProps = {
	records: { any }?,
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	size: UDim2?,
	iconSize: number?,
	padding: UDim2?,
	DebugInnerBounds: boolean?,
	debugInnerBounds: boolean?,
	native: { [any]: any }?,
}

local e: typeof(React.createElement) = React.createElement

local DEFAULT_ICON_SIZE = 50
local DEFAULT_CELL_HEIGHT = 74
local SLOT_REFERENCE_WIDTH = 168
local SLOT_REFERENCE_HEIGHT = 180

local function getRecordLayoutOrder(recordRaw: any, fallbackIndex: number): number
	if typeof(recordRaw) ~= "table" then
		return fallbackIndex
	end

	local record = recordRaw :: { [string]: any }
	if record.kind == "Debuff" then
		return fallbackIndex
	end

	return fallbackIndex + 1000
end

return function(props: BuffScreenProps): React.ReactNode
	local iconSize = props.iconSize or DEFAULT_ICON_SIZE
	local slotHeight = math.ceil(iconSize * (SLOT_REFERENCE_HEIGHT / SLOT_REFERENCE_WIDTH))
	local cellHeight = slotHeight + 20
	local records = if props.records ~= nil then Table.copy(props.records) else {}
	local children: { React.ReactNode } = {
		e("UIGridLayout", {
			CellPadding = props.padding or UDim2.fromOffset(8, 8),
			CellSize = UDim2.fromOffset(iconSize, math.max(DEFAULT_CELL_HEIGHT, cellHeight)),
			FillDirection = Enum.FillDirection.Horizontal,
			FillDirectionMaxCells = 3,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Top,
		}),
	}

	for index, record in records do
		children[#children + 1] = e(Buff, {
			record = record,
			layoutOrder = getRecordLayoutOrder(record, index),
			iconSize = iconSize,
			zIndex = (props.zIndex or 20) + 1,
			DebugInnerBounds = props.DebugInnerBounds,
			debugInnerBounds = props.debugInnerBounds,
		})
	end

	local frameProps = if props.native ~= nil then Table.copy(props.native) else {}
	frameProps.Size = frameProps.Size or props.size or UDim2.fromScale(1, 1)
	frameProps.BackgroundTransparency = frameProps.BackgroundTransparency or 1
	frameProps.BorderSizePixel = frameProps.BorderSizePixel or 0
	frameProps.LayoutOrder = frameProps.LayoutOrder or props.layoutOrder or 1
	frameProps.Visible = if frameProps.Visible ~= nil then frameProps.Visible else props.visible ~= false
	frameProps.ZIndex = frameProps.ZIndex or props.zIndex or 20

	return e("Frame", frameProps, children)
end
