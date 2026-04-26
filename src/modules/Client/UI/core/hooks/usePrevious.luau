--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local function usePrevious<T>(value: T): T?
	local ref = React.useRef(nil :: T?)
	local previousValue = ref.current

	React.useEffect(function()
		ref.current = value
	end, { value })

	return previousValue
end

return usePrevious
