--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

export type MutableRefObject<T> = {
	current: T,
}

local function useLatest<T>(value: T): MutableRefObject<T>
	local ref = React.useRef(value) :: MutableRefObject<T>

	React.useEffect(function()
		ref.current = value
	end, { value })

	return ref
end

return useLatest
