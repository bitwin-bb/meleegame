--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local function useLast<T>(value: T, initialValue: T?): T?
	local ref = React.useRef(initialValue)
	local previousValue = ref.current

	React.useEffect(function()
		ref.current = value
	end, { value })

	return previousValue
end

return useLast
