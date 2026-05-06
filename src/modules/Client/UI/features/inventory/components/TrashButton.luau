--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ImageIds = require(script:FindFirstAncestor("game").Client.UI.core.ImageIds)
local React = require(ReplicatedStorage.Packages.React)

export type TrashButtonProps = {
	size: UDim2,
	position: UDim2,
	anchorPoint: Vector2,
	layoutOrder: number,
	zIndex: number,
	isOpen: boolean,
	imageColor3: Color3,
	imageTransparency: number,
	active: boolean,
	selectable: boolean,
	onMouseEnter: (() -> ())?,
	onMouseLeave: (() -> ())?,
	onInputBegan: ((GuiObject, InputObject) -> ())?,
	onActivated: (() -> ())?,
}

return function(props: TrashButtonProps): React.ReactNode
	return React.createElement("ImageButton", {
		Size = props.size,
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = if props.isOpen then ImageIds.trashCanOpen else ImageIds.trashCanClosed,
		ImageColor3 = props.imageColor3,
		ImageTransparency = props.imageTransparency,
		ZIndex = props.zIndex,
		AutoButtonColor = false,
		Active = props.active,
		Selectable = props.selectable,
		[React.Event.MouseEnter] = props.onMouseEnter,
		[React.Event.MouseLeave] = props.onMouseLeave,
		[React.Event.InputBegan] = props.onInputBegan,
		[React.Event.Activated] = props.onActivated,
	})
end
