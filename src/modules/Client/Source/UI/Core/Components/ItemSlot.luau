local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemIcon = require("ItemIcon")
local React: any = require(ReplicatedStorage.Packages.React)
local StackAmountLabel = require("StackAmountLabel")

export type ItemSlotProps = {
	buttonProps: { [any]: any },
	scale: number?,
	keyHintText: string?,
	keyHintProps: { [any]: any }?,
	icon: string?,
	iconProps: { [any]: any }?,
	amount: number?,
	amountText: string?,
	stackLabelProps: { [any]: any }?,
	strokeProps: { [any]: any }?,
	children: { React.ReactNode }?,
}

local e: typeof(React.createElement) = React.createElement

return function(props: ItemSlotProps): React.ReactNode
	local children: { React.ReactNode } = {}

	if props.scale ~= nil then
		children[#children + 1] = e("UIScale", {
			Scale = props.scale,
		})
	end

	if props.keyHintText ~= nil then
		local keyHintProps: { [any]: any } = props.keyHintProps or ({} :: any)
		keyHintProps.Text = props.keyHintText
		children[#children + 1] = e("TextLabel", keyHintProps)
	end

	if props.amount ~= nil or props.amountText ~= nil then
		local stackLabelProps: { [any]: any } = props.stackLabelProps or ({} :: any)
		stackLabelProps.amount = props.amount
		stackLabelProps.text = props.amountText
		children[#children + 1] = e(StackAmountLabel, stackLabelProps)
	end

	if props.icon ~= nil then
		local iconProps: { [any]: any } = props.iconProps or ({} :: any)
		iconProps.icon = props.icon
		children[#children + 1] = e(ItemIcon, iconProps)
	end

	if props.strokeProps ~= nil then
		children[#children + 1] = e("UIStroke", props.strokeProps)
	end

	if props.children ~= nil then
		for _, child in props.children do
			children[#children + 1] = child
		end
	end

	return e("ImageButton", props.buttonProps, children)
end
