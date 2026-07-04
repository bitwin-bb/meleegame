local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React: any = require(ReplicatedStorage.Packages.React)
local Table: any = require("Table")
local useTimer = require("useTimer")

export type CooldownEffectOptions = {
	record: any,
	zIndex: number?,
	transparency: number?,
	native: { [any]: any }?,
}

local e: typeof(React.createElement) = React.createElement

local function CoerceTransparency(valueRaw: any): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return 0.35
	end

	return math.clamp(valueRaw, 0, 1)
end

local function useCooldownEffect(options: CooldownEffectOptions): React.ReactNode
	local timer = useTimer(options.record)
	if timer.isInfinite or timer.progress <= 0 then
		return nil
	end

	local native = if options.native ~= nil then Table.copy(options.native) else {}
	native.AnchorPoint = native.AnchorPoint or Vector2.new(0.5, 1)
	native.Position = native.Position or UDim2.fromScale(0.5, 1)
	native.Size = native.Size or UDim2.fromScale(1, timer.progress)
	native.BackgroundColor3 = native.BackgroundColor3 or Color3.fromRGB(0, 0, 0)
	native.BackgroundTransparency = if native.BackgroundTransparency ~= nil
		then native.BackgroundTransparency
		else CoerceTransparency(options.transparency)
	native.BorderSizePixel = native.BorderSizePixel or 0
	native.ZIndex = native.ZIndex or (options.zIndex or 1)

	return e("Frame", native)
end

return useCooldownEffect
