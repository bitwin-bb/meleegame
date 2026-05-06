--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

export type ScaleProps = {
	scale: number?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: ScaleProps): React.ReactNode
	return e("UIScale", {
		Scale = props.scale,
	})
end
