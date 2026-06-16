local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local e: typeof(React.createElement) = React.createElement

export type InventoryGridProps = {
	size: UDim2,
	position: UDim2,
	anchorPoint: Vector2,
	zIndex: number,
	showRevealOverlay: boolean,
	revealOverlayZIndex: number,
	children: { React.ReactNode },
	extraChildren: { React.ReactNode }?,
}

return function(props: InventoryGridProps): React.ReactNode
	local children: { React.ReactNode } = {
		e("Frame", {
			Size = props.size,
			Position = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = props.zIndex + 1,
		}, props.children),
	}

	if props.showRevealOverlay then
		children[#children + 1] = e("Frame", {
			Size = props.size,
			Position = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = props.revealOverlayZIndex,
			Active = true,
			Selectable = true,
		})
	end

	if props.extraChildren ~= nil then
		for _, child in props.extraChildren do
			children[#children + 1] = child
		end
	end

	return e("Frame", {
		Size = props.size,
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = props.zIndex,
	}, children)
end
