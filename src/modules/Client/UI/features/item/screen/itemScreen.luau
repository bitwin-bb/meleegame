--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local Charm = require(ReplicatedStorage.Packages.Charm)
local PortalTargets = require(script:FindFirstAncestor("game").Client.UI.core.utils.PortalTargets)
local itemSlice = require(script:FindFirstAncestor("game").Client.UI.features.item.state.itemSlice)

type ItemDragState = itemSlice.ItemDragState

type ItemScreenProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

local e: typeof(React.createElement) = React.createElement

local function resolveDragState(): ItemDragState
	return itemSlice.getDragState()
end

return function(props: ItemScreenProps): React.ReactNode
	local dragState, setDragState = React.useState(resolveDragState)

	React.useEffect(function()
		local unsubscribeDrag = Charm.subscribe(itemSlice.dragStateAtom, function(nextState: ItemDragState)
			setDragState(nextState)
		end, {
			inclusive = true,
		})

		return function()
			unsubscribeDrag()
		end
	end, {})

	if props.visible == false then
		return nil
	end

	if not dragState.active then
		return nil
	end

	local stack = dragState.stack
	local icon = dragState.icon
	local zIndex = props.zIndex or 130
	local pointer = dragState.pointerPosition
	local iconSize = 46

	local children: { [string]: React.ReactNode } = {}

	if dragState.active and stack ~= nil and icon ~= nil then
		children.GhostIcon = e("ImageLabel", {
			Name = "GhostIcon",
			Size = UDim2.fromOffset(iconSize, iconSize),
			Position = UDim2.fromOffset(pointer.X, pointer.Y),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = icon,
			ImageTransparency = 0,
			ZIndex = zIndex + 1,
		}, {
			GhostAmount = if stack.amount > 1
				then e("TextLabel", {
					Name = "Amount",
					Size = UDim2.fromOffset(0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					Position = UDim2.new(1, -2, 1, -1),
					AnchorPoint = Vector2.new(1, 1),
					BackgroundTransparency = 1,
					Text = tostring(stack.amount),
					Font = Enum.Font.GothamBold,
					TextSize = 12,
					TextColor3 = Color3.fromRGB(255, 255, 255),
					TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
					TextStrokeTransparency = 0.35,
					ZIndex = zIndex + 2,
				})
				else nil,
		})
	end

	local rootElement = e("Frame", {
		Name = "ItemDragLayer",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 20,
		ZIndex = zIndex,
		Active = false,
		Selectable = false,
	}, children)

	local portalTarget = PortalTargets.resolveUiScreenGui()
	if portalTarget ~= nil then
		return ReactRoblox.createPortal(rootElement, portalTarget)
	end

	return rootElement
end
