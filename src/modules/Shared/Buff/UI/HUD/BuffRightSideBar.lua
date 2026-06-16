local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuffScreen = require("BuffScreen")
local React = require(ReplicatedStorage.Packages.React)
local Responsive = require("useViewportScale")
local Table = require("Table")

export type BuffRightSideBarProps = {
	records: { any }?,
	useServiceState: boolean?,
	layoutOrder: number?,
	visible: boolean?,
	zIndex: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	iconSize: number?,
	DebugInnerBounds: boolean?,
	debugInnerBounds: boolean?,
	native: { [any]: any }?,
}

local e: typeof(React.createElement) = React.createElement

local DEFAULT_CONTAINER_HEIGHT = 150

return function(props: BuffRightSideBarProps): React.ReactNode
	local responsive = Responsive.useResponsiveMetrics()
	local meterTokens = responsive.tokens.meter
	local iconSize = props.iconSize or math.clamp(meterTokens.segmentSize + 14, 42, 54)
	local frameProps = if props.native ~= nil then Table.copy(props.native) else {}

	frameProps.Name = frameProps.Name or "Buffs"
	frameProps.Size = frameProps.Size
		or props.size
		or UDim2.fromOffset(meterTokens.frameWidth, DEFAULT_CONTAINER_HEIGHT)
	frameProps.Position = frameProps.Position or props.position or UDim2.fromScale(1, 0)
	frameProps.AnchorPoint = frameProps.AnchorPoint or props.anchorPoint or Vector2.new(1, 0)
	frameProps.BackgroundTransparency = frameProps.BackgroundTransparency or 1
	frameProps.BorderSizePixel = frameProps.BorderSizePixel or 0
	frameProps.LayoutOrder = frameProps.LayoutOrder or props.layoutOrder or 8
	frameProps.Visible = if frameProps.Visible ~= nil then frameProps.Visible else props.visible ~= false
	frameProps.ZIndex = frameProps.ZIndex or props.zIndex or 20

	return e("Frame", frameProps, {
		e(BuffScreen, {
			records = props.records,
			size = UDim2.fromScale(1, 1),
			iconSize = iconSize,
			zIndex = (props.zIndex or 20) + 1,
			DebugInnerBounds = props.DebugInnerBounds,
			debugInnerBounds = props.debugInnerBounds,
		}),
	})
end
