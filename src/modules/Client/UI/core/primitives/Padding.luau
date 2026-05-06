--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

export type PaddingProps = {
	all: UDim?,
	top: UDim?,
	bottom: UDim?,
	left: UDim?,
	right: UDim?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: PaddingProps): React.ReactNode
	local all = props.all
	return e("UIPadding", {
		PaddingTop = props.top or all,
		PaddingBottom = props.bottom or all,
		PaddingLeft = props.left or all,
		PaddingRight = props.right or all,
	})
end
